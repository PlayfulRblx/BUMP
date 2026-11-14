"""
Concept renders for BUMP's hexagonal lobby, with the round's arena in the middle.

    /Applications/Blender.app/Contents/MacOS/Blender -b -P design/lobby/render_concepts.py -- OUT_DIR [A B C]

Blockouts only (1 Blender unit = 1 Roblox stud): three ideas, each rendered from above and
from a spectator's eye. The arena is BUMP's: 7 rings of flat-top hex tiles, 7 studs across.
"""

import math
import random
import sys

import bpy
import bmesh
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp"
WANTED = set(argv[1:]) or {"A", "B", "C"}

SQ3 = math.sqrt(3)
TILE = 7.0

RING_COLORS = [
    (255, 240, 200), (255, 214, 140), (255, 176, 120), (240, 140, 160),
    (176, 140, 230), (120, 170, 240), (120, 170, 240), (120, 170, 240),
]
SEATS = [(235, 80, 80), (80, 140, 240), (250, 200, 60), (90, 200, 110)]


def rgb(c, k=1.0):
    return (min(1, (c[0] / 255) ** 2.2 * k), min(1, (c[1] / 255) ** 2.2 * k), min(1, (c[2] / 255) ** 2.2 * k), 1)


_mats = {}


def mat(color, rough=0.6, glass=False, emit=0.0, metal=0.0):
    if isinstance(color, bpy.types.Material):
        return color
    key = (tuple(color), rough, glass, emit, metal)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("m%d" % len(_mats))
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if glass:
        b.inputs["Alpha"].default_value = 0.28
        try:
            m.blend_method = "BLEND"
        except Exception:
            pass
        try:
            m.surface_render_method = "BLENDED"
        except Exception:
            pass
    if emit > 0:
        b.inputs["Emission Color"].default_value = color
        b.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


def link(obj, material):
    obj.data.materials.append(material)
    return obj


def prism(radius, height, at, color, sides=6, rot=0.0, **kw):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=height, location=(at[0], at[1], at[2] + height / 2), rotation=(0, 0, rot))
    o = bpy.context.object
    return link(o, mat(color, **kw))


def box(size, at, color, rot=0.0, **kw):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at, rotation=(0, 0, rot))
    o = bpy.context.object
    o.scale = size
    return link(o, mat(color, **kw))


def ball(radius, at, color, **kw):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=at, segments=32, ring_count=16)
    o = bpy.context.object
    bpy.ops.object.shade_smooth()
    return link(o, mat(color, **kw))


def cone(r1, r2, height, at, color, sides=6, rot=0.0, **kw):
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r1, radius2=r2, depth=height, location=(at[0], at[1], at[2] + height / 2), rotation=(0, 0, rot))
    o = bpy.context.object
    return link(o, mat(color, **kw))


def hex_ring(inner, outer, z0, z1, color, offset=math.radians(30), outer_low=None, **kw):
    """A flat hexagonal ring (a walkway), corners at `offset` + 60k; `outer_low` tapers its
    underside in to that radius (a floating rock's belly)."""
    bm = bmesh.new()
    rings = []
    for r, low in ((inner, inner), (outer, outer_low or outer)):
        for z in (z0, z1):
            radius = low if z == z0 else r
            rings.append([bm.verts.new((radius * math.cos(offset + k * math.pi / 3), radius * math.sin(offset + k * math.pi / 3), z)) for k in range(6)])
    ib, it, ob, ot = rings
    for k in range(6):
        n = (k + 1) % 6
        bm.faces.new((it[k], it[n], ot[n], ot[k]))
        bm.faces.new((ib[k], ob[k], ob[n], ib[n]))
        bm.faces.new((ot[k], ot[n], ob[n], ob[k]))
        bm.faces.new((it[k], ib[k], ib[n], it[n]))
    me = bpy.data.meshes.new("ring")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("ring", me)
    bpy.context.collection.objects.link(o)
    return link(o, mat(color, **kw))


def corner(r, k, offset=math.radians(30)):
    a = offset + k * math.pi / 3
    return Vector((r * math.cos(a), r * math.sin(a), 0))


def person(at, color, facing=0.0):
    x, y, z = at
    prism(0.9, 2.6, (x, y, z), rgb(color), sides=12)
    ball(0.95, (x, y, z + 3.4), rgb((250, 220, 190)))
    box((2.6, 1.2, 1.4), (x, y, z + 2.2), rgb(color, 0.8), rot=facing)


def crowd(points, z, seed=1):
    rnd = random.Random(seed)
    palette = SEATS + [(240, 240, 240), (160, 120, 220), (255, 150, 200), (70, 70, 90)]
    for p in points:
        person((p[0], p[1], z), rnd.choice(palette), rnd.random() * 6)


# ═══ the arena: BUMP's platform mid-game ═══════════════════════════════════════════

def arena(z=0.0, rings=7, gone=(), balls=True):
    rnd = random.Random(4)
    for q in range(-rings, rings + 1):
        for r in range(max(-rings, -q - rings), min(rings, -q + rings) + 1):
            ring = max(abs(q), abs(r), abs(q + r))
            if (q, r) in gone:
                continue
            x = TILE * 1.5 * q
            y = TILE * SQ3 * (r + q / 2)
            c = RING_COLORS[ring]
            k = 1.25 if (q + r * 2) % 2 == 0 else 1.0
            warn = ring == rings and rnd.random() < 0.08
            prism(TILE * 0.97, 2.5, (x, y, z - 2.5), rgb((255, 80, 80)) if warn else rgb(c, k))
    if balls:
        for i, (x, y) in enumerate([(-22, 14), (18, 26), (10, -30)]):
            ball(4, (x, y, z + 4), rgb((250, 250, 255)), rough=0.15)
            person((x, y, z + 8), SEATS[i])
        person((-35, -18, z), SEATS[3])


