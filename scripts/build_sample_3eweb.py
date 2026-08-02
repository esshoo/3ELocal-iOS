#!/usr/bin/env python3
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "TestPackages" / "Sources"
OUTPUT = ROOT / "TestPackages"

for source in sorted(SOURCES.iterdir()):
    if not source.is_dir():
        continue
    manifest = __import__('json').loads((source / 'manifest.json').read_text(encoding='utf-8'))
    destination = OUTPUT / f"Hello3E-v{manifest['version']}.3eweb"
    with ZipFile(destination, 'w', ZIP_DEFLATED) as archive:
        for file in sorted(source.rglob('*')):
            if file.is_file():
                archive.write(file, file.relative_to(source).as_posix())
    print(destination)
