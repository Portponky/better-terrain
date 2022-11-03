@tool
extends Control

signal update_overlay

# Buttons
@onready var draw_button := $VBoxContainer/Toolbar/Draw
@onready var rectangle_button := $VBoxContainer/Toolbar/Rectangle
@onready var fill_button := $VBoxContainer/Toolbar/Fill

@onready var paint_type := $VBoxContainer/Toolbar/PaintType
@onready var paint_terrain := $VBoxContainer/Toolbar/PaintTerrain

@onready var layer_options = $VBoxContainer/Toolbar/LayerOptions

@onready var add_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/AddTerrain
@onready var edit_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/EditTerrain
@onready var move_up_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/MoveUp
@onready var move_down_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/MoveDown
@onready var remove_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/RemoveTerrain

@onready var terrain_tree := $VBoxContainer/HSplitContainer/VBoxContainer/Panel/Tree
@onready var tile_view := $VBoxContainer/HSplitContainer/Panel/ScrollArea/TileView

@onready var terrain_icons = [
	load("res://addons/better-terrain/icons/MatchSidesAndCorners.svg"),
	load("res://addons/better-terrain/icons/MatchCorners.svg"),
	load("res://addons/better-terrain/icons/NonModifying.svg"),
]

const TERRAIN_PROPERTIES_SCENE := preload("res://addons/better-terrain/TerrainProperties.tscn")

var tilemap : TileMap
var tileset : TileSet

var layer = 0
var initial_click : Vector2i

enum PaintMode {
	NO_PAINT,
	PAINT,
	ERASE
}

var paint_mode = PaintMode.NO_PAINT


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	draw_button.icon = get_theme_icon("Edit", "EditorIcons")
	rectangle_button.icon = get_theme_icon("Rectangle", "EditorIcons")
	fill_button.icon = get_theme_icon("Bucket", "EditorIcons")
	add_terrain_button.icon = get_theme_icon("Add", "EditorIcons")
	edit_terrain_button.icon = get_theme_icon("Tools", "EditorIcons")
	move_up_button.icon = get_theme_icon("ArrowUp", "EditorIcons")
	move_down_button.icon = get_theme_icon("ArrowDown", "EditorIcons")
	remove_terrain_button.icon = get_theme_icon("Remove", "EditorIcons")
	
	# Make a root node for the terrain tree
	terrain_tree.create_item()


func _get_fill_cells(target: Vector2i):
	var pick = BetterTerrain.get_cell(tilemap, layer, target)
	var bounds = tilemap.get_used_rect()
	
	# No sets yet, so use a dictionary
	var checked = {}
	var pending = [target]
	var goal = []
	
	while !pending.is_empty():
		var p = pending.pop_front()
		if checked.has(p):
			continue
		checked[p] = true
		if !bounds.has_point(p) or BetterTerrain.get_cell(tilemap, layer, p) != pick:
			continue
		
		goal.append(p)
		pending.append_array([
			p + Vector2i.RIGHT,
			p + Vector2i.UP,
			p + Vector2i.LEFT,
			p + Vector2i.DOWN
		])
	
	return goal


func reload() -> void:
	# clear terrains
	var root = terrain_tree.get_root()
	var children = root.get_children()
	for child in children:
		root.remove_child(child)
	
	# load terrains from tileset
	for i in BetterTerrain.terrain_count(tileset):
		var terrain = BetterTerrain.get_terrain(tileset, i)
		var new_terrain = terrain_tree.create_item(root)
		new_terrain.set_text(0, terrain.name)
		new_terrain.set_icon(0, terrain_icons[terrain.type])
		new_terrain.set_icon_modulate(0, terrain.color)
	
	layer_options.clear()
	if tilemap.get_layers_count() == 0:
		layer_options.text = tr("No layers")
		layer_options.disabled = true
		layer = 0
	else:
		for n in tilemap.get_layers_count():
			var name = tilemap.get_layer_name(n)
			if name.is_empty():
				name = tr("Layer {0}").format([n])
			layer_options.add_item(name, n)
			layer_options.set_item_disabled(n, !tilemap.is_layer_enabled(n))
		layer_options.disabled = false
		layer_options.selected = layer
	tile_view.refresh_tileset(tileset)


