@tool
extends Control

signal paste_occurred
signal change_zoom_level(value)
signal terrain_updated(index)

@onready var checkerboard := get_theme_icon("Checkerboard", "EditorIcons")

@onready var paint_symmetry_icons := [
	null,
	preload("res://addons/better-terrain/icons/paint-symmetry/SymmetryMirror.svg"),
	preload("res://addons/better-terrain/icons/paint-symmetry/SymmetryFlip.svg"),
	preload("res://addons/better-terrain/icons/paint-symmetry/SymmetryReflect.svg"),
	preload("res://addons/better-terrain/icons/paint-symmetry/SymmetryRotateClockwise.svg"),
	preload("res://addons/better-terrain/icons/paint-symmetry/SymmetryRotateCounterClockwise.svg"),
	preload("res://addons/better-terrain/icons/paint-symmetry/SymmetryRotate180.svg"),
	preload("res://addons/better-terrain/icons/paint-symmetry/SymmetryRotateAll.svg"),
	preload("res://addons/better-terrain/icons/paint-symmetry/SymmetryAll.svg"),
]

# Draw checkerboard and tiles with specific  materials in
# individual canvas items via rendering server
var _canvas_item_map = {}
var _canvas_item_background : RID

var tileset: TileSet
var disabled_sources: Array[int] = []: set = set_disabled_sources

var paint := BetterTerrain.TileCategory.NON_TERRAIN
var paint_symmetry := BetterTerrain.SymmetryType.NONE
var highlighted_tile_part := { valid = false }
var zoom_level := 1.0

var tiles_size : Vector2
var tile_size : Vector2i
var tile_part_size : Vector2
var alternate_size : Vector2
var alternate_lookup := []
var initial_click : Vector2i
var prev_position : Vector2i
var current_position : Vector2i

var selection_start : Vector2i
var selection_end : Vector2i
var selection_rect : Rect2i
var selected_tile_states : Array[Dictionary] = []
var copied_tile_states : Array[Dictionary] = []
var staged_paste_tile_states : Array[Dictionary] = []

var pick_icon_terrain : int = -1
var pick_icon_terrain_cancel := false

var undo_manager : EditorUndoRedoManager
var terrain_undo

# Modes for painting
enum PaintMode {
	NO_PAINT,
	PAINT_TYPE,
	PAINT_PEERING,
	PAINT_SYMMETRY,
	SELECT,
	PASTE
}

var paint_mode := PaintMode.NO_PAINT

# Actual interactions for painting
enum PaintAction {
	NO_ACTION,
	DRAW_TYPE,
	ERASE_TYPE,
	DRAW_PEERING,
	ERASE_PEERING,
	DRAW_SYMMETRY,
	ERASE_SYMMETRY,
	SELECT,
	PASTE
}

var paint_action := PaintAction.NO_ACTION

const ALTERNATE_TILE_MARGIN := 18

func _enter_tree() -> void:
	_canvas_item_background = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_canvas_item_background, get_canvas_item())
	RenderingServer.canvas_item_set_draw_behind_parent(_canvas_item_background, true)


func _exit_tree() -> void:
	RenderingServer.free_rid(_canvas_item_background)
	for p in _canvas_item_map:
		RenderingServer.free_rid(_canvas_item_map[p])
	_canvas_item_map.clear()


func refresh_tileset(ts: TileSet) -> void:
	tileset = ts
	
	tiles_size = Vector2.ZERO
	alternate_size = Vector2.ZERO
	alternate_lookup = []
	disabled_sources = []
	
	if !tileset:
		return
	
	for s in tileset.get_source_count():
		var source_id := tileset.get_source_id(s)
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if !source or !source.texture:
			continue
		
		tiles_size.x = max(tiles_size.x, source.texture.get_width())
		tiles_size.y += source.texture.get_height()
		
		tile_size = source.texture_region_size
		tile_part_size = Vector2(tile_size) / 3.0
		
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			var alt_count := source.get_alternative_tiles_count(coord)
			if alt_count <= 1:
				continue
			
			var rect := source.get_tile_texture_region(coord, 0)
			alternate_lookup.append([rect.size, source_id, coord])
			alternate_size.x = max(alternate_size.x, rect.size.x * (alt_count - 1))
			alternate_size.y += rect.size.y
	
	_on_zoom_value_changed(zoom_level)


func is_tile_in_source(source: TileSetAtlasSource, coord: Vector2i) -> bool:
	var origin := source.get_tile_at_coords(coord)
	if origin == Vector2i(-1, -1):
		return false
	
	# Animation frames are not needed
	var size := source.get_tile_size_in_atlas(origin)
	return coord.x < origin.x + size.x and coord.y < origin.y + size.y


