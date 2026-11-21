import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ironpin/data/controller.dart';
import 'package:ironpin/data/scanner_api.dart';
import 'package:ironpin/data/sources.dart';
import 'package:ironpin/data/store.dart';

/// «اسکن بدون سرور» must stop the whole fetch, not only the scanner server.
///
/// The refresh button used to skip the server and still search every local
/// source, so turning the key on changed nothing the user could see: the
/// internal sources were still read. Both counters below stand in for the
/// network, so the test never reaches a real host.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('a serverless refresh reads no source and no scanner endpoint',
      () async {
    var sourceRequests = 0;
    var scannerRequests = 0;
    final fixture =
        File('test/fixtures/fardad_sheets_reconstructed.html').readAsStringSync();
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    final c = MarketController(
        store,
        client: SourceClient(client: MockClient((_) async {
          sourceRequests++;
          return http.Response(fixture, 200,
              headers: {'content-type': 'text/html; charset=utf-8'});
        })),
        scannerApi: ScannerApi(client: MockClient((_) async {
          scannerRequests++;
          return http.Response('not a registry', 500);
        })));
    addTearDown(() async {
      c.dispose();
      await store.close();
    });

    // One local source, so the control run is fast and countable.
    c.enabled = {'fardad-sheet'};
    await c.setDiscoveryDays(0);

    // Control: with the key off the refresh really does fetch both.
    await c.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(sourceRequests, greaterThan(0),
        reason: 'the control refresh must reach the local source');
    expect(scannerRequests, greaterThan(0),
        reason: 'the control refresh must reach the scanner server');
    final fetchedAt = c.lastRefreshAt;
    expect(fetchedAt, isNotNull);
    final storedRows = c.quotes.length;
    expect(storedRows, greaterThan(0));

    // The key on: the same button must not read anything from the network.
    await c.setScannerServerless(true);
    expect(c.scannerServerless, isTrue);
    final quietSources = sourceRequests;
    final quietScanner = scannerRequests;
    await c.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(sourceRequests, quietSources,
        reason: 'no local source may be read while serverless');
    expect(scannerRequests, quietScanner,
        reason: 'no scanner endpoint may be read while serverless');
    expect(c.lastRefreshAt, fetchedAt,
        reason: 'nothing was fetched, so the last-fetch time must not move');
    expect(c.quotes.length, storedRows,
        reason: 'the local archive is re-read, not replaced');
    expect(c.refreshNote, contains('بدون سرور'));
    expect(c.busy, isFalse);

    // The key off again: the refresh fetches like before.
    await c.setScannerServerless(false);
    await c.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(sourceRequests, greaterThan(quietSources));
    expect(scannerRequests, greaterThan(quietScanner));
  });
}
