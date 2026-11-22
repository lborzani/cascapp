// O taco da loja (`Cosmetics`, encaixe `cue`). O `cue.glb` não tem UV, então a
// textura (`tools/build_cue_skins.gd`) é projetada pela posição local: x ao
// longo do taco, da ponta (0) ao fim do cabo (1), e o ângulo em volta dele. A
// emenda do ângulo fica embaixo (-Y), virada para o pano. O alfa é o contrário
// do metal.
shader_type spatial;

uniform sampler2D skin : source_color, filter_linear_mipmap, repeat_enable;
uniform float cue_length = 1.15;
// O quanto a cor brilha sozinha (o neon); 0 nos outros.
uniform float glow = 0.0;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 uv = vec2(local.x / cue_length, atan(local.z, local.y) / TAU + 0.5);
	vec4 color = texture(skin, uv);
	float metal = 1.0 - color.a;
	ALBEDO = color.rgb;
	// Não 1: a mesa não tem nada em volta para o metal refletir, e o ouro puro
	// saía marrom-escuro.
	METALLIC = metal * 0.6;
	ROUGHNESS = mix(0.38, 0.22, metal);
	EMISSION = color.rgb * glow;
}
