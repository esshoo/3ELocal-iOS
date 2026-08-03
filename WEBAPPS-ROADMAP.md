# 3ELocal Web Apps Roadmap

## M01 — Local package runtime — implemented in 0.2.0

- Keep the existing editable local project launcher.
- Add `.3eweb` custom package type.
- Validate and extract local HTML5/JavaScript packages.
- Install packages under versioned application folders.
- Separate application code from persistent app data folders.
- Display installed applications with names, icons and versions.
- Support install, reinstall, update, rollback and uninstall.
- Use a stable loopback origin for each installed app.
- Include install/update test packages.

## M02 — Remote Web Apps — implemented in 0.2.0 build 5

- Add remote URL entries without downloading site content.
- Read web manifests and website icons when permitted.
- Add online/offline status and connection errors.
- Add per-app navigation policies and allowed domains.
- Separate persistent WebKit data for remote application origins on iOS 17 and newer.
- Add app details, storage size and launch-history information.
- Improve Files-app package intake before and after folder connection.

## M03 — Online package downloads — implemented in 0.2.0 build 6

- Download `.3eweb` packages with URLSession.
- Install from direct links and QR codes.
- Add a downloads screen with progress, pause, retry and cancellation.
- Add a private catalog JSON format.
- Compare installed and available versions.
- Add manual update checks and ignored-version state.

## M04 — Package trust and signatures

- Generate `checksums.json` for every package.
- Add Ed25519 package signatures.
- Maintain trusted publisher public keys.
- Add trusted, developer and blocked package states.
- Add developer mode for unsigned local packages.
- Display package permissions before installation.

## M05 — Developer workflow

- Upload `.3eweb` packages from a computer over the local network.
- Reload without cache.
- View JavaScript console messages and failed requests.
- Inspect package files and manifest values.
- Export an installed application as `.3eweb`.
- Export and import application data backups.

## M06 — Restricted JavaScript-to-Swift bridge

- App information and runtime capability checks.
- Import and export documents through system pickers.
- Native sharing.
- Per-app key/value storage.
- Permission prompts for every native capability.
- No arbitrary Swift, shell, native library or filesystem execution.

## Acceptance rule for every milestone

Each milestone must preserve:

- Existing project discovery and local HTTP serving.
- Registry compatibility with 3ELiDAR and 3ERoomElectrical.
- The fixed Bundle ID and URL scheme.
- User project files and installed app data.
- GitHub Actions unsigned IPA generation.


## M05.1 — مكتمل في هذا الفرع

- إدارة مفاتيح Ed25519 على الجهاز.
- Keychain + Face ID.
- صلاحية المفتاح والحزمة.
- توقيع التطبيقات المثبتة وتصديرها.
- استيراد محلي من Files وKeys/Inbox.

## M05.2 — التالي

- نقل `.3ekey` عبر جلسة وضع المطور على الشبكة المحلية باستخدام رمز اقتران مؤقت.
- عدم قبول المفتاح إلا بعد تأكيد صريح على iPhone.
- حذف نسخة النقل فور إدخالها إلى Keychain.
- سجل تدقيق لعمليات إنشاء واستيراد واستخدام المفاتيح.
