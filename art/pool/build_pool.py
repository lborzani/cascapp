"""Gera a mesa, as bolas e o taco da sinuca em 3D, do zero.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python art/pool/build_pool.py

Saídas:
- art/pool/pool.blend        a cena montada, para abrir e mexer à mão;
- assets/pool/table.glb      mesa (pano, tabelas, madeira, caçapas);
- assets/pool/ball.glb       uma bola (a textura de cada uma troca na Godot);
- assets/pool/cue.glb        o taco, ponta na origem, cabo para +X;
- assets/pool/balls/*.png    textura de cada bola;
- art/pool/renders/*.png     renders de aprovação.

Escala 1:1 com core/pool_rules.gd: 1 unidade da mesa = 1 metro aqui. O pano é
o retângulo (0..2, 0..-1) em z = 0 — o y da mesa vira -y no Blender, e o export
glTF (Y para cima) devolve isso como (x, 0, y) na Godot, igual à mesa 2D.
"""

import math
import os

import bpy
import bmesh
import mathutils
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ART = os.path.join(ROOT, "art", "pool")
OUT = os.path.join(ROOT, "assets", "pool")
RENDERS = os.path.join(ART, "renders")
FONT = os.path.join(ROOT, "assets", "fonts", "AtkinsonHyperlegible-Bold.ttf")

# --- as constantes de core/pool_rules.gd --------------------------------------

TABLE_W = 2.0
TABLE_H = 1.0
R = 0.027
POCKET_R = 0.058
POCKETS = [
    (0.0, 0.0), (TABLE_W * 0.5, -0.012), (TABLE_W, 0.0),
    (0.0, TABLE_H), (TABLE_W * 0.5, TABLE_H + 0.012), (TABLE_W, TABLE_H),
]
BRAZILIAN_COLORS = ["c9524d", "d9c341", "5f9e63", "8a5b3c", "4b7fb5", "d98cb0", "2a2421"]
GROUP_COLORS = ["4b7fb5", "d98b3a"]
CUE_LENGTH = 1.15

# --- medidas só do desenho ----------------------------------------------------

CUSHION_W = 0.04       # largura da borracha, do pano até a madeira
CUSHION_H = 0.036      # altura do nariz da borracha (~2/3 do diâmetro da bola)
RAIL_W = 0.10          # madeira
RAIL_TOP = 0.042
APRON_DEPTH = 0.16     # saia de madeira abaixo do pano, para a vista 3/4
RAIL_CORNER = 0.05     # raio do canto arredondado de fora
HOLE_R = POCKET_R      # boca desenhada do mesmo tamanho da captura
# As bocas ficam recuadas para dentro da madeira, como no 8 Ball Pool: a física
# captura a bola no ponto de POCKETS, e a Godot a anima até o buraco.
CORNER_RECESS = 0.045  # na diagonal
SIDE_RECESS = 0.03
RIM_W = 0.006          # aro de metal em volta da boca, só do lado da madeira
CLOTH = "0b6e17"
CUSHION_CLOTH = "11831d"
WOOD = (0.45, 0.25, 0.13)


