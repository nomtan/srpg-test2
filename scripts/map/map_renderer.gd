class_name MapRenderer
extends Node3D

const TOP_LAYER := "TopLayer"
const CLIFF_LAYER := "CliffLayer"
const WATER_LAYER := "WaterLayer"
const PROP_LAYER := "PropLayer"
const DEBUG_LAYER := "DebugLayer"

var map_data: MapData
var _layers: Dictionary = {}


func begin_render(data: MapData) -> void:
	map_data = data
	for child in get_children():
		if child.name in [TOP_LAYER, CLIFF_LAYER, WATER_LAYER, PROP_LAYER, DEBUG_LAYER]:
			child.free()
	_layers.clear()
	for layer_name: String in [TOP_LAYER, CLIFF_LAYER, WATER_LAYER, PROP_LAYER, DEBUG_LAYER]:
		var layer := Node3D.new()
		layer.name = layer_name
		add_child(layer)
		_layers[layer_name] = layer


func add_to_layer(node: Node3D, layer_name: String) -> void:
	var layer := _layers.get(layer_name) as Node3D
	if not layer:
		push_error("MapRenderer layer is not initialized: %s" % layer_name)
		return
	layer.add_child(node)


func get_layer(layer_name: String) -> Node3D:
	return _layers.get(layer_name) as Node3D
