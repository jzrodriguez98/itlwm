#!/usr/bin/env python3
"""Regenerate the BTLEAdvFixup pattern table inside tools/check-my-mac.pl from BTLEAdvFixup/BTLEAdvPatches.hpp.

  python3 tools/gen_check_my_mac.py          rewrite the generated block
  python3 tools/gen_check_my_mac.py --check  exit 1 if the block is out of date (used by tools/test_awdl.py)
  python3 tools/gen_check_my_mac.py --imports DIR
                                             also rewrite the import lists from DIR/<target>/AirportItlwm.kext

Each entry is (kext build, site, pattern name, find bytes, replace bytes). Like the kext, which tries every pattern of its build on
every page, the checker reports per site which pattern matched.
"""
import re, sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
header = (root / 'BTLEAdvFixup/BTLEAdvPatches.hpp').read_text()
script = root / 'tools/check-my-mac.pl'
BEGIN, END = '# BEGIN GENERATED PATTERNS (tools/gen_check_my_mac.py)', '# END GENERATED PATTERNS'

body = header.split('#if !defined(BTLEADV_SEQUOIA) && !defined(BTLEADV_SONOMA)', 1)[1]
tahoe, rest = body.split('\n#elif defined(BTLEADV_SEQUOIA)\n', 1)
sequoia, rest = rest.split('\n#else\n', 1)
sonoma = rest.split('\n#endif', 1)[0]

entries = []
for build, section in (('tahoe', tahoe), ('sequoia', sequoia), ('sonoma', sonoma)):
    arrays = {name: bytes(int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', values))
              for name, values in re.findall(r'static const uint8_t (\w+)\[\] = \{(.*?)\};', section, re.S)}
    for name, data in arrays.items():
        if 'Find' in name:
            entries.append((build, name.split('Find')[0], name, data, arrays[name.replace('Find', 'Replace')]))

lines = [BEGIN, 'our @KNOWN = (']
for build, site, name, data, rep in entries:
    lines.append("    ['%s', '%s', '%s', '%s', '%s']," % (build, site, name, data.hex(), rep.hex()))
lines += [');', END]
block = '\n'.join(lines)

text = script.read_text()
start, stop = text.index(BEGIN), text.index(END) + len(END)
updated = text[:start] + block + text[stop:]
if '--imports' in sys.argv:
    import base64, gzip, subprocess
    d = Path(sys.argv[sys.argv.index('--imports') + 1])
    IB, IE = '# BEGIN GENERATED IMPORTS (tools/gen_check_my_mac.py --imports DIR)', '# END GENERATED IMPORTS'
    rows = [IB, 'our %IMPORTS = (']
    for t in ('tahoe', 'sequoia', 'sonoma'):
        out = subprocess.run(['nm', '-u', str(d / t / 'AirportItlwm.kext/Contents/MacOS/AirportItlwm')],
                             check=True, capture_output=True, text=True).stdout
        names = '\n'.join(sorted(set(out.split()))).encode()
        blob = base64.b64encode(gzip.compress(names, mtime=0)).decode()
        rows.append('    %s => \'%s\',' % (t, blob))
    rows += [');', IE]
    a, b = updated.index(IB), updated.index(IE) + len(IE)
    updated = updated[:a] + '\n'.join(rows) + updated[b:]
if '--check' in sys.argv:
    if updated != text:
        raise SystemExit('tools/check-my-mac.pl: generated pattern block is out of date; run tools/gen_check_my_mac.py')
    print('check-my-mac.pl pattern table: up to date (%d patterns)' % len(entries))
else:
    script.write_text(updated)
    print('wrote %d patterns' % len(entries))