def hex_rgb(code):
    return tuple(int(code[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def to_blender(x, y, z=0.0):
    return (x, -y, z)


# --- cena limpa ---------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    return scene


def new_collection(name):
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)
    return col


def link(obj, col):
    for c in obj.users_collection:
        c.objects.unlink(obj)
    col.objects.link(obj)


# --- texturas geradas ---------------------------------------------------------

def image_from_array(name, rgba):
    """rgba: (altura, largura, 4) em 0..1, linha 0 = embaixo (convenção do Blender)."""
    h, w, _ = rgba.shape
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    return img


def save_png(img, path):
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()


def smooth_noise(h, w, cells, rng):
    """Ruído suave e repetível nas bordas: grade aleatória ampliada bilinear."""
    grid = rng.random((cells, cells))
    ys = np.linspace(0, cells, h, endpoint=False)
    xs = np.linspace(0, cells, w, endpoint=False)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = (ys - y0)[:, None]
    fx = (xs - x0)[None, :]
    y1 = (y0 + 1) % cells
    x1 = (x0 + 1) % cells
    a = grid[y0][:, x0]
    b = grid[y0][:, x1]
    c = grid[y1][:, x0]
    d = grid[y1][:, x1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def cloth_texture():
    rng = np.random.default_rng(7)
    n = 256
    base = np.array(hex_rgb(CLOTH))
    grain = rng.random((n, n)) * 0.06 - 0.03 + (smooth_noise(n, n, 8, rng) - 0.5) * 0.05
    rgb = np.clip(base[None, None, :] * (1.0 + grain[..., None]), 0, 1)
    return np.dstack([rgb, np.ones((n, n))])


def wood_texture():
    rng = np.random.default_rng(11)
    h, w = 512, 512
    warp = smooth_noise(h, w, 6, rng) * 2.5 + smooth_noise(h, w, 24, rng) * 0.5
    ys = np.linspace(0, 1, h)[:, None]
    rings = np.sin((ys * 38.0 + warp) * math.pi) * 0.5 + 0.5
    rings = rings ** 4
    fibre = rng.random((h, 1)) * 0.08 + smooth_noise(h, w, 64, rng) * 0.05
    light = 0.85 + rings * 0.18 + fibre * 0.6
    base = np.array(WOOD)
    rgb = np.clip(base[None, None, :] * light[..., None], 0, 1)
    return np.dstack([rgb, np.ones((h, w))])


def render_digit_masks(digits, size=128):
    """Renderiza cada número com a fonte do app e devolve máscaras (size, size), linha 0 embaixo.

    O Blender não desenha texto numa imagem pela API, então monta uma cena à parte
    com uma câmera ortográfica olhando o número em branco sobre preto.
    """
    scene = bpy.data.scenes.new("digits")
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "SINGLE"
    scene.display.shading.single_color = (1, 1, 1)
    scene.display.shading.background_type = "VIEWPORT"
    scene.display.shading.background_color = (0, 0, 0)
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    world = bpy.data.worlds.new("digits")
    scene.world = world

    cam_data = bpy.data.cameras.new("digits")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 1.0
    cam = bpy.data.objects.new("digits_cam", cam_data)
    cam.location = (0, 0, 5)
    scene.collection.objects.link(cam)
    scene.camera = cam

    font = bpy.data.fonts.load(FONT)
    masks = {}
    tmp = os.path.join(ART, "renders", "_digit.png")
    for digit in digits:
        curve = bpy.data.curves.new(f"d{digit}", "FONT")
        curve.body = str(digit)
        curve.font = font
        curve.size = 0.8
        curve.align_x = "CENTER"
        curve.align_y = "CENTER"
        obj = bpy.data.objects.new(f"d{digit}", curve)
        scene.collection.objects.link(obj)
        scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True, scene=scene.name)
        img = bpy.data.images.load(tmp)
        px = np.array(img.pixels[:]).reshape(size, size, 4)
        masks[digit] = px[..., 0].copy()
        bpy.data.images.remove(img)
        scene.collection.objects.unlink(obj)
    os.remove(tmp)
    bpy.data.scenes.remove(scene)
    return masks


def sphere_dirs(h, w):
    """Direção 3D de cada texel da textura equiretangular da UV sphere do Blender.

    Na UV sphere padrão u = 0 aponta para -X, u cresce no sentido anti-horário
    (visto de cima) e v = 0 é o polo de baixo.
    """
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    lon = math.pi + u[None, :] * 2 * math.pi
    lat = (v[:, None] - 0.5) * math.pi
    x = np.cos(lat) * np.cos(lon)
    y = np.cos(lat) * np.sin(lon)
    z = np.sin(lat) * np.ones_like(lon)
    return np.stack([x, y, z], axis=-1)


def unit(v):
    v = np.array(v, dtype=float)
    return v / np.linalg.norm(v)


def stamp(rgb, dirs, centre, radius, colour, mask=None, mask_scale=1.0):
    """Pinta um disco na esfera; com `mask`, o número dentro dele."""
    c = unit(centre)
    up = np.array([0, 0, 1.0]) if abs(c[2]) < 0.9 else np.array([1.0, 0, 0])
    e1 = unit(np.cross(up, c))
    e2 = np.cross(c, e1)
    facing = dirs @ c
    lx = dirs @ e1
    ly = dirs @ e2
    dist = np.sqrt(lx ** 2 + ly ** 2)
    inside = (facing > 0) & (dist < radius)
    # Borda com um texel de suavização.
    edge = np.clip((radius - dist) / (radius * 0.04), 0, 1) * (facing > 0)
    rgb[:] = rgb * (1 - edge[..., None]) + np.array(colour)[None, None, :] * edge[..., None]
    if mask is None:
        return
    size = mask.shape[0]
    span = radius * mask_scale
    mx = ((lx / span) * 0.5 + 0.5) * (size - 1)
    my = ((ly / span) * 0.5 + 0.5) * (size - 1)
    ok = inside & (mx >= 0) & (mx < size - 1) & (my >= 0) & (my < size - 1)
    ink = np.zeros(dirs.shape[:2])
    ink[ok] = mask[my[ok].astype(int), mx[ok].astype(int)]
    rgb[:] = rgb * (1 - ink[..., None])


def ball_textures():
    h, w = 256, 512
    dirs = sphere_dirs(h, w)
    masks = render_digit_masks(range(1, 8))
    textures = {}

    # A branca: seis pintas vermelhas, como no 8 Ball Pool. Elas são o que deixa
    # o giro (e o efeito) visível numa bola lisa.
    rgb = np.ones((h, w, 3)) * 0.96
    for c in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]:
        stamp(rgb, dirs, c, 0.10, hex_rgb("c62f2f"))
    textures["cue"] = rgb

    # Brasileira: lisas com número num disco branco, dos dois lados.
    for value, code in enumerate(BRAZILIAN_COLORS, start=1):
        rgb = np.ones((h, w, 3)) * np.array(hex_rgb(code))[None, None, :]
        for c in [(0, -1, 0), (0, 1, 0)]:
            stamp(rgb, dirs, c, 0.42, (0.97, 0.96, 0.92), masks[value], 1.15)
        textures[f"n{value}"] = rgb

    # Mata-mata: a cor do grupo e dois discos brancos lisos, para ver a bola girar.
    for group, code in enumerate(GROUP_COLORS):
        rgb = np.ones((h, w, 3)) * np.array(hex_rgb(code))[None, None, :]
        for c in [(0, -1, 0), (0, 1, 0)]:
            stamp(rgb, dirs, c, 0.30, (0.97, 0.96, 0.92))
        textures[f"g{group}"] = rgb

    images = {}
    for name, rgb in textures.items():
        img = image_from_array(f"ball_{name}", np.dstack([rgb, np.ones((h, w))]))
        save_png(img, os.path.join(OUT, "balls", f"ball_{name}.png"))
        images[name] = img
    return images


# --- materiais ----------------------------------------------------------------

def material(name, colour=None, image=None, roughness=0.5, metallic=0.0, coat=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if coat > 0:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.05
    if image is not None:
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    elif colour is not None:
        lin = [srgb_to_linear(c) for c in colour]
        bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    return mat


# --- geometria ----------------------------------------------------------------

def mesh_object(name, bm, col, mats, recalc=True):
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    for m in mats:
        me.materials.append(m)
    return obj


def prism(bm, outline, z0, z1, mat_index=0):
    """Extruda um polígono do plano (lista de (x, y) da mesa) de z0 a z1."""
    bottom = [bm.verts.new(to_blender(x, y, z0)) for x, y in outline]
    top = [bm.verts.new(to_blender(x, y, z1)) for x, y in outline]
    faces = [bm.faces.new(list(reversed(bottom))), bm.faces.new(top)]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new([bottom[i], bottom[j], top[j], top[i]]))
    for f in faces:
        f.material_index = mat_index
    return faces


def planar_uv(obj, tiles_per_metre):
    """UV por projeção no eixo dominante de cada face: basta para pano e madeira."""
    me = obj.data
    # O boolean herda o UVMap dos cilindros de corte, zerado nas faces da mesa.
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name="UVMap").data
    for poly in me.polygons:
        n = poly.normal
        axis = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            a, b = [co[i] for i in range(3) if i != axis]
            uv[li].uv = (a * tiles_per_metre, b * tiles_per_metre)


