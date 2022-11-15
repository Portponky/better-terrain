@tool
extends Node

func create_tile_restore_point(undo_manager: EditorUndoRedoManager, tm: TileMap, layer: int, cells: Array, and_surrounding_cells: bool = true):
	if and_surrounding_cells:
		cells = BetterTerrain._widen(tm, cells)
	
	var restore = []
	for c in cells:
		restore.append([
			c,
			tm.get_cell_source_id(layer, c),
			tm.get_cell_atlas_coords(layer, c),
			tm.get_cell_alternative_tile(layer, c)
		])
	
	undo_manager.add_undo_method(self, &"restore_tiles", tm, layer, restore)


func create_tile_restore_point_area(undo_manager: EditorUndoRedoManager, tm: TileMap, layer: int, area: Rect2i, and_surrounding_cells: bool = true):
	area.end += Vector2i.ONE
	
	var restore = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c = Vector2i(x, y)
			restore.append([
				c,
				tm.get_cell_source_id(layer, c),
				tm.get_cell_atlas_coords(layer, c),
				tm.get_cell_alternative_tile(layer, c)
			])
	
	undo_manager.add_undo_method(self, &"restore_tiles", tm, layer, restore)
	
	if !and_surrounding_cells:
		return
	
	var edges = []
	for x in range(area.position.x, area.end.x):
		edges.append(Vector2i(x, area.position.y))
		edges.append(Vector2i(x, area.end.y))
	for y in range(area.position.y + 1, area.end.y - 1):
		edges.append(Vector2i(area.position.x, y))
		edges.append(Vector2i(area.end.x, y))
	
	edges = BetterTerrain._widen_with_exclusion(tm, edges, area)
	create_tile_restore_point(undo_manager, tm, layer, edges, false)


func restore_tiles(tm: TileMap, layer: int, restore: Array):
	for r in restore:
		tm.set_cell(layer, r[0], r[1], r[2], r[3])
