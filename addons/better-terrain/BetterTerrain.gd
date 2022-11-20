@tool
extends Node

const TERRAIN_META = "_better_terrain"

var _tile_cache = {}
var data := load("res://addons/better-terrain/BetterTerrainData.gd"):
	get:
		return data

enum TerrainType {
	MATCH_TILES,
	MATCH_VERTICES,
	NON_MODIFYING,
	MAX
}

# Meta-data functions
func _get_terrain_meta(ts: TileSet) -> Dictionary:
	return ts.get_meta(TERRAIN_META) if ts and ts.has_meta(TERRAIN_META) else {
		terrains = []
	}


func _set_terrain_meta(ts: TileSet, meta : Dictionary) -> void:
	ts.set_meta(TERRAIN_META, meta)


func _get_tile_meta(td: TileData) -> Dictionary:
	return td.get_meta(TERRAIN_META) if td.has_meta(TERRAIN_META) else {
		type = -1
	}


func _set_tile_meta(td: TileData, meta) -> void:
	td.set_meta(TERRAIN_META, meta)


func _get_cache(ts: TileSet) -> Array:
	if _tile_cache.has(ts):
		return _tile_cache[ts]
	
	if !ts:
		return []
	
	_tile_cache[ts] = []
	var cache = _tile_cache[ts]

	var ts_meta = _get_terrain_meta(ts)
	for terrains in ts_meta.terrains.size():
		cache.append([])
	
	for s in ts.get_source_count():
		var source_id = ts.get_source_id(s)
		var source := ts.get_source(source_id) as TileSetAtlasSource
		if !source:
			continue
		for c in source.get_tiles_count():
			var coord := source.get_tile_id(c)
			for a in source.get_alternative_tiles_count(coord):
				var alternate = source.get_alternative_tile_id(coord, a)
				var td := source.get_tile_data(coord, alternate)
				var tile_meta = _get_tile_meta(td)
				if tile_meta.type >= 0 and tile_meta.type < cache.size():
					var peering_keys = tile_meta.keys()
					peering_keys.erase("type")
					cache[tile_meta.type].append([source_id, coord, alternate, tile_meta, peering_keys])
	
	return cache


func _purge_cache(ts: TileSet) -> void:
	_tile_cache.erase(ts)


func _clear_invalid_peering_types(ts: TileSet) -> void:
	var ts_meta = _get_terrain_meta(ts)
	
	var cache = _get_cache(ts)
	for t in cache.size():
		var type = ts_meta.terrains[t][2]
		var valid_peering_types = data.get_terrain_peering_cells(ts, type)
		
		for c in cache[t]:
			var source = ts.get_source(c[0]) as TileSetAtlasSource
			var td = source.get_tile_data(c[1], c[2])
			var td_meta = c[3]
			
			for peering in c[4]:
				if valid_peering_types.has(peering):
					continue
				td_meta.erase(peering)
			
			_set_tile_meta(td, td_meta)
	
	# Not strictly necessary
	_purge_cache(ts)


func _has_invalid_peering_types(ts: TileSet) -> bool:
	var ts_meta = _get_terrain_meta(ts)
	
	var cache = _get_cache(ts)
	for t in cache.size():
		var type = ts_meta.terrains[t][2]
		var valid_peering_types = data.get_terrain_peering_cells(ts, type)
		
		for c in cache[t]:
			for peering in c[4]:
				if !valid_peering_types.has(peering):
					return true
	
	return false


func _update_tile_tiles(tm: TileMap, layer: int, coord: Vector2i, types: Dictionary) -> void:
	var type = types[coord]
	var c := _get_cache(tm.tile_set)
	
	var best_score := -1000 # Impossibly bad score
	var best := []
	for t in c[type]:
		var td_meta = t[3]
		
		var score := 0
		for peering in t[4]:
			score += 3 if td_meta[peering].has(types[tm.get_neighbor_cell(coord, peering)]) else -10
		
		if score > best_score:
			best_score = score
			best = [t]
		elif score == best_score:
			best.append(t)
	
	if !best.is_empty():
		var choice = best[randi() % best.size()]
		tm.set_cell(layer, coord, choice[0], choice[1], choice[2])


