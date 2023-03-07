@tool
extends Node

## A [TileMap] terrain / auto-tiling system.
##
## This is a drop-in replacement for Godot 4's tilemap terrain system, offering
## more versatile and straightforward autotiling. It can be used with any
## existing [TileMap] or [TileSet], either through the editor plugin, or
## directly via code.
## [br][br]
## The [b]BetterTerrain[/b] class contains only static functions, each of which
## either takes a [TileMap], a [TileSet], and sometimes a [TileData]. Meta-data
## is embedded inside the [TileSet] and the [TileData] types to store the
## terrain information. See [method Object.get_meta] for information.
## [br][br]
## Once terrain is set up, it can be written to the tilemap using [method set_cells].
## Similar to Godot 3.x, setting the cells does not run the terrain solved, so once
## the cells have been set, you need to call an update function such as [method update_terrain_cells].


## The meta-data key used to store terrain information.
const TERRAIN_META = &"_better_terrain"

## The current version. Used to handle future upgrades.
const TERRAIN_SYSTEM_VERSION = "0.1"

var _tile_cache = {}

## A helper class that provides functions detailing valid peering bits and
## polygons for different tile types.
var data := load("res://addons/better-terrain/BetterTerrainData.gd"):
	get:
		return data

enum TerrainType {
	MATCH_TILES, ## Selects tiles by matching against adjacent tiles.
	MATCH_VERTICES, ## Select tiles by analysing vertices, similar to wang-style tiles.
	CATEGORY, ## Declares a matching type for more sophisticated rules.
	MAX
}

# Array intersection
func _intersect(first: Array, second: Array) -> bool:
	if first.size() > second.size():
		return _intersect(second, first) # Array 'has' is fast compared to gdscript loop
	for f in first:
		if second.has(f):
			return true
	return false


