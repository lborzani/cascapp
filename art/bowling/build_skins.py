"""Gera as texturas das bolas da loja e o render de aprovação.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python art/bowling/build_skins.py

Saídas:
- assets/bowling/skins/<id>.png    uma textura por bola, no mesmo mapa da `ball.glb`
                                   (equiretangular da UV sphere); a Godot troca a textura
                                   do material `ball` por ela;
- art/bowling/renders/5_bolas.png  as seis lado a lado, para aprovar.

Cada textura é função da direção 3D do texel (`kit.sphere_dirs`), então não há
costura na emenda do mapa nem pinçado nos polos. Os furos ficam com o material
`hole`, como na bola padrão. Os ids são os da loja (`pocketbase/pb_hooks/loja.js`
e `core/cosmetics.gd`).
"""

import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import build_bowling as bb  # noqa: E402  só as funções
kit = bb.kit

SKINS_OUT = os.path.join(bb.OUT, "skins")
H, W = 256, 512


def waves(d, rng, count=6, freq=2.0):
    """Soma de senos em direções sorteadas: um ruído suave e sem costura na esfera, 0..1."""
    total = np.zeros(d.shape[:2])
    amp_sum = 0.0
    for i in range(count):
        k = kit.unit(rng.normal(size=3)) * freq * (1.6 ** i)
        amp = 0.62 ** i
        total += amp * np.sin(d @ k + rng.random() * 2 * math.pi)
        amp_sum += amp
    return total / amp_sum * 0.5 + 0.5


