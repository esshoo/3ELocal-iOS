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