# Meta-data functions
func _get_terrain_meta(ts: TileSet) -> Dictionary:
	return ts.get_meta(TERRAIN_META) if ts and ts.has_meta(TERRAIN_META) else {
		terrains = [],
		version = TERRAIN_SYSTEM_VERSION
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
	
	var cache = []
	if !ts:
		return cache
	_tile_cache[ts] = cache

	var watcher = Node.new()
	watcher.set_script(load("res://addons/better-terrain/Watcher.gd"))
	watcher.tileset = ts
	watcher.trigger.connect(_purge_cache.bind(ts))
	add_child(watcher)
	ts.changed.connect(watcher.activate)
	
	var types = []
	
	var ts_meta := _get_terrain_meta(ts)
	for t in ts_meta.terrains.size():
		var terrain = ts_meta.terrains[t]
		var bits = terrain[3].duplicate()
		bits.push_back(t)
		types.push_back(bits)
		cache.push_back([])
	
	for s in ts.get_source_count():
		var source_id := ts.get_source_id(s)
		var source := ts.get_source(source_id) as TileSetAtlasSource
		if !source:
			continue
		source.changed.connect(watcher.activate)
		for c in source.get_tiles_count():
			var coord := source.get_tile_id(c)
			for a in source.get_alternative_tiles_count(coord):
				var alternate := source.get_alternative_tile_id(coord, a)
				var td := source.get_tile_data(coord, alternate)
				var td_meta := _get_tile_meta(td)
				if td_meta.type < 0 or td_meta.type >= cache.size():
					continue
				
				td.changed.connect(watcher.activate)
				var peering = {}
				for key in td_meta.keys():
					if !(key is int):
						continue
					
					var targets = []
					for t in types.size():
						if _intersect(types[t], td_meta[key]):
							targets.push_back(t)
					
					peering[key] = targets
				
				cache[td_meta.type].push_back([source_id, coord, alternate, peering, td.probability])
	
	return cache


func _purge_cache(ts: TileSet) -> void:
	_tile_cache.erase(ts)
	for c in get_children():
		if c.tileset == ts:
			c.tidy()
			break


func _clear_invalid_peering_types(ts: TileSet) -> void:
	var ts_meta := _get_terrain_meta(ts)
	
	var cache := _get_cache(ts)
	for t in cache.size():
		var type = ts_meta.terrains[t][2]
		var valid_peering_types = data.get_terrain_peering_cells(ts, type)
		
		for c in cache[t]:
			var source := ts.get_source(c[0]) as TileSetAtlasSource
			var td := source.get_tile_data(c[1], c[2])
			var td_meta = _get_tile_meta(td)
			
			for peering in c[3].keys():
				if valid_peering_types.has(peering):
					continue
				td_meta.erase(peering)
			
			_set_tile_meta(td, td_meta)
	
	# Not strictly necessary
	_purge_cache(ts)


func _has_invalid_peering_types(ts: TileSet) -> bool:
	var ts_meta := _get_terrain_meta(ts)
	
	var cache := _get_cache(ts)
	for t in cache.size():
		var type = ts_meta.terrains[t][2]
		var valid_peering_types = data.get_terrain_peering_cells(ts, type)
		
		for c in cache[t]:
			for peering in c[3].keys():
				if !valid_peering_types.has(peering):
					return true
	
	return false


func _update_terrain_data(ts: TileSet) -> void:
	var ts_meta = _get_terrain_meta(ts)
	if !ts_meta.has("version"):
		for t in ts_meta.terrains:
			if t.size() == 3:
				t.push_back([])
		_set_terrain_meta(ts, ts_meta)


func _weighted_selection(choices: Array):
	if choices.is_empty():
		return null
	if choices.size() == 1:
		return choices[0]
	
	var weight = choices.reduce(func(a, c): return a + c[4], 0.0)
	if weight == 0.0:
		return choices[randi() % choices.size()]
	
	var pick = randf() * weight
	for c in choices:
		if pick < c[4]:
			return c
		pick -= c[4]
	return choices.back()


func _update_tile_tiles(tm: TileMap, layer: int, coord: Vector2i, types: Dictionary):
	var type = types[coord]
	var c := _get_cache(tm.tile_set)
	
	var best_score := -1000 # Impossibly bad score
	var best := []
	for t in c[type]:
		var score = 0
		for peering in t[3]:
			score += 3 if t[3][peering].has(types[tm.get_neighbor_cell(coord, peering)]) else -10
		
		if score > best_score:
			best_score = score
			best = [t]
		elif score == best_score:
			best.append(t)
	
	return _weighted_selection(best)


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


func _update_tile_vertices(tm: TileMap, layer: int, coord: Vector2i, types: Dictionary):
	var type = types[coord]
	var c := _get_cache(tm.tile_set)
	
	var best_score := -1000 # Impossibly bad score
	var best = []
	for t in c[type]:
		var score := 0
		for peering in t[3]:
			score += _probe(tm, coord, peering, types, t[3][peering])
		
		if score > best_score:
			best_score = score
			best = [t]
		elif score == best_score:
			best.append(t)
	
	return _weighted_selection(best)


func _update_tile_immediate(tm: TileMap, layer: int, coord: Vector2i, ts_meta: Dictionary, types: Dictionary) -> void:
	var type = types[coord]
	if type < 0 or type >= ts_meta.terrains.size():
		return
	
	var placement
	var terrain = ts_meta.terrains[type]
	if terrain[2] == TerrainType.MATCH_TILES:
		placement = _update_tile_tiles(tm, layer, coord, types)
	elif terrain[2] == TerrainType.MATCH_VERTICES:
		placement = _update_tile_vertices(tm, layer, coord, types)
	else:
		return
	
	if placement:
		tm.set_cell(layer, coord, placement[0], placement[1], placement[2])


func _update_tile_deferred(tm: TileMap, layer: int, coord: Vector2i, ts_meta: Dictionary, types: Dictionary):
	var type = types[coord]
	if type >= 0 and type < ts_meta.terrains.size():
		var terrain = ts_meta.terrains[type]
		if terrain[2] == TerrainType.MATCH_TILES:
			return _update_tile_tiles(tm, layer, coord, types)
		elif terrain[2] == TerrainType.MATCH_VERTICES:
			return _update_tile_vertices(tm, layer, coord, types)
	return null


func _widen(tm: TileMap, coords: Array) -> Array:
	var result := {}
	for c in coords:
		result[c] = true
		var neighbors = data.neighboring_coords(tm, c, data.get_terrain_peering_cells(tm.tile_set, TerrainType.MATCH_TILES))
		for t in neighbors:
			result[t] = true
	return result.keys()


func _widen_with_exclusion(tm: TileMap, coords: Array, exclusion: Rect2i) -> Array:
	var result := {}
	for c in coords:
		if !exclusion.has_point(c):
			result[c] = true
		var neighbors = data.neighboring_coords(tm, c, data.get_terrain_peering_cells(tm.tile_set, TerrainType.MATCH_TILES))
		for t in neighbors:
			if !exclusion.has_point(t):
				result[t] = true
	return result.keys()

# Terrains

## Returns an [Array] of categories. These are the terrains in the [TileSet] which
## are marked with [enum TerrainType] of [code]CATEGORY[/code]. Each entry in the
## array is a [Dictionary] with [code]name[/code], [code]color[/code], and [code]id[/code].
func get_terrain_categories(ts: TileSet) -> Array:
	var result = []
	if !ts:
		return result
	
	var ts_meta := _get_terrain_meta(ts)
	for id in ts_meta.terrains.size():
		var t = ts_meta.terrains[id]
		if t[2] == TerrainType.CATEGORY:
			result.push_back({name = t[0], color = t[1], id = id})
	
	return result


## Adds a new terrain to the [TileSet]. Returns [code]true[/code] if this is successful.
## [br][br]
## [code]type[/code] must be one of [enum TerrainType].[br]
## [code]categories[/code] is an indexed list of terrain categories that this terrain
## can match as. The indexes must be valid terrains of the CATEGORY type.
func add_terrain(ts: TileSet, name: String, color: Color, type: int, categories: Array = []) -> bool:
	if !ts or name.is_empty() or type < 0 or type >= TerrainType.MAX:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	
	# check categories
	if type == TerrainType.CATEGORY and !categories.is_empty():
		return false
	for c in categories:
		if c < 0 or c >= ts_meta.terrains.size() or ts_meta.terrains[c][2] != TerrainType.CATEGORY:
			return false
	
	ts_meta.terrains.push_back([name, color, type, categories])
	_set_terrain_meta(ts, ts_meta)
	_purge_cache(ts)
	return true


## Removes the terrain at [code]index[/code] from the [TileSet]. Returns [code]true[/code]
## if the deletion is successful.
func remove_terrain(ts: TileSet, index: int) -> bool:
	if !ts or index < 0:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return false
	
	if ts_meta.terrains[index][2] == TerrainType.CATEGORY:
		for t in ts_meta.terrains:
			t[3].erase(index)
	
	for s in ts.get_source_count():
		var source := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if !source:
			continue
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			for a in source.get_alternative_tiles_count(coord):
				var alternate := source.get_alternative_tile_id(coord, a)
				var td := source.get_tile_data(coord, alternate)
				
				var td_meta := _get_tile_meta(td)
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


## Returns the number of terrains in the [TileSet].
func terrain_count(ts: TileSet) -> int:
	if !ts:
		return 0
	
	var ts_meta := _get_terrain_meta(ts)
	return ts_meta.terrains.size()


## Retrieves information about the terrain at [code]index[/code] in the [TileSet].
## [br][br]
## Returns a [Dictionary] describing the terrain. If it succeeds, the key [code]valid[/code]
## will be set to [code]true[/code]. Other keys are [code]name[/code], [code]color[/code],
## [code]type[/code] (a [enum TerrainType]), and [code]categories[/code] which is
## an [Array] of category type terrains that this terrain matches as.
func get_terrain(ts: TileSet, index: int) -> Dictionary:
	if !ts or index < 0:
		return {valid = false}
	
	var ts_meta := _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return {valid = false}
	
	var terrain = ts_meta.terrains[index]
	return {
		name = terrain[0],
		color = terrain[1],
		type = terrain[2],
		categories = terrain[3],
		valid = true
	}


## Updates the details of the terrain at [code]index[/code] in [TileSet]. Returns
## [code]true[/code] if this succeeds.
## [br][br]
## If supplied, the [code]categories[/code] must be a list of indexes to other [code]CATEGORY[/code]
## type terrains.
func set_terrain(ts: TileSet, index: int, name: String, color: Color, type: int, categories: Array = []) -> bool:
	if !ts or name.is_empty() or index < 0 or type < 0 or type >= TerrainType.MAX:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return false
	
	if type == TerrainType.CATEGORY and !categories.is_empty():
		return false
	for c in categories:
		if c < 0 or c == index or c >= ts_meta.terrains.size() or ts_meta.terrains[c][2] != TerrainType.CATEGORY:
			return false
	
	if type != TerrainType.CATEGORY:
		for t in ts_meta.terrains:
			t[3].erase(index)
	
	ts_meta.terrains[index] = [name, color, type, categories]
	_set_terrain_meta(ts, ts_meta)
	
	_clear_invalid_peering_types(ts)
	_purge_cache(ts)
	return true


## Swaps the terrains at [code]index1[/code] and [code]index2[/code] in [TileSet].
func swap_terrains(ts: TileSet, index1: int, index2: int) -> bool:
	if !ts or index1 < 0 or index2 < 0 or index1 == index2:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	if index1 >= ts_meta.terrains.size() or index2 >= ts_meta.terrains.size():
		return false
	
	for t in ts_meta.terrains:
		var has1 = t[3].has(index1)
		var has2 = t[3].has(index2)
		
		if has1 and !has2:
			t[3].erase(index1)
			t[3].push_back(index2)
		elif has2 and !has1:
			t[3].erase(index2)
			t[3].push_back(index1)
	
	for s in ts.get_source_count():
		var source := ts.get_source(ts.get_source_id(s)) as TileSetAtlasSource
		if !source:
			continue
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			for a in source.get_alternative_tiles_count(coord):
				var alternate := source.get_alternative_tile_id(coord, a)
				var td := source.get_tile_data(coord, alternate)
				
				var td_meta := _get_tile_meta(td)
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

## For a tile in a [TileSet] as specified by [TileData], set the terrain associated
## with that tile to [code]type[/code], which is an index of an existing terrain.
## Returns [code]true[/code] on success.
func set_tile_terrain_type(ts: TileSet, td: TileData, type: int) -> bool:
	if !ts or !td or type < -1:
		return false
	
	var td_meta = _get_tile_meta(td)
	td_meta.type = type
	if type == -1:
		td_meta = null
	_set_tile_meta(td, td_meta)
	
	_clear_invalid_peering_types(ts)
	_purge_cache(ts)
	return true


## Returns the terrain type associated with tile specified by [TileData]. Returns
## -1 if the tile has no associated terrain.
func get_tile_terrain_type(td: TileData) -> int:
	if !td:
		return -1
	var td_meta := _get_tile_meta(td)
	return td_meta.type


## For a [TileSet]'s tile, specified by [TileData], add terrain [code]type[/code]
## (an index of a terrain) to match this tile in direction [code]peering[/code],
## which is of type [enum TileSet.CellNeighbor]. Returns [code]true[/code] on success.
func add_tile_peering_type(ts: TileSet, td: TileData, peering: int, type: int) -> bool:
	if !ts or !td or peering < 0 or peering > 15 or type < 0:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	var td_meta := _get_tile_meta(td)
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


## For a [TileSet]'s tile, specified by [TileData], remove terrain [code]type[/code]
## from matching in direction [code]peering[/code], which is of type [enum TileSet.CellNeighbor].
## Returns [code]true[/code] on success.
func remove_tile_peering_type(ts: TileSet, td: TileData, peering: int, type: int) -> bool:
	if !ts or !td or peering < 0 or peering > 15 or type < 0:
		return false
	
	var td_meta := _get_tile_meta(td)
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


## For the tile specified by [TileData], return an [Array] of peering directions
## for which terrain matching is set up. These will be of type [enum TileSet.CellNeighbor].
func tile_peering_keys(td: TileData) -> Array:
	if !td:
		return []
	
	var td_meta := _get_tile_meta(td)
	var result := []
	for k in td_meta:
		if k is int:
			result.append(k)
	return result


## For the tile specified by [TileData], return the [Array] of terrains that match
## for the direction [code]peering[/code] which should be of type [enum TileSet.CellNeighbor].
func tile_peering_types(td: TileData, peering: int) -> Array:
	if !td or peering < 0 or peering > 15:
		return []
	
	var td_meta := _get_tile_meta(td)
	return td_meta[peering].duplicate() if td_meta.has(peering) else []


# Painting

## Applies the terrain [code]type[/code] to the [TileMap] for the [code]layer[/code]
## and [code]coord[/code]. Returns [code]true[/code] if it succeeds. Use [method set_cells]
## to change multiple tiles at once.
func set_cell(tm: TileMap, layer: int, coord: Vector2i, type: int) -> bool:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count() or type < 0:
		return false
	
	var cache := _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	if cache[type].is_empty():
		return false
	
	var tile = cache[type].front()
	tm.set_cell(layer, coord, tile[0], tile[1], tile[2])
	return true


## Applies the terrain [code]type[/code] to the [TileMap] for the [code]layer[/code]
## and [Vector2i] [code]coords[/code]. Returns [code]true[/code] if it succeeds.
## [br][br]
## Note that this does not cause the terrain solver to run, so this will just place
## an arbitrary terrain-associated tile in the given position. To run the solver,
## you must set the require cells, and then call either [method update_terrain_cell],
## [method update_terrain_cels], or [method update_terrain_area].
## [br][br]
## If you want to prepare changes to the tiles in advance, you can use [method create_terrain_changeset]
## and the associated functions.
func set_cells(tm: TileMap, layer: int, coords: Array, type: int) -> bool:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count() or type < 0:
		return false
	
	var cache := _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	var tile = cache[type].front()
	for c in coords:
		tm.set_cell(layer, c, tile[0], tile[1], tile[2])
	return true


## Returns the terrain type detected in the [TileMap] at specified [code]layer[/code]
## and [code]coord[/code]. Returns -1 if tile is not valid or does not contain a
## tile associated with a terrain.
func get_cell(tm: TileMap, layer: int, coord: Vector2i) -> int:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count():
		return -1
	
	if tm.get_cell_source_id(layer, coord) == -1:
		return -1
	
	var t = tm.get_cell_tile_data(layer, coord)
	if !t:
		return -1
	
	return _get_tile_meta(t).type


## Runs the tile solving algorithm on the [TileMap] for the given [code]layer[/code]
## for the [Vector2i] coordinates in the [code]cells[/code] parameter. By default,
## the surrounding cells are also solved, but this can be adjusted by passing [code]false[/code]
## to the [code]and_surrounding_cells[/code] parameter.
## [br][br]
## See also [method update_terrain_area] and [method update_terrain_cell].
func update_terrain_cells(tm: TileMap, layer: int, cells: Array, and_surrounding_cells := true) -> void:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count():
		return
	
	if and_surrounding_cells:
		cells = _widen(tm, cells)
	var needed_cells := _widen(tm, cells)
	
	var types := {}
	for c in needed_cells:
		types[c] = get_cell(tm, layer, c)
	
	var ts_meta := _get_terrain_meta(tm.tile_set)
	for c in cells:
		_update_tile_immediate(tm, layer, c, ts_meta, types)


## Runs the tile solving algorithm on the [TileMap] for the given [code]layer[/code]
## and [code]cell[/code]. By default, the surrounding cells are also solved, but
## this can be adjusted by passing [code]false[/code] to the [code]and_surrounding_cells[/code]
## parameter. This calls through to [method update_terrain_cells].
func update_terrain_cell(tm: TileMap, layer: int, cell: Vector2i, and_surrounding_cells := true) -> void:
	update_terrain_cells(tm, layer, [cell], and_surrounding_cells)


## Runs the tile solving algorithm on the [TileMap] for the given [code]layer[/code]
## and [code]area[/code]. By default, the surrounding cells are also solved, but
## this can be adjusted by passing [code]false[/code] to the [code]and_surrounding_cells[/code]
## parameter.
## [br][br]
## See also [method update_terrain_cells].
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
	
	var additional_cells := []
	var needed_cells := _widen_with_exclusion(tm, edges, area)
	
	if and_surrounding_cells:
		additional_cells = needed_cells
		needed_cells = _widen_with_exclusion(tm, needed_cells, area)
	
	var types := {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var coord = Vector2i(x, y)
			types[coord] = get_cell(tm, layer, coord)
	for c in needed_cells:
		types[c] = get_cell(tm, layer, c)
	
	var ts_meta := _get_terrain_meta(tm.tile_set)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var coord := Vector2i(x, y)
			_update_tile_immediate(tm, layer, coord, ts_meta, types)
	for c in additional_cells:
		_update_tile_immediate(tm, layer, c, ts_meta, types)


## For a [TileMap], on a specific [code]layer[/code], create a changeset that will
## be calculated via a [WorkerThreadPool], so it will not delay processing the current
## frame or affect the framerate.
## [br][br]
## The [code]paint[/code] parameter must be a [Dictionary] with keys of type [Vector2i]
## representing map coordinates, and integer values representing terrain types.
## [br][br]
## Returns a [Dictionary] with internal details. See also [method is_terrain_changeset_ready],
## [method apply_terrain_changeset], and [method wait_for_terrain_changeset].
func create_terrain_changeset(tm: TileMap, layer: int, paint: Dictionary) -> Dictionary:
	# Force cache rebuild if required
	var _cache := _get_cache(tm.tile_set)
	
	var cells := paint.keys()
	var needed_cells := _widen(tm, cells)
	
	var types := {}
	for c in needed_cells:
		types[c] = paint[c] if paint.has(c) else get_cell(tm, layer, c)
	
	var placements := []
	placements.resize(cells.size())
	
	var ts_meta := _get_terrain_meta(tm.tile_set)
	var work := func(n: int):
		placements[n] = _update_tile_deferred(tm, layer, cells[n], ts_meta, types)
	
	return {
		"valid": true,
		"tilemap": tm,
		"layer": layer,
		"cells": cells,
		"placements": placements,
		"group_id": WorkerThreadPool.add_group_task(work, cells.size(), -1, false, "BetterTerrain")
	}


## Returns [code]true[/code] if a changeset created by [method create_terrain_changeset]
## has finished the threaded calculation and is ready to be applied by [method apply_terrain_changeset].
## See also [method wait_for_terrain_changeset].
func is_terrain_changeset_ready(change: Dictionary) -> bool:
	if !change.has("group_id"):
		return false
	
	return WorkerThreadPool.is_group_task_completed(change.group_id)


## Blocks until a changeset created by [method create_terrain_changeset] finishes.
## This is useful to tidy up threaded work in the event that a node is to be removed
## whilst still waiting on threads.
## [br][br]
## Usage example:
## [codeblock]
## func _exit_tree():
##     if changeset.valid:
##         BetterTerrain.wait_for_terrain_changeset(changeset)
## [/codeblock]
func wait_for_terrain_changeset(change: Dictionary) -> void:
	if change.has("group_id"):
		WorkerThreadPool.wait_for_group_task_completion(change.group_id)


## Apply the changes in a changeset created by [method create_terrain_changeset]
## once it is confirmed by [method is_terrain_changeset_ready]. The changes will
## be applied to the [TileMap] that the changeset was initialized with.
## [br][br]
## Completed changesets can be applied multiple times, and stored for as long as
## needed once calculated.
func apply_terrain_changeset(change: Dictionary) -> void:
	for n in change.cells.size():
		var placement = change.placements[n]
		if placement:
			change.tilemap.set_cell(change.layer, change.cells[n], placement[0], placement[1], placement[2])