func _probe(tm: TileMap, coord: Vector2i, peering: int, types: Dictionary, goal: Array) -> int:
	var targets = data.associated_vertex_cells(tm, coord, peering)
	
	var partial_match := false
	var best = types[targets[0]]
	for t in targets:
		var test = types[t]
		best = min(best, test)
		if test in goal:
			partial_match = true
	
	# Best - exact match on lowest type
	if best in goal:
		return 3
	
	# Bad - any match of any type
	if partial_match:
		return -1
	
	# Worse - only match current terrain
	if types[coord] in goal:
		return -3
	
	# Worst - no kind of match at all
	return -5


func _update_tile_vertices(tm: TileMap, layer: int, coord: Vector2i, types: Dictionary) -> void:
	var type = types[coord]
	var c = _get_cache(tm.tile_set)
	
	var best_score := -1000 # Impossibly bad score
	var best = []
	for t in c[type]:
		var t_meta = t[3]
		
		var score := 0
		for peering in t[4]:
			score += _probe(tm, coord, peering, types, t_meta[peering])
		
		if score > best_score:
			best_score = score
			best = [t]
		elif score == best_score:
			best.append(t)
	
	if !best.is_empty():
		var choice = best[randi() % best.size()]
		tm.set_cell(layer, coord, choice[0], choice[1], choice[2])


func _update_tile(tm: TileMap, layer: int, coord: Vector2i, ts_meta: Dictionary, types: Dictionary) -> void:
	var type = types[coord]
	if type >= 0 and type < ts_meta.terrains.size():
		var terrain = ts_meta.terrains[type]
		if terrain[2] == TerrainType.MATCH_TILES:
			_update_tile_tiles(tm, layer, coord, types)
		elif terrain[2] == TerrainType.MATCH_VERTICES:
			_update_tile_vertices(tm, layer, coord, types)


func _widen(tm: TileMap, coords: Array) -> Array:
	var result = {}
	for c in coords:
		result[c] = true
		var neighbors = data.neighboring_coords(tm, c, data.get_terrain_peering_cells(tm.tile_set, TerrainType.MATCH_TILES))
		for t in neighbors:
			result[t] = true
	return result.keys()


func _widen_with_exclusion(tm: TileMap, coords: Array, exclusion: Rect2i) -> Array:
	var result = {}
	for c in coords:
		if !exclusion.has_point(c):
			result[c] = true
		var neighbors = data.neighboring_coords(tm, c, data.get_terrain_peering_cells(tm.tile_set, TerrainType.MATCH_TILES))
		for t in neighbors:
			if !exclusion.has_point(t):
				result[t] = true
	return result.keys()


# Terrain types
func add_terrain(ts: TileSet, name: String, color: Color, type: int) -> bool:
	if !ts or name.is_empty() or type < 0 or type >= TerrainType.MAX:
		return false
	
	var ts_meta = _get_terrain_meta(ts)
	ts_meta.terrains.push_back([name, color, type])
	_set_terrain_meta(ts, ts_meta)
	_purge_cache(ts)
	return true


func remove_terrain(ts: TileSet, index: int) -> bool:
	if !ts or index < 0:
		return false
	
	var ts_meta = _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return false
	
	for s in ts.get_source_count():
		var source := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if !source:
			continue
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			for a in source.get_alternative_tiles_count(coord):
				var alternate = source.get_alternative_tile_id(coord, a)
				var td = source.get_tile_data(coord, alternate)
				
				var td_meta = _get_tile_meta(td)
				if td_meta.type == -1:
					continue
				
				if td_meta.type == index:
					_set_tile_meta(td, null)
					continue
				
				if td_meta.type > index:
					td_meta.type -= 1
				
				for peering in td_meta.keys():
					if !(peering is int):
						continue
					
					var fixed_peering = []
					for p in td_meta[peering]:
						if p < index:
							fixed_peering.append(p)
						elif p > index:
							fixed_peering.append(p - 1)
					
					if fixed_peering.is_empty():
						td_meta.erase(peering)
					else:
						td_meta[peering] = fixed_peering
				
				_set_tile_meta(td, td_meta)
	
	ts_meta.terrains.remove_at(index)
	_set_terrain_meta(ts, ts_meta)
	
	_purge_cache(ts)	
	return true


