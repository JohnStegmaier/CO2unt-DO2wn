class_name ShopRoom
extends Room

## The floor's shop, seen from the side.
##
## A belt-scroll counter. The camera looks along the room rather than down at it,
## so the shopkeeper stands behind a counter at the back and the player walks a
## shallow strip in front of it. Same illusion as [ElevatorRoom], which should be
## read first: depth is carried by SCALE, not by screen position, and vertical
## movement is slowed to match a strip that would otherwise be crossed in a third
## of a second.
##
## What this room adds is a second axis of depth — the planes slide against each
## other as the player looks around, so the wall, the shelves, the keeper and the
## counter separate. That is done by moving the LAYERS and not the camera; see
## [DepthLayer] for why.
##
## It is a Room because Game treats it as one: instanced into RoomContainer at
## coord * STRIDE and reporting the side the player left through. It knows
## nothing about the clock, the music or the item catalogue — it is handed its
## shelves through [method configure_shop] and reports a sale upward.
##
## Inheriting Room means the scene MUST keep its Tint ColorRect and its Elevator
## child even though this room uses neither: Room._ready and Room.configure reach
## for both unconditionally. That is a permanent requirement, not a temporary
## accommodation — the follow-up that was going to retire KIND_TINTS was dropped
## with the branch that owned it. Delete either node and this room faults on
## contact.

## Somebody bought something. Reported rather than applied: what an item DOES is
## the catalogue's business and who it happens to is Game's, and a room that
## reached for the player's stats would be the one place in the project that
## knew both. Same shape as [signal LevelDoor.player_entered].
signal offer_purchased(offer: ShopOffer)

## The frame, 442 x 240. Shorter than Room.INTERIOR on purpose: 240 is exactly
## what the camera can show at zoom 1.5, so the view is pinned and the authored
## picture is the whole picture. Only possible because Game cuts to this room
## behind a fade instead of sliding — see ElevatorRoom.FRAME.
const FRAME := Rect2(0, 0, 442, 240)

## Room-local rect anything on foot may stand in. A shallow strip along the front
## of the counter: that ratio is what makes the room read side-on rather than
## tilted.
const SHOP_FLOOR := Rect2(49, 191, 343, 49)

## Nearest and furthest the player's origin ever gets, in room-local y. The far
## end is where the counter's collision band stops them — capsule half-height
## above its front face — and the near end is against the lip at the bottom of
## the frame. Everything about depth is measured between these two numbers, so
## they have to be what the COLLISION actually allows rather than what the art
## suggests, or the player finishes growing before they stop walking.
const DEPTH_NEAR_Y := 233.0
const DEPTH_FAR_Y := 191.0

## Stand at least this close to the counter to be offered the prompt. A little
## short of the counter itself, so arriving at it is what triggers the offer
## rather than pressing all the way into it.
const TALK_Y := 199.0
## And within this much of the shopkeeper, in room-local x. Depth alone would
## also be true of the far ends of the counter, where there is nobody to talk to.
const TALK_X := Vector2(186.0, 256.0)

## Push down to here and you leave. Almost against the lip, so leaving is a
## deliberate walk into the bottom of the frame rather than a drift.
const EXIT_Y := 231.0

## Where a player arriving from the previous room is put. Between the talk line
## and the exit line, so neither fires on arrival.
const LANDING := Vector2(221, 216)

@export_group("Shelves")
## The cubbies: how many, how big, where. Change [member ShopGrid.rows] or
## [member ShopGrid.columns] and the planks, the holes and the items are all
## regenerated from it — nothing here is hand-placed.
@export var grid: ShopGrid

@export_group("Perspective")
## Hide the player's gun in here, for the reason ElevatorRoom gives: it is aimed
## with a mouse in a top-down frame and reads as broken side-on.
@export var hide_player_gun: bool = true
## Draw the player bigger near the camera and smaller toward the counter.
@export var depth_scale_enabled: bool = true
## Size at the near edge, closest to the viewport.
@export_range(0.5, 5.0) var depth_scale_near: float = 3.30
## Size against the counter, furthest away. The ratio between the two is the
## illusion; this strip is shallower than the lift lobby's, so the ratio is
## gentler than ElevatorRoom's or the player appears to shrink into the distance
## while walking two steps.
@export_range(0.5, 5.0) var depth_scale_far: float = 2.30
## How much slower depth is than sideways movement. Sideways is untouched.
@export_range(0.1, 1.0) var depth_move_scale: float = 0.30