def rounded_rect(x0, y0, x1, y1, radius, steps=10):
    """Contorno de um retângulo com cantos arredondados, no plano da mesa."""
    points = []
    for cx, cy, start in ((x1 - radius, y0 + radius, -90), (x1 - radius, y1 - radius, 0),
                          (x0 + radius, y1 - radius, 90), (x0 + radius, y0 + radius, 180)):
        for i in range(steps + 1):
            a = math.radians(start + 90 * i / steps)
            points.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    return points


def box(bm, x0, y0, x1, y1, z0, z1, mat_index=0):
    return prism(bm, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], z0, z1, mat_index)


def frame(bm, outer, inner, z0, z1):
    """Moldura fechada (manifold) entre dois retângulos — o boolean exato só
    funciona bem em malha sem faces sobrepostas."""
    def ring(rect, z):
        x0, y0, x1, y1 = rect
        return [bm.verts.new(to_blender(x, y, z)) for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1))]
    ob, ot = ring(outer, z0), ring(outer, z1)
    ib, it = ring(inner, z0), ring(inner, z1)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new([ot[i], ot[j], it[j], it[i]])   # tampo
        bm.faces.new([ob[j], ob[i], ib[i], ib[j]])   # fundo
        bm.faces.new([ob[i], ob[j], ot[j], ot[i]])   # face de fora
        bm.faces.new([ib[j], ib[i], it[i], it[j]])   # face de dentro
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def apply_boolean_cut(obj, cutters):
    for cutter in cutters:
        mod = obj.modifiers.new("cut", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.object = cutter
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)


