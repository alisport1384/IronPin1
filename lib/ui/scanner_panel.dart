import 'package:flutter/material.dart';

import '../data/controller.dart';
import '../data/scanner_api.dart';
import '../domain/market.dart';
import '../domain/money.dart';
import 'common.dart';

/// پایگاه دانش اسکنر آنلاین در زبانهٔ «اطلاعات».
///
/// The scanner discovers sources with جستجوگر ۲, extracts knowledge, categorises
/// it by topic and publishes the whole thing at one address. This panel reads
/// that public database: it shows what the scanner found, names the links that
/// are new since the last look, and groups the knowledge by topic.
///
/// Both switches are off by default. With both off the knowledge is read from
/// the server on a refresh; «اسکن بدون سرور» is the opt-in that stops that read.
class ScannerPanel extends StatefulWidget {
  final MarketController c;
  const ScannerPanel({super.key, required this.c});

  @override
  State<ScannerPanel> createState() => _ScannerPanelState();
}

class _ScannerPanelState extends State<ScannerPanel> {
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('اسکنر آنلاین — پایگاه دانش قیمت آهن',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      const Text(
          'اسکنر منابع را با جستجوگر ۲ کشف می‌کند، اطلاعات استخراج‌شده را دسته‌بندی و منتشر می‌کند. '
          'این بخش فقط همان پایگاه عمومی را می‌خواند و چیزی به آن نمی‌فرستد.',
          style: TextStyle(fontSize: 11, color: muted, height: 1.8)),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('اسکن جستجوگر۲ در اطلاعات',
              style: TextStyle(fontSize: 12)),
          subtitle: const Text(
              'پیش‌فرض خاموش؛ روشن‌کردن یعنی خود اپ با هوش جستجوگر ۲ منابع تازه را جستجو و به اپ می‌افزاید.',
              style: TextStyle(fontSize: 11)),
          value: c.finderEnabled,
          onChanged: (v) async {
            await c.setFinderEnabled(v);
            if (mounted) setState(() {});
          }),
      SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('اسکن بدون سرور', style: TextStyle(fontSize: 12)),
          subtitle: const Text(
              'پیش‌فرض خاموش؛ روشن‌کردن یعنی نوسازی و اسکن پس‌زمینه هیچ منبعی از شبکه نمی‌خوانند — نه سرور اسکنر و نه منابع داخلی — و اپ فقط روی دادهٔ همین گوشی می‌ماند.',
              style: TextStyle(fontSize: 11)),
          value: c.scannerServerless,
          onChanged: (v) async {
            await c.setScannerServerless(v);
            if (mounted) setState(() {});
          }),
      infoBox('پیش‌فرض: اطلاعات از سرور می‌آید',
          'تا وقتی هر دو کلید خاموش‌اند، پایگاه منابع در هر نوسازی خوانده می‌شود تا پیوندهای تازهٔ کشف‌شده توسط جستجوگر ۲ شناسایی شوند، و کل دانش هر ۱۲ ساعت یک بار (یا با دکمهٔ پایین) نوسازی می‌شود. اگر «اسکن بدون سرور» را روشن کنید، هیچ‌کدام خوانده نمی‌شود و دکمهٔ نوسازی هم فقط دادهٔ همین گوشی را می‌خواند؛ نه سرور اسکنر و نه منابع داخلی از شبکه خوانده نمی‌شوند.'),
      const SizedBox(height: 4),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        faDigits('منابع ذخیره‌شده: ${c.scannerSourceCount}'
                            ' • موارد دانش: ${c.scannerItemCount}'
                            ' • منابع تازه: ${c.scannerNewSources.length}'),
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                        c.scannerLastKnowledgeFetch.isEmpty
                            ? 'کل دانش هنوز دریافت نشده است.'
                            : 'آخرین دریافت کل دانش: ${dateLabel(DateTime.tryParse(c.scannerLastKnowledgeFetch))}',
                        style: const TextStyle(fontSize: 11, color: muted)),
                    if (c.scannerBusy)
                      const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('در حال دریافت از اسکنر…',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.deepOrange))),
                    if (c.scannerError.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(c.scannerError,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.deepOrange))),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                          onPressed: c.scannerBusy || c.scannerServerless
                              ? null
                              : () async {
                                  await c.refreshScanner(force: true);
                                  if (mounted) setState(() {});
                                },
                          icon: c.scannerBusy
                              ? const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.cloud_download_outlined,
                                  size: 17),
                          label: const Text('دریافت کل دانش همین حالا',
                              style: TextStyle(fontSize: 11))),
                      TextButton.icon(
                          onPressed: () =>
                              openLink(context, ScannerApi.allKnowledgePage),
                          icon: const Icon(Icons.public, size: 16),
                          label: const Text('کل دانش یکجا',
                              style: TextStyle(fontSize: 11))),
                      TextButton.icon(
                          onPressed: () =>
                              openLink(context, ScannerApi.sourcesPage),
                          icon: const Icon(Icons.list_alt_outlined, size: 16),
                          label: const Text('منابع اسکنر',
                              style: TextStyle(fontSize: 11))),
                    ]),
                  ]))),
      const SizedBox(height: 10),
      if (c.scannerNewSources.isEmpty)
        infoBox('منابع تازه',
            'در آخرین دریافت، پیوند تازه‌ای به پایگاه منابع اسکنر افزوده نشده است. چون جستجوگر ۲ منابع جدید می‌یابد، این فهرست با هر نوسازی دوباره بررسی می‌شود.')
      else
        Card(
            child: ExpansionTile(
                dense: true,
                title: Text(
                    faDigits(
                        'منابع تازهٔ کشف‌شده • ${c.scannerNewSources.length} پیوند'),
                    style: const TextStyle(fontSize: 12)),
                subtitle: const Text(
                    'پیوندهایی که جستجوگر ۲ منذ آخرین نوسازی افزوده است',
                    style: TextStyle(fontSize: 10, color: muted)),
                childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final url in c.scannerNewSources.take(60))
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                            onPressed: () => openLink(context, url),
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: Text(url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10)))),
                  if (c.scannerNewSources.length > 60)
                    Text(
                        faDigits(
                            'و ${c.scannerNewSources.length - 60} پیوند دیگر…'),
                        style: const TextStyle(fontSize: 10, color: muted)),
                ])),
      const SizedBox(height: 10),
      const Text('دسته‌بندی دانش',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      const Text(
          'دانش استخراج‌شده بر اساس موضوع دسته‌بندی می‌شود؛ هر مورد با منبع و تاریخ استخراج همراه است.',
          style: TextStyle(fontSize: 11, color: muted, height: 1.8)),
      if (c.scannerTopics.isEmpty)
        infoBox('هنوز دانشی ذخیره نشده',
            'با اولین نوسازی (یا دکمهٔ «دریافت کل دانش همین حالا») دانش قیمت استخراج‌شده از پایگاه اسکنر خوانده و اینجا دسته‌بندی می‌شود.')
      else
        for (final t in c.scannerTopics)
          _ScannerTopicTile(
              topic: t['topic'] as String,
              total: (t['total'] as int?) ?? 0,
              facts: (t['facts'] as int?) ?? 0,
              chunks: (t['chunks'] as int?) ?? 0,
              newest: (t['newest'] as int?) ?? 0),
      const SizedBox(height: 16),
    ]);
  }
}