func terrain_count(ts: TileSet) -> int:
	if !ts:
		return 0
	
	var ts_meta = _get_terrain_meta(ts)
	return ts_meta.terrains.size()


func get_terrain(ts: TileSet, index: int) -> Dictionary:
	if !ts or index < 0:
		return {valid = false}
	
	var ts_meta = _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return {valid = false}
	
	var terrain = ts_meta.terrains[index]
	return {name = terrain[0], color = terrain[1], type = terrain[2], valid = true}


func set_terrain(ts: TileSet, index: int, name: String, color: Color, type: int) -> bool:
	if !ts or name.is_empty() or index < 0 or type < 0 or type >= TerrainType.MAX:
		return false
	
	var ts_meta = _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return false
	
	_clear_invalid_peering_types(ts)
	
	ts_meta.terrains[index] = [name, color, type]
	_set_terrain_meta(ts, ts_meta)
	
	_purge_cache(ts)
	return true


func swap_terrains(ts: TileSet, index1: int, index2: int) -> bool:
	if !ts or index1 < 0 or index2 < 0 or index1 == index2:
		return false
	
	var ts_meta = _get_terrain_meta(ts)
	if index1 >= ts_meta.terrains.size() or index2 >= ts_meta.terrains.size():
		return false
	
	for s in ts.get_source_count():
		var source := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if !source:
			continue
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			for a in source.get_alternative_tiles_count(coord):
				var alternate = source.get_alternative_tile_id(coord, a)
				var td = source.get_tile_data(coord, alternate)
				
				var td_meta = _get_tile_meta(td)
				if td_meta.type == -1:
					continue
				
				if td_meta.type == index1:
					td_meta.type = index2
				elif td_meta.type == index2:
					td_meta.type = index1
				
				for peering in td_meta.keys():
					if !(peering is int):
						continue
					
					var fixed_peering = []
					for p in td_meta[peering]:
						if p == index1:
							fixed_peering.append(index2)
						elif p == index2:
							fixed_peering.append(index1)
						else:
							fixed_peering.append(p)
					td_meta[peering] = fixed_peering
				
				_set_tile_meta(td, td_meta)
	
	var temp = ts_meta.terrains[index1]
	ts_meta.terrains[index1] = ts_meta.terrains[index2]
	ts_meta.terrains[index2] = temp
	_set_terrain_meta(ts, ts_meta)
	
	_purge_cache(ts)
	return true


# Terrain tile data
func set_tile_terrain_type(ts: TileSet, td: TileData, type: int) -> bool:
	if !ts or !td or type < -1:
		return false
	
	var td_meta = _get_tile_meta(td)
	td_meta.type = type
	if type == -1:
		td_meta = null
	_set_tile_meta(td, td_meta)
	_purge_cache(ts)
	return true


func get_tile_terrain_type(td: TileData) -> int:
	if !td:
		return -1
	var td_meta = _get_tile_meta(td)
	return td_meta.type


func add_tile_peering_type(ts: TileSet, td: TileData, peering: int, type: int) -> bool:
	if !ts or !td or peering < 0 or peering > 15 or type < 0:
		return false
	
	var ts_meta = _get_terrain_meta(ts)
	var td_meta = _get_tile_meta(td)
	if td_meta.type < 0 or td_meta.type >= ts_meta.terrains.size():
		return false
	
	if !td_meta.has(peering):
		td_meta[peering] = [type]
	elif !td_meta[peering].has(type):
		td_meta[peering].append(type)
	else:
		return false
	_set_tile_meta(td, td_meta)
	_purge_cache(ts)
	return true


