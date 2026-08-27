import os

workspace_dir = r"e:\Descon\descon\VFX\shaders"

for file in os.listdir(workspace_dir):
    if file.endswith(".tres"):
        file_path = os.path.join(workspace_dir, file)
        try:
            with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()
            
            # Check duplicate assignments to nodes/xxx/yyy/node
            assignments = {}
            for line_no, line in enumerate(lines, 1):
                line_strip = line.strip()
                if "=" in line_strip:
                    parts = line_strip.split("=", 1)
                    key = parts[0].strip()
                    if key.startswith("nodes/"):
                        if key in assignments:
                            print(f"DUPLICATE KEY ASSIGNMENT in {file}: Key='{key}' on line {line_no} (already saw on line {assignments[key]})")
                        else:
                            assignments[key] = line_no
        except Exception as e:
            print(f"Error reading {file}: {e}")