/// One topic of the scanner knowledge. The items are read only once the tile is
/// opened, so the information tab stays fast with thousands of stored rows.
class _ScannerTopicTile extends StatefulWidget {
  final String topic;
  final int total, facts, chunks, newest;
  const _ScannerTopicTile({
    required this.topic,
    required this.total,
    required this.facts,
    required this.chunks,
    required this.newest,
  });

  @override
  State<_ScannerTopicTile> createState() => _ScannerTopicTileState();
}

class _ScannerTopicTileState extends State<_ScannerTopicTile> {
  List<ScannerItem>? _items;
  bool _loading = false;

  Future<void> _open() async {
    if (_items != null || _loading) return;
    setState(() => _loading = true);
    try {
      // Facts first: they are the concise extractions; chunks are the raw text.
      final facts = await _read('fact');
      final chunks = await _read('chunk');
      if (!mounted) return;
      setState(() {
        _items = [...facts, ...chunks];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<List<ScannerItem>> _read(String kind) async {
    final c = context.findAncestorStateOfType<_ScannerPanelState>()?.widget.c;
    if (c == null) return const [];
    return c.store.scannerItems(
        topic: widget.topic, kind: kind, limit: 25);
  }

  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: 3),
      child: ExpansionTile(
          dense: true,
          onExpansionChanged: (v) {
            if (v) _open();
          },
          title: Text(
              faDigits(
                  '${widget.topic} • ${widget.total} مورد • ${widget.facts} واقعیت'),
              style: const TextStyle(fontSize: 12)),
          subtitle: Text(
              faDigits(
                  'بخش/متن: ${widget.chunks} • جدیدترین: ${dateLabel(DateTime.fromMillisecondsSinceEpoch(widget.newest), time: false)}'),
              style: const TextStyle(fontSize: 10, color: muted)),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text('در حال خواندن…',
                      style: TextStyle(fontSize: 11))),
            for (final i in _items ?? const <ScannerItem>[])
              ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(i.claim,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, height: 1.7)),
                  subtitle: Text(
                      '${i.domain.isEmpty ? 'منبع نامشخص' : i.domain}'
                      '${i.url.isEmpty ? '' : '\n${i.url}'}',
                      style: const TextStyle(fontSize: 10)),
                  onTap:
                      i.url.isEmpty ? null : () => openLink(context, i.url)),
          ]));
}
