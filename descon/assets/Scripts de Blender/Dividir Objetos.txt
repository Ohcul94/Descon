#Con los objetos ya divididos y Renombrados (Hacerlo Manualmente)
#1-Pone Punto de Origen en Vector mas bajo del eje Z.
#2-Agrupa todos los objetos al punto 0,0,0.
#3-Exporta en formato .GLB cada objeto por separado con su respectivo Nombre del Inspector.
import bpy
import os
from mathutils import Vector

def centrar_pivote_en_base_y_exportar(ruta_destino):
    """
    Función que toma cada objeto, calcula su base más baja usando su Bounding Box, 
    coloca el punto de origen (pivote) exactamente ahí, lo mueve al 0,0,0
    y lo exporta respetando su nombre.
    """
    # Validamos que estemos en Modo Objeto para evitar errores al procesar mallas
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')

    # Obtenemos únicamente las mallas de la escena
    objetos_escena = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    
    if not objetos_escena:
        print("Error: No se encontraron objetos tipo MESH en la escena para procesar.")
        return

    # Comprobamos si el directorio de destino existe
    if not os.path.exists(ruta_destino):
        os.makedirs(ruta_destino)

    # Guardamos la posición original del cursor 3D para ser prolijos y no dejártelo perdido por ahí
    cursor_original = bpy.context.scene.cursor.location.copy()

    print("--- INICIANDO ASIGNACIÓN DE PIVOTES Y EXPORTACIÓN ---")
    
    for obj in objetos_escena:
        # Limpiamos la selección global y dejamos solo el objeto actual
        bpy.ops.object.select_all(action='DESELECT')
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)

        # 1. Aplicamos transformaciones previas (escala y rotación)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        
        # 2. Calculamos el punto central inferior (base) de la geometría
        # El bound_box devuelve las 8 esquinas de la caja delimitadora en espacio local
        bbox = [Vector(v) for v in obj.bound_box]
        
        # Promediamos X e Y para obtener el centro lateral
        centro_x = sum(v.x for v in bbox) / 8.0
        centro_y = sum(v.y for v in bbox) / 8.0
        
        # Buscamos el valor más bajo en el eje Z (el fondo/base del modelo)
        min_z = min(v.z for v in bbox)
        
        # Armamos el vector del punto base en el espacio local del objeto
        base_local = Vector((centro_x, centro_y, min_z))
        
        # Convertimos esa coordenada local a global multiplicándola por la matriz de mundo del objeto
        base_global = obj.matrix_world @ base_local
        
        # 3. Movemos el cursor 3D de Blender a ese punto global exacto
        bpy.context.scene.cursor.location = base_global
        
        # 4. Asignamos el Origen (Pivote) a la posición actual del Cursor 3D
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        
        # 5. Posicionamos el objeto en el origen absoluto (0, 0, 0). 
        # Como el pivote ahora es la base, el objeto quedará apoyado perfectamente sobre el nivel Z=0 del mundo.
        obj.location = (0.0, 0.0, 0.0)
        
        # Limpiamos el nombre original del objeto por seguridad
        nombre_limpio = bpy.path.clean_name(obj.name)
        
        # Generamos la ruta de guardado
        ruta_completa = os.path.join(ruta_destino, f"{nombre_limpio}.glb")
        
        # Exportamos en formato GLB. 
        bpy.ops.export_scene.gltf(
            filepath=ruta_completa,
            use_selection=True,
            export_format='GLB',
            export_apply=True
        )
        
        print(f"Exportado con pivote en base: {ruta_completa}")

    # Restauramos el cursor 3D a su lugar original por buenas prácticas de desarrollo
    bpy.context.scene.cursor.location = cursor_original

# --- BLOQUE DE EJECUCIÓN PRINCIPAL ---
if __name__ == "__main__":
    # Ruta exacta que pasaste anteriormente para los decorativos individuales de tu proyecto
    RUTA_ASSETS = r""
    
    centrar_pivote_en_base_y_exportar(RUTA_ASSETS)
    print("--- PROCESO COMPLETADO ---")