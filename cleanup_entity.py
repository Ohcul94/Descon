import os
path = r'e:\Descon\Descon\scripts\entities\Entity.gd'
try:
    with open(path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    if len(lines) >= 525:
        # Mantener líneas 1-456 (índices 0-455) y 526-fin (índices 525+)
        new_lines = lines[:456] + lines[525:]
        with open(path, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)
        print("Success: Entity.gd cleaned surgically.")
    else:
        print("Error: File shorter than expected.")
except Exception as e:
    print(f"Error: {e}")
