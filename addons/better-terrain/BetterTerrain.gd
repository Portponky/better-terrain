@tool
extends Node

const TERRAIN_META = "better_terrain"

var tile_cache = {}

# Meta-data functions
func _get_terrain_meta(ts: TileSet) -> Dictionary:
	return ts.get_meta(TERRAIN_META) if ts.has_meta(TERRAIN_META) else {
		terrains = []
	}


func _set_terrain_meta(ts: TileSet, meta : Dictionary) -> void:
	ts.set_meta(TERRAIN_META, meta)


func _get_tile_meta(td: TileData) -> Dictionary:
	return td.get_meta(TERRAIN_META) if td.has_meta(TERRAIN_META) else {
		type = -1
	}


func _set_tile_meta(td: TileData, meta : Dictionary) -> void:
	td.set_meta(TERRAIN_META, meta)


func _get_cache(ts: TileSet) -> Array:
	if tile_cache.has(ts):
		return tile_cache[ts]
	
	tile_cache[ts] = []
	var t = tile_cache[ts]

	var ts_meta = _get_terrain_meta(ts)
	for terrains in ts_meta.terrains.size():
		t.append([])
	
	for s in ts.get_source_count():
		var source_id = ts.get_source_id(s)
		var source := ts.get_source(source_id) as TileSetAtlasSource
		if !source:
			continue
		for c in source.get_tiles_count():
			var coord := source.get_tile_id(c)
			for a in source.get_alternative_tiles_count(coord):
				var td := source.get_tile_data(coord, a)
				var tile_meta = _get_tile_meta(td)
				if tile_meta.type >= 0 and tile_meta.type < t.size():
					t[tile_meta.type].append([source_id, coord, a])
	
	return t


func _purge_cache(ts: TileSet) -> void:
	tile_cache.erase(ts)


# Sanity check for peering bit
# could probably be split into sides and corners
func _verify_tileset_has_peering_bit(ts: TileSet, peering: int) -> bool:
	if ts.tile_shape == TileSet.TILE_SHAPE_SQUARE or ts.tile_shape == TileSet.TILE_SHAPE_ISOMETRIC:
		return peering in [
			TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
			TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
			TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
			TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
			TileSet.CELL_NEIGHBOR_LEFT_SIDE,
			TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
			TileSet.CELL_NEIGHBOR_TOP_SIDE,
			TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER
		]
	if ts.tile_offset_axis == TileSet.TILE_OFFSET_AXIS_HORIZONTAL:
		return peering in [
			TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
			TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
			TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
			TileSet.CELL_NEIGHBOR_BOTTOM_CORNER,
			TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
			TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
			TileSet.CELL_NEIGHBOR_LEFT_SIDE,
			TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
			TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,
			TileSet.CELL_NEIGHBOR_TOP_CORNER,
			TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
			TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER
		]
	
	return peering in [
		TileSet.CELL_NEIGHBOR_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
		TileSet.CELL_NEIGHBOR_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_TOP_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE
	]


# port of get_overlapping_coords_and_peering_bits


# tidy up
func _update_tile(tm: TileMap, layer: int, coord: Vector2i, types: Dictionary) -> void:
	var type = types[coord]
	if type == -1:
		return
	var c = _get_cache(tm.tile_set)
	
	var best_score = -1
	var best = null
	for t in c[type]:
		var source = tm.tile_set.get_source(t[0]) as TileSetAtlasSource
		var td = source.get_tile_data(t[1], t[2])
		var t_meta = _get_tile_meta(td)
		
		var score = 0
		for peering in t_meta.keys():
			if !(peering is int):
				continue
			
			var neighbor = tm.get_neighbor_cell(coord, peering)
			if t_meta[peering].has(types[neighbor]):
				score += 3
			else:
				score -= 1
		
		if score > best_score:
			best_score = score
			best = t
	
	if best:
		tm.set_cell(layer, coord, best[0], best[1], best[2])

# Terrain types
func add_terrain(ts: TileSet, name: String, color: Color, type: int) -> bool:
	if !ts or name.is_empty() or type < 0 or type > 3:
		return false
	
	var t = _get_terrain_meta(ts)
	t.terrains.push_back([name, color, type])
	_set_terrain_meta(ts, t)
	_purge_cache(ts)
	return true


func remove_terrain(ts: TileSet, index: int) -> bool:
	if !ts or index < 0:
		return false
	
	var t = _get_terrain_meta(ts)
	if index >= t.terrains.size():
		return false
	
	t.terrains.remove_at(index)
	_set_terrain_meta(ts, t)
	
	# remove all peering bits and tiles of type
	
	_purge_cache(ts)	
	return true


func terrain_count(ts: TileSet) -> int:
	if !ts:
		return 0
	
	var t = _get_terrain_meta(ts)
	return t.terrains.size()