def ramp(t, stops):
    """Gradiente: `stops` é [(posição, (r, g, b)), ...] em ordem."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        inside = (t >= p0) & (t <= p1)
        f = ((t - p0) / max(p1 - p0, 1e-6))[..., None]
        out = np.where(inside[..., None], np.array(c0) * (1 - f) + np.array(c1) * f, out)
    return out


def rgba(rgb):
    return np.dstack([np.clip(rgb, 0, 1), np.ones(rgb.shape[:2])])


def galaxy(d, rng):
    gas = waves(d, rng, 6, 1.8)
    tint = waves(d, rng, 4, 1.2)
    rgb = ramp(gas ** 1.6, [(0, (0.02, 0.01, 0.07)), (0.45, (0.16, 0.05, 0.35)), (0.8, (0.55, 0.12, 0.55)), (1, (0.95, 0.55, 0.85))])
    rgb = rgb * (1 - 0.5 * tint[..., None]) + np.array([0.05, 0.35, 0.6]) * (0.5 * tint[..., None]) * gas[..., None]
    stars = np.array([kit.unit(v) for v in rng.normal(size=(500, 3))], dtype=np.float32)
    near = (d.astype(np.float32) @ stars.T).max(axis=-1)
    glow = np.clip((near - 0.99975) / 0.00025, 0, 1) ** 0.5
    return rgba(rgb + glow[..., None])


def flames(d, rng):
    z = d[..., 2]
    lon = np.arctan2(d[..., 1], d[..., 0])
    lick = waves(d, rng, 5, 2.4)
    edge = 0.4 + 0.3 * (0.5 + 0.5 * np.sin(lon * 7 + 4.0 * lick)) + 0.25 * lick
    heat = np.clip((edge - (z * 0.5 + 0.5)) / 0.35 + 0.15, 0, 1)
    rgb = ramp(heat, [(0, (0.05, 0.01, 0.02)), (0.25, (0.5, 0.03, 0.02)), (0.55, (0.95, 0.35, 0.03)), (0.85, (1.0, 0.8, 0.15)), (1, (1.0, 0.97, 0.7))])
    return rgba(rgb)


def ocean(d, rng):
    depth = waves(d, rng, 5, 1.6)
    swell = np.sin(11.0 * (d @ kit.unit((0.3, 0.8, 0.5))) + 4.5 * waves(d, rng, 4, 2.0))
    rgb = ramp(depth, [(0, (0.0, 0.08, 0.25)), (0.55, (0.0, 0.35, 0.6)), (1, (0.1, 0.75, 0.8))])
    foam = np.clip((swell - 0.82) / 0.12, 0, 1)
    return rgba(rgb * (1 - foam[..., None]) + np.array([0.9, 0.97, 1.0]) * foam[..., None])


def melon(d, rng):
    lon = np.arctan2(d[..., 1], d[..., 0])
    jag = waves(d, rng, 5, 3.0)
    stripe = np.sin(lon * 8 + 1.2 * np.sin(d[..., 2] * 6) + 2.2 * (jag - 0.5))
    dark = np.clip((stripe + 0.1) / 0.25, 0, 1)
    light = ramp(waves(d, rng, 3, 2.0), [(0, (0.45, 0.72, 0.28)), (1, (0.62, 0.85, 0.4))])
    rgb = light * (1 - dark[..., None]) + np.array([0.07, 0.3, 0.08]) * dark[..., None]
    return rgba(rgb)


def wood(d, rng):
    axis = kit.unit((1.0, 0.2, 0.1))
    across = d - (d @ axis)[..., None] * axis
    r = np.linalg.norm(across, axis=-1) * 9.0 + 1.6 * waves(d, rng, 4, 1.5)
    ring = np.abs(np.sin(r * math.pi)) ** 3
    grain = waves(d, rng, 3, 14.0)
    rgb = ramp(0.65 * ring + 0.35 * grain, [(0, (0.6, 0.36, 0.17)), (0.6, (0.43, 0.24, 0.1)), (1, (0.26, 0.13, 0.05))])
    return rgba(rgb)


def checker(d, rng):
    k = 4.0
    s = np.sin(k * d[..., 0]) * np.sin(k * d[..., 1] + 0.7) * np.sin(k * d[..., 2] + 1.3)
    white = np.clip(s * 25 + 0.5, 0, 1)
    return rgba(np.array([0.06, 0.06, 0.07]) * (1 - white[..., None]) + np.array([0.93, 0.93, 0.9]) * white[..., None])


SKINS = [
    ("ball_galaxy", galaxy),
    ("ball_flames", flames),
    ("ball_ocean", ocean),
    ("ball_melon", melon),
    ("ball_wood", wood),
    ("ball_checker", checker),
]


def main():
    scene = kit.reset()
    os.makedirs(SKINS_OUT, exist_ok=True)
    os.makedirs(bb.RENDERS, exist_ok=True)
    dirs = kit.sphere_dirs(H, W)
    mats = {"hole": kit.material("hole", kit.hex_rgb("15121a"), roughness=0.8)}
    images = []
    for index, (skin, paint) in enumerate(SKINS):
        img = kit.image_from_array(skin, paint(dirs, np.random.default_rng(100 + index)))
        kit.save_png(img, os.path.join(SKINS_OUT, skin + ".png"))
        images.append(img)

    # Uma bola com o mármore só para ter a malha com os furos; cada cópia troca o material.
    mats["ball"] = kit.material("ball", (0.7, 0.7, 0.7), roughness=0.15, coat=1.0)
    col = kit.new_collection("skins")
    ball = bb.build_ball(col, mats)
    ball.hide_render = True
    floor = bpy.data.meshes.new("floor")
    floor.from_pydata([(-3, -3, 0), (3, -3, 0), (3, 3, 0), (-3, 3, 0)], [], [(0, 1, 2, 3)])
    floor_obj = bpy.data.objects.new("floor", floor)
    floor_obj.data.materials.append(kit.material("floor", kit.hex_rgb(bb.SURFACE), roughness=0.6))
    col.objects.link(floor_obj)
    for index, img in enumerate(images):
        copy = ball.copy()
        copy.data = ball.data.copy()
        copy.data.materials[0] = kit.material(SKINS[index][0], image=img, roughness=0.15, coat=1.0)
        copy.location = ((index % 3 - 1) * 0.3, (index // 3) * 0.3, bb.BALL_R)
        copy.rotation_euler = (math.radians(35), 0, math.radians(20 + 25 * index))
        copy.hide_render = False
        col.objects.link(copy)

    bb.setup_render(scene)
    lamp = bpy.data.lights.new("key", "AREA")
    lamp.energy = 60
    lamp.size = 1.5
    key = bpy.data.objects.new("key", lamp)
    key.location = (0.4, -0.6, 1.4)
    scene.collection.objects.link(key)
    cam = kit.camera(scene, "skins", (0.0, -1.05, 0.85), (0.0, 0.17, 0.08), 42)
    kit.render(scene, cam, os.path.join(bb.RENDERS, "5_bolas.png"), 1400, 1000)


# O boneco (`build_bowler.py`) importa as texturas daqui sem refazer as bolas.
if __name__ == "__main__":
    main()
