import pathlib
p = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js")
txt = p.read_text(encoding="utf-8", errors="ignore")
idx = txt.find("en.mechanics.map")
seg = txt[idx: idx+9000]
# find all occurrences of ").join"
import re
for m in re.finditer(r"\)\.join\(''\)", seg):
    pos = idx + m.start()
    snippet = txt[pos-300: pos+200]
    print(repr(snippet[:500]))
    break

# try to locate the closing divs before join
# Look for last </div> before join
join_pos = txt.find(").join('')", idx)
before = txt[join_pos-800: join_pos+200]
print("--- before join ---")
print(repr(before[-800:]))
