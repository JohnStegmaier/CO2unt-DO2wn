shader_type canvas_item;

// Closing darkness for the moment the air runs out. Drawn over a full-screen
// ColorRect; death_overlay.gd drives `progress` from 0 to 1.
//
// At progress 0 the whole screen is clear. As it rises the black creeps in from
// the corners toward the centre, and at 1 the last pinhole shuts. The radius is
// measured in a squashed space so the hole stays round on a 16:9 viewport
// instead of stretching into an ellipse.

// 0 = clear, 1 = fully closed.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// How wide the blur between clear and black is, in UV units. Small values give
// a hard iris, large ones a soft haze.
uniform float softness : hint_range(0.001, 1.0) = 0.45;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Viewport aspect, so the hole is a circle rather than an ellipse.
uniform float aspect = 1.7777778;

void fragment() {
	vec2 centred = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	// Normalised so 1.0 is the far corner: at progress 0 the clear radius is
	// past the corner and nothing is tinted at all.
	float distance_from_centre = length(centred) / (0.5 * sqrt(aspect * aspect + 1.0));

	// The clear radius travels from just past the corner to below zero, so the
	// final frame is solid rather than leaving a bright pinhole behind.
	float clear_radius = mix(1.0 + softness, -softness, progress);
	float darkness = smoothstep(clear_radius, clear_radius + softness, distance_from_centre);

	COLOR = vec4(vignette_color.rgb, vignette_color.a * darkness);
}
