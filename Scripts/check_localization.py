#!/usr/bin/env python3
"""Controlla che ogni testo dell'interfaccia abbia la traduzione inglese.

I testi nel codice sono in italiano e fanno da chiave (vedi
Sources/PizzinuKit/Utilities/Localization.swift). Lo script raccoglie le chiavi
da L("…") e dai testi SwiftUI scritti direttamente, e le confronta con
Resources/en.lproj/Localizable.strings. Esce con errore se ne manca qualcuna.

Uso: python3 Scripts/check_localization.py
"""
import glob, os, re, sys

os.chdir(os.path.join(os.path.dirname(__file__), '..'))
LIT = r'"((?:[^"\\\n]|\\.)*)"'
SWIFTUI = r'(?<![A-Za-z])(?:footerButton|actionButton|Text|Button|Toggle|Section|Picker|Label|LabeledContent|TextField|Stepper|\.help)\('
SKIP = ('DebugSnapshots.swift', 'ExceptionLog.swift', 'Localization.swift')

def unescape(s):
    return s.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')

keys = []
for path in sorted(glob.glob('Sources/Pizzinu/*.swift') + glob.glob('Sources/PizzinuKit/**/*.swift', recursive=True)):
    if path.endswith(SKIP):
        continue
    src = open(path, encoding='utf-8').read()
    found = [m.group(1) for m in re.finditer(r'\bL\(' + LIT, src)]
    found += [m.group(1) for m in re.finditer(SWIFTUI + LIT, src)
              if '\\(' not in m.group(1) and re.search(r'[A-Za-zÀ-ÿ]', m.group(1)) and m.group(1) != 'Pizzinu']
    if path.endswith('MarkdownToolbarView.swift'):
        block = src[src.index('var title: String {'):]
        block = block[:block.index('\n        }\n')]
        found += [m.group(1) for m in re.finditer(r'case \.[a-z]+: ' + LIT, block)]
    for key in found:
        key = unescape(key)
        if key not in keys:
            keys.append(key)
    if path.endswith('AppDelegate.swift'):
        m = re.search(r'let message = """\n(.*?)\n\s*"""', src, re.S)
        if m:
            lines = m.group(1).split('\n')
            indent = min(len(l) - len(l.lstrip()) for l in lines if l.strip())
            keys.append('\n'.join(l[indent:] for l in lines))

strings = open('Resources/en.lproj/Localizable.strings', encoding='utf-8').read()
translated = {unescape(m.group(1)) for m in re.finditer(r'^' + LIT + r' = ', strings, re.M)}
missing = [k for k in keys if k not in translated]
unused = sorted(translated - set(keys) - {'menu.annulla-modifica', 'menu.ripeti-modifica'})
print(f'{len(keys)} testi nel codice, {len(translated)} tradotti in inglese.')
for k in missing:
    print('  senza inglese:', repr(k))
for k in unused:
    print('  tradotto ma non più usato:', repr(k))
sys.exit(1 if missing else 0)
