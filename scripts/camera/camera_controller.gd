class_name CameraController
extends Node3D

var camera: Camera3D


func setup() -> Camera3D:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.5
	camera.position = Vector3(11.5, 12.5, 13.5)
	camera.look_at_from_position(camera.position, Vector3(4, 0.8, 4), Vector3.UP)
	add_child(camera)
	return camera
