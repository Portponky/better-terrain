using Godot;
using Godot.Collections;
using System;

/*

This is a lightweight wrapper for Better Terrain in C#.

It is not a C# implementation, it merely provides a type safe interface to access
the BetterTerrain autoload from C#. If you are not using Godot in C#, you can ignore
this file.

The interface is created for a specific tilemap node, which it uses to locate the
autoload, and to fill in as a parameter to simplify all the subsequent calls.
Very simple example:

```
	BetterTerrain bt;
	
	public override void _Ready()
	{
		TileMap tm = GetNode<TileMap>("TileMap");
		bt = new BetterTerrain(tm);
		
		var layer = 0;
		var coord = new Vector2I(0, 0);
		bt.SetCell(layer, coord, 1);
		bt.UpdateTerrainCell(layer, coord);
	}
```

The functions available are the same as BetterTerrain's, though the TileMap or
TileSet parameters are automatically filled in. The help is not duplicated here,
refer to the GDScript version for specifics.

*/

public class BetterTerrain
{
	Node bt;
	TileMap tm;
	
	public enum TerrainType {
		MatchTiles = 0,
		MatchVertices = 1,
		Category = 2,
		Decoration = 3
	}
	
	public enum SymmetryType {
		None = 0,
		Mirror = 1, // Horizontally mirror
		Flip = 2, // Vertically flip
		Reflect = 3, // All four reflections
		RotateClockwise = 4,
		RotateCounterClockwise = 5,
		Rotate180 = 6,
		RotateAll = 7, // All four rotated forms
		All = 8 // All rotated and reflected forms
	}
	
	public BetterTerrain(TileMap _tm)
	{
		tm = _tm;
		bt = tm.GetNode("/root/BetterTerrain");
	}
	
	public Array<Dictionary<string, Variant>> GetTerrainCategories()
	{
		return (Array<Dictionary<string, Variant>>)bt.Call("get_terrain_categories", tm.TileSet);
	}
	
	public bool AddTerrain(string name, Color color, TerrainType type, Array<int> categories = null, Dictionary<Variant, Variant> icon = null)
	{
		if (categories is null)
			categories = new Array<int>();
		if (icon is null)
			icon = new Dictionary<Variant, Variant>();
		return (bool)bt.Call("add_terrain", tm.TileSet, name, color, (int)type, categories, icon);
	}
	
	public bool RemoveTerrain(int index)
	{
		return (bool)bt.Call("remove_terrain", tm.TileSet, index);
	}
	
	public int TerrainCount()
	{
		return (int)bt.Call("terrain_count", tm.TileSet);
	}
	
	public Dictionary<string, Variant> GetTerrain(int index)
	{
		return (Dictionary<string, Variant>)bt.Call("get_terrain", tm.TileSet, index);
	}
	
	public bool SetTerrain(int index, string name, Color color, TerrainType type, Array<int> categories = null, Dictionary<Variant, Variant> icon = null)
	{
		if (categories is null)
			categories = new Array<int>();
		if (icon is null)
			icon = new Dictionary<Variant, Variant>();
		return (bool)bt.Call("set_terrain", tm.TileSet, index, name, color, (int)type, categories, icon);
	}
	
	public bool SwapTerrains(int index1, int index2)
	{
		return (bool)bt.Call("swap_terrains", tm.TileSet, index1, index2);
	}
	
	public bool SetTileTerrainType(TileData td, int type)
	{
		return (bool)bt.Call("set_tile_terrain_type", tm.TileSet, td, type);
	}
	
	public int GetTileTerrainType(TileData td)
	{
		return (int)bt.Call("get_tile_terrain_type", td);
	}
	
	public bool SetTileSymmetryType(TileData td, SymmetryType type)
	{
		return (bool)bt.Call("set_tile_symmetry_type", tm.TileSet, td, (int)type);
	}
	
	public SymmetryType GetTileSymmetryType(TileData td)
	{
		return (SymmetryType)(int)bt.Call("get_tile_symmetry_type", td);
	}
	
	public Array<TileData> GetTilesInTerrain(int type)
	{
		return (Array<TileData>)bt.Call("get_tiles_in_terrain", tm.TileSet, type);
	}
	
	public Array<Dictionary<string, Variant>> GetTileSourcesInTerrain(int type)
	{
		return (Array<Dictionary<string, Variant>>)bt.Call("get_tile_sources_in_terrain", tm.TileSet, type);
	}
	
	public bool AddTilePeeringType(TileData td, TileSet.CellNeighbor peering, int type)
	{
		return (bool)bt.Call("add_tile_peering_type", tm.TileSet, td, (int)peering, type);
	}
	
	public bool RemoveTilePeeringType(TileData td, TileSet.CellNeighbor peering, int type)
	{
		return (bool)bt.Call("remove_tile_peering_type", tm.TileSet, td, (int)peering, type);
	}
	
	public Array<TileSet.CellNeighbor> TilePeeringKeys(TileData td)
	{
		return (Array<TileSet.CellNeighbor>)bt.Call("tile_peering_keys", td);
	}
	
	public Array<int> TilePeeringTypes(TileData td, TileSet.CellNeighbor peering)
	{
		return (Array<int>)bt.Call("tile_peering_types", td, (int)peering);
	}
	
	public Array<TileSet.CellNeighbor> TilePeeringForType(TileData td, int type)
	{
		return (Array<TileSet.CellNeighbor>)bt.Call("tile_peering_for_type", td, type);
	}
	
	public bool SetCell(int layer, Vector2I coord, int type)
	{
		return (bool)bt.Call("set_cell", tm, layer, coord, type);
	}
	
	public bool SetCells(int layer, Array<Vector2I> coords, int type)
	{
		return (bool)bt.Call("set_cells", tm, layer, coords, type);
	}
	
	public bool ReplaceCell(int layer, Vector2I coord, int type)
	{
		return (bool)bt.Call("replace_cell", tm, layer, coord, type);
	}
	
	public bool ReplaceCells(int layer, Array<Vector2I> coords, int type)
	{
		return (bool)bt.Call("replace_cells", tm, layer, coords, type);
	}
	
	public int GetCell(int layer, Vector2I coord)
	{
		return (int)bt.Call("get_cell", tm, layer, coord);
	}
	
	public void UpdateTerrainCells(int layer, Array<Vector2I> cells, bool and_surrounding_cells = true)
	{
		bt.Call("update_terrain_cells", tm, layer, cells, and_surrounding_cells);
	}
	
	public void UpdateTerrainCell(int layer, Vector2I cell, bool and_surrounding_cells = true)
	{
		bt.Call("update_terrain_cell", tm, layer, cell, and_surrounding_cells);
	}
	
	public void UpdateTerrainArea(int layer, Rect2I area, bool and_surrounding_cells = true)
	{
		bt.Call("update_terrain_area", tm, layer, area, and_surrounding_cells);
	}
	
	public Dictionary<Variant, Variant> CreateTerrainChangeset(int layer, Dictionary<Vector2I, int> paint)
	{
		return (Dictionary<Variant, Variant>)bt.Call("create_terrain_changeset", tm, layer, paint);
	}
	
	public bool IsTerrainChangesetReady(Dictionary<Variant, Variant> change)
	{
		return (bool)bt.Call("is_terrain_changeset_ready", change);
	}
	
	public void WaitForTerrainChangeset(Dictionary<Variant, Variant> change)
	{
		bt.Call("wait_for_terrain_changeset", change);
	}
	
	public void ApplyTerrainChangeset(Dictionary<Variant, Variant> change)
	{
		bt.Call("apply_terrain_changeset", change);
	}
}
