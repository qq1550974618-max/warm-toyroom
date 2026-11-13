extends RefCounted
var room:Node
func bind(owner_room:Node) -> void:
	room=owner_room
	room.get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	room.get_window().content_scale_size=Vector2i(2560,1440)
func set_4k(_enabled:bool) -> void:pass
func logical_point(point:Vector2) -> Vector2:return point
