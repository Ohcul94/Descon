import bpy
from mathutils import Vector

def centrar_pivote_en_base_y_mover_al_origen():
    """
    Función que calcula la base geométrica (punto más bajo) de cada objeto seleccionado, 
    le asigna el pivote en ese lugar exacto y luego traslada todo el objeto para 
    que ese pivote quede anclado en las coordenadas absolutas (0, 0, 0) del mundo.
    Esto permite que al escalar, el modelo crezca solo hacia arriba sin hundirse en el piso.
    """
    # Validamos estar en Modo Objeto para poder operar sobre las mallas sin errores de contexto
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')

    # Filtramos la selección actual, aislando solo las mallas (MESH)
    objetos_seleccionados = [obj for obj in bpy.context.selected_objects if obj.type == 'MESH']
    
    if not objetos_seleccionados:
        print("Error: No hay objetos MESH seleccionados para procesar.")
        return

    # Guardamos la posición del cursor 3D para restaurarlo al final
    cursor_original = bpy.context.scene.cursor.location.copy()

    print("--- INICIANDO AJUSTE DE PIVOTE Y TRASLADO AL ORIGEN ---")
    
    for obj in objetos_seleccionados:
        # Aislamos la selección para operar sobre un objeto a la vez
        bpy.ops.object.select_all(action='DESELECT')
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)

        # 1. Aplicamos transformaciones previas (rotación y escala)
        # Fundamental para que los cálculos de la caja delimitadora (Bounding Box) sean reales.
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        
        # 2. Obtenemos los 8 vértices de la caja delimitadora en espacio local
        bbox = [Vector(v) for v in obj.bound_box]
        
        # 3. Calculamos el centro geométrico en los ejes X e Y promediando los vértices
        centro_x = sum(v.x for v in bbox) / 8.0
        centro_y = sum(v.y for v in bbox) / 8.0
        
        # 4. Buscamos el vértice más bajo en el eje Z para determinar la "base" del modelo
        min_z = min(v.z for v in bbox)
        
        # Armamos el vector tridimensional de la base en el espacio local
        base_local = Vector((centro_x, centro_y, min_z))
        
        # 5. Convertimos esa coordenada local a espacio global usando la matriz del mundo del objeto
        base_global = obj.matrix_world @ base_local
        
        # 6. Desplazamos el cursor 3D de Blender a esa coordenada global de la base
        bpy.context.scene.cursor.location = base_global
        
        # 7. Asignamos el Origen (Pivote) a la posición actual del Cursor 3D
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        
        # 8. MUDANZA FINAL: Trasladamos el objeto a la coordenada absoluta cero del mundo.
        # Como el pivote ahora es la base inferior, el objeto quedará apoyado exactamente sobre la grilla Z=0.
        obj.location = (0.0, 0.0, 0.0)
        
        print(f"Pivote en base y trasladado a (0,0,0) con éxito: {obj.name}")

    # Restauramos la selección que tenías al principio para mantener tu flujo de trabajo
    for obj in objetos_seleccionados:
        obj.select_set(True)

    # Devolvemos el cursor 3D a donde estaba antes de ejecutar el código
    bpy.context.scene.cursor.location = cursor_original

# --- BLOQUE DE EJECUCIÓN PRINCIPAL ---
if __name__ == "__main__":
    centrar_pivote_en_base_y_mover_al_origen()
    print("--- PROCESO FINALIZADO ---")