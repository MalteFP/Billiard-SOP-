extends Node2D

@export var table_size := Vector2(2.54, 1.27)

const E_BALL := 0.95
const MU_BALL := 0.06
const E_CUSHION := 0.75
const MU_CUSHION := 0.2
const SOLVER_ITERATIONS := 20

const tip_height := 0
const tip_side := 0

var balls: Array[Ball] = []

var cue: Ball
@onready var cam = $Camera2D

func _ready() -> void:
	spawn_balls()
	var viewport_size = get_viewport_rect().size
	var table_pixels = table_size * Ball.PIXELS_PER_METER
	cam.zoom = Vector2(1,1) / ((table_pixels + Vector2(30,30)) / viewport_size)
	cam.position = table_pixels / 2.0


func spawn_balls() -> void:
	cue = add_ball(Vector2(table_size.x * 0.25, table_size.y * 0.5), Color.WHITE)

	#add_ball(Vector2(table_size.x * 0.25 + 1, table_size.y * 0.5), Color.RED)
	spawn_rack(Vector2(table_size.x * 0.25 + 1, table_size.y * 0.5))

	shoot(cue, Vector2(1,0), 6, tip_height, tip_side)


func add_ball(pos_m: Vector2, col: Color) -> Ball:
	var b := Ball.new()
	b.color = col
	b.set_pos(pos_m)
	add_child(b)
	balls.append(b)
	return b


func _physics_process(delta: float) -> void:
	var fastest := 0.0
	for b in balls:
		fastest = maxf(fastest, b.velocity.length())
	var steps := clampi(ceili(fastest * delta / (0.5 * Ball.RADIUS)), 1, 20)
	var dt := delta / steps

	for s in steps:
		for b in balls:
			b.step(dt)
		for b in balls:
			collide_cushions(b)
		resolve_ball_collisions()


func collide_cushions(b: Ball) -> void:
	var r := Ball.RADIUS
	var p := b.get_pos()

	var walls := [
		[Vector2.ZERO, Vector2.RIGHT],
		[Vector2(table_size.x, 0.0), Vector2.LEFT],
		[Vector2.ZERO, Vector2.DOWN],
		[Vector2(0.0, table_size.y), Vector2.UP],
	]

	for w in walls:
		var n: Vector2 = w[1]
		var dist := (p - (w[0] as Vector2)).dot(n)
		if dist < r:
			p += n * (r - dist)
			b.set_pos(p)
			bounce_cushion(b, n)


func bounce_cushion(b: Ball, n: Vector2) -> void:
	var vn := b.velocity.dot(n)
	if vn >= 0.0:
		return

	var t := Vector2(-n.y, n.x)

	var jn := -(1.0 + E_CUSHION) * Ball.MASS * vn
	b.velocity += n * jn / Ball.MASS

	var slip := b.velocity.dot(t) - Ball.RADIUS * b.angular_velocity.z
	var f := clampf(-slip * Ball.MASS / 3.5, -MU_CUSHION * jn, MU_CUSHION * jn)
	b.velocity += t * f / Ball.MASS
	b.angular_velocity.z -= Ball.RADIUS * f / Ball.INERTIA


