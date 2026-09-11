#!/usr/bin/env python3
"""Write releases/client-manifest.json by READING the versions, never by retyping them.

2026-09-11. The manifest was hand-written into the release command twice, and both times it
omitted `launcher_version` -- the one field BOTH launcher-update paths key off:

  launcher.gd:372   updates itself when manifest launcher_version != its own LAUNCHER_VERSION
  client.gd:35282   replaces the launcher for players still on a pre-self-update one

Each explicitly bails when the field is missing, so the whole self-update capability -- built and
complete on both sides -- sat inert because of an absent line in a file typed by hand. Owner:
*"We historically had a way for the client to download the launcher and effectively self update
it... Is that something we can still do here?"* Yes, and this is why it stopped.

Reads VERSION.txt, RUNTIME_VERSION.txt and launcher.gd's LAUNCHER_VERSION so the three can never
disagree with what actually shipped.
"""
import io, json, os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(path):
    with io.open(os.path.join(root, path), encoding='utf-8') as f:
        return f.read().strip()


def launcher_version():
    src = read('launcher/launcher.gd')
    m = re.search(r'const\s+LAUNCHER_VERSION\s*=\s*"([^"]+)"', src)
    if not m:
        sys.exit('launcher.gd: could not find LAUNCHER_VERSION')
    return m.group(1)


def main():
    v = read('VERSION.txt')
    r = read('RUNTIME_VERSION.txt')
    lv = launcher_version()
    manifest = {
        'content_version': v,
        'runtime_version': r,
        'launcher_version': lv,
        'windows': {
            'pck': 'phantom-badlands-pck-v%s.zip' % v,
            'runtime': 'phantom-badlands-runtime-r%s.zip' % r,
        },
    }
    out = os.path.join(root, 'releases', 'client-manifest.json')
    with io.open(out, 'w', encoding='utf-8') as f:
        f.write(json.dumps(manifest, indent=2) + '\n')
    print('wrote %s' % out)
    print('  content %s | runtime r%s | launcher %s' % (v, r, lv))


if __name__ == '__main__':
    main()
