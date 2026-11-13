extends RefCounted
var room:Node
func bind(owner_room:Node) -> void:
	room=owner_room
	room.get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	room.get_window().content_scale_size=Vector2i(2560,1440)
	# Expand the 3D view to the actual display aspect. Never stretch a 16:9 image.
	room.get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
func set_4k(_enabled:bool) -> void:pass
func logical_point(point:Vector2) -> Vector2:return point