func remove_tile_peering_type(ts: TileSet, td: TileData, peering: int, type: int) -> bool:
	if !ts or !td or peering < 0 or peering > 15 or type < 0:
		return false
	
	var td_meta = _get_tile_meta(td)
	if !td_meta.has(peering):
		return false
	if !td_meta[peering].has(type):
		return false
	td_meta[peering].erase(type)
	if td_meta[peering].is_empty():
		td_meta.erase(peering)
	_set_tile_meta(td, td_meta)
	_purge_cache(ts)
	return true


func tile_peering_keys(td: TileData) -> Array:
	if !td:
		return []
	
	var td_meta = _get_tile_meta(td)
	var result = []
	for k in td_meta:
		if k is int:
			result.append(k)
	return result


func tile_peering_types(td: TileData, peering: int) -> Array:
	if !td or peering < 0 or peering > 15:
		return []
	
	var td_meta = _get_tile_meta(td)
	return td_meta[peering].duplicate() if td_meta.has(peering) else []


# Painting
func set_cell(tm: TileMap, layer: int, coord: Vector2i, type: int) -> bool:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count() or type < 0:
		return false
	
	var cache = _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	if cache[type].is_empty():
		return false
	
	var tile = cache[type].front()
	tm.set_cell(layer, coord, tile[0], tile[1], tile[2])
	return true


func set_cells(tm: TileMap, layer: int, coords: Array, type: int) -> bool:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count() or type < 0:
		return false
	
	var cache = _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	var tile = cache[type].front()
	for c in coords:
		tm.set_cell(layer, c, tile[0], tile[1], tile[2])
	return true


func get_cell(tm: TileMap, layer: int, coord: Vector2i) -> int:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count():
		return -1
	
	if tm.get_cell_source_id(layer, coord) == -1:
		return -1
	
	var t = tm.get_cell_tile_data(layer, coord)
	if !t:
		return -1
	
	return _get_tile_meta(t).type


func update_terrain_cells(tm: TileMap, layer: int, cells: Array, and_surrounding_cells := true) -> void:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count():
		return
	
	if and_surrounding_cells:
		cells = _widen(tm, cells)
	var needed_cells = _widen(tm, cells)
	
	var types = {}
	for c in needed_cells:
		types[c] = get_cell(tm, layer, c)
	
	var ts_meta = _get_terrain_meta(tm.tile_set)
	for c in cells:
		_update_tile(tm, layer, c, ts_meta, types)


#helper
func update_terrain_cell(tm: TileMap, layer: int, cell: Vector2i, and_surrounding_cells := true) -> void:
	update_terrain_cells(tm, layer, [cell], and_surrounding_cells)


func update_terrain_area(tm: TileMap, layer: int, area: Rect2i, and_surrounding_cells := true) -> void:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count():
		return
	
	# Normalize area and extend so tiles cover inclusive space
	area = area.abs()
	area.size += Vector2i.ONE
	
	var edges = []
	for x in range(area.position.x, area.end.x):
		edges.append(Vector2i(x, area.position.y))
		edges.append(Vector2i(x, area.end.y - 1))
	for y in range(area.position.y + 1, area.end.y - 1):
		edges.append(Vector2i(area.position.x, y))
		edges.append(Vector2i(area.end.x - 1, y))
	
	var additional_cells = []
	var needed_cells = _widen_with_exclusion(tm, edges, area)
	
	if and_surrounding_cells:
		additional_cells = needed_cells
		needed_cells = _widen_with_exclusion(tm, needed_cells, area)
	
	var types = {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var coord = Vector2i(x, y)
			types[coord] = get_cell(tm, layer, coord)
	for c in needed_cells:
		types[c] = get_cell(tm, layer, c)
	
	var ts_meta = _get_terrain_meta(tm.tile_set)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var coord = Vector2i(x, y)
			_update_tile(tm, layer, coord, ts_meta, types)
	for c in additional_cells:
		_update_tile(tm, layer, c, ts_meta, types)
