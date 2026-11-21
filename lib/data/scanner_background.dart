import '../domain/ocr.dart';
import '../domain/photo_scan.dart';
import 'scanner_source_reader.dart';
import 'sources.dart';
import 'store.dart';

/// Reads a bounded slice of the scanner's source registry while the app is
/// closed.
///
/// The registry holds about a thousand places, so the background pass reads
/// only a few of them (the rotating cursor in [MarketStore] setting
/// `scanner.sourcesCursor` decides which) and stores what the pages really
/// say. Nothing here decides what a row is: the same reader a manual refresh
/// uses does the deciding.
Future<int> runScannerBackground(MarketStore store, SourceClient client) async {
  final routes = await store.scannerRoutes();
  if (routes.isEmpty) return 0;
  final cursor =
      int.tryParse(await store.setting('scanner.sourcesCursor') ?? '') ?? 0;
  final days = int.tryParse(await store.setting('windowDays') ?? '') ?? 30;
  final photos = PhotoScanner(
      client: client.client, engine: OcrEngine.platform());
  final now = DateTime.now();
  var written = 0;
  final start = ((cursor % routes.length) + routes.length) % routes.length;
  for (var i = 0; i < MarketControllerScannerBackground.limit; i++) {
    final e = routes[(start + i) % routes.length];
    try {
      final found = await readSourceWithAppEngine(client, photos, e,
          now: now, windowDays: days, pageLimit: 1);
      if (found.quotes.isEmpty) continue;
      await store.saveSnapshot(e.id, found.quotes, replaceMissing: true);
      written += found.quotes.length;
    } catch (_) {
      // One unreadable place never stops the rest of the slice.
    }
  }
  await store.setSetting('scanner.sourcesCursor',
      '${(start + MarketControllerScannerBackground.limit) % routes.length}');
  return written;
}

/// Kept in step with `MarketController.scannerSourcesPerBackground` without
/// making the background isolate depend on the UI controller.
class MarketControllerScannerBackground {
  static const int limit = 4;
}
