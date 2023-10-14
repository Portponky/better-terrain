@tool
extends Control

signal update_overlay

# The maximum individual tiles the overlay will draw before shortcutting the display
# To prevent editor lag when drawing large rectangles or filling large areas
const MAX_CANVAS_RENDER_TILES = 1500
const TERRAIN_PROPERTIES_SCENE := preload("res://addons/better-terrain/editor/TerrainProperties.tscn")
const TERRAIN_ENTRY_SCENE := preload("res://addons/better-terrain/editor/TerrainEntry.tscn")

# Buttons
@onready var draw_button := $VBoxContainer/Toolbar/Draw
@onready var line_button := $VBoxContainer/Toolbar/Line
@onready var rectangle_button := $VBoxContainer/Toolbar/Rectangle
@onready var fill_button := $VBoxContainer/Toolbar/Fill
@onready var replace_button := $VBoxContainer/Toolbar/Replace

@onready var paint_type := $VBoxContainer/Toolbar/PaintType
@onready var paint_terrain := $VBoxContainer/Toolbar/PaintTerrain
@onready var select_tiles := $VBoxContainer/Toolbar/SelectTiles

@onready var paint_symmetry := $VBoxContainer/Toolbar/PaintSymmetry
@onready var symmetry_options = $VBoxContainer/Toolbar/SymmetryOptions

@onready var shuffle_random := $VBoxContainer/Toolbar/ShuffleRandom
@onready var zoom_slider := $VBoxContainer/Toolbar/Zoom

@onready var source_selector := $VBoxContainer/Toolbar/Sources
@onready var source_selector_popup := $VBoxContainer/Toolbar/Sources/Sources

@onready var clean_button := $VBoxContainer/Toolbar/Clean
@onready var layer_options := $VBoxContainer/Toolbar/LayerOptions

@onready var add_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/AddTerrain
@onready var edit_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/EditTerrain
@onready var pick_icon_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/PickIcon
@onready var move_up_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/MoveUp
@onready var move_down_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/MoveDown
@onready var remove_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/RemoveTerrain

@onready var scroll_container := $VBoxContainer/HSplitContainer/VBoxContainer/Panel/ScrollContainer
@onready var terrain_list := $VBoxContainer/HSplitContainer/VBoxContainer/Panel/ScrollContainer/TerrainList
@onready var tile_view := $VBoxContainer/HSplitContainer/Panel/ScrollArea/TileView
@onready var grid_mode_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/GridMode

var selected_entry := -2

@onready var terrain_icons := [
	load("res://addons/better-terrain/icons/MatchTiles.svg"),
	load("res://addons/better-terrain/icons/MatchVertices.svg"),
	load("res://addons/better-terrain/icons/NonModifying.svg"),
	load("res://addons/better-terrain/icons/Decoration.svg"),
]

var tilemap : TileMap
var tileset : TileSet

var undo_manager : EditorUndoRedoManager
var terrain_undo

var layer := 0
var draw_overlay := false
var initial_click : Vector2i
var prev_position : Vector2i
var current_position : Vector2i
var tileset_dirty := false

enum PaintMode {
	NO_PAINT,
	PAINT,
	ERASE
}

enum PaintAction {
	NO_ACTION,
	LINE
}

enum SourceSelectors {
	ALL = 1000000,
	NONE = 1000001,
}

var paint_mode := PaintMode.NO_PAINT

var paint_action := PaintAction.NO_ACTION


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	draw_button.icon = get_theme_icon("Edit", "EditorIcons")
	line_button.icon = get_theme_icon("Line", "EditorIcons")
	rectangle_button.icon = get_theme_icon("Rectangle", "EditorIcons")
	fill_button.icon = get_theme_icon("Bucket", "EditorIcons")
	select_tiles.icon = get_theme_icon("ToolSelect", "EditorIcons")
	add_terrain_button.icon = get_theme_icon("Add", "EditorIcons")
	edit_terrain_button.icon = get_theme_icon("Tools", "EditorIcons")
	pick_icon_button.icon = get_theme_icon("ColorPick", "EditorIcons")
	move_up_button.icon = get_theme_icon("ArrowUp", "EditorIcons")
	move_down_button.icon = get_theme_icon("ArrowDown", "EditorIcons")
	remove_terrain_button.icon = get_theme_icon("Remove", "EditorIcons")
	grid_mode_button.icon = get_theme_icon("Grid", "EditorIcons")
	
	select_tiles.button_group.pressed.connect(_on_bit_button_pressed)
	
	terrain_undo = load("res://addons/better-terrain/editor/TerrainUndo.gd").new()
	add_child(terrain_undo)
	tile_view.undo_manager = undo_manager
	tile_view.terrain_undo = terrain_undo
	
	tile_view.paste_occurred.connect(_on_paste_occurred)
	tile_view.change_zoom_level.connect(_on_change_zoom_level)
	tile_view.terrain_updated.connect(_on_terrain_updated)
	
	if Engine.get_version_info().hex < 0x040200:
		paint_symmetry.visible = false