func _build_tile_part_from_position(result: Dictionary, position: Vector2i, rect: Rect2) -> void:
	result.rect = rect
	var type := BetterTerrain.get_tile_terrain_type(result.data)
	if type == BetterTerrain.TileCategory.NON_TERRAIN:
		return
	result.terrain_type = type
	
	var normalize_position := (Vector2(position) - rect.position) / rect.size
	
	var terrain := BetterTerrain.get_terrain(tileset, type)
	if !terrain.valid:
		return
	for p in BetterTerrain.data.get_terrain_peering_cells(tileset, terrain.type):
		var side_polygon = BetterTerrain.data.peering_polygon(tileset, terrain.type, p)
		if Geometry2D.is_point_in_polygon(normalize_position, side_polygon):
			result.peering = p
			result.polygon = side_polygon
			break


func tile_part_from_position(position: Vector2i) -> Dictionary:
	if !tileset:
		return { valid = false }
	
	var offset := Vector2.ZERO
	var alt_offset := Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	if Rect2(alt_offset, zoom_level * alternate_size).has_point(position):
		for a in alternate_lookup:
			if a[1] in disabled_sources:
				continue
			var next_offset_y = alt_offset.y + zoom_level * a[0].y
			if position.y > next_offset_y:
				alt_offset.y = next_offset_y
				continue
			
			var source := tileset.get_source(a[1]) as TileSetAtlasSource
			if !source:
				break
			
			var count := source.get_alternative_tiles_count(a[2])
			var index := int((position.x - alt_offset.x) / (zoom_level * a[0].x)) + 1
			
			if index < count:
				var alt_id := source.get_alternative_tile_id(a[2], index)
				var target_rect := Rect2(
					alt_offset + Vector2.RIGHT * (index - 1) * zoom_level * a[0].x,
					zoom_level * a[0]
				)
				
				var result := {
					valid = true,
					source_id = a[1],
					coord = a[2],
					alternate = alt_id,
					data = source.get_tile_data(a[2], alt_id)
				}
				_build_tile_part_from_position(result, position, target_rect)
				return result
	
	else:
		for s in tileset.get_source_count():
			var source_id := tileset.get_source_id(s)
			if source_id in disabled_sources:
				continue
			var source := tileset.get_source(source_id) as TileSetAtlasSource
			if !source || !source.texture:
				continue
			for t in source.get_tiles_count():
				var coord := source.get_tile_id(t)
				var rect := source.get_tile_texture_region(coord, 0)
				var target_rect := Rect2(offset + zoom_level * rect.position, zoom_level * rect.size)
				if !target_rect.has_point(position):
					continue
				
				var result := {
					valid = true,
					source_id = source_id,
					coord = coord,
					alternate = 0,
					data = source.get_tile_data(coord, 0)
				}
				_build_tile_part_from_position(result, position, target_rect)
				return result
			
			offset.y += zoom_level * source.texture.get_height()
	
	return { valid = false }


func tile_rect_from_position(position: Vector2i) -> Rect2:
	if !tileset:
		return Rect2(-1,-1,0,0)
	
	var offset := Vector2.ZERO
	var alt_offset := Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	if Rect2(alt_offset, zoom_level * alternate_size).has_point(position):
		for a in alternate_lookup:
			if a[1] in disabled_sources:
				continue
			var next_offset_y = alt_offset.y + zoom_level * a[0].y
			if position.y > next_offset_y:
				alt_offset.y = next_offset_y
				continue
			
			var source := tileset.get_source(a[1]) as TileSetAtlasSource
			if !source:
				break
			
			var count := source.get_alternative_tiles_count(a[2])
			var index := int((position.x - alt_offset.x) / (zoom_level * a[0].x)) + 1
			
			if index < count:
				var target_rect := Rect2(
					alt_offset + Vector2.RIGHT * (index - 1) * zoom_level * a[0].x,
					zoom_level * a[0]
				)
				return target_rect
	
	else:
		for s in tileset.get_source_count():
			var source_id := tileset.get_source_id(s)
			if source_id in disabled_sources:
				continue
			var source := tileset.get_source(source_id) as TileSetAtlasSource
			if !source:
				continue
			for t in source.get_tiles_count():
				var coord := source.get_tile_id(t)
				var rect := source.get_tile_texture_region(coord, 0)
				var target_rect := Rect2(offset + zoom_level * rect.position, zoom_level * rect.size)
				if target_rect.has_point(position):
					return target_rect
			
			offset.y += zoom_level * source.texture.get_height()
	
	return Rect2(-1,-1,0,0)