@export_group("Look")
## How far the nearest plane slides when the player looks all the way to one
## side. Small on purpose — this is a suggestion of depth, not a camera pan.
@export var look_travel: float = 10.0
## Higher is snappier. Low enough that the planes drift rather than track.
@export var look_smoothing: float = 4.0
## Fraction of a half-screen the mouse may sit from centre before it counts as
## looking. See [LookInput].
@export_range(0.0, 0.9) var look_deadzone: float = 0.12

@export_group("Audio")
## Named SFX from AudioManager. Empty plays nothing, and an unknown name plays
## nothing, so none of these can break a build whose audio has not landed yet.
@export var greet_sfx: String = "shopkeeper_greet"
@export var buy_sfx: String = "money_jingle_1"
@export var deny_sfx: String = "wall_collision_1"

@export_group("Art")
## Animation the shopkeeper plays when the player engages him, if his
## SpriteFrames has one.
##
## A seam rather than a dependency. The art shipped four-frame left-arm and
## right-arm animations alongside his idle, but their pivots are not documented
## and hanging them off him by eye reads as a broken puppet — so they are left
## for whoever does the greet properly. Name an animation here and it plays;
## leave it empty, or name one he does not have, and he just keeps idling.
@export var greet_animation: StringName = &""

## Backing colour of an empty cubby.
@export var cubby_color: Color = Color(0.07, 0.08, 0.11, 1.0)
## The shelf planks the cubbies sit on.
@export var plank_color: Color = Color(0.36, 0.27, 0.19, 1.0)
@export var price_color: Color = Color(1.0, 0.87, 0.45, 1.0)
## Price tags go grey once the player cannot afford them, which is the only
## affordability feedback that does not need a line of text.
@export var price_unaffordable_color: Color = Color(0.55, 0.55, 0.58, 1.0)

@onready var _layer_root: Node2D = $Depth
@onready var _shelves: DepthLayer = $Depth/Shelves
@onready var _planks: Node2D = $Depth/Shelves/Planks
@onready var _slots: Node2D = $Depth/Shelves/Slots
@onready var _frame: SelectionFrame = $Depth/Shelves/SelectionFrame
@onready var _talk_prompt: Label = $Depth/Shopkeeper/TalkPrompt
@onready var _keeper: AnimatedSprite2D = $Depth/Shopkeeper/keeper

## Every plane that slides when the player looks around, gathered from the scene
## rather than listed here so adding a plane is a scene edit and not a code one.
var _layers: Array[DepthLayer] = []

## Which grid side walking toward the camera leads back to. Read from the door
## mask in configure(), the same way ElevatorRoom does it.
var _return_side: int = GridDirection.Side.NORTH
## Cleared while something seals the room, and latched once the player leaves so
## a single walk into the bottom edge cannot fire the transition twice.
var _exit_armed: bool = true

## Whoever is standing in the shop, handed over by ShopZone. Physics tells us who
## the player is rather than us reaching up the tree for them.
var _player: Player
## What the player looks like at life size, read on the way in — the BASIS the
## depth scaling multiplies, not a note of what to put back.
var _sprite_scale: Vector2 = Vector2.ONE
var _sprite_offset: Vector2 = Vector2.ZERO
## Half the sprite's height, negated: the offset that puts its bottom edge on the
## body origin. Measured from the art rather than assumed.
var _foot_offset: float = -16.0

## The shelves. Owned by the run, not by this node — see [ShopRegistry].
var _stock: ShopStock
## Whoever is paying. Duck-typed on coins/spend_coins so this room does not name
## the Player class for the one thing the Player does not own yet.
var _purse: Object

var _engaged: bool = false
## Which cubby the frame is on. -1 when nothing is selected.
var _selected: int = -1
## Smoothed look, -1 to 1. Eased rather than snapped, including to zero when the
## player engages — that easing IS the "camera locks dead centre".
var _look: float = 0.0

## Per-cubby node holding the icon and the price tag, or null for an empty
## cubby. The cubby backing itself is not in here: it is a hole in the wall and
## stays put when the thing inside it is sold.
var _contents: Array[Node2D] = []


