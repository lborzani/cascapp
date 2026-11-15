"""Gera a pista, os pinos e a bola do boliche em 3D, do zero.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python art/bowling/build_bowling.py

Saídas:
- art/bowling/bowling.blend    a cena montada, para abrir e mexer à mão;
- assets/bowling/lane.glb      pista, aproximação, canaletas, deck, poço e máquina;
- assets/bowling/pin.glb       um pino, base na origem;
- assets/bowling/ball.glb      a bola, centro na origem (a cor de cada jogador vem da Godot,
                               multiplicando a textura cinza de mármore);
- art/bowling/renders/*.png    renders de aprovação.

Escala 1:1, em metros, com as medidas oficiais. A linha de falta é y = 0 e a pista
corre para +y no Blender; o export glTF (Y para cima) devolve isso como -Z na
Godot, que é a frente da câmera. O x (lado) é o mesmo nos dois, e o tampo da
pista é a altura 0.
"""

import math
import os
import sys

import bpy
import bmesh
import mathutils
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # sem __pycache__ dentro de art/pool
sys.path.insert(0, os.path.join(HERE, "..", "pool"))
import build_pool as kit  # noqa: E402  só as funções; a sinuca não roda no import

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "bowling")
RENDERS = os.path.join(HERE, "renders")

# --- medidas oficiais (as mesmas que a física da Godot vai usar) --------------

LANE_W = 1.0541          # 41,5 pol, 39 tábuas
BOARDS = 39
HEAD_PIN = 18.288        # 60 pés da linha de falta ao centro do pino 1
PIN_SPACING = 0.3048     # 12 pol entre centros
DECK_END = 19.16         # fim do deck: 60 pés + 2 pés 10 3/16 pol
GUTTER_W = 0.235         # 9,25 pol
GUTTER_DEPTH = 0.048
BALL_R = 0.109           # 8,5 pol de diâmetro
PIN_H = 0.381            # 15 pol

# --- medidas só do desenho ----------------------------------------------------

APPROACH = 3.0           # quanto da aproximação aparece antes da linha de falta
CAP_W = 0.08             # divisória depois da canaleta
CAP_H = 0.03
PIT_DEPTH = 0.30
PIT_LEN = 0.9
KICKBACK_T = 0.04
KICKBACK_H = 0.75
MASK_FRONT = HEAD_PIN - 0.5
MASK_BOTTOM = 0.62
MASK_TOP = 1.25
WOOD_TILE = 3.0          # metros de pista que a textura cobre antes de repetir
MAPLE = (0.88, 0.72, 0.50)

# Cores do app (ui/app_theme.gd): a máquina usa a superfície e o detalhe lima.
SURFACE = "211c40"
ACCENT = "c8f53c"

# Perfil do pino, em polegadas: (altura, diâmetro). Aproxima a tabela da USBC;
# a cabeça é meia esfera de 1,273 pol de raio.
PIN_PROFILE_IN = [
    (0.0, 2.031), (0.375, 2.50), (0.75, 2.828), (1.5, 3.40), (2.25, 3.906),
    (3.375, 4.510), (4.5, 4.766), (5.875, 4.563), (7.25, 3.703), (8.625, 2.472),
    (9.375, 1.965), (10.0, 1.797), (10.875, 1.870), (11.75, 2.142), (12.5, 2.40),
]
HEAD_R_IN = 1.273
STRIPES_IN = [(9.0, 9.45), (10.15, 10.6)]


def board_x(n):
    """Centro da tábua n (1 a 39, contando da direita de quem joga)."""
    bw = LANE_W / BOARDS
    return LANE_W / 2 - (n - 0.5) * bw


def pin_spots():
    """Os dez pinos em (x, y), na ordem oficial: 1 na frente, 7 a 10 da esquerda para a direita."""
    dy = PIN_SPACING * math.sin(math.radians(60))
    spots = []
    for row in range(4):
        for i in range(row + 1):
            spots.append(((i - row / 2) * PIN_SPACING, HEAD_PIN + row * dy))
    return spots