func _process(delta):
	scroll_container.scroll_horizontal = 0


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
	for c in terrain_list.get_children():
		terrain_list.remove_child(c)
	
	# load terrains from tileset
	var terrain_count := BetterTerrain.terrain_count(tileset)
	var item_count = terrain_count + 1
	for i in terrain_count:
		var terrain := BetterTerrain.get_terrain(tileset, i)
		if i >= terrain_list.get_child_count():
			add_terrain_entry(terrain, i)
	
	if item_count > terrain_list.get_child_count():
		var terrain := BetterTerrain.get_terrain(tileset, BetterTerrain.TileCategory.EMPTY)
		if terrain.valid:
			add_terrain_entry(terrain, item_count - 1)
	
	while item_count < terrain_list.get_child_count():
		var child = terrain_list.get_child(terrain_list.get_child_count() - 1)
		terrain_list.remove_child(child)
		child.free()
	
	source_selector_popup.clear()
	source_selector_popup.add_item("All", SourceSelectors.ALL)
	source_selector_popup.add_item("None", SourceSelectors.NONE)
	var source_count = tileset.get_source_count() if tileset else 0
	for s in source_count:
		var source_id = tileset.get_source_id(s)
		var source := tileset.get_source(source_id)
		if !(source is TileSetAtlasSource):
			continue
		
		var name := source.resource_name
		if name.is_empty():
			var texture := (source as TileSetAtlasSource).texture
			var texture_name := texture.resource_name if texture else ""
			if !texture_name.is_empty():
				name = texture_name
			else:
				var texture_path := texture.resource_path if texture else ""
				if !texture_path.is_empty():
					name = texture_path.get_file()
		
		if !name.is_empty():
			name += " "
		name += " (ID: %d)" % source_id
		
		source_selector_popup.add_check_item(name, source_id)
		source_selector_popup.set_item_checked(source_selector_popup.get_item_index(source_id), true)
	source_selector.visible = source_selector_popup.item_count > 3 # All, None and more than one source
	
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
	_on_grid_mode_pressed()


func queue_tiles_changed() -> void:
	# Bring terrain data up to date with complex tileset changes
	if !tileset or tileset_dirty:
		return
	
	tileset_dirty = true
	tiles_changed.call_deferred()


func _on_entry_select(index:int):
	selected_entry = index
	if selected_entry >= BetterTerrain.terrain_count(tileset):
		selected_entry = BetterTerrain.TileCategory.EMPTY
	for i in range(terrain_list.get_child_count()):
		if i != index:
			terrain_list.get_child(i).set_selected(false)
	update_tile_view_paint()


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


func _on_grid_mode_pressed():
	for c in terrain_list.get_children():
		c.grid_mode = grid_mode_button.button_pressed
		c.update_style()


