#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

required=(
  project.yml
  Supporting/Info.plist
  Supporting/TrustedPublishers.json
  Sources/App/ThreeELocalApp.swift
  Sources/Web/LocalHTTPServer.swift
  Sources/WebApps/WebAppManifest.swift
  Sources/WebApps/WebAppPackageInstaller.swift
  Sources/WebApps/WebAppPackageTrust.swift
  Sources/WebApps/WebAppCatalog.swift
  Sources/WebApps/WebAppDownloadManager.swift
  Sources/UI/WebAppCatalogView.swift
  Sources/UI/KeyboardDismissTapView.swift
  Sources/UI/WebAppDownloadsView.swift
  Sources/UI/DirectPackageDownloadView.swift
  Sources/UI/QRCodeScannerView.swift
  scripts/3eweb_sign.py
  .github/workflows/build-unsigned-ipa.yml
  TestPackages/Hello3E-v1.0.0.3eweb
  TestPackages/Hello3E-v1.1.0.3eweb
  TestPackages/Hello3E-v1.2.0.3eweb
  TestPackages/Hello3E-v1.3.0-Signed.3eweb
  TestPackages/Hello3E-v1.3.0-Tampered.3eweb
  TestCatalog/catalog.json
  TestCatalog/packages/Hello3E-v1.3.0-Signed.3eweb
  M04-TEST-PLAN.md
  SIGNING.md
)

for file in "${required[@]}"; do
  [[ -f "$file" ]] || { echo "Missing $file" >&2; exit 1; }
done

python3 - <<'PY'
import base64
import hashlib
import json
import plistlib
from pathlib import Path
from urllib.parse import urljoin, urlparse
from zipfile import ZipFile

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

with Path('Supporting/Info.plist').open('rb') as f:
    p=plistlib.load(f)
assert p['CFBundleDisplayName']=='3ELocal'
assert p['CFBundleURLTypes'][0]['CFBundleURLSchemes']==['localweb']
assert 'NSCameraUsageDescription' in p
exported=p['UTExportedTypeDeclarations'][0]
assert exported['UTTypeIdentifier']=='com.essam.3e.webapp-package'
assert '3eweb' in exported['UTTypeTagSpecification']['public.filename-extension']

for version in ('1.0.0','1.1.0','1.2.0'):
    package=Path(f'TestPackages/Hello3E-v{version}.3eweb')
    with ZipFile(package) as z:
        names=set(z.namelist())
        assert 'manifest.json' in names
        manifest=json.loads(z.read('manifest.json'))
        assert manifest['schemaVersion']==1
        assert manifest['type']=='local'
        assert manifest['version']==version
        assert manifest['entry'] in names
        assert manifest['icon'] in names

trusted=json.loads(Path('Supporting/TrustedPublishers.json').read_text())
publisher=trusted['publishers'][0]
key_entry=publisher['keys'][0]
public_key=Ed25519PublicKey.from_public_bytes(base64.b64decode(key_entry['publicKey']))

signed=Path('TestPackages/Hello3E-v1.3.0-Signed.3eweb')
with ZipFile(signed) as z:
    manifest=json.loads(z.read('manifest.json'))
    signature=json.loads(z.read('signature.json'))
    checksums_data=z.read('checksums.json')
    checksums=json.loads(checksums_data)
    public_key.verify(base64.b64decode(signature['signature']), checksums_data)
    assert manifest['version']=='1.3.0'
    assert checksums['appID']==manifest['id']
    assert checksums['version']==manifest['version']
    for item in checksums['files']:
        assert hashlib.sha256(z.read(item['path'])).hexdigest()==item['sha256']

# The tampered package retains a valid signature document but at least one file hash must fail.
tampered=Path('TestPackages/Hello3E-v1.3.0-Tampered.3eweb')
with ZipFile(tampered) as z:
    checksums_data=z.read('checksums.json')
    checksums=json.loads(checksums_data)
    signature=json.loads(z.read('signature.json'))
    public_key.verify(base64.b64decode(signature['signature']), checksums_data)
    assert any(hashlib.sha256(z.read(item['path'])).hexdigest()!=item['sha256'] for item in checksums['files'])

catalog=json.loads(Path('TestCatalog/catalog.json').read_text(encoding='utf-8'))
assert catalog['schemaVersion']==1
assert len(catalog['apps'])==1
entry=catalog['apps'][0]
assert entry['version']=='1.3.0'
base='https://example.com/TestCatalog/catalog.json'
for key in ('packageURL','iconURL'):
    resolved=urljoin(base,entry[key])
    assert urlparse(resolved).scheme=='https'
assert Path('TestCatalog/packages/Hello3E-v1.3.0-Signed.3eweb').read_bytes() == signed.read_bytes()

project=Path('project.yml').read_text()
assert 'CURRENT_PROJECT_VERSION: 7' in project
assert 'WebAppPackageVerifier' in Path('Sources/WebApps/WebAppPackageTrust.swift').read_text()
assert 'KeyboardDismissTapView' in Path('Sources/UI/WebAppCatalogView.swift').read_text()
print('Info.plist, M04 signatures, keyboard fix, catalog and samples OK')
PY

while IFS= read -r file; do
  swiftc -frontend -parse "$file"
done < <(find Sources -name '*.swift' -print | sort)

echo "Repository structure and Swift syntax OK"
