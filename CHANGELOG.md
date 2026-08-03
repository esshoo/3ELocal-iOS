# Changelog

## 0.2.0-M05.1 — On-device package signing

- Added generation of Ed25519 publisher keys directly on iPhone.
- Added import of `.3ekey` and PKCS#8 Ed25519 PEM keys from Files or `Apps/LocalWeb/Keys/Inbox`.
- Private key material is transferred into iOS Keychain and optionally protected by Face ID/device passcode.
- Added selectable key lifetimes: one day, 7 days, 30 days, one year, or lifetime.
- Added optional signed-package validity independent from key lifetime.
- Added signing and export of an installed local app to `Apps/LocalWeb/Packages/Signed`.
- Added schema 2 checksums with signed time, key validity, and optional package expiration covered by the Ed25519 signature.
- Added dynamic trust for public keys imported/generated on the device while preserving the bundled trusted-publisher list.
- Deleting a private key preserves its public key so previously signed packages can still be verified.
- Added Face ID purpose string and new key-management UI.
- Build number increased to 8.

## 0.2.0-M04 — Trusted Packages and Keyboard Fix

- أصلح بقاء لوحة مفاتيح رابط المتجر ومنع الخروج من الشاشة.
- أضاف زر تم، submit، السحب والضغط خارج الحقل لإخفاء لوحة المفاتيح.
- أضاف توقيع Ed25519 لحزم `.3eweb`.
- يتحقق من SHA-256 لكل ملف ويرفض الحزم المعدلة أو الملفات الإضافية.
- أضاف قائمة ناشرين موثوقين ومفتاحًا عامًا مدمجًا.
- أضاف حالة الثقة والناشر ومفتاح التوقيع إلى بطاقات وتفاصيل التطبيقات.
- أضاف وضع مطور اختياريًا للحزم غير الموقعة.
- يمنع استبدال تطبيق موثوق بحزمة غير موقعة.
- أضاف أداة Python لتوقيع الحزم وحزمة اختبار موقعة وأخرى معدلة.

## 0.2.0-M03 — Online Packages and Private Catalog

- Added direct HTTPS `.3eweb` package downloads with progress display.
- Added pause, resume, cancel and retry controls using URLSession resume data when supported by the server.
- Added persistent discovery of completed package files in `Apps/LocalWeb/Downloads` after relaunch.
- Added QR scanning for package links with an explicit camera permission description.
- Added a private `catalog.json` format with relative package and icon URLs.
- Added catalog search, runtime compatibility checks and manual refresh.
- Added installed-versus-available version comparison and update badges.
- Added ignored-version state that persists per app and only hides the selected version.
- Added safe install-after-download through the existing `.3eweb` validator.
- Added `localweb://install?url=` and `localweb://catalog?url=` deep links.
- Added the Hello3E 1.2.0 online-update test package and a publishable test catalog.
- Increased the internal build number to 6.

## 0.2.0-M02 — Remote Web Apps

- Added remote web applications that run from HTTPS URLs without downloading the website.
- Added optional website metadata discovery from HTML and Web App Manifest files.
- Added custom app name, description and icon selection.
- Added local/remote filtering and online/offline badges in the application library.
- Added per-app navigation policies: same host, declared domains or unrestricted.
- Added external-link handoff to the system browser when navigation is blocked.
- Added a persistent, isolated WebKit data store per remote app on iOS 17 and newer.
- Added connection-error banners and offline recovery UI.
- Added an application details screen with storage size, install/update dates and launch history.
- Added reliable `.3eweb` intake from the Files app, including pending imports before the 3E folder reconnects.
- Increased the internal build number to 5.

## 0.1.2

- Added compatibility with both historical `registry.json` app formats: array and dictionary.
- Preserves 3ELiDAR and 3ERoomElectrical records instead of replacing them when an older array registry is found.
- Canonicalizes the next write to an app-keyed dictionary and coordinates writes with `NSFileCoordinator`.
- Increased the internal build number to 3.

## 0.1.1

- Fixed the Swift actor-isolation build error in `ThreeEStorageManager`.
- Ensured the GitHub Actions `build` directory exists before writing `xcodebuild.log`.
- Added automatic upload of the build log when the workflow fails.
- Increased the internal build number to 2.