# --- texturas -----------------------------------------------------------------

def lane_texture(w=512, h=1024):
    """Tábuas de maple ao longo da pista: 39 tábuas na largura, WOOD_TILE metros na altura."""
    rng = np.random.default_rng(21)
    board_px = w / BOARDS
    cols = np.arange(w)
    board = np.minimum((cols / board_px).astype(int), BOARDS - 1)
    tone = rng.random(BOARDS) * 0.10 - 0.05
    streaks = rng.random((1, w)) * 0.05                      # fibra corrida ao longo da tábua
    clouds = (kit.smooth_noise(h, w, 4, rng) - 0.5) * 0.08    # manchas largas
    fine = (kit.smooth_noise(h, w, 48, rng) - 0.5) * 0.03
    light = 1.0 + tone[board][None, :] + streaks + clouds + fine
    seam = ((cols % board_px) < 1.0)[None, :]
    light = np.where(seam, light * 0.78, light)
    rgb = np.clip(np.array(MAPLE)[None, None, :] * light[..., None], 0, 1)
    return np.dstack([rgb, np.ones((h, w))])


def marble_texture(h=256, w=512):
    """Mármore cinza claro, função da direção 3D de cada texel (sem costura)."""
    d = kit.sphere_dirs(h, w)
    x, y, z = d[..., 0], d[..., 1], d[..., 2]
    warp = np.sin(3.1 * x + 1.3) * np.cos(2.7 * y - 0.4) + 0.6 * np.sin(4.3 * z + 2.1 * x)
    swirl = np.sin(6.0 * (0.6 * x + 0.35 * y + 0.7 * z) + 2.2 * warp)
    value = 0.72 + 0.28 * swirl
    return np.dstack([value, value, value, np.ones((h, w))])


# --- geometria ----------------------------------------------------------------

def face_up(bm):
    for f in bm.faces:
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()


def box(bm, x0, y0, x1, y1, z0, z1):
    bmesh.ops.create_cube(bm, size=1.0, matrix=mathutils.Matrix.LocRotScale(
        ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), None, (x1 - x0, y1 - y0, z1 - z0)))


def flat(bm, points, z):
    face = bm.faces.new([bm.verts.new((x, y, z)) for x, y in points])
    return face


def disc(bm, x, y, r, z, segments=12):
    flat(bm, [(x + r * math.cos(a), y + r * math.sin(a))
              for a in np.linspace(0, math.tau, segments, endpoint=False)], z)


def lane_uv(obj):
    me = obj.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name="UVMap").data
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = (co.x / LANE_W + 0.5, co.y / WOOD_TILE)


