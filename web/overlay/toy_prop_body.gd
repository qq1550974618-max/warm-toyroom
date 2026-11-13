extends RigidBody3D

var last_velocity:=Vector3.ZERO
var last_angular:=Vector3.ZERO

func reset_contact_history() -> void:
	last_velocity=Vector3.ZERO;last_angular=Vector3.ZERO;set_meta("contact_speed",0.0);set_meta("thrown_until_frame",-1);set_meta("last_contact_frame",-30)
	if has_meta("contact_position"):remove_meta("contact_position")

func _integrate_forces(state:PhysicsDirectBodyState3D) -> void:
	if state.get_contact_count()>0:
		var best:=0;var strongest:=0.0
		for i in state.get_contact_count():
			var strength:float=state.get_contact_impulse(i).length()
			if strength>strongest:strongest=strength;best=i
		var normal:Vector3=state.get_contact_local_normal(best).normalized()
		var point:Vector3=state.get_contact_collider_position(best)
		set_meta("contact_position",point)
		set_meta("contact_normal",normal)
		set_meta("contact_speed",absf((last_velocity+last_angular.cross(point-state.transform.origin)).dot(normal)))
	last_velocity=state.linear_velocity;last_angular=state.angular_velocity
