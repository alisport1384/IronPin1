import '../domain/maps_resolver.dart';
import '../domain/photo_scan.dart';
import '../domain/searcher.dart';
import 'sources.dart';

/// Reads one source with the app's own engine.
///
/// The scanner's knowledge is prose: it publishes the chunks its model
/// retrieved from a page, and a chunk of an article about «قیمت تیرچه» is not
/// an offer. Reading such a chunk as a price row put the wrong product, the
/// wrong amount and no unit into the tabs, which is exactly what the user
/// reported.
///
/// So the page itself is read here — the same `SourceClient` parser a
/// registered route uses (a seller's table under its own heading, a channel's
/// messages), the same photo reader for the pictures the source published, and
/// the same searcher that decides what is an offer. Nothing is special about
/// the reading: the scanner only says *where* to look.
///
/// A page that is not a price list therefore yields nothing, which is the
/// correct answer for it.
Future<SearcherResult> readSourceWithAppEngine(
  SourceClient client,
  PhotoScanner photos,
  SourceEndpoint endpoint, {
  required DateTime now,
  required int windowDays,
  int pageLimit = 2,
}) async {
  final fetched =
      await client.fetch(endpoint, windowDays: windowDays, pageLimit: pageLimit);
  final pictures =
      await readPostPhotos(fetched, photos, defaultCurrency: endpoint.defaultCurrency);
  if (pictures.rows.isEmpty) return const SearcherResult([]);
  return Searcher.processAsync(pictures.rows,
      now: now,
      windowDays: windowDays,
      resolver: MapsResolver(client.client));
}
