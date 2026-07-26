shader_type canvas_item;

// A flat-color ring, computed from UV distance rather than baked into a
// texture. bullet.gd's Outline tried a GradientTexture2D radial fill first —
// at the size an enemy shot actually draws at, minifying that baked gradient
// left it a blocky rounded square no filter setting fixed. Distance from the
// pixel to the sprite's own centre has no source resolution to alias against,
// so this stays a circle at any size. The Sprite2D still needs SOME texture
// assigned for Godot to give it a quad to draw into — this ignores that
// texture's content entirely and only uses UV.

uniform vec4 ring_color : source_color = vec4(0.1, 0.0, 0.0, 1.0);
uniform float inner_radius : hint_range(0.0, 0.5) = 0.3;
uniform float outer_radius : hint_range(0.0, 0.5) = 0.5;
// In UV units. Small values keep the ring crisp; larger ones give it a soft
// feathered edge instead of a hard one.
uniform float softness : hint_range(0.0, 0.1) = 0.015;

void fragment() {
	float d = length(UV - vec2(0.5));
	float inside_outer = smoothstep(outer_radius, outer_radius - softness, d);
	float outside_inner = smoothstep(inner_radius, inner_radius + softness, d);
	COLOR = vec4(ring_color.rgb, ring_color.a * inside_outer * outside_inner);
}