def clouds(z, radius, count=40, seed=3):
    rnd = random.Random(seed)
    for _ in range(count):
        a = rnd.random() * math.tau
        d = rnd.random() * radius
        s = 8 + rnd.random() * 18
        o = ball(s, (math.cos(a) * d, math.sin(a) * d, z - rnd.random() * 30), (1, 1, 1, 1), rough=1)
        o.scale = (1.6, 1.3, 0.45)


# ═══ the scene ═════════════════════════════════════════════════════════════════════

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            pass
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    try:
        scene.view_settings.view_transform = "Standard"
    except TypeError:
        pass
    world = bpy.data.worlds.new("sky")
    scene.world = world
    world.use_nodes = True
    nodes = world.node_tree.nodes
    bg = nodes["Background"]
    grad = nodes.new("ShaderNodeTexGradient")
    coord = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    ramp = nodes.new("ShaderNodeValToRGB")
    links = world.node_tree.links
    links.new(coord.outputs["Generated"], sep.inputs[0])
    links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.75, 0.86, 0.98, 1)
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = (0.22, 0.5, 0.92, 1)
    links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.0
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 100), rotation=(math.radians(40), math.radians(15), math.radians(35)))
    sun = bpy.context.object
    sun.data.energy = 4.0
    sun.data.angle = math.radians(4)
    try:
        scene.eevee.use_shadows = True
    except AttributeError:
        pass


def shoot(name, eye, look, lens=30):
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new(name)
    cam_data.lens = lens
    cam_data.clip_end = 3000
    cam = bpy.data.objects.new(name, cam_data)
    scene.collection.objects.link(cam)
    cam.location = eye
    direction = Vector(look) - Vector(eye)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = "%s/%s.png" % (OUT, name)
    bpy.ops.render.render(write_still=True)
    print("[Lobby] wrote", scene.render.filepath)


GONE = {(7, -3), (7, -4), (6, -6), (-7, 2), (-7, 3), (2, 5), (-3, -4), (0, 7), (1, 6)}

# ═══ A: the bowl ══════════════════════════════════════════════════════════════════
# Terraces step up and away from the arena on all six sides, like a stadium: wherever you
# stand on the rim or the steps, you look down into the game.


def concept_a():
    reset()
    arena(0, gone=GONE)
    clouds(-70, 200)
    steps = 6
    for i in range(steps):
        inner = 104 + i * 9
        top = -2 + i * 3.2
        shade = 1.0 + 0.06 * (i % 2)
        hex_ring(inner, inner + 9, top - 3.2 - (6 if i == 0 else 0), top, rgb((236, 226, 246), shade))
    # the promenade on top, and the outer wall
    rim_in, rim_out = 158, 190
    rim_z = -2 + (steps - 1) * 3.2
    hex_ring(rim_in, rim_out, rim_z - 6, rim_z, rgb((250, 236, 214)))
    hex_ring(104, rim_out, rim_z - 60, rim_z - 6, rgb((205, 195, 228)), outer_low=130)
    hex_ring(rim_out - 3, rim_out, rim_z, rim_z + 6, rgb((180, 160, 230)))
    # six corner towers: queue, shop, leaderboard, practice...
    tower_colors = [(255, 176, 120), (120, 170, 240), (240, 140, 160), (176, 140, 230), (255, 214, 140), (120, 200, 170)]
    for k in range(6):
        c = corner(174, k)
        prism(11, 26, (c.x, c.y, rim_z), rgb(tower_colors[k]))
        cone(14, 2, 12, (c.x, c.y, rim_z + 26), rgb(tower_colors[k], 0.75))
    # a big screen over one side
    s = corner(150, 1.5)
    box((60, 3, 30), (s.x, s.y + 12, rim_z + 40), rgb((30, 30, 44)), rot=0)
    box((56, 3.2, 26), (s.x, s.y + 11.8, rim_z + 40), rgb((120, 180, 255)), emit=1.2)
    # spectators on the steps
    rnd = random.Random(8)
    pts = []
    for _ in range(70):
        a = rnd.random() * math.tau
        i = rnd.randrange(steps)
        d = 108 + i * 9 + rnd.random() * 4
        pts.append((math.cos(a) * d * 0.95, math.sin(a) * d * 0.95, -2 + i * 3.2))
    for p in pts:
        person(p, rnd.choice(SEATS + [(240, 240, 240), (160, 120, 220)]))
    shoot("A_bowl_overview", (0, -330, 230), (0, 10, -10), lens=32)
    shoot("A_bowl_spectator", (-40, -150, 22), (10, 0, -2), lens=24)


# ═══ B: the ring plaza ════════════════════════════════════════════════════════════
# A flat hex walkway level with the arena, a glass rail and a gap of sky between, and the
# lobby's places as six pods on the corners. Bridges slide out to the arena when a round starts.


