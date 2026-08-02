# 3ELocal for iOS

تطبيق iOS لتشغيل مشاريع الويب المحلية من مجلد 3E المشترك.

## الهوية الثابتة

| الخاصية | القيمة |
|---|---|
| Display Name | `3ELocal` |
| Bundle ID | `com.essam.3E.localweb` |
| URL Scheme | `localweb://` |
| مجلد التطبيق | `Apps/LocalWeb` |
| App Group مستقبلًا | `group.com.essam.3e` |

## الوظائف الموجودة

- اختيار مجلد `3E` من تطبيق Files وحفظ صلاحية الوصول إليه.
- إنشاء بنية التطبيقات المشتركة بدون حذف الملفات الموجودة.
- تسجيل التطبيق داخل `3E/System/registry.json` مع الحفاظ على سجلات التطبيقات الأخرى.
- اكتشاف مشاريع تحتوي على `index.html` داخل:
  - `3E/Apps/LocalWeb/Projects`
  - `3E/Shared/Projects`
- شبكة مشاريع متكيفة مع iPhone وiPad.
- البحث والمفضلة وآخر المشاريع المفتوحة.
- خادم HTTP محلي مبني على `Network.framework`.
- عرض المشاريع داخل `WKWebView` مع دعم HTML/CSS/JS/WASM والوسائط وطلبات Range.
- مشاركة عنوان المشروع على شبكة Wi-Fi أثناء بقاء التطبيق مفتوحًا.
- استقبال روابط مثل:
  - `localweb://open?path=Apps/LocalWeb/Projects/Hello3E`
  - `localweb://open?path=Shared/Projects/MyProject`
- زر إنشاء مشروع تجريبي من داخل التطبيق.
- تجهيز مباشر لإضافة App Group لاحقًا بدون تغيير بنية المجلدات.

## بنية مجلد 3E

```text
3E/
├── Apps/
│   ├── LiDARLab/
│   ├── RoomElectrical/
│   └── LocalWeb/
│       ├── Projects/
│       ├── Imports/
│       ├── Exports/
│       ├── Cache/
│       └── Settings/
├── Shared/
│   ├── Inbox/
│   ├── Outbox/
│   ├── Projects/
│   └── Media/
└── System/
    └── registry.json
```

## الرفع إلى GitHub من Windows

1. أنشئ مستودعًا جديدًا فارغًا على GitHub.
2. فك ضغط المشروع وارفع **محتويات** مجلد `3ELocal-iOS` إلى جذر المستودع.
3. تأكد أن الملف التالي موجود كما هو:

```text
.github/workflows/build-unsigned-ipa.yml
```

4. افتح تبويب **Actions** في GitHub.
5. اختر **Build Unsigned IPA**.
6. اضغط **Run workflow**.
7. بعد انتهاء البناء افتح التشغيل، ثم نزّل Artifact باسم:

```text
3ELocal-unsigned-ipa
```

داخله ستجد:

```text
3ELocal-unsigned.ipa
BUILD-INFO.txt
xcodebuild.log
```

## التثبيت على iPhone

ملف `3ELocal-unsigned.ipa` غير موقّع ولا يمكن تثبيته مباشرة. مرّره إلى برنامج توقيع يعيد توقيع IPA بشهادة Apple الخاصة بك، ثم ثبّت النسخة الموقعة.

لا تضف App Group أثناء التوقيع التجريبي الحالي. عندما تصبح الشهادة والـProvisioning Profile داعمين لها، أضف:

```text
group.com.essam.3e
```

إلى التطبيقات الثلاثة، ثم أضف مزود App Group في طبقة التخزين.

## إضافة مشروع Web

كل مشروع يجب أن يكون داخل مجلد مستقل ويحتوي على `index.html`، مثل:

```text
3E/Apps/LocalWeb/Projects/MySite/
├── index.html
├── style.css
├── app.js
└── assets/
```

يوجد مشروع مثال داخل `SampleProjects/Hello3E`، ويمكن أيضًا إنشاؤه من زر **إنشاء مشروع تجريبي** داخل التطبيق.

## ملاحظات iOS

