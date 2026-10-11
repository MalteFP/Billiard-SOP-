extends Node2D
class_name Ball


var color: Color  = Color.WHITE
var velocity := Vector2.ZERO
var angular_velocity := Vector3.ZERO
var orientation := Basis.IDENTITY

const RADIUS := 0.02857
const MASS := 0.17
const GRAVITY := 9.82
const MU_SLIDE := 0.2
const MU_ROLL := 0.01
const MU_SPIN := 0.044
const INERTIA := 0.4 * MASS * pow(RADIUS, 2)
const PIXELS_PER_METER := 1000
const EPS := 0.0005


func step(delta: float) -> void:
	var remaining := delta - update_sliding(delta)
	if remaining > 0.0:
		update_friction(remaining)
	update_spin(delta)
	update_rotation(delta)
	position += velocity * PIXELS_PER_METER * delta
	queue_redraw()

func contact_velocity() -> Vector2:
	return velocity + RADIUS * Vector2(angular_velocity.y, -angular_velocity.x)

func sync_rolling():
	angular_velocity.x = velocity.y / RADIUS
	angular_velocity.y = -velocity.x / RADIUS

func update_sliding(delta: float) -> float:
	var u: Vector2 = contact_velocity()
	var slip := u.length()
	if slip < EPS:
		return 0.0
	
	var t_stop := slip / (3.5 * MU_SLIDE * GRAVITY)
	var dt := minf(delta, t_stop)
	
	var accel := -u / slip * MU_SLIDE * GRAVITY
	var force := accel * MASS
	velocity += accel * dt
	
	var torque := Vector3(-RADIUS * force.y, RADIUS * force.x, 0.0)
	angular_velocity += torque / INERTIA * dt
	
	if dt >= t_stop:
		sync_rolling()
	return dt

func update_friction(delta: float) -> void:
	var speed := velocity.length()
	if speed < EPS:
		velocity = Vector2.ZERO
		angular_velocity.x = 0.0
		angular_velocity.y = 0.0
		return
	
	var decel := MU_ROLL * GRAVITY * delta
	if speed <= decel:
		velocity = Vector2.ZERO
		angular_velocity.x = 0.0
		angular_velocity.y = 0.0
	else:
		velocity -= velocity / speed * decel
		sync_rolling()



func update_spin(delta: float) -> void:
	var decel := (5.0 / 3.0) * MU_SPIN * GRAVITY / RADIUS * delta
	angular_velocity.z = move_toward(angular_velocity.z, 0.0, decel)


func update_rotation(delta: float) -> void:
	var w := angular_velocity.length()
	if w < EPS:
		return
	orientation = (Basis(angular_velocity / w, w * delta) * orientation).orthonormalized()



func _draw() -> void:
	var r := RADIUS * PIXELS_PER_METER
	draw_circle(Vector2.ZERO, r, color)
	var axes: Array[Vector3] = [
		Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD
	]
	for axis in axes:
		var p := orientation * axis
		if p.z < 0.0:
			var facing := -p.z
			draw_circle(Vector2(p.x, p.y) * r, r * 0.14 * facing, Color(0.1, 0.1, 0.1, facing))
 
	draw_circle(Vector2(-0.3, -0.3) * r, r * 0.18, Color(1, 1, 1, 0.35))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0, 0, 0, 0.6), 1.5, true)


func set_pos(pos: Vector2):
	position = pos * PIXELS_PER_METER
func get_pos() -> Vector2:
	return position / PIXELS_PER_METER
