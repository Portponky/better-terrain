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
const TERRAIN_SYSTEM_VERSION = "0.2"

var _tile_cache = {}
var rng = RandomNumberGenerator.new()
var use_seed := true

## A helper class that provides functions detailing valid peering bits and
## polygons for different tile types.
var data := load("res://addons/better-terrain/BetterTerrainData.gd"):
	get:
		return data

enum TerrainType {
	MATCH_TILES, ## Selects tiles by matching against adjacent tiles.
	MATCH_VERTICES, ## Select tiles by analysing vertices, similar to wang-style tiles.
	CATEGORY, ## Declares a matching type for more sophisticated rules.
	DECORATION, ## Fills empty tiles by matching adjacent tiles
	MAX,
}

enum TileCategory {
	EMPTY = -1, ## An empty cell, or a tile marked as decoration
	NON_TERRAIN = -2, ## A non-empty cell that does not contain a terrain tile
	ERROR = -3
}

enum SymmetryType {
	NONE,
	MIRROR, ## Horizontally mirror
	FLIP, ## Vertically flip
	REFLECT, ## All four reflections
	ROTATE_CLOCKWISE,
	ROTATE_COUNTER_CLOCKWISE,
	ROTATE_180,
	ROTATE_ALL, ## All four rotated forms
	ALL ## All rotated and reflected forms
}


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
		decoration = ["Decoration", Color.DIM_GRAY, TerrainType.DECORATION, [], {path = "res://addons/better-terrain/icons/Decoration.svg"}],
		version = TERRAIN_SYSTEM_VERSION
	}


func _set_terrain_meta(ts: TileSet, meta : Dictionary) -> void:
	ts.set_meta(TERRAIN_META, meta)