func generate_popup() -> ConfirmationDialog:
	var popup = TERRAIN_PROPERTIES_SCENE.instantiate()
	add_child(popup)
	return popup


func _on_add_terrain_pressed() -> void:
	if !tileset:
		return
	
	var popup = generate_popup()
	popup.terrain_name = "New terrain"
	popup.terrain_color = Color.AQUAMARINE
	popup.terrain_type = 0
	popup.popup_centered()
	await popup.visibility_changed
	if popup.accepted and BetterTerrain.add_terrain(tileset, popup.terrain_name, popup.terrain_color, popup.terrain_type):
		var new_terrain = terrain_tree.create_item(terrain_tree.get_root())
		new_terrain.set_text(0, popup.terrain_name)
		new_terrain.set_icon(0, terrain_icons[popup.terrain_type])
		new_terrain.set_icon_modulate(0, popup.terrain_color)
	popup.queue_free()


func _on_edit_terrain_pressed() -> void:
	if !tileset:
		return
	
	var item = terrain_tree.get_selected()
	if !item:
		return
		
	var t = BetterTerrain.get_terrain(tileset, item.get_index())
	
	var popup = generate_popup()
	popup.terrain_name = t.name
	popup.terrain_type = t.type
	popup.terrain_color = t.color
	popup.popup_centered()
	await popup.visibility_changed
	if popup.accepted and BetterTerrain.set_terrain(tileset, item.get_index(), popup.terrain_name, popup.terrain_color, popup.terrain_type):
		item.set_text(0, popup.terrain_name)
		item.set_icon(0, terrain_icons[popup.terrain_type])
		item.set_icon_modulate(0, popup.terrain_color)
	popup.queue_free()


func _on_move_pressed(down: bool) -> void:
	if !tileset:
		return
	
	var item = terrain_tree.get_selected()
	if !item:
		return
	
	var index1 = item.get_index()
	var index2 = index1 + (1 if down else -1)
	if index2 < 0 or index2 >= terrain_tree.get_root().get_child_count():
		return
	
	if BetterTerrain.swap_terrains(tileset, index1, index2):
		var item2 = terrain_tree.get_root().get_child(index2)
		if down:
			item.move_after(item2)
		else:
			item.move_before(item2)


func _on_remove_terrain_pressed() -> void:
	if !tileset:
		return
	
	# Confirmation dialog
	var item = terrain_tree.get_selected()
	if !item:
		return
	
	if BetterTerrain.remove_terrain(tileset, item.get_index()):
		item.free()


func _on_draw_pressed():
	draw_button.button_pressed = true
	rectangle_button.button_pressed = false
	fill_button.button_pressed = false


func _on_rectangle_pressed():
	draw_button.button_pressed = false
	rectangle_button.button_pressed = true
	fill_button.button_pressed = false

func _on_fill_pressed():
	draw_button.button_pressed = false
	rectangle_button.button_pressed = false
	fill_button.button_pressed = true

func _on_tree_cell_selected():
	var selected = terrain_tree.get_selected()
	if !selected:
		return
	
	tile_view.paint = selected.get_index()
	tile_view.queue_redraw()


func _on_paint_type_pressed():
	paint_terrain.button_pressed = false
	tile_view.paint_mode = tile_view.PaintMode.PAINT_TYPE if paint_type.button_pressed else tile_view.PaintMode.NO_PAINT


func _on_paint_terrain_pressed():
	paint_type.button_pressed = false
	tile_view.paint_mode = tile_view.PaintMode.PAINT_PEERING if paint_terrain.button_pressed else tile_view.PaintMode.NO_PAINT


