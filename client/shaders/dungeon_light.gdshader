shader_type canvas_item;

// Dungeon lighting: a torch radius around the player, plus light from lamps and braziers.
//
// Owner's design (2026-09-10): darkness is a property OF THE DUNGEON, not a resource the player
// carries. A normal dungeon is gently lit - `ambient` 0.62 - so there is nothing to manage and
// nothing is hidden. A dungeon flagged dark drops `ambient` and lamps become navigation.
//
// This draws DARKNESS, not light: it is a black overlay whose alpha is highest where the light
// is weakest. That way the tiles underneath keep their own colour instead of being multiplied
// toward a tint, which is the mistake that stained floors when sprites were `color=`-tinted.

// Where the light comes from, in canvas UV. NOT assumed to be the centre: the dungeon viewport
// clamps at floor edges, so the player is off-centre whenever the floor runs out.
uniform vec2 player_uv = vec2(0.5, 0.5);

// Extra light sources (lamps, braziers, lava) in canvas UV.
const int MAX_LIGHTS = 24;
uniform vec2 lights[MAX_LIGHTS];
uniform int light_count = 0;

// How bright the unlit floor stays. 1.0 disables the effect entirely.
uniform float ambient : hint_range(0.0, 1.0) = 0.62;

// Radii as a fraction of canvas WIDTH, so they are resolution independent.
uniform float torch_radius = 0.30;
uniform float lamp_radius = 0.14;
uniform float lamp_strength : hint_range(0.0, 1.0) = 1.0;

// canvas width / height. Without it a circle becomes an ellipse on a wide canvas.
uniform float aspect = 1.0;

float falloff(vec2 uv, vec2 c, float r) {
	vec2 d = vec2(uv.x - c.x, (uv.y - c.y) / aspect);
	float t = clamp((length(d) - r * 0.45) / (r * 0.85), 0.0, 1.0);
	return 1.0 - (t * t * (3.0 - 2.0 * t));   // smoothstep, 1 at the centre
}

void fragment() {
	float light = ambient + (1.0 - ambient) * falloff(UV, player_uv, torch_radius);
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) {
			break;
		}
		float l = ambient + (1.0 - ambient) * falloff(UV, lights[i], lamp_radius) * lamp_strength;
		light = max(light, l);
	}
	COLOR = vec4(0.0, 0.0, 0.0, clamp(1.0 - light, 0.0, 1.0));
}