func tile_parts_from_rect(rect:Rect2) -> Array[Dictionary]:
	if !tileset:
		return []
	
	var tiles:Array[Dictionary] = []
	
	var offset := Vector2.ZERO
	var alt_offset := Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	for s in tileset.get_source_count():
		var source_id := tileset.get_source_id(s)
		if source_id in disabled_sources:
			continue
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if !source:
			continue
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			var tile_rect := source.get_tile_texture_region(coord, 0)
			var target_rect := Rect2(offset + zoom_level * tile_rect.position, zoom_level * tile_rect.size)
			if target_rect.intersects(rect):
				var result := {
					valid = true,
					source_id = source_id,
					coord = coord,
					alternate = 0,
					data = source.get_tile_data(coord, 0)
				}
				var pos = target_rect.position + target_rect.size/2
				_build_tile_part_from_position(result, pos, target_rect)
				tiles.push_back(result)
			var alt_count := source.get_alternative_tiles_count(coord)
			for a in alt_count:
				var alt_id := 0
				if a == 0:
					continue
				
				target_rect = Rect2(alt_offset + zoom_level * (a - 1) * tile_rect.size.x * Vector2.RIGHT, zoom_level * tile_rect.size)
				alt_id = source.get_alternative_tile_id(coord, a)
				if target_rect.intersects(rect):
					var td := source.get_tile_data(coord, alt_id)
					var result := {
						valid = true,
						source_id = source_id,
						coord = coord,
						alternate = alt_id,
						data = td
					}
					var pos = target_rect.position + target_rect.size/2
					_build_tile_part_from_position(result, pos, target_rect)
					tiles.push_back(result)
			if alt_count > 1:
				alt_offset.y += zoom_level * tile_rect.size.y
		
		offset.y += zoom_level * source.texture.get_height()
	
	return tiles


func _get_canvas_item(td: TileData) -> RID:
	if !td.material:
		return self.get_canvas_item()
	if _canvas_item_map.has(td.material):
		return _canvas_item_map[td.material]
	
	var rid = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_material(rid, td.material.get_rid())
	RenderingServer.canvas_item_set_parent(rid, get_canvas_item())
	RenderingServer.canvas_item_set_draw_behind_parent(rid, true)
	RenderingServer.canvas_item_set_default_texture_filter(rid, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)
	_canvas_item_map[td.material] = rid
	return rid


func _draw_tile_data(texture: Texture2D, rect: Rect2, src_rect: Rect2, td: TileData, draw_sides: bool = true) -> void:
	var flipped_rect := rect
	if td.flip_h:
		flipped_rect.size.x = -rect.size.x
	if td.flip_v:
		flipped_rect.size.y = -rect.size.y
	
	RenderingServer.canvas_item_add_texture_rect_region(
		_get_canvas_item(td),
		flipped_rect,
		texture.get_rid(),
		src_rect,
		td.modulate,
		td.transpose
	)
	
	var type := BetterTerrain.get_tile_terrain_type(td)
	if type == BetterTerrain.TileCategory.NON_TERRAIN:
		draw_rect(rect, Color(0.1, 0.1, 0.1, 0.5), true)
		return
	
	var terrain := BetterTerrain.get_terrain(tileset, type)
	if !terrain.valid:
		return
	
	var transform := Transform2D(0.0, rect.size, 0.0, rect.position)
	var center_polygon = transform * BetterTerrain.data.peering_polygon(tileset, terrain.type, -1)
	draw_colored_polygon(center_polygon, Color(terrain.color, 0.6))
	if terrain.type == BetterTerrain.TerrainType.DECORATION:
		center_polygon.append(center_polygon[0])
		draw_polyline(center_polygon, Color.BLACK)
	
	if paint < BetterTerrain.TileCategory.EMPTY or paint >= BetterTerrain.terrain_count(tileset):
		return
	
	if not draw_sides:
		return
	
	var paint_terrain := BetterTerrain.get_terrain(tileset, paint)
	for p in BetterTerrain.data.get_terrain_peering_cells(tileset, terrain.type):
		if paint in BetterTerrain.tile_peering_types(td, p):
			var side_polygon = transform * BetterTerrain.data.peering_polygon(tileset, terrain.type, p)
			draw_colored_polygon(side_polygon, Color(paint_terrain.color, 0.6))
			if paint_terrain.type == BetterTerrain.TerrainType.DECORATION:
				side_polygon.append(side_polygon[0])
				draw_polyline(side_polygon, Color.BLACK)


