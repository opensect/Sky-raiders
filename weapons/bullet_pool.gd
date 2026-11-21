class_name BulletPool
extends RefCounted

# BulletController (pooling): bullets are cheap but a full-auto SMG
# from 8 players can create well over a hundred a second, so bullets
# are recycled instead of instantiated and freed every shot.
#
# The pool pre-creates N bullet nodes under the game's bullets
# container, deactivated (invisible, no physics). `obtain()` hands out
# an inactive one (or a fresh node if the pool is exhausted — never
# fails, just allocates). `release()` deactivates it again. A bullet
# returns itself to the pool in _despawn() instead of queue_free().
# Each peer runs its own pool: spawn_bullet is an RPC with call_local,
# so every peer pulls from its own local pool for the same shot.

const DEFAULT_SIZE := 96

var _pool: Array = []
var _scene: PackedScene
var _parent: Node


func _init(scene: PackedScene, parent: Node, pool_size: int = DEFAULT_SIZE) -> void:
	_scene = scene
	_parent = parent
	for i in pool_size:
		var b = _scene.instantiate()
		b.pooled = true
		b.visible = false
		b.set_physics_process(false)
		b.name = "pool_%d" % i
		_parent.add_child(b)
		_pool.append(b)


func obtain() -> Node:
	for b in _pool:
		if not b.active:
			b.active = true
			return b
	# Pool exhausted (very heavy fire): allocate a one-off bullet.
	var extra = _scene.instantiate()
	extra.pooled = false
	return extra


func release(b: Node) -> void:
	if b == null or not is_instance_valid(b):
		return
	if not b.pooled:
		b.queue_free()
		return
	b.active = false
	b.visible = false
	b.set_physics_process(false)
	# Park it far off-screen so a stale visual can never show.
	b.position = Vector2(-10000, -10000)


func active_count() -> int:
	var n := 0
	for b in _pool:
		if b.active:
			n += 1
	return n


func pool_size() -> int:
	return _pool.size()