func _ready() -> void:
	# Deliberately NOT super._ready(): Room's version wires four doorways and a
	# top-down car, none of which this scene has.
	_collect_layers()
	if grid == null:
		# Belt and braces: the scene supplies one, but a ShopRoom dropped into
		# another scene without it should still build rather than crash.
		grid = ShopGrid.new()
	_rebuild_shelves()
	_refresh_coins()


func _exit_tree() -> void:
	# The room is freed the moment the player walks out, and a player who left
	# mid-conversation would be frozen with squashed movement for the rest of the
	# run.
	_release_player()


## Which door this shop was given. A shop is placed at a dead end, so the mask
## has one bit and that bit is the way back.
##
## Deliberately not super.configure(): Room's version walks all four sides
## through door_for() and stands a top-down car against a bare wall.
func configure(data: RoomData) -> void:
	_open_doors = data.doors
	set_locked(false)

	# The inherited top-down car is put away rather than removed. Room reaches
	# for the node unconditionally, so it has to exist.
	_elevator.set_active(false)

	for side in GridDirection.SIDES:
		if data.has_door(side):
			_return_side = side
			return
	push_warning("ShopRoom: configured with no doors, defaulting the way back to north")


## Hand the room its shelves and whoever is paying for what comes off them.
##
## Separate from [method configure] because it answers a question about the RUN
## rather than about the cell: the plan says this cell is a shop, and this says
## what is on its shelves this visit. Both arguments are duck-typed and either
## may be null — a shop with no stock is bare, and one with no purse simply
## refuses every purchase, which is what the harness and the pre-currency build
## both need.
func configure_shop(stock: ShopStock, purse: Object) -> void:
	_stock = stock
	_purse = purse
	_rebuild_shelves()
	_refresh_coins()


## The camera clamp. Overridden because this room is shorter than a standard
## cell: at 240 the view cannot be smaller than the room, so
## PlayerCamera._clamp_axis centres vertically and the frame stops drifting.
func interior_rect() -> Rect2:
	return Rect2(global_position + FRAME.position, FRAME.size)


## Where to put a player who just walked in. There is one way in and out whatever
## side the plan attached it to, so the argument is deliberately ignored.
func spawn_position(_arrive_side: int) -> Vector2:
	return global_position + LANDING


## And the same spot for anyone who did not use the door. Room's version returns
## the middle of its FLOOR rect, which for this room is inside the counter.
func default_spawn_position() -> Vector2:
	return global_position + LANDING


## The one landing this room has. Room's version walks all four sides and would
## fault on the doorways this scene does not have.
func open_door_landings() -> Array[Vector2]:
	return [LANDING]


## Seal the way out, or restore it. Same contract as Room's, with a strip of
## floor standing in for a doorway.
func set_locked(locked: bool) -> void:
	_exit_armed = not locked


## Doors, talking and the way out are all decided from where the player is
## standing rather than from Area2D crossings — the player does not walk into
## this room, they are warped in behind a fade, and a body that appears already
## inside a zone never emits body_entered. See ElevatorRoom._process.
func _process(delta: float) -> void:
	# Browsing is checked BEFORE the is_warping guard below, because engaging
	# sets that very flag to freeze the player. Ordered the other way round, the
	# shop would lock up the instant the player talked to anybody.
	if _engaged:
		_update_look(delta)
		_process_browsing()
		return

	_update_look(delta)

	if _player == null or not is_instance_valid(_player):
		return
	if _player.is_warping or _player.is_dead():
		return

	var local: Vector2 = to_local(_player.global_position)
	_update_depth_scale(local.y)

	var can_talk: bool = _can_talk(local)
	_talk_prompt.visible = can_talk

	if can_talk and Input.is_action_just_pressed("interact"):
		_engage()
		return

	if _exit_armed and local.y >= EXIT_Y:
		# Latched, because the player is still standing in the strip while Game
		# tears the floor down around them.
		_exit_armed = false
		door_entered.emit(_return_side)


func _can_talk(local: Vector2) -> bool:
	return local.y <= TALK_Y and local.x >= TALK_X.x and local.x <= TALK_X.y


# -- Looking around ----------------------------------------------------------