def build_lane(col, mats):
    outer = LANE_W / 2 + GUTTER_W          # borda de fora da canaleta
    cap_out = outer + CAP_W
    objs = []

    # Madeira: pista até o fim do deck, e a aproximação larga antes da linha.
    bm = bmesh.new()
    box(bm, -LANE_W / 2, 0.0, LANE_W / 2, DECK_END, -0.06, 0.0)
    box(bm, -cap_out, -APPROACH, cap_out, 0.0, -0.06, 0.0)
    wood = kit.mesh_object("lane_wood", bm, col, [mats["wood"]])
    lane_uv(wood)
    objs.append(wood)

    # Marcas: linha de falta, setas, pontos e o lugar de cada pino.
    bm = bmesh.new()
    z = 0.002
    flat(bm, [(-cap_out, -0.012), (cap_out, -0.012), (cap_out, 0.0), (-cap_out, 0.0)], z)
    bw = LANE_W / BOARDS
    for n, tip in [(5, 3.962), (10, 4.267), (15, 4.572), (20, 4.877),
                   (25, 4.572), (30, 4.267), (35, 3.962)]:
        x = board_x(n)
        flat(bm, [(x - bw * 0.42, tip - 0.16), (x + bw * 0.42, tip - 0.16), (x, tip)], z)
    for n in (3, 5, 8, 11, 14, 26, 29, 32, 35, 37):
        disc(bm, board_x(n), 2.134, 0.008, z)
    for y in (-0.12, -2.4):
        for n in (3, 5, 8, 11, 14, 20, 26, 29, 32, 35, 37):
            disc(bm, board_x(n), y, 0.009, z)
    for x, y in pin_spots():
        disc(bm, x, y, 0.026, z, 16)
    face_up(bm)
    objs.append(kit.mesh_object("marks", bm, col, [mats["mark"]], recalc=False))

    # Canaletas: meia-cana de y = 0 até o poço.
    bm = bmesh.new()
    steps = 12
    for side in (-1, 1):
        rows = []
        for y in (0.0, DECK_END):
            row = []
            for i in range(steps + 1):
                t = i / steps
                x = side * (LANE_W / 2 + GUTTER_W * t)
                row.append(bm.verts.new((x, y, -GUTTER_DEPTH * math.sin(math.pi * t))))
            rows.append(row)
        for i in range(steps):
            bm.faces.new([rows[0][i], rows[0][i + 1], rows[1][i + 1], rows[1][i]])
    face_up(bm)
    gutters = kit.mesh_object("gutters", bm, col, [mats["gutter"]], recalc=False)
    for poly in gutters.data.polygons:
        poly.use_smooth = True
    objs.append(gutters)

    # Divisórias, as paredes do fundo (kickbacks), o poço e a cortina.
    bm = bmesh.new()
    for side in (-1, 1):
        x0, x1 = sorted((side * outer, side * cap_out))
        box(bm, x0, 0.0, x1, DECK_END + PIT_LEN, -0.06, CAP_H)
        k0, k1 = sorted((side * outer, side * (outer + KICKBACK_T)))
        box(bm, k0, HEAD_PIN - 0.35, k1, DECK_END + PIT_LEN, 0.0, KICKBACK_H)
    objs.append(kit.mesh_object("walls", bm, col, [mats["surface"]]))

    bm = bmesh.new()
    box(bm, -outer, DECK_END, outer, DECK_END + PIT_LEN, -PIT_DEPTH - 0.02, -PIT_DEPTH)
    box(bm, -cap_out, DECK_END + PIT_LEN, cap_out, DECK_END + PIT_LEN + 0.05, -PIT_DEPTH, MASK_TOP)
    objs.append(kit.mesh_object("pit", bm, col, [mats["pit"]]))

    # Máquina: a fachada em cima dos pinos, com a faixa lima acesa.
    bm = bmesh.new()
    box(bm, -cap_out, MASK_FRONT, cap_out, DECK_END + PIT_LEN, MASK_BOTTOM, MASK_TOP)
    objs.append(kit.mesh_object("masking", bm, col, [mats["surface"]]))
    bm = bmesh.new()
    box(bm, -cap_out, MASK_FRONT - 0.01, cap_out, MASK_FRONT, MASK_BOTTOM + 0.05, MASK_BOTTOM + 0.08)
    objs.append(kit.mesh_object("accent", bm, col, [mats["accent"]]))
    return objs


def pin_profile():
    """Perfil do pino em metros, com anéis extras nas bordas das faixas."""
    hs = [h for h, _ in PIN_PROFILE_IN]
    rs = [d / 2 for _, d in PIN_PROFILE_IN]
    extra = [h for band in STRIPES_IN for h in band]
    points = sorted({*hs, *extra})
    profile = [(h, float(np.interp(h, hs, rs))) for h in points]
    centre = 15.0 - HEAD_R_IN
    for a in (0, 22.5, 45, 67.5, 90):
        t = math.radians(a)
        profile.append((centre + HEAD_R_IN * math.sin(t), HEAD_R_IN * math.cos(t)))
    return [(h * 0.0254, r * 0.0254) for h, r in profile]