func _draw_tile_symmetry(texture: Texture2D, rect: Rect2, src_rect: Rect2, td: TileData, draw_icon: bool = true) -> void:
	var flipped_rect := rect
	if td.flip_h:
		flipped_rect.size.x = -rect.size.x
	if td.flip_v:
		flipped_rect.size.y = -rect.size.y
	
	RenderingServer.canvas_item_add_texture_rect_region(
		_get_canvas_item(td),
		flipped_rect,
		texture.get_rid(),
		src_rect,
		td.modulate,
		td.transpose
	)
	
	if not draw_icon:
		return
	
	var symmetry_type = BetterTerrain.get_tile_symmetry_type(td)
	if symmetry_type == 0:
		return
	var symmetry_icon = paint_symmetry_icons[symmetry_type]
	
	RenderingServer.canvas_item_add_texture_rect_region(
		_get_canvas_item(td),
		rect,
		symmetry_icon.get_rid(),
		Rect2(Vector2.ZERO, symmetry_icon.get_size()),
		Color(1,1,1,0.5)
	)


func _draw() -> void:
	if !tileset:
		return
	
	# Clear material-based render targets
	RenderingServer.canvas_item_clear(_canvas_item_background)
	for p in _canvas_item_map:
		RenderingServer.canvas_item_clear(_canvas_item_map[p])
	
	var offset := Vector2.ZERO
	var alt_offset := Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	
	RenderingServer.canvas_item_add_texture_rect(
		_canvas_item_background,
		Rect2(alt_offset, zoom_level * alternate_size),
		checkerboard.get_rid(),
		true
	)
	
	for s in tileset.get_source_count():
		var source_id := tileset.get_source_id(s)
		if source_id in disabled_sources:
			continue
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if !source or !source.texture:
			continue
		
		RenderingServer.canvas_item_add_texture_rect(
			_canvas_item_background,
			Rect2(offset, zoom_level * source.texture.get_size()),
			checkerboard.get_rid(),
			true
		)
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			var rect := source.get_tile_texture_region(coord, 0)
			var alt_count := source.get_alternative_tiles_count(coord)
			var target_rect : Rect2
			for a in alt_count:
				var alt_id := 0
				if a == 0:
					target_rect = Rect2(offset + zoom_level * rect.position, zoom_level * rect.size)
				else:
					target_rect = Rect2(alt_offset + zoom_level * (a - 1) * rect.size.x * Vector2.RIGHT, zoom_level * rect.size)
					alt_id = source.get_alternative_tile_id(coord, a)
				
				var td := source.get_tile_data(coord, alt_id)
				var drawing_current = BetterTerrain.get_tile_terrain_type(td) == paint
				if paint_mode == PaintMode.PAINT_SYMMETRY:
					_draw_tile_symmetry(source.texture, target_rect, rect, td, drawing_current)
				else:
					_draw_tile_data(source.texture, target_rect, rect, td)
				
				if drawing_current:
					draw_rect(target_rect.grow(-1), Color(0,0,0, 0.75), false, 1)
					draw_rect(target_rect, Color(1,1,1, 0.75), false, 1)
				
				if paint_mode == PaintMode.SELECT:
					if selected_tile_states.any(func(v):
						return v.part.data == td
						):
						draw_rect(target_rect.grow(-1), Color.DEEP_SKY_BLUE, false, 2)
			
			if alt_count > 1:
				alt_offset.y += zoom_level * rect.size.y
		
		# Blank out unused or uninteresting tiles
		var size := source.get_atlas_grid_size()
		for y in size.y:
			for x in size.x:
				var pos := Vector2i(x, y)
				if !is_tile_in_source(source, pos):
					var atlas_pos := source.margins + pos * (source.separation + source.texture_region_size)
					draw_rect(Rect2(offset + zoom_level * atlas_pos, zoom_level * source.texture_region_size), Color(0.0, 0.0, 0.0, 0.8), true)
		
		offset.y += zoom_level * source.texture.get_height()
	
	# Blank out unused alternate tile sections
	alt_offset = Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	for a in alternate_lookup:
		if a[1] in disabled_sources:
			continue
		var source := tileset.get_source(a[1]) as TileSetAtlasSource
		if source:
			var count := source.get_alternative_tiles_count(a[2]) - 1
			var occupied_width = count * zoom_level * a[0].x
			var area := Rect2(
				alt_offset.x + occupied_width,
				alt_offset.y,
				zoom_level * alternate_size.x - occupied_width,
				zoom_level * a[0].y
			)
			draw_rect(area, Color(0.0, 0.0, 0.0, 0.8), true)
		alt_offset.y += zoom_level * a[0].y
	
	if highlighted_tile_part.valid:
		if paint_mode == PaintMode.PAINT_PEERING and highlighted_tile_part.has("polygon"):
			var transform := Transform2D(0.0, highlighted_tile_part.rect.size - 2 * Vector2.ONE, 0.0, highlighted_tile_part.rect.position + Vector2.ONE)
			draw_colored_polygon(transform * highlighted_tile_part.polygon, Color(Color.WHITE, 0.2))
		if paint_mode != PaintMode.NO_PAINT:
			var inner_rect := Rect2(highlighted_tile_part.rect.position + Vector2.ONE, highlighted_tile_part.rect.size - 2 * Vector2.ONE) 
			draw_rect(inner_rect, Color.WHITE, false)
		if paint_mode == PaintMode.PAINT_SYMMETRY:
			if paint_symmetry > 0:
				var symmetry_icon = paint_symmetry_icons[paint_symmetry]
				draw_texture_rect(symmetry_icon, highlighted_tile_part.rect, false, Color(0.5,0.75,1,0.5))
	
	if paint_mode == PaintMode.SELECT:
		draw_rect(selection_rect, Color.WHITE, false)
	
	if paint_mode == PaintMode.PASTE:
		if staged_paste_tile_states.size() > 0:
			var base_rect = staged_paste_tile_states[0].base_rect
			var paint_terrain := BetterTerrain.get_terrain(tileset, paint)
			var paint_terrain_type = paint_terrain.type
			if paint_terrain_type == BetterTerrain.TerrainType.CATEGORY:
				paint_terrain_type = 0
			for state in staged_paste_tile_states:
				var staged_rect:Rect2 = state.base_rect
				staged_rect.position -= base_rect.position + base_rect.size / 2
				
				staged_rect.position *= zoom_level
				staged_rect.size *= zoom_level
				
				staged_rect.position += Vector2(current_position)
				
				var real_rect = tile_rect_from_position(staged_rect.get_center())
				if real_rect.position.x >= 0:
					draw_rect(real_rect, Color(0,0,0, 0.3), true)
					var transform := Transform2D(0.0, real_rect.size, 0.0, real_rect.position)
					var tile_sides = BetterTerrain.data.get_terrain_peering_cells(tileset, paint_terrain_type)
					for p in tile_sides:
						if state.paint in BetterTerrain.tile_peering_types(state.part.data, p):
							var side_polygon = BetterTerrain.data.peering_polygon(tileset, paint_terrain_type, p)
							var color = Color(paint_terrain.color, 0.6)
							draw_colored_polygon(transform * side_polygon, color)
				
				draw_rect(staged_rect, Color.DEEP_PINK, false)
	


