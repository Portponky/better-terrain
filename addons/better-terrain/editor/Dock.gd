@tool
extends Control

signal update_overlay

# The maximum individual tiles the overlay will draw before shortcutting the display
# To prevent editor lag when drawing large rectangles or filling large areas
const MAX_CANVAS_RENDER_TILES = 1500
const TERRAIN_PROPERTIES_SCENE := preload("res://addons/better-terrain/editor/TerrainProperties.tscn")

# Buttons
@onready var draw_button := $VBoxContainer/Toolbar/Draw
@onready var rectangle_button := $VBoxContainer/Toolbar/Rectangle
@onready var fill_button := $VBoxContainer/Toolbar/Fill

@onready var paint_type := $VBoxContainer/Toolbar/PaintType
@onready var paint_terrain := $VBoxContainer/Toolbar/PaintTerrain

@onready var clean_button := $VBoxContainer/Toolbar/Clean
@onready var layer_options := $VBoxContainer/Toolbar/LayerOptions

@onready var add_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/AddTerrain
@onready var edit_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/EditTerrain
@onready var move_up_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/MoveUp
@onready var move_down_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/MoveDown
@onready var remove_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/RemoveTerrain

@onready var terrain_tree := $VBoxContainer/HSplitContainer/VBoxContainer/Panel/Tree
@onready var tile_view := $VBoxContainer/HSplitContainer/Panel/ScrollArea/TileView

@onready var terrain_icons := [
	load("res://addons/better-terrain/icons/MatchTiles.svg"),
	load("res://addons/better-terrain/icons/MatchVertices.svg"),
	load("res://addons/better-terrain/icons/NonModifying.svg"),
]

var tilemap : TileMap
var tileset : TileSet

var undo_manager : EditorUndoRedoManager
var terrain_undo

var layer := 0
var draw_overlay := false
var initial_click : Vector2i
var current_position : Vector2i
var tileset_dirty := false

enum PaintMode {
	NO_PAINT,
	PAINT,
	ERASE
}

var paint_mode := PaintMode.NO_PAINT


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
	
	terrain_undo = load("res://addons/better-terrain/editor/TerrainUndo.gd").new()
	add_child(terrain_undo)
	tile_view.undo_manager = undo_manager
	tile_view.terrain_undo = terrain_undo


func _get_fill_cells(target: Vector2i) -> Array:
	var pick := BetterTerrain.get_cell(tilemap, layer, target)
	var bounds := tilemap.get_used_rect()
	var neighbors = BetterTerrain.data.cells_adjacent_for_fill(tileset)
	
	# No sets yet, so use a dictionary
	var checked := {}
	var pending := [target]
	var goal := []
	
	while !pending.is_empty():
		var p = pending.pop_front()
		if checked.has(p):
			continue
		checked[p] = true
		if !bounds.has_point(p) or BetterTerrain.get_cell(tilemap, layer, p) != pick:
			continue
		
		goal.append(p)
		pending.append_array(BetterTerrain.data.neighboring_coords(tilemap, p, neighbors))
	
	return goal


func tiles_about_to_change() -> void:
	if tileset and tileset.changed.is_connected(queue_tiles_changed):
		tileset.changed.disconnect(queue_tiles_changed)


func tiles_changed() -> void:
	# ensure up to date
	BetterTerrain._update_terrain_data(tileset)
	
	# clear terrains
	var root = terrain_tree.get_root()
	
	# load terrains from tileset
	var terrain_count := BetterTerrain.terrain_count(tileset)
	for i in terrain_count:
		var terrain := BetterTerrain.get_terrain(tileset, i)
		if i >= root.get_child_count():
			terrain_tree.create_item(root)
		var item = root.get_child(i)
		item.set_text(0, terrain.name)
		item.set_icon(0, terrain_icons[terrain.type])
		item.set_icon_modulate(0, terrain.color)
	
	while terrain_count < root.get_child_count():
		var child = root.get_child(root.get_child_count() - 1)
		root.remove_child(child)
		child.free()
	
	layer_options.clear()
	if tilemap and tilemap.get_layers_count() == 0:
		layer_options.text = tr("No layers")
		layer_options.disabled = true
		layer = 0
	elif tilemap:
		for n in tilemap.get_layers_count():
			var name := tilemap.get_layer_name(n)
			if name.is_empty():
				name = tr("Layer {0}").format([n])
			layer_options.add_item(name, n)
			layer_options.set_item_disabled(n, !tilemap.is_layer_enabled(n))
		layer_options.disabled = false
		layer = min(layer, tilemap.get_layers_count() - 1)
		layer_options.selected = layer
	
	update_tile_view_paint()
	tile_view.refresh_tileset(tileset)
	
	if tileset and !tileset.changed.is_connected(queue_tiles_changed):
		tileset.changed.connect(queue_tiles_changed)
	
	clean_button.visible = BetterTerrain._has_invalid_peering_types(tileset)
	
	tileset_dirty = false