def build_pin(col, mats, segments=20):
    bm = bmesh.new()
    angles = np.linspace(0, math.tau, segments, endpoint=False)
    rings = []
    profile = pin_profile()
    for h, r in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0, 0, h))])
        else:
            rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), h)) for a in angles])
    base = bm.faces.new(list(reversed(rings[0])))
    base.smooth = False
    stripes = [(a * 0.0254, b * 0.0254) for a, b in STRIPES_IN]
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        mid = (profile[i][0] + profile[i + 1][0]) / 2
        index = 1 if any(lo <= mid <= hi for lo, hi in stripes) else 0
        for j in range(segments):
            k = (j + 1) % segments
            verts = [a[j], a[k], b[0]] if len(b) == 1 else [a[j], a[k], b[k], b[j]]
            f = bm.faces.new(verts)
            f.material_index = index
            f.smooth = True
    return kit.mesh_object("pin", bm, col, [mats["pin"], mats["stripe"]])


def build_ball(col, mats):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=BALL_R, location=(0, 0, 0))
    ball = bpy.context.active_object
    ball.name = "ball"
    ball.data.materials.append(mats["ball"])
    kit.link(ball, col)
    # Polegar e dois dedos, em volta do topo (+z).
    holes = [((0.0, -0.42, 0.91), 0.0125), ((-0.13, 0.30, 0.945), 0.0112), ((0.13, 0.30, 0.945), 0.0112)]
    for direction, radius in holes:
        d = mathutils.Vector(direction).normalized()
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=16, radius=radius, depth=0.13, location=d * BALL_R,
            rotation=d.to_track_quat("Z", "Y").to_euler(),
        )
        cutter = bpy.context.active_object
        cutter.data.materials.append(mats["hole"])
        mod = ball.modifiers.new("hole", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.material_mode = "TRANSFER"
        mod.object = cutter
        bpy.context.view_layer.objects.active = ball
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter)
    bpy.ops.object.select_all(action="DESELECT")
    ball.select_set(True)
    bpy.context.view_layer.objects.active = ball
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    return ball


# --- renders ------------------------------------------------------------------

def setup_render(scene):
    engines = {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("alley")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.006, 0.005, 0.016, 1)
    scene.world = world

    def light(name, kind, location, rotation, energy, size=None, colour=(1.0, 0.96, 0.9)):
        data = bpy.data.lights.new(name, kind)
        data.energy = energy
        data.color = colour
        if size:
            data.shape = "RECTANGLE"
            data.size, data.size_y = size
        obj = bpy.data.objects.new(name, data)
        obj.location = location
        obj.rotation_euler = rotation
        scene.collection.objects.link(obj)

    # Fileira de luminárias sobre a pista e a do deck, embaixo da máquina.
    for i, y in enumerate(np.arange(-2.0, 17.0, 3.0)):
        light(f"row{i}", "AREA", (0, y, 3.0), (0, 0, 0), 55, (2.0, 1.0))
    light("deck", "AREA", (0, HEAD_PIN + 0.35, MASK_BOTTOM - 0.02),
          (0, 0, 0), 45, (1.4, 0.9))


def tinted(img_rgba, colour, name):
    rgba = img_rgba.copy()
    rgba[..., :3] *= np.array([kit.srgb_to_linear(c) for c in colour])[None, None, :] ** (1 / 2.2)
    return kit.image_from_array(name, rgba)


def place_preview(col, pin, ball, ball_preview_mat):
    for i, (x, y) in enumerate(pin_spots()):
        p = pin.copy()
        p.location = (x, y, 0)
        p.rotation_euler = (0, 0, i * 0.7)
        col.objects.link(p)
    b = ball.copy()
    b.data = ball.data.copy()
    b.data.materials[0] = ball_preview_mat
    b.location = (0.05, -0.2, BALL_R)
    b.rotation_euler = (math.radians(70), 0, math.radians(30))
    col.objects.link(b)
    # Uma segunda bola rolando no meio da pista, para a vista de cima.
    b2 = b.copy()
    b2.location = (-0.12, 9.0, BALL_R)
    b2.rotation_euler = (math.radians(80), 0, 0)
    col.objects.link(b2)


