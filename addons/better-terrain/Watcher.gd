@tool
extends Node

signal trigger
var complete := false
var tileset : TileSet

func tidy() -> bool:
	if complete:
		return false
	
	complete = true
	queue_free()
	return true


func activate():
	if tidy():
		trigger.emit()