func queue_tiles_changed() -> void:
	# Bring terrain data up to date with complex tileset changes
	if !tileset or tileset_dirty:
		return
	
	tileset_dirty = true
	call_deferred(&"tiles_changed")


func _on_clean_pressed() -> void:
	var confirmed := [false]
	var popup := ConfirmationDialog.new()
	popup.dialog_text = tr("Tile set changes have caused terrain to become invalid. Remove invalid terrain data?")
	popup.dialog_hide_on_ok = false
	popup.confirmed.connect(func():
		confirmed[0] = true
		popup.hide()
	)
	add_child(popup)
	popup.popup_centered()
	await popup.visibility_changed
	popup.queue_free()
	
	if confirmed[0]:
		undo_manager.create_action("Clean invalid terrain peering data", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(BetterTerrain, &"_clear_invalid_peering_types", tileset)
		undo_manager.add_do_method(self, &"tiles_changed")
		terrain_undo.create_peering_restore_point(undo_manager, tileset)
		undo_manager.add_undo_method(self, &"tiles_changed")
		undo_manager.commit_action()


func update_tile_view_paint() -> void:
	var selected = terrain_tree.get_selected()
	tile_view.paint = selected.get_index() if selected else -1
	tile_view.queue_redraw()


func generate_popup() -> ConfirmationDialog:
	var popup := TERRAIN_PROPERTIES_SCENE.instantiate()
	add_child(popup)
	return popup


func _on_add_terrain_pressed() -> void:
	if !tileset:
		return
	
	var popup := generate_popup()
	popup.set_category_data(BetterTerrain.get_terrain_categories(tileset))
	popup.terrain_name = "New terrain"
	popup.terrain_color = Color.from_hsv(randf(), 0.3 + 0.7 * randf(), 0.6 + 0.4 * randf())
	popup.terrain_type = 0
	popup.popup_centered()
	await popup.visibility_changed
	if popup.accepted:
		undo_manager.create_action("Add terrain type", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(self, &"perform_add_terrain", popup.terrain_name, popup.terrain_color, popup.terrain_type, popup.terrain_categories)
		undo_manager.add_undo_method(self, &"perform_remove_terrain", terrain_tree.get_root().get_child_count())
		undo_manager.commit_action()
	popup.queue_free()


func _on_edit_terrain_pressed() -> void:
	if !tileset:
		return
	
	var item = terrain_tree.get_selected()
	if !item:
		return
	var index = item.get_index()
	
	var t := BetterTerrain.get_terrain(tileset, item.get_index())
	var categories = BetterTerrain.get_terrain_categories(tileset)
	categories = categories.filter(func(x): return x.id != index)
	
	var popup := generate_popup()
	popup.set_category_data(categories)
	
	popup.terrain_name = t.name
	popup.terrain_type = t.type
	popup.terrain_color = t.color
	popup.terrain_categories = t.categories
	popup.popup_centered()
	await popup.visibility_changed
	if popup.accepted:
		undo_manager.create_action("Edit terrain details", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(self, &"perform_edit_terrain", index, popup.terrain_name, popup.terrain_color, popup.terrain_type, popup.terrain_categories)
		undo_manager.add_undo_method(self, &"perform_edit_terrain", index, t.name, t.color, t.type, t.categories)
		if t.type != popup.terrain_type:
			terrain_undo.create_terran_type_restore_point(undo_manager, tileset)
			terrain_undo.create_peering_restore_point_specific(undo_manager, tileset, index)
		undo_manager.commit_action()
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
	
	undo_manager.create_action("Reorder terrains", UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(self, &"perform_swap_terrain", index1, index2)
	undo_manager.add_undo_method(self, &"perform_swap_terrain", index1, index2)
	undo_manager.commit_action()


func _on_remove_terrain_pressed() -> void:
	if !tileset:
		return
	
	var item = terrain_tree.get_selected()
	if !item:
		return
	
	# store confirmation in array to pass by ref
	var t := BetterTerrain.get_terrain(tileset, item.get_index())
	var confirmed := [false]
	var popup := ConfirmationDialog.new()
	popup.dialog_text = tr("Are you sure you want to remove {0}?").format([t.name])
	popup.dialog_hide_on_ok = false
	popup.confirmed.connect(func():
		confirmed[0] = true
		popup.hide()
	)
	add_child(popup)
	popup.popup_centered()
	await popup.visibility_changed
	popup.queue_free()
	
	if confirmed[0]:
		undo_manager.create_action("Remove terrain type", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(self, &"perform_remove_terrain", item.get_index())
		undo_manager.add_undo_method(self, &"perform_add_terrain", t.name, t.color, t.type)
		for n in range(terrain_tree.get_root().get_child_count() - 1, item.get_index(), -1):
			undo_manager.add_undo_method(self, &"perform_swap_terrain", n, n - 1)
		if t.type == BetterTerrain.TerrainType.CATEGORY:
			terrain_undo.create_terran_type_restore_point(undo_manager, tileset)
		terrain_undo.create_peering_restore_point_specific(undo_manager, tileset, item.get_index())
		undo_manager.commit_action()


func perform_add_terrain(name: String, color: Color, type: int, categories: Array) -> void:
	if BetterTerrain.add_terrain(tileset, name, color, type, categories):
		var new_terrain = terrain_tree.create_item(terrain_tree.get_root())
		new_terrain.set_text(0, name)
		new_terrain.set_icon(0, terrain_icons[type])
		new_terrain.set_icon_modulate(0, color)


func perform_remove_terrain(index: int) -> void:
	var root = terrain_tree.get_root()
	if index >= root.get_child_count():
		return
	var item = root.get_child(index)
	if BetterTerrain.remove_terrain(tileset, index):
		item.free()
		update_tile_view_paint()


func perform_swap_terrain(index1: int, index2: int) -> void:
	var lower := min(index1, index2)
	var higher := max(index1, index2)
	var root = terrain_tree.get_root()
	if lower >= root.get_child_count() or higher >= root.get_child_count():
		return
	var item1 = root.get_child(lower)
	var item2 = root.get_child(higher)
	if BetterTerrain.swap_terrains(tileset, lower, higher):
		item2.move_before(item1)
		item1.move_after(root.get_child(higher))
		update_tile_view_paint()


func perform_edit_terrain(index: int, name: String, color: Color, type: int, categories: Array) -> void:
	var root = terrain_tree.get_root()
	if index >= root.get_child_count():
		return
	var item = root.get_child(index)
	if BetterTerrain.set_terrain(tileset, index, name, color, type, categories):
		item.set_text(0, name)
		item.set_icon(0, terrain_icons[type])
		item.set_icon_modulate(0, color)
		tile_view.queue_redraw()


func _on_draw_pressed() -> void:
	draw_button.button_pressed = true
	rectangle_button.button_pressed = false
	fill_button.button_pressed = false


func _on_rectangle_pressed() -> void:
	draw_button.button_pressed = false
	rectangle_button.button_pressed = true
	fill_button.button_pressed = false


func _on_fill_pressed() -> void:
	draw_button.button_pressed = false
	rectangle_button.button_pressed = false
	fill_button.button_pressed = true


func _on_paint_type_pressed() -> void:
	paint_terrain.button_pressed = false
	tile_view.paint_mode = tile_view.PaintMode.PAINT_TYPE if paint_type.button_pressed else tile_view.PaintMode.NO_PAINT


func _on_paint_terrain_pressed() -> void:
	paint_type.button_pressed = false
	tile_view.paint_mode = tile_view.PaintMode.PAINT_PEERING if paint_terrain.button_pressed else tile_view.PaintMode.NO_PAINT


func _on_layer_options_item_selected(index) -> void:
	layer = index


func canvas_draw(overlay: Control) -> void:
	if !draw_overlay:
		return
	
	var selected = terrain_tree.get_selected()
	if !selected:
		return
	
	var type = selected.get_index()
	var terrain := BetterTerrain.get_terrain(tileset, type)
	if !terrain.valid:
		return
	
	var tiles := []
	var transform := tilemap.get_viewport_transform() * tilemap.global_transform
	
	if rectangle_button.button_pressed and paint_mode != PaintMode.NO_PAINT:
		var area := Rect2i(initial_click, current_position - initial_click).abs()

		# Shortcut fill for large areas
		if area.size.x > 1 and area.size.y > 1 and area.size.x * area.size.y > MAX_CANVAS_RENDER_TILES:
			var shortcut := PackedVector2Array([
				tilemap.map_to_local(area.position),
				tilemap.map_to_local(Vector2i(area.end.x, area.position.y)),
				tilemap.map_to_local(area.end),
				tilemap.map_to_local(Vector2i(area.position.x, area.end.y))
			])
			overlay.draw_colored_polygon(transform * shortcut, Color(terrain.color, 0.5))
			return
		
		for y in range(area.position.y, area.end.y + 1):
			for x in range(area.position.x, area.end.x + 1):
				tiles.append(Vector2i(x, y))
	elif fill_button.button_pressed:
		tiles = _get_fill_cells(current_position)
		if tiles.size() > MAX_CANVAS_RENDER_TILES:
			tiles.resize(MAX_CANVAS_RENDER_TILES)
	else:
		tiles.append(current_position)
	
	var shape = BetterTerrain.data.cell_polygon(tileset)
	for t in tiles:
		var tile_transform := Transform2D(0.0, tilemap.tile_set.tile_size, 0.0, tilemap.map_to_local(t))
		overlay.draw_colored_polygon(transform * tile_transform * shape, Color(terrain.color, 0.5))


func canvas_input(event: InputEvent) -> bool:
	var selected = terrain_tree.get_selected()
	if !selected:
		return false
	
	draw_overlay = true
	if event is InputEventMouseMotion:
		var tr := tilemap.get_viewport_transform() * tilemap.global_transform
		var pos := tr.affine_inverse() * Vector2(event.position)
		var event_position := tilemap.local_to_map(pos)
		if event_position == current_position:
			return false
		current_position = event_position
		update_overlay.emit()
	
	if event is InputEventMouseButton and !event.pressed:
		if rectangle_button.button_pressed and paint_mode != PaintMode.NO_PAINT:
			var type = selected.get_index()
			var area := Rect2i(initial_click, current_position - initial_click).abs()
			
			# Fill from initial_target to target
			undo_manager.create_action(tr("Draw terrain rectangle"), UndoRedo.MERGE_DISABLE, tilemap)
			for y in range(area.position.y, area.end.y + 1):
				for x in range(area.position.x, area.end.x + 1):
					var coord := Vector2i(x, y)
					if paint_mode == PaintMode.PAINT:
						undo_manager.add_do_method(BetterTerrain, &"set_cell", tilemap, layer, coord, type)
					else:
						undo_manager.add_do_method(tilemap, &"erase_cell", layer, coord)
			
			undo_manager.add_do_method(BetterTerrain, &"update_terrain_area", tilemap, layer, area)
			terrain_undo.create_tile_restore_point_area(undo_manager, tilemap, layer, area)
			undo_manager.commit_action()
			update_overlay.emit()
			
		paint_mode = PaintMode.NO_PAINT
		return true
	
	var clicked : bool = event is InputEventMouseButton and event.pressed
	if clicked:
		paint_mode = PaintMode.NO_PAINT
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			paint_mode = PaintMode.PAINT
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			paint_mode = PaintMode.ERASE
		else:
			return false
	
	if (clicked or event is InputEventMouseMotion) and paint_mode != PaintMode.NO_PAINT:
		if clicked:
			initial_click = current_position
		var type = selected.get_index()
		
		if draw_button.button_pressed:
			undo_manager.create_action(tr("Draw terrain"), UndoRedo.MERGE_DISABLE, tilemap)
			if paint_mode == PaintMode.PAINT:
				undo_manager.add_do_method(BetterTerrain, &"set_cell", tilemap, layer, current_position, type)
			elif paint_mode == PaintMode.ERASE:
				undo_manager.add_do_method(tilemap, &"erase_cell", layer, current_position)
			undo_manager.add_do_method(BetterTerrain, &"update_terrain_cell", tilemap, layer, current_position)
			terrain_undo.create_tile_restore_point(undo_manager, tilemap, layer, [current_position])
			undo_manager.commit_action()
		elif fill_button.button_pressed:
			var cells := _get_fill_cells(current_position)
			undo_manager.create_action(tr("Fill terrain"), UndoRedo.MERGE_DISABLE, tilemap)
			if paint_mode == PaintMode.PAINT:
				undo_manager.add_do_method(BetterTerrain, &"set_cells", tilemap, layer, cells, type)
			elif paint_mode == PaintMode.ERASE:
				for c in cells:
					undo_manager.add_do_method(tilemap, &"erase_cell", layer, c)
			undo_manager.add_do_method(BetterTerrain, &"update_terrain_cells", tilemap, layer, cells)
			terrain_undo.create_tile_restore_point(undo_manager, tilemap, layer, cells)
			undo_manager.commit_action()
		
		update_overlay.emit()
		return true
	
	return false


func canvas_mouse_exit() -> void:
	draw_overlay = false
	update_overlay.emit()
