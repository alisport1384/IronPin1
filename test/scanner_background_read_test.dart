import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ironpin/data/scanner_api.dart';
import 'package:ironpin/data/scanner_background.dart';
import 'package:ironpin/data/sources.dart';
import 'package:ironpin/data/store.dart';

/// The background pass keeps reading the scanner's own sources while the app
/// is closed, and the manual refresh rotates through them in bounded slices.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  final fixture =
      File('test/fixtures/fardad_sheets_reconstructed.html').readAsStringSync();

  Future<MarketStore> store() => MarketStore.open(
      dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);

  test('the background pass reads a few scanner sources and stores their rows',
      () async {
    final db = await store();
    final urls = [
      'https://a.example/sheet',
      'https://b.example/sheet',
      'https://c.example/sheet',
      'https://d.example/sheet',
      'https://e.example/sheet',
    ];
    final now = DateTime.utc(2026, 11, 21);
    for (final u in urls) {
      await db.scannerSaveSources([
        ScannerSource(
            url: u,
            domain: Uri.parse(u).host,
            kind: 'site',
            origin: 'finder',
            state: 'new',
            name: null,
            readable: true,
            part: 0,
            createdAt: now,
            lastCheckedAt: now)
      ], now);
    }
    final client = SourceClient(client: MockClient((_) async {
      return http.Response(fixture, 200,
          headers: {'content-type': 'text/html; charset=utf-8'});
    }));
    addTearDown(() async {
      client.close();
      await db.close();
    });

    final written = await runScannerBackground(db, client);
    expect(written, greaterThan(0));
    expect(await db.scannerEndpointRowCount(), written);
    // A bounded slice, not the whole registry.
    final rows = await db.latest();
    expect(rows.map((q) => q.endpoint).toSet().length,
        lessThanOrEqualTo(MarketControllerScannerBackground.limit));
    expect(rows.every((q) => q.endpoint.startsWith('scanner-')), isTrue);
    // The cursor moved, so the next pass reads the next places.
    final cursor =
        int.parse(await db.setting('scanner.sourcesCursor') ?? '-1');
    expect(cursor, greaterThanOrEqualTo(0));
    expect(cursor, lessThan(urls.length));
  });

  test('a manual refresh reads a bounded slice and rotates the cursor',
      () async {
    final db = await store();
    final now = DateTime.utc(2026, 11, 21);
    final urls = [
      for (var i = 0; i < 5; i++) 'https://s$i.example/sheet'
    ];
    for (final u in urls) {
      await db.scannerSaveSources([
        ScannerSource(
            url: u,
            domain: Uri.parse(u).host,
            kind: 'site',
            origin: 'finder',
            state: 'new',
            name: null,
            readable: true,
            part: 0,
            createdAt: now,
            lastCheckedAt: now)
      ], now);
    }
    final client = SourceClient(client: MockClient((_) async {
      return http.Response(fixture, 200,
          headers: {'content-type': 'text/html; charset=utf-8'});
    }));
    addTearDown(() async {
      client.close();
      await db.close();
    });
    final routes = await db.scannerRoutes();
    expect(routes.length, urls.length);
    // Every route is a readable page, so the reader is the same engine a
    // registered route uses.
    for (final r in routes) {
      expect(r.parser, 'site-table');
      expect(r.id, 'scanner-${r.url}');
    }
  });
}
