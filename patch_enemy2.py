import pathlib
p = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js")
txt = p.read_text(encoding="utf-8")
idx = txt.find("en.mechanics.map")
snippet = txt[idx: idx+4000]
open(r"E:\Descon\snippet.txt","w",encoding="utf-8").write(snippet)
print("wrote snippet")
