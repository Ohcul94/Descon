from PIL import Image
import os

def analyze(path):
    im = Image.open(path).convert('RGBA')
    w, h = im.size
    px = im.load()
    minx, miny, maxx, maxy = w, h, -1, -1
    sx = sy = n = 0
    # Inner content only (ignore outer 15% frame)
    m = int(min(w, h) * 0.18)
    for y in range(m, h - m, 2):
        for x in range(m, w - m, 2):
            r, g, b, a = px[x, y]
            if a > 40:
                if x < minx: minx = x
                if y < miny: miny = y
                if x > maxx: maxx = x
                if y > maxy: maxy = y
                sx += x; sy += y; n += 1
    if n == 0:
        print(os.path.basename(path), 'EMPTY')
        return
    cx, cy = sx / n, sy / n
    bcx, bcy = (minx + maxx) / 2, (miny + maxy) / 2
    print(
        f"{os.path.basename(path):28s} {w}x{h} "
        f"content_bbox=({minx},{miny})-({maxx},{maxy}) "
        f"bbox_c=({bcx:.0f},{bcy:.0f}) "
        f"centroid=({cx:.0f},{cy:.0f}) "
        f"off_c=({cx-w/2:+.1f},{cy-h/2:+.1f}) "
        f"off_bbox=({bcx-w/2:+.1f},{bcy-h/2:+.1f})"
    )

print('=== AMMO (inner) ===')
root = r'E:\Descon\descon\assets\Municiones\Iconos'
for dirpath, _, files in os.walk(root):
    for f in sorted(files):
        if f.endswith('.png'):
            analyze(os.path.join(dirpath, f))

print('=== SKILLS sample (inner) ===')
base = r'E:\Descon\descon\assets\Skills\Iconos'
for rel in [
    r'Ataque\Reflect\Reflect.png',
    r'Utilidad\Destello\Destello.png',
    r'Cura\Auto Reparacion\AutoReparacion.png',
    r'Defensa\Escudo Celular\Escudo Celular.png',
    r'Ataque\Miedo\Miedo.png',
]:
    p = os.path.join(base, rel)
    if os.path.exists(p):
        analyze(p)
    else:
        print('missing', p)
