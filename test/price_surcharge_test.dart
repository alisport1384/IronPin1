import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ironpin/data/controller.dart';
import 'package:ironpin/data/store.dart';
import 'package:ironpin/domain/market.dart';
import 'package:ironpin/domain/range_projection.dart';
import 'package:ironpin/domain/row_facts.dart';
import 'package:ironpin/ui/range_page.dart';

/// The optional percentage added to the prices of the prices and range tabs.
///
/// Iran's VAT of 1405 is 10%; road freight there is charged per ton-kilometre
/// (وزن × مسافت × تعرفهٔ تن-کیلومتر) and has no fixed percentage, so the value
/// is adjustable and the default is only the tax. Off by default: a fresh
/// install shows exactly the announced prices.
Quote row(int n) => Quote(
    id: 's$n',
    endpoint: 'catalog',
    seller: 'فروشنده$n',
    title: 'تیرآهن 14',
    category: 'تیرآهن',
    size: '14',
    unit: 'kg',
    amount: 125000,
    currency: 'تومان',
    sourceDateRaw: DateTime.now().toUtc().toIso8601String(),
    fetchedAt: DateTime.now().toUtc(),
    sourceUrl: 'https://example.com');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('off by default; the default value is Iran\'s VAT of 1405', () async {
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    addTearDown(store.close);
    final c = MarketController(store);
    expect(c.priceSurchargeEnabled, isFalse);
    expect(c.priceSurchargePercent, 10);
    expect(c.priceSurchargeFactor, 1);
    expect(c.withPriceSurcharge(1000), 1000);
  });

  test('enabling adds the percentage and the value is adjustable', () async {
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    addTearDown(store.close);
    final c = MarketController(store);
    await c.setPriceSurchargeEnabled(true);
    expect(c.priceSurchargeFactor, closeTo(1.1, 1e-9));
    expect(c.withPriceSurcharge(1000), closeTo(1100, 1e-9));
    await c.setPriceSurchargePercent(25);
    expect(c.withPriceSurcharge(1000), closeTo(1250, 1e-9));
    await c.setPriceSurchargeEnabled(false);
    expect(c.withPriceSurcharge(1000), 1000);
    // A value outside 0..100 is refused, so a typo cannot break every price.
    await c.setPriceSurchargePercent(150);
    expect(c.priceSurchargePercent, 25);
  });

  test('the choice is stored like every other setting', () async {
    final store = await MarketStore.open(
        dbPath: inMemoryDatabasePath, factory: databaseFactoryFfi);
    addTearDown(store.close);
    final c = MarketController(store);
    await c.setPriceSurchargeEnabled(true);
    await c.setPriceSurchargePercent(18);
    expect(await store.setting('surchargeEnabled'), 'true');
    expect(double.tryParse(await store.setting('surchargePercent') ?? ''), 18);
  });

  test('the candidate price of the range tab follows the factor', () {
    final at = DateTime.now().toUtc();
    final plain = candidatePriceText(
        CatalogueItem('k', RowFacts.ofQuote(row(1)).toWire(), at));
    expect(plain, contains('۱۲۵٬۰۰۰'));
    final raised = candidatePriceText(
        CatalogueItem('k2', RowFacts.ofQuote(row(2)).toWire(), at),
        factor: 1.1);
    expect(raised, contains('۱۳۷٬۵۰۰'));
  });
}
