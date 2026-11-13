extends "res://toy_prop_body.gd"
var room:Node3D
var voice:AudioStreamPlayer3D
var cue_counts={"pickup":0,"throw":0}
var cues={"pickup":preload("res://assets/playground/chicken_pickup.wav"),"throw":preload("res://assets/playground/chicken_throw.wav")}
func _ready() -> void:
	name="BasketballChick";mass=.15;collision_layer=4;collision_mask=7;continuous_cd=true;linear_damp=.4;angular_damp=.55
	center_of_mass_mode=RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM;center_of_mass=Vector3(.018,-.125,0)
	var model=preload("res://assets/playground/chicken_toy.glb").instantiate();add_child(model)
	var points=PackedVector3Array()
	for v in JSON.parse_string(FileAccess.get_file_as_string("res://assets/playground/chicken_hull.json")):points.append(Vector3(v[0],v[1],v[2]))
	# Planar soles under the rounded shoes, as on the physical vinyl reference.
	for i in points.size():
		if points[i].y<-.192:points[i].y=-.195
	var hull=preload("res://v17_scene_refinement.gd").new().support_hull(points)
	var cs=CollisionShape3D.new();cs.name="ToyHull";cs.shape=hull;add_child(cs)
	var pm=PhysicsMaterial.new();pm.friction=.65;pm.bounce=.16;physics_material_override=pm
	set_meta("kind","chicken");set_meta("display_name","坤坤");set_meta("prop_size",Vector3(.25,.39,.30));set_meta("spawn_transform",transform)
	for mesh in model.find_children("*","MeshInstance3D",true,false):mesh.layers=2;mesh.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
	voice=AudioStreamPlayer3D.new();voice.name="MemeVoice";voice.unit_size=4;voice.max_distance=18;voice.volume_db=-16;add_child(voice)
func play_cue(kind:String) -> void:
	if kind not in cue_counts:return
	cue_counts[kind]+=1
	if not room.sounds_enabled:return
	voice.stream=cues[kind];voice.play()
