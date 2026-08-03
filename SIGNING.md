# توقيع حزم 3E Web

يستخدم M04 توقيع **Ed25519** مع بصمة SHA-256 لكل ملف.

كل حزمة موقعة تحتوي على:

```text
manifest.json
checksums.json
signature.json
www/...
```

- `checksums.json`: معرّف التطبيق، الإصدار، وبصمة SHA-256 لكل ملف.
- `signature.json`: هوية الناشر ومفتاحه والتوقيع الرقمي على `checksums.json`.
- يرفض 3ELocal الملفات المفقودة أو المعدلة أو الإضافية غير المشمولة بالتوقيع.

## المفتاح الخاص

المفتاح الخاص موجود فقط داخل ملف `3E-WebApp-Signing-Kit.zip` المنفصل. لا ترفعه إلى GitHub. يحتوي مشروع التطبيق على المفتاح العام فقط في:

```text
Supporting/TrustedPublishers.json
```

## توقيع تطبيق

```bash
python -m pip install -r requirements-signing.txt
python scripts/3eweb_sign.py MyWebApp MyWebApp-1.0.0.3eweb \
  --private-key /secure/path/3E-Publisher-PrivateKey.pem \
  --publisher-id com.essam.3e \
  --publisher-name "3E / Essam" \
  --key-id 3e-main-2026-01
```


# التوقيع من iPhone — M05.1

## استيراد المفتاح الرئيسي

حزمة التوقيع المنفصلة تحتوي ملف `3E-Publisher-PrivateKey.3ekey`. انقله إلى iPhone ثم افتح:

```text
الإعدادات → إدارة مفاتيح التوقيع → اختيار ملف .3ekey
```

أو ضعه في:

```text
Apps/LocalWeb/Keys/Inbox
```

ثم استخدم «استيراد من مجلد Keys/Inbox». بعد الاستيراد يُحفظ المفتاح في Keychain ويُحذف ملف Inbox. ملف `.3ekey` نفسه غير مشفر، لذلك يجب الاحتفاظ بالنسخة الأصلية خارج GitHub وخارج مجلدات المشاركة العامة.

## مدة المفتاح والحزمة

- مدة المفتاح: الفترة التي يُسمح خلالها بإنشاء توقيعات جديدة.
- مدة الحزمة: اختيار مستقل يحدد متى يرفض 3ELocal الحزمة الموقعة.
- الحزم الموقعة قبل انتهاء المفتاح تظل صالحة ما لم يكن للحزمة تاريخ انتهاء خاص.

## التخزين

مفتاح Ed25519 الخام يُخزن كعنصر Keychain من نوع generic password وبخيار `WhenUnlockedThisDeviceOnly`. عند تفعيل الحماية يطلب Keychain حضور المستخدم في كل عملية توقيع. المفتاح لا يوضع داخل مشروع التطبيق ولا داخل `TrustedPublishers.json`.
