import pathlib
t=pathlib.Path(r"E:\Descon\AdminDash\js\renderers.js").read_bytes()
needle=b").join('')"
print(t.count(needle))
for idx in [i for i in range(len(t)) if t[i:i+len(needle)]==needle][:3]:
    print(t[idx-800:idx+200])
    print('---')
