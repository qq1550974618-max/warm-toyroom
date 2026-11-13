extends RefCounted
# Keep the established 2560x1440 UI layout while rendering the entire 3D
# viewport at native UHD. No scene lighting, textures or FOV are altered.
const BASE_SIZE=Vector2(2560,1440)
var room:Node
var factor:=1.0
var requested_4k:=false
var layers:Dictionary={}

func bind(owner_room:Node) -> void:
	room=owner_room
	_register_tree(room)
	room.get_tree().node_added.connect(_on_node_added)
	set_4k(requested_4k)

func _on_node_added(node:Node) -> void:
	if node is CanvasLayer and node.get_viewport()==room.get_viewport():
		_register_layer.call_deferred(node)

func _register_tree(node:Node) -> void:
	if node is CanvasLayer and node.get_viewport()==room.get_viewport():_register_layer(node)
	for child in node.get_children():_register_tree(child)

func _register_layer(node:CanvasLayer) -> void:
	if not is_instance_valid(node) or layers.has(node.get_instance_id()):return
	layers[node.get_instance_id()]=node.transform
	# Top-level anchors would otherwise expand to 3840x2160 as well as being
	# scaled by the canvas, moving buttons off screen. Children retain anchors.
	for child in node.get_children():
		if not child is Control:continue
		var top=Vector2(child.anchor_left,child.anchor_top)*BASE_SIZE+Vector2(child.offset_left,child.offset_top)
		var bottom=Vector2(child.anchor_right,child.anchor_bottom)*BASE_SIZE+Vector2(child.offset_right,child.offset_bottom)
		child.set_anchors_preset(Control.PRESET_TOP_LEFT)
		child.position=top;child.size=bottom-top
	_apply_layer(node)

func _apply_layer(node:CanvasLayer) -> void:
	node.transform=Transform2D.IDENTITY.scaled(Vector2.ONE*factor)*layers[node.get_instance_id()]

func set_4k(enabled:bool) -> void:
	requested_4k=enabled
	if room==null:return
	var next_factor:=1.5 if enabled else 1.0
	var ratio:=next_factor/factor
	factor=next_factor
	var window:=room.get_window()
	window.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_size=Vector2i(BASE_SIZE*factor)
	window.scaling_3d_scale=1.0
	for id in layers.keys():
		var node=instance_from_id(id)
		if is_instance_valid(node):_apply_layer(node)
		else:layers.erase(id)
	if room.prop_interaction!=null:room.prop_interaction.aim_cursor*=ratio

func logical_point(point:Vector2) -> Vector2:
	return point/factor
