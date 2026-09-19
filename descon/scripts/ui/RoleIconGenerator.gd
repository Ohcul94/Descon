extends RefCounted

# RoleIconGenerator.gd - Genera iconos de rol proceduralmente (Estilo WOW)

const ICON_SIZE = 24

static func get_role_icon(role: String) -> ImageTexture:
	match role:
		"tank":
			return _draw_tank()
		"healer":
			return _draw_healer()
		"buffer":
			return _draw_buffer()
		"dps":
			return _draw_dps()
		_:
			return null

static func _draw_tank() -> ImageTexture:
	# Escudo blindado - Tanque
	var img = Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var c = Color(0.3, 0.6, 1.0)
	var center = ICON_SIZE * 0.5
	for y in range(ICON_SIZE):
		for x in range(ICON_SIZE):
			var cx = x - center
			var cy = y - center
			var shield_w = 9.0 - abs(cy) * 0.6
			if abs(cx) < shield_w and cy > -10 and cy < 9:
				img.set_pixel(x, y, c)
			elif abs(abs(cx) - shield_w) < 1.2 and cy > -10 and cy < 9:
				img.set_pixel(x, y, c.lightened(0.35))
	return ImageTexture.create_from_image(img)

static func _draw_healer() -> ImageTexture:
	# Cruz verde - Sanador
	var img = Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var c = Color(0.2, 0.9, 0.3)
	var cx = int(ICON_SIZE * 0.5)
	var cy = int(ICON_SIZE * 0.5)
	# Cruz vertical
	for y in range(cy - 8, cy + 9):
		for x in range(cx - 3, cx + 4):
			if x >= 0 and x < ICON_SIZE and y >= 0 and y < ICON_SIZE:
				img.set_pixel(x, y, c)
	# Cruz horizontal
	for y in range(cy - 3, cy + 4):
		for x in range(cx - 8, cx + 9):
			if x >= 0 and x < ICON_SIZE and y >= 0 and y < ICON_SIZE:
				img.set_pixel(x, y, c)
	# Borde exterior
	for y in range(cy - 9, cy + 10):
		for x in range(cx - 9, cx + 10):
			if x >= 0 and x < ICON_SIZE and y >= 0 and y < ICON_SIZE:
				var on_vert = (x >= cx - 3 and x < cx + 4)
				var on_horiz = (y >= cy - 3 and y < cy + 4)
				var in_cross = on_vert or on_horiz
				var is_edge = (x == cx - 9 or x == cx + 8 or y == cy - 9 or y == cy + 8)
				if is_edge and in_cross:
					img.set_pixel(x, y, c.lightened(0.3))
	return ImageTexture.create_from_image(img)

static func _draw_buffer() -> ImageTexture:
	# Rayo amarillo - Buffer
	var img = Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var c = Color(1.0, 0.85, 0.2)
	var bolt = [
		[10, 1], [11, 2], [10, 3], [9, 4], [10, 5], [11, 6],
		[10, 7], [9, 8], [10, 9], [11, 10], [10, 11], [9, 12],
		[10, 13], [11, 14], [10, 15], [9, 16], [10, 17], [11, 18], [10, 19], [9, 20],
		[10, 21], [11, 22]
	]
	for p in bolt:
		if p[0] >= 0 and p[0] < ICON_SIZE and p[1] >= 0 and p[1] < ICON_SIZE:
			img.set_pixel(p[0], p[1], c)
			if p[0] - 1 >= 0:
				img.set_pixel(p[0] - 1, p[1], c.darkened(0.25))
			if p[0] + 1 < ICON_SIZE:
				img.set_pixel(p[0] + 1, p[1], c.darkened(0.25))
	return ImageTexture.create_from_image(img)

static func _draw_dps() -> ImageTexture:
	# Espadas cruzadas - DPS
	var img = Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var c = Color(0.9, 0.2, 0.2)
	# Espada 1: diagonal principal
	for i in range(ICON_SIZE):
		var x = i
		var y = i
		if x >= 0 and x < ICON_SIZE and y >= 0 and y < ICON_SIZE:
			img.set_pixel(x, y, c)
			if x + 1 < ICON_SIZE:
				img.set_pixel(x + 1, y, c.darkened(0.2))
	# Espada 2: diagonal secundaria
	for i in range(ICON_SIZE):
		var x = ICON_SIZE - 1 - i
		var y = i
		if x >= 0 and x < ICON_SIZE and y >= 0 and y < ICON_SIZE:
			img.set_pixel(x, y, c)
			if x - 1 >= 0:
				img.set_pixel(x - 1, y, c.darkened(0.2))
	# Centro más brillante
	var mid = int(ICON_SIZE * 0.5)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var px = mid + dx
			var py = mid + dy
			if px >= 0 and px < ICON_SIZE and py >= 0 and py < ICON_SIZE:
				img.set_pixel(px, py, c.lightened(0.45))
	return ImageTexture.create_from_image(img)
