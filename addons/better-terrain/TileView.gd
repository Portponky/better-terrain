@tool
extends Control

@onready var checkerboard = get_theme_icon("Checkerboard", "EditorIcons")

var tileset: TileSet

var paint = -1
var highlighted_position := Vector2i(-1, -1) 
var zoom_level := 1.0

var tiles_size : Vector2
var alternate_size : Vector2
var alternate_lookup := []

# Modes for painting
enum PaintMode {
	NO_PAINT,
	PAINT_TYPE,
	PAINT_PEERING
}

var paint_mode = PaintMode.NO_PAINT

# Actual interactions for painting
enum PaintAction {
	NO_ACTION,
	DRAW_TYPE,
	ERASE_TYPE,
	DRAW_PEERING,
	ERASE_PEERING
}

var paint_action = PaintAction.NO_ACTION

const ALTERNATE_TILE_MARGIN := 18

func refresh_tileset(ts: TileSet) -> void:
	tileset = ts
	
	tiles_size = Vector2.ZERO
	alternate_size = Vector2.ZERO
	alternate_lookup = []
	
	for s in tileset.get_source_count():
		var source_id = tileset.get_source_id(s)
		var source = tileset.get_source(source_id) as TileSetAtlasSource
		if !source or !source.texture:
			continue
		
		tiles_size.x = max(tiles_size.x, source.texture.get_width())
		tiles_size.y += source.texture.get_height()
		
		for t in source.get_tiles_count():
			var coord = source.get_tile_id(t)
			var alt_count = source.get_alternative_tiles_count(coord)
			if alt_count <= 1:
				continue
			
			var rect = source.get_tile_texture_region(coord, 0)
			alternate_lookup.append([rect.size, source_id, coord])
			alternate_size.x = max(alternate_size.x, rect.size.x * (alt_count - 1))
			alternate_size.y += rect.size.y
	
	_on_zoom_value_changed(zoom_level)


func is_tile_in_source(source: TileSetAtlasSource, coord: Vector2i) -> bool:
	var origin = source.get_tile_at_coords(coord)
	if origin == Vector2i(-1, -1):
		return false
	
	# Animation frames are not needed
	var size = source.get_tile_size_in_atlas(origin)
	return coord.x < origin.x + size.x


func _build_tile_part_from_position(td: TileData, position: Vector2i, rect: Rect2) -> Dictionary:
	var result = {
		valid = true,
		data = td
	}
	
	var type = BetterTerrain.get_tile_terrain_type(td)
	if type == -1:
		return result
	
	var normalize_position = (Vector2(position) - rect.position) / rect.size
	
	var terrain = BetterTerrain.get_terrain(tileset, type)
	for p in BetterTerrainData.get_terrain_peering_cells(tileset, terrain.type):
		var side_polygon = BetterTerrainData.peering_polygon(tileset, terrain.type, p)
		if Geometry2D.is_point_in_polygon(normalize_position, side_polygon):
			result.peering = p
			break
	
	return result


func tile_part_from_position(position: Vector2i) -> Dictionary:
	if !tileset:
		return { valid = false }
	
	var offset = Vector2.ZERO
	var alt_offset = Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	if Rect2(alt_offset, zoom_level * alternate_size).has_point(position):
		for a in alternate_lookup:
			var next_offset_y = alt_offset.y + zoom_level * a[0].y
			if position.y > next_offset_y:
				alt_offset.y = next_offset_y
				continue
			
			var source = tileset.get_source(a[1]) as TileSetAtlasSource
			if !source:
				break
			
			var count = source.get_alternative_tiles_count(a[2])
			var index = int((position.x - alt_offset.x) / (zoom_level * a[0].x)) + 1
			var target_rect = Rect2(
				alt_offset + Vector2.RIGHT * (index - 1) * zoom_level * a[0].x,
				zoom_level * a[0]
			)
			
			if index < count:
				var td = source.get_tile_data(a[2], index)
				return _build_tile_part_from_position(td, position, target_rect)
	
	else:
		for s in tileset.get_source_count():
			var source_id = tileset.get_source_id(s)
			var source = tileset.get_source(source_id) as TileSetAtlasSource
			if !source:
				continue
			for t in source.get_tiles_count():
				var coord = source.get_tile_id(t)
				var rect = source.get_tile_texture_region(coord, 0)
				var target_rect = Rect2(offset + zoom_level * rect.position, zoom_level * rect.size)
				if !target_rect.has_point(position):
					continue
				
				var td = source.get_tile_data(coord, 0)
				return _build_tile_part_from_position(td, position, target_rect)
			
			offset.y += zoom_level * source.texture.get_height()
	
	return { valid = false }


func _draw_tile_data(texture: Texture2D, rect: Rect2, src_rect: Rect2, td: TileData) -> void:
	draw_texture_rect_region(texture, rect, src_rect, td.modulate)
	
	var type = BetterTerrain.get_tile_terrain_type(td)
	if type == -1:
		draw_rect(rect, Color(0.1, 0.1, 0.1, 0.5), true)
		return
	
	var terrain = BetterTerrain.get_terrain(tileset, type)
	if !terrain.valid:
		return
	
	var center_polygon = BetterTerrainData.peering_polygon(tileset, terrain.type, -1)
	draw_colored_polygon(BetterTerrainData.scale_polygon_to_rect(rect, center_polygon), Color(terrain.color, 0.6))
	
	if paint < 0 or paint >= BetterTerrain.terrain_count(tileset):
		return
	
	var paint_terrain = BetterTerrain.get_terrain(tileset, paint)
	for p in BetterTerrainData.get_terrain_peering_cells(tileset, terrain.type):
		if paint in BetterTerrain.tile_peering_types(td, p):
			var side_polygon = BetterTerrainData.peering_polygon(tileset, terrain.type, p)
			draw_colored_polygon(BetterTerrainData.scale_polygon_to_rect(rect, side_polygon), Color(paint_terrain.color, 0.6))


