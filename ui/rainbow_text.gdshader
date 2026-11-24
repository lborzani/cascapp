// O nome em arco-íris (`Cosmetics`, encaixe `name_color`, item `name_rainbow`)
// num `Label`: a cor anda com o x local do texto, então cada letra sai de uma
// cor. O alfa do glifo continua o do texto.
shader_type canvas_item;

varying float across;

void vertex() {
	across = VERTEX.x;
}

void fragment() {
	float hue = fract(across / 150.0);
	vec3 rainbow = clamp(abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	COLOR.rgb = mix(rainbow, vec3(1.0), 0.2);
}
