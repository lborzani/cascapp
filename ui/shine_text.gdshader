// O título dos testadores (`Cosmetics`, item com `shine`) num `Label`: ouro que
// ondula para o âmbar ao longo do texto, com um reflexo branco que atravessa as
// letras em laço. O alfa do glifo continua o do texto.
shader_type canvas_item;

varying float across;

void vertex() {
	across = VERTEX.x;
}

void fragment() {
	vec3 gold = mix(vec3(1.0, 0.86, 0.42), vec3(1.0, 0.62, 0.3), 0.5 + 0.5 * sin(across / 38.0 + TIME * 1.3));
	// O reflexo anda 130 px por segundo e volta a cada 4 s.
	float glint = exp(-pow((across - (mod(TIME, 4.0) * 130.0 - 60.0)) / 16.0, 2.0));
	COLOR.rgb = mix(gold, vec3(1.0), glint * 0.85);
}
