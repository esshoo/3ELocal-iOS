# 3ELocal for iOS

تطبيق iOS لتشغيل مشاريع الويب المحلية، وتثبيت حزم HTML5/JavaScript، وإدارة تطبيقات الويب من مجلد 3E المشترك.

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

## تطبيقات الويب المثبتة — M02

يدعم 3ELocal الآن نوعين من التطبيقات المثبتة إلى جانب المشاريع المحلية:

1. **تطبيق محلي** بصيغة `.3eweb`: تُحفظ ملفات HTML5 وJavaScript على الجهاز وتعمل دون إنترنت.
2. **تطبيق إنترنت**: يحفظ 3ELocal الرابط والاسم والأيقونة وسياسة التنقل، بينما يظل المحتوى على الخادم.

لإضافة تطبيق إنترنت:

```text
التطبيقات → + → إضافة تطبيق من الإنترنت
```

يمكن لـ3ELocal قراءة اسم الموقع ووصفه وأيقوناته من الصفحة وملف Web App Manifest عندما يسمح الخادم بذلك. ويمكن تعديل القيم يدويًا قبل الحفظ.

سياسات التنقل المتاحة:

- نفس الموقع فقط.
- نطاقات محددة.
- أي موقع داخل التطبيق.

على iOS 17 أو أحدث يستخدم كل تطبيق إنترنت مخزن WebKit دائمًا مستقلًا، وبذلك لا تختلط Cookies وLocal Storage بين تطبيقات الإنترنت المختلفة.

تتضمن شاشة تفاصيل التطبيق النوع، الرابط، الحجم، الإصدار، تاريخ التثبيت، آخر تحديث، آخر تشغيل وعدد مرات التشغيل.


## تنزيل التطبيقات ومتجر 3E الخاص — M03

يدعم 3ELocal تنزيل حزم `.3eweb` من روابط HTTPS مباشرة، أو من فهرس تطبيقات خاص بك.

### التنزيل المباشر

```text
التنزيلات → + → لصق رابط HTTPS أو مسح QR → تنزيل → فحص وتثبيت
```

تعرض شاشة التنزيلات التقدم والحجم، وتوفر الإيقاف المؤقت والاستكمال والإلغاء وإعادة المحاولة. يعتمد الاستكمال من نفس الموضع على دعم الخادم لطلبات الاستئناف؛ وإلا قد يعيد iOS التنزيل من البداية.

كل حزمة تُنزّل إلى:

```text
3E/Apps/LocalWeb/Downloads
```

ولا تُثبت إلا بعد مرورها على فاحص الحزم نفسه المستخدم للاستيراد المحلي.

### فهرس التطبيقات

صيغة الفهرس الأساسية:

```json
{
  "schemaVersion": 1,
  "name": "My 3E Catalog",
  "apps": [
    {
      "id": "com.example.myapp",
      "name": "My App",
      "version": "1.0.0",
      "description": "تطبيق ويب محلي",
      "iconURL": "icons/myapp.png",
      "packageURL": "packages/MyApp-1.0.0.3eweb",
      "minimumRuntimeVersion": "0.2.0"
    }
  ]
}
```

يمكن أن تكون `iconURL` و`packageURL` روابط HTTPS كاملة أو روابط نسبية إلى مكان `catalog.json`. يجب أن يكون الفهرس والحزم متاحين من دون تسجيل دخول داخل التطبيق؛ لذلك استخدم مستودعًا عامًا أو خادمًا خاصًا بك يدعم HTTPS.

يتضمن المشروع مجلد `TestCatalog` جاهزًا للنشر واختبار تحديث Hello3E من 1.1.0 إلى 1.2.0.

### روابط 3ELocal

```text
localweb://install?url=<percent-encoded-https-package-url>
localweb://catalog?url=<percent-encoded-https-catalog-url>
```

لا يتم تثبيت أي تحديث بصمت. يعرض التطبيق الإصدار الجديد، ويترك للمستخدم التنزيل أو تجاهل الإصدار المحدد.


## M04 — أمان الحزم

يدعم التطبيق الآن حزم `.3eweb` الموقعة باستخدام Ed25519، ويعرض الناشر الموثوق ويرفض أي ملف تم تعديله بعد التوقيع. توجد تفاصيل إنشاء التوقيع في `SIGNING.md` وخطة التجربة في `M04-TEST-PLAN.md`.


## M05.1 — التوقيع من الآيفون

يمكن الآن إنشاء مفتاح Ed25519 أو استيراد ملف `.3ekey`/PEM من داخل التطبيق. يُنقل المفتاح الخاص إلى Keychain، ويمكن ربط كل عملية توقيع بـFace ID أو رمز الجهاز.

المسار:

```text
الإعدادات
→ إدارة مفاتيح التوقيع
→ إنشاء أو استيراد مفتاح
```

لتوقيع تطبيق مثبت:

```text
التطبيقات
→ تفاصيل التطبيق المحلي
→ توقيع وتصدير من الآيفون
```

تُحفظ الحزمة الناتجة في:

```text
Apps/LocalWeb/Packages/Signed
```

يمكن وضع ملف المفتاح مؤقتًا في `Apps/LocalWeb/Keys/Inbox`. بعد نجاح الاستيراد يحذفه التطبيق من Inbox، بينما يبقى المفتاح الخاص في Keychain. لا تضع ملفات المفاتيح الخاصة في GitHub.

انتهاء صلاحية المفتاح يمنع إنشاء توقيعات جديدة فقط. ويمكن تحديد انتهاء مستقل للحزمة إذا كان المطلوب أن تتوقف الحزمة نفسها بعد يوم أو شهر أو سنة.
