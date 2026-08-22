import pathlib
p = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js")
t = p.read_text(encoding="utf-8")
idx = t.find("en.mechanics.map")
# find closing after fields
start = idx
# get 6000 chars
seg = t[idx: idx+8000]
# write raw bytes to file for inspection
open(r"E:\Descon\mechseg.txt","w",encoding="utf-8").write(seg)
print(seg[2000:4000])
