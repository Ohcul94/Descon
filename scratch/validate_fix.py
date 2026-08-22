import pathlib
t = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js").read_text(encoding="utf-8")
for bad in ["[type]", "[idx]", "[name]", "[i]", "[listName]", "[enemyId]"]:
    c = t.count(bad)
    if c:
        print("LITERAL leftover", bad, c)
print("vol-input count:", t.count("vol-input"))
print("vol-slider count:", t.count("vol-slider"))
# verify line 39 now uses interpolated listName
for i, line in enumerate(t.splitlines(), 1):
    if "mech-override-vol" in line and "oninput" in line:
        print("L39 snippet:", line[line.find("config.enemyModels"):line.find("config.enemyModels")+90])