func canvas_draw(overlay: Control) -> void:
	var selected = terrain_tree.get_selected()
	if !selected:
		return
	
	var type = selected.get_index()
	var terrain = BetterTerrain.get_terrain(tileset, type)
	if !terrain.valid:
		return
	
	var pos = tilemap.get_viewport_transform().affine_inverse() * overlay.get_local_mouse_position()
	var tile = tilemap.local_to_map(tilemap.to_local(pos))
	
	var tile_size = Vector2(tilemap.tile_set.tile_size)
	var tile_area = Rect2(tilemap.map_to_local(tile) - 0.5 * tile_size, tile_size)
	
	if rectangle_button.button_pressed and paint_mode != PaintMode.NO_PAINT:
		# During fill operation
		var tl = Vector2i(min(initial_click.x, tile.x), min(initial_click.y, tile.y))
		var br = Vector2i(max(initial_click.x, tile.x), max(initial_click.y, tile.y))
		tile_area = Rect2(
			tilemap.map_to_local(tl) - 0.5 * tile_size,
			tilemap.map_to_local(br) - tilemap.map_to_local(tl) + tile_size
		)
	
	var area = tilemap.get_viewport_transform() * tilemap.global_transform * tile_area
	
	overlay.draw_rect(area, Color(terrain.color, 0.5), true)


func canvas_input(event: InputEvent) -> bool:
	var selected = terrain_tree.get_selected()
	if !selected:
		return false
	
	if event is InputEventMouseMotion:
		update_overlay.emit()
	
	if event is InputEventMouseButton and !event.pressed:
		if rectangle_button.button_pressed and paint_mode != PaintMode.NO_PAINT:
			var tr = tilemap.get_viewport_transform() * tilemap.global_transform
			var pos = tr.affine_inverse() * event.position
			var target = tilemap.local_to_map(tilemap.to_local(pos))
			var type = selected.get_index()
			
			var tl = Vector2i(min(initial_click.x, target.x), min(initial_click.y, target.y))
			var br = Vector2i(max(initial_click.x, target.x), max(initial_click.y, target.y))
			
			# Fill from initial_target to target
			for y in range(tl.y, br.y + 1):
				for x in range(tl.x, br.x + 1):
					if paint_mode == PaintMode.PAINT:
						BetterTerrain.set_cell(tilemap, layer, Vector2i(x, y), type)
					else:
						tilemap.erase_cell(layer, Vector2i(x, y))
			
			BetterTerrain.update_terrain_area(tilemap, layer, tl - Vector2i.ONE, br + Vector2i.ONE)
			update_overlay.emit()
			
		paint_mode = PaintMode.NO_PAINT
		return true
	
	var clicked = event is InputEventMouseButton and event.pressed
	if clicked:
		paint_mode = PaintMode.NO_PAINT
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			paint_mode = PaintMode.PAINT
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			paint_mode = PaintMode.ERASE
		else:
			return false
	
	if (clicked or event is InputEventMouseMotion) and paint_mode != PaintMode.NO_PAINT:
		var tr = tilemap.get_viewport_transform() * tilemap.global_transform
		var pos = tr.affine_inverse() * event.position
		var target = tilemap.local_to_map(tilemap.to_local(pos))
		if clicked:
			initial_click = target
		var type = selected.get_index()
		
		if draw_button.button_pressed:
			if paint_mode == PaintMode.PAINT:
				BetterTerrain.set_cell(tilemap, layer, target, type)
			elif paint_mode == PaintMode.ERASE:
				tilemap.erase_cell(layer, target)
			BetterTerrain.update_terrain_area(tilemap, layer, target - Vector2i.ONE, target + Vector2i.ONE)
		elif fill_button.button_pressed:
			var cells = _get_fill_cells(target)
			if paint_mode == PaintMode.PAINT:
				BetterTerrain.set_cells(tilemap, layer, cells, type)
			elif paint_mode == PaintMode.ERASE:
				for c in cells:
					tilemap.erase_cell(layer, c)
			BetterTerrain.update_terrain_cells(tilemap, layer, cells)
		
		return true
	
	return false


func _on_layer_options_item_selected(index):
	layer = index
