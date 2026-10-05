#!/usr/bin/env python3
"""Use the unchanged, SHA-verified 0.2.1 transport packager; update UX metadata only."""
from pathlib import Path
import runpy
from package_keyboard_app import archive

ROOT = Path(__file__).resolve().parents[1]

def main():
    runpy.run_path(str(ROOT/'tools/package_keyboard_app.py'), run_name='__main__')
    app = ROOT/'out/MouseLink.swiftpm'
    manifest = app/'Package.swift'
    old = 'displayVersion: "0.2.1", bundleVersion: "3"'
    text = manifest.read_text()
    if text.count(old) != 1:
        raise ValueError('Expected previous manifest version exactly once')
    manifest.write_text(text.replace(old, 'displayVersion: "0.3.0", bundleVersion: "4"'))
    project = ROOT/'out/project.yml'
    text = project.read_text().replace('MARKETING_VERSION: 0.2.1', 'MARKETING_VERSION: 0.3.0')
    project.write_text(text.replace('CURRENT_PROJECT_VERSION: 3', 'CURRENT_PROJECT_VERSION: 4'))
    (app/'操作画面と画面端切替.md').write_bytes((ROOT/'docs/continuity-ux.md').read_bytes())
    for name in ['keyboard-enter.md', 'continuity-ux.md']:
        destination = app/'docs'/name
        destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes((ROOT/'docs'/name).read_bytes())
    print('Continuity UX package:', archive(app))

if __name__ == '__main__':
    main()
