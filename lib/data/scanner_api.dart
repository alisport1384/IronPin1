import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/market.dart';

/// اسکنر آنلاین پایگاه دانش قیمت آهن.
///
/// The scanner publishes three stable endpoints and one human page:
///
///  * `/api/sources`   — the source registry (`ironpin-sources-v1`), grown by
///                       source discovery in جستجوگر ۲; new links appear here
///                       first.
///  * `/api/report/all`— the whole extracted knowledge (`qwen-knowledge-v1`),
///                       pre-chunked, grouped by `topic`.
///  * `/report/all`    — the same knowledge as one page, for a browser.
///
/// Nothing here decides anything: the app only reads, categorises and shows.
class ScannerApi {
  static const String baseUrl = 'https://qwen.alisport0.qzz.io';
  static const String sourcesEndpoint = '$baseUrl/api/sources';
  static const String knowledgeEndpoint = '$baseUrl/api/report/all';

  /// The scanner's own extraction, in the app's own `Quote` shape
  /// (`ironpin-quotes-v1`). Optional: a scanner without it answers 404 and the
  /// app simply keeps its own sources.
  static const String quotesEndpoint = '$baseUrl/api/ironpin';

  /// The single link that puts every extracted item in one place.
  static const String allKnowledgePage = '$baseUrl/report/all';
  static const String sourcesPage = '$baseUrl/report/sources';

  final http.Client client;
  ScannerApi({http.Client? client}) : client = client ?? http.Client();

  Future<ScannerSources> sources() async {
    final r = await client.get(Uri.parse(sourcesEndpoint), headers: {
      'User-Agent': 'IronPin/0.9 (public knowledge reader)',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 40));
    if (r.statusCode != 200) {
      throw ScannerException('HTTP ${r.statusCode} در فهرست منابع');
    }
    return ScannerSources.fromJson(
        jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true))
            as Map<String, dynamic>);
  }

  /// The whole knowledge dump. It is large (about 11 MB), so the caller decides
  /// when it is worth downloading; parsing happens off the UI thread.
  Future<ScannerKnowledge> knowledge() async {
    final r = await client.get(Uri.parse(knowledgeEndpoint), headers: {
      'User-Agent': 'IronPin/0.9 (public knowledge reader)',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 180));
    if (r.statusCode != 200) {
      throw ScannerException('HTTP ${r.statusCode} در کل دانش');
    }
    return ScannerKnowledge.fromJson(
        jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true))
            as Map<String, dynamic>);
  }

  /// The scanner's quotes (`ironpin-quotes-v1`), when it publishes them.
  ///
  /// `null` is a normal answer — a scanner without the endpoint (404) or with a
  /// malformed body — so the refresh is never broken by it.
  Future<ScannerQuotes?> quotes() async {
    try {
      final r = await client.get(Uri.parse(quotesEndpoint), headers: {
        'User-Agent': 'IronPin/0.9 (public knowledge reader)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 120));
      if (r.statusCode == 404) return null;
      if (r.statusCode != 200) {
        throw ScannerException('HTTP ${r.statusCode} در ردیف‌های اسکنر');
      }
      return ScannerQuotes.fromJson(
          jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true))
              as Map<String, dynamic>);
    } on ScannerException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  void close() => client.close();
}

class ScannerException implements Exception {
  final String message;
  const ScannerException(this.message);
  @override
  String toString() => message;
}

/// One entry of `ironpin-sources-v1`.
class ScannerSource {
  final String url, domain, kind, origin, state;
  final String? name;
  final bool readable;
  final int part;
  final DateTime createdAt, lastCheckedAt;

  /// True when this url was not in the archive the last time the app looked.
  /// هوش جستجوگر ۲ keeps discovering sources, so the registry grows; the app
  /// compares each fetch with what it stored instead of trusting a fixed list.
  final bool isNew;

  const ScannerSource({
    required this.url,
    required this.domain,
    required this.kind,
    required this.origin,
    required this.state,
    required this.name,
    required this.readable,
    required this.part,
    required this.createdAt,
    required this.lastCheckedAt,
    this.isNew = false,
  });

  factory ScannerSource.fromJson(Map<String, dynamic> j) => ScannerSource(
        url: '${j['url'] ?? ''}',
        domain: '${j['domain'] ?? ''}',
        kind: '${j['kind'] ?? 'site'}',
        origin: '${j['origin'] ?? ''}',
        state: '${j['state'] ?? ''}',
        name: j['name'] as String?,
        readable: j['readable'] != false,
        part: (j['part'] as num?)?.toInt() ?? 0,
        createdAt: _ms(j['created_at']),
        lastCheckedAt: _ms(j['last_checked_at']),
      );

  Map<String, Object?> toRow(String firstSeen, String lastSeen) => {
        'url': url,
        'domain': domain,
        'kind': kind,
        'origin': origin,
        'state': state,
        'name': name,
        'readable': readable ? 1 : 0,
        'part': part,
        'first_seen': firstSeen,
        'last_seen': lastSeen,
      };
}