def concept_b():
    reset()
    arena(0, gone=GONE)
    clouds(-80, 220)
    z = 1.0
    hex_ring(100, 150, z - 6, z, rgb((246, 238, 228)))
    hex_ring(100, 150, z - 40, z - 6, rgb((210, 200, 225)), outer_low=112)
    hex_ring(100, 101.2, z, z + 4, (0.75, 0.9, 1, 1), glass=True, rough=0.05)
    # a checker of hex inlays on the walkway
    for k in range(6):
        a = corner(125, k + 0.5)
        prism(6, 0.4, (a.x, a.y, z), rgb((255, 211, 111)))
    # six pods on the corners, each a place
    pods = [
        ("Queue", (255, 120, 90)), ("Shop", (120, 170, 240)), ("Board", (176, 140, 230)),
        ("Practice", (120, 200, 170)), ("Podium", (255, 211, 111)), ("Spawn", (240, 140, 160)),
    ]
    for k, (name, color) in enumerate(pods):
        c = corner(160, k)
        prism(26, 3, (c.x, c.y, z - 2), rgb(color, 1.15), rot=math.radians(30))
        prism(22, 1, (c.x, c.y, z + 1), rgb(color), rot=math.radians(30))
        if name == "Queue":
            for j in range(4):
                p = c + Vector((math.cos(j * 1.57) * 9, math.sin(j * 1.57) * 9, 0))
                prism(4, 0.6, (p.x, p.y, z + 2), rgb(SEATS[j]), emit=0.8, sides=24)
        elif name == "Practice":
            box((3, 14, 30), (c.x - 6, c.y, z + 16), rgb((200, 200, 205)))
            box((3, 14, 30), (c.x + 6, c.y, z + 16), rgb((200, 200, 205)))
        elif name == "Podium":
            for j, h in enumerate((8, 12, 5)):
                box((8, 8, h), (c.x + (j - 1) * 9, c.y, z + 2 + h / 2), rgb((255, 230, 160)))
        elif name == "Board":
            box((26, 2, 18), (c.x, c.y, z + 14), rgb((30, 30, 44)), rot=math.radians(60 * k + 30 + 90))
        elif name == "Shop":
            prism(9, 10, (c.x, c.y, z + 2), rgb((255, 255, 255)))
            cone(14, 0, 8, (c.x, c.y, z + 12), rgb(color, 0.8))
        else:
            ball(5, (c.x, c.y, z + 9), rgb(color), emit=0.6)
    # bridges sliding out to the arena (two out, the rest tucked in)
    for k in range(6):
        a = corner(100, k + 0.5)
        b = corner(88, k + 0.5)
        length = 13 if k in (0, 3) else 3
        mid = a + (b - a).normalized() * (length / 2)
        box((length, 8, 1.2), (mid.x, mid.y, z - 0.6), rgb((255, 211, 111)), rot=math.atan2(b.y - a.y, b.x - a.x))
    rnd = random.Random(5)
    pts = []
    for _ in range(50):
        a = rnd.random() * math.tau
        d = 104 + rnd.random() * 38
        pts.append((math.cos(a) * d, math.sin(a) * d))
    crowd(pts, z, seed=6)
    shoot("B_ring_overview", (0, -300, 200), (0, 20, -10), lens=32)
    shoot("B_ring_spectator", (28, -138, 13), (-5, 0, -2), lens=24)


# ═══ C: sky islands ═══════════════════════════════════════════════════════════════
# Six hex islands round the arena, a little higher, joined into a ring by rope bridges. Each
# island is a place; you walk the ring and look in.


def concept_c():
    reset()
    arena(0, gone=GONE)
    clouds(-90, 260, count=55)
    z = 10.0
    islands = [
        ("Spawn", (240, 140, 160)), ("Queue", (255, 120, 90)), ("Shop", (120, 170, 240)),
        ("Practice", (120, 200, 170)), ("Board", (176, 140, 230)), ("Podium", (255, 211, 111)),
    ]
    centres = []
    for k, (name, color) in enumerate(islands):
        c = corner(150, k + 0.5)
        centres.append(c)
        prism(34, 4, (c.x, c.y, z - 4), rgb((140, 210, 130)))
        prism(34.5, 1, (c.x, c.y, z - 1), rgb((120, 190, 110)))
        cone(34, 6, 34, (c.x, c.y, z - 38), rgb((150, 120, 100)), rot=0.3)
        prism(20, 0.8, (c.x, c.y, z), rgb(color, 1.1))
        if name == "Queue":
            for j in range(4):
                p = c + Vector((math.cos(j * 1.57) * 9, math.sin(j * 1.57) * 9, 0))
                prism(4, 0.6, (p.x, p.y, z + 0.8), rgb(SEATS[j]), emit=0.8, sides=24)
        elif name == "Practice":
            box((3, 14, 30), (c.x - 6, c.y, z + 15), rgb((200, 200, 205)))
            box((3, 14, 30), (c.x + 6, c.y, z + 15), rgb((200, 200, 205)))
        elif name == "Podium":
            for j, h in enumerate((8, 12, 5)):
                box((8, 8, h), (c.x + (j - 1) * 9, c.y, z + h / 2), rgb((255, 230, 160)))
        elif name == "Board":
            box((26, 2, 18), (c.x, c.y, z + 13), rgb((30, 30, 44)), rot=math.atan2(c.y, c.x) + math.pi / 2)
        elif name == "Shop":
            prism(9, 10, (c.x, c.y, z), rgb((255, 255, 255)))
            cone(14, 0, 8, (c.x, c.y, z + 10), rgb(color, 0.8))
        else:
            for j in range(3):
                t = c + Vector((math.cos(j * 2.1) * 14, math.sin(j * 2.1) * 14, 0))
                prism(1.2, 8, (t.x, t.y, z), rgb((140, 100, 70)), sides=8)
                ball(6, (t.x, t.y, z + 11), rgb((110, 190, 100)))
    # rope bridges between neighbours, sagging
    for k in range(6):
        a, b = centres[k], centres[(k + 1) % 6]
        d = (b - a)
        start = a + d.normalized() * 33
        end = b - d.normalized() * 33
        n = 16
        for i in range(n):
            t = (i + 0.5) / n
            p = start.lerp(end, t)
            sag = math.sin(t * math.pi) * 4
            box((d.length * 0.62 / n * 0.85, 9, 0.8), (p.x, p.y, z - 0.4 - sag), rgb((200, 160, 110)), rot=math.atan2(d.y, d.x))
    # a glowing drop ring at each island's inner edge
    for c in centres:
        p = c * (112 / c.length)
        prism(6, 0.4, (p.x, p.y, z - 0.5), rgb((255, 211, 111)), emit=1.0, sides=24)
    rnd = random.Random(9)
    pts = []
    for c in centres:
        for _ in range(7):
            a = rnd.random() * math.tau
            d = rnd.random() * 24
            pts.append((c.x + math.cos(a) * d, c.y + math.sin(a) * d))
    crowd(pts, z, seed=10)
    shoot("C_islands_overview", (0, -340, 220), (0, 20, -10), lens=32)
    first = centres[4]
    eye = first * (128 / first.length)
    shoot("C_islands_spectator", (eye.x, eye.y, z + 6), (0, 0, -4), lens=24)