## Gather the planes once. Anything under Depth carrying a DepthLayer script is
## in; anything else is scenery that does not move.
func _collect_layers() -> void:
	_layers.clear()
	for child in _layer_root.get_children():
		var layer := child as DepthLayer
		if layer != null:
			_layers.append(layer)


## Slide every plane by its own share of one shared offset.
##
## The target is zero while engaged, so the planes ease home rather than snapping
## — a hard cut to centre at the moment of engaging would read as a glitch.
func _update_look(delta: float) -> void:
	var target: float = 0.0
	if not _engaged and _player != null and is_instance_valid(_player):
		target = LookInput.horizontal(get_viewport(), _player.aiming_with_gamepad, look_deadzone)

	_look = lerpf(_look, target, 1.0 - exp(-look_smoothing * delta))
	# Negated: pushing right looks right, which means the scenery travels left.
	var offset := Vector2(-_look * look_travel, 0.0)
	for layer in _layers:
		layer.apply_look(offset)


# -- The player --------------------------------------------------------------


## Size the player by how far down the room they are standing.
func _update_depth_scale(depth: float) -> void:
	if not depth_scale_enabled:
		return
	# Yield to the death squash, as ElevatorRoom does: die() tweens this very
	# property and would be fighting us for it every frame.
	if _player.is_dead():
		return

	var t: float = clampf(inverse_lerp(DEPTH_FAR_Y, DEPTH_NEAR_Y, depth), 0.0, 1.0)
	var size: float = lerpf(depth_scale_far, depth_scale_near, t)

	_player.sprite.scale = _sprite_scale * size
	# Anchored by the feet and scaled with her, so growing happens upward from
	# the floor instead of in both directions.
	_player.sprite.position = Vector2(_sprite_offset.x, _foot_offset * size)


func _on_shop_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null:
		return
	_player = player
	_sprite_scale = player.sprite.scale
	_sprite_offset = player.sprite.position
	_foot_offset = _measure_foot_offset(player)
	# Sideways is left alone. Only depth is slowed, because only depth is lying
	# about how far it goes.
	player.move_scale = Vector2(1.0, depth_move_scale)
	if hide_player_gun:
		player.gun.visible = false


func _on_shop_exited(body: Node2D) -> void:
	if body is Player:
		_release_player()


## Half the height of a frame of the player's art, negated. Read off the sprite
## so that art of a different size still stands on the floor rather than in it.
func _measure_foot_offset(player: Player) -> float:
	var frames: SpriteFrames = player.sprite.sprite_frames
	if frames == null:
		return _foot_offset
	var anim: StringName = player.sprite.animation
	if not frames.has_animation(anim) or frames.get_frame_count(anim) == 0:
		return _foot_offset
	var texture: Texture2D = frames.get_frame_texture(anim, 0)
	if texture == null:
		return _foot_offset
	return -texture.get_height() * 0.5


## Hand the player back exactly as she arrived.
##
## Unconditional and safe to call more than once. Everything this room changed
## about her appearance is restored from her own authored values by
## reset_presentation, but the freeze is NOT — is_warping is ours, we set it, and
## nothing else will put it back. A path that misses this leaves a player who
## cannot move for the rest of the run.
func _release_player() -> void:
	if _player == null:
		return
	if is_instance_valid(_player):
		if _engaged and not _player.is_dead():
			# Not cleared while dead: die() owns what a corpse is allowed to do,
			# and handing control back to one would undo it.
			_player.is_warping = false
		_player.reset_presentation()
	_engaged = false
	_selected = -1
	_player = null


# -- Talking to the shopkeeper -----------------------------------------------


func _engage() -> void:
	_play_sfx(greet_sfx)
	_play_greet_animation()
	if _stock == null or _stock.is_empty():
		# Sold out. He still grunts at you — being told there is nothing left is
		# better than a button that appears to do nothing.
		return

	_engaged = true
	_talk_prompt.visible = false
	_player.velocity = Vector2.ZERO
	# is_warping rather than can_move: bomb, shoot and reload are all polled
	# OUTSIDE player.gd's can_move block, so a can_move freeze would still let
	# Space detonate a bomb while the player reads price tags. is_warping returns
	# out of _physics_process at the top and suppresses all of them, and it is
	# the flag ElevatorRoom._board already uses for exactly this.
	_player.is_warping = true

	_select(_stock.first_populated())