def hole_centres():
    """Centro desenhado de cada boca: o ponto da física empurrado para fora."""
    centres = []
    for px, py in POCKETS:
        ox = -1.0 if px <= 0 else (1.0 if px >= TABLE_W else 0.0)
        oy = -1.0 if py <= 0 else (1.0 if py >= TABLE_H else 0.0)
        recess = CORNER_RECESS if ox and oy else SIDE_RECESS
        n = math.hypot(ox, oy)
        # Nos meios a física já põe a boca 0,012 para fora; o recuo conta da borda.
        base_y = TABLE_H if oy > 0 else 0.0
        if ox:
            centres.append((px + ox / n * recess, py + oy / n * recess))
        else:
            centres.append((px, base_y + oy * recess))
    return centres


def pocket_cutters(col, radius, z0, z1):
    cutters = []
    for i, (px, py) in enumerate(hole_centres()):
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=40, radius=radius, depth=z1 - z0,
            location=to_blender(px, py, (z0 + z1) * 0.5),
        )
        c = bpy.context.active_object
        c.name = f"cutter{i}"
        cutters.append(c)
    return cutters


def jaw_start(edge_coord, along_pocket, across_pocket):
    """Onde a borracha começa ao lado de uma caçapa.

    Segue a regra de `_in_jaws`: com o centro da bola encostado na borracha
    (a R do pano), a tabela só existe fora do círculo POCKET_R + R.
    """
    reach = POCKET_R + R
    dy = abs(edge_coord - across_pocket)
    return math.sqrt(max(reach * reach - dy * dy, 0.0))


def cushions(bm, mat_index):
    """Seis borrachas, cada uma entre duas caçapas, com as pontas em chanfro."""
    cw = CUSHION_W
    segments = []
    # Lados compridos: de canto até o meio, dos dois lados.
    for y_edge, sign, mid in [(0.0, -1.0, POCKETS[1]), (TABLE_H, 1.0, POCKETS[4])]:
        ball_y = y_edge - sign * R
        corner_gap = jaw_start(ball_y, 0.0, y_edge)
        mid_gap = jaw_start(ball_y, mid[0], mid[1])
        for x0, x1, slope0, slope1 in [
            (corner_gap, mid[0] - mid_gap, 1.0, 0.35),
            (mid[0] + mid_gap, TABLE_W - corner_gap, 0.35, 1.0),
        ]:
            outer = y_edge + sign * cw
            segments.append([
                (x0, y_edge), (x1, y_edge),
                (x1 + cw * slope1, outer), (x0 - cw * slope0, outer),
            ])
    # Lados curtos.
    for x_edge, sign in [(0.0, -1.0), (TABLE_W, 1.0)]:
        ball_x = x_edge - sign * R
        gap = jaw_start(ball_x, 0.0, x_edge)
        outer = x_edge + sign * cw
        segments.append([
            (x_edge, gap), (x_edge, TABLE_H - gap),
            (outer, TABLE_H - gap + cw), (outer, gap - cw),
        ])
    for outline in segments:
        # Orientação anti-horária no plano do Blender (y invertido), para as
        # normais saírem para fora.
        flipped = [(x, -y) for x, y in outline]
        area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(flipped, flipped[1:] + flipped[:1]))
        if area < 0:
            outline = list(reversed(outline))
        prism(bm, outline, 0.0, CUSHION_H, mat_index)


