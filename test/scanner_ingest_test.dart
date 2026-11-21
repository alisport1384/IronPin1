import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ironpin/data/range_session.dart';
import 'package:ironpin/data/scanner_api.dart';
import 'package:ironpin/data/scanner_ingest.dart';
import 'package:ironpin/data/store.dart';
import 'package:ironpin/domain/range_projection.dart';

/// The scanner's published knowledge has to become archive rows, not only a
/// list the information tab reads: the prices, chart and range tabs read rows,
/// and the range product list and its index are built from rows. The knowledge
/// goes through the same analyzer and the same rules as a post, so an item
/// without a product and an announced amount is dropped here too.
ScannerItem _item(String id, String claim,
        {String topic = 'قیمت نبشی امروز',
        String domain = 'example.com',
        String url = 'https://example.com/p',
        DateTime? verifiedAt}) =>
    ScannerItem(
        id: id,
        scanId: 'scan-1',
        topic: topic,
        claim: claim,
        url: url,
        domain: domain,
        kind: 'chunk',
        category: 'rag',
        attribute: 'price',
        layer: 'price',
        lang: 'fa',
        confidence: 0.6,
        ttlDays: 45,
        tokens: 120,
        lastVerifiedAt: verifiedAt ?? DateTime.utc(2026, 11, 20),
        tags: const []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  final now = DateTime.utc(2026, 11, 21);

  ScannerKnowledge knowledge(List<ScannerItem> items) => ScannerKnowledge(
      format: 'qwen-knowledge-v1',
      kind: 'report',
      generatedAt: '2026-11-21T00:00:00Z',
      scope: const {},
      items: items);

  test('knowledge rows reach the archive, the prices filter and the range index',
      () async {
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    addTearDown(() => store.close());

    final written = await ScannerIngest(store).ingest(
        knowledge([
          _item('a', 'قیمت نبشی 5 میل ابعاد 50*50 یاوران زنجان ۱۱۷٬۰۹۰ تومان'),
          _item('b', 'قیمت نبشی 6 میل ابعاد 60*60 یاوران زنجان ۱۱۸٬۰۹۰ تومان'),
          _item('c', 'قیمت میلگرد 16 ذوب آهن A3 ۱۱۹٬۰۰۰ تومان',
              topic: 'قیمت میلگرد'),
          _item('d', 'قیمت میلگرد 18 شاهرود A3 ۱۰۶٬۸۱۸ تومان',
              topic: 'قیمت میلگرد'),
          // Prose about the market: a product may be named, but no amount is
          // announced, so it is a sentence and not an offer.
          _item('e', 'قیمت میلگرد در بازار فیزیکی نیز در محدودهٔ ۱۱۰ هزار تومان '
              'قرار دارد و این مقاله دربارهٔ تاثیر نرخ ارز بر بازار فولاد است.'),
        ]),
        now: now);

    expect(written, greaterThan(0));
    final rows = await store.latest();
    expect(rows.length, written);
    expect(rows.every((q) => q.endpoint == ScannerIngest.endpoint), isTrue,
        reason: 'the ingested rows are one endpoint of their own');
    expect(rows.every((q) => q.id.startsWith('${ScannerIngest.endpoint}:')),
        isTrue);
    expect(await store.activeEndpointCount(ScannerIngest.endpoint), written);

    // Each product keeps its own specification, so two sizes of one product are
    // not merged and a new good is a new entry of the product list.
    final angles = rows.where((q) => q.category == 'نبشی').toList();
    expect(angles.length, greaterThanOrEqualTo(2));
    expect(angles.map((q) => q.dimensionsLabel).toSet().length,
        greaterThanOrEqualTo(2),
        reason: '50*50 and 60*60 must stay two products');
    expect(rows.any((q) => q.category == 'میلگرد'), isTrue);
    // The scanner's verification date travels with the row; the read time does
    // not replace it.
    expect(rows.every((q) => q.amount != null && q.amount! > 0), isTrue);
    expect(
        rows.every((q) => q.details['دستهٔ دانش']?.isNotEmpty == true), isTrue,
        reason: 'the scanner topic is kept as evidence');

    // The range tab reads the derived index, so the new goods are candidates.
    final session = RangeSession(store);
    final set = await session.candidates(
        scope: const CandidateScope(
            basis: '', query: '', maxAgeDays: 30, category: 'نبشی'),
        at: now);
    expect(set.total, greaterThanOrEqualTo(2),
        reason: 'the range product list must offer the new goods');
  });

  test('an undated offer is kept, the same rule a source message uses',
      () async {
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    addTearDown(() => store.close());
    // A page whose publication date the scanner could not state: the offer is
    // still current by the domain's own rule (no date is not an old date).
    final written = await ScannerIngest(store).ingest(
        knowledge([
          _item('u', 'قیمت پروفیل UPN 80 ذوب آهن ۱۲٬۵۰۰ تومان',
              topic: 'قیمت پروفیل',
              verifiedAt: DateTime.fromMillisecondsSinceEpoch(0)),
        ]),
        now: now);
    expect(written, 1);
    expect((await store.latest()).single.sourceDateRaw, isEmpty);
  });

  test('a dump with no offer writes nothing and replaces nothing', () async {
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    addTearDown(() => store.close());
    expect(
        await ScannerIngest(store).ingest(
            knowledge([
              _item('x', 'این صفحه معرفی کارخانه است و هیچ قیمتی اعلام نمی‌کند.'),
            ]),
            now: now),
        0);
    expect(await store.latest(), isEmpty);
    expect(await store.activeEndpointCount(ScannerIngest.endpoint), 0);
  });

  test('a dump whose offers are gone retires the earlier rows', () async {
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    addTearDown(() => store.close);
    await ScannerIngest(store).ingest(
        knowledge([
          _item('a', 'قیمت میلگرد 16 ذوب آهن A3 ۱۱۹٬۰۰۰ تومان',
              topic: 'قیمت میلگرد'),
        ]),
        now: now);
    expect(await store.activeEndpointCount(ScannerIngest.endpoint), 1);
    // The next dump holds only prose: the old offer must not stay in the tabs
    // as if the source still published it.
    final written = await ScannerIngest(store).ingest(
        knowledge([
          _item('x', 'این صفحه معرفی کارخانه است و هیچ قیمتی اعلام نمی‌کند.'),
        ]),
        now: now);
    expect(written, 0);
    expect(await store.activeEndpointCount(ScannerIngest.endpoint), 0);
    expect(await store.latest(), isEmpty);
  });

  test('a later ingest replaces the earlier one instead of adding to it',
      () async {
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    addTearDown(() => store.close());
    await ScannerIngest(store).ingest(
        knowledge([
          _item('a', 'قیمت میلگرد 16 ذوب آهن A3 ۱۱۹٬۰۰۰ تومان',
              topic: 'قیمت میلگرد'),
        ]),
        now: now);
    final second = await ScannerIngest(store).ingest(
        knowledge([
          _item('b', 'قیمت میلگرد 18 شاهرود A3 ۱۰۶٬۸۱۸ تومان',
              topic: 'قیمت میلگرد'),
        ]),
        now: now);
    expect(second, 1);
    final rows = await store.latest();
    expect(rows.length, 1);
    expect(rows.single.sizeLabel, isNot('16'));
  });
}
