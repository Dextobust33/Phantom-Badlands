shader_type canvas_item;

// v0.9.672 — per-region equipment tint. Recolors up to 3 horizontal bands of a
// character sprite (helm=top / armor=mid / boots=bottom) toward an equipped
// piece's colour, respecting the sprite's alpha so only the character (not the
// transparent padding) is tinted. band* = (y_min, y_max) in UV space; band*_col
// rgb = tint colour, a = blend strength. Composed with COLOR at the end so the
// per-character self_modulate tint + combat FX modulate still apply on top.

uniform vec4 band0 = vec4(0.0);
uniform vec4 band0_col = vec4(0.0);
uniform vec4 band1 = vec4(0.0);
uniform vec4 band1_col = vec4(0.0);
uniform vec4 band2 = vec4(0.0);
uniform vec4 band2_col = vec4(0.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 c = tex.rgb;
	if (tex.a > 0.02) {
		if (band0_col.a > 0.0 && UV.y >= band0.x && UV.y < band0.y)
			c = mix(c, band0_col.rgb, band0_col.a);
		if (band1_col.a > 0.0 && UV.y >= band1.x && UV.y < band1.y)
			c = mix(c, band1_col.rgb, band1_col.a);
		if (band2_col.a > 0.0 && UV.y >= band2.x && UV.y < band2.y)
			c = mix(c, band2_col.rgb, band2_col.a);
	}
	COLOR = vec4(c, tex.a) * COLOR;
}
