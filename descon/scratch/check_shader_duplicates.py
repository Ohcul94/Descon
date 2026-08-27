import os
import re

workspace_dir = r"e:\Descon\descon"

for root, dirs, files in os.walk(workspace_dir):
    # Skip .godot directory
    if ".godot" in root:
        continue
    for file in files:
        if file.endswith(".tres") or file.endswith(".tscn"):
            file_path = os.path.join(root, file)
            try:
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                
                # VisualShader blocks in .tscn or .tres can define nodes like:
                # nodes/fragment/6/node = ...
                # Or sub_resources of type VisualShader having nodes/fragment/6/node = ...
                # Since a tscn/tres can have multiple VisualShader sub_resources, we should track duplicate nodes per sub_resource block.
                # Let's split content by sub_resource or resource blocks
                blocks = re.split(r'(\[sub_resource|\[resource)', content)
                
                current_block_header = ""
                for block in blocks:
                    if block.startswith("[sub_resource") or block.startswith("[resource"):
                        current_block_header = block
                        continue
                    
                    # We are inside a block. Let's see if this block is a VisualShader
                    if "VisualShader" in current_block_header or "type=\"VisualShader\"" in current_block_header:
                        seen_nodes = set()
                        for line in block.splitlines():
                            match = re.search(r'nodes/([^/]+)/(\d+)/node\s*=', line)
                            if match:
                                graph_type = match.group(1)
                                node_id = match.group(2)
                                key = (graph_type, node_id)
                                if key in seen_nodes:
                                    print(f"DUPLICATE NODE ID in {file_path} inside block {current_block_header.strip()}: Graph={graph_type}, ID={node_id}")
                                else:
                                    seen_nodes.add(key)
            except Exception as e:
                print(f"Error reading {file_path}: {e}")