func _disengage() -> void:
	if not _engaged:
		return
	_engaged = false
	_selected = -1
	_frame.clear_cell()
	if _player != null and is_instance_valid(_player) and not _player.is_dead():
		_player.is_warping = false


func _process_browsing() -> void:
	if _player == null or not is_instance_valid(_player):
		_disengage()
		return

	if Input.is_action_just_pressed("back"):
		_disengage()
		return

	if Input.is_action_just_pressed("interact"):
		_buy()
		return

	var dx: int = 0
	var dy: int = 0
	if Input.is_action_just_pressed("ui_right"):
		dx = 1
	elif Input.is_action_just_pressed("ui_left"):
		dx = -1
	elif Input.is_action_just_pressed("ui_down"):
		dy = 1
	elif Input.is_action_just_pressed("ui_up"):
		dy = -1
	# One axis per press, deliberately: two directions in the same frame would
	# move the selection diagonally for a single input.
	if dx != 0 or dy != 0:
		_select(_stock.next_populated(_selected, dx, dy, grid))


func _select(index: int) -> void:
	_selected = index
	if index < 0 or grid == null:
		_frame.clear_cell()
		return
	_frame.set_cell(grid.cell_rect(index))


func _buy() -> void:
	if _stock == null or _selected < 0:
		return
	var offer: ShopOffer = _stock.offer_at(_selected)
	if offer == null:
		return

	# spend_coins is the single gate rather than "can afford, then spend": two
	# calls can disagree, one cannot.
	if not _spend(offer.price):
		_play_sfx(deny_sfx)
		_frame.deny()
		return

	_stock.take(_selected)
	_clear_contents(_selected)
	_refresh_coins()
	_play_sfx(buy_sfx)
	offer_purchased.emit(offer)

	if _stock.is_empty():
		_disengage()
		return
	# Step to whatever is left rather than sitting on the hole just created.
	_select(_stock.next_populated(_selected, 1, 0, grid))


# -- Money -------------------------------------------------------------------
#
# Coins live on the Player and are shipped by another branch. Both of these are
# duck-typed so this room works before that lands and needs no edit after it: an
# absent purse simply cannot afford anything.


func _balance() -> int:
	if _purse == null or not ("coins" in _purse):
		return 0
	return int(_purse.coins)


func _spend(amount: int) -> bool:
	if _purse == null or not _purse.has_method("spend_coins"):
		return false
	return bool(_purse.spend_coins(amount))


## The balance itself is drawn by the HUD's CoinCounter, which is always on
## screen and wired to the player's coins_changed. This room deliberately does
## not draw it a second time — it only re-reads it, to decide which price tags
## the player can afford.
func _refresh_coins() -> void:
	_refresh_price_colors()


# -- The shelves -------------------------------------------------------------


## Build the planks, the cubbies and whatever is sitting in them.
##
## Everything is generated from [member grid], so resizing the shelf is one
## number in the inspector. Called again whenever the stock changes, and safe to
## call before the stock exists — that just builds empty cubbies.
func _rebuild_shelves() -> void:
	for child in _planks.get_children():
		child.queue_free()
	for child in _slots.get_children():
		child.queue_free()
	_contents.clear()

	if grid == null or grid.capacity() <= 0:
		return

	for row in grid.rows:
		_planks.add_child(_make_plank(row))

	_contents.resize(grid.capacity())
	for index in grid.capacity():
		var cell: Rect2 = grid.cell_rect(index)
		_slots.add_child(_make_cubby(cell))

		var offer: ShopOffer = null
		if _stock != null:
			offer = _stock.offer_at(index)
		if offer == null:
			continue
		var content := _make_contents(cell, offer)
		_slots.add_child(content)
		_contents[index] = content


func _make_plank(row: int) -> ColorRect:
	var rect: Rect2 = grid.row_rect(row)
	var plank := ColorRect.new()
	plank.name = "plank_%d" % row
	# Sat under the row of cubbies rather than behind it, so the items read as
	# standing ON something.
	plank.position = rect.position + Vector2(-1.0, rect.size.y)
	plank.size = Vector2(rect.size.x + 2.0, 3.0)
	plank.color = plank_color
	plank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return plank


func _make_cubby(cell: Rect2) -> ColorRect:
	var cubby := ColorRect.new()
	cubby.position = cell.position
	cubby.size = cell.size
	cubby.color = cubby_color
	cubby.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cubby