- الخادم يعمل أثناء فتح التطبيق. قد يوقف iOS الخادم عند انتقال التطبيق للخلفية أو قفل الشاشة.
- مشاركة الرابط مع جهاز آخر تحتاج وجود الجهازين على شبكة Wi-Fi نفسها.
- المشاريع التي تحتاج Node.js أو PHP أو Python يجب بناؤها مسبقًا ونسخ ملفات `dist` أو `build` الناتجة.
- يمكن تغيير Bundle ID أثناء إعادة التوقيع، لكن إبقاء `com.essam.3E.localweb` يحافظ على الهوية المتفق عليها.

## توليد مشروع Xcode

المستودع يستخدم [XcodeGen](https://github.com/yonaskolb/XcodeGen). يقوم GitHub Actions بتثبيته وإنشاء `ThreeELocal.xcodeproj` تلقائيًا من `project.yml`، لذلك لا تحتاج إلى جهاز Mac لرفع المشروع أو تشغيل عملية البناء.


## Registry compatibility

Version 0.1.2 accepts both `apps` array and app-keyed dictionary formats in `System/registry.json`. It preserves all known and unknown app records and writes the canonical dictionary form.

# 3E Web Apps — v0.2.0-M01

يحتفظ هذا الإصدار بكل وظائف المشاريع المحلية السابقة، ويضيف نوعًا جديدًا هو **التطبيق المثبت**.

## الفرق بين المشروع والتطبيق المثبت

- المشروع المحلي: مجلد تطوير داخل `Apps/LocalWeb/Projects` أو `Shared/Projects` يحتوي على `index.html`.
- التطبيق المثبت: حزمة ZIP منظمة بامتداد `.3eweb` تحتوي على هوية وإصدار وأيقونة وملف بداية.

## بنية حزمة `.3eweb`

```text
MyApp.3eweb
├── manifest.json
├── icon.png
└── www/
    ├── index.html
    ├── app.js
    ├── style.css
    └── assets/
```

مثال `manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "com.essam.3eweb.myapp",
  "name": "My App",
  "version": "1.0.0",
  "description": "تطبيق ويب محلي",
  "icon": "icon.png",
  "entry": "www/index.html",
  "type": "local",
  "minimumRuntimeVersion": "0.2.0"
}
```

## التخزين بعد التثبيت

```text
3E/Apps/LocalWeb/InstalledApps/
└── com.essam.3eweb.myapp/
    ├── app-info.json
    ├── Versions/
    │   ├── 1.0.0/
    │   └── 1.1.0/
    ├── Data/
    ├── Documents/
    ├── Cache/
    └── Backups/
```

تحديث الحزمة يستبدل ملفات الإصدار النشط فقط، ولا يحذف `Data` أو `Documents`.

## اختبار المرحلة الأولى

داخل `TestPackages` توجد حزمتان:

```text
Hello3E-v1.0.0.3eweb
Hello3E-v1.1.0.3eweb
```

خطوات الاختبار:

1. ثبّت `Hello3E-v1.0.0.3eweb` من تبويب **التطبيقات**.
2. افتح التطبيق واضغط زر زيادة العداد عدة مرات.
3. ثبّت `Hello3E-v1.1.0.3eweb`؛ سيظهر كتحديث لنفس التطبيق.
4. افتحه وتأكد أن قيمة العداد بقيت كما هي.
5. اضغط مطولًا على بطاقة التطبيق واختر **الرجوع للإصدار السابق**.
6. اختبر الحذف وتأكد من اختفاء مجلد التطبيق وبياناته.

## إنشاء الحزم التجريبية مجددًا

```bash
python3 scripts/build_sample_3eweb.py
```

## حدود المرحلة الحالية

- النوع المدعوم حاليًا في الحزم هو `local` فقط.
- تطبيقات الروابط البعيدة والتنزيل من متجر 3E ستضاف في المراحل التالية.
- لا يوجد JavaScript-to-Swift bridge في هذه المرحلة.
- ملفات React/Vue/Vite يجب بناؤها أولًا، ثم وضع ملفات `dist` داخل الحزمة.
