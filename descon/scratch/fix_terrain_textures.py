import re
import os

files_to_fix = [
    r"e:\Descon\descon\tools\MapEditor3D_1_Loby.tscn",
    r"e:\Descon\descon\tools\MapEditor3D_1_Mapa_1.tscn"
]

ext_resource_line = '[ext_resource type="Texture2D" uid="uid://b35ujov50l07d" path="res://assets/Pared Corrompida_Pared+Corrompida_normal.jpg" id="8_normal"]\n'

for file_path in files_to_fix:
    if not os.path.exists(file_path):
        print(f"File not found: {file_path}")
        continue
        
    print(f"Processing: {file_path}")
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Insert the external resource if not already present
    if 'id="8_normal"' not in content:
        # Find the last [ext_resource] line and insert after it
        lines = content.splitlines()
        last_ext_idx = -1
        for idx, line in enumerate(lines):
            if line.startswith("[ext_resource"):
                last_ext_idx = idx
        if last_ext_idx != -1:
            lines.insert(last_ext_idx + 1, ext_resource_line.strip())
            content = "\n".join(lines) + "\n"
        else:
            print("Could not find any [ext_resource] line!")
            continue

    # 2. Replace the normal_texture reference
    content = content.replace(
        'normal_texture = SubResource("ImageTexture_nltq6")',
        'normal_texture = ExtResource("8_normal")'
    )

    # 3. Remove the SubResource ImageTexture_nltq6 block
    # It looks like:
    # [sub_resource type="ImageTexture" id="ImageTexture_nltq6"]
    # image = SubResource("Image_5ewog")
    #
    content = re.sub(
        r'\[sub_resource type="ImageTexture" id="ImageTexture_nltq6"\]\s*image = SubResource\("Image_5ewog"\)\s*',
        '',
        content
    )

    # 4. Remove the SubResource Image_5ewog block
    # It looks like:
    # [sub_resource type="Image" id="Image_5ewog"]
    # data = {
    # "data": PackedByteArray(...)
    # }
    #
    content = re.sub(
        r'\[sub_resource type="Image" id="Image_5ewog"\]\s*data = \{[^\}]*\}\s*',
        '',
        content
    )

    # Write the modified content back
    with open(file_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)
        
    print(f"Successfully optimized: {file_path}")
