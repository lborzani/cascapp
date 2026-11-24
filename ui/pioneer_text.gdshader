// O nome dos testadores (`Cosmetics`, item `name_pioneer`) num `Label`: menta,
// violeta e ouro (`ProfileStyle.PIONEER`) correndo pelas letras, com uma
// cintilação branca que passa de tempos em tempos. O alfa do glifo continua o
// do texto.
shader_type canvas_item;

varying float across;

const vec3 MINT = vec3(0.24, 1.0, 0.82);
const vec3 VIOLET = vec3(0.65, 0.42, 1.0);
const vec3 GOLD = vec3(1.0, 0.82, 0.35);

void vertex() {
	across = VERTEX.x;
}

void fragment() {
	float at = fract(across / 150.0 - TIME * 0.25) * 3.0;
	vec3 colour = at < 1.0 ? mix(MINT, VIOLET, at) : at < 2.0 ? mix(VIOLET, GOLD, at - 1.0) : mix(GOLD, MINT, at - 2.0);
	// A cintilação anda 160 px por segundo e volta a cada 5 s.
	float glint = exp(-pow((across - (mod(TIME, 5.0) * 160.0 - 60.0)) / 14.0, 2.0));
	COLOR.rgb = mix(colour, vec3(1.0), glint * 0.8);
}