# ═══ round two: a colourful playground with parkour (the user, 2026-11-13: "A colourful lobby
# with things to do and parkour", in the spirit of Super Bomb Survival, not a copy of it) ═══

CANDY = [(255, 95, 95), (255, 165, 50), (255, 215, 60), (90, 205, 110), (70, 165, 255), (175, 105, 255), (255, 110, 200)]


def piece(size, at, color, rot=(0, 0, 0), **kw):
    bpy.ops.mesh.primitive_cube_add(size=1, location=at, rotation=rot)
    o = bpy.context.object
    o.scale = size
    return link(o, mat(color, **kw))


def tube(radius, length, at, color, rot=(0, 0, 0), sides=24, **kw):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=length, location=at, rotation=rot)
    o = bpy.context.object
    return link(o, mat(color, **kw))


def ring_at(cx, cy, inner, outer, z0, z1, color, **kw):
    o = hex_ring(inner, outer, z0, z1, color, **kw)
    o.location = (cx, cy, 0)
    return o


def sector(x, y):
    a = math.atan2(y, x) - math.radians(30)
    return round(a / (math.pi / 3)) % 6


def tiled_plaza(r0, r1, z, skip=(), thickness=3.0):
    """Hex tiles in rings r0..r1 round the arena, a candy colour per side, checkered."""
    for q in range(-r1, r1 + 1):
        for r in range(max(-r1, -q - r1), min(r1, -q + r1) + 1):
            ring = max(abs(q), abs(r), abs(q + r))
            if ring < r0 or (q, r) in skip:
                continue
            x = TILE * 1.5 * q
            y = TILE * SQ3 * (r + q / 2)
            c = CANDY[sector(x, y)]
            k = 1.0 if (q + r * 2) % 2 == 0 else 1.35
            prism(TILE * 0.97, thickness, (x, y, z - thickness), rgb(c, k))


def trampoline(x, y, z, color):
    prism(6.2, 1.4, (x, y, z), rgb((60, 60, 80)), sides=24)
    prism(5.2, 1.6, (x, y, z), rgb(color), sides=24, rough=0.3)


