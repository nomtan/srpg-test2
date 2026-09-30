class_name AssembledCharacter
extends Node3D


func set_expression(expression: String) -> bool:
	return $ExpressionController.set_expression(expression)


func set_eyes(value: String) -> bool:
	return $ExpressionController.set_eyes(value)


func set_eyebrows(value: String) -> bool:
	return $ExpressionController.set_eyebrows(value)


func set_mouth(value: String) -> bool:
	return $ExpressionController.set_mouth(value)
