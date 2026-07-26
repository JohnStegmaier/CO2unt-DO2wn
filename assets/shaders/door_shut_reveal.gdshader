shader_type canvas_item;

// Wipe reveal for a door sliding shut. room.gd drives `reveal` from 0 to 1 in
// step with the door's own slide, so nothing of the sprite is ever drawn
// ahead of where the door has actually reached — no part of it shows before
// that part has passed the doorway's starting edge.
//
// `axis`/`from_end` pick which edge the reveal grows from, set once per side
// in room.gd: the north and south doors reveal along Y, east and west along
// X, each starting from whichever edge faces the direction that door travels.

uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform int axis = 1; // 0 = X (east/west doors), 1 = Y (north/south doors)
uniform bool from_end = false; // true reveals from UV 1.0 backward, false from UV 0.0 forward

void fragment() {
	float coord = axis == 0 ? UV.x : UV.y;
	float distance_from_leading_edge = from_end ? (1.0 - coord) : coord;
	if (distance_from_leading_edge > reveal) {
		discard;
	}
	COLOR = texture(TEXTURE, UV);
}