def build_table(col, mats):
    # Pano, borracha e madeira em objetos separados: na Godot cada um vira um
    # MeshInstance3D com o próprio material, sem multi-material por face.
    cut_depth = (-APRON_DEPTH - 0.01, 0.2)
    inner = (-CUSHION_W, -CUSHION_W, TABLE_W + CUSHION_W, TABLE_H + CUSHION_W)

    bm = bmesh.new()
    box(bm, *inner[:2], *inner[2:], -0.04, 0.0)
    cloth = mesh_object("cloth", bm, col, [mats["cloth"]])

    bm = bmesh.new()
    cushions(bm, 0)
    cushion = mesh_object("cushions", bm, col, [mats["cushion"]])
    bevel_noses(cushion)

    # Madeira: bloco com os cantos de fora arredondados, menos o miolo da mesa.
    outer = CUSHION_W + RAIL_W
    bm = bmesh.new()
    prism(bm, rounded_rect(-outer, -outer, TABLE_W + outer, TABLE_H + outer, RAIL_CORNER), -APRON_DEPTH, RAIL_TOP)
    rail = mesh_object("rail", bm, col, [mats["wood"]])
    bm = bmesh.new()
    box(bm, *inner[:2], *inner[2:], -1.0, 1.0)
    hollow = mesh_object("hollow", bm, col, [])
    apply_boolean_cut(rail, [hollow])

    cutters = pocket_cutters(col, HOLE_R, *cut_depth)
    for obj in (cloth, cushion, rail):
        apply_boolean_cut(obj, cutters)

    # Aro de metal em volta de cada boca, só por cima da madeira.
    bm = bmesh.new()
    for px, py in hole_centres():
        bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=48,
            radius1=HOLE_R + RIM_W, radius2=HOLE_R + RIM_W, depth=0.004,
            matrix=mathutils.Matrix.Translation(to_blender(px, py, RAIL_TOP)),
        )
    rims = mesh_object("rims", bm, col, [mats["metal"]])
    apply_boolean_cut(rims, cutters + [hollow])
    for c in cutters + [hollow]:
        bpy.data.objects.remove(c)
    planar_uv(cloth, 4.0)
    planar_uv(cushion, 4.0)
    planar_uv(rail, 2.5)

    # Caçapas: um copo escuro aberto em cima, por dentro do buraco.
    bm = bmesh.new()
    for px, py in hole_centres():
        ret = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=40,
            radius1=HOLE_R * 0.99, radius2=HOLE_R * 0.99, depth=0.16,
            matrix=mathutils.Matrix.Translation(to_blender(px, py, RAIL_TOP - 0.081)),
        )
        top = [f for f in bm.faces if f.normal.z > 0.9 and all(v in ret["verts"] for v in f.verts)]
        bmesh.ops.delete(bm, geom=top, context="FACES")
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    mesh_object("pockets", bm, col, [mats["pocket"]], recalc=False)

    # Pinos de metal na madeira, nas posições da mesa de referência.
    bm = bmesh.new()
    mid = CUSHION_W + RAIL_W * 0.5
    studs = [(x, y) for x in (0.22, 0.70, 1.30, 1.78) for y in (-mid, TABLE_H + mid)]
    studs += [(x, y) for y in (0.25, 0.75) for x in (-mid, TABLE_W + mid)]
    for x, y in studs:
        at = mathutils.Matrix.Translation(to_blender(x, y, RAIL_TOP))
        flat = mathutils.Matrix.Diagonal((1.0, 1.0, 0.45, 1.0))
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=6, radius=0.0085, matrix=at @ flat)
    studs_obj = mesh_object("studs", bm, col, [mats["metal"]])
    for poly in studs_obj.data.polygons:
        poly.use_smooth = True


