@tool
class_name BetterTerrainData

# Based on TileSet.CELL_NEIGHBOR_* but reduced to ints for brevity
const terrain_peering_square_tiles := [0, 3, 4, 7, 8, 11, 12, 15]
const terrain_peering_square_vertices := [3, 7, 11, 15]
const terrain_peering_isometric_tiles := [1, 2, 5, 6, 9, 10, 13, 14]
const terrain_peering_isometric_vertices := [1, 5, 9, 13]
const terrain_peering_horiztonal_tiles := [0, 2, 3, 5, 6, 7, 8, 10, 11, 13, 14, 15]
const terrain_peering_horiztonal_vertices := [3, 5, 7, 11, 13, 15]
const terrain_peering_vertical_tiles := [1, 2, 3, 4, 6, 7, 9, 10, 11, 12, 14, 15]
const terrain_peering_vertical_vertices := [1, 3, 7, 9, 11, 15]


static func get_terrain_peering_cells(ts: TileSet, type: int) -> Array:
	if !ts or type < 0 or type >= BetterTerrain.TerrainType.MAX or type == BetterTerrain.TerrainType.NON_MODIFYING:
		return []
	
	match [ts.tile_shape, type]:
		[TileSet.TILE_SHAPE_SQUARE, BetterTerrain.TerrainType.MATCH_TILES]:
			return terrain_peering_square_tiles
		[TileSet.TILE_SHAPE_SQUARE, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return terrain_peering_square_vertices
		[TileSet.TILE_SHAPE_ISOMETRIC, BetterTerrain.TerrainType.MATCH_TILES]:
			return terrain_peering_isometric_tiles
		[TileSet.TILE_SHAPE_ISOMETRIC, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return terrain_peering_isometric_vertices
	
	match [ts.tile_offset_axis, type]:
		[TileSet.TILE_OFFSET_AXIS_VERTICAL, BetterTerrain.TerrainType.MATCH_TILES]:
			return terrain_peering_vertical_tiles
		[TileSet.TILE_OFFSET_AXIS_VERTICAL, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return terrain_peering_vertical_vertices
		[TileSet.TILE_OFFSET_AXIS_HORIZONTAL, BetterTerrain.TerrainType.MATCH_TILES]:
			return terrain_peering_horiztonal_tiles
		[TileSet.TILE_OFFSET_AXIS_HORIZONTAL, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return terrain_peering_horiztonal_vertices
	
	return []


static func is_terrain_peering_cell(ts: TileSet, type: int, peering: int) -> bool:
	return peering in get_terrain_peering_cells(ts, type)


static func peering_polygon_square_tiles(peering: int) -> PackedVector2Array:
	const t = 1.0 / 3.0
	var result : PackedVector2Array
	match peering:
		TileSet.CELL_NEIGHBOR_RIGHT_SIDE: result.append(Vector2(2*t, t))
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER: result.append(Vector2(2*t, 2*t))
		TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: result.append(Vector2(t, 2*t))
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER: result.append(Vector2(0, 2*t))
		TileSet.CELL_NEIGHBOR_LEFT_SIDE: result.append(Vector2(0, t))
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER: result.append(Vector2(0, 0))
		TileSet.CELL_NEIGHBOR_TOP_SIDE: result.append(Vector2(t, 0))
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER: result.append(Vector2(2*t, 0))
		-1: result.append(Vector2(t, t))
	result.append(result[0] + Vector2(t, 0))
	result.append(result[0] + Vector2(t, t))
	result.append(result[0] + Vector2(0, t))
	return result


static func peering_polygon_square_vertices(peering: int) -> PackedVector2Array:
	const t = 1.0 / 2.0
	var result : PackedVector2Array
	match peering:
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER:
			result.append(Vector2(1, t))
			result.append(Vector2(1, 1))
			result.append(Vector2(t, 1))
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER:
			result.append(Vector2(0, t))
			result.append(Vector2(t, 1))
			result.append(Vector2(0, 1))
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER:
			result.append(Vector2(0, 0))
			result.append(Vector2(t, 0))
			result.append(Vector2(0, t))
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER:
			result.append(Vector2(t, 0))
			result.append(Vector2(1, 0))
			result.append(Vector2(1, t))
		-1:
			result.append(Vector2(t, 0))
			result.append(Vector2(1, t))
			result.append(Vector2(t, 1))
			result.append(Vector2(0, t))
	return result


static func peering_polygon(ts: TileSet, type: int, peering: int) -> PackedVector2Array:
	if ts.tile_shape == TileSet.TILE_SHAPE_SQUARE:
		match type:
			BetterTerrain.TerrainType.MATCH_TILES: return peering_polygon_square_tiles(peering)
			BetterTerrain.TerrainType.MATCH_VERTICES: return peering_polygon_square_vertices(peering)
	
	var result : PackedVector2Array
	return result


static func scale_polygon_to_rect(rect: Rect2i, polygon: PackedVector2Array) -> PackedVector2Array:
	for i in polygon.size():
		polygon[i].x = rect.position.x + rect.size.x * polygon[i].x
		polygon[i].y = rect.position.y + rect.size.x * polygon[i].y
	return polygon
