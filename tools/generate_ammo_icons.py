#!/usr/bin/env python3
"""
Genera iconos de munición estilo skill icons de Descon.
Receta visual: frame metálico + fondo tech oscuro + emblema central con glow.
Salida: descon/assets/Municiones/Iconos/{Tipo}/{Tipo}.png (512x512 RGBA)
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 512
OUT_ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "descon", "assets", "Municiones", "Iconos",
)

# Colores por tipo de munición (referidos a su VFX)
AMMO_TYPES = {
    "laser": {
        "color": (255, 40, 50),
        "label": "LASER",
        "draw": "laser",
    },
    "missile": {
        "color": (255, 130, 20),
        "label": "MISSILE",
        "draw": "missile",
    },
    "mine": {
        "color": (255, 40, 180),
        "label": "MINE",
        "draw": "mine",
    },
    "siphon": {
        "color": (230, 40, 230),
        "label": "SIPHON",
        "draw": "siphon",
    },
    "emp": {
        "color": (40, 190, 255),
        "label": "EMP",
        "draw": "emp",
    },
    "electron": {
        "color": (255, 230, 40),
        "label": "ELECTRON",
        "draw": "electron",
    },
    "melee": {
        "color": (255, 40, 50),
        "label": "MELEE",
        "draw": "melee",
    },
    "heal": {
        "color": (40, 200, 80),
        "label": "HEAL",
        "draw": "heal",
    },
}


def lerp(a, b, t):
    return a + (b - a) * t


def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(v)))


def mix(c1, c2, t):
    return tuple(clamp(lerp(c1[i], c2[i], t)) for i in range(3))


def scale_color(c, f):
    return tuple(clamp(v * f) for v in c)


def rounded_rect_mask(size, radius, inset=0):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(
        [inset, inset, size - 1 - inset, size - 1 - inset],
        radius=radius,
        fill=255,
    )
    return m


def draw_metal_frame(img):
    """Frame metálico redondeado estilo skill icons."""
    s = SIZE
    r = 92
    frame = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)

    # Base metálica con gradiente vertical
    for y in range(s):
        t = y / (s - 1)
        # Gris claro arriba, medio abajo
        v = lerp(195, 110, t)
        # Variación horizontal sutil
        d.line([(0, y), (s, y)], fill=(clamp(v), clamp(v), clamp(v + 4), 255))

    # Recortar a rounded rect exterior
    outer = rounded_rect_mask(s, r, 0)
    # Hueco interior
    inner_r = 68
    inset = 34
    inner = rounded_rect_mask(s, inner_r, inset)
    frame_mask = Image.eval(outer, lambda p: p)
    # frame = outer AND NOT inner
    px_o = outer.load()
    px_i = inner.load()
    for y in range(s):
        for x in range(s):
            if px_i[x, y] > 0:
                px_o[x, y] = 0

    frame.putalpha(outer)

    # Bordes: brillo superior e inferior
    edge = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    de = ImageDraw.Draw(edge)
    # Borde exterior claro
    de.rounded_rectangle([2, 2, s - 3, s - 3], radius=r, outline=(230, 230, 235, 255), width=3)
    # Borde interior oscuro
    de.rounded_rectangle(
        [inset, inset, s - 1 - inset, s - 1 - inset],
        radius=inner_r,
        outline=(40, 40, 45, 255),
        width=3,
    )
    # Línea de brillo en el anillo
    de.rounded_rectangle([6, 6, s - 7, s - 7], radius=r - 4, outline=(255, 255, 255, 60), width=2)

    # Máscara del anillo para que el brillo solo salga en el frame
    ring = Image.new("L", (s, s), 0)
    px_r = ring.load()
    for y in range(s):
        for x in range(s):
            if px_o[x, y] > 0:
                px_r[x, y] = 255
    edge_masked = edge.copy()
    edge_masked.putalpha(Image.composite(edge.getchannel("A"), Image.new("L", (s, s), 0), ring))

    # Scrapes / rayones
    rng = random.Random(7)
    scrapes = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ds = ImageDraw.Draw(scrapes)
    for _ in range(18):
        ang = rng.uniform(0, math.pi * 2)
        cx = rng.uniform(10, s - 10)
        cy = rng.uniform(10, s - 10)
        # Solo en el anillo del frame
        dist_center = math.hypot(cx - s / 2, cy - s / 2)
        if dist_center < inset - 4 or dist_center > r + 8:
            continue
        length = rng.uniform(8, 28)
        x2 = cx + math.cos(ang) * length
        y2 = cy + math.sin(ang) * length
        bright = rng.randint(160, 220)
        ds.line([(cx, cy), (x2, y2)], fill=(bright, bright, bright, rng.randint(40, 90)), width=1)
    scrapes_masked = scrapes.copy()
    scrapes_masked.putalpha(Image.composite(scrapes.getchannel("A"), Image.new("L", (s, s), 0), ring))

    # Componer frame: base + bordes + scrapes
    # Primero recortar frame base al anillo
    base = frame.copy()
    base.putalpha(Image.composite(frame.getchannel("A"), Image.new("L", (s, s), 0), ring))

    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out = Image.alpha_composite(out, base)
    out = Image.alpha_composite(out, edge_masked)
    out = Image.alpha_composite(out, scrapes_masked)

    # Sombra suave del frame hacia dentro
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [inset, inset, s - 1 - inset, s - 1 - inset],
        radius=inner_r,
        outline=(0, 0, 0, 120),
        width=6,
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(4))
    out = Image.alpha_composite(out, shadow)

    return out, ring


def draw_tech_background(base_color):
    """Fondo tech oscuro con grid, circuitos y hexágonos."""
    s = SIZE
    inset = 34
    inner_r = 68

    bg = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(bg)

    # Fondo con gradiente radial sutil hacia el centro
    cx, cy = s / 2, s / 2
    max_d = math.hypot(cx, cy)
    for y in range(inset, s - inset):
        for x in range(inset, s - inset):
            dist = math.hypot(x - cx, y - cy) / max_d
            v = lerp(28, 12, dist)
            d.point((x, y), fill=(clamp(v), clamp(v), clamp(v + 3), 255))

    # Grid sutil
    grid_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    dg = ImageDraw.Draw(grid_layer)
    step = 26
    grid_c = (60, 70, 80, 35)
    for x in range(inset, s - inset, step):
        dg.line([(x, inset), (x, s - inset)], fill=grid_c, width=1)
    for y in range(inset, s - inset, step):
        dg.line([(inset, y), (s - inset, y)], fill=grid_c, width=1)

    # Circuitos (líneas con esquinas)
    rng = random.Random(42)
    circuits = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    dc = ImageDraw.Draw(circuits)
    cc = (70, 90, 100, 70)
    for _ in range(14):
        x = rng.randint(inset + 20, s - inset - 20)
        y = rng.randint(inset + 20, s - inset - 20)
        pts = [(x, y)]
        for _seg in range(rng.randint(2, 4)):
            horiz = rng.random() > 0.5
            length = rng.randint(20, 60) * (1 if rng.random() > 0.5 else -1)
            if horiz:
                x = clamp(x + length, inset + 10, s - inset - 10)
            else:
                y = clamp(y + length, inset + 10, s - inset - 10)
            pts.append((x, y))
        if len(pts) >= 2:
            dc.line(pts, fill=cc, width=1)
            # Pad final
            dc.ellipse([pts[-1][0] - 2, pts[-1][1] - 2, pts[-1][0] + 2, pts[-1][1] + 2],
                       fill=(90, 120, 130, 90))

    # Hexágonos decorativos
    def hexagon(draw, cx, cy, r, outline, width=1):
        pts = []
        for i in range(6):
            ang = math.pi / 6 + i * math.pi / 3
            pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
        draw.polygon(pts, outline=outline, width=width)

    hexes = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    dh = ImageDraw.Draw(hexes)
    hex_positions = [
        (80, 100, 14), (110, 130, 12), (s - 90, 110, 13),
        (s - 120, 140, 11), (90, s - 110, 14), (s - 100, s - 120, 12),
        (70, s / 2, 10), (s - 75, s / 2 + 20, 10),
    ]
    for hx, hy, hr in hex_positions:
        if inset + hr < hx < s - inset - hr and inset + hr < hy < s - inset - hr:
            hexagon(dh, hx, hy, hr, (80, 100, 110, 80), 1)

    # Texto tiny HUD
    hud = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    du = ImageDraw.Draw(hud)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    tiny_texts = [
        (60, 80, "AMMO.SYS"),
        (60, 94, "01001101"),
        (s - 150, 80, "TIER:MAX"),
        (s - 150, 94, "11100101"),
        (60, s - 90, "VFX.LINK"),
        (s - 150, s - 90, "RDY"),
    ]
    for tx, ty, txt in tiny_texts:
        if inset + 5 < tx < s - inset - 5 and inset + 5 < ty < s - inset - 5:
            du.text((tx, ty), txt, fill=(100, 130, 140, 100), font=font)

    # Corchetes HUD en esquinas
    brackets = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    db = ImageDraw.Draw(brackets)
    bc = (120, 150, 160, 120)
    m = inset + 16
    bl = 18
    # Superior izq
    db.line([(m, m + bl), (m, m), (m + bl, m)], fill=bc, width=2)
    # Superior der
    db.line([(s - m - bl, m), (s - m, m), (s - m, m + bl)], fill=bc, width=2)
    # Inferior izq
    db.line([(m, s - m - bl), (m, s - m), (m + bl, s - m)], fill=bc, width=2)
    # Inferior der
    db.line([(s - m - bl, s - m), (s - m, s - m), (s - m, s - m - bl)], fill=bc, width=2)

    # Componer todo y recortar al interior
    content = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    content = Image.alpha_composite(content, bg)
    content = Image.alpha_composite(content, grid_layer)
    content = Image.alpha_composite(content, circuits)
    content = Image.alpha_composite(content, hexes)
    content = Image.alpha_composite(content, hud)
    content = Image.alpha_composite(content, brackets)

    # Recortar al rounded interior
    inner = rounded_rect_mask(s, inner_r, inset)
    content.putalpha(Image.composite(content.getchannel("A"), Image.new("L", (s, s), 0), inner))
    return content


def add_glow(img, color, radius=18, intensity=1.0):
    """Agrega glow neón alrededor de contenido opaco."""
    # Extraer alpha como máscara
    a = img.getchannel("A")
    # Colorizar
    glow = Image.new("RGBA", img.size, color + (0,))
    # Blur de la máscara
    blurred = a.filter(ImageFilter.GaussianBlur(radius))
    # Escalar intensidad
    if intensity != 1.0:
        blurred = blurred.point(lambda p: clamp(p * intensity))
    glow.putalpha(blurred)
    return glow


def draw_laser(d, cx, cy, color, scale=1.0):
    """Haz de energía diagonal (estilo Laser1 / VFX_Laser)."""
    # Arrow / bolt principal
    length = 140 * scale
    width = 28 * scale
    ang = math.radians(-40)
    dx, dy = math.cos(ang), math.sin(ang)
    px, py = -dy, dx

    tip = (cx + dx * length / 2, cy + dy * length / 2)
    tail = (cx - dx * length / 2, cy - dy * length / 2)
    left = (cx - dx * length * 0.15 + px * width, cy - dy * length * 0.15 + py * width)
    right = (cx - dx * length * 0.15 - px * width, cy - dy * length * 0.15 - py * width)

    # Cuerpo exterior
    d.polygon([tip, left, tail, right], fill=color + (220,))
    # Núcleo blanco
    core_w = width * 0.45
    tip2 = (cx + dx * length * 0.42, cy + dy * length * 0.42)
    tail2 = (cx - dx * length * 0.42, cy - dy * length * 0.42)
    left2 = (cx - dx * length * 0.1 + px * core_w, cy - dy * length * 0.1 + py * core_w)
    right2 = (cx - dx * length * 0.1 - px * core_w, cy - dy * length * 0.1 - py * core_w)
    d.polygon([tip2, left2, tail2, right2], fill=(255, 255, 255, 240))

    # Estelas
    for i, off in enumerate([18, 36, 54]):
        sx = tail[0] - dx * off
        sy = tail[1] - dy * off
        w = width * (0.7 - i * 0.18)
        d.line(
            [(sx + px * w, sy + py * w), (sx - px * w, sy - py * w)],
            fill=color + (clamp(160 - i * 45),),
            width=max(2, int(6 - i)),
        )

    # Pequeños bolts secundarios
    for s_off in (-70, 70):
        bx = cx + px * s_off * scale
        by = cy + py * s_off * scale
        d.line([(bx - dx * 30, by - dy * 30), (bx + dx * 30, by + dy * 30)],
               fill=scale_color(color, 1.1) + (140,), width=3)


def draw_missile(d, cx, cy, color, scale=1.0):
    """Misil con estela de fuego."""
    # Cuerpo vertical del misil
    bw, bh = 36 * scale, 100 * scale
    # Punta
    tip = (cx, cy - bh * 0.7)
    body_top = (cx, cy - bh * 0.35)
    # Cuerpo
    body = [
        (cx - bw / 2, cy - bh * 0.3),
        (cx - bw / 2, cy + bh * 0.25),
        (cx + bw / 2, cy + bh * 0.25),
        (cx + bw / 2, cy - bh * 0.3),
    ]
    # Aletas
    fin_l = [(cx - bw / 2, cy + bh * 0.1), (cx - bw / 2 - 18 * scale, cy + bh * 0.35), (cx - bw / 2, cy + bh * 0.35)]
    fin_r = [(cx + bw / 2, cy + bh * 0.1), (cx + bw / 2 + 18 * scale, cy + bh * 0.35), (cx + bw / 2, cy + bh * 0.35)]

    # Estela de fuego primero (detrás)
    flame_len = 70 * scale
    for i in range(5):
        t = i / 4
        fw = lerp(28, 6, t) * scale
        fy = cy + bh * 0.25 + flame_len * t
        alpha = clamp(200 * (1 - t * 0.85))
        fc = mix(color, (255, 240, 80), 1 - t) if t < 0.5 else mix((255, 160, 30), (180, 40, 10), (t - 0.5) * 2)
        d.ellipse([cx - fw, fy - fw * 0.6, cx + fw, fy + fw * 0.6], fill=fc + (alpha,))

    # Aletas (gris oscuro / metal)
    d.polygon(fin_l, fill=(90, 95, 105, 230))
    d.polygon(fin_r, fill=(90, 95, 105, 230))
    # Cuerpo
    d.polygon(body, fill=(110, 115, 125, 240))
    # Borde cuerpo
    d.polygon(body, outline=(40, 42, 48, 255), width=2)
    # Punta
    d.polygon([tip, (cx - bw / 2, cy - bh * 0.28), (cx + bw / 2, cy - bh * 0.28)], fill=color + (230,))
    # Ojillo rojo en punta
    d.ellipse([cx - 7, cy - bh * 0.5 - 5, cx + 7, cy - bh * 0.5 + 9], fill=(255, 50, 50, 255))
    # Brillo del cuerpo
    d.line([(cx - bw * 0.2, cy - bh * 0.25), (cx - bw * 0.2, cy + bh * 0.2)],
           fill=(160, 165, 175, 160), width=3)


def draw_mine(d, cx, cy, color, scale=1.0):
    """Mina radial con cristales (estilo Mina1)."""
    # Centro cilíndrico
    core_w, core_h = 70 * scale, 36 * scale
    d.rounded_rectangle(
        [cx - core_w, cy - core_h, cx + core_w, cy + core_h],
        radius=10,
        fill=(55, 60, 70, 240),
        outline=(30, 32, 38, 255),
        width=2,
    )
    # Detalle del centro
    d.rounded_rectangle(
        [cx - core_w * 0.5, cy - core_h * 0.5, cx + core_w * 0.5, cy + core_h * 0.5],
        radius=6,
        fill=(75, 80, 92, 220),
        outline=(40, 42, 50, 200),
        width=1,
    )

    # Cristales radiales (8 direcciones)
    n = 8
    for i in range(n):
        ang = i * math.pi * 2 / n
        dx, dy = math.cos(ang), math.sin(ang)
        px, py = -dy, dx

        inner = 55 * scale
        outer = 115 * scale
        half_w = 16 * scale

        tip = (cx + dx * outer, cy + dy * outer)
        base_l = (cx + dx * inner + px * half_w, cy + dy * inner + py * half_w)
        base_r = (cx + dx * inner - px * half_w, cy + dy * inner - py * half_w)
        mid = (cx + dx * (inner + outer) * 0.5, cy + dy * (inner + outer) * 0.5)

        # Cristal exterior
        d.polygon([tip, base_l, mid, base_r], fill=color + (200,))
        # Núcleo brillante
        tip2 = (cx + dx * outer * 0.85, cy + dy * outer * 0.85)
        mid2 = (cx + dx * (inner + outer) * 0.5, cy + dy * (inner + outer) * 0.5)
        d.polygon([tip2, mid2], fill=(255, 255, 255, 230))

    # Brillo central
    d.ellipse([cx - 14, cy - 14, cx + 14, cy + 14], fill=color + (255,))
    d.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=(255, 255, 255, 255))


def draw_siphon(d, cx, cy, color, scale=1.0):
    """Anillo de drenaje con chispas (VFX_Siphon)."""
    # Anillos concéntricos
    for i, r in enumerate([90, 70, 50]):
        rw = 5 - i
        d.ellipse(
            [cx - r * scale, cy - r * scale, cx + r * scale, cy + r * scale],
            outline=color + (clamp(200 - i * 40),),
            width=max(2, int(rw)),
        )

    # Espiral de drenaje (curvas)
    pts = []
    for t in range(0, 360, 4):
        rad = math.radians(t)
        rr = (20 + t * 0.22) * scale
        pts.append((cx + rr * math.cos(rad), cy + rr * math.sin(rad)))
    if len(pts) >= 2:
        d.line(pts, fill=color + (220,), width=4, joint="curve")

    # Núcleo con corazón / gota (drenaje)
    # Forma de gota invertida
    d.ellipse([cx - 22 * scale, cy - 30 * scale, cx + 22 * scale, cy + 10 * scale],
              fill=color + (230,))
    d.polygon([
        (cx, cy + 32 * scale),
        (cx - 22 * scale, cy - 5 * scale),
        (cx + 22 * scale, cy - 5 * scale),
    ], fill=color + (230,))
    # Highlight
    d.ellipse([cx - 10 * scale, cy - 20 * scale, cx + 4 * scale, cy - 4 * scale],
              fill=(255, 255, 255, 200))

    # Chispas / drenaje hacia afuera
    rng = random.Random(99)
    for _ in range(12):
        ang = rng.uniform(0, math.pi * 2)
        r0 = rng.uniform(40, 60) * scale
        r1 = rng.uniform(85, 110) * scale
        x0, y0 = cx + r0 * math.cos(ang), cy + r0 * math.sin(ang)
        x1, y1 = cx + r1 * math.cos(ang), cy + r1 * math.sin(ang)
        d.line([(x0, y0), (x1, y1)], fill=scale_color(color, 1.2) + (160,), width=2)
        d.ellipse([x1 - 3, y1 - 3, x1 + 3, y1 + 3], fill=(255, 255, 255, 200))


def draw_emp(d, cx, cy, color, scale=1.0):
    """Pulso EMP: ondas concéntricas + rayos."""
    # Ondas expansivas
    for i, r in enumerate([45, 75, 105]):
        # Trazo discontinuo simulado con arcos
        alpha = clamp(220 - i * 50)
        d.arc(
            [cx - r * scale, cy - r * scale, cx + r * scale, cy + r * scale],
            start=20 + i * 15,
            end=340 - i * 15,
            fill=color + (alpha,),
            width=max(3, 6 - i),
        )

    # Núcleo central
    d.ellipse([cx - 28 * scale, cy - 28 * scale, cx + 28 * scale, cy + 28 * scale],
              fill=color + (200,))
    d.ellipse([cx - 14 * scale, cy - 14 * scale, cx + 14 * scale, cy + 14 * scale],
              fill=(255, 255, 255, 240))

    # Rayos eléctricos
    rng = random.Random(55)
    for _ in range(8):
        ang = rng.uniform(0, math.pi * 2)
        pts = [(cx, cy)]
        r = 30 * scale
        a = ang
        for _seg in range(4):
            a += rng.uniform(-0.5, 0.5)
            r += rng.uniform(18, 28) * scale
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        d.line(pts, fill=scale_color(color, 1.3) + (200,), width=2, joint="curve")

    # Pequeños nodos en las ondas
    for i in range(6):
        ang = i * math.pi / 3 + 0.3
        r = 75 * scale
        nx, ny = cx + r * math.cos(ang), cy + r * math.sin(ang)
        d.ellipse([nx - 5, ny - 5, nx + 5, ny + 5], fill=color + (220,))


def draw_electron(d, cx, cy, color, scale=1.0):
    """Esfera de energía con electrones en órbita (parabólica)."""
    # Núcleo
    core_r = 36 * scale
    d.ellipse([cx - core_r, cy - core_r, cx + core_r, cy + core_r],
              fill=color + (230,))
    # Highlight
    d.ellipse([cx - core_r * 0.55, cy - core_r * 0.65, cx + core_r * 0.1, cy + core_r * 0.05],
              fill=(255, 255, 255, 220))

    # Órbitas elípticas
    for i, (rx, ry, rot) in enumerate([
        (100, 40, 0),
        (100, 40, math.pi / 3),
        (100, 40, -math.pi / 3),
    ]):
        # Dibiar órbita como polilínea rotada
        pts = []
        for t in range(0, 360, 6):
            rad = math.radians(t)
            ex = rx * scale * math.cos(rad)
            ey = ry * scale * math.sin(rad)
            ca, sa = math.cos(rot), math.sin(rot)
            pts.append((cx + ex * ca - ey * sa, cy + ex * sa + ey * ca))
        d.line(pts, fill=color + (160,), width=2, joint="curve")

    # Electrón en órbita
    ang = math.radians(40)
    ex = 100 * scale * math.cos(ang)
    ey = 40 * scale * math.sin(ang)
    d.ellipse([cx + ex - 10, cy + ey - 10, cx + ex + 10, cy + ey + 10],
              fill=(255, 255, 255, 240))
    d.ellipse([cx + ex - 7, cy + ey - 7, cx + ex + 7, cy + ey + 7],
              fill=color + (255,))

    # Destellos / chispas
    rng = random.Random(11)
    for _ in range(10):
        ang2 = rng.uniform(0, math.pi * 2)
        rr = rng.uniform(core_r + 15, 110) * scale
        sx, sy = cx + rr * math.cos(ang2), cy + rr * math.sin(ang2)
        sz = rng.randint(2, 5)
        d.ellipse([sx - sz, sy - sz, sx + sz, sy + sz],
                  fill=scale_color(color, 1.2) + (rng.randint(120, 220),))

    # Trajectoria parabólica sutil (como el VFX de electron)
    par_pts = []
    for t in range(-60, 61, 4):
        x = cx + t * scale * 1.4
        y = cy + 70 * scale - (t * scale * 0.55) ** 2 / (100 * scale)
        par_pts.append((x, y))
    if len(par_pts) >= 2:
        d.line(par_pts, fill=color + (100,), width=2, joint="curve")


def draw_melee(d, cx, cy, color, scale=1.0):
    """Sierra de plasma diagonal con fuego orbital (VFX_Fire_ball_type_B)."""
    ang = math.radians(-45)
    dx, dy = math.cos(ang), math.sin(ang)
    px, py = -dy, dx
    length = 170 * scale
    half_w = 22 * scale

    # 4 bolas de fuego orbitando el eje de la hoja
    for i in range(4):
        t = (i / 4.0) * 2.0 - 1.0
        along = t * length * 0.38
        side = (28 if i % 2 == 0 else -28) * scale
        fx = cx + dx * along + px * side
        fy = cy + dy * along + py * side
        fr = 16 * scale
        d.ellipse([fx - fr, fy - fr, fx + fr, fy + fr], fill=color + (180,))
        d.ellipse([fx - fr * 0.55, fy - fr * 0.55, fx + fr * 0.55, fy + fr * 0.55],
                  fill=(255, 200, 60, 230))
        d.ellipse([fx - fr * 0.25, fy - fr * 0.25, fx + fr * 0.25, fy + fr * 0.25],
                  fill=(255, 255, 255, 240))

    # Hoja / sierra (diamante alargado)
    tip = (cx + dx * length / 2, cy + dy * length / 2)
    tail = (cx - dx * length / 2, cy - dy * length / 2)
    left = (cx + px * half_w, cy + py * half_w)
    right = (cx - px * half_w, cy - py * half_w)
    d.polygon([tip, left, tail, right], fill=(200, 205, 215, 235))
    d.polygon([tip, left, tail, right], outline=(40, 42, 48, 255), width=2)

    # Núcleo de plasma
    core_w = half_w * 0.45
    tip2 = (cx + dx * length * 0.4, cy + dy * length * 0.4)
    tail2 = (cx - dx * length * 0.4, cy - dy * length * 0.4)
    left2 = (cx + px * core_w, cy + py * core_w)
    right2 = (cx - px * core_w, cy - py * core_w)
    d.polygon([tip2, left2, tail2, right2], fill=color + (240,))

    # Dientes de sierra en los bordes
    teeth = 9
    for i in range(teeth):
        t = -0.42 + i * (0.84 / (teeth - 1))
        bx = cx + dx * length * t
        by = cy + dy * length * t
        side = half_w * (1 if i % 2 == 0 else -1)
        ttx = bx + px * (side + 10 * scale * (1 if side > 0 else -1))
        tty = by + py * (side + 10 * scale * (1 if side > 0 else -1))
        d.polygon([
            (bx - dx * 6, by - dy * 6),
            (bx + dx * 6, by + dy * 6),
            (ttx, tty),
        ], fill=(160, 165, 175, 230))

    # Brillo en la punta
    d.ellipse([tip[0] - 7, tip[1] - 7, tip[0] + 7, tip[1] + 7], fill=(255, 255, 255, 230))


def draw_heal(d, cx, cy, color, scale=1.0):
    """Dron de curación con cruz blanca (Projectile heal drone)."""
    # Brazos / propulsores laterales
    for sx in (-1, 1):
        ax = cx + sx * 78 * scale
        d.line([(cx + sx * 40 * scale, cy), (ax, cy - 8 * scale)],
               fill=color + (180,), width=4)
        d.ellipse([ax - 14 * scale, cy - 14 * scale - 8 * scale,
                   ax + 14 * scale, cy + 14 * scale - 8 * scale],
                  fill=(70, 75, 85, 230),
                  outline=(30, 32, 38, 255), width=2)
        d.ellipse([ax - 7 * scale, cy - 7 * scale - 8 * scale,
                   ax + 7 * scale, cy + 7 * scale - 8 * scale],
                  fill=color + (220,))

    # Halo de curación exterior
    d.ellipse([cx - 95 * scale, cy - 95 * scale, cx + 95 * scale, cy + 95 * scale],
              outline=color + (70,), width=3)
    d.ellipse([cx - 78 * scale, cy - 78 * scale, cx + 78 * scale, cy + 78 * scale],
              outline=color + (40,), width=2)

    # Cuerpo del dron
    body_r = 48 * scale
    d.ellipse([cx - body_r, cy - body_r, cx + body_r, cy + body_r],
              fill=(55, 60, 70, 245),
              outline=(30, 32, 38, 255), width=3)
    d.ellipse([cx - body_r + 8, cy - body_r + 8, cx + body_r - 8, cy + body_r - 8],
              fill=color + (200,))
    d.ellipse([cx - body_r * 0.55, cy - body_r * 0.65, cx + body_r * 0.1, cy + body_r * 0.05],
              fill=(255, 255, 255, 120))

    # Cruz de curación blanca
    arm = 26 * scale
    tw = 12 * scale
    d.rounded_rectangle([cx - arm, cy - tw / 2, cx + arm, cy + tw / 2],
                        radius=3, fill=(255, 255, 255, 250))
    d.rounded_rectangle([cx - tw / 2, cy - arm, cx + tw / 2, cy + arm],
                        radius=3, fill=(255, 255, 255, 250))

    # Pequeños "+" flotantes
    for ox, oy, s in [(-70, -55, 8), (72, -48, 7), (60, 68, 6), (-65, 62, 7)]:
        px0, py0 = cx + ox * scale, cy + oy * scale
        d.rounded_rectangle([px0 - s * scale, py0 - 2 * scale, px0 + s * scale, py0 + 2 * scale],
                            radius=2, fill=scale_color(color, 1.3) + (220,))
        d.rounded_rectangle([px0 - 2 * scale, py0 - s * scale, px0 + 2 * scale, py0 + s * scale],
                            radius=2, fill=scale_color(color, 1.3) + (220,))


DRAW_FUNCS = {
    "laser": draw_laser,
    "missile": draw_missile,
    "mine": draw_mine,
    "siphon": draw_siphon,
    "emp": draw_emp,
    "electron": draw_electron,
    "melee": draw_melee,
    "heal": draw_heal,
}


def generate_icon(type_key, cfg):
    s = SIZE
    color = cfg["color"]

    # 1) Capa interior: fondo tech
    bg = draw_tech_background(color)

    # 2) Capa del emblema + glow
    emblem = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(emblem)
    cx, cy = s / 2, s / 2 + 4
    DRAW_FUNCS[cfg["draw"]](d, cx, cy, color, scale=1.0)

    # Glow fuerte detrás del emblema
    glow_strong = add_glow(emblem, color, radius=22, intensity=1.2)
    glow_soft = add_glow(emblem, color, radius=40, intensity=0.55)

    # 3) Componer interior
    inner = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    inner = Image.alpha_composite(inner, bg)
    inner = Image.alpha_composite(inner, glow_soft)
    inner = Image.alpha_composite(inner, glow_strong)
    inner = Image.alpha_composite(inner, emblem)

    # Tinte sutil del color en todo el interior
    tint = Image.new("RGBA", (s, s), color + (18,))
    inner = Image.alpha_composite(inner, tint)

    # 4) Frame metálico encima
    frame, ring = draw_metal_frame(Image.new("RGBA", (s, s), (0, 0, 0, 0)))

    # Asegurar que interior quede debajo del frame pero visible en el hueco
    # Recortar interior al hueco
    inset = 34
    inner_r = 68
    hole = rounded_rect_mask(s, inner_r, inset)
    inner_masked = inner.copy()
    inner_masked.putalpha(Image.composite(inner.getchannel("A"), Image.new("L", (s, s), 0), hole))

    # Glow que se desborda un poco sobre el frame (efecto skills)
    edge_glow = add_glow(emblem, color, radius=30, intensity=0.35)
    # Solo permitir glow dentro del hueco y un poco del borde interior
    edge_glow_masked = edge_glow.copy()
    # Radio de máscara más grande para permitir overflow
    soft_hole = rounded_rect_mask(s, inner_r + 10, inset - 6)
    edge_glow_masked.putalpha(Image.composite(edge_glow.getchannel("A"), Image.new("L", (s, s), 0), soft_hole))

    result = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    result = Image.alpha_composite(result, inner_masked)
    result = Image.alpha_composite(result, edge_glow_masked)
    result = Image.alpha_composite(result, frame)

    # Label tiny en la parte inferior del interior
    overlay = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    do = ImageDraw.Draw(overlay)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    label = cfg["label"]
    # Posición bajo el centro
    ty = s - 78
    # Fondo etiqueta
    tw = do.textlength(label, font=font) if font else len(label) * 7
    do.rounded_rectangle(
        [cx - tw / 2 - 8, ty - 4, cx + tw / 2 + 8, ty + 16],
        radius=3,
        fill=(0, 0, 0, 140),
        outline=color + (160,),
        width=1,
    )
    do.text((cx - tw / 2, ty), label, fill=color + (230,), font=font)
    # Recortar label al hueco
    overlay.putalpha(Image.composite(overlay.getchannel("A"), Image.new("L", (s, s), 0), hole))
    result = Image.alpha_composite(result, overlay)

    return result


def main():
    os.makedirs(OUT_ROOT, exist_ok=True)
    for key, cfg in AMMO_TYPES.items():
        out_dir = os.path.join(OUT_ROOT, key)
        os.makedirs(out_dir, exist_ok=True)
        # Nombre con mayúscula inicial consistente con skills
        fname = key[0].upper() + key[1:] + ".png"
        out_path = os.path.join(out_dir, fname)
        icon = generate_icon(key, cfg)
        icon.save(out_path, "PNG")
        print(f"[OK] {out_path} ({icon.size[0]}x{icon.size[1]})")

    print(f"\nGenerados {len(AMMO_TYPES)} iconos en {OUT_ROOT}")


if __name__ == "__main__":
    main()
