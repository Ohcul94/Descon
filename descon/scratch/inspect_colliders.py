import glob
import re

for path in glob.glob('tools/MapEditor3D_*.tscn'):
    try:
        with open(path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading {path}: {e}")
        continue
        
    parents = re.findall(r'parent="([^"]+)"', content)
    sub_parents = []
    for p in parents:
        parts = p.split('/')
        # If it is a child of an instanced node under ObjectsRoot (e.g. ObjectsRoot/Mercado)
        if len(parts) >= 2 and parts[0] == 'ObjectsRoot':
            sub_parents.append(p)
            
    if sub_parents:
        print(f"File: {path}")
        unique_parents = sorted(list(set(sub_parents)))
        for parent in unique_parents:
            # Check if there is an editable line for this parent
            editable_tag = f'[editable path="{parent}"]'
            has_tag = editable_tag in content
            print(f"  Parent: {parent} -> Has editable tag? {has_tag}")
