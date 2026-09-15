import os
import shutil
import json
import struct
import numpy as np

def fix_glb_normals(path):
    print(f"\n==========================================")
    print(f"Procesando: {path}")
    
    with open(path, 'rb') as f:
        magic = f.read(4)
        if magic != b'glTF':
            print("  ERROR: No es un archivo GLB valido.")
            return False
        version, total_len = struct.unpack('<II', f.read(8))
        json_len, json_type = struct.unpack('<II', f.read(8))
        json_bytes = f.read(json_len)
        data = json.loads(json_bytes.decode('utf-8'))
        
        bin_len, bin_type = struct.unpack('<II', f.read(8))
        bin_data = bytearray(f.read(bin_len))
        
    accessors = data.get('accessors', [])
    buffer_views = data.get('bufferViews', [])
    buffers = data.get('buffers', [])
    materials = data.get('materials', [])
    
    # Asegurar doubleSided = False en los materiales para consistencia con Enemigo 2
    for mat in materials:
        if 'doubleSided' in mat:
            mat['doubleSided'] = False
            
    modified = False
    
    for mesh_idx, mesh in enumerate(data.get('meshes', [])):
        for prim_idx, prim in enumerate(mesh.get('primitives', [])):
            attrs = prim.get('attributes', {})
            if 'NORMAL' in attrs:
                print(f"  Mesh {mesh_idx} Prim {prim_idx}: Ya tiene NORMAL, saltando.")
                continue
                
            pos_acc_idx = attrs.get('POSITION')
            indices_acc_idx = prim.get('indices')
            if pos_acc_idx is None or indices_acc_idx is None:
                print(f"  Mesh {mesh_idx} Prim {prim_idx}: No tiene POSITION o indices, saltando.")
                continue
                
            pos_acc = accessors[pos_acc_idx]
            pos_count = pos_acc['count']
            pos_bv = buffer_views[pos_acc['bufferView']]
            pos_offset = pos_bv.get('byteOffset', 0) + pos_acc.get('byteOffset', 0)
            
            # Leer posiciones
            positions = []
            for v_i in range(pos_count):
                o = pos_offset + v_i * 12
                x, y, z = struct.unpack_from('<fff', bin_data, o)
                positions.append((x, y, z))
            positions = np.array(positions, dtype=np.float32)
            
            # Leer índices
            ind_acc = accessors[indices_acc_idx]
            ind_count = ind_acc['count']
            ind_bv = buffer_views[ind_acc['bufferView']]
            ind_offset = ind_bv.get('byteOffset', 0) + ind_acc.get('byteOffset', 0)
            ind_type = ind_acc['componentType']
            
            indices = []
            if ind_type == 5123: # UNSIGNED_SHORT
                for i in range(ind_count):
                    idx = struct.unpack_from('<H', bin_data, ind_offset + i * 2)[0]
                    indices.append(idx)
            elif ind_type == 5125: # UNSIGNED_INT
                for i in range(ind_count):
                    idx = struct.unpack_from('<I', bin_data, ind_offset + i * 4)[0]
                    indices.append(idx)
            else:
                print(f"  Tipo de indice no soportado: {ind_type}")
                continue
                
            indices = np.array(indices, dtype=np.int32).reshape(-1, 3)
            
            # Calcular normales por cara (ponderadas por doble área via cross product)
            v0 = positions[indices[:, 0]]
            v1 = positions[indices[:, 1]]
            v2 = positions[indices[:, 2]]
            face_normals = np.cross(v1 - v0, v2 - v0)
            
            normals = np.zeros_like(positions, dtype=np.float32)
            for tri_i in range(len(indices)):
                fn = face_normals[tri_i]
                fn_len = np.linalg.norm(fn)
                if fn_len > 1e-8:
                    normals[indices[tri_i, 0]] += fn
                    normals[indices[tri_i, 1]] += fn
                    normals[indices[tri_i, 2]] += fn
                    
            # Normalizar vectores de vértice
            norm_lens = np.linalg.norm(normals, axis=1, keepdims=True)
            norm_lens[norm_lens < 1e-8] = 1.0
            normals = normals / norm_lens
            
            normals_bytes = normals.astype('<f4').tobytes()
            
            # Alinear bin_data a 4 bytes
            rem = len(bin_data) % 4
            if rem > 0:
                bin_data.extend(b'\x00' * (4 - rem))
                
            norm_bv_offset = len(bin_data)
            norm_bv_length = len(normals_bytes)
            bin_data.extend(normals_bytes)
            
            norm_bv_idx = len(buffer_views)
            buffer_views.append({
                'buffer': 0,
                'byteOffset': norm_bv_offset,
                'byteLength': norm_bv_length,
                'target': 34962 # ARRAY_BUFFER
            })
            
            min_vals = normals.min(axis=0).tolist()
            max_vals = normals.max(axis=0).tolist()
            
            norm_acc_idx = len(accessors)
            accessors.append({
                'bufferView': norm_bv_idx,
                'byteOffset': 0,
                'componentType': 5126,
                'count': pos_count,
                'type': 'VEC3',
                'max': max_vals,
                'min': min_vals
            })
            
            attrs['NORMAL'] = norm_acc_idx
            modified = True
            print(f"  Mesh {mesh_idx} Prim {prim_idx}: Normales generadas ({pos_count} vertices).")

    if not modified:
        print("  Sin cambios necesarios.")
        return False
        
    buffers[0]['byteLength'] = len(bin_data)
    
    new_json_bytes = json.dumps(data, separators=(',', ':')).encode('utf-8')
    pad_json = (4 - (len(new_json_bytes) % 4)) % 4
    new_json_bytes += b' ' * pad_json
    
    pad_bin = (4 - (len(bin_data) % 4)) % 4
    bin_data.extend(b'\x00' * pad_bin)
    
    total_file_len = 12 + 8 + len(new_json_bytes) + 8 + len(bin_data)
    
    # Crear backup
    bak_path = path + ".bak"
    if not os.path.exists(bak_path):
        shutil.copy2(path, bak_path)
        print(f"  Backup creado: {bak_path}")
        
    # Escribir archivo actualizado
    with open(path, 'wb') as f:
        f.write(b'glTF')
        f.write(struct.pack('<II', 2, total_file_len))
        f.write(struct.pack('<II', len(new_json_bytes), 0x4E4F534A))
        f.write(new_json_bytes)
        f.write(struct.pack('<II', len(bin_data), 0x004E4942))
        f.write(bin_data)
        
    print(f"  OK: Archivo actualizado con normales ({total_file_len} bytes)")
    return True

