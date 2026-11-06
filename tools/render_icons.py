"""Ícones 3D dos jogos, renderizados no Blender a partir das peças do próprio jogo.

    blender -b --factory-startup -P tools/render_icons.py

Sai em assets/icons/<jogo>.png. Depois de rodar, o Godot precisa importar os
PNGs novos (`godot --headless --path . --editor --quit`).

O ícone parte do mesmo SVG que o tabuleiro desenha (assets/pieces/): o contorno
vira o corpo da peça, extrudado e chanfrado, e o miolo claro sobe um pouco por
cima dele — o traço do desenho vira um sulco. Assim o ícone é a peça do jogo com
volume, e não um desenho novo que divergiria dela.

Não há .blend: a cena inteira sai deste script, que é o que vai para o Git e o
que se compara num diff. Mesma versão do Blender, mesmo PNG (semente fixa,
render na CPU).
"""

import os
import struct

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "icons")
# Lado do PNG. Três vezes o maior lugar em que o ícone aparece (a bolacha da
# folha do jogo, ~64 px): abaixo disso o celular denso estica e borra.
SIZE = 192

# jogo -> peça em assets/pieces
ICONS = {
    "chess": "knight_white.svg",
}

# Marfim de plástico no miolo, o branco das peças do tabuleiro um tom mais
# quente; latão no contorno, o dourado do chopp que anela as bolachas
# (`AppTheme.GOLD`). Valores lineares, não sRGB.
IVORY = (0.80, 0.76, 0.66, 1.0)
BRASS = (0.62, 0.36, 0.09, 1.0)
DEPTH = 0.16  # espessura do corpo, em fração da altura da peça
RAISE = 0.05  # quanto o miolo sobe acima do contorno


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 256
    scene.cycles.seed = 0
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("mundo")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.25
    scene.world = world


def plastic(name, color, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = 0.3 if metallic else 0.4
    shader.inputs["Coat Weight"].default_value = 0.0 if metallic else 0.3
    return material


def piece(svg):
    """Importa o SVG e devolve a peça em pé, com volume e altura 1."""
    before = set(bpy.data.objects)
    bpy.ops.import_curve.svg(filepath=svg)
    curves = [o for o in bpy.data.objects if o not in before]
    # O SVG tem dois caminhos: o contorno escuro (o maior) e o miolo claro.
    curves.sort(key=lambda o: o.dimensions.x * o.dimensions.y, reverse=True)
    bpy.context.view_layer.update()
    # O SVG entra em metros minúsculos (72 px = 0,02 m); tudo sai proporcional a
    # esta altura, e a escala volta para 1 no fim.
    height = curves[0].dimensions.y
    rim = plastic("latão", BRASS, metallic=1.0)
    face = plastic("marfim", IVORY)
    for index, curve in enumerate(curves):
        curve.data.extrude = height * (DEPTH * 0.5 if index == 0 else RAISE * 0.5)
        curve.data.materials.clear()
        curve.data.materials.append(rim if index == 0 else face)
        curve.location.z += 0.0 if index == 0 else height * (DEPTH + RAISE) * 0.5
    bpy.ops.object.select_all(action="DESELECT")
    for curve in curves:
        curve.select_set(True)
    bpy.context.view_layer.objects.active = curves[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bevel = obj.modifiers.new("chanfro", "BEVEL")
    bevel.width = height * 0.018
    bevel.segments = 4
    bevel.limit_method = "ANGLE"
    bpy.ops.object.shade_smooth_by_angle()
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    obj.location = (0.0, 0.0, 0.0)
    obj.scale = (1.0 / height,) * 3
    # Em pé, virada um pouco para a direita: três quartos mostra a espessura.
    obj.rotation_euler = (1.5708, 0.0, -0.38)
    return obj


def stage(target):
    bpy.context.view_layer.update()
    dims = target.dimensions
    camera_data = bpy.data.cameras.new("camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(dims.x, dims.z, dims.y) * 1.55
    camera = bpy.data.objects.new("camera", camera_data)
    # Três quartos, de leve: o bastante para o chanfro e a espessura aparecerem,
    # pouco para o perfil continuar sendo o perfil da peça.
    camera.location = (0.9, -4.0, 0.55)
    bpy.context.collection.objects.link(camera)
    track = camera.constraints.new("TRACK_TO")
    track.target = target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    bpy.context.scene.camera = camera

    # Luz macia de cima e da esquerda, como a de Metrópole, e um recorte frio por
    # trás para a silhueta descolar do fundo escuro da bolacha.
    for name, location, energy, size, color in [
        ("chave", (-2.0, -2.5, 3.0), 260.0, 2.5, (1.0, 0.96, 0.9)),
        ("recorte", (2.5, 2.5, 1.5), 140.0, 1.5, (0.8, 0.88, 1.0)),
    ]:
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.size = size
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        light.location = location
        bpy.context.collection.objects.link(light)
        aim = light.constraints.new("TRACK_TO")
        aim.target = target
        aim.track_axis = "TRACK_NEGATIVE_Z"
        aim.up_axis = "UP_Y"


def strip_text(path):
    """Tira os blocos de texto do PNG. O Cycles grava neles o tempo de render,
    que muda a cada rodada: pixels iguais, bytes diferentes, e o controle de
    versão via todo ícone como alterado."""
    data = open(path, "rb").read()
    out, index = [data[:8]], 8
    while index < len(data):
        length, kind = struct.unpack(">I4s", data[index:index + 8])
        end = index + 12 + length
        if kind not in (b"tEXt", b"zTXt", b"iTXt", b"tIME"):
            out.append(data[index:end])
        index = end
    open(path, "wb").write(b"".join(out))


def main():
    os.makedirs(OUT, exist_ok=True)
    for game, svg in ICONS.items():
        reset()
        target = piece(os.path.join(ROOT, "assets", "pieces", svg))
        stage(target)
        path = os.path.join(OUT, game + ".png")
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        strip_text(path)
        print("ícone", game)


main()
