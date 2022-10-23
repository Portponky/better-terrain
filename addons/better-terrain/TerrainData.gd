@tool
class_name BetterTerrainData

# Based on TileSet.CELL_NEIGHBOR_* but reduced to ints for brevity
const terrain_peering_square_sides := [0, 4, 8, 12]
const terrain_peering_square_corners := [3, 7, 11, 15]
const terrain_peering_square_sides_corners := [0, 3, 4, 7, 8, 11, 12, 15]
const terrain_peering_isometric_sides := [2, 6, 10, 14]
const terrain_peering_isometric_corners := [1, 5, 9, 13]
const terrain_peering_isometric_sides_corners := [1, 2, 5, 6, 9, 10, 13, 14]
const terrain_peering_horiztonal_sides := [0, 2, 6, 8, 10, 14]
const terrain_peering_horiztonal_corners := [3, 5, 7, 11, 13, 15]
const terrain_peering_horiztonal_sides_corners := [0, 2, 3, 5, 6, 7, 8, 10, 11, 13, 14, 15]
const terrain_peering_vertical_sides := [2, 4, 6, 10, 12, 14]
const terrain_peering_vertical_corners := [1, 3, 7, 9, 11, 15]
const terrain_peering_vertical_sides_corners := [1, 2, 3, 4, 6, 7, 9, 10, 11, 12, 14, 15]


static func get_terrain_peering_cells(ts: TileSet, type: int) -> Array:
	if !ts or type < 0 or type >= BetterTerrain.TerrainType.MAX or type == BetterTerrain.TerrainType.NON_MODIFYING:
		return []
	
	match [ts.tile_shape, type]:
		[TileSet.TILE_SHAPE_SQUARE, BetterTerrain.TerrainType.MATCH_SIDES]:
			return terrain_peering_square_sides
		[TileSet.TILE_SHAPE_SQUARE, BetterTerrain.TerrainType.MATCH_CORNERS]:
			return terrain_peering_square_corners
		[TileSet.TILE_SHAPE_SQUARE, BetterTerrain.TerrainType.MATCH_SIDES_AND_CORNERS]:
			return terrain_peering_square_sides_corners
		[TileSet.TILE_SHAPE_ISOMETRIC, BetterTerrain.TerrainType.MATCH_SIDES]:
			return terrain_peering_isometric_sides
		[TileSet.TILE_SHAPE_ISOMETRIC, BetterTerrain.TerrainType.MATCH_CORNERS]:
			return terrain_peering_isometric_corners
		[TileSet.TILE_SHAPE_ISOMETRIC, BetterTerrain.TerrainType.MATCH_SIDES_AND_CORNERS]:
			return terrain_peering_isometric_sides_corners
	
	match [ts.tile_offset_axis, type]:
		[TileSet.TILE_OFFSET_AXIS_VERTICAL, BetterTerrain.TerrainType.MATCH_SIDES]:
			return terrain_peering_vertical_sides
		[TileSet.TILE_OFFSET_AXIS_VERTICAL, BetterTerrain.TerrainType.MATCH_CORNERS]:
			return terrain_peering_vertical_corners
		[TileSet.TILE_OFFSET_AXIS_VERTICAL, BetterTerrain.TerrainType.MATCH_SIDES_AND_CORNERS]:
			return terrain_peering_vertical_sides_corners
		[TileSet.TILE_OFFSET_AXIS_HORIZONTAL, BetterTerrain.TerrainType.MATCH_SIDES]:
			return terrain_peering_horiztonal_sides
		[TileSet.TILE_OFFSET_AXIS_HORIZONTAL, BetterTerrain.TerrainType.MATCH_CORNERS]:
			return terrain_peering_horiztonal_corners
		[TileSet.TILE_OFFSET_AXIS_HORIZONTAL, BetterTerrain.TerrainType.MATCH_SIDES_AND_CORNERS]:
			return terrain_peering_horiztonal_sides_corners
	
	return []


static func is_terrain_peering_cell(ts: TileSet, type: int, peering: int) -> bool:
	return peering in get_terrain_peering_cells(ts, type)


static func peering_polygon_square_sides(peering: int) -> PackedVector2Array:
	const t = 1.0 / 3.0
	var result : PackedVector2Array
	match peering:
		TileSet.CELL_NEIGHBOR_RIGHT_SIDE:
			result.append(Vector2(1, 0))
			result.append(Vector2(1, 1))
			result.append(Vector2(2*t, 2*t))
			result.append(Vector2(2*t, t))
		TileSet.CELL_NEIGHBOR_BOTTOM_SIDE:
			result.append(Vector2(t, 2*t))
			result.append(Vector2(2*t, 2*t))
			result.append(Vector2(1, 1))
			result.append(Vector2(0, 1))
		TileSet.CELL_NEIGHBOR_LEFT_SIDE:
			result.append(Vector2(0, 0))
			result.append(Vector2(t, t))
			result.append(Vector2(t, 2*t))
			result.append(Vector2(0, 1))
		TileSet.CELL_NEIGHBOR_TOP_SIDE:
			result.append(Vector2(0, 0))
			result.append(Vector2(1, 0))
			result.append(Vector2(2*t, t))
			result.append(Vector2(t, t))
		-1:
			result.append(Vector2(t, t))
			result.append(Vector2(2*t, t))
			result.append(Vector2(2*t, 2*t))
			result.append(Vector2(t, 2*t))
		
	return result


static func peering_polygon_square_corners(peering: int) -> PackedVector2Array:
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


static func peering_polygon_square_sides_corners(peering: int) -> PackedVector2Array:
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


static func peering_polygon(ts: TileSet, type: int, peering: int) -> PackedVector2Array:
	if ts.tile_shape == TileSet.TILE_SHAPE_SQUARE:
		match type:
			BetterTerrain.TerrainType.MATCH_SIDES: return peering_polygon_square_sides(peering)
			BetterTerrain.TerrainType.MATCH_CORNERS: return peering_polygon_square_corners(peering)
			BetterTerrain.TerrainType.MATCH_SIDES_AND_CORNERS: return peering_polygon_square_sides_corners(peering)
	
	var result : PackedVector2Array
	return result


static func scale_polygon_to_rect(rect: Rect2i, polygon: PackedVector2Array) -> PackedVector2Array:
	for i in polygon.size():
		polygon[i].x = rect.position.x + rect.size.x * polygon[i].x
		polygon[i].y = rect.position.y + rect.size.x * polygon[i].y
	return polygon
