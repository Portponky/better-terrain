@tool
extends Control

@onready var checkerboard = get_theme_icon("Checkerboard", "EditorIcons")

var tileset : TileSet

var highlighted_position := Vector2i(-1, -1) 

func _ready():
	pass


func _draw():
	if !tileset:
		return
	
	var position = Vector2i.ZERO
	for s in tileset.get_source_count():
		var source = tileset.get_source(tileset.get_source_id(s)) as TileSetAtlasSource
		if !source:
			continue
		draw_texture_rect(checkerboard, Rect2(position, source.texture.get_size()), true)
		for t in source.get_tiles_count():
			var coord = source.get_tile_id(t)
			var td = source.get_tile_data(coord, 0)
			var rect = source.get_tile_texture_region(coord, 0)
			var target_rect = Rect2i(position + rect.position, rect.size)
			draw_texture_rect_region(source.texture, target_rect, rect, td.modulate)
			if BetterTerrain.get_tile_terrain_type(td) == -1:
				draw_rect(target_rect, Color(0.1, 0.1, 0.1, 0.5), true)
			if target_rect.has_point(highlighted_position):
				draw_rect(Rect2i(target_rect.position + Vector2i.ONE, target_rect.size - Vector2i.ONE), Color(1.0, 1.0, 1.0, 1.0), false)
		
		# Blank out unused or uninteresting tiles
		var size = source.get_atlas_grid_size()
		for y in size.y:
			for x in size.x:
				var pos = Vector2i(x, y)
				if !is_tile_in_source(source, pos):
					var atlas_pos = source.margins + pos * (source.separation + source.texture_region_size)
					draw_rect(Rect2i(atlas_pos, source.texture_region_size), Color(0.0, 0.0, 0.0, 0.8), true)
		
		position.y += source.texture.get_height()


func is_tile_in_source(source: TileSetAtlasSource, coord: Vector2i) -> bool:
	var origin = source.get_tile_at_coords(coord)
	if origin == Vector2i(-1, -1):
		return false
	
	# Animation frames are not needed
	var size = source.get_tile_size_in_atlas(origin)
	if origin.x + size.x <= coord.x:
		return false
	return true


func _gui_input(event):
	if event is InputEventMouseMotion:
		highlighted_position = event.position
		queue_redraw()
