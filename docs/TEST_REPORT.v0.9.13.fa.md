# گزارش تست نسخهٔ ۰.۹.۱۳ (build 35)

تاریخ اجرا: ۲۹ آبان ۱۴۰۵ (2026-11-21)

```
flutter analyze              -> No issues found!
flutter test --concurrency=1 -> 517 passed, 0 failed
```

## چه چیزی سنجیده شد

- مجموعهٔ کامل ۵۱۷ تست بدون شکست، به‌همراه آزمون‌های تازهٔ این نسخه:
  - `test/price_surcharge_test.dart`: «x درصد اضافه» پیش‌فرض خاموش، مقدار قابل تغییر
    (۰ تا ۱۰۰)، ضریب روی مبالغ و نرخ‌های تب قیمت و تب رنج، و عدم تغییر نرخ اعلامی خود.
  - `test/info_sources_test.dart`: «فهرست منابع» در زبانهٔ «اطلاعات» و کارت‌های نام‌مشترک.
  - `test/revision_test.dart` و `test/manual_history_test.dart`: ارتقای اسکیما به نسخهٔ ۹
    (جدول‌های اسکنر آنلاین) بدون دستکاری قیمت‌ها، تاریخچه و تنظیمات.
- بنچمارک مقیاس (محیط x86):
  - `test/scale_100k_test.dart`:
    - `SCALE_15000`: `initMs=959 sortAscMs=22 searchMs=237 rangeConfirmMs=147 rssMb=335`
    - `SCALE_100000`: `initMs=3803 sortAscMs=274 searchMs=517 rangeConfirmMs=1009 rssMb=717`

## دو کلید زبانهٔ «اطلاعات»

- «اسکن جستجوگر۲ در اطلاعات» و «اسکن بدون سرور» هر دو پیش‌فرض خاموش‌اند.
- پیش‌فرض (هر دو خاموش): پایگاه منابع در هر نوسازی خوانده می‌شود تا پیوندهای تازهٔ
  کشف‌شده توسط جستجوگر ۲ شناسایی شوند و کل دانش هر ۱۲ ساعت یک بار نوسازی می‌شود.
- «اسکن بدون سرور» روشن: هیچ چیزی از سرور اسکنر خوانده نمی‌شود.
- دانش دریافتی فیلتر می‌شود: فقط موارد `attribute=price` و فقط تفاوت با آخرین دریافت.

## ساخت APK و انتشار دو معماری

- `versionName='0.9.13'`, `versionCode='35'`, `minSdk=21`, `targetSdk=35`.
- هر دو APK با فیلتر ABI ساخته شدند و بررسی شدند:
  - `releases/app-armeabi-v7a-release.apk` — `lib/armeabi-v7a/*` (۶ مورد)، ۱۴٫۰MB
    - `sha256 = 140f79c1e48750d16e08b07797ef1b1560ff2c4833669ceb840092aa8307708e`
  - `releases/app-arm64-v8a-release.apk` — `lib/arm64-v8a/*` (۶ مورد)، ۱۴٫۶MB
    - `sha256 = 0ff0fbeedd2488d5aca031ff328a45586b64f7abb5b634b082b631b155bdf962`
  - هر دو دارای `assets/tessdata/fas.traineddata` و `eng.traineddata`.
- امضا و انتشار رسمی در GitHub Release با کلید ثابت پروژه.

## آزمایش‌نشده

- تست تعاملی روی گوشی واقعی اندرویدی پس از دریافت فایل نهایی با کاربر است.
