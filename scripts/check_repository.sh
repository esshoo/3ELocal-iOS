#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

required=(
  project.yml
  Supporting/Info.plist
  Sources/App/ThreeELocalApp.swift
  Sources/Web/LocalHTTPServer.swift
  Sources/WebApps/WebAppManifest.swift
  Sources/WebApps/WebAppPackageInstaller.swift
  Sources/WebApps/WebAppCatalog.swift
  Sources/WebApps/WebAppDownloadManager.swift
  Sources/UI/WebAppCatalogView.swift
  Sources/UI/WebAppDownloadsView.swift
  Sources/UI/DirectPackageDownloadView.swift
  Sources/UI/QRCodeScannerView.swift
  .github/workflows/build-unsigned-ipa.yml
  TestPackages/Hello3E-v1.0.0.3eweb
  TestPackages/Hello3E-v1.1.0.3eweb
  TestPackages/Hello3E-v1.2.0.3eweb
  TestCatalog/catalog.json
  TestCatalog/packages/Hello3E-v1.2.0.3eweb
  M03-TEST-PLAN.md
)

for file in "${required[@]}"; do
  [[ -f "$file" ]] || { echo "Missing $file" >&2; exit 1; }
done

python3 - <<'PY'
import json
import plistlib
from pathlib import Path
from urllib.parse import urljoin, urlparse
from zipfile import ZipFile

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

catalog=json.loads(Path('TestCatalog/catalog.json').read_text(encoding='utf-8'))
assert catalog['schemaVersion']==1
assert len(catalog['apps'])==1
entry=catalog['apps'][0]
assert entry['version']=='1.2.0'
base='https://example.com/TestCatalog/catalog.json'
for key in ('packageURL','iconURL'):
    resolved=urljoin(base,entry[key])
    assert urlparse(resolved).scheme=='https'
assert Path('TestCatalog/packages/Hello3E-v1.2.0.3eweb').read_bytes() == Path('TestPackages/Hello3E-v1.2.0.3eweb').read_bytes()

manifest_source=Path('Sources/WebApps/WebAppManifest.swift').read_text()
assert 'let updateURL: String?' in manifest_source
assert Path('Sources/WebApps/WebAppDownloadManager.swift').exists()
assert Path('Sources/UI/QRCodeScannerView.swift').exists()
project=Path('project.yml').read_text()
assert 'CURRENT_PROJECT_VERSION: 6' in project
print('Info.plist, M03 catalog, downloads and sample packages OK')
PY

# Parsing checks syntax without requiring the iOS SDK on non-macOS development machines.
while IFS= read -r file; do
  swiftc -frontend -parse "$file"
done < <(find Sources -name '*.swift' -print | sort)

echo "Repository structure and Swift syntax OK"
