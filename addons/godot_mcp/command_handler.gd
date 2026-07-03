@tool
extends Node

var _websocket_server
var _command_processors = []

# Preload command processor classes at module top-level so the analyzer
# and editor can resolve their `class_name` declarations.
# Note: load command processor scripts dynamically inside the initializer
# to avoid static analyzer/resolution issues in some editor setups.

func _ready():
	print("Command handler initializing...")
	_websocket_server = get_parent()
	print("WebSocket server reference set: ", _websocket_server)
    
	# Initialize command processors
	_initialize_command_processors()
    
	print("Command handler initialized and ready to process commands")

func _initialize_command_processors():
	# Dynamically load and instantiate processor scripts
	var node_commands_script = load("res://addons/godot_mcp/commands/node_commands.gd")
	var script_commands_script = load("res://addons/godot_mcp/commands/script_commands.gd")
	var scene_commands_script = load("res://addons/godot_mcp/commands/scene_commands.gd")
	var project_commands_script = load("res://addons/godot_mcp/commands/project_commands.gd")
	var editor_commands_script = load("res://addons/godot_mcp/commands/editor_commands.gd")
	var editor_script_commands_script = load("res://addons/godot_mcp/commands/editor_script_commands.gd")
	var animation_commands_script = load("res://addons/godot_mcp/commands/animation_commands.gd")
	var audio_commands_script = load("res://addons/godot_mcp/commands/audio_commands.gd")
	var introspection_commands_script = load("res://addons/godot_mcp/commands/introspection_commands.gd")
	var visualizer_commands_script = load("res://addons/godot_mcp/commands/visualizer_commands.gd")

	var node_commands = node_commands_script.new() if node_commands_script else null
	var script_commands = script_commands_script.new() if script_commands_script else null
	var scene_commands = scene_commands_script.new() if scene_commands_script else null
	var project_commands = project_commands_script.new() if project_commands_script else null
	var editor_commands = editor_commands_script.new() if editor_commands_script else null
	var editor_script_commands = editor_script_commands_script.new() if editor_script_commands_script else null
	var animation_commands = animation_commands_script.new() if animation_commands_script else null
	var audio_commands = audio_commands_script.new() if audio_commands_script else null
	var introspection_commands = introspection_commands_script.new() if introspection_commands_script else null
	var visualizer_commands = visualizer_commands_script.new() if visualizer_commands_script else null

	# Set server reference for all processors
	var processors = [
		node_commands, script_commands, scene_commands, project_commands,
		editor_commands, editor_script_commands, animation_commands,
		audio_commands, introspection_commands, visualizer_commands
	]
	for p in processors:
		if p != null:
			p._websocket_server = _websocket_server

	# Add them to our processor list
	for p in processors:
		_command_processors.append(p)

	# Add them as children for proper lifecycle management
	for p in processors:
		add_child(p)

func _handle_command(client_id: int, command: Dictionary) -> void:
	var command_type = command.get("type", "")
	var params = command.get("params", {})
	var command_id = command.get("commandId", "")
	
	print("Processing command: %s" % command_type)
	
	# Try each processor until one handles the command
	for processor in _command_processors:
		if processor.process_command(client_id, command_type, params, command_id):
			return
	
	# If no processor handled the command, send an error
	_send_error(client_id, "Unknown command: %s" % command_type, command_id)

func _send_error(client_id: int, message: String, command_id: String) -> void:
	var response = {
		"status": "error",
		"message": message
	}
	
	if not command_id.is_empty():
		response["commandId"] = command_id
	
	_websocket_server.send_response(client_id, response)
	print("Error: %s" % message)