func delete_selection():
	undo_manager.create_action("Delete tile terrain peering types", UndoRedo.MERGE_DISABLE, tileset)
	for t in selected_tile_states:
		for side in range(16):
			var old_peering = BetterTerrain.tile_peering_types(t.part.data, side)
			if old_peering.has(paint):
				undo_manager.add_do_method(BetterTerrain, &"remove_tile_peering_type", tileset, t.part.data, side, paint)
				undo_manager.add_undo_method(BetterTerrain, &"add_tile_peering_type", tileset, t.part.data, side, paint)
	
	undo_manager.add_do_method(self, &"queue_redraw")
	undo_manager.add_undo_method(self, &"queue_redraw")
	undo_manager.commit_action()


func toggle_selection():
	undo_manager.create_action("Toggle tile terrain", UndoRedo.MERGE_DISABLE, tileset, true)
	for t in selected_tile_states:
		var type := BetterTerrain.get_tile_terrain_type(t.part.data)
		var goal := paint if paint != type else BetterTerrain.TileCategory.NON_TERRAIN
		
		terrain_undo.add_do_method(undo_manager, BetterTerrain, &"set_tile_terrain_type", [tileset, t.part.data, goal])
		if goal == BetterTerrain.TileCategory.NON_TERRAIN:
			terrain_undo.create_peering_restore_point_tile(
				undo_manager,
				tileset,
				t.part.source_id,
				t.part.coord,
				t.part.alternate
			)
		else:
			undo_manager.add_undo_method(BetterTerrain, &"set_tile_terrain_type", tileset, t.part.data, type)
	
	terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
	undo_manager.add_undo_method(self, &"queue_redraw")
	undo_manager.commit_action()
	terrain_undo.action_count += 1


func copy_selection():
	copied_tile_states = selected_tile_states