func _draw():
	if !tileset:
		return
	
	var highlight_rect: Rect2
	var offset = Vector2.ZERO
	var alt_offset = Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	
	draw_texture_rect(checkerboard, Rect2(alt_offset, zoom_level * alternate_size), true)
	
	for s in tileset.get_source_count():
		var source = tileset.get_source(tileset.get_source_id(s)) as TileSetAtlasSource
		if !source or !source.texture:
			continue
		draw_texture_rect(checkerboard, Rect2(offset, zoom_level * source.texture.get_size()), true)
		for t in source.get_tiles_count():
			var coord = source.get_tile_id(t)
			var rect = source.get_tile_texture_region(coord, 0)
			var alt_count = source.get_alternative_tiles_count(coord)
			var target_rect : Rect2
			for a in alt_count:
				if a == 0:
					target_rect = Rect2(offset + zoom_level * rect.position, zoom_level * rect.size)
				else:
					target_rect = Rect2(alt_offset + zoom_level * (a - 1) * rect.size.x * Vector2.RIGHT, zoom_level * rect.size)
				
				var td = source.get_tile_data(coord, a)
				_draw_tile_data(source.texture, target_rect, rect, td)
				if target_rect.has_point(highlighted_position):
					highlight_rect = target_rect
			
			if alt_count > 1:
				alt_offset.y += zoom_level * rect.size.y
		
		# Blank out unused or uninteresting tiles
		var size = source.get_atlas_grid_size()
		for y in size.y:
			for x in size.x:
				var pos = Vector2i(x, y)
				if !is_tile_in_source(source, pos):
					var atlas_pos = source.margins + pos * (source.separation + source.texture_region_size)
					draw_rect(Rect2(offset + zoom_level * atlas_pos, zoom_level * source.texture_region_size), Color(0.0, 0.0, 0.0, 0.8), true)
		
		offset.y += zoom_level * source.texture.get_height()
	
	# Blank out unused alternate tile sections
	alt_offset = Vector2.RIGHT * (zoom_level * tiles_size.x + ALTERNATE_TILE_MARGIN)
	for a in alternate_lookup:
		var source = tileset.get_source(a[1]) as TileSetAtlasSource
		if source:
			var count = source.get_alternative_tiles_count(a[2]) - 1
			var occupied_width = count * zoom_level * a[0].x
			var area = Rect2(
				alt_offset.x + occupied_width,
				alt_offset.y,
				zoom_level * alternate_size.x - occupied_width,
				zoom_level * a[0].y
			)
			draw_rect(area, Color(0.0, 0.0, 0.0, 0.8), true)
		alt_offset.y += zoom_level * a[0].y
	
	if highlight_rect.has_area():
		draw_rect(Rect2(highlight_rect.position + Vector2.ONE, highlight_rect.size - Vector2.ONE), Color(1.0, 1.0, 1.0, 1.0), false)


func _input(event):
	if event is InputEventMouseMotion:
		var e = make_input_local(event)
		highlighted_position = e.position
		# don't redraw on every mouse motion
		queue_redraw()


func _gui_input(event):
	if event is InputEventMouseButton and !event.pressed:
		paint_action = PaintAction.NO_ACTION
	
	var clicked = event is InputEventMouseButton and event.pressed
	if paint >= 0 and clicked:
		paint_action = PaintAction.NO_ACTION
	
		# Determine what to do until the button is released
		var tile = tile_part_from_position(event.position)
		if !tile.valid:
			return
		
		match [paint_mode, event.button_index]:
			[PaintMode.PAINT_TYPE, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_TYPE
			[PaintMode.PAINT_TYPE, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_TYPE
			[PaintMode.PAINT_PEERING, MOUSE_BUTTON_LEFT]: paint_action = PaintAction.DRAW_PEERING
			[PaintMode.PAINT_PEERING, MOUSE_BUTTON_RIGHT]: paint_action = PaintAction.ERASE_PEERING
	
	if (clicked or event is InputEventMouseMotion) and paint_action != PaintAction.NO_ACTION:
		var tile = tile_part_from_position(event.position)
		if !tile.valid:
			return
		
		if paint_action == PaintAction.DRAW_TYPE or paint_action == PaintAction.ERASE_TYPE:
			var type = BetterTerrain.get_tile_terrain_type(tile.data)
			var goal = paint if paint_action == PaintAction.DRAW_TYPE else -1
			if type != goal:
				BetterTerrain.set_tile_terrain_type(tileset, tile.data, goal)
				queue_redraw()
		elif paint_action == PaintAction.DRAW_PEERING:
			if tile.has("peering"):
				if !(paint in BetterTerrain.tile_peering_types(tile.data, tile.peering)):
					BetterTerrain.add_tile_peering_type(tileset, tile.data, tile.peering, paint)
					queue_redraw()
		elif paint_action == PaintAction.ERASE_PEERING:
			if tile.has("peering"):
				if paint in BetterTerrain.tile_peering_types(tile.data, tile.peering):
					BetterTerrain.remove_tile_peering_type(tileset, tile.data, tile.peering, paint)
					queue_redraw()


func _on_zoom_value_changed(value):
	zoom_level = value
	custom_minimum_size.x = zoom_level * tiles_size.x
	if alternate_size.x > 0:
		custom_minimum_size.x += ALTERNATE_TILE_MARGIN + zoom_level * alternate_size.x
	custom_minimum_size.y = zoom_level * max(tiles_size.y, alternate_size.y)
	queue_redraw()