func _get_tile_meta(td: TileData) -> Dictionary:
	return td.get_meta(TERRAIN_META) if td.has_meta(TERRAIN_META) else {
		type = TileCategory.NON_TERRAIN
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
	
	var types = {}
	
	var ts_meta := _get_terrain_meta(ts)
	for t in ts_meta.terrains.size():
		var terrain = ts_meta.terrains[t]
		var bits = terrain[3].duplicate()
		bits.push_back(t)
		types[t] = bits
		cache.push_back([])
	
	# Decoration
	types[-1] = [TileCategory.EMPTY]
	cache.push_back([[-1, Vector2.ZERO, -1, {}, 1.0]])
	
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
				if td_meta.type < TileCategory.EMPTY or td_meta.type >= cache.size():
					continue
				
				td.changed.connect(watcher.activate)
				var peering = {}
				for key in td_meta.keys():
					if !(key is int):
						continue
					
					var targets = []
					for k in types:
						if _intersect(types[k], td_meta[key]):
							targets.push_back(k)
					
					peering[key] = targets
				
				# Decoration tiles without peering are skipped
				if td_meta.type == TileCategory.EMPTY and !peering:
					continue
				
				var symmetry = td_meta.get("symmetry", SymmetryType.NONE)
				# Branch out no symmetry tiles early
				if symmetry == SymmetryType.NONE:
					cache[td_meta.type].push_back([source_id, coord, alternate, peering, td.probability])
					continue
				
				for flags in data.symmetry_mapping[symmetry]:
					var symmetric_peering = data.peering_bits_after_symmetry(peering, flags)
					cache[td_meta.type].push_back([source_id, coord, alternate | flags, symmetric_peering, td.probability])
	
	return cache


func _get_cache_terrain(ts_meta : Dictionary, index: int) -> Array:
	# the cache and the terrains in ts_meta don't line up because
	# decorations are cached too
	if index < 0 or index >= ts_meta.terrains.size():
		return ts_meta.decoration
	return ts_meta.terrains[index]


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
		var type = _get_cache_terrain(ts_meta, t)[2]
		var valid_peering_types = data.get_terrain_peering_cells(ts, type)
		
		for c in cache[t]:
			if c[0] < 0:
				continue
			var source := ts.get_source(c[0]) as TileSetAtlasSource
			if !source:
				continue
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
		var type = _get_cache_terrain(ts_meta, t)[2]
		var valid_peering_types = data.get_terrain_peering_cells(ts, type)
		
		for c in cache[t]:
			for peering in c[3].keys():
				if !valid_peering_types.has(peering):
					return true
	
	return false


func _update_terrain_data(ts: TileSet) -> void:
	var ts_meta = _get_terrain_meta(ts)
	var previous_version = ts_meta.get("version")
	
	# First release: no version info
	if !ts_meta.has("version"):
		ts_meta["version"] = "0.0"
	
	# 0.0 -> 0.1: add categories
	if ts_meta.version == "0.0":
		for t in ts_meta.terrains:
			if t.size() == 3:
				t.push_back([])
		ts_meta.version = "0.1"
	
	# 0.1 -> 0.2: add decoration tiles and terrain icons
	if ts_meta.version == "0.1":
		# Add terrain icon containers
		for t in ts_meta.terrains:
			if t.size() == 4:
				t.push_back({})
		
		# Add default decoration data
		ts_meta["decoration"] = ["Decoration", Color.DIM_GRAY, TerrainType.DECORATION, [], {path = "res://addons/better-terrain/icons/Decoration.svg"}]
		ts_meta.version = "0.2"
	
	if previous_version != ts_meta.version:
		_set_terrain_meta(ts, ts_meta)


func _weighted_selection(choices: Array, apply_empty_probability: bool):
	if choices.is_empty():
		return null
	
	if apply_empty_probability:
		var max_weight = choices.reduce(func(a, c): return maxf(a, c[4]), 0.0)
		if max_weight < 1.0 and rng.randf() > max_weight:
			return [-1, Vector2.ZERO, -1, null, 1.0]
	
	if choices.size() == 1:
		return choices[0]
	
	var weight = choices.reduce(func(a, c): return a + c[4], 0.0)
	if weight == 0.0:
		return choices[rng.randi() % choices.size()]
	
	var pick = rng.randf() * weight
	for c in choices:
		if pick < c[4]:
			return c
		pick -= c[4]
	return choices.back()


func _weighted_selection_seeded(choices: Array, coord: Vector2i, apply_empty_probability: bool):
	if use_seed:
		rng.seed = hash(coord)
	return _weighted_selection(choices, apply_empty_probability)


func _update_tile_tiles(tm: TileMap, coord: Vector2i, types: Dictionary, cache: Array, apply_empty_probability: bool):
	var type = types[coord]
	
	var best_score := -1000 # Impossibly bad score
	var best := []
	for t in cache[type]:
		var score = 0
		for peering in t[3]:
			score += 3 if t[3][peering].has(types[tm.get_neighbor_cell(coord, peering)]) else -10
		
		if score > best_score:
			best_score = score
			best = [t]
		elif score == best_score:
			best.append(t)
	
	return _weighted_selection_seeded(best, coord, apply_empty_probability)


func _probe(tm: TileMap, coord: Vector2i, peering: int, type: int, types: Dictionary) -> int:
	var targets = data.associated_vertex_cells(tm, coord, peering)
	targets = targets.map(func(c): return types[c])
	
	var first = targets[0]
	if targets.all(func(t): return t == first):
		return first
	
	# if different, use the lowest  non-same
	targets = targets.filter(func(t): return t != type)
	return targets.reduce(func(a, t): return min(a, t))


func _update_tile_vertices(tm: TileMap, coord: Vector2i, types: Dictionary, cache: Array):
	var type = types[coord]
	
	var best_score := -1000 # Impossibly bad score
	var best = []
	for t in cache[type]:
		var score := 0
		for peering in t[3]:
			score += 3 if _probe(tm, coord, peering, type, types) in t[3][peering] else -10
		
		if score > best_score:
			best_score = score
			best = [t]
		elif score == best_score:
			best.append(t)
	
	return _weighted_selection_seeded(best, coord, false)


func _update_tile_immediate(tm: TileMap, layer: int, coord: Vector2i, ts_meta: Dictionary, types: Dictionary, cache: Array) -> void:
	var type = types[coord]
	if type < TileCategory.EMPTY or type >= ts_meta.terrains.size():
		return
	
	var placement
	var terrain = _get_cache_terrain(ts_meta, type)
	if terrain[2] in [TerrainType.MATCH_TILES, TerrainType.DECORATION]:
		placement = _update_tile_tiles(tm, coord, types, cache, terrain[2] == TerrainType.DECORATION)
	elif terrain[2] == TerrainType.MATCH_VERTICES:
		placement = _update_tile_vertices(tm, coord, types, cache)
	else:
		return
	
	if placement:
		tm.set_cell(layer, coord, placement[0], placement[1], placement[2])


func _update_tile_deferred(tm: TileMap, coord: Vector2i, ts_meta: Dictionary, types: Dictionary, cache: Array):
	var type = types[coord]
	if type >= TileCategory.EMPTY and type < ts_meta.terrains.size():
		var terrain = _get_cache_terrain(ts_meta, type)
		if terrain[2] in [TerrainType.MATCH_TILES, TerrainType.DECORATION]:
			return _update_tile_tiles(tm, coord, types, cache, terrain[2] == TerrainType.DECORATION)
		elif terrain[2] == TerrainType.MATCH_VERTICES:
			return _update_tile_vertices(tm, coord, types, cache)
	return null


func _widen(tm: TileMap, coords: Array) -> Array:
	var result := {}
	var peering_neighbors = data.get_terrain_peering_cells(tm.tile_set, TerrainType.MATCH_TILES)
	for c in coords:
		result[c] = true
		var neighbors = data.neighboring_coords(tm, c, peering_neighbors)
		for t in neighbors:
			result[t] = true
	return result.keys()


func _widen_with_exclusion(tm: TileMap, coords: Array, exclusion: Rect2i) -> Array:
	var result := {}
	var peering_neighbors = data.get_terrain_peering_cells(tm.tile_set, TerrainType.MATCH_TILES)
	for c in coords:
		if !exclusion.has_point(c):
			result[c] = true
		var neighbors = data.neighboring_coords(tm, c, peering_neighbors)
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
## [code]icon[/code] is a [Dictionary] with either a [code]path[/code] string pointing
## to a resource, or a [code]source_id[/code] [int] and a [code]coord[/code] [Vector2i].
## The former takes priority if both are present.
func add_terrain(ts: TileSet, name: String, color: Color, type: int, categories: Array = [], icon: Dictionary = {}) -> bool:
	if !ts or name.is_empty() or type < 0 or type == TerrainType.DECORATION or type >= TerrainType.MAX:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	
	# check categories
	if type == TerrainType.CATEGORY and !categories.is_empty():
		return false
	for c in categories:
		if c < 0 or c >= ts_meta.terrains.size() or ts_meta.terrains[c][2] != TerrainType.CATEGORY:
			return false
	
	if icon and not (icon.has("path") or (icon.has("source_id") and icon.has("coord"))):
		return false
	
	ts_meta.terrains.push_back([name, color, type, categories, icon])
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
				if td_meta.type == TileCategory.NON_TERRAIN:
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
## [code]type[/code] (a [enum TerrainType]), [code]categories[/code] which is
## an [Array] of category type terrains that this terrain matches as, and
## [code]icon[/code] which is a [Dictionary] with a [code]path[/code] [String] or
## a [code]source_id[/code] [int] and [code]coord[/code] [Vector2i]
func get_terrain(ts: TileSet, index: int) -> Dictionary:
	if !ts or index < TileCategory.EMPTY:
		return {valid = false}
	
	var ts_meta := _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return {valid = false}
	
	var terrain = _get_cache_terrain(ts_meta, index)
	return {
		id = index,
		name = terrain[0],
		color = terrain[1],
		type = terrain[2],
		categories = terrain[3].duplicate(),
		icon = terrain[4].duplicate(),
		valid = true
	}


## Updates the details of the terrain at [code]index[/code] in [TileSet]. Returns
## [code]true[/code] if this succeeds.
## [br][br]
## If supplied, the [code]categories[/code] must be a list of indexes to other [code]CATEGORY[/code]
## type terrains.
## [code]icon[/code] is a [Dictionary] with either a [code]path[/code] string pointing
## to a resource, or a [code]source_id[/code] [int] and a [code]coord[/code] [Vector2i].
func set_terrain(ts: TileSet, index: int, name: String, color: Color, type: int, categories: Array = [], icon: Dictionary = {valid = false}) -> bool:
	if !ts or name.is_empty() or index < 0 or type < 0 or type == TerrainType.DECORATION or type >= TerrainType.MAX:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	if index >= ts_meta.terrains.size():
		return false
	
	if type == TerrainType.CATEGORY and !categories.is_empty():
		return false
	for c in categories:
		if c < 0 or c == index or c >= ts_meta.terrains.size() or ts_meta.terrains[c][2] != TerrainType.CATEGORY:
			return false
	
	var icon_valid = icon.get("valid", "true")
	if icon_valid:
		match icon:
			{}, {"path"}, {"source_id", "coord"}: pass
			_: return false
	
	if type != TerrainType.CATEGORY:
		for t in ts_meta.terrains:
			t[3].erase(index)
	
	ts_meta.terrains[index] = [name, color, type, categories, icon]
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
				if td_meta.type == TileCategory.NON_TERRAIN:
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
	if !ts or !td or type < TileCategory.NON_TERRAIN:
		return false
	
	var td_meta = _get_tile_meta(td)
	td_meta.type = type
	if type == TileCategory.NON_TERRAIN:
		td_meta = null
	_set_tile_meta(td, td_meta)
	
	_clear_invalid_peering_types(ts)
	_purge_cache(ts)
	return true


## Returns the terrain type associated with tile specified by [TileData]. Returns
## -1 if the tile has no associated terrain.
func get_tile_terrain_type(td: TileData) -> int:
	if !td:
		return TileCategory.ERROR
	var td_meta := _get_tile_meta(td)
	return td_meta.type


## For a tile represented by [TileData] [code]td[/code] in [TileSet]
## [code]ts[/code], sets [enum SymmetryType] [code]type[/code]. This controls
## how the tile is rotated/mirrored during placement.
func set_tile_symmetry_type(ts: TileSet, td: TileData, type: int) -> bool:
	if !ts or !td or type < SymmetryType.NONE or type > SymmetryType.ALL:
		return false
	
	var td_meta := _get_tile_meta(td)
	if td_meta.type == TileCategory.NON_TERRAIN:
		return false
	
	td_meta.symmetry = type
	_set_tile_meta(td, td_meta)
	_purge_cache(ts)
	return true


## For a tile [code]td[/code], returns the [enum SymmetryType] which that
## tile uses.
func get_tile_symmetry_type(td: TileData) -> int:
	if !td:
		return SymmetryType.NONE
	
	var td_meta := _get_tile_meta(td)
	return td_meta.get("symmetry", SymmetryType.NONE)


## Returns an Array of all [TileData] tiles included in the specified
## terrain [code]type[/code] for the [TileSet] [code]ts[/code]
func get_tiles_in_terrain(ts: TileSet, type: int) -> Array[TileData]:
	var result:Array[TileData] = []
	if !ts or type < TileCategory.EMPTY:
		return result
	
	var cache := _get_cache(ts)
	if type > cache.size():
		return result
	
	var tiles = cache[type]
	if !tiles:
		return result
	for c in tiles:
		if c[0] < 0:
			continue
		var source := ts.get_source(c[0]) as TileSetAtlasSource
		var td := source.get_tile_data(c[1], c[2])
		result.push_back(td)
	
	return result


## Returns an [Array] of [Dictionary] items including information about each 
## tile included in the specified terrain [code]type[/code] for 
## the [TileSet] [code]ts[/code]. Each Dictionary item includes 
## [TileSetAtlasSource] [code]source[/code], [TileData] [code]td[/code], 
## [Vector2i] [code]coord[/code], and [int] [code]alt_id[/code].
func get_tile_sources_in_terrain(ts: TileSet, type: int) -> Array[Dictionary]:
	var result:Array[Dictionary] = []
	
	var cache := _get_cache(ts)
	var tiles = cache[type]
	if !tiles:
		return result
	for c in tiles:
		if c[0] < 0:
			continue
		var source := ts.get_source(c[0]) as TileSetAtlasSource
		if not source:
			continue
		var td := source.get_tile_data(c[1], c[2])
		result.push_back({
			source = source,
			td = td,
			coord = c[1],
			alt_id = c[2]
		})
	
	return result


## For a [TileSet]'s tile, specified by [TileData], add terrain [code]type[/code]
## (an index of a terrain) to match this tile in direction [code]peering[/code],
## which is of type [enum TileSet.CellNeighbor]. Returns [code]true[/code] on success.
func add_tile_peering_type(ts: TileSet, td: TileData, peering: int, type: int) -> bool:
	if !ts or !td or peering < 0 or peering > 15 or type < TileCategory.EMPTY:
		return false
	
	var ts_meta := _get_terrain_meta(ts)
	var td_meta := _get_tile_meta(td)
	if td_meta.type < TileCategory.EMPTY or td_meta.type >= ts_meta.terrains.size():
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
	if !ts or !td or peering < 0 or peering > 15 or type < TileCategory.EMPTY:
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


## For the tile specified by [TileData], return the [Array] of peering directions
## for the specified terrain type [code]type[/code].
func tile_peering_for_type(td: TileData, type: int) -> Array:
	if !td:
		return []
	
	var td_meta := _get_tile_meta(td)
	var result = []
	var sides = tile_peering_keys(td)
	for side in sides:
		if td_meta[side].has(type):
			result.push_back(side)
	
	result.sort()
	return result


# Painting

## Applies the terrain [code]type[/code] to the [TileMap] for the [code]layer[/code]
## and [code]coord[/code]. Returns [code]true[/code] if it succeeds. Use [method set_cells]
## to change multiple tiles at once.
## [br][br]
## Use terrain type -1 to erase cells.
func set_cell(tm: TileMap, layer: int, coord: Vector2i, type: int) -> bool:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count() or type < TileCategory.EMPTY:
		return false
	
	if type == TileCategory.EMPTY:
		tm.erase_cell(layer, coord)
		return true
	
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
## [br][br]
## Use terrain type -1 to erase cells.
func set_cells(tm: TileMap, layer: int, coords: Array, type: int) -> bool:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count() or type < TileCategory.EMPTY:
		return false
	
	if type == TileCategory.EMPTY:
		for c in coords:
			tm.erase_cell(layer, c)
		return true
	
	var cache := _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	if cache[type].is_empty():
		return false
	
	var tile = cache[type].front()
	for c in coords:
		tm.set_cell(layer, c, tile[0], tile[1], tile[2])
	return true


## Replaces an existing tile on the [TileMap] for the [code]layer[/code]
## and [code]coord[/code] with a new tile in the provided terrain [code]type[/code] 
## *only if* there is a tile with a matching set of peering sides in this terrain.
## Returns [code]true[/code] if any tiles were changed. Use [method replace_cells]
## to replace multiple tiles at once.
func replace_cell(tm: TileMap, layer: int, coord: Vector2i, type: int) -> bool:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count() or type < 0:
		return false
	
	var cache := _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	if cache[type].is_empty():
		return false
	
	var td = tm.get_cell_tile_data(layer, coord)
	if !td:
		return false
	
	var ts_meta := _get_terrain_meta(tm.tile_set)
	var categories = ts_meta.terrains[type][3]
	var check_types = [type] + categories
	
	for check_type in check_types:
		var placed_peering = tile_peering_for_type(td, check_type)
		for pt in get_tiles_in_terrain(tm.tile_set, type):
			var check_peering = tile_peering_for_type(pt, check_type)
			if placed_peering == check_peering:
				var tile = cache[type].front()
				tm.set_cell(layer, coord, tile[0], tile[1], tile[2])
				return true
	
	return false


## Replaces existing tiles on the [TileMap] for the [code]layer[/code]
## and [code]coords[/code] with new tiles in the provided terrain [code]type[/code] 
## *only if* there is a tile with a matching set of peering sides in this terrain
## for each tile.
## Returns [code]true[/code] if any tiles were changed.
func replace_cells(tm: TileMap, layer: int, coords: Array, type: int) -> bool:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count() or type < 0:
		return false
	
	var cache := _get_cache(tm.tile_set)
	if type >= cache.size():
		return false
	
	if cache[type].is_empty():
		return false
	
	var ts_meta := _get_terrain_meta(tm.tile_set)
	var categories = ts_meta.terrains[type][3]
	var check_types = [type] + categories
	
	var changed = false
	var potential_tiles = get_tiles_in_terrain(tm.tile_set, type)
	for c in coords:
		var found = false
		var td = tm.get_cell_tile_data(layer, c)
		if !td:
			continue
		for check_type in check_types:
			var placed_peering = tile_peering_for_type(td, check_type)
			for pt in potential_tiles:
				var check_peering = tile_peering_for_type(pt, check_type)
				if placed_peering == check_peering:
					var tile = cache[type].front()
					tm.set_cell(layer, c, tile[0], tile[1], tile[2])
					changed = true
					found = true
					break
			
			if found:
				break
	
	return changed


## Returns the terrain type detected in the [TileMap] at specified [code]layer[/code]
## and [code]coord[/code]. Returns -1 if tile is not valid or does not contain a
## tile associated with a terrain.
func get_cell(tm: TileMap, layer: int, coord: Vector2i) -> int:
	if !tm or !tm.tile_set or layer < 0 or layer >= tm.get_layers_count():
		return TileCategory.ERROR
	
	if tm.get_cell_source_id(layer, coord) == -1:
		return TileCategory.EMPTY
	
	var t = tm.get_cell_tile_data(layer, coord)
	if !t:
		return TileCategory.EMPTY
	
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
	var cache = _get_cache(tm.tile_set)
	for c in cells:
		_update_tile_immediate(tm, layer, c, ts_meta, types, cache)


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
	var cache = _get_cache(tm.tile_set)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var coord := Vector2i(x, y)
			_update_tile_immediate(tm, layer, coord, ts_meta, types, cache)
	for c in additional_cells:
		_update_tile_immediate(tm, layer, c, ts_meta, types, cache)


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
		placements[n] = _update_tile_deferred(tm, cells[n], ts_meta, types, _cache)
	
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