func paste_selection():
	staged_paste_tile_states = copied_tile_states
	selected_tile_states = []
	paint_mode = PaintMode.PASTE
	paint_action = PaintAction.PASTE
	paste_occurred.emit()
	queue_redraw()


func set_disabled_sources(list):
	disabled_sources = list
	queue_redraw()


func emit_terrain_updated(index):
	terrain_updated.emit(index)


func _gui_input(event) -> void:
	if event is InputEventKey and event.is_pressed():
		if event.keycode == KEY_DELETE and not event.echo:
			accept_event()
			delete_selection()
		if event.keycode == KEY_ENTER and not event.echo:
			accept_event()
			toggle_selection()
		if event.keycode == KEY_ESCAPE and not event.echo:
			accept_event()
			if paint_action == PaintAction.PASTE:
				staged_paste_tile_states = []
				paint_mode = PaintMode.SELECT
				paint_action = PaintAction.NO_ACTION
				selection_start = Vector2i(-1,-1)
		if event.keycode == KEY_C and (event.ctrl_pressed or event.meta_pressed) and not event.echo:
			accept_event()
			copy_selection()
		if event.keycode == KEY_X and (event.ctrl_pressed or event.meta_pressed) and not event.echo:
			accept_event()
			copy_selection()
			delete_selection()
		if event.keycode == KEY_V and (event.ctrl_pressed or event.meta_pressed) and not event.echo:
			accept_event()
			paste_selection()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and (event.ctrl_pressed or event.meta_pressed):
			accept_event()
			change_zoom_level.emit(zoom_level * 1.1)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and (event.ctrl_pressed or event.meta_pressed):
			accept_event()
			change_zoom_level.emit(zoom_level / 1.1)
	
	var released : bool = event is InputEventMouseButton and (not event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT))
	if released:
		paint_action = PaintAction.NO_ACTION
	
	if event is InputEventMouseMotion:
		prev_position = current_position
		current_position = event.position
		var tile := tile_part_from_position(event.position)
		if tile.valid != highlighted_tile_part.valid or\
			(tile.valid and tile.data != highlighted_tile_part.data) or\
			(tile.valid and tile.get("peering") != highlighted_tile_part.get("peering")) or\
			event.button_mask & MOUSE_BUTTON_LEFT and paint_action == PaintAction.SELECT:
			queue_redraw()
		highlighted_tile_part = tile
	
	var clicked : bool = event is InputEventMouseButton and (event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT))
	if clicked:
		initial_click = current_position
		selection_start = Vector2i(-1,-1)
		terrain_undo.action_index += 1
		terrain_undo.action_count = 0
	if released:
		terrain_undo.finish_action()
		selection_rect = Rect2i(0,0,0,0)
		queue_redraw()
	
	if paint_action == PaintAction.PASTE:
		if event is InputEventMouseMotion:
			queue_redraw()
		
		if clicked:
			if event.button_index == MOUSE_BUTTON_LEFT and staged_paste_tile_states.size() > 0:
				undo_manager.create_action("Paste tile terrain peering types", UndoRedo.MERGE_DISABLE, tileset)
				var base_rect = staged_paste_tile_states[0].base_rect
				for p in staged_paste_tile_states:
					var staged_rect:Rect2 = p.base_rect
					staged_rect.position -= base_rect.position + base_rect.size / 2
					
					staged_rect.position *= zoom_level
					staged_rect.size *= zoom_level
					
					staged_rect.position += Vector2(current_position)
					
					var old_tile_part = tile_part_from_position(staged_rect.get_center())
					var new_tile_state = p
					if (not old_tile_part.valid) or (not new_tile_state.part.valid):
						continue
					
					for side in range(16):
						var old_peering = BetterTerrain.tile_peering_types(old_tile_part.data, side)
						var new_sides = new_tile_state.sides
						if new_sides.has(side) and not old_peering.has(paint):
							undo_manager.add_do_method(BetterTerrain, &"add_tile_peering_type", tileset, old_tile_part.data, side, paint)
							undo_manager.add_undo_method(BetterTerrain, &"remove_tile_peering_type", tileset, old_tile_part.data, side, paint)
						elif old_peering.has(paint) and not new_sides.has(side):
							undo_manager.add_do_method(BetterTerrain, &"remove_tile_peering_type", tileset, old_tile_part.data, side, paint)
							undo_manager.add_undo_method(BetterTerrain, &"add_tile_peering_type", tileset, old_tile_part.data, side, paint)
					
					var old_symmetry = BetterTerrain.get_tile_symmetry_type(old_tile_part.data)
					var new_symmetry = new_tile_state.symmetry
					if new_symmetry != old_symmetry:
						undo_manager.add_do_method(BetterTerrain, &"set_tile_symmetry_type", tileset, old_tile_part.data, new_symmetry)
						undo_manager.add_undo_method(BetterTerrain, &"set_tile_symmetry_type", tileset, old_tile_part.data, old_symmetry)
					
				undo_manager.add_do_method(self, &"queue_redraw")
				undo_manager.add_undo_method(self, &"queue_redraw")
				undo_manager.commit_action()
			
			staged_paste_tile_states = []
			paint_mode = PaintMode.SELECT
			paint_action = PaintAction.SELECT
		return
	
	if clicked and pick_icon_terrain >= 0:
		highlighted_tile_part = tile_part_from_position(current_position)
		if !highlighted_tile_part.valid:
			return
		
		var t = BetterTerrain.get_terrain(tileset, paint)
		var prev_icon = t.icon.duplicate()
		var icon = {
			source_id = highlighted_tile_part.source_id,
			coord = highlighted_tile_part.coord
		}
		undo_manager.create_action("Edit terrain details", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(BetterTerrain, &"set_terrain", tileset, paint, t.name, t.color, t.type, t.categories, icon)
		undo_manager.add_do_method(self, &"emit_terrain_updated", paint)
		undo_manager.add_undo_method(BetterTerrain, &"set_terrain", tileset, paint, t.name, t.color, t.type, t.categories, prev_icon)
		undo_manager.add_undo_method(self, &"emit_terrain_updated", paint)
		undo_manager.commit_action()
		pick_icon_terrain = -1
		return
	
	if pick_icon_terrain_cancel:
		pick_icon_terrain = -1
		pick_icon_terrain_cancel = false
	
	if paint != BetterTerrain.TileCategory.NON_TERRAIN and clicked:
		paint_action = PaintAction.NO_ACTION
		if highlighted_tile_part.valid:
			match [paint_mode, event.button_index]:
				[PaintMode.PAINT_TYPE, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_TYPE
				[PaintMode.PAINT_TYPE, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_TYPE
				[PaintMode.PAINT_PEERING, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_PEERING
				[PaintMode.PAINT_PEERING, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_PEERING
				[PaintMode.PAINT_SYMMETRY, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_SYMMETRY
				[PaintMode.PAINT_SYMMETRY, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_SYMMETRY
				[PaintMode.SELECT, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.SELECT
		else:
			match [paint_mode, event.button_index]:
				[PaintMode.SELECT, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.SELECT
	
	if (clicked or event is InputEventMouseMotion) and paint_action != PaintAction.NO_ACTION:
		
		if paint_action == PaintAction.SELECT:
			if clicked:
				selection_start = Vector2i(-1,-1)
				queue_redraw()
			if selection_start.x < 0:
				selection_start = current_position
			selection_end = current_position
			
			selection_rect = Rect2i(selection_start, selection_end - selection_start).abs()
			var selected_tile_parts = tile_parts_from_rect(selection_rect)
			selected_tile_states = []
			for t in selected_tile_parts:
				var state := {
					part = t,
					base_rect = Rect2(t.rect.position / zoom_level, t.rect.size / zoom_level),
					paint = paint,
					sides = BetterTerrain.tile_peering_for_type(t.data, paint),
					symmetry = BetterTerrain.get_tile_symmetry_type(t.data)
				}
				selected_tile_states.push_back(state)
		else:
			if !highlighted_tile_part.valid:
				return
			#slightly crude and non-optimal but way simpler than the "correct" solution
			var current_position_vec2 = Vector2(current_position)
			var prev_position_vec2 = Vector2(prev_position)
			var mouse_dist = current_position_vec2.distance_to(prev_position_vec2)
			var step_size = (tile_part_size.x * zoom_level)
			var steps = ceil(mouse_dist / step_size) + 1
			for i in range(steps):
				var t = float(i) / steps 
				var check_position = prev_position_vec2.lerp(current_position_vec2, t)
				highlighted_tile_part = tile_part_from_position(check_position)
			
				if !highlighted_tile_part.valid:
					continue
				
				if paint_action == PaintAction.DRAW_TYPE or paint_action == PaintAction.ERASE_TYPE:
					var type := BetterTerrain.get_tile_terrain_type(highlighted_tile_part.data)
					var goal := paint if paint_action == PaintAction.DRAW_TYPE else BetterTerrain.TileCategory.NON_TERRAIN
					if type != goal:
						undo_manager.create_action("Set tile terrain type " + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tileset, true)
						terrain_undo.add_do_method(undo_manager, BetterTerrain, &"set_tile_terrain_type", [tileset, highlighted_tile_part.data, goal])
						terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
						if goal == BetterTerrain.TileCategory.NON_TERRAIN:
							terrain_undo.create_peering_restore_point_tile(
								undo_manager,
								tileset,
								highlighted_tile_part.source_id,
								highlighted_tile_part.coord,
								highlighted_tile_part.alternate
							)
						else:
							undo_manager.add_undo_method(BetterTerrain, &"set_tile_terrain_type", tileset, highlighted_tile_part.data, type)
						undo_manager.add_undo_method(self, &"queue_redraw")
						undo_manager.commit_action()
						terrain_undo.action_count += 1
				elif paint_action == PaintAction.DRAW_PEERING:
					if highlighted_tile_part.has("peering"):
						if !(paint in BetterTerrain.tile_peering_types(highlighted_tile_part.data, highlighted_tile_part.peering)):
							undo_manager.create_action("Set tile terrain peering type " + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tileset, true)
							terrain_undo.add_do_method(undo_manager, BetterTerrain, &"add_tile_peering_type", [tileset, highlighted_tile_part.data, highlighted_tile_part.peering, paint])
							terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
							undo_manager.add_undo_method(BetterTerrain, &"remove_tile_peering_type", tileset, highlighted_tile_part.data, highlighted_tile_part.peering, paint)
							undo_manager.add_undo_method(self, &"queue_redraw")
							undo_manager.commit_action()
							terrain_undo.action_count += 1
				elif paint_action == PaintAction.ERASE_PEERING:
					if highlighted_tile_part.has("peering"):
						if paint in BetterTerrain.tile_peering_types(highlighted_tile_part.data, highlighted_tile_part.peering):
							undo_manager.create_action("Remove tile terrain peering type " + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tileset, true)
							terrain_undo.add_do_method(undo_manager, BetterTerrain, &"remove_tile_peering_type", [tileset, highlighted_tile_part.data, highlighted_tile_part.peering, paint])
							terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
							undo_manager.add_undo_method(BetterTerrain, &"add_tile_peering_type", tileset, highlighted_tile_part.data, highlighted_tile_part.peering, paint)
							undo_manager.add_undo_method(self, &"queue_redraw")
							undo_manager.commit_action()
							terrain_undo.action_count += 1
				elif paint_action == PaintAction.DRAW_SYMMETRY:
					if paint == BetterTerrain.get_tile_terrain_type(highlighted_tile_part.data):
						undo_manager.create_action("Set tile symmetry type " + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tileset, true)
						var old_symmetry = BetterTerrain.get_tile_symmetry_type(highlighted_tile_part.data)
						terrain_undo.add_do_method(undo_manager, BetterTerrain, &"set_tile_symmetry_type", [tileset, highlighted_tile_part.data, paint_symmetry])
						terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
						undo_manager.add_undo_method(BetterTerrain, &"set_tile_symmetry_type", tileset, highlighted_tile_part.data, old_symmetry)
						undo_manager.add_undo_method(self, &"queue_redraw")
						undo_manager.commit_action()
						terrain_undo.action_count += 1
				elif paint_action == PaintAction.ERASE_SYMMETRY:
					if paint == BetterTerrain.get_tile_terrain_type(highlighted_tile_part.data):
						undo_manager.create_action("Remove tile symmetry type " + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tileset, true)
						var old_symmetry = BetterTerrain.get_tile_symmetry_type(highlighted_tile_part.data)
						terrain_undo.add_do_method(undo_manager, BetterTerrain, &"set_tile_symmetry_type", [tileset, highlighted_tile_part.data, BetterTerrain.SymmetryType.NONE])
						terrain_undo.add_do_method(undo_manager, self, &"queue_redraw", [])
						undo_manager.add_undo_method(BetterTerrain, &"set_tile_symmetry_type", tileset, highlighted_tile_part.data, old_symmetry)
						undo_manager.add_undo_method(self, &"queue_redraw")
						undo_manager.commit_action()
						terrain_undo.action_count += 1


func _on_zoom_value_changed(value) -> void:
	zoom_level = value
	custom_minimum_size.x = zoom_level * tiles_size.x
	if alternate_size.x > 0:
		custom_minimum_size.x += ALTERNATE_TILE_MARGIN + zoom_level * alternate_size.x
	custom_minimum_size.y = zoom_level * max(tiles_size.y, alternate_size.y)
	queue_redraw()


func clear_highlighted_tile() -> void:
	highlighted_tile_part = { valid = false }
	queue_redraw()