func update_tile_view_paint() -> void:
	tile_view.paint = selected_entry
	tile_view.queue_redraw()
	
	var editable = tile_view.paint != BetterTerrain.TileCategory.EMPTY
	edit_terrain_button.disabled = !editable
	move_up_button.disabled = !editable or tile_view.paint == 0
	move_down_button.disabled = !editable or tile_view.paint == BetterTerrain.terrain_count(tileset) - 1
	remove_terrain_button.disabled = !editable
	pick_icon_button.disabled = !editable


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
	popup.terrain_icon = ""
	popup.terrain_type = 0
	popup.popup_centered()
	await popup.visibility_changed
	if popup.accepted:
		undo_manager.create_action("Add terrain type", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(self, &"perform_add_terrain", popup.terrain_name, popup.terrain_color, popup.terrain_type, popup.terrain_categories, {path = popup.terrain_icon})
		undo_manager.add_undo_method(self, &"perform_remove_terrain", terrain_list.get_child_count() - 1)
		undo_manager.commit_action()
	popup.queue_free()


func _on_edit_terrain_pressed() -> void:
	if !tileset:
		return
	
	if selected_entry < 0:
		return
	
	var t := BetterTerrain.get_terrain(tileset, selected_entry)
	var categories = BetterTerrain.get_terrain_categories(tileset)
	categories = categories.filter(func(x): return x.id != selected_entry)
	
	var popup := generate_popup()
	popup.set_category_data(categories)
	
	t.icon = t.icon.duplicate()
	
	popup.terrain_name = t.name
	popup.terrain_type = t.type
	popup.terrain_color = t.color
	if t.has("icon") and t.icon.has("path"):
		popup.terrain_icon = t.icon.path
	popup.terrain_categories = t.categories
	popup.popup_centered()
	await popup.visibility_changed
	if popup.accepted:
		undo_manager.create_action("Edit terrain details", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(self, &"perform_edit_terrain", selected_entry, popup.terrain_name, popup.terrain_color, popup.terrain_type, popup.terrain_categories, {path = popup.terrain_icon})
		undo_manager.add_undo_method(self, &"perform_edit_terrain", selected_entry, t.name, t.color, t.type, t.categories, t.icon)
		if t.type != popup.terrain_type:
			terrain_undo.create_terrain_type_restore_point(undo_manager, tileset)
			terrain_undo.create_peering_restore_point_specific(undo_manager, tileset, selected_entry)
		undo_manager.commit_action()
	popup.queue_free()


func _on_pick_icon_pressed():
	if selected_entry < 0:
		return
	tile_view.pick_icon_terrain = selected_entry


func _on_pick_icon_focus_exited():
	tile_view.pick_icon_terrain_cancel = true
	pick_icon_button.button_pressed = false


func _on_move_pressed(down: bool) -> void:
	if !tileset:
		return
	
	if selected_entry < 0:
		return
	
	var index1 = selected_entry
	var index2 = index1 + (1 if down else -1)
	if index2 < 0 or index2 >= terrain_list.get_child_count():
		return
	
	undo_manager.create_action("Reorder terrains", UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(self, &"perform_swap_terrain", index1, index2)
	undo_manager.add_undo_method(self, &"perform_swap_terrain", index1, index2)
	undo_manager.commit_action()


func _on_remove_terrain_pressed() -> void:
	if !tileset:
		return
	
	if selected_entry < 0:
		return
	
	# store confirmation in array to pass by ref
	var t := BetterTerrain.get_terrain(tileset, selected_entry)
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
		undo_manager.add_do_method(self, &"perform_remove_terrain", selected_entry)
		undo_manager.add_undo_method(self, &"perform_add_terrain", t.name, t.color, t.type, t.categories, t.icon)
		for n in range(terrain_list.get_child_count() - 2, selected_entry, -1):
			undo_manager.add_undo_method(self, &"perform_swap_terrain", n, n - 1)
		if t.type == BetterTerrain.TerrainType.CATEGORY:
			terrain_undo.create_terrain_type_restore_point(undo_manager, tileset)
		terrain_undo.create_peering_restore_point_specific(undo_manager, tileset, selected_entry)
		undo_manager.commit_action()


func add_terrain_entry(terrain:Dictionary, index:int = -1):
	if index < 0:
		index = terrain_list.get_child_count()
	
	var entry = TERRAIN_ENTRY_SCENE.instantiate()
	entry.tileset = tileset
	entry.terrain = terrain
	entry.grid_mode = grid_mode_button.button_pressed
	entry.select.connect(_on_entry_select)
	
	terrain_list.add_child(entry)
	terrain_list.move_child(entry, index)


func remove_terrain_entry(index: int):
	terrain_list.get_child(index).free()
	for i in range(index, terrain_list.get_child_count()):
		var child = terrain_list.get_child(i)
		child.terrain = BetterTerrain.get_terrain(tileset, i)
		child.update()


func perform_add_terrain(name: String, color: Color, type: int, categories: Array, icon:Dictionary = {}) -> void:
	if BetterTerrain.add_terrain(tileset, name, color, type, categories, icon):
		var index = BetterTerrain.terrain_count(tileset) - 1
		var terrain = BetterTerrain.get_terrain(tileset, index)
		add_terrain_entry(terrain, index)


func perform_remove_terrain(index: int) -> void:
	if index >= BetterTerrain.terrain_count(tileset):
		return
	if BetterTerrain.remove_terrain(tileset, index):
		remove_terrain_entry(index)
		update_tile_view_paint()


func perform_swap_terrain(index1: int, index2: int) -> void:
	var lower := min(index1, index2)
	var higher := max(index1, index2)
	if lower >= terrain_list.get_child_count() or higher >= terrain_list.get_child_count():
		return
	var item1 = terrain_list.get_child(lower)
	var item2 = terrain_list.get_child(higher)
	if BetterTerrain.swap_terrains(tileset, lower, higher):
		terrain_list.move_child(item1, higher)
		item1.terrain = BetterTerrain.get_terrain(tileset, higher)
		item1.update()
		item2.terrain = BetterTerrain.get_terrain(tileset, lower)
		item2.update()
		selected_entry = index2
		terrain_list.get_child(index2).set_selected(true)
		update_tile_view_paint()


func perform_edit_terrain(index: int, name: String, color: Color, type: int, categories: Array, icon: Dictionary = {}) -> void:
	if index >= terrain_list.get_child_count():
		return
	var entry = terrain_list.get_child(index)
	# don't overwrite empty icon
	var valid_icon = icon
	if icon.has("path") and icon.path.is_empty():
		var terrain = BetterTerrain.get_terrain(tileset, index)
		valid_icon = terrain.icon
	if BetterTerrain.set_terrain(tileset, index, name, color, type, categories, valid_icon):
		entry.terrain = BetterTerrain.get_terrain(tileset, index)
		entry.update()
		tile_view.queue_redraw()


func _on_shuffle_random_pressed():
	BetterTerrain.use_seed = !shuffle_random.button_pressed 


func _on_bit_button_pressed(button: BaseButton) -> void:
	match select_tiles.button_group.get_pressed_button():
		select_tiles: tile_view.paint_mode = tile_view.PaintMode.SELECT
		paint_type: tile_view.paint_mode = tile_view.PaintMode.PAINT_TYPE
		paint_terrain: tile_view.paint_mode = tile_view.PaintMode.PAINT_PEERING
		paint_symmetry: tile_view.paint_mode = tile_view.PaintMode.PAINT_SYMMETRY
		_: tile_view.paint_mode = tile_view.PaintMode.NO_PAINT
	tile_view.queue_redraw()
	
	symmetry_options.visible = paint_symmetry.button_pressed


func _on_symmetry_selected(index):
	tile_view.paint_symmetry = index


func _on_layer_options_item_selected(index) -> void:
	layer = index


func _on_paste_occurred():
	select_tiles.button_pressed = true


func _on_change_zoom_level(value):
	zoom_slider.value = value


func _on_terrain_updated(index):
	var entry = terrain_list.get_child(index)
	entry.terrain = BetterTerrain.get_terrain(tileset, index)
	entry.update()


func canvas_draw(overlay: Control) -> void:
	if !draw_overlay:
		return
	
	if selected_entry < 0:
		return
	
	var type = selected_entry
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
	elif paint_action == PaintAction.LINE and paint_mode != PaintMode.NO_PAINT:
		var cells := _get_tileset_line(initial_click, current_position, tileset)
		var shape = BetterTerrain.data.cell_polygon(tileset)
		for c in cells:
			var tile_transform := Transform2D(0.0, tilemap.tile_set.tile_size, 0.0, tilemap.map_to_local(c))
			overlay.draw_colored_polygon(transform * tile_transform * shape, Color(terrain.color, 0.5))
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
	if selected_entry < 0:
		return false
	
	draw_overlay = true
	if event is InputEventMouseMotion:
		var tr := tilemap.get_viewport_transform() * tilemap.global_transform
		var pos := tr.affine_inverse() * Vector2(event.position)
		var event_position := tilemap.local_to_map(pos)
		prev_position = current_position
		if event_position == current_position:
			return false
		current_position = event_position
		update_overlay.emit()
	
	var replace_mode = replace_button.button_pressed
	
	var released : bool = event is InputEventMouseButton and !event.pressed
	if released:
		terrain_undo.finish_action()
		var type = selected_entry
		if rectangle_button.button_pressed and paint_mode != PaintMode.NO_PAINT:
			var area := Rect2i(initial_click, current_position - initial_click).abs()
			# Fill from initial_target to target
			undo_manager.create_action(tr("Draw terrain rectangle"), UndoRedo.MERGE_DISABLE, tilemap)
			for y in range(area.position.y, area.end.y + 1):
				for x in range(area.position.x, area.end.x + 1):
					var coord := Vector2i(x, y)
					if paint_mode == PaintMode.PAINT:
						if replace_mode:
							undo_manager.add_do_method(BetterTerrain, &"replace_cell", tilemap, layer, coord, type)
						else:
							undo_manager.add_do_method(BetterTerrain, &"set_cell", tilemap, layer, coord, type)
					else:
						undo_manager.add_do_method(tilemap, &"erase_cell", layer, coord)
			
			undo_manager.add_do_method(BetterTerrain, &"update_terrain_area", tilemap, layer, area)
			terrain_undo.create_tile_restore_point_area(undo_manager, tilemap, layer, area)
			undo_manager.commit_action()
			update_overlay.emit()
		elif paint_action == PaintAction.LINE and paint_mode != PaintMode.NO_PAINT:
			undo_manager.create_action(tr("Draw terrain line"), UndoRedo.MERGE_DISABLE, tilemap)
			var cells := _get_tileset_line(initial_click, current_position, tileset)
			if paint_mode == PaintMode.PAINT:
				if replace_mode:
					undo_manager.add_do_method(BetterTerrain, &"replace_cells", tilemap, layer, cells, type)
				else:
					undo_manager.add_do_method(BetterTerrain, &"set_cells", tilemap, layer, cells, type)
			elif paint_mode == PaintMode.ERASE:
				for c in cells:
					undo_manager.add_do_method(tilemap, &"erase_cell", layer, c)
			undo_manager.add_do_method(BetterTerrain, &"update_terrain_cells", tilemap, layer, cells)
			terrain_undo.create_tile_restore_point(undo_manager, tilemap, layer, cells)
			undo_manager.commit_action()
			update_overlay.emit()
		
		paint_mode = PaintMode.NO_PAINT
		return true
	
	var clicked : bool = event is InputEventMouseButton and event.pressed
	var shift : bool = event.shift_pressed
	if clicked:
		paint_mode = PaintMode.NO_PAINT
		
		if (draw_button.button_pressed and shift) or line_button.button_pressed:
			paint_action = PaintAction.LINE
		else:
			paint_action = PaintAction.NO_ACTION
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			paint_mode = PaintMode.PAINT
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			paint_mode = PaintMode.ERASE
		else:
			return false
	
	if (clicked or event is InputEventMouseMotion) and paint_mode != PaintMode.NO_PAINT:
		if clicked:
			initial_click = current_position
			terrain_undo.action_index += 1
			terrain_undo.action_count = 0
		var type = selected_entry
		
		if paint_action == PaintAction.LINE:
			# if painting as line, execution happens on release. 
			# prevent other painting actions from running.
			pass
		elif draw_button.button_pressed:
			undo_manager.create_action(tr("Draw terrain") + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tilemap, true)
			var cells := _get_tileset_line(prev_position, current_position, tileset)
			if paint_mode == PaintMode.PAINT:
				if replace_mode:
					terrain_undo.add_do_method(undo_manager, BetterTerrain, &"replace_cells", [tilemap, layer, cells, type])
				else:
					terrain_undo.add_do_method(undo_manager, BetterTerrain, &"set_cells", [tilemap, layer, cells, type])
			elif paint_mode == PaintMode.ERASE:
				for c in cells:
					terrain_undo.add_do_method(undo_manager, tilemap, &"erase_cell", [layer, c])
			terrain_undo.add_do_method(undo_manager, BetterTerrain, &"update_terrain_cells", [tilemap, layer, cells])
			terrain_undo.create_tile_restore_point(undo_manager, tilemap, layer, cells)
			undo_manager.commit_action()
			terrain_undo.action_count += 1
		elif fill_button.button_pressed:
			var cells := _get_fill_cells(current_position)
			undo_manager.create_action(tr("Fill terrain"), UndoRedo.MERGE_DISABLE, tilemap)
			if paint_mode == PaintMode.PAINT:
				if replace_mode:
					undo_manager.add_do_method(BetterTerrain, &"replace_cells", tilemap, layer, cells, type)
				else:
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


func _shortcut_input(event) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_C and event.ctrl_pressed and not event.echo:
			get_viewport().set_input_as_handled()
			tile_view.copy_selection()
		if event.keycode == KEY_V and event.ctrl_pressed and not event.echo:
			get_viewport().set_input_as_handled()
			tile_view.paste_selection()


## bresenham alg ported from Geometry2D::bresenham_line()
func _get_line(from:Vector2i, to:Vector2i) -> Array[Vector2i]:
	if from == to:
		return [to]
	
	var points:Array[Vector2i] = []
	var delta := (to - from).abs() * 2
	var step := (to - from).sign()
	var current := from
	
	if delta.x > delta.y:
		var err:int = delta.x / 2
		while current.x != to.x:
			points.push_back(current);
			err -= delta.y
			if err < 0:
				current.y += step.y
				err += delta.x
			current.x += step.x
	else:
		var err:int = delta.y / 2
		while current.y != to.y:
			points.push_back(current)
			err -= delta.x
			if err < 0:
				current.x += step.x
				err += delta.y
			current.y += step.y
	
	points.push_back(current);
	return points;


## half-offset bresenham alg ported from TileMapEditor::get_line
func _get_tileset_line(from:Vector2i, to:Vector2i, tileset:TileSet) -> Array[Vector2i]:
	if tileset.tile_shape == TileSet.TILE_SHAPE_SQUARE:
		return _get_line(from, to)
	
	var points:Array[Vector2i] = []
	
	var transposed := tileset.get_tile_offset_axis() == TileSet.TILE_OFFSET_AXIS_VERTICAL
	if transposed:
		from = Vector2i(from.y, from.x)
		to = Vector2i(to.y, to.x)

	var delta:Vector2i = to - from
	delta = Vector2i(2 * delta.x + abs(posmod(to.y, 2)) - abs(posmod(from.y, 2)), delta.y)
	var sign:Vector2i = delta.sign()

	var current := from;
	points.push_back(Vector2i(current.y, current.x) if transposed else current)

	var err := 0
	if abs(delta.y) < abs(delta.x):
		var err_step:Vector2i = 3 * delta.abs()
		while current != to:
			err += err_step.y
			if err > abs(delta.x):
				if sign.x == 0:
					current += Vector2i(sign.y, 0)
				else:
					current += Vector2i(sign.x if bool(current.y % 2) != (sign.x < 0) else 0, sign.y)
				err -= err_step.x
			else:
				current += Vector2i(sign.x, 0)
				err += err_step.y
			points.push_back(Vector2i(current.y, current.x) if transposed else current)
	else:
		var err_step:Vector2i = delta.abs()
		while current != to:
			err += err_step.x
			if err > 0:
				if sign.x == 0:
					current += Vector2i(0, sign.y)
				else:
					current += Vector2i(sign.x if bool(current.y % 2) != (sign.x < 0) else 0, sign.y)
				err -= err_step.y;
			else:
				if sign.x == 0:
					current += Vector2i(0, sign.y)
				else:
					current += Vector2i(-sign.x if bool(current.y % 2) != (sign.x > 0) else 0, sign.y)
				err += err_step.y
			points.push_back(Vector2i(current.y, current.x) if transposed else current)
	
	return points


func _on_terrain_enable_id_pressed(id):
	if id in [SourceSelectors.ALL, SourceSelectors.NONE]:
		for i in source_selector_popup.item_count:
			if source_selector_popup.is_item_checkable(i):
				source_selector_popup.set_item_checked(i, id == SourceSelectors.ALL)
	else:
		var index = source_selector_popup.get_item_index(id)
		var checked = source_selector_popup.is_item_checked(index)
		source_selector_popup.set_item_checked(index, !checked)
	
	var disabled_sources : Array[int]
	for i in source_selector_popup.item_count:
		if source_selector_popup.is_item_checkable(i) and !source_selector_popup.is_item_checked(i):
			disabled_sources.append(source_selector_popup.get_item_id(i))
	tile_view.disabled_sources = disabled_sources

