"""Gera as texturas das bolas especiais da loja (cromada, neon, cristal, lava e a dos testadores).

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


def _great_arc(d, a, b, width):
    """Quanto cada texel está sobre o arco de círculo máximo de `a` a `b` (0..1)."""
    normal = kit.unit(np.cross(a, b))
    across = np.abs(d @ normal)
    span = math.acos(np.clip(a @ b, -1, 1))
    inside = np.arccos(np.clip(d @ a, -1, 1)) + np.arccos(np.clip(d @ b, -1, 1)) <= span + 0.01
    return np.exp(-(across / width) ** 2) * inside


def pioneer(d, rng):
    """A dos testadores: céu índigo com nebulosas em menta, violeta e ouro (as
    cores do conjunto, `ProfileStyle.PIONEER` no app), poeira de estrelas e o
    Cruzeiro do Sul em ouro, dos dois lados da bola. O `glow` do item acende
    estrelas e nebulosas; o fundo escuro quase não brilha."""
    rgb = bs.ramp(d[..., 2] * 0.5 + 0.5, [(0, (0.03, 0.03, 0.11)), (1, (0.09, 0.05, 0.24))])
    for colour in [(0.24, 1.0, 0.82), (0.65, 0.42, 1.0), (1.0, 0.82, 0.35)]:
        cloud = np.clip((bs.waves(d, rng, 4, 1.4) - 0.55) / 0.3, 0, 1) ** 2
        rgb = rgb + cloud[..., None] * np.array(colour) * 0.4
    dust = rng.normal(size=(260, 3))
    dust /= np.linalg.norm(dust, axis=1, keepdims=True)
    near = np.arccos(np.clip(d @ dust.T, -1, 1))
    size = rng.uniform(0.006, 0.016, 260)
    rgb = rgb + (np.exp(-(near / size) ** 2) * rng.uniform(0.4, 1.0, 260)).max(axis=-1)[..., None]
    # O Cruzeiro (Acrux, Mimosa, Gacrux, Imai, Ginan), nas posições do app
    # (`ProfileCover.CONSTELLATIONS`), em volta de um centro no equador da bola.
    crux = [(0.101, 0.500, 0.8), (-0.342, -0.069, 1.2), (0.006, -0.500, 1.6), (0.342, -0.226, 2.8), (0.211, 0.049, 3.6)]
    gold = np.array([1.0, 0.82, 0.35])
    for centre in ([1.0, 0.0, 0.0], [-1.0, 0.0, 0.0]):
        centre = np.array(centre)
        east = kit.unit(np.cross([0, 0, 1], centre))
        stars = [kit.unit(centre + east * x * 0.9 - np.array([0, 0, 1]) * y * 0.9) for x, y, _ in crux]
        for i, j in [(0, 2), (1, 3)]:
            rgb = rgb + _great_arc(d, stars[i], stars[j], 0.006)[..., None] * gold * 0.7
        for star, (_, _, mag) in zip(stars, crux):
            angle = np.arccos(np.clip(d @ star, -1, 1))
            radius = 0.012 + (4.0 - mag) * 0.008
            rgb = rgb + np.exp(-(angle / radius) ** 2)[..., None] * np.array([1.0, 0.95, 0.8])
            rgb = rgb + np.exp(-(angle / (radius * 3.0)) ** 2)[..., None] * gold * 0.35
    return bs.rgba(rgb)


SPECIAL = [
    ("ball_chrome", chrome),
    ("ball_neon", neon),
    ("ball_crystal", crystal),
    ("ball_lava", lava),
    ("ball_pioneer", pioneer),
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
