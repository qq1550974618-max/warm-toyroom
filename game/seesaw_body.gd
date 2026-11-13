extends RigidBody3D
var playground:Node3D
var maximum_angle=0.0
var maximum_angular_speed=0.0
func _ready() -> void:
	mass=3.2;collision_layer=4;collision_mask=7;continuous_cd=true;can_sleep=false
	linear_damp=.2;angular_damp=.65;contact_monitor=true;max_contacts_reported=12
	set_meta("heavy_push_only",true)
	var pm=PhysicsMaterial.new();pm.friction=.95;pm.bounce=.03;physics_material_override=pm
func _physics_process(_delta:float) -> void:
	var axis=playground.BOARD_BASIS.z
	var local_basis=playground.BOARD_BASIS.inverse()*basis
	var angle=atan2(local_basis.x.y,local_basis.x.x);var speed=angular_velocity.dot(axis)
	maximum_angle=maxf(maximum_angle,absf(angle));maximum_angular_speed=maxf(maximum_angular_speed,absf(speed))
	apply_torque(axis*(-angle*3.5-speed*.22))
	if playground==null:return
	for person in [playground.room.actor,playground.room.companion]:
		if playground.on_seat(person,0):
			var load_mass=1.7 if person.rice_charged else .58
			apply_force(Vector3.DOWN*load_mass*9.8,person.global_position-global_position)
