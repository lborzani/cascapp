"""Gera as texturas das quatro bolas especiais da loja (cromada, neon, cristal e lava).

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python art/bowling/build_special_balls.py

Saídas: assets/bowling/skins/<id>.png, no mesmo mapa equiretangular das outras
(`build_skins.py`, cada texel pela direção 3D dele, sem costura). As seis bolas
de antes não são refeitas. O que torna estas especiais é o material, e ele é da
Godot: `metallic`, `glow` e `alpha` de cada item em `core/cosmetics.gd`, que
`BowlingLane.tint_ball` aplica. A conferência é a folha da Godot
(`tests/ball_sheet.tscn`), com o material de verdade.
"""

import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)
import build_skins as bs  # noqa: E402  só as funções
kit = bs.kit


def chrome(d, rng):
    """Um reflexo de estúdio pintado: céu claro em cima, horizonte escuro e chão
    morno embaixo, com duas janelas de luz. A pista não tem céu para o metal
    refletir, então o reflexo vem na cor."""
    z = d[..., 2]
    sky = bs.ramp(z * 1.4, [(0, (0.22, 0.24, 0.28)), (0.25, (0.78, 0.82, 0.88)), (1, (0.97, 0.98, 1.0))])
    floor = bs.ramp(-z * 2.0, [(0, (0.16, 0.16, 0.18)), (0.3, (0.42, 0.38, 0.34)), (1, (0.30, 0.28, 0.26))])
    rgb = np.where((z >= 0)[..., None], sky, floor)
    lon = np.arctan2(d[..., 1], d[..., 0])
    for centre in (0.6, 2.7):
        window = np.exp(-((np.angle(np.exp(1j * (lon - centre))) / 0.18) ** 2) - ((z - 0.35) / 0.25) ** 2)
        rgb = rgb + window[..., None] * 0.6
    return bs.rgba(rgb)


def neon(d, rng):
    """Três anéis de neon em volta da bola, cada um num plano, sobre o escuro."""
    rgb = np.zeros(d.shape[:2] + (3,)) + np.array([0.04, 0.03, 0.10])
    colours = [(1.0, 0.31, 0.85), (0.22, 0.9, 1.0), (0.78, 1.0, 0.25)]
    for colour in colours:
        normal = kit.unit(rng.normal(size=3))
        distance = np.abs(d @ normal)
        tube = np.exp(-(distance / 0.035) ** 2) + 0.35 * np.exp(-(distance / 0.11) ** 2)
        rgb = rgb + tube[..., None] * np.array(colour)
    return bs.rgba(rgb)


def crystal(d, rng):
    """Vidro azulado com um redemoinho por dentro; a transparência é do material."""
    swirl = bs.waves(d, rng, 4, 2.5)
    rgb = bs.ramp(swirl, [(0, (0.62, 0.86, 0.95)), (0.5, (0.86, 0.97, 1.0)), (1, (0.55, 0.78, 0.98))])
    return bs.rgba(rgb)


def lava(d, rng):
    """Rocha escura rachada (Voronoi na esfera), com o fogo nas rachaduras."""
    seeds = rng.normal(size=(42, 3))
    seeds /= np.linalg.norm(seeds, axis=1, keepdims=True)
    angles = np.arccos(np.clip(d @ seeds.T, -1, 1))
    angles.sort(axis=-1)
    gap = angles[..., 1] - angles[..., 0]
    crack = np.clip(1 - gap / 0.07, 0, 1) ** 1.5
    rock = bs.waves(d, rng, 4, 6.0)
    base = bs.ramp(rock, [(0, (0.05, 0.04, 0.04)), (1, (0.16, 0.11, 0.10))])
    fire = bs.ramp(crack, [(0, (0.35, 0.04, 0.0)), (0.5, (0.95, 0.32, 0.03)), (1, (1.0, 0.86, 0.35))])
    rgb = base * (1 - crack[..., None]) + fire * crack[..., None]
    return bs.rgba(rgb)


SPECIAL = [
    ("ball_chrome", chrome),
    ("ball_neon", neon),
    ("ball_crystal", crystal),
    ("ball_lava", lava),
]


def main():
    kit.reset()
    dirs = kit.sphere_dirs(bs.H, bs.W)
    for index, (skin, paint) in enumerate(SPECIAL):
        img = kit.image_from_array(skin, paint(dirs, np.random.default_rng(200 + index)))
        kit.save_png(img, os.path.join(bs.SKINS_OUT, skin + ".png"))
        print("ok", skin)


if __name__ == "__main__":
    main()
