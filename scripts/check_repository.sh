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
  Sources/WebApps/RemoteWebAppInstaller.swift
  Sources/WebApps/RemoteWebAppMetadataFetcher.swift
  Sources/Web/NetworkStatusMonitor.swift
  Sources/Web/WebAppDataStoreIdentifier.swift
  Sources/UI/InstalledWebAppsView.swift
  Sources/UI/RemoteWebAppEditorView.swift
  Sources/UI/InstalledWebAppDetailsView.swift
  .github/workflows/build-unsigned-ipa.yml
  TestPackages/Hello3E-v1.0.0.3eweb
  TestPackages/Hello3E-v1.1.0.3eweb
)

for file in "${required[@]}"; do
  [[ -f "$file" ]] || { echo "Missing $file" >&2; exit 1; }
done

python3 - <<'PY'
import json
import plistlib
from pathlib import Path
from zipfile import ZipFile

with Path('Supporting/Info.plist').open('rb') as f:
    p=plistlib.load(f)
assert p['CFBundleDisplayName']=='3ELocal'
assert p['CFBundleURLTypes'][0]['CFBundleURLSchemes']==['localweb']
exported=p['UTExportedTypeDeclarations'][0]
assert exported['UTTypeIdentifier']=='com.essam.3e.webapp-package'
assert '3eweb' in exported['UTTypeTagSpecification']['public.filename-extension']

for package in [Path('TestPackages/Hello3E-v1.0.0.3eweb'), Path('TestPackages/Hello3E-v1.1.0.3eweb')]:
    with ZipFile(package) as z:
        names=set(z.namelist())
        assert 'manifest.json' in names
        manifest=json.loads(z.read('manifest.json'))
        assert manifest['schemaVersion']==1
        assert manifest['type']=='local'
        assert manifest['entry'] in names
        assert manifest['icon'] in names
source = Path('Sources/WebApps/WebAppManifest.swift').read_text()
assert 'case remote' in source
assert 'NavigationPolicy' in source
assert Path('M02-TEST-PLAN.md').exists()
project = Path('project.yml').read_text()
assert 'CURRENT_PROJECT_VERSION: 5' in project
print('Info.plist, sample packages and M02 sources OK')
PY

swiftc -frontend -parse $(find Sources -name '*.swift' -print)

echo "Repository structure and Swift syntax OK"