def bevel_noses(obj):
    """Inclina a face de dentro da borracha, como o nariz de uma tabela de verdade."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    # Vértices de baixo que tocam o pano entram 1 cm para baixo da face de cima:
    # a face de dentro vira uma rampa de cima para fora.
    for v in bm.verts:
        x, y, z = v.co.x, -v.co.y, v.co.z
        on_edge = (
            abs(x) < 1e-6 or abs(x - TABLE_W) < 1e-6 or abs(y) < 1e-6 or abs(y - TABLE_H) < 1e-6
        )
        if on_edge and z < 1e-6:
            if abs(y) < 1e-6:
                v.co.y += 0.008
            elif abs(y - TABLE_H) < 1e-6:
                v.co.y -= 0.008
            elif abs(x) < 1e-6:
                v.co.x -= 0.008
            else:
                v.co.x += 0.008
    bm.to_mesh(me)
    bm.free()


def build_ball(col, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=R, location=(0, 0, 0))
    ball = bpy.context.active_object
    ball.name = "ball"
    bpy.ops.object.shade_smooth()
    ball.data.materials.append(mat)
    link(ball, col)
    return ball


def build_cue(col, mats):
    """Taco deitado em +X, ponta na origem. Cada trecho é um cone com o próprio material."""
    profile = [
        # (de, até, raio no começo, raio no fim, material)
        (0.000, 0.010, 0.0100, 0.0105, "tip"),
        (0.010, 0.032, 0.0108, 0.0110, "ferrule"),
        (0.032, 0.700, 0.0110, 0.0160, "shaft"),
        (0.700, 0.712, 0.0165, 0.0165, "joint"),
        (0.712, 0.860, 0.0165, 0.0190, "forearm"),
        (0.860, 1.080, 0.0190, 0.0225, "grip"),
        (1.080, CUE_LENGTH - 0.006, 0.0225, 0.0240, "forearm"),
        (CUE_LENGTH - 0.006, CUE_LENGTH, 0.0240, 0.0236, "tip"),
    ]
    bm = bmesh.new()
    names = []
    for start, end, r0, r1, name in profile:
        if name not in names:
            names.append(name)
        rot = mathutils.Matrix.Rotation(math.radians(90), 4, "Y")
        at = mathutils.Matrix.Translation(((start + end) * 0.5, 0, 0))
        ret = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=24,
            radius1=r0, radius2=r1, depth=end - start, matrix=at @ rot,
        )
        index = names.index(name)
        for f in {f for v in ret["verts"] for f in v.link_faces}:
            f.material_index = index
    cue = mesh_object("cue", bm, col, [mats[n] for n in names])
    for poly in cue.data.polygons:
        poly.use_smooth = True
    return cue


# --- export e renders ---------------------------------------------------------

def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_image_format="AUTO",
    )


def setup_render(scene):
    engines = {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("bar")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.008, 0.012, 0.035, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    scene.world = world

    # A luminária de bar sobre a mesa: uma luz de área comprida, quente.
    lamp = bpy.data.lights.new("lamp", "AREA")
    lamp.shape = "RECTANGLE"
    lamp.size = 2.6
    lamp.size_y = 1.4
    lamp.energy = 55
    lamp.color = (1.0, 0.93, 0.82)
    obj = bpy.data.objects.new("lamp", lamp)
    obj.location = (TABLE_W * 0.5, -TABLE_H * 0.5, 1.3)
    scene.collection.objects.link(obj)
    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = 0.6
    fobj = bpy.data.objects.new("fill", fill)
    fobj.rotation_euler = (math.radians(30), 0, math.radians(30))
    scene.collection.objects.link(fobj)


def camera(scene, name, location, target, lens, ortho=None):
    data = bpy.data.cameras.new(name)
    data.lens = lens
    data.clip_end = 50
    if ortho:
        data.type = "ORTHO"
        data.ortho_scale = ortho
    cam = bpy.data.objects.new(name, data)
    cam.location = location
    direction = mathutils.Vector(target) - mathutils.Vector(location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    return cam


def render(scene, cam, path, w, h):
    scene.camera = cam
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def place_balls(col, ball, ball_mats, cue_obj):
    """Brasileira na posição inicial, com o taco mirando a branca."""
    spots = [(TABLE_W * 0.25, TABLE_H * 0.5)]
    apex = (TABLE_W * 0.72, TABLE_H * 0.5)
    gap = R * 2.02
    for row in range(4):
        for slot in range(row + 1):
            if len(spots) == 8:
                break
            spots.append((apex[0] + row * gap * 0.866, apex[1] + (slot - row * 0.5) * gap))
    names = ["cue"] + [f"n{i}" for i in range(1, 8)]
    rng = np.random.default_rng(3)
    for (x, y), name in zip(spots, names):
        b = ball.copy()
        b.data = ball.data.copy()
        b.data.materials[0] = ball_mats[name]
        b.location = to_blender(x, y, R)
        b.rotation_euler = tuple(rng.random(3) * math.tau) if name == "cue" else (math.radians(90), 0, math.radians(rng.random() * 40 - 20))
        col.objects.link(b)
    # Mata-mata, numa segunda mesa ao lado não: só três bolas soltas para o close.
    for i, (name, (x, y)) in enumerate([("g0", (0.42, 0.22)), ("g1", (0.36, 0.30)), ("g0", (0.30, 0.20))]):
        b = ball.copy()
        b.data = ball.data.copy()
        b.data.materials[0] = ball_mats[name]
        b.location = to_blender(x, y, R)
        b.rotation_euler = (math.radians(70), 0, math.radians(i * 40))
        col.objects.link(b)
    # Taco: atrás da branca, apontando para o triângulo, recuado 4 cm.
    cx, cy = spots[0]
    cue_obj.location = to_blender(cx - R - 0.04, cy, R + 0.004)
    cue_obj.rotation_euler = (0, math.radians(-4), math.radians(180))


def main():
    scene = reset()
    os.makedirs(os.path.join(OUT, "balls"), exist_ok=True)
    os.makedirs(RENDERS, exist_ok=True)

    cloth_img = image_from_array("cloth", cloth_texture())
    save_png(cloth_img, os.path.join(ART, "cloth.png"))
    wood_img = image_from_array("wood", wood_texture())
    save_png(wood_img, os.path.join(ART, "wood.png"))
    ball_imgs = ball_textures()

    mats = {
        "cloth": material("cloth", image=cloth_img, roughness=0.95),
        "wood": material("wood", image=wood_img, roughness=0.6, coat=0.15),
        "pocket": material("pocket", hex_rgb("050404"), roughness=1.0),
        "cushion": material("cushion", hex_rgb(CUSHION_CLOTH), roughness=0.9),
        "metal": material("metal", (0.82, 0.83, 0.86), roughness=0.25, metallic=1.0),
        "tip": material("tip", hex_rgb("4b7fb5"), roughness=0.8),
        "ferrule": material("ferrule", hex_rgb("efe6d8"), roughness=0.3),
        "shaft": material("shaft", hex_rgb("d9b27c"), roughness=0.35),
        "joint": material("joint", (0.75, 0.75, 0.78), roughness=0.2, metallic=1.0),
        "forearm": material("forearm", hex_rgb("3a2416"), roughness=0.3, coat=0.5),
        "grip": material("grip", hex_rgb("1c1714"), roughness=0.85),
    }
    ball_mats = {
        name: material(f"ball_{name}", image=img, roughness=0.12, coat=1.0)
        for name, img in ball_imgs.items()
    }

    table_col = new_collection("table")
    build_table(table_col, mats)
    ball_col = new_collection("ball")
    ball = build_ball(ball_col, ball_mats["cue"])
    cue_col = new_collection("cue")
    cue_obj = build_cue(cue_col, mats)

    export(list(table_col.objects), os.path.join(OUT, "table.glb"))
    export([ball], os.path.join(OUT, "ball.glb"))
    export([cue_obj], os.path.join(OUT, "cue.glb"))

    # Cena de preview: as bolas e o taco postos na mesa.
    preview = new_collection("preview")
    place_balls(preview, ball, ball_mats, cue_obj)
    ball.hide_render = True
    setup_render(scene)

    centre = (TABLE_W * 0.5, -TABLE_H * 0.5, 0)
    top = camera(scene, "top", (TABLE_W * 0.5, -TABLE_H * 0.5, 5.0), centre, 70)
    render(scene, top, os.path.join(RENDERS, "1_top.png"), 1600, 860)
    angled = camera(scene, "angled", (-0.7, -2.6, 1.5), (TABLE_W * 0.55, -TABLE_H * 0.45, -0.05), 32)
    render(scene, angled, os.path.join(RENDERS, "2_angled.png"), 1600, 900)
    close = camera(scene, "close", (0.12, -0.68, 0.22), (0.47, -0.5, 0.0), 50)
    render(scene, close, os.path.join(RENDERS, "3_close_cue.png"), 1400, 800)
    rack = camera(scene, "rack", (1.78, -0.98, 0.32), (1.50, -0.5, 0.0), 60)
    render(scene, rack, os.path.join(RENDERS, "4_rack.png"), 1400, 800)

    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ART, "pool.blend"))


main()
