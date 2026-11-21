import lupa.lua54 as L, sys, json, os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
H = os.path.dirname(os.path.abspath(__file__)) + '/'

def rt(fw, side):
    r = L.LuaRuntime(unpack_returned_tuples=True)
    g = r.globals(); g.ROOT_DIR = ROOT; g.FRAMEWORK = fw; g.SIDE = side
    r.execute(open(H + 'fivem.lua', encoding='utf-8').read())
    r.execute(open(H + 'frameworks.lua', encoding='utf-8').read())
    return r

total = ok = 0; out = {}
tests_src = open(H + 'tests.lua', encoding='utf-8').read()
for fw in ['esx', 'qb', 'qbx']:
    r = rt(fw, 'server'); r.globals().LIST_ONLY = True
    names = list(r.execute(tests_src).values())
    print('=====', fw.upper())
    for n in names:
        r = rt(fw, 'server' if n.startswith('S') else 'client'); r.globals().ONLY = n
        checks = [dict(name=c['name'], ok=bool(c['ok']), detail=c['detail']) for c in r.execute(tests_src).values()]
        good = all(c['ok'] for c in checks)
        print(('OK  ' if good else 'KO  ') + n)
        for c in checks:
            total += 1; ok += c['ok']
            if not c['ok'] or '-v' in sys.argv: print('    ', '✔' if c['ok'] else '✘', c['name'], '—', c['detail'])
        out[fw + ':' + n] = checks
print(f'TOTAL {ok}/{total}')
json.dump(out, open(H + 'results.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
code = 0 if ok == total else 1
if '--ui' in sys.argv:     # + la page des dialogues dans Chromium (npm install playwright)
    import subprocess
    code |= subprocess.call(['node', H + 'ui.test.js'])
sys.exit(code)
