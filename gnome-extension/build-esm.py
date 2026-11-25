#!/usr/bin/env python3
"""Assemble the GNOME 45+ build of the panel extension (ES modules).
  gnome-extension/build-esm.py [out-dir]      default: gnome-extension/build/glob@living-sky
The pet drawing in glob@living-sky/pets/ is written for GNOME 42-44 (`imports.cairo`, `var def`);
this copies esm/extension.js + esm/metadata.json and turns each pets/*.js into a module
(`import Cairo from 'cairo'`, an `export {...}` line). install.sh runs it on GNOME 45 and newer.
"""
import os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'glob@living-sky')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'build', 'glob@living-sky')

shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(os.path.join(OUT, 'pets'))
for f in ('extension.js', 'metadata.json'):
    shutil.copy(os.path.join(HERE, 'esm', f), os.path.join(OUT, f))
for name in sorted(os.listdir(os.path.join(SRC, 'pets'))):
    if not name.endswith('.js'):
        continue
    s = open(os.path.join(SRC, 'pets', name)).read()
    s = s.replace("const Cairo = imports.cairo;", "import Cairo from 'cairo';")
    if re.search(r'^[^/\n]*\bimports\.', s, re.M):    # code (not comments) still on the old system
        sys.exit('build-esm: %s still uses imports.*' % name)
    exported = re.search(r'/\* exported ([^*]+)\*/', s)
    names = [n.strip() for n in exported.group(1).split(',')] if exported else []
    s = re.sub(r"^'use strict';\n", '', s, flags=re.M)        # modules are strict anyway
    s += '\nexport {%s};\n' % ', '.join(names)
    open(os.path.join(OUT, 'pets', name), 'w').write(s)
print(OUT)
