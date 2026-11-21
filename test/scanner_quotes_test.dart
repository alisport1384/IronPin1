import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ironpin/data/controller.dart';
import 'package:ironpin/data/scanner_api.dart';
import 'package:ironpin/data/scanner_quotes.dart';
import 'package:ironpin/data/store.dart';

/// The scanner's quotes are already in the app's own `Quote` shape, so the app
/// does not interpret them — it keeps the offers and refuses the prose.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  Map<String, Object?> quote({
    required String id,
    String title = 'میلگرد ۱۶',
    String category = 'میلگرد',
    Object? amount = 123500,
    String unit = 'kg',
    String currency = 'تومان',
    String city = 'قم',
    String url = 'https://example.com/a',
  }) =>
      {
        'id': id,
        'endpoint': 'qwen-scanner',
        'seller': 'example.com',
        'sellerCity': city,
        'title': title,
        'category': category,
        'material': 'فولاد کربنی',
        'brand': '',
        'loading': 'نامشخص',
        'loadingCity': 'نامشخص',
        'unit': unit,
        'tax': 'نامشخص',
        'currency': currency,
        'terms': 'نامشخص',
        'sourceUrl': url,
        'sourceDateRaw': '2026-11-21T14:01:45.804Z',
        'status': 'استخراج متنی با مبلغ/ارز/واحد',
        'amount': amount,
        'pieceKg': null,
        'lengthM': null,
        'areaM2': null,
        'fetchedAt': '2026-11-21T14:01:45.804Z',
        'size': '',
        'thickness': '',
        'dimensions': '',
        'grade': '',
        'details': {'تحلیل متن': 'محلی v2'},
      };

  Map<String, Object?> payload(List<Map<String, Object?>> quotes) => {
        'format': 'ironpin-quotes-v1',
        'generated_at': '2026-11-21T14:38:26.181Z',
        'count': quotes.length,
        'quotes': quotes,
      };

  http.Response json(Object? body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)), 200,
      headers: {'content-type': 'application/json'});

  Future<MarketStore> memory() => MarketStore.open(
      dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);

  test('an offer is kept exactly as the scanner says it', () async {
    final db = await memory();
    addTearDown(() => db.close());
    final result = await ScannerQuotesIngest(db).ingest(
        ScannerQuotes.fromJson(payload([
          quote(id: 'q-1'),
        ])),
        DateTime.now());
    expect(result.written, 1);
    final stored = await db.latest();
    expect(stored.length, 1);
    final q = stored.single;
    expect(q.endpoint, ScannerQuotesIngest.endpoint);
    expect(q.title, 'میلگرد ۱۶');
    expect(q.category, 'میلگرد');
    expect(q.amount, 123500);
    expect(q.unit, 'kg');
    expect(q.currency, 'تومان');
    expect(q.sellerCity, 'قم');
    expect(q.details['منبع ردیف'], 'اسکنر آنلاین (ironpin-quotes-v1)');
  });

  test('prose, a non-metal good, and a missing amount/unit/currency are refused',
      () async {
    final db = await memory();
    addTearDown(() => db.close());
    // The shapes the real dump carries: 5,538 of 5,613 items are prose with no
    // amount at all.
    final result = await ScannerQuotesIngest(db).ingest(
        ScannerQuotes.fromJson(payload([
          quote(id: 'q-1'),
          quote(
              id: 'q-2',
              title:
                  'تحلیل و پیش‌بینی قیمت میلگرد در سال 1404 یکی از دغدغه‌های اصلی خریداران است.',
              amount: null,
              unit: 'unknown',
              currency: 'نامشخص'),
          quote(id: 'q-3', title: 'قرص آهن یک ورق', category: 'ورق'),
          quote(id: 'q-4', amount: 0),
          quote(id: 'q-5', unit: 'unknown'),
          quote(id: 'q-6', currency: 'نامشخص'),
        ])),
        DateTime.now());
    expect(result.written, 1);
    expect(result.refused['noProduct'], 1);
    expect(result.refused['noAmount'], 2);
    expect(result.refused['noUnit'], 1);
    expect(result.refused['noCurrency'], 1);
  });

  test('the scanner id makes one offer twice in a dump one row', () async {
    final db = await memory();
    addTearDown(() => db.close());
    final result = await ScannerQuotesIngest(db).ingest(
        ScannerQuotes.fromJson(payload([
          quote(id: 'q-1'),
          quote(id: 'q-1'),
        ])),
        DateTime.now());
    expect(result.written, 1);
  });

  test('a new dump replaces the rows of the previous one', () async {
    final db = await memory();
    addTearDown(() => db.close());
    await ScannerQuotesIngest(db).ingest(
        ScannerQuotes.fromJson(payload([quote(id: 'q-1')])),
        DateTime.now());
    final second = await ScannerQuotesIngest(db).ingest(
        ScannerQuotes.fromJson(payload([
          quote(id: 'q-2', amount: 130000),
        ])),
        DateTime.now());
    expect(second.written, 1);
    final stored = await db.latest();
    expect(stored.length, 1);
    expect(stored.single.amount, 130000);
  });

  test('a scanner without the endpoint is a normal answer, not an error',
      () async {
    expect(
        await ScannerApi(
                client: MockClient((_) async => http.Response('', 404)))
            .quotes(),
        isNull);
    expect(
        await ScannerApi(
                client: MockClient((_) async => http.Response('not json', 200)))
            .quotes(),
        isNull);
  });

  test('the refresh reads the quotes and publishes them to the tabs', () async {
    final db = await memory();
    final c = MarketController(
        db,
        scannerApi: ScannerApi(client: MockClient((request) async {
          if (request.url.path.endsWith('/api/sources')) {
            return json({
              'format': 'ironpin-sources-v1',
              'generated_at': '2026-11-21T10:48:09Z',
              'total': 0,
              'by_kind': <String, int>{},
              'sources': <Object?>[],
            });
          }
          if (request.url.path.endsWith('/api/report/all')) {
            return json({
              'format': 'qwen-knowledge-v1',
              'generated_at': '2026-11-21T08:31:09Z',
              'items': <Object?>[],
            });
          }
          if (request.url.path.endsWith('/api/ironpin')) {
            return json(payload([
              quote(id: 'q-1'),
            ]));
          }
          return http.Response('not found', 404);
        })));
    addTearDown(() async {
      c.dispose();
      await db.close();
    });

    await c.refreshScanner(force: true);
    await c.reload();

    final rows = c.quotes
        .where((q) => q.endpoint == ScannerQuotesIngest.endpoint)
        .toList();
    expect(rows, isNotEmpty);
    expect(rows.single.title, 'میلگرد ۱۶');
    expect(c.scannerOfferCount, rows.length);
  });

  test('the observed real dump keeps only its real offers', () {
    // The shape measured on 2026-11-21: 5,613 quotes, 75 with an amount, and
    // most of those are prose with an incidental number. The reader must not
    // turn a sentence into a row.
    final observed = File('/tmp/ironpin.json');
    if (!observed.existsSync()) return;
    final dump = ScannerQuotes.fromJson(jsonDecode(observed.readAsStringSync())
        as Map<String, dynamic>);
    expect(dump.quotes.length, 5613);
    var withAmount = 0;
    for (final q in dump.quotes) {
      if ((q.amount ?? 0) > 0) withAmount++;
    }
    expect(withAmount, 75);
  });
}
