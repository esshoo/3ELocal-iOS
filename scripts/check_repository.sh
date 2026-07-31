#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

required=(
  project.yml
  Supporting/Info.plist
  Sources/App/ThreeELocalApp.swift
  Sources/Web/LocalHTTPServer.swift
  .github/workflows/build-unsigned-ipa.yml
)

for file in "${required[@]}"; do
  [[ -f "$file" ]] || { echo "Missing $file" >&2; exit 1; }
done

python3 - <<'PY'
import plistlib
from pathlib import Path
with Path('Supporting/Info.plist').open('rb') as f:
    p=plistlib.load(f)
assert p['CFBundleDisplayName']=='3ELocal'
assert p['CFBundleURLTypes'][0]['CFBundleURLSchemes']==['localweb']
print('Info.plist OK')
PY

echo "Repository structure OK"