# Resolves ALL ball-ball contacts of this step together, so the result does not
# depend on which pair happens to be processed first (keeps symmetric breaks symmetric).
func resolve_ball_collisions() -> void:
	var r := Ball.RADIUS
	var contacts: Array[Dictionary] = []
	var push: Array[Vector2] = []
	push.resize(balls.size())
	push.fill(Vector2.ZERO)

	# 1. Find overlapping pairs and remember how fast they approach right now.
	for i in balls.size():
		for j in range(i + 1, balls.size()):
			var a := balls[i]
			var b := balls[j]
			var d := b.get_pos() - a.get_pos()
			var dist := d.length()
			if dist >= 2.0 * r:
				continue
			var n := d / dist if dist > 0.0 else Vector2.RIGHT
			var half := n * (2.0 * r - dist) * 0.5
			push[i] -= half
			push[j] += half
			var vn0 := (a.velocity - b.velocity).dot(n)
			contacts.append({
				"a": a, "b": b, "n": n,
				"target": E_BALL * vn0 if vn0 > 0.0 else 0.0,   # wanted separation speed
				"acc": 0.0,                                      # accumulated normal impulse
			})

	if contacts.is_empty():
		return

	# 2. Separate overlapping balls (all at once, not pair by pair).
	for i in balls.size():
		balls[i].set_pos(balls[i].get_pos() + push[i])

	# 3. Normal impulses: iterate until all contacts agree. Impulses can only push.
	for it in SOLVER_ITERATIONS:
		for c in contacts:
			var a: Ball = c.a
			var b: Ball = c.b
			var n: Vector2 = c.n
			var separation := -(a.velocity - b.velocity).dot(n)
			var lam: float = (Ball.MASS * 0.5) * (c.target - separation)
			var new_acc := maxf(c.acc + lam, 0.0)
			lam = new_acc - c.acc
			c.acc = new_acc
			a.velocity -= n * lam / Ball.MASS
			b.velocity += n * lam / Ball.MASS

	# 4. Friction between the ball surfaces (throw and side spin transfer),
	#    limited by the normal impulse each contact carried.
	for c in contacts:
		var a: Ball = c.a
		var b: Ball = c.b
		var n: Vector2 = c.n
		var jn: float = c.acc
		var t := Vector2(-n.y, n.x)
		var slip := (a.velocity - b.velocity).dot(t) \
			+ Ball.RADIUS * (a.angular_velocity.z + b.angular_velocity.z)
		var f := clampf(-slip * Ball.MASS / 7.0, -MU_BALL * jn, MU_BALL * jn)
		a.velocity += t * f / Ball.MASS
		b.velocity -= t * f / Ball.MASS
		a.angular_velocity.z += Ball.RADIUS * f / Ball.INERTIA
		b.angular_velocity.z += Ball.RADIUS * f / Ball.INERTIA


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var dir := get_local_mouse_position() - cue.position
		if dir.length() < 1.0:
			return
		var speed := clampf(dir.length() / Ball.PIXELS_PER_METER * 4.0, 0.0, 10.0)
		speed = minf(4.0, speed)
		shoot(cue, dir, speed, tip_height, tip_side)

func shoot(ball: Ball, dir: Vector2, speed: float, height := 0.0, side := 0.0) -> void:
	dir = dir.normalized()
	ball.velocity = dir * speed
	var k := 2.5 * speed / Ball.RADIUS
	ball.angular_velocity = Vector3(dir.y, -dir.x, 0.0) * k * height \
		+ Vector3(0.0, 0.0, -k * side)

func _draw() -> void:
	var s := table_size * Ball.PIXELS_PER_METER
	var rail := 30.0
	draw_rect(Rect2(Vector2(-rail, -rail), s + Vector2(rail, rail) * 2.0), Color("5a3820"))
	draw_rect(Rect2(Vector2.ZERO, s), Color("1f6b3a"))


func spawn_rack(apex_pos: Vector2) -> void:
	var r := Ball.RADIUS
	var dx := sqrt(3.0) * r
	var dy := r

	var colors := [
		Color.YELLOW,
		Color.BLUE, Color.RED,
		Color.PURPLE, Color.ORANGE, Color.GREEN,
		Color.MAROON, Color.BLACK, Color.YELLOW, Color.BLUE,
		Color.RED, Color.PURPLE, Color.ORANGE, Color.GREEN, Color.MAROON
	]

	var index := 0

	for row in range(5):
		for col in range(row + 1):
			var pos = apex_pos + Vector2(row * dx, (col - row * 0.5) * 2.0 * dy)
			add_ball(pos, colors[index])
			index += 1
