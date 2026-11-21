import 'package:flutter/foundation.dart';

import '../domain/market.dart';
import '../domain/searcher.dart';
import '../domain/text_engine.dart';
import 'scanner_api.dart';
import 'store.dart';

/// Turns the scanner's published knowledge into the app's own price rows.
///
/// The scanner reads public pages with جستجوگر ۲ and publishes what it
/// extracted. Showing that archive only in the information tab left the prices,
/// chart and range tabs empty of it, because those three read the stored rows
/// and the knowledge never became one.
///
/// Every price item therefore goes through the same `TextPriceEngine` and
/// `Searcher` path a post or a picture goes through, and only the rows that
/// survive are stored — under one endpoint of their own, so from then on they
/// are ordinary rows: the three tabs, the range product list and the range
/// index read them like any other source.
///
/// Nothing is guessed: an item that carries no product with an announced amount
/// is dropped by the same rule that drops a sentence from a channel. The
/// scanner's own verification date travels with the row, so the tabs' windows
/// decide what is current — the read time is never presented as the source's.
class ScannerIngest {
  /// The endpoint the ingested rows live under. It is not one of the user's
  /// sources: it has no switch, is never fetched on its own, and is replaced
  /// whole by each ingest.
  static const String endpoint = 'scanner-knowledge';

  final MarketStore store;
  const ScannerIngest(this.store);

  /// Parses [knowledge] and stores the rows it really holds. Returns how many
  /// rows were written, `0` when the dump carried no offer at all.
  Future<int> ingest(ScannerKnowledge knowledge,
      {required DateTime now, int windowDays = 0}) async {
    final items = knowledge.priceItems;
    if (items.isEmpty) return 0;
    // The scanner publishes whole pages as chunks. This read is local, so the
    // same dump can be parsed again, and a dump that grew while the app was
    // away is re-read on its own.
    final before = await store.activeEndpointCount(endpoint);
    // Plain maps cross an isolate without copying a `Quote` (whose lazily
    // built search text is not part of its state), and they keep the parse off
    // the interface thread: the whole dump is tens of thousands of items.
    final payload = <Map<String, Object?>>[
      for (final i in items)
        {
          'id': i.id,
          'topic': i.topic,
          'claim': i.claim,
          'url': i.url,
          'domain': i.domain,
          'verifiedAt': i.lastVerifiedAt.millisecondsSinceEpoch,
        }
    ];
    final args = _ParseArgs(payload: payload, now: now, windowDays: windowDays);
    List<Map<String, Object?>> written;
    try {
      written = await compute(_parse, args);
    } catch (_) {
      // No second isolate available on this embedder: same answer, in place.
      written = _parse(args);
    }
    // Only the rows whose amount survived the analyzer are written. An item
    // whose amount was never a unit price (a table total, a branch total) is
    // exactly the kind of number that would corrupt every tab that reads it,
    // and the analyzer only decides by looking at the text — so the check
    // happens here, on the row, not on a guess made before parsing.
    final rows = [
      for (final j in written)
        if ((j['amount'] as num?)?.toDouble() case final double amount
            when amount > 0)
          Quote.fromJson(j)
    ];
    if (rows.isEmpty) {
      // The dump's offers are gone (or none survived the rules). The old rows
      // of this endpoint are not left in the tabs as if they were still
      // current: they are retired, exactly as a source that no longer answers
      // is.
      if (before > 0) await store.retireEndpoint(endpoint);
      return 0;
    }
    await store.saveSnapshot(endpoint, rows, replaceMissing: true);
    return rows.length;
  }
}

class _ParseArgs {
  final List<Map<String, Object?>> payload;
  final DateTime now;
  final int windowDays;
  const _ParseArgs(
      {required this.payload, required this.now, required this.windowDays});
}

/// The whole parse, runnable on its own isolate. Returns quote payloads, not
/// `Quote` objects, so the answer crosses the isolate boundary unchanged.
List<Map<String, Object?>> _parse(_ParseArgs args) {
  final rows = <Quote>[];
  for (final item in args.payload) {
    final text = '${item['claim']}'.trim();
    if (text.length < 20) continue;
    final domain = '${item['domain']}';
    final verified = item['verifiedAt'];
    try {
      for (final q in TextPriceEngine.analyze(
          text: text,
          endpoint: ScannerIngest.endpoint,
          seller: domain.isEmpty ? 'اسکنر آنلاین' : domain,
          sourceUrl: '${item['url']}',
          fetchedAt: args.now,
          postId: '${item['id']}',
          publishedAt: DateTime.fromMillisecondsSinceEpoch(
              verified is int ? verified : 0))) {
        // The scanner's own topic is part of the evidence: it says which
        // question the page answered, which the row's product alone does not.
        final j = q.toJson();
        j['details'] = {...q.details, 'دستهٔ دانش': '${item['topic']}'};
        rows.add(Quote.fromJson(j));
      }
    } catch (_) {
      // One malformed item must not lose the whole dump: the rest of the
      // archive is read and this item simply contributes nothing.
    }
  }
  if (rows.isEmpty) return const [];
  final found = Searcher.process(rows,
      now: args.now, windowDays: args.windowDays);
  return [for (final q in found.quotes) q.toJson()];
}
