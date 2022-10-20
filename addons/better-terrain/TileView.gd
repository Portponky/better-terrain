@tool
extends Control

@onready var checkerboard = get_theme_icon("Checkerboard", "EditorIcons")

var tileset : TileSet
var paint = -1

var highlighted_position := Vector2i(-1, -1) 

func _ready():
	pass


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
			
			var type = BetterTerrain.get_tile_terrain_type(td)
			if type == -1:
				draw_rect(target_rect, Color(0.1, 0.1, 0.1, 0.5), true)
			elif type >= 0 and type < colors.size():
				draw_rect(target_rect, colors[type], true)
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
			
			var result = {
				valid = true,
				source_id = source_id,
				coord = coord,
				alternate = 0
			}
			
			var td = source.get_tile_data(coord, 0)
			if BetterTerrain.get_tile_terrain_type(td) in [-1, 3]:
				return result
			
			# Take account of peering bit
			return result
		
		offset.y += source.texture.get_height()
	
	return { valid = false }



func _input(event):
	if event is InputEventMouseMotion:
		var e = make_input_local(event)
		highlighted_position = e.position
		# don't redraw on every mouse motion
		queue_redraw()


func _gui_input(event):
	if paint >= 0 and event is InputEventMouseButton and event.pressed:
		var tile = tile_part_from_position(event.position)
		if !tile.valid:
			return
		
		var source = tileset.get_source(tile.source_id) as TileSetAtlasSource
		var td = source.get_tile_data(tile.coord, tile.alternate)
		if !td:
			return
		
		if BetterTerrain.get_tile_terrain_type(td) != paint:
			BetterTerrain.set_tile_terrain_type(tileset, td, paint)
			queue_redraw()
