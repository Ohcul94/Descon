import pathlib
p = pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js")
t = p.read_text(encoding="utf-8")
old = "['${enemyId}'][listName]"
new = "['${enemyId}'][${listName}]"
cnt = t.count(old)
print("occurrences of broken pattern:", cnt)
t2 = t.replace(old, new)
p.write_text(t2, encoding="utf-8")
print("remaining broken:", t2.count(old), "| fixed:", cnt)
