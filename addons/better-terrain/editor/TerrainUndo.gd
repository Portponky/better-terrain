@tool
extends Node

func create_tile_restore_point(undo_manager: EditorUndoRedoManager, tm: TileMap, layer: int, cells: Array, and_surrounding_cells: bool = true) -> void:
	if and_surrounding_cells:
		cells = BetterTerrain._widen(tm, cells)
	
	var restore := []
	for c in cells:
		restore.append([
			c,
			tm.get_cell_source_id(layer, c),
			tm.get_cell_atlas_coords(layer, c),
			tm.get_cell_alternative_tile(layer, c)
		])
	
	undo_manager.add_undo_method(self, &"restore_tiles", tm, layer, restore)


func create_tile_restore_point_area(undo_manager: EditorUndoRedoManager, tm: TileMap, layer: int, area: Rect2i, and_surrounding_cells: bool = true) -> void:
	area.end += Vector2i.ONE
	
	var restore := []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			restore.append([
				c,
				tm.get_cell_source_id(layer, c),
				tm.get_cell_atlas_coords(layer, c),
				tm.get_cell_alternative_tile(layer, c)
			])
	
	undo_manager.add_undo_method(self, &"restore_tiles", tm, layer, restore)
	
	if !and_surrounding_cells:
		return
	
	var edges := []
	for x in range(area.position.x, area.end.x):
		edges.append(Vector2i(x, area.position.y))
		edges.append(Vector2i(x, area.end.y))
	for y in range(area.position.y + 1, area.end.y - 1):
		edges.append(Vector2i(area.position.x, y))
		edges.append(Vector2i(area.end.x, y))
	
	edges = BetterTerrain._widen_with_exclusion(tm, edges, area)
	create_tile_restore_point(undo_manager, tm, layer, edges, false)


func restore_tiles(tm: TileMap, layer: int, restore: Array) -> void:
	for r in restore:
		tm.set_cell(layer, r[0], r[1], r[2], r[3])


func create_peering_restore_point(undo_manager: EditorUndoRedoManager, ts: TileSet) -> void:
	var restore := []
	
	for s in ts.get_source_count():
		var source_id := ts.get_source_id(s)
		var source := ts.get_source(source_id) as TileSetAtlasSource
		if !source:
			continue
		
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			for a in source.get_alternative_tiles_count(coord):
				var alternate := source.get_alternative_tile_id(coord, a)
				
				var td := source.get_tile_data(coord, alternate)
				var tile_type := BetterTerrain.get_tile_terrain_type(td)
				if tile_type == -1:
					continue
				
				var peering_dict := {}
				for c in BetterTerrain.tile_peering_keys(td):
					peering_dict[c] = BetterTerrain.tile_peering_types(td, c)
				restore.append([source_id, coord, alternate, tile_type, peering_dict])
	
	undo_manager.add_undo_method(self, &"restore_peering", ts, restore)


func create_peering_restore_point_specific(undo_manager: EditorUndoRedoManager, ts: TileSet, protect: int) -> void:
	var restore := []
	
	for s in ts.get_source_count():
		var source_id := ts.get_source_id(s)
		var source := ts.get_source(source_id) as TileSetAtlasSource
		if !source:
			continue
		
		for t in source.get_tiles_count():
			var coord := source.get_tile_id(t)
			for a in source.get_alternative_tiles_count(coord):
				var alternate := source.get_alternative_tile_id(coord, a)
				
				var td := source.get_tile_data(coord, alternate)
				var tile_type := BetterTerrain.get_tile_terrain_type(td)
				if tile_type == -1:
					continue
				
				var to_restore : bool = tile_type == protect
				
				var terrain := BetterTerrain.get_terrain(ts, tile_type)
				var cells = BetterTerrain.data.get_terrain_peering_cells(ts, terrain.type)
				for c in cells:
					if protect in BetterTerrain.tile_peering_types(td, c):
						to_restore = true
						break
				
				if !to_restore:
					continue
				
				var peering_dict := {}
				for c in cells:
					peering_dict[c] = BetterTerrain.tile_peering_types(td, c)
				restore.append([source_id, coord, alternate, tile_type, peering_dict])
	
	undo_manager.add_undo_method(self, &"restore_peering", ts, restore)


func create_peering_restore_point_tile(undo_manager: EditorUndoRedoManager, ts: TileSet, source_id: int, coord: Vector2i, alternate: int) -> void:
	var source := ts.get_source(source_id) as TileSetAtlasSource
	var td := source.get_tile_data(coord, alternate)
	var tile_type := BetterTerrain.get_tile_terrain_type(td)
	
	var restore := []
	var peering_dict := {}
	for c in BetterTerrain.tile_peering_keys(td):
		peering_dict[c] = BetterTerrain.tile_peering_types(td, c)
	restore.append([source_id, coord, alternate, tile_type, peering_dict])
	
	undo_manager.add_undo_method(self, &"restore_peering", ts, restore)


func restore_peering(ts: TileSet, restore: Array) -> void:
	for r in restore:
		var source := ts.get_source(r[0]) as TileSetAtlasSource
		var td := source.get_tile_data(r[1], r[2])
		BetterTerrain.set_tile_terrain_type(ts, td, r[3])
		var peering_types = r[4]
		for peering in peering_types:
			var types := BetterTerrain.tile_peering_types(td, peering)
			for t in types:
				BetterTerrain.remove_tile_peering_type(ts, td, peering, t)
			for t in peering_types[peering]:
				BetterTerrain.add_tile_peering_type(ts, td, peering, t)


func create_terran_type_restore_point(undo_manager: EditorUndoRedoManager, ts: TileSet) -> void:
	var count = BetterTerrain.terrain_count(ts)
	var restore = []
	for i in count:
		restore.push_back(BetterTerrain.get_terrain(ts, i))
	
	undo_manager.add_undo_method(self, &"restore_terrain", ts, restore)


func restore_terrain(ts: TileSet, restore: Array) -> void:
	for i in restore.size():
		var r = restore[i]
		BetterTerrain.set_terrain(ts, i, r.name, r.color, r.type, r.categories)
