extends Node

var admin_main = null

func setup(main):
	admin_main = main

func render_items(container):
	for cat in ["weapons", "shields", "engines"]:
		var label = Label.new(); label.text = "\nSISTEMA: " + cat.to_upper(); label.modulate = Color.GOLD; container.add_child(label)
		var list = GameConstants.SHOP_ITEMS.get(cat, [])
		for i in range(list.size()):
			var item = list[i]
			var card = admin_main._create_card(container, "ITEM: " + item.name.to_upper())
			var grid = admin_main._create_grid(card, 4)
			admin_main._add_input(grid, "NOMBRE", item.name, func(v): GameConstants.SHOP_ITEMS[cat][i].name = v, true)
			admin_main._add_input(grid, "BASE", str(item.get("base", 0)), func(v): GameConstants.SHOP_ITEMS[cat][i].base = int(v))
			admin_main._add_input(grid, "HUBS", str(item.prices.hubs), func(v): GameConstants.SHOP_ITEMS[cat][i].prices.hubs = int(v))
			admin_main._add_input(grid, "OHCU", str(item.prices.ohcu), func(v): GameConstants.SHOP_ITEMS[cat][i].prices.ohcu = int(v))

func render_ammo(container):
	for cat in ["laser", "missile", "mine"]:
		var label = Label.new(); label.text = "\nMUNICIÓN: " + cat.to_upper(); label.modulate = Color.GOLD; container.add_child(label)
		var mults = GameConstants.AMMO_MULTIPLIERS.get(cat, [])
		var shop_ammo = GameConstants.SHOP_ITEMS.ammo.get(cat, [])
		
		for i in range(mults.size()):
			var item_name = "TIER T" + str(i+1)
			if i < shop_ammo.size(): item_name = shop_ammo[i].name
			
			var card = admin_main._create_card(container, item_name.to_upper())
			var grid = admin_main._create_grid(card, 5)
			
			if i < shop_ammo.size():
				admin_main._add_input(grid, "NOMBRE", shop_ammo[i].name, func(v): GameConstants.SHOP_ITEMS.ammo[cat][i].name = v, true)
				admin_main._add_input(grid, "MULT", str(mults[i]), func(v): GameConstants.AMMO_MULTIPLIERS[cat][i] = float(v))
				admin_main._add_input(grid, "RANGO", str(shop_ammo[i].get("range", 600)), func(v): GameConstants.SHOP_ITEMS.ammo[cat][i].range = int(v))
				admin_main._add_input(grid, "P_HUBS", str(shop_ammo[i].prices.hubs), func(v): GameConstants.SHOP_ITEMS.ammo[cat][i].prices.hubs = int(v))
				admin_main._add_input(grid, "P_OHCU", str(shop_ammo[i].prices.ohcu), func(v): GameConstants.SHOP_ITEMS.ammo[cat][i].prices.ohcu = int(v))
