import '../domain/market.dart';
import '../domain/product_text.dart';
import 'scanner_api.dart';
import 'store.dart';

/// Stores the scanner's quotes, keeping only what is really an offer.
///
/// The scanner publishes its extraction in the app's own [Quote] shape, so the
/// app does not have to interpret anything. But the scanner's own log says most
/// of its items are «متن فاقد مبلغ یکتای قابل استخراج» — text with no amount —
/// and a dump of 5,613 of them carried 75 amounts. Storing all 5,613 would fill
/// the tabs with prose, which is exactly the complaint this replaces.
///
/// So a quote is kept only when it is an offer by the same rules as any other
/// source:
/// * the product is one the app's vocabulary knows and is not non-metal;
/// * the amount is positive;
/// * the basis is one the app can compare (`unknown` is refused);
/// * the currency is stated (`نامشخص` is refused).
/// Everything else is counted and dropped, and the reason is logged.
class ScannerQuotesIngest {
  final MarketStore store;
  const ScannerQuotesIngest(this.store);

  /// Endpoint the kept quotes live under. Ordinary archive rows, so the prices,
  /// chart and range tabs read them like any other source.
  static const endpoint = 'scanner-quotes';

  static const _refusedKeys = [
    'noProduct',
    'noAmount',
    'noUnit',
    'noCurrency',
  ];

  Future<ScannerQuotesResult> ingest(ScannerQuotes quotes, DateTime now) async {
    final refused = {for (final k in _refusedKeys) k: 0};
    final out = <Quote>[];
    final seen = <String>{};
    for (final q in quotes.quotes) {
      final category = q.category.trim();
      if (category.isEmpty ||
          ProductText.isNonMetal('${q.title} ${q.category}')) {
        refused['noProduct'] = refused['noProduct']! + 1;
        continue;
      }
      final amount = q.amount;
      if (amount == null || amount <= 0 || amount.isNaN) {
        refused['noAmount'] = refused['noAmount']! + 1;
        continue;
      }
      if (q.unit == 'unknown') {
        refused['noUnit'] = refused['noUnit']! + 1;
        continue;
      }
      if (q.currency == 'نامشخص') {
        refused['noCurrency'] = refused['noCurrency']! + 1;
        continue;
      }
      // One offer twice in the dump is one row; the identity is the scanner's
      // own id when it gave one.
      final key = q.id.isEmpty
          ? '${q.sourceUrl}|${q.title}|$amount|${q.unit}|${q.sourceDateRaw}'
          : q.id;
      if (!seen.add(key)) continue;
      out.add(Quote(
        id: '$endpoint:${_suffix(key)}',
        endpoint: endpoint,
        seller: q.seller,
        sellerCity: q.sellerCity,
        title: q.title,
        category: q.category,
        material: q.material,
        brand: q.brand,
        loading: q.loading,
        loadingCity: q.loadingCity,
        unit: q.unit,
        tax: q.tax,
        currency: q.currency,
        terms: q.terms,
        sourceUrl: q.sourceUrl,
        sourceDateRaw: q.sourceDateRaw,
        status: q.status,
        amount: q.amount,
        pieceKg: q.pieceKg,
        lengthM: q.lengthM,
        areaM2: q.areaM2,
        fetchedAt: now,
        size: q.size,
        thickness: q.thickness,
        dimensions: q.dimensions,
        grade: q.grade,
        details: {
          ...q.details,
          'منبع ردیف': 'اسکنر آنلاین (ironpin-quotes-v1)',
        },
      ));
    }
    if (out.isEmpty) return ScannerQuotesResult(0, refused);
    await store.saveSnapshot(endpoint, out, replaceMissing: true);
    return ScannerQuotesResult(out.length, refused);
  }

  static String _suffix(String key) {
    var h = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0x7fffffff;
    }
    return h.toRadixString(16);
  }
}

class ScannerQuotesResult {
  final int written;
  final Map<String, int> refused;
  const ScannerQuotesResult(this.written, this.refused);
}