if __name__ == '__main__':
    targets = [
        # Naves Jugadores
        'e:/Descon/descon/assets/Personajes/3D/Nave1/futuristic+jet+3d+model_Clone1.glb',
        'e:/Descon/descon/assets/Personajes/3D/Nave2/Nave2.glb',
        'e:/Descon/descon/assets/Personajes/3D/Nave3/Nave3.glb',
        'e:/Descon/descon/assets/Personajes/3D/Nave4/Nave4.glb',
        'e:/Descon/descon/assets/Personajes/3D/Nave5/Nave5.glb',
        'e:/Descon/descon/assets/Personajes/3D/Nave6/Nave6.glb',
        'e:/Descon/descon/assets/Personajes/Assets 3D/futuristic+jet+3d+model.glb',
        # Enemigos
        'e:/Descon/descon/assets/Enemigos/3D/Enemigo1/Enemigo1.glb',
        'e:/Descon/descon/assets/Enemigos/3D/Enemigo5/Enemigo5.glb',
        'e:/Descon/descon/assets/Enemigos/3D/Enemigo8/Enemigo8.glb',
        # Bosses
        'e:/Descon/descon/assets/Enemigos/3D/Bosses/Boss1/Boss1.glb',
        'e:/Descon/descon/assets/Enemigos/3D/Bosses/Boss2/Boss2.glb',
        'e:/Descon/descon/assets/Enemigos/3D/Bosses/Boss3/Boss3.glb',
        # Esferas orbitales
        'e:/Descon/descon/assets/Esferas/3D/EsferaAmarilla/EsferaAmarilla.glb',
        'e:/Descon/descon/assets/Esferas/3D/EsferaAzul/EsferaAzul.glb',
        'e:/Descon/descon/assets/Esferas/3D/EsferaRoja/EsferaRoja.glb',
        'e:/Descon/descon/assets/Esferas/3D/EsferaVerde/EsferaVerde.glb'
    ]
    
    success_count = 0
    for target in targets:
        if os.path.exists(target):
            if fix_glb_normals(target):
                success_count += 1
        else:
            print(f"No encontrado: {target}")
            
    print(f"\nProceso finalizado. Total actualizados: {success_count}/{len(targets)}")
