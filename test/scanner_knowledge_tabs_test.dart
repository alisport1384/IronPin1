import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ironpin/data/controller.dart';
import 'package:ironpin/data/scanner_api.dart';
import 'package:ironpin/data/scanner_ingest.dart';
import 'package:ironpin/data/sources.dart';
import 'package:ironpin/data/store.dart';
import 'package:ironpin/domain/range_projection.dart';

/// The whole path the user asked for: the scanner's knowledge dump is read,
/// turned into archive rows by the app's own analyzer, and from then on those
/// rows are read by the prices, chart and range tabs exactly like any other
/// source — including the range product list, where each good keeps its own
/// specification.
Map<String, Object?> _item(String id, String topic, String claim) => {
      'id': id,
      'scan_id': 'scan-1',
      'topic': topic,
      'question': topic,
      'claim': claim,
      'url': 'https://example.com/$id',
      'domain': 'example.com',
      'kind': 'chunk',
      'category': 'rag',
      'attribute': 'price',
      'layer': 'price',
      'lang': 'fa',
      'confidence': 0.7,
      'ttl_days': 45,
      'tokens': 120,
      'last_verified_at': DateTime.utc(2026, 11, 20).millisecondsSinceEpoch,
      'tags': <String>[],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('the scanner dump reaches the prices, chart and range tabs', () async {
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    addTearDown(store.close);
    final sourcesBody = jsonEncode({
      'format': 'ironpin-sources-v1',
      'generated_at': '2026-11-21T00:00:00Z',
      'total': 1,
      'by_kind': {'site': 1},
      'sources': [
        {
          'url': 'https://example.com',
          'domain': 'example.com',
          'kind': 'site',
          'origin': 'finder',
          'state': 'ok',
          'name': 'example',
          'readable': true,
          'part': 1,
          'created_at': 1795000000000,
          'last_checked_at': 1795100000000,
        }
      ],
    });
    final knowledgeBody = jsonEncode({
      'format': 'qwen-knowledge-v1',
      'kind': 'report',
      'generated_at': '2026-11-21T00:00:00Z',
      'scope': <String, Object?>{},
      'items': [
        _item('a', 'قیمت نبشی امروز',
            'قیمت نبشی 5 میل ابعاد 50*50 یاوران زنجان ۱۱۷٬۰۹۰ تومان'),
        _item('b', 'قیمت نبشی امروز',
            'قیمت نبشی 6 میل ابعاد 60*60 یاوران زنجان ۱۱۸٬۰۹۰ تومان'),
        _item('c', 'قیمت میلگرد',
            'قیمت میلگرد 16 ذوب آهن A3 ۱۱۹٬۰۰۰ تومان'),
      ],
    });
    final c = MarketController(
        store,
        client: SourceClient(client: _quietClient()),
        scannerApi: ScannerApi(client: MockClient((request) async {
          if (request.url.path.endsWith('/api/sources')) {
            return http.Response.bytes(utf8.encode(sourcesBody), 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }
          if (request.url.path.endsWith('/api/report/all')) {
            return http.Response.bytes(utf8.encode(knowledgeBody), 200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }
          return http.Response('not found', 404);
        })));
    addTearDown(c.dispose);

    await c.refreshScanner(force: true);
    // The publication of the new rows is queued, not awaited by the read.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(c.scannerOfferCount, greaterThan(0),
        reason: 'the information tab counts what the tabs read');
    expect(c.historyRevision, greaterThan(0),
        reason: 'the archive changed, so the derived index is rebuilt');
    final scannerRows =
        c.quotes.where((q) => q.endpoint == ScannerIngest.endpoint).toList();
    expect(scannerRows, isNotEmpty,
        reason: 'the prices tab reads the ingested rows');
    expect(scannerRows.length, c.scannerOfferCount);

    // The chart tab builds its options from the same rows.
    expect(
        c.chartOptions.any((q) => q.endpoint == ScannerIngest.endpoint), isTrue,
        reason: 'the chart tab must offer the ingested goods');

    // The prices filter sees their categories, so a new good is selectable.
    expect(c.availableCategories, contains('نبشی'));
    expect(c.availableCategories, contains('میلگرد'));

    // The range tab reads the derived index: each good keeps its own
    // specification, so two sizes of one product are two entries.
    final angles = scannerRows.where((q) => q.category == 'نبشی').toList();
    expect(angles.map((q) => q.dimensionsLabel).toSet().length,
        greaterThanOrEqualTo(2));
    final set = await c.rangeSession.candidates(
        scope: const CandidateScope(
            basis: '', query: '', maxAgeDays: 30, category: 'نبشی'),
        at: DateTime.now());
    expect(set.total, greaterThanOrEqualTo(2),
        reason: 'the range product list must offer the new goods');
  });

  test('a later dump replaces the earlier rows instead of adding to them',
      () async {
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    addTearDown(store.close);
    var dump = '2026-11-21T00:00:00Z';
    final c = MarketController(
        store,
        client: SourceClient(client: _quietClient()),
        scannerApi: ScannerApi(client: MockClient((request) async {
          if (request.url.path.endsWith('/api/sources')) {
            return http.Response.bytes(
                utf8.encode(jsonEncode({
                  'format': 'ironpin-sources-v1',
                  'generated_at': dump,
                  'total': 0,
                  'by_kind': <String, int>{},
                  'sources': <Object?>[],
                })),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'});
          }
          return http.Response.bytes(
              utf8.encode(jsonEncode({
                'format': 'qwen-knowledge-v1',
                'kind': 'report',
                'generated_at': dump,
                'scope': <String, Object?>{},
                'items': [
                  _item('a', 'قیمت میلگرد',
                      'قیمت میلگرد 16 ذوب آهن A3 ۱۱۹٬۰۰۰ تومان'),
                ],
              })),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        })));
    addTearDown(c.dispose);

    await c.refreshScanner(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final first = c.scannerOfferCount;
    expect(first, greaterThan(0));

    dump = '2026-11-22T00:00:00Z';
    await c.refreshScanner(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.scannerOfferCount, first,
        reason: 'the same one offer is replaced, not duplicated');
    expect(
        c.quotes
            .where((q) => q.endpoint == ScannerIngest.endpoint)
            .toSet()
            .length,
        first);
  });
}

/// A client that answers nothing: this test is about the scanner's own read,
/// so no local source is fetched.
http.Client _quietClient() => MockClient((_) async => http.Response('', 404));
