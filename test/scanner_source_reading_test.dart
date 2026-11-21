import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ironpin/data/controller.dart';
import 'package:ironpin/data/scanner_api.dart';
import 'package:ironpin/data/sources.dart';
import 'package:ironpin/data/store.dart';
import 'package:ironpin/domain/ocr.dart';
import 'package:ironpin/domain/photo_scan.dart';

/// The scanner's knowledge must not become price rows.
///
/// The dump is prose: a chunk of an article is not an offer, and turning it
/// into a row is what put the wrong product, the wrong amount and an unknown
/// unit into the tabs. What the app reads from the scanner is its *sources*,
/// each read with the app's own engine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  final sheetFixture =
      File('test/fixtures/fardad_sheets_reconstructed.html').readAsStringSync();
  final now = DateTime.utc(2026, 11, 20, 10);

  Map<String, Object?> sourceBody(List<Map<String, Object?>> items) =>
      {'kind': 'ironpin-sources-v1', 'total': items.length, 'sources': items};

  Map<String, Object?> knowledgeBody(List<String> urls) => {
        'kind': 'qwen-knowledge-v1',
        'generated_at': '2026-11-21T08:31:09Z',
        'items': [
          for (final u in urls)
            {
              'id': 'item-$u',
              'url': u,
              'topic': 'قیمت آهن',
              'claim': 'قیمت میلگرد ۱۶ امروز ۱۲۳۵۰۰ تومان است',
              'attribute': 'price',
              'kind': 'chunk',
              'category': 'rag',
              'layer': 'price',
              'confidence': 0.9,
              'tokens': 120,
              'ttl_days': 30,
              'lang': 'fa',
              'scan_id': 'scan-1',
              'domain': Uri.parse(u).host,
              'tags': <String>[],
              'last_verified_at': now.millisecondsSinceEpoch,
            }
        ]
      };

  http.Response jsonPage(Object? body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)), 200,
      headers: {'content-type': 'application/json'});

  ScannerApi scannerApi({
    required List<Map<String, Object?>> sources,
    List<String> knowledge = const [],
  }) =>
      ScannerApi(client: MockClient((request) async {
        if (request.url.path.endsWith('/api/sources')) {
          return jsonPage(sourceBody(sources));
        }
        if (request.url.path.endsWith('/api/report/all')) {
          return jsonPage(knowledgeBody(knowledge));
        }
        return http.Response('not found', 404);
      }));

  PhotoScanner quietPhotos() => PhotoScanner(
      client: MockClient((_) async => http.Response('no image', 200,
          headers: {'content-type': 'image/png'})),
      engine: const UnavailableOcrEngine());

  test('a scanner source is read by the app engine; its prose is not a row',
      () async {
    const url = 'https://fardadfoolad.ir/products/164/test';
    var pageRequests = 0;
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final c = MarketController(
        store,
        scannerApi: scannerApi(
            sources: [
              {'url': url, 'kind': 'site'}
            ],
            knowledge: [url]),
        photoScanner: quietPhotos(),
        client: SourceClient(client: MockClient((_) async {
          pageRequests++;
          return http.Response(sheetFixture, 200,
              headers: {'content-type': 'text/html; charset=utf-8'});
        })));
    addTearDown(() async {
      c.dispose();
      await store.close();
    });

    await c.refreshScanner(force: true);
    // The controller's in-memory list is refreshed from the store at the end of
    // a publication; the test reads it through the same door the UI does.
    await c.reload();

    // The place the scanner named was read, and only its page was asked for.
    expect(pageRequests, greaterThan(0));
    expect(c.scannerSources, isNotEmpty);
    expect(c.scannerSources.first.url, url);

    // The rows came from the page, so they carry the page's own product,
    // amount and unit — and the prose chunk is nowhere among them.
    final scannerRows =
        c.quotes.where((q) => q.endpoint.startsWith('scanner-')).toList();
    expect(scannerRows, isNotEmpty);
    expect(scannerRows.every((q) => q.endpoint == c.scannerSources.first.id),
        isTrue);
    expect(scannerRows.length, 2,
        reason: 'only the two rows that really carry a price');
    expect(scannerRows.map((q) => q.thicknessLabel).toSet(), {'3.0'});
    expect(scannerRows.every((q) => q.brand == 'فولاد مبارکه'), isTrue);
    expect(scannerRows.every((q) => q.unit == 'kg'), isTrue);
    expect(scannerRows.every((q) => q.hasTextAmount), isTrue);
    expect(scannerRows.every((q) => q.amount == null), isTrue,
        reason: 'the page announced no currency, so no amount is invented');
    expect(scannerRows.any((q) => q.title.contains('میلگرد')), isFalse,
        reason: 'the prose chunk must not become a price row');
    expect(c.scannerOfferCount, scannerRows.length);
  });

  test('the prose of the dump is stored as knowledge, never as a price row',
      () async {
    const url = 'https://example.com/article';
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final c = MarketController(store,
        scannerApi: scannerApi(sources: [], knowledge: [url]));
    addTearDown(() async {
      c.dispose();
      await store.close();
    });

    await c.refreshScanner(force: true);

    expect(c.scannerItemCount, 1);
    expect(c.scannerTopics, isNotEmpty);
    // No readable source was named, so nothing was fetched and no row was
    // invented from the prose.
    expect(c.scannerOfferCount, 0);
    expect(c.quotes.where((q) => q.endpoint.startsWith('scanner-')), isEmpty);
  });

  test('a place that is not a price list yields nothing', () async {
    const url = 'https://example.com/news';
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final c = MarketController(
        store,
        scannerApi: scannerApi(sources: [
          {'url': url, 'kind': 'site'}
        ]),
        photoScanner: PhotoScanner(
            client: MockClient((_) async => http.Response('', 404)),
            engine: const UnavailableOcrEngine()),
        client: SourceClient(client: MockClient((_) async {
          return http.Response(
              '<html><body><h1>اخبار فولاد</h1>'
              '<p>افزایش تولید ورق در نیمهٔ اول سال</p></body></html>',
              200,
              headers: {'content-type': 'text/html; charset=utf-8'});
        })));
    addTearDown(() async {
      c.dispose();
      await store.close();
    });

    await c.refreshScanner(force: true);

    expect(c.scannerSources.length, 1);
    expect(c.quotes.where((q) => q.endpoint.startsWith('scanner-')), isEmpty,
        reason: 'a news page is not a price list, so it adds no row');
    expect(c.scannerOfferCount, 0);
  });
}
