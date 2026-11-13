extends RefCounted
func add_box(parent:Node,position:Vector3,size:Vector3) -> CollisionShape3D:
	var cs=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=size;cs.shape=shape;parent.add_child(cs);cs.position=position;return cs

func add_rug_contact(parent:Node) -> void:
	# One smooth contact surface replaces decorative fringe, paper and micro bevels.
	var points=PackedVector3Array()
	for y in [0.0,.044]:
		var inset=.080 if y>0 else 0.0
		for x in [-1,1]:
			for z in [-1,1]:points.append(Vector3(x*(2.78-inset),y,z*(1.69-inset)))
	var shape=ConvexPolygonShape3D.new();shape.points=points;shape.margin=.001
	var cs=CollisionShape3D.new();cs.name="BeveledRugContact";cs.shape=shape;parent.add_child(cs);cs.position=Vector3(-3.575,0,.505)
func apply(game:Node) -> void:
	var scene=game.room
	# Visual plank bevels, nails and fringe are far below toy-foot contact scale.
	# One continuous floor avoids snagging and thousands of redundant contacts.
	for cs in scene.get_node("Props/Floor").find_children("*","CollisionShape3D",true,false):cs.disabled=true
	for mesh in scene.get_node("Props/Rug").find_children("*","MeshInstance3D",true,false):
		var bounds: AABB=mesh.global_transform*mesh.get_aabb()
		if bounds.end.y<.09:
			for cs in mesh.find_children("*","CollisionShape3D",true,false):cs.disabled=true
	var walking_floor=StaticBody3D.new();walking_floor.name="ContinuousWalkingFloor";walking_floor.collision_layer=1;walking_floor.collision_mask=6;scene.add_child(walking_floor)
	add_box(walking_floor,Vector3(0,-.05,0),Vector3(16,.10,16))
	add_rug_contact(walking_floor)
	for prop in game.physics_props:
		if prop.get_meta("kind","")!="pencil":continue
		for cs in prop.find_children("*","CollisionShape3D",true,false):
			if cs.shape is ConvexPolygonShape3D and cs.shape.points.size()>96:cs.shape=support_hull(cs.shape.points)
	for mesh in scene.get_node("Props/FloorDetails").find_children("*","MeshInstance3D",true,false):
		if str(mesh.name) in ["Room Paper fine deckle shade_002","Room Paper ivory fibres_001"]:
			mesh.hide()
			for cs in mesh.find_children("*","CollisionShape3D",true,false):cs.disabled=true
	for body in scene.find_children("*","StaticBody3D",true,false):body.collision_mask=6
	var support=StaticBody3D.new();support.name="SoftFurnitureSupport";support.collision_layer=16;support.collision_mask=32;scene.add_child(support)
	add_box(support,Vector3(0,-.05,0),Vector3(16,.10,16))
	add_rug_contact(support)
	add_box(support,Vector3(-5.67,1.39,-4.015),Vector3(4.05,2.78,2.58))
	for name in ["AlphabetBlocks","SmallBlockM","FloorCushions"]:
		var root=scene.get_node_or_null("Props/"+name)
		if root==null:continue
		for cs in root.find_children("*","CollisionShape3D",true,false):
			if cs.shape is ConvexPolygonShape3D and cs.shape.points.size()>120:cs.shape=support_hull(cs.shape.points)
			if not cs.shape is ConcavePolygonShape3D:
				var copy=CollisionShape3D.new();copy.shape=cs.shape;support.add_child(copy);copy.global_transform=cs.global_transform
	for pillow in game.physics_cushions:
		pillow.collision_layer=33;pillow.collision_mask=62;pillow.continuous_cd=false
		pillow.linear_damp=1.4;pillow.angular_damp=2.0
		pillow.physics_material_override=pillow.physics_material_override.duplicate()
		pillow.physics_material_override.friction=.92;pillow.physics_material_override.bounce=0.0
		pillow.contact_monitor=true;pillow.max_contacts_reported=4
		var rest=preload("res://cushion_rest.gd").new();rest.body=pillow;pillow.add_child(rest)
	var basket=scene.get_node("Props/WickerBasket");basket.position+=Vector3(.16,0,.48)
	for cs in basket.find_children("*","CollisionShape3D",true,false):cs.disabled=true
	for mesh in basket.find_children("*","MeshInstance3D",true,false):
		mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;mesh.set_meta("dynamic_relocated_prop",true)
	var shell=StaticBody3D.new();shell.name="HollowBasketContact";shell.collision_layer=1;shell.collision_mask=6;basket.add_child(shell)
	add_box(shell,Vector3(0,.065,-.04),Vector3(1.77,.12,1.02))
	for side in [-1,1]:
		add_box(shell,Vector3(side*.875,.48,-.04),Vector3(.095,.84,1.06))
		add_box(shell,Vector3(0,.48,side*.52-.04),Vector3(1.77,.84,.085))
	for cs in shell.get_children():
		var copy=CollisionShape3D.new();copy.shape=cs.shape;support.add_child(copy);copy.global_transform=cs.global_transform
func support_hull(points:PackedVector3Array) -> ConvexPolygonShape3D:
	var output=PackedVector3Array();var seen={}
	for y in 7:
		for x in 12:
			var a=PI*y/6;var b=TAU*x/12;var d=Vector3(sin(a)*cos(b),cos(a),sin(a)*sin(b));var best=-INF;var chosen=Vector3.ZERO
			for p in points:
				if p.dot(d)>best:best=p.dot(d);chosen=p
			if not seen.has(chosen):seen[chosen]=true;output.append(chosen)
	var shape=ConvexPolygonShape3D.new();shape.points=output;shape.margin=.002;return shape