def main():
    scene = kit.reset()
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(RENDERS, exist_ok=True)

    wood_img = kit.image_from_array("lane_wood", lane_texture())
    marble = marble_texture()
    marble_img = kit.image_from_array("ball_marble", marble)
    mats = {
        "wood": kit.material("wood", image=wood_img, roughness=0.28, coat=0.25),
        "mark": kit.material("mark", kit.hex_rgb("3a2416"), roughness=0.3),
        "gutter": kit.material("gutter", (0.30, 0.31, 0.36), roughness=0.35, metallic=0.7),
        "surface": kit.material("surface", kit.hex_rgb(SURFACE), roughness=0.5),
        "pit": kit.material("pit", kit.hex_rgb("050404"), roughness=1.0),
        "accent": kit.material("accent", kit.hex_rgb(ACCENT), roughness=0.4),
        "pin": kit.material("pin", kit.hex_rgb("f4f2ee"), roughness=0.18, coat=0.6),
        "stripe": kit.material("stripe", kit.hex_rgb("c62f2f"), roughness=0.2, coat=0.6),
        "ball": kit.material("ball", image=marble_img, roughness=0.15, coat=1.0),
        "hole": kit.material("hole", kit.hex_rgb("15121a"), roughness=0.8),
    }
    accent = mats["accent"].node_tree.nodes["Principled BSDF"]
    accent.inputs["Emission Color"].default_value = (*[kit.srgb_to_linear(c) for c in kit.hex_rgb(ACCENT)], 1)
    accent.inputs["Emission Strength"].default_value = 2.0

    lane_col = kit.new_collection("lane")
    lane_objs = build_lane(lane_col, mats)
    pin_col = kit.new_collection("pin")
    pin = build_pin(pin_col, mats)
    ball_col = kit.new_collection("ball")
    ball = build_ball(ball_col, mats)

    kit.export(lane_objs, os.path.join(OUT, "lane.glb"))
    kit.export([pin], os.path.join(OUT, "pin.glb"))
    kit.export([ball], os.path.join(OUT, "ball.glb"))

    # Cena de preview: pinos no lugar e a bola na linha de falta.
    preview = kit.new_collection("preview")
    preview_ball = kit.material("ball_preview", image=tinted(marble, kit.hex_rgb("4b7fb5"), "ball_blue"),
                                roughness=0.15, coat=1.0)
    place_preview(preview, pin, ball, preview_ball)
    pin.hide_render = True
    ball.hide_render = True
    setup_render(scene)

    aim = kit.camera(scene, "aim", (0.0, -2.6, 1.35), (0.0, 10.0, 0.0), 35)
    kit.render(scene, aim, os.path.join(RENDERS, "1_mira.png"), 900, 1600)
    pins = kit.camera(scene, "pins", (0.45, HEAD_PIN - 2.4, 0.5), (0.0, HEAD_PIN + 0.4, 0.15), 40)
    kit.render(scene, pins, os.path.join(RENDERS, "2_pinos.png"), 1400, 1000)
    close = kit.camera(scene, "close", (0.5, -1.0, 0.38), (0.05, -0.2, 0.08), 45)
    kit.render(scene, close, os.path.join(RENDERS, "3_bola.png"), 1400, 1000)
    overview = kit.camera(scene, "overview", (2.6, 5.0, 3.0), (0.0, 13.0, 0.0), 28)
    kit.render(scene, overview, os.path.join(RENDERS, "4_pista.png"), 1600, 900)

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "bowling.blend"))


main()
