extends Node
var body:RigidBody3D
var quiet_time=0.0
var last_sample=Transform3D.IDENTITY
func _ready() -> void:last_sample=body.global_transform
func _physics_process(delta:float) -> void:
	if body.sleeping:quiet_time=0;last_sample=body.global_transform;return
	# Fabric absorbs tiny rocking contacts. Sleep only after supported quiet
	# contact, keeping the rigid body free to wake on footsteps or an impulse.
	quiet_time+=delta
	if quiet_time<1.0:return
	var drift=body.global_position.distance_to(last_sample.origin)
	var spin=body.global_basis.get_rotation_quaternion().angle_to(last_sample.basis.get_rotation_quaternion())
	if body.get_contact_count()>0 and drift<.012 and spin<.07 and body.linear_velocity.length()<.12:body.sleeping=true
	last_sample=body.global_transform;quiet_time=0