func get_terrain(ts: TileSet, index: int) -> Dictionary:
	if !ts or index < 0:
		return {}
	
	var t = _get_terrain_meta(ts)
	if index >= t.terrains.size():
		return {}
	
	var terrain = t.terrains[index]
	return {name = terrain[0], color = terrain[1], type = terrain[2]}


func set_terrain(ts: TileSet, index: int, name: String, color: Color, type: int) -> bool:
	if !ts or name.is_empty() or index < 0 or type < 0 or type > 2:
		return false
	
	var t = _get_terrain_meta(ts)
	if index >= t.terrains.size():
		return false
	
	t.terrains[index] = [name, color, type]
	_set_terrain_meta(ts, t)
	
	# mask out peering bits?
	
	_purge_cache(ts)
	return true


func swap_terrains(ts: TileSet, index1: int, index2: int) -> bool:
	if !ts or index1 < 0 or index2 < 0 or index1 == index2:
		return false
	
	var t = _get_terrain_meta(ts)
	if index1 >= t.terrains.size() or index2 >= t.terrains.size():
		return false
	
	var temp = t.terrains[index1]
	t.terrains[index1] = t.terrains[index2]
	t.terrains[index2] = temp
	_set_terrain_meta(ts, t)
	
	# swap all peering bits and tile types
	
	_purge_cache(ts)
	return true


# Terrain tile data
func set_tile_terrain_type(ts: TileSet, td: TileData, type: int) -> bool:
	if !ts or !td or type < -1:
		return false
	
	var t = _get_tile_meta(td)
	t.type = type
	_set_tile_meta(td, t)
	_purge_cache(ts)
	return true


func get_tile_terrain_type(td: TileData) -> int:
	if !td:
		return -1
	var t = _get_tile_meta(td)
	return t.type


func add_tile_peering_type(ts: TileSet, td: TileData, peering: int, type: int) -> bool:
	if !ts or !td or peering < 0 or peering > 15 or type < 0:
		return false
	if !_verify_tileset_has_peering_bit(ts, peering):
		return false
	
	var t = _get_tile_meta(td)
	if !t.has(peering):
		t[peering] = [type]
	elif !t[peering].has(type):
		t[peering].append(type)
	else:
		return false
	_set_tile_meta(td, t)
	_purge_cache(ts)
	return true


func remove_tile_peering_type(ts: TileSet, td: TileData, peering: int, type: int) -> bool:
	if !ts or !td or peering < 0 or peering > 15 or type < 0:
		return false
	
	var t = _get_tile_meta(td)
	if !t.has(peering):
		return false
	if !t[peering].has(type):
		return false
	t[peering].remove(type)
	if t[peering].is_empty():
		t.remove(peering)
	_set_tile_meta(td, t)
	_purge_cache(ts)
	return true


func tile_peering_types(td: TileData, peering: int) -> Array:
	if !td or peering < 0 or peering > 15:
		return []
	
	var t = _get_tile_meta(td)
	return t[peering] if t.has(peering) else []


# Painting
func set_cell(tm: TileMap, layer: int, coord: Vector2i, type: int) -> bool:
	if !tm or layer < 0 or layer >= tm.get_layers_count() or type < 0:
		return false
	
	var cache = _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	var tile = cache[type].front()
	tm.set_cell(layer, coord, tile[0], tile[1], tile[2])
	return true


func set_cells(tm: TileMap, layer: int, coords: Array[Vector2i], type: int) -> bool:
	if !tm or layer < 0 or layer >= tm.get_layers_count() or type < 0:
		return false
	
	var cache = _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	var tile = cache[type].front()
	for c in coords:
		tm.set_cell(layer, c, tile[0], tile[1], tile[2])
	return true


func get_cell(tm: TileMap, layer: int, coord: Vector2i) -> int:
	if !tm or layer < 0 or layer >= tm.get_layers_count():
		return -1
	
	var t = tm.get_cell_tile_data(layer, coord)
	if !t:
		return -1
	
	return _get_tile_meta(t).type

# needs tidied a bit
# needs to support hex or other tilesets
func update_terrains(tm: TileMap, layer: int, top_left: Vector2i, bottom_right: Vector2i) -> void:
	if !tm or layer < 0 or layer >= tm.get_layers_count():
		return
	
	var tm_meta = _get_terrain_meta(tm.tile_set)
	var types = {}
	for y in range(top_left.y - 1, bottom_right.y + 2):
		for x in range(top_left.x - 1, bottom_right.x + 2):
			var coord = Vector2i(x, y)
			types[coord] = get_cell(tm, layer, coord)
	
	for y in range(top_left.y, bottom_right.y + 1):
		for x in range(top_left.x, bottom_right.x + 1):
			var coord = Vector2i(x, y)
			var type = types[coord]
			if type >= 0 and type < tm_meta.terrains.size() and tm_meta.terrains[type][2] != 3:
				_update_tile(tm, layer, Vector2i(x, y), types)

