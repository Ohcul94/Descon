import os

file_path = r"e:\Descon\descon\tools\MapEditor3D_1_Loby.tscn"

if os.path.exists(file_path):
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    
    # Check if editable paths already exist
    editable_lines = [
        '[editable path="ObjectsRoot/Decorativo3"]',
        '[editable path="ObjectsRoot/Baúl_Personal"]',
        '[editable path="ObjectsRoot/Decorativo1"]',
        '[editable path="ObjectsRoot/Mercado"]'
    ]
    
    missing_lines = [line for line in editable_lines if line not in content]
    
    if missing_lines:
        print(f"Injecting missing editable paths: {missing_lines}")
        # Strip trailing newlines and append
        clean_content = content.rstrip()
        new_content = clean_content + "\n\n" + "\n".join(missing_lines) + "\n"
        with open(file_path, "w", encoding="utf-8") as f:
            f.write(new_content)
        print("Successfully injected editable paths!")
    else:
        print("All editable paths already exist in the file.")
else:
    print(f"File not found: {file_path}")
