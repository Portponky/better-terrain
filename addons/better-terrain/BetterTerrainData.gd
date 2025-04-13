@tool

## Data functions for [TileSet] properties.
##
## This data class has functions for retrieving data regarding the mathematical
## properties of a tile set.

const _terrain_peering_square_tiles : Array[int] = [0, 3, 4, 7, 8, 11, 12, 15]
const _terrain_peering_square_vertices : Array[int] = [3, 7, 11, 15]
const _terrain_peering_isometric_tiles : Array[int] = [1, 2, 5, 6, 9, 10, 13, 14]
const _terrain_peering_isometric_vertices : Array[int] = [1, 5, 9, 13]
const _terrain_peering_horiztonal_tiles : Array[int] = [0, 2, 6, 8, 10, 14]
const _terrain_peering_horiztonal_vertices : Array[int] = [3, 5, 7, 11, 13, 15]
const _terrain_peering_vertical_tiles : Array[int] = [2, 4, 6, 10, 12, 14]
const _terrain_peering_vertical_vertices : Array[int] = [1, 3, 7, 9, 11, 15]
const _terrain_peering_non_modifying : Array[int] = []

const _terrain_peering_hflip : Array[int] = [8, 9, 6, 7, 4, 5, 2, 3, 0, 1, 14, 15, 12, 13, 10, 11]
const _terrain_peering_vflip : Array[int] = [0, 1, 14, 15, 12, 13, 10, 11, 8, 9, 6, 7, 4, 5, 2, 3]
const _terrain_peering_transpose : Array[int] = [4, 5, 2, 3, 0, 1, 14, 15, 12, 13, 10, 11, 8, 9, 6, 7]

const symmetry_mapping := {
	BetterTerrain.SymmetryType.NONE: [0],
	BetterTerrain.SymmetryType.MIRROR: [0, TileSetAtlasSource.TRANSFORM_FLIP_H],
	BetterTerrain.SymmetryType.FLIP: [0, TileSetAtlasSource.TRANSFORM_FLIP_V],
	BetterTerrain.SymmetryType.REFLECT: [
		0,
		TileSetAtlasSource.TRANSFORM_FLIP_H,
		TileSetAtlasSource.TRANSFORM_FLIP_V,
		TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V
	],
	BetterTerrain.SymmetryType.ROTATE_CLOCKWISE: [0, TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_TRANSPOSE],
	BetterTerrain.SymmetryType.ROTATE_COUNTER_CLOCKWISE: [0, TileSetAtlasSource.TRANSFORM_FLIP_V | TileSetAtlasSource.TRANSFORM_TRANSPOSE],
	BetterTerrain.SymmetryType.ROTATE_180: [0, TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V],
	BetterTerrain.SymmetryType.ROTATE_ALL: [
		0,
		TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_TRANSPOSE,
		TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V,
		TileSetAtlasSource.TRANSFORM_FLIP_V | TileSetAtlasSource.TRANSFORM_TRANSPOSE
	],
	BetterTerrain.SymmetryType.ALL: [
		0,
		TileSetAtlasSource.TRANSFORM_FLIP_H,
		TileSetAtlasSource.TRANSFORM_FLIP_V,
		TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V,
		TileSetAtlasSource.TRANSFORM_TRANSPOSE,
		TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_TRANSPOSE,
		TileSetAtlasSource.TRANSFORM_FLIP_V | TileSetAtlasSource.TRANSFORM_TRANSPOSE,
		TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V | TileSetAtlasSource.TRANSFORM_TRANSPOSE
	]
}


