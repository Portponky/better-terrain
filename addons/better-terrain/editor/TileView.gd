@tool
extends Control

@onready var checkerboard := get_theme_icon("Checkerboard", "EditorIcons")

var tileset: TileSet

var paint := -1
var highlighted_tile_part := { valid = false }
var zoom_level := 1.0

var tiles_size : Vector2
var alternate_size : Vector2
var alternate_lookup := []

var undo_manager : EditorUndoRedoManager
var terrain_undo

# Modes for painting
enum PaintMode {
	NO_PAINT,
	PAINT_TYPE,
	PAINT_PEERING
}

var paint_mode := PaintMode.NO_PAINT

# Actual interactions for painting
enum PaintAction {
	NO_ACTION,
	DRAW_TYPE,
	ERASE_TYPE,
	DRAW_PEERING,
	ERASE_PEERING
}

var paint_action := PaintAction.NO_ACTION

const ALTERNATE_TILE_MARGIN := 18

func refresh_tileset(ts: TileSet) -> void:
	tileset = ts
	
	tiles_size = Vector2.ZERO
	alternate_size = Vector2.ZERO
	alternate_lookup = []
	
	if !tileset:
		return
	
	for s in tileset.get_source_count():
		var source_id := tileset.get_source_id(s)
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if !source or !source.texture:
			continue
		
		tiles_size.x = max(tiles_size.x, source.texture.get_width())
		tiles_size.y += source.texture.get_height()
		
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
	if type == -1:
		return
	
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
			var source := tileset.get_source(source_id) as TileSetAtlasSource
			if !source:
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


func _draw_tile_data(texture: Texture2D, rect: Rect2, src_rect: Rect2, td: TileData) -> void:
	var flipped_rect := rect
	if td.flip_h:
		flipped_rect.size.x = -rect.size.x
	if td.flip_v:
		flipped_rect.size.y = -rect.size.y
	draw_texture_rect_region(texture, flipped_rect, src_rect, td.modulate, td.transpose)
	
	var type := BetterTerrain.get_tile_terrain_type(td)
	if type == -1:
		draw_rect(rect, Color(0.1, 0.1, 0.1, 0.5), true)
		return
	
	var terrain := BetterTerrain.get_terrain(tileset, type)
	if !terrain.valid:
		return
	
	var transform := Transform2D(0.0, rect.size, 0.0, rect.position)
	var center_polygon = BetterTerrain.data.peering_polygon(tileset, terrain.type, -1)
	draw_colored_polygon(transform * center_polygon, Color(terrain.color, 0.6))
	
	if paint < 0 or paint >= BetterTerrain.terrain_count(tileset):
		return
	
	var paint_terrain := BetterTerrain.get_terrain(tileset, paint)
	for p in BetterTerrain.data.get_terrain_peering_cells(tileset, terrain.type):
		if paint in BetterTerrain.tile_peering_types(td, p):
			var side_polygon = BetterTerrain.data.peering_polygon(tileset, terrain.type, p)
			draw_colored_polygon(transform * side_polygon, Color(paint_terrain.color, 0.6))


func _draw() -> void:
	if !tileset:
		return
	
	var offset := Vector2.ZERO
	var alt_offset := Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	
	draw_texture_rect(checkerboard, Rect2(alt_offset, zoom_level * alternate_size), true)
	
	for s in tileset.get_source_count():
		var source := tileset.get_source(tileset.get_source_id(s)) as TileSetAtlasSource
		if !source or !source.texture:
			continue
		draw_texture_rect(checkerboard, Rect2(offset, zoom_level * source.texture.get_size()), true)
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
				_draw_tile_data(source.texture, target_rect, rect, td)
			
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


func _gui_input(event) -> void:
	if event is InputEventMouseButton and !event.pressed:
		paint_action = PaintAction.NO_ACTION
	
	if event is InputEventMouseMotion:
		var tile := tile_part_from_position(event.position)
		if tile.valid != highlighted_tile_part.valid or\
			(tile.valid and tile.data != highlighted_tile_part.data) or\
			(tile.valid and tile.get("peering") != highlighted_tile_part.get("peering")):
			queue_redraw()
		highlighted_tile_part = tile
	
	var clicked : bool = event is InputEventMouseButton and event.pressed
	if paint >= 0 and clicked:
		paint_action = PaintAction.NO_ACTION
		if !highlighted_tile_part.valid:
			return
		
		match [paint_mode, event.button_index]:
			[PaintMode.PAINT_TYPE, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_TYPE
			[PaintMode.PAINT_TYPE, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_TYPE
			[PaintMode.PAINT_PEERING, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_PEERING
			[PaintMode.PAINT_PEERING, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_PEERING
	
	if (clicked or event is InputEventMouseMotion) and paint_action != PaintAction.NO_ACTION:
		if !highlighted_tile_part.valid:
			return
		
		if paint_action == PaintAction.DRAW_TYPE or paint_action == PaintAction.ERASE_TYPE:
			var type := BetterTerrain.get_tile_terrain_type(highlighted_tile_part.data)
			var goal := paint if paint_action == PaintAction.DRAW_TYPE else -1
			if type != goal:
				undo_manager.create_action("Set tile terrain type", UndoRedo.MERGE_DISABLE, tileset)
				undo_manager.add_do_method(BetterTerrain, &"set_tile_terrain_type", tileset, highlighted_tile_part.data, goal)
				undo_manager.add_do_method(self, &"queue_redraw")
				if goal == -1:
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
		elif paint_action == PaintAction.DRAW_PEERING:
			if highlighted_tile_part.has("peering"):
				if !(paint in BetterTerrain.tile_peering_types(highlighted_tile_part.data, highlighted_tile_part.peering)):
					undo_manager.create_action("Set tile terrain peering type", UndoRedo.MERGE_DISABLE, tileset)
					undo_manager.add_do_method(BetterTerrain, &"add_tile_peering_type", tileset, highlighted_tile_part.data, highlighted_tile_part.peering, paint)
					undo_manager.add_do_method(self, &"queue_redraw")
					undo_manager.add_undo_method(BetterTerrain, &"remove_tile_peering_type", tileset, highlighted_tile_part.data, highlighted_tile_part.peering, paint)
					undo_manager.add_undo_method(self, &"queue_redraw")
					undo_manager.commit_action()
		elif paint_action == PaintAction.ERASE_PEERING:
			if highlighted_tile_part.has("peering"):
				if paint in BetterTerrain.tile_peering_types(highlighted_tile_part.data, highlighted_tile_part.peering):
					undo_manager.create_action("Set tile terrain peering type", UndoRedo.MERGE_DISABLE, tileset)
					undo_manager.add_do_method(BetterTerrain, &"remove_tile_peering_type", tileset, highlighted_tile_part.data, highlighted_tile_part.peering, paint)
					undo_manager.add_do_method(self, &"queue_redraw")
					undo_manager.add_undo_method(BetterTerrain, &"add_tile_peering_type", tileset, highlighted_tile_part.data, highlighted_tile_part.peering, paint)
					undo_manager.add_undo_method(self, &"queue_redraw")
					undo_manager.commit_action()


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
