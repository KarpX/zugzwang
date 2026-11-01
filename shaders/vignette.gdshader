shader_type canvas_item;

// Настройки виньетки паники и тяжелого дыхания (Белый Король)
uniform float vignette_intensity : hint_range(0.0, 3.0) = 1.15;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.02, 0.01, 0.015, 1.0);
uniform float pulse_speed : hint_range(0.5, 6.0) = 2.4;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.09;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);
	
	// Органическая пульсация в такт дыханию
	float pulse = sin(TIME * pulse_speed) * pulse_amount * vignette_opacity;
	float inner_radius = clamp(0.28 - pulse, 0.05, 0.8);
	float outer_radius = clamp(0.72 - pulse, 0.2, 1.2);
	
	float factor = smoothstep(inner_radius, outer_radius, dist * vignette_intensity);
	COLOR = vec4(vignette_color.rgb, factor * vignette_opacity);
}
