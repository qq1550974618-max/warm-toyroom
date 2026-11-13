extends Node
var actor:CharacterBody3D
var model:Node3D
var meshes:Array[MeshInstance3D]=[]
var was_active=false
func setup(owner_actor:CharacterBody3D) -> void:
	actor=owner_actor;model=load("res://assets/playground/v17_whale_ball.glb").instantiate();actor.add_child(model);model.hide()
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		meshes.append(mesh);mesh.layers=2;mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
func prepare_materials() -> void:pass
func _physics_process(_delta:float) -> void:update_pose()
func update_pose() -> void:
	if actor==null:return
	var active=actor.state=="roll" and actor.roll_time>=actor.BALL_CROUCH_TIME
	model.visible=active
	if was_active and not active:actor.visual.show()
	if active:
		var t=actor.roll_weight
		actor.visual.visible=t<.94
		model.basis=(Basis(Vector3.UP,actor.heading_yaw)*Basis(Vector3.BACK,actor.roll_angle)).scaled(Vector3.ONE*actor.roll_radius*maxf(.08,smoothstep(0,1,t)))
		model.position=Vector3(0,actor.roll_radius,0)
	was_active=active