## Returns an [Array] of ints of type [enum TileSet.CellNeighbor] which represent
## the valid neighboring tiles for a terrain of [code]type[/code] in TileSet
static func get_terrain_peering_cells(ts: TileSet, type: int) -> Array[int]:
	if !ts or type < 0 or type >= BetterTerrain.TerrainType.MAX:
		return []
	
	if type == BetterTerrain.TerrainType.CATEGORY:
		return _terrain_peering_non_modifying
	if type == BetterTerrain.TerrainType.DECORATION:
		type = BetterTerrain.TerrainType.MATCH_TILES
	
	match [ts.tile_shape, type]:
		[TileSet.TILE_SHAPE_SQUARE, BetterTerrain.TerrainType.MATCH_TILES]:
			return _terrain_peering_square_tiles
		[TileSet.TILE_SHAPE_SQUARE, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return _terrain_peering_square_vertices
		[TileSet.TILE_SHAPE_ISOMETRIC, BetterTerrain.TerrainType.MATCH_TILES]:
			return _terrain_peering_isometric_tiles
		[TileSet.TILE_SHAPE_ISOMETRIC, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return _terrain_peering_isometric_vertices
	
	match [ts.tile_offset_axis, type]:
		[TileSet.TILE_OFFSET_AXIS_VERTICAL, BetterTerrain.TerrainType.MATCH_TILES]:
			return _terrain_peering_vertical_tiles
		[TileSet.TILE_OFFSET_AXIS_VERTICAL, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return _terrain_peering_vertical_vertices
		[TileSet.TILE_OFFSET_AXIS_HORIZONTAL, BetterTerrain.TerrainType.MATCH_TILES]:
			return _terrain_peering_horiztonal_tiles
		[TileSet.TILE_OFFSET_AXIS_HORIZONTAL, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return _terrain_peering_horiztonal_vertices
	
	return []


## Returns true if [code]peering[/code] is a valid neighboring cell for a terrain of
## [code]type[/code] in [TileSet]
static func is_terrain_peering_cell(ts: TileSet, type: int, peering: int) -> bool:
	return peering in get_terrain_peering_cells(ts, type)


static func _peering_polygon_square_tiles(peering: int) -> PackedVector2Array:
	const t := 1.0 / 3.0
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


static func _peering_polygon_square_vertices(peering: int) -> PackedVector2Array:
	const t := 1.0 / 2.0
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


static func _peering_polygon_isometric_tiles(peering: int) -> PackedVector2Array:
	const t := 1.0 / 4.0
	match peering:
		-1: return PackedVector2Array([Vector2(2 * t, t), Vector2(3 * t, 2 * t), Vector2(2 * t, 3 * t), Vector2(t, 2 * t)])
		TileSet.CELL_NEIGHBOR_RIGHT_CORNER:
			return PackedVector2Array([Vector2(3 * t, 2 * t), Vector2(1, t), Vector2(1, 3 * t)])
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE:
			return PackedVector2Array([Vector2(3 * t, 2 * t), Vector2(1, 3 * t), Vector2(3 * t, 1), Vector2(2 * t, 3 * t)])
		TileSet.CELL_NEIGHBOR_BOTTOM_CORNER:
			return PackedVector2Array([Vector2(2 * t, 3 * t), Vector2(3 * t, 1), Vector2(t, 1)])
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE:
			return PackedVector2Array([Vector2(t, 2 * t), Vector2(2 * t, 3 * t), Vector2(t, 1), Vector2(0, 3 * t)])
		TileSet.CELL_NEIGHBOR_LEFT_CORNER:
			return PackedVector2Array([Vector2(0, t), Vector2(t, 2 * t), Vector2(0, 3 * t)])
		TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE:
			return PackedVector2Array([Vector2(t, 0), Vector2(2 * t, t), Vector2(t, 2 * t), Vector2(0, t)])
		TileSet.CELL_NEIGHBOR_TOP_CORNER:
			return PackedVector2Array([Vector2(t, 0), Vector2(3 * t, 0), Vector2(2 * t, t)])
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE:
			return PackedVector2Array([Vector2(3 * t, 0), Vector2(1, t), Vector2(3 * t, 2 * t), Vector2(2 * t, t)])
	return PackedVector2Array()


static func _peering_polygon_isometric_vertices(peering: int) -> PackedVector2Array:
	const t := 1.0 / 4.0
	const ttt := 3.0 * t
	match peering:
		-1: return PackedVector2Array([Vector2(t, t), Vector2(ttt, t), Vector2(ttt, ttt), Vector2(t, ttt)])
		TileSet.CELL_NEIGHBOR_RIGHT_CORNER:
			return PackedVector2Array([Vector2(ttt, t), Vector2(1, 0), Vector2(1, 1), Vector2(ttt, ttt)])
		TileSet.CELL_NEIGHBOR_BOTTOM_CORNER:
			return PackedVector2Array([Vector2(t, ttt), Vector2(ttt, ttt), Vector2(1, 1), Vector2(0, 1)])
		TileSet.CELL_NEIGHBOR_LEFT_CORNER:
			return PackedVector2Array([Vector2(0, 0), Vector2(t, t), Vector2(t, ttt), Vector2(0, 1)])
		TileSet.CELL_NEIGHBOR_TOP_CORNER:
			return PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(ttt, t), Vector2(t, t)])
	return PackedVector2Array()


static func _peering_polygon_horizontal_tiles(peering: int) -> PackedVector2Array:
	const e := 1.0 / (2.0 * sqrt(3.0))
	const w := sqrt(3.0) / 8.0
	const t := 1.0 / 2.0
	const s := 1.0 / 8.0
	match peering:
		-1:
			return PackedVector2Array([
				Vector2(t, 2 * s),
				Vector2(t + w, t - s),
				Vector2(t + w, t + s),
				Vector2(t, 6 * s),
				Vector2(t - w, t + s),
				Vector2(t - w, t - s)
			])
		TileSet.CELL_NEIGHBOR_RIGHT_SIDE:
			return PackedVector2Array([
				Vector2(t + w, t - s),
				Vector2(1, t - e),
				Vector2(1, t + e),
				Vector2(t + w, t + s)
			])
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE:
			return PackedVector2Array([
				Vector2(t + w, t + s),
				Vector2(1, t + e),
				Vector2(t, 1),
				Vector2(t, 6 * s)
			])
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE:
			return PackedVector2Array([
				Vector2(t, 6 * s),
				Vector2(t, 1),
				Vector2(0, t + e),
				Vector2(t - w, t + s)
			])
		TileSet.CELL_NEIGHBOR_LEFT_SIDE:
			return PackedVector2Array([
				Vector2(t - w, t + s),
				Vector2(0, t + e),
				Vector2(0, t - e),
				Vector2(t - w, t - s)
			])
		TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE:
			return PackedVector2Array([
				Vector2(t - w, t - s),
				Vector2(0, t - e),
				Vector2(t, 0),
				Vector2(t, 2 * s)
			])
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE:
			return PackedVector2Array([
				Vector2(t, 2 * s),
				Vector2(t, 0),
				Vector2(1, t - e),
				Vector2(t + w, t - s)
			])
	return PackedVector2Array()


static func _peering_polygon_horizontal_vertices(peering: int) -> PackedVector2Array:
	const e := 1.0 / (2.0 * sqrt(3.0))
	const w := sqrt(3.0) / 8.0
	const t := 1.0 / 2.0
	const s := 1.0 / 8.0
	match peering:
		-1:
			return PackedVector2Array([
				Vector2(t - s, t - w),
				Vector2(t + s, t - w),
				Vector2(6 * s, t),
				Vector2(t + s, t + w),
				Vector2(t - s, t + w),
				Vector2(2 * s, t)
			])
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER:
			return PackedVector2Array([
				Vector2(6 * s, t),
				Vector2(1, t),
				Vector2(1, t + e),
				Vector2(t + e, 1 - s),
				Vector2(t + s, t +  w)
			])
		TileSet.CELL_NEIGHBOR_BOTTOM_CORNER:
			return PackedVector2Array([
				Vector2(t - s, t + w),
				Vector2(t + s, t + w),
				Vector2(t + e, 1 - s),
				Vector2(t, 1),
				Vector2(t - e, 1 - s)
			])
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER:
			return PackedVector2Array([
				Vector2(0, t),
				Vector2(2 * s, t),
				Vector2(t - s, t +  w),
				Vector2(t - e, 1 - s),
				Vector2(0, t + e)
			])
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER:
			return PackedVector2Array([
				Vector2(t - e, s),
				Vector2(t - s, t - w),
				Vector2(2 * s, t),
				Vector2(0, t),
				Vector2(0, t - e)
			])
		TileSet.CELL_NEIGHBOR_TOP_CORNER:
			return PackedVector2Array([
				Vector2(t, 0),
				Vector2(t + e, s),
				Vector2(t + s, t - w),
				Vector2(t - s, t - w),
				Vector2(t - e, s)
			])
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER:
			return PackedVector2Array([
				Vector2(t + e, s),
				Vector2(1, t - e),
				Vector2(1, t),
				Vector2(6 * s, t),
				Vector2(t + s, t - w)
			])
	return PackedVector2Array()


static func _peering_polygon_vertical_tiles(peering: int) -> PackedVector2Array:
	const e := 1.0 / (2.0 * sqrt(3.0))
	const w := sqrt(3.0) / 8.0
	const t := 1.0 / 2.0
	const s := 1.0 / 8.0
	match peering:
		-1:
			return PackedVector2Array([
				Vector2(t - s, t - w),
				Vector2(t + s, t - w),
				Vector2(6 * s, t),
				Vector2(t + s, t + w),
				Vector2(t - s, t + w),
				Vector2(2 * s, t)
			])
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE:
			return PackedVector2Array([
				Vector2(6 * s, t),
				Vector2(1, t),
				Vector2(t + e, 1),
				Vector2(t + s, t + w)
			])
		TileSet.CELL_NEIGHBOR_BOTTOM_SIDE:
			return PackedVector2Array([
				Vector2(t - s, t + w),
				Vector2(t + s, t + w),
				Vector2(t + e, 1),
				Vector2(t - e, 1)
			])
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE:
			return PackedVector2Array([
				Vector2(0, t),
				Vector2(2 * s, t),
				Vector2(t - s, t + w),
				Vector2(t - e, 1)
			])
		TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE:
			return PackedVector2Array([
				Vector2(t - e, 0),
				Vector2(t - s, t - w),
				Vector2(2 * s, t),
				Vector2(0, t)
			])
		TileSet.CELL_NEIGHBOR_TOP_SIDE:
			return PackedVector2Array([
				Vector2(t - e, 0),
				Vector2(t + e, 0),
				Vector2(t + s, t - w),
				Vector2(t - s, t - w)
			])
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE:
			return PackedVector2Array([
				Vector2(t + e, 0),
				Vector2(1, t),
				Vector2(6 * s, t),
				Vector2(t + s, t - w)
			])
	return PackedVector2Array()


static func _peering_polygon_vertical_vertices(peering: int) -> PackedVector2Array:
	const e := 1.0 / (2.0 * sqrt(3.0))
	const w := sqrt(3.0) / 8.0
	const t := 1.0 / 2.0
	const s := 1.0 / 8.0
	match peering:
		-1:
			return PackedVector2Array([
				Vector2(t, 2 * s),
				Vector2(t + w, t - s),
				Vector2(t + w, t + s),
				Vector2(t, 6 * s),
				Vector2(t - w, t + s),
				Vector2(t - w, t - s)
			])
		TileSet.CELL_NEIGHBOR_RIGHT_CORNER:
			return PackedVector2Array([
				Vector2(1 - s, t - e),
				Vector2(1, t),
				Vector2(1 - s, t + e),
				Vector2(t + w, t + s),
				Vector2(t + w, t - s)
			])
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER:			
			return PackedVector2Array([
				Vector2(t + w, t + s),
				Vector2(1 - s, t + e),
				Vector2(t + e, 1),
				Vector2(t, 1),
				Vector2(t, 6 * s)
			])
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER:
			return PackedVector2Array([
				Vector2(t - w, t + s),
				Vector2(t, 6 * s),
				Vector2(t, 1),
				Vector2(t - e, 1),
				Vector2(s, t + e)
			])
		TileSet.CELL_NEIGHBOR_LEFT_CORNER:
			return PackedVector2Array([
				Vector2(s, t - e),
				Vector2(t - w, t - s),
				Vector2(t - w, t + s),
				Vector2(s, t + e),
				Vector2(0, t)
			])
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER:
			return PackedVector2Array([
				Vector2(t - e, 0),
				Vector2(t, 0),
				Vector2(t, 2 * s),
				Vector2(t - w, t - s),
				Vector2(s, t - e)
			])
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER:
			return PackedVector2Array([
				Vector2(t, 0),
				Vector2(t + e, 0),
				Vector2(1 - s, t - e),
				Vector2(t + w, t - s),
				Vector2(t, 2 * s)
			])
	return PackedVector2Array()


static func _peering_non_modifying() -> PackedVector2Array:
	const t := 1.0 / 3.0
	return PackedVector2Array([
		Vector2(t, 0),
		Vector2(2 * t, 0),
		Vector2(1, t),
		Vector2(1, 2 * t),
		Vector2(2 * t, 1),
		Vector2(t, 1),
		Vector2(0, 2 * t),
		Vector2(0, t)
	])


## Returns a parameterized polygon (coordinated are between 0 and 1) for [code]peering[/code]
## direction for a terrain of [code]type[/code] in [TileSet]
static func peering_polygon(ts: TileSet, type: int, peering: int) -> PackedVector2Array:
	if type == BetterTerrain.TerrainType.CATEGORY:
		return _peering_non_modifying()
	if type == BetterTerrain.TerrainType.DECORATION:
		type = BetterTerrain.TerrainType.MATCH_TILES
	
	match [ts.tile_shape, type]:
		[TileSet.TILE_SHAPE_SQUARE, BetterTerrain.TerrainType.MATCH_TILES]:
			return _peering_polygon_square_tiles(peering)
		[TileSet.TILE_SHAPE_SQUARE, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return _peering_polygon_square_vertices(peering)
		[TileSet.TILE_SHAPE_ISOMETRIC, BetterTerrain.TerrainType.MATCH_TILES]:
			return _peering_polygon_isometric_tiles(peering)
		[TileSet.TILE_SHAPE_ISOMETRIC, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return _peering_polygon_isometric_vertices(peering)
	
	match [ts.tile_offset_axis, type]:
		[TileSet.TILE_OFFSET_AXIS_VERTICAL, BetterTerrain.TerrainType.MATCH_TILES]:
			return _peering_polygon_vertical_tiles(peering)
		[TileSet.TILE_OFFSET_AXIS_VERTICAL, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return _peering_polygon_vertical_vertices(peering)
		[TileSet.TILE_OFFSET_AXIS_HORIZONTAL, BetterTerrain.TerrainType.MATCH_TILES]:
			return _peering_polygon_horizontal_tiles(peering)
		[TileSet.TILE_OFFSET_AXIS_HORIZONTAL, BetterTerrain.TerrainType.MATCH_VERTICES]:
			return _peering_polygon_horizontal_vertices(peering)
	
	return PackedVector2Array()


## Returns as polygon centered on 0, 0 which represents the shape of the cell of
## a tile from [TileSet].
static func cell_polygon(ts: TileSet) -> PackedVector2Array:
	const t := 1.0 / 2.0
	if ts.tile_shape in [TileSet.TILE_SHAPE_SQUARE, TileSet.TILE_SHAPE_HALF_OFFSET_SQUARE]:
		return PackedVector2Array([Vector2(-t, -t), Vector2(t, -t), Vector2(t, t), Vector2(-t, t)])
	if ts.tile_shape == TileSet.TILE_SHAPE_ISOMETRIC:
		return PackedVector2Array([Vector2(0, -t), Vector2(t, 0), Vector2(0, t), Vector2(-t, 0)])
	
	const e := t - 1.0 / (2.0 * sqrt(3.0))
	if ts.tile_offset_axis == TileSet.TILE_OFFSET_AXIS_HORIZONTAL:
		return PackedVector2Array([
			Vector2(0, -t),
			Vector2(t, -e),
			Vector2(t, e),
			Vector2(0, t),
			Vector2(-t, e),
			Vector2(-t, -e),
		])
	
	return PackedVector2Array([
		Vector2(-t, 0),
		Vector2(-e, -t),
		Vector2(e, -t),
		Vector2(t, 0),
		Vector2(e, t),
		Vector2(-e, t),
	])


## Returns an [Array] of coordinated that neighbor [code]coord[/code] based on [code]peering[/code]
## [Array] of [enum TileSet.CellNeighbor] for a [TileSet].
static func neighboring_coords(tm: TileMapLayer, coord: Vector2i, peerings: Array) -> Array:
	return peerings.map(func(p): return tm.get_neighbor_cell(coord, p))


## Returns an [Array] of coordinates which neighbor the vertex describe by [code]corner[/code]
## (which is of type [enum TileSet.CellNeighbor]) from [code]coord[/code] in [TileSet].
static func associated_vertex_cells(tm: TileMapLayer, coord: Vector2i, corner: int) -> Array:
	# get array of associated peering bits
	if tm.tile_set.tile_shape in [TileSet.TILE_SHAPE_SQUARE, TileSet.TILE_SHAPE_ISOMETRIC]:
		match corner:
			# Square
			TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER:
				return neighboring_coords(tm, coord, [0, 3, 4])
			TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER:
				return neighboring_coords(tm, coord, [4, 7, 8])
			TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER:
				return neighboring_coords(tm, coord, [8, 11, 12])
			TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER:
				return neighboring_coords(tm, coord, [12, 15, 0])
			# Isometric
			TileSet.CELL_NEIGHBOR_RIGHT_CORNER:
				return neighboring_coords(tm, coord, [14, 1, 2])
			TileSet.CELL_NEIGHBOR_BOTTOM_CORNER:
				return neighboring_coords(tm, coord, [2, 5, 6])
			TileSet.CELL_NEIGHBOR_LEFT_CORNER:
				return neighboring_coords(tm, coord, [6, 9, 10])
			TileSet.CELL_NEIGHBOR_TOP_CORNER:
				return neighboring_coords(tm, coord, [10, 13, 14])
	
	if tm.tile_set.tile_offset_axis == TileSet.TILE_OFFSET_AXIS_HORIZONTAL:
		match corner:
			TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER:
				return neighboring_coords(tm, coord, [0, 2])
			TileSet.CELL_NEIGHBOR_BOTTOM_CORNER:
				return neighboring_coords(tm, coord, [2, 6])
			TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER:
				return neighboring_coords(tm, coord, [6, 8])
			TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER:
				return neighboring_coords(tm, coord, [8, 10])
			TileSet.CELL_NEIGHBOR_TOP_CORNER:
				return neighboring_coords(tm, coord, [10, 14])
			TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER:
				return neighboring_coords(tm, coord, [14, 0])
	
	# TileSet.TILE_OFFSET_AXIS_VERTICAL
	match corner:
		TileSet.CELL_NEIGHBOR_RIGHT_CORNER:
			return neighboring_coords(tm, coord, [14, 2])
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER:
			return neighboring_coords(tm, coord, [2, 4])
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER:
			return neighboring_coords(tm, coord, [4, 6])
		TileSet.CELL_NEIGHBOR_LEFT_CORNER:
			return neighboring_coords(tm, coord, [6, 10])
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER:
			return neighboring_coords(tm, coord, [10, 12])
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER:
			return neighboring_coords(tm, coord, [12, 14])
	
	return []


## Returns an [Array] of [enum TileSet.CellNeighbor] suitable for flood filling
## an area in [TileSet].
static func cells_adjacent_for_fill(ts: TileSet) -> Array[int]:
	if ts.tile_shape == TileSet.TILE_SHAPE_SQUARE:
		return [0, 4, 8, 12]
	if ts.tile_shape == TileSet.TILE_SHAPE_ISOMETRIC:
		return [2, 6, 10, 14]
	if ts.tile_offset_axis == TileSet.TILE_OFFSET_AXIS_HORIZONTAL:
		return _terrain_peering_horiztonal_tiles
	return _terrain_peering_vertical_tiles


static func peering_bit_after_symmetry(bit: int, altflags: int) -> int:
	if altflags & TileSetAtlasSource.TRANSFORM_TRANSPOSE:
		bit = _terrain_peering_transpose[bit]
	if altflags & TileSetAtlasSource.TRANSFORM_FLIP_H:
		bit = _terrain_peering_hflip[bit]
	if altflags & TileSetAtlasSource.TRANSFORM_FLIP_V:
		bit = _terrain_peering_vflip[bit]
	return bit


static func peering_bits_after_symmetry(dict: Dictionary, altflags: int) -> Dictionary:
	# rearrange dictionary keys based on altflags
	var result := {}
	for k in dict:
		result[peering_bit_after_symmetry(k, altflags)] = dict[k]
	return result