class ScannerSources {
  final String format, generatedAt;
  final int total;
  final Map<String, int> byKind;
  final List<ScannerSource> sources;
  const ScannerSources({
    required this.format,
    required this.generatedAt,
    required this.total,
    required this.byKind,
    required this.sources,
  });

  factory ScannerSources.fromJson(Map<String, dynamic> j) => ScannerSources(
        format: '${j['format'] ?? ''}',
        generatedAt: '${j['generated_at'] ?? ''}',
        total: (j['total'] as num?)?.toInt() ?? 0,
        byKind: {
          for (final e in (j['by_kind'] as Map? ?? {}).entries)
            '${e.key}': (e.value as num?)?.toInt() ?? 0,
        },
        sources: [
          for (final e in (j['sources'] as List? ?? []))
            ScannerSource.fromJson(Map<String, dynamic>.from(e as Map))
        ],
      );
}

/// One pre-chunked knowledge item of `qwen-knowledge-v1`.
class ScannerItem {
  final String id, scanId, topic, claim, url, domain;
  final String kind, category, attribute, layer, lang;
  final double confidence;
  final int ttlDays, tokens;
  final DateTime lastVerifiedAt;
  final List<String> tags;

  const ScannerItem({
    required this.id,
    required this.scanId,
    required this.topic,
    required this.claim,
    required this.url,
    required this.domain,
    required this.kind,
    required this.category,
    required this.attribute,
    required this.layer,
    required this.lang,
    required this.confidence,
    required this.ttlDays,
    required this.tokens,
    required this.lastVerifiedAt,
    required this.tags,
  });

  factory ScannerItem.fromJson(Map<String, dynamic> j) => ScannerItem(
        id: '${j['id'] ?? ''}',
        scanId: '${j['scan_id'] ?? ''}',
        topic: '${j['topic'] ?? ''}',
        claim: '${j['claim'] ?? ''}',
        url: '${j['url'] ?? ''}',
        domain: '${j['domain'] ?? ''}',
        kind: '${j['kind'] ?? 'chunk'}',
        category: '${j['category'] ?? ''}',
        attribute: '${j['attribute'] ?? ''}',
        layer: '${j['layer'] ?? ''}',
        lang: '${j['lang'] ?? ''}',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        ttlDays: (j['ttl_days'] as num?)?.toInt() ?? 0,
        tokens: (j['tokens'] as num?)?.toInt() ?? 0,
        lastVerifiedAt: _ms(j['last_verified_at']),
        tags: [
          for (final t in (j['tags'] as List? ?? [])) '$t'
        ],
      );

  Map<String, Object?> toRow(String fetchedAt) => {
        'id': id,
        'topic': topic,
        'kind': kind,
        'claim': claim,
        'url': url,
        'domain': domain,
        'confidence': confidence,
        'attribute': attribute,
        'lang': lang,
        'verified_at': lastVerifiedAt.millisecondsSinceEpoch,
        'fetched_at': fetchedAt,
      };
}

class ScannerKnowledge {
  final String format, kind, generatedAt;
  final Map<String, Object?> scope;
  final List<ScannerItem> items;
  const ScannerKnowledge({
    required this.format,
    required this.kind,
    required this.generatedAt,
    required this.scope,
    required this.items,
  });

  factory ScannerKnowledge.fromJson(Map<String, dynamic> j) =>
      ScannerKnowledge(
        format: '${j['format'] ?? ''}',
        kind: '${j['kind'] ?? ''}',
        generatedAt: '${j['generated_at'] ?? ''}',
        scope: Map<String, Object?>.from(j['scope'] as Map? ?? {}),
        items: [
          for (final e in (j['items'] as List? ?? []))
            ScannerItem.fromJson(Map<String, dynamic>.from(e as Map))
        ],
      );

  /// The scanner labels every item with one attribute; only `price` items are
  /// kept, so the archive never grows with unrelated extraction.
  List<ScannerItem> get priceItems =>
      items.where((i) => i.attribute == 'price').toList(growable: false);
}

/// The scanner's extraction, already in the app's own [Quote] shape.
///
/// Reading it needs no re-interpretation: the scanner says what it found and
/// the app keeps it — or refuses it, when it is not an offer (see
/// `ScannerQuotesIngest`). Keeping the app's own shape is what makes the two
/// sides agree about what a row is.
class ScannerQuotes {
  final String format, generatedAt;
  final int count;
  final List<Quote> quotes;
  const ScannerQuotes({
    required this.format,
    required this.generatedAt,
    required this.count,
    required this.quotes,
  });

  factory ScannerQuotes.fromJson(Map<String, dynamic> j) => ScannerQuotes(
        format: '${j['format'] ?? ''}',
        generatedAt: '${j['generated_at'] ?? ''}',
        count: (j['count'] as num?)?.toInt() ?? 0,
        quotes: [
          for (final e in (j['quotes'] as List? ?? []))
            Quote.fromJson(Map<String, dynamic>.from(e as Map))
        ],
      );
}

DateTime _ms(Object? value) {
  final n = value is num ? value.toInt() : int.tryParse('$value');
  return n == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.fromMillisecondsSinceEpoch(n);
}
