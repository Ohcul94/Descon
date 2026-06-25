# GUÍA: Pared1 — Flujo Dungeon para Proyecto 2.5D

## Archivos generados
- `Pared1.obj` — Modelo 3D Low Poly listo para Meshy
- `Pared1.mtl` — Material placeholder (se reemplaza con las texturas de Meshy)

---

## Paso a Paso con Meshy

### 1. Importar en Meshy
1. Abrí [Meshy.ai](https://meshy.ai)
2. Seleccioná **"Texture"** (no "Text to 3D")
3. Subí el archivo `Pared1.obj`
4. Escribí el prompt: *"Stone dungeon wall, medieval, dark rock, mossy, sci-fi variant, seamless PBR texture"*
5. Meshy generará: **Albedo, Normal Map, Roughness, AO**

### 2. Exportar de Meshy
- Formato de exportación: **GLB** (lleva texturas incrustadas)
- Guardarlo en esta misma carpeta como `Pared1.glb`

### 3. En Godot (para tu proyecto 2.5D)
```
Escena de Dungeon:
├── StaticBody2D          ← Colisión 2D (físicas e interacción)
│   └── CollisionShape2D  ← Forma de la pared en 2D
└── SubViewport / Node3D  ← Renderizado visual 3D
    └── MeshInstance3D    ← Aquí va el Pared1.glb
```

> **Importante**: El GLB de la pared es **solo visual**. Nunca le pongas colisión 3D.
> Tu física sigue siendo completamente 2D como el resto del proyecto.

---

## Especificaciones del Modelo

| Propiedad       | Valor              |
|-----------------|--------------------|
| Ancho           | 2.0 unidades (2m)  |
| Alto            | 2.0 unidades (2m)  |
| Profundidad     | 0.25 unidades      |
| Triángulos      | 12                 |
| Vértices        | 8                  |
| UV Unwrap       | Proporcional/cara  |
| Cara principal  | Frontal (Z+)       |

---

## Módulos sugeridos para tu dungeon
Creá variantes con el mismo proceso:
- `Pared1` — Panel estándar 2x2
- `Pared_Esquina` — Panel en L para las esquinas
- `Pared_Puerta` — Panel con hueco para puertas
- `Pared_Pilar` — Columna 0.5x2x0.5
- `Techo1` — Panel horizontal 2x2x0.1
- `Piso1` — Panel horizontal 2x2x0.1