## The icon and the price tag, in one node so a sale frees both together and the
## hole in the wall stays behind.
func _make_contents(cell: Rect2, offer: ShopOffer) -> Node2D:
	var content := Node2D.new()

	# Backdrop behind, icon in front, both at the scales the ItemDef authored, and
	# the pair shrunk together if they would not fit the cubby. Drawing the item
	# the way a drop draws it is the point: the thing on the shelf has to be
	# recognisably the thing you find on the floor, so the shop reads icon_scale
	# and backdrop rather than fitting the bare texture to the cell.
	var item: ItemDef = offer.item
	if item != null:
		var centre: Vector2 = cell.get_center() - Vector2(0.0, 2.0)
		var fit: float = _cubby_fit(item, cell)
		if item.backdrop != null:
			content.add_child(
				_item_sprite(item.backdrop, item.backdrop_scale * fit, centre))
		if item.icon != null:
			content.add_child(_item_sprite(item.icon, item.icon_scale * fit, centre))

	var tag := Label.new()
	tag.text = str(offer.price)
	tag.position = cell.position + Vector2(0.0, cell.size.y - 9.0)
	tag.size = Vector2(cell.size.x, 9.0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Sized in code rather than through a theme because the project has none —
	# see assets/themes, which holds only a .gitkeep.
	tag.add_theme_font_size_override("font_size", 8)
	tag.add_theme_color_override("font_color", price_color)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(tag)

	return content


## One layer of an item's picture, centred in its cubby.
func _item_sprite(texture: Texture2D, scale_factor: float, centre: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = centre
	sprite.scale = Vector2.ONE * scale_factor
	return sprite


## How much to shrink an item so its widest authored layer fits the cubby.
##
## Never above 1.0: the authored scale is the item at the size it is meant to be
## drawn, and blowing a nearest-neighbour sprite up past that next to one drawn
## at 1x looks like a mistake. Returns 1.0 when it already fits, which is the
## common case — this only bites for an item authored larger than the shelf.
func _cubby_fit(item: ItemDef, cell: Rect2) -> float:
	var widest := 0.0
	if item.icon != null:
		widest = maxf(widest, _longest_side(item.icon) * item.icon_scale)
	if item.backdrop != null:
		widest = maxf(widest, _longest_side(item.backdrop) * item.backdrop_scale)
	if widest <= 0.0:
		return 1.0
	return minf(1.0, minf(cell.size.x, cell.size.y) / widest)


func _longest_side(texture: Texture2D) -> float:
	var size: Vector2 = texture.get_size()
	return maxf(size.x, size.y)


func _clear_contents(index: int) -> void:
	if index < 0 or index >= _contents.size():
		return
	var content: Node2D = _contents[index]
	if content != null and is_instance_valid(content):
		content.queue_free()
	_contents[index] = null


## Grey out what the player cannot afford. The only affordability feedback that
## costs no screen space, which in a 442x240 frame is the whole argument.
func _refresh_price_colors() -> void:
	if _stock == null:
		return
	var balance: int = _balance()
	for index in _contents.size():
		var content: Node2D = _contents[index]
		if content == null or not is_instance_valid(content):
			continue
		var offer: ShopOffer = _stock.offer_at(index)
		if offer == null:
			continue
		for child in content.get_children():
			var tag := child as Label
			if tag == null:
				continue
			var affordable: bool = balance >= offer.price
			tag.add_theme_color_override(
				"font_color", price_color if affordable else price_unaffordable_color)


## The other half of the [member greet_animation] seam. Guarded on both the name
## and whether he actually has it, so an empty slot or a stale name costs nothing
## and he simply keeps idling.
func _play_greet_animation() -> void:
	if greet_animation.is_empty() or _keeper.sprite_frames == null:
		return
	if not _keeper.sprite_frames.has_animation(greet_animation):
		return
	_keeper.play(greet_animation)


## Guarded because audio_manager.gd indexes its dictionary directly and will hard
## error on a name it does not have. Registering the shop's sounds is the audio
## branch's job; this one only ever asks for them by name.
func _play_sfx(sound: String) -> void:
	if sound.is_empty() or not AudioManager.sounds.has(sound):
		return
	AudioManager.play_sfx(sound)
