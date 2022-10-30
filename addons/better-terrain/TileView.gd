@tool
extends Control

@onready var checkerboard = get_theme_icon("Checkerboard", "EditorIcons")

var tileset : TileSet
var paint = -1

var highlighted_position := Vector2i(-1, -1) 

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

func is_tile_in_source(source: TileSetAtlasSource, coord: Vector2i) -> bool:
	var origin = source.get_tile_at_coords(coord)
	if origin == Vector2i(-1, -1):
		return false
	
	# Animation frames are not needed
	var size = source.get_tile_size_in_atlas(origin)
	if origin.x + size.x <= coord.x:
		return false
	return true


func tile_part_from_position(position: Vector2i) -> Dictionary:
	if !tileset:
		return { valid = false }
	
	# return tile source, coord, alternate, peering bit from position
	var offset = Vector2i.ZERO
	for s in tileset.get_source_count():
		var source_id = tileset.get_source_id(s)
		var source = tileset.get_source(source_id) as TileSetAtlasSource
		if !source:
			continue
		for t in source.get_tiles_count():
			var coord = source.get_tile_id(t)
			var rect = source.get_tile_texture_region(coord, 0)
			var target_rect = Rect2i(offset + rect.position, rect.size)
			if !target_rect.has_point(position):
				continue

			var td = source.get_tile_data(coord, 0)
			
			var result = {
				valid = true,
				data = td
			}
			
			var type = BetterTerrain.get_tile_terrain_type(td)
			if type == -1:
				return result
			
			var normalize_position = Vector2(position - target_rect.position) / Vector2(target_rect.size)
			
			var terrain = BetterTerrain.get_terrain(tileset, type)
			for p in BetterTerrainData.get_terrain_peering_cells(tileset, terrain.type):
				var side_polygon = BetterTerrainData.peering_polygon(tileset, terrain.type, p)
				if Geometry2D.is_point_in_polygon(normalize_position, side_polygon):
					result.peering = p
					break
			
			return result
		
		offset.y += source.texture.get_height()
	
	return { valid = false }


func draw_tile_data(td: TileData, rect: Rect2i) -> void:
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
	
	var colors = []
	for i in BetterTerrain.terrain_count(tileset):
		var color = BetterTerrain.get_terrain(tileset, i).color
		color.a = 0.6
		colors.append(color)
	
	var offset = Vector2i.ZERO
	for s in tileset.get_source_count():
		var source = tileset.get_source(tileset.get_source_id(s)) as TileSetAtlasSource
		if !source:
			continue
		draw_texture_rect(checkerboard, Rect2(offset, source.texture.get_size()), true)
		for t in source.get_tiles_count():
			var coord = source.get_tile_id(t)
			var rect = source.get_tile_texture_region(coord, 0)
			var target_rect = Rect2i(offset + rect.position, rect.size)
			var td = source.get_tile_data(coord, 0)
			draw_texture_rect_region(source.texture, target_rect, rect, td.modulate)
			
			draw_tile_data(td, target_rect)
			
			if target_rect.has_point(highlighted_position):
				draw_rect(Rect2i(target_rect.position + Vector2i.ONE, target_rect.size - Vector2i.ONE), Color(1.0, 1.0, 1.0, 1.0), false)
		
		# Blank out unused or uninteresting tiles
		var size = source.get_atlas_grid_size()
		for y in size.y:
			for x in size.x:
				var pos = Vector2i(x, y)
				if !is_tile_in_source(source, pos):
					var atlas_pos = source.margins + pos * (source.separation + source.texture_region_size)
					draw_rect(Rect2i(offset + atlas_pos, source.texture_region_size), Color(0.0, 0.0, 0.0, 0.8), true)
		
		offset.y += source.texture.get_height()


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