def slide_tower(x, y, z, color, height=34):
    prism(5, height, (x, y, z), rgb((255, 255, 255)), sides=12)
    cone(7, 0, 8, (x, y, z + height), rgb(color), sides=12)
    turns = 1.6
    n = 40
    for i in range(n):
        t = i / n
        a = t * turns * math.tau
        h = z + height - 2 - t * (height - 3)
        piece((5.5, 7, 0.8), (x + math.cos(a) * 9, y + math.sin(a) * 9, h), rgb(CANDY[(i // 4) % len(CANDY)]),
              rot=(math.radians(-14), 0, a + math.pi))


def cannon(x, y, z, aim, color):
    piece((7, 7, 3), (x, y, z + 1.5), rgb((70, 70, 90)), rot=(0, 0, aim))
    tube(2.6, 12, (x + math.cos(aim) * 2, y + math.sin(aim) * 2, z + 7), rgb(color, 0.9),
         rot=(0, math.radians(55), aim))
    tube(3.2, 1.2, (x + math.cos(aim) * 5.4, y + math.sin(aim) * 5.4, z + 11.6), rgb((40, 40, 50)),
         rot=(0, math.radians(55), aim))


def ball_pit(x, y, z, seed=2):
    ring_at(x, y, 13, 15.5, z, z + 3, rgb((255, 255, 255)))
    rnd = random.Random(seed)
    for _ in range(90):
        a = rnd.random() * math.tau
        d = rnd.random() * 12
        ball(1.3, (x + math.cos(a) * d, y + math.sin(a) * d, z + 1 + rnd.random() * 1.2), rgb(rnd.choice(CANDY)), rough=0.3)
    ball(4, (x + 4, y - 3, z + 5), rgb((250, 250, 255)), rough=0.15)


def balloons(points, seed=4):
    rnd = random.Random(seed)
    for (x, y, z) in points:
        ball(2.6, (x, y, z), rgb(rnd.choice(CANDY)), rough=0.25).scale = (1, 1, 1.2)
        piece((0.15, 0.15, 10), (x, y, z - 7.5), rgb((240, 240, 240)))


def podium(x, y, z, aim):
    for j, (h, c) in enumerate(((8, (200, 205, 215)), (12, (255, 205, 60)), (5, (220, 150, 90)))):
        off = (j - 1) * 9
        piece((8, 8, h), (x + math.cos(aim) * off, y + math.sin(aim) * off, z + h / 2), rgb(c))


def board(x, y, z, aim):
    piece((26, 2, 16), (x, y, z + 14), rgb((40, 40, 60)), rot=(0, 0, aim))
    piece((23, 2.2, 13), (x, y, z + 14), rgb((70, 165, 255)), rot=(0, 0, aim), emit=0.8)
    for side in (-1, 1):
        piece((1.5, 1.5, 8), (x + math.cos(aim) * side * 11, y + math.sin(aim) * side * 11, z + 3), rgb((40, 40, 60)))


def queue_pads(x, y, z):
    for j in range(4):
        prism(4.2, 0.8, (x + math.cos(j * 1.57) * 9, y + math.sin(j * 1.57) * 9, z), rgb(SEATS[j]), emit=0.9, sides=24)
    prism(3, 14, (x, y, z), rgb((255, 255, 255)), sides=12)
    ball(4, (x, y, z + 17), rgb((255, 215, 60)), emit=0.8)


def chimney(x, y, z, aim, height=44, color=(255, 255, 255)):
    for side in (-1, 1):
        piece((2.5, 12, height), (x + math.cos(aim) * side * 5, y + math.sin(aim) * side * 5, z + height / 2), rgb(color), rot=(0, 0, aim))
    prism(8, 2, (x, y, z + height), rgb((255, 215, 60)))
    piece((0.4, 0.4, 10), (x, y, z + height + 7), rgb((240, 240, 240)))
    piece((5, 0.3, 3), (x + 2.5, y, z + height + 10), rgb((255, 95, 95)))


def stepping_spiral(start_angle, laps, r0, r1, z0, z1, n, seed=7, size=4.5):
    """Floating hex stones climbing round the outside, gaps for single, double and long jumps."""
    rnd = random.Random(seed)
    last = None
    for i in range(n):
        t = i / (n - 1)
        a = start_angle + t * laps * math.tau
        r = r0 + (r1 - r0) * t + rnd.uniform(-4, 4)
        z = z0 + (z1 - z0) * t
        p = (math.cos(a) * r, math.sin(a) * r, z)
        prism(size, 1.6, p, rgb(CANDY[i % len(CANDY)], 1.1))
        last = p
    return last


def summit(p, color=(255, 215, 60)):
    x, y, z = p
    prism(12, 3, (x, y, z - 1), rgb((255, 255, 255)))
    prism(4, 6, (x, y, z + 2), rgb(color), sides=12)
    cone(5, 0, 6, (x, y, z + 8), rgb(color), sides=5, emit=0.5)
    ball(2.4, (x, y, z + 16), rgb(color), emit=1.2)


def lobby_toys(z, rplaza):
    """One thing to do on each corner of the plaza."""
    kinds = ["Trampolines", "Slide", "Cannon", "Pit", "Podium", "Queue"]
    for k, kind in enumerate(kinds):
        c = corner(rplaza, k)
        aim = math.atan2(c.y, c.x)
        if kind == "Trampolines":
            for j in range(4):
                o = Vector((math.cos(aim + math.pi / 2), math.sin(aim + math.pi / 2), 0)) * ((j - 1.5) * 13)
                trampoline(c.x + o.x, c.y + o.y, z, CANDY[j + 2])
        elif kind == "Slide":
            slide_tower(c.x, c.y, z, CANDY[1])
        elif kind == "Cannon":
            cannon(c.x, c.y, z, aim + math.pi * 0.85, CANDY[0])
            ring_at(c.x - math.cos(aim) * 2, c.y - math.sin(aim) * 2, 1, 1.01, z, z + 0.1, rgb((255, 255, 255)))
        elif kind == "Pit":
            ball_pit(c.x, c.y, z)
        elif kind == "Podium":
            podium(c.x, c.y, z, aim + math.pi / 2)
            board(c.x - math.cos(aim) * 14, c.y - math.sin(aim) * 14, z, aim + math.pi / 2)
        else:
            queue_pads(c.x, c.y, z)


# D: the playground ring. A hex-tiled plaza round the arena, a candy colour per side, a toy on
# each corner, and a parkour spiral of floating stones climbing a whole lap round the outside
# to a summit, with a wall-jump chimney as the shortcut.
def concept_d():
    reset()
    arena(0, gone=GONE)
    clouds(-80, 260, count=50)
    z = 1.0
    tiled_plaza(10, 15, z)
    hex_ring(150, 166, z - 40, z - 3, rgb((235, 228, 245)), outer_low=118)
    lobby_toys(z, 132)
    top = stepping_spiral(math.radians(-60), 1.0, 178, 182, z + 4, z + 66, 46)
    summit((top[0] * 1.0, top[1] * 1.0, top[2] + 3))
    c = corner(176, 3.5)
    chimney(c.x, c.y, z, math.atan2(c.y, c.x))
    rnd = random.Random(11)
    balloons([(math.cos(a) * d, math.sin(a) * d, 30 + rnd.random() * 25) for a, d in
              [(rnd.random() * math.tau, 100 + rnd.random() * 60) for _ in range(18)]])
    rnd = random.Random(12)
    pts = [(math.cos(a) * d, math.sin(a) * d) for a, d in [(rnd.random() * math.tau, 102 + rnd.random() * 52) for _ in range(45)]]
    crowd(pts, z, seed=13)
    shoot("D_playground_overview", (0, -360, 250), (0, 15, 0), lens=30)
    shoot("D_playground_spectator", (-60, -150, 14), (30, 30, 4), lens=22)


# E: two tiers. The playground plaza low down, and above it a ring of floating hex tiles on
# stilts with gaps to jump (the parkour lap), reached by wall-jump chimneys on the corners.
# From the top ring you look down on both the plaza and the round.
def concept_e():
    reset()
    arena(0, gone=GONE)
    clouds(-80, 280, count=55)
    z = 1.0
    tiled_plaza(10, 13, z)
    hex_ring(134, 146, z - 36, z - 3, rgb((235, 228, 245)), outer_low=112)
    lobby_toys(z, 118)
    top = 34.0
    rnd = random.Random(21)
    gaps = set()
    for q in range(-17, 18):
        for r in range(max(-17, -q - 17), min(17, -q + 17) + 1):
            ring = max(abs(q), abs(r), abs(q + r))
            if 15 <= ring <= 16 and rnd.random() < 0.13:
                gaps.add((q, r))
    for q in range(-16, 17):
        for r in range(max(-16, -q - 16), min(16, -q + 16) + 1):
            ring = max(abs(q), abs(r), abs(q + r))
            if 15 <= ring <= 16 and (q, r) not in gaps:
                x = TILE * 1.5 * q
                y = TILE * SQ3 * (r + q / 2)
                c = CANDY[(sector(x, y) + 3) % 6]
                prism(TILE * 0.97, 2, (x, y, top - 2), rgb(c, 1.0 if (q + r) % 2 else 1.3))
    for k in range(12):
        c = corner(162, k / 2)
        prism(2.2, top - 2 - z, (c.x, c.y, z), rgb((255, 255, 255)), sides=12)
    for k in range(6):
        c = corner(146, k + 0.5)
        chimney(c.x, c.y, z, math.atan2(c.y, c.x) + math.pi / 2, height=top - 1, color=CANDY[k])
    s = corner(166, 0)
    summit((s.x * 1.12, s.y * 1.12, top + 18))
    stepping_spiral(math.radians(18), 0.06, 170, 182, top + 2, top + 16, 5, size=4)
    rnd = random.Random(14)
    balloons([(math.cos(a) * d, math.sin(a) * d, 50 + rnd.random() * 20) for a, d in
              [(rnd.random() * math.tau, 100 + rnd.random() * 70) for _ in range(16)]])
    rnd = random.Random(15)
    pts = [(math.cos(a) * d, math.sin(a) * d) for a, d in [(rnd.random() * math.tau, 100 + rnd.random() * 38) for _ in range(36)]]
    crowd(pts, z, seed=16)
    shoot("E_twotier_overview", (0, -380, 260), (0, 15, 5), lens=30)
    c = corner(166, 4.6)
    shoot("E_twotier_spectator", (c.x, c.y, top + 6), (0, 0, 0), lens=22)


# F: parkour islands. Six bright islands round the arena, each with a toy, joined by parkour
# instead of bridges: stepping stones, a balance beam, trampolines across a gap, a wall-jump
# gap, a long-jump run; one is the easy walk round.
def concept_f():
    reset()
    arena(0, gone=GONE)
    clouds(-90, 280, count=60)
    z = 10.0
    centres = []
    kinds = ["Queue", "Trampolines", "Slide", "Pit", "Cannon", "Podium"]
    for k, kind in enumerate(kinds):
        c = corner(150, k + 0.5)
        centres.append(c)
        color = CANDY[k]
        cone(32, 8, 34, (c.x, c.y, z - 38), rgb((150, 120, 100)), rot=0.2)
        prism(33, 4, (c.x, c.y, z - 4), rgb(color, 1.25))
        prism(30, 0.6, (c.x, c.y, z), rgb(color))
        aim = math.atan2(c.y, c.x)
        if kind == "Trampolines":
            for j in range(3):
                trampoline(c.x + (j - 1) * 13, c.y, z + 0.6, CANDY[(j + 3) % 7])
        elif kind == "Slide":
            slide_tower(c.x, c.y, z + 0.6, CANDY[(k + 2) % 7])
        elif kind == "Cannon":
            cannon(c.x, c.y, z + 0.6, aim + math.pi * 0.8, CANDY[(k + 2) % 7])
        elif kind == "Pit":
            ball_pit(c.x, c.y, z + 0.6)
        elif kind == "Podium":
            podium(c.x, c.y, z + 0.6, aim + math.pi / 2)
        else:
            queue_pads(c.x, c.y, z + 0.6)
    for k in range(6):
        a, b = centres[k], centres[(k + 1) % 6]
        d = b - a
        u = d.normalized()
        start, end = a + u * 32, b - u * 32
        span = (end - start).length
        style = k % 6
        if style == 0:  # stepping stones, up and down
            for i in range(7):
                p = start.lerp(end, (i + 0.5) / 7)
                prism(4, 1.5, (p.x, p.y, z - 1 + math.sin(i * 1.3) * 5), rgb(CANDY[i % 7], 1.1))
        elif style == 1:  # balance beam
            mid = (start + end) / 2
            piece((span, 1.4, 1.2), (mid.x, mid.y, z - 0.6), rgb((255, 255, 255)), rot=(0, 0, math.atan2(u.y, u.x)))
        elif style == 2:  # trampolines across the gap
            for i in range(3):
                p = start.lerp(end, (i + 1) / 4)
                piece((1, 1, 30), (p.x, p.y, z - 18), rgb((200, 200, 210)))
                trampoline(p.x, p.y, z - 4, CANDY[(i + 4) % 7])
        elif style == 3:  # a tall wall-jump chimney to cross over
            mid = (start + end) / 2
            for part in (start.lerp(end, 0.15), start.lerp(end, 0.85)):
                piece((10, 10, 3), (part.x, part.y, z - 1.5), rgb(CANDY[k]))
            chimney(mid.x, mid.y, z - 20, math.atan2(u.y, u.x), height=46, color=CANDY[(k + 3) % 7])
        elif style == 4:  # a long-jump run: a ramp, then a gap
            p = start.lerp(end, 0.35)
            piece((span * 0.7, 9, 1.2), (p.x, p.y, z - 0.6), rgb(CANDY[(k + 1) % 7]), rot=(0, 0, math.atan2(u.y, u.x)))
            q = start.lerp(end, 0.9)
            prism(5, 1.5, (q.x, q.y, z - 1.5), rgb(CANDY[(k + 2) % 7]))
        else:  # the easy way: a bridge
            for i in range(14):
                p = start.lerp(end, (i + 0.5) / 14)
                piece((span / 14 * 0.85, 9, 0.8), (p.x, p.y, z - 0.4 - math.sin((i + 0.5) / 14 * math.pi) * 3), rgb((200, 160, 110)), rot=(0, 0, math.atan2(u.y, u.x)))
    s = corner(200, 2)
    stepping_spiral(math.atan2(centres[2].y, centres[2].x) + 0.12, 0.12, 175, 205, z + 3, z + 40, 8, size=4)
    summit((s.x, s.y, z + 46))
    rnd = random.Random(31)
    balloons([(math.cos(a) * d, math.sin(a) * d, 40 + rnd.random() * 25) for a, d in
              [(rnd.random() * math.tau, 110 + rnd.random() * 70) for _ in range(16)]])
    rnd = random.Random(32)
    pts = []
    for c in centres:
        for _ in range(6):
            a, d = rnd.random() * math.tau, rnd.random() * 24
            pts.append((c.x + math.cos(a) * d, c.y + math.sin(a) * d))
    crowd(pts, z + 0.6, seed=33)
    shoot("F_islands_overview", (0, -380, 250), (0, 20, 0), lens=30)
    e = centres[4] * (132 / centres[4].length)
    shoot("F_islands_spectator", (e.x, e.y, z + 8), (40, 60, 0), lens=22)


# ═══ round three: a standard Roblox hub, styled on the user's "AR" place (2026-11-13: "a more
# standard roblox lobby experience ... Something of this style with the arena built in the
# middle", then "we can restyle the arena to match"). AR is a night-time neon city hub: grey
# stone and metal under a blue night, pink/blue/purple neon trim, storefronts with glowing signs
# round a central plaza, lit skyscrapers behind, string lights, trees in planters. ═══

NEON = {"cyan": (60, 220, 255), "blue": (90, 140, 255), "purple": (150, 100, 255), "pink": (255, 90, 200),
        "orange": (255, 140, 60), "green": (90, 255, 140), "yellow": (255, 220, 90)}
STONE = (70, 74, 86)
DARK = (34, 36, 48)


def night_reset():
    reset()
    scene = bpy.context.scene
    world = scene.world
    nodes = world.node_tree.nodes
    ramp = [n for n in nodes if n.type == "VALTORGB"][0]
    ramp.color_ramp.elements[0].color = (0.05, 0.05, 0.16, 1)
    ramp.color_ramp.elements[1].color = (0.01, 0.01, 0.04, 1)
    nodes["Background"].inputs["Strength"].default_value = 1.0
    sun = [o for o in scene.objects if o.type == "LIGHT"][0]
    sun.data.energy = 0.7
    sun.data.color = (0.55, 0.6, 1.0)
    try:
        scene.eevee.use_raytracing = True
    except AttributeError:
        pass


def glow(color, strength=6.0):
    return mat(rgb(color), emit=strength, rough=0.4)


def window_mat(color, seed=0):
    key = ("win", color, seed)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("win%d" % len(_mats))
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = rgb(DARK)
    brick = nt.nodes.new("ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 0.11
    brick.inputs["Mortar Size"].default_value = 0.12
    brick.inputs["Brick Width"].default_value = 0.5
    brick.inputs["Row Height"].default_value = 0.35
    brick.offset = 0
    brick.inputs["Color1"].default_value = rgb(color, 1.0)
    brick.inputs["Color2"].default_value = rgb(color, 0.25)
    brick.inputs["Mortar"].default_value = (0, 0, 0, 1)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    nt.links.new(geo.outputs["Position"], brick.inputs["Vector"])
    nt.links.new(brick.outputs["Color"], b.inputs["Emission Color"])
    b.inputs["Emission Strength"].default_value = 2.5
    _mats[key] = m
    return m


def tower(x, y, w, d, h, color, rot=0.0, seed=0):
    """A dark skyscraper, its face to the plaza lit with a grid of windows (some dark)."""
    piece((w, d, h), (x, y, h / 2 - 20), rgb(DARK), rot=(0, 0, rot))
    piece((w + 0.6, d + 0.6, 1.2), (x, y, h - 20), glow(color, 4), rot=(0, 0, rot))
    rnd = random.Random(seed)
    bm = bmesh.new()
    out = Vector((math.cos(rot), math.sin(rot), 0))
    side = Vector((-math.sin(rot), math.cos(rot), 0))
    face = Vector((x, y, 0)) - out * (w / 2 + 0.05)
    cols = max(2, int(d / 5))
    rows = max(3, int(h / 6))
    for i in range(cols):
        for j in range(rows):
            if rnd.random() < 0.3:
                continue
            c = face + side * ((i + 0.5) / cols - 0.5) * (d - 3)
            zc = -20 + 4 + j * (h - 6) / rows
            hw, hh = 1.4, 1.8
            vs = [bm.verts.new(c + side * sx * hw + Vector((0, 0, zc + sz * hh))) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            bm.faces.new(vs)
    me = bpy.data.meshes.new("windows")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("windows", me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(glow(color, 3))
    return o


def sign(text, at, facing, color, size=7.0):
    bpy.ops.object.text_add(location=at, rotation=(math.radians(90), 0, facing))
    t = bpy.context.object
    t.data.body = text
    t.data.size = size
    t.data.extrude = 0.4
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    t.data.materials.append(glow(color, 9))
    return t


def neon_arena(z=0.0, rings=7, gone=()):
    """The arena restyled to match: dark slate tiles, each edged in neon, cyan in the middle
    through purple to pink at the rim (a ring's colour still says how close to the edge you are)."""
    ramp = [NEON["cyan"], NEON["cyan"], NEON["blue"], NEON["blue"], NEON["purple"], NEON["purple"], NEON["pink"], NEON["pink"]]
    rnd = random.Random(4)
    for q in range(-rings, rings + 1):
        for r in range(max(-rings, -q - rings), min(rings, -q + rings) + 1):
            ring = max(abs(q), abs(r), abs(q + r))
            if (q, r) in gone:
                continue
            x = TILE * 1.5 * q
            y = TILE * SQ3 * (r + q / 2)
            warn = ring == rings and rnd.random() < 0.08
            edge = (255, 60, 60) if warn else ramp[ring]
            prism(TILE * 0.97, 2.5, (x, y, z - 2.5), glow(edge, 5 if warn else 3.5))
            prism(TILE * 0.82, 2.56, (x, y, z - 2.5), rgb(STONE if (q + r * 2) % 2 == 0 else (58, 62, 74)), rough=0.5)
    for i, (x, y) in enumerate([(-22, 14), (18, 26), (10, -30)]):
        ball(4, (x, y, z + 4), rgb((230, 240, 255)), rough=0.1, emit=0.15)
        person((x, y, z + 8), SEATS[i])
    person((-35, -18, z), SEATS[3])


def tree(x, y, z):
    prism(4, 2, (x, y, z), rgb(STONE), sides=6)
    prism(0.8, 7, (x, y, z + 2), rgb((90, 60, 50)), sides=8)
    for j in range(3):
        ball(3.2 - j * 0.4, (x + (j - 1) * 1.6, y + (j % 2), z + 10 + j * 1.2), rgb((50, 120, 70)), rough=0.9)


def string_lights(a, b, sag, z, n=18, seed=1):
    rnd = random.Random(seed)
    colors = list(NEON.values())
    for i in range(n + 1):
        t = i / n
        p = a.lerp(b, t)
        h = z - math.sin(t * math.pi) * sag
        ball(0.7, (p.x, p.y, h), glow(rnd.choice(colors), 12))


STORES = [("PLAY", "cyan"), ("SHOP", "pink"), ("LEADERBOARD", "yellow"), ("PRACTICE", "green"), ("REWARDS", "orange"), ("LOCKER", "purple")]


def concept_g():
    night_reset()
    neon_arena(0, gone=GONE)
    z = 3.0
    # the plaza: dark paving, raised a little above the arena, a neon rail at its inner edge
    hex_ring(96, 158, z - 6, z, rgb(STONE))
    hex_ring(96, 96.6, z, z + 3.5, (0.6, 0.85, 1, 1), glass=True, rough=0.05)
    hex_ring(95.9, 96.7, z + 3.5, z + 4.0, glow(NEON["cyan"], 6))
    hex_ring(120, 121, z, z + 0.15, glow(NEON["blue"], 3))
    hex_ring(96, 158, z - 60, z - 6, rgb(DARK), outer_low=100)
    # six storefronts, one on each side, facing the arena
    for k, (name, colour) in enumerate(STORES):
        mid = corner(166, k + 0.5)
        facing = math.atan2(mid.y, mid.x)
        c = NEON[colour]
        width = 62 if name != "PLAY" else 74
        bpy.ops.mesh.primitive_cube_add(size=1, location=(mid.x, mid.y, z + 15), rotation=(0, 0, facing))
        shell = bpy.context.object
        shell.scale = (22, width, 30)
        shell.data.materials.append(mat(rgb((52, 55, 68)), rough=0.5))
        inward = Vector((-math.cos(facing), -math.sin(facing), 0))
        front = mid + inward * 11.2
        side = Vector((-math.sin(facing), math.cos(facing), 0))
        # glowing doorway, frame, awning and the sign
        piece((0.6, width * 0.45, 13), (front.x, front.y, z + 6.5), glow(c, 2.5), rot=(0, 0, facing))
        for s in (-1, 1):
            p = front + side * (width / 2 - 1)
            p = front + side * s * (width / 2 - 1)
            piece((1, 1.2, 30), (p.x, p.y, z + 15), glow(c, 6), rot=(0, 0, facing))
        piece((1, width, 1.2), (front.x, front.y, z + 30), glow(c, 6), rot=(0, 0, facing))
        awn = front + inward * 3
        piece((7, width * 0.7, 0.8), (awn.x, awn.y, z + 14.5), rgb(c, 0.6), rot=(math.radians(-12) * 0, 0, facing))
        sg = front + inward * 0.8
        sign(name, (sg.x, sg.y, z + 22), facing - math.pi / 2, c, size=7.5 if len(name) < 8 else 5.5)
        if name == "PLAY":
            for j in range(4):
                p = front + inward * 12 + side * ((j - 1.5) * 10)
                prism(4, 0.5, (p.x, p.y, z), glow(SEATS[j], 4), sides=24)
            bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=3, depth=500, location=(mid.x, mid.y, z + 250))
            beam = bpy.context.object
            beam.data.materials.append(mat(rgb(c), emit=4, glass=True))
    # the corners: planters with trees and lamp posts
    for k in range(6):
        cc = corner(148, k)
        tree(cc.x, cc.y, z)
        for s in (-1, 1):
            p = corner(140, k + s * 0.12)
            prism(0.4, 9, (p.x, p.y, z), rgb(DARK), sides=8)
            ball(1, (p.x, p.y, z + 9.5), glow(NEON["yellow"], 10))
    # string lights from store to store across each corner
    for k in range(6):
        a = corner(150, k - 0.35)
        b = corner(150, k + 0.35)
        string_lights(a, b, 5, z + 26, seed=k)
    # the city behind: lit towers
    rnd = random.Random(42)
    palette = [NEON["blue"], NEON["purple"], NEON["pink"], NEON["cyan"], NEON["orange"], NEON["green"]]
    for i in range(48):
        a = rnd.random() * math.tau
        d = 215 + rnd.random() * 160
        tower(math.cos(a) * d, math.sin(a) * d, 22 + rnd.random() * 26, 22 + rnd.random() * 26,
              70 + rnd.random() * 170, rnd.choice(palette), rot=a, seed=i)
    rnd = random.Random(19)
    pts = [(math.cos(a) * d, math.sin(a) * d) for a, d in [(rnd.random() * math.tau, 102 + rnd.random() * 40) for _ in range(40)]]
    crowd(pts, z, seed=20)
    shoot("G_neon_overview", (0, -330, 230), (0, 30, -5), lens=28)
    shoot("G_neon_spectator", (-30, -128, 10), (10, 40, 8), lens=22)
    shoot("G_neon_play", (40, 80, 14), (-55, -100, 18), lens=22)


for key, fn in (("A", concept_a), ("B", concept_b), ("C", concept_c), ("D", concept_d), ("E", concept_e), ("F", concept_f), ("G", concept_g)):
    if key in WANTED:
        fn()
