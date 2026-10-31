#!/usr/bin/env python3
"""
Bunker Door Generator for 'White King' (Zugzwang)
Creates a detailed, reinforced, weathered wooden bunker door:
- Heavy outer steel frame with perimeter bolts/rivets
- Inner steel leaf frame with corner gussets
- Vertical wooden planks with procedural wood grain, knots, and noise
- 3 heavy horizontal iron reinforcement straps with 3D round rivets
- Heavy multi-segment barrel hinges on the left
- Heavy armored lock box and industrial tubular grab handle on the right
- Solid door with NO window (as requested)
- Saves to MagicaVoxel .vox and exports to .obj, .mtl, and .png palette
"""

import os
import sys
import math
import struct
from pathlib import Path
from PIL import Image

# Setup paths
PROJECT_ROOT = Path(r"c:\Users\carpe\OneDrive\Documents\zugzwang")
MV_REPO_VOX = Path(r"C:\Users\carpe\source\repos\magicavoxel-mcp\vox")
MV_APP_VOX = Path(r"F:\MagicaVoxel\MagicaVoxel-0.99.6.4-win64\vox\zugzwang")

SIZE_X = 64   # Width (0..63)
SIZE_Y = 20   # Depth (0..19: front is low Y=1..8, back is high Y=9..16)
SIZE_Z = 128  # Height (0..127)

def hash_noise(x: int, z: int, seed: int = 1337) -> float:
    n = (x * 374761393 + z * 668265263 + seed * 1013904223) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return (((n ^ (n >> 16)) & 0xFFFF) / 65535.0)

def smooth_noise(x: float, z: float, seed: int = 1337) -> float:
    x0, z0 = int(math.floor(x)), int(math.floor(z))
    x1, z1 = x0 + 1, z0 + 1
    fx, fz = x - x0, z - z0
    # Quintic blend
    fx = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
    fz = fz * fz * fz * (fz * (fz * 6.0 - 15.0) + 10.0)
    
    s00 = hash_noise(x0, z0, seed)
    s10 = hash_noise(x1, z0, seed)
    s01 = hash_noise(x0, z1, seed)
    s11 = hash_noise(x1, z1, seed)
    
    top = s00 * (1.0 - fx) + s10 * fx
    bot = s01 * (1.0 - fx) + s11 * fx
    return top * (1.0 - fz) + bot * fz

def fbm_noise(x: float, z: float, octaves: int = 3, seed: int = 1337) -> float:
    total = 0.0
    amp = 1.0
    freq = 1.0
    max_amp = 0.0
    for i in range(octaves):
        total += smooth_noise(x * freq, z * freq, seed + i * 99) * amp
        max_amp += amp
        amp *= 0.5
        freq *= 2.0
    return total / max_amp

# Palette indices
# Wood: 10..18
# Steel / Iron: 20..27
# Rust / Grunge: 28..29
# Hinges & Hardware: 30..34
PALETTE = [(0, 0, 0, 0)] * 256

def init_palette():
    # Wood shades (warm, aged bunker oak/walnut)
    PALETTE[10] = (28, 16, 10, 255)   # Deep crevice / dark seam
    PALETTE[11] = (46, 27, 16, 255)   # Dark grain shadow
    PALETTE[12] = (64, 38, 22, 255)   # Deep walnut brown
    PALETTE[13] = (82, 50, 29, 255)   # Classic bunker oak base
    PALETTE[14] = (100, 62, 36, 255)  # Mid warm timber
    PALETTE[15] = (118, 74, 43, 255)  # Lighter grain accent
    PALETTE[16] = (136, 86, 50, 255)  # Warm highlight grain
    PALETTE[17] = (154, 98, 58, 255)  # Weathered light wood
    PALETTE[18] = (22, 12, 8, 255)    # Dark knot center

    # Iron / Steel / Bunker frame
    PALETTE[20] = (16, 17, 20, 255)   # Deep metal shadow
    PALETTE[21] = (26, 28, 32, 255)   # Dark bunker steel frame
    PALETTE[22] = (38, 41, 46, 255)   # Base reinforced iron
    PALETTE[23] = (52, 56, 62, 255)   # Medium cold steel plate
    PALETTE[24] = (68, 73, 82, 255)   # Lighter steel plate face
    PALETTE[25] = (88, 95, 106, 255)  # Steel bevel / edge highlight
    PALETTE[26] = (120, 130, 144, 255) # Bolt / rivet specular highlight
    PALETTE[27] = (165, 175, 192, 255) # Bright glint

    # Rust / Dirt
    PALETTE[28] = (60, 34, 24, 255)   # Dark oxide rust
    PALETTE[29] = (88, 46, 30, 255)   # Warm rust speckle

    # Hardware / Latch / Hinges
    PALETTE[30] = (20, 22, 25, 255)   # Hardware dark shadow
    PALETTE[31] = (32, 35, 40, 255)   # Hardware body
    PALETTE[32] = (48, 52, 60, 255)   # Hardware mid
    PALETTE[33] = (70, 77, 88, 255)   # Hardware highlight
    PALETTE[34] = (95, 105, 120, 255) # Hardware rim / bolt

    # Fill remaining colors with neutral tones
    for i in range(1, 256):
        if PALETTE[i] == (0, 0, 0, 0):
            g = min(255, i)
            PALETTE[i] = (g, g, g, 255)

class BunkerDoorBuilder:
    def __init__(self):
        self.voxels = {}  # (x, y, z) -> color_index
        init_palette()

    def set_voxel(self, x: int, y: int, z: int, c: int):
        if 0 <= x < SIZE_X and 0 <= y < SIZE_Y and 0 <= z < SIZE_Z:
            self.voxels[(x, y, z)] = c

    def fill_box(self, x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, c: int):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                for z in range(min(z0, z1), max(z0, z1) + 1):
                    self.set_voxel(x, y, z, c)

    def build(self):
        print("1. Generating Outer Doorway Frame...")
        self._build_outer_frame()

        print("2. Generating Vertical Wooden Planks with Grain & Noise...")
        self._build_wood_panels()

        print("3. Generating Inner Leaf Perimeter Frame & Gussets...")
        self._build_leaf_border()

        print("4. Generating 3 Heavy Iron Reinforcing Straps with 3D Rivets...")
        self._build_reinforcing_straps()

        print("5. Generating Heavy Industrial Hinges (Left)...")
        self._build_hinges()

        print("6. Generating Deadbolt Lock Box and Heavy Grip Handle (Right)...")
        self._build_lock_and_handle()

        print("7. Adding Weathering & Distress Details...")
        self._add_weathering()

    def _build_outer_frame(self):
        # Outer steel frame: left (0..5), right (58..63), top (124..127), sill (0..2)
        # Depth y=5..13
        # Main frame volume
        self.fill_box(0, 5, 0, 5, 13, 127, 21)
        self.fill_box(58, 5, 0, 63, 13, 127, 21)
        self.fill_box(0, 5, 124, 63, 13, 127, 21)
        self.fill_box(0, 5, 0, 63, 13, 2, 21)

        # Stepped front reveal / chamfer at y=5
        for z in range(0, 128):
            # Left jamb front face
            for x in range(0, 5):
                n = hash_noise(x, z, 101)
                c = 21 if n > 0.4 else (22 if n > 0.15 else 20)
                self.set_voxel(x, 5, z, c)
            # Right jamb front face
            for x in range(59, 64):
                n = hash_noise(x, z, 102)
                c = 21 if n > 0.4 else (22 if n > 0.15 else 20)
                self.set_voxel(x, 5, z, c)

        # Header front face
        for x in range(0, 64):
            for z in range(125, 128):
                n = hash_noise(x, z, 103)
                c = 21 if n > 0.3 else (22 if n > 0.1 else 20)
                self.set_voxel(x, 5, z, c)

        # Sill front face (wear on bottom step)
        for x in range(0, 64):
            for z in range(0, 3):
                c = 22 if z == 2 else 20
                self.set_voxel(x, 5, z, c)

        # Frame perimeter bolts (heavy industrial anchoring bolts)
        # Left jamb bolts
        for bz in [8, 24, 40, 56, 72, 88, 104, 120]:
            self._add_rivet(2, 4, bz, size=2, highlight_col=26, shadow_col=20)
        # Right jamb bolts
        for bz in [8, 24, 40, 56, 72, 88, 104, 120]:
            self._add_rivet(60, 4, bz, size=2, highlight_col=26, shadow_col=20)
        # Header bolts
        for bx in [16, 32, 48]:
            self._add_rivet(bx, 4, 126, size=2, highlight_col=26, shadow_col=20)

    def _build_wood_panels(self):
        # 6 Vertical wooden planks:
        # Plank boundaries:
        # P0: 9..15 (7w), P1: 17..23 (7w), P2: 25..32 (8w), P3: 34..41 (8w), P4: 43..49 (7w), P5: 51..55 (5w)
        # Seams: 8, 16, 24, 33, 42, 50, 56 (dark shadow grooves)
        planks = [
            (9, 15, -0.05),   # (x_start, x_end, plank_tint_offset)
            (17, 23, 0.08),
            (25, 32, -0.02),
            (34, 41, 0.05),
            (43, 49, -0.08),
            (51, 55, 0.02),
        ]
        seams = [8, 16, 24, 33, 42, 50, 56]

        # Natural knots in wood (x_center, z_center, radius)
        knots = [
            (20, 82, 3.5),   # Plank 1 upper knot
            (37, 36, 4.0),   # Plank 3 lower knot
            (46, 92, 3.0),   # Plank 4 upper knot
            (12, 48, 2.8),   # Plank 0 mid knot
        ]

        # Fill wood core from y=8 to y=10
        for z in range(5, 122):
            for x in range(8, 57):
                for y in range(8, 11):
                    self.set_voxel(x, y, z, 12)

        # Procedural texturing on front face (y=8)
        for z in range(5, 122):
            # Seams
            for sx in seams:
                self.set_voxel(sx, 8, z, 10) # dark seam crevice
                # Slightly recess seam
                self.set_voxel(sx, 7, z, 0)

            # Planks texturing
            for p_idx, (px0, px1, tint) in enumerate(planks):
                for x in range(px0, px1 + 1):
                    # Check distance to knots
                    in_knot = False
                    knot_dist_factor = 1.0
                    for kx, kz, kr in knots:
                        dx = (x - kx) * 1.5
                        dz = (z - kz) * 0.4
                        dist = math.sqrt(dx * dx + dz * dz)
                        if dist < kr:
                            in_knot = True
                            if dist < kr * 0.4:
                                wood_col = 18 # Dark knot core
                            elif dist < kr * 0.7:
                                wood_col = 11 # Knot ring
                            else:
                                wood_col = 15 # Knot rim highlight
                            break
                        elif dist < kr * 2.0:
                            knot_dist_factor = 1.0 + (kr * 2.0 - dist) * 0.25

                    if in_knot:
                        self.set_voxel(x, 8, z, wood_col)
                        continue

                    # Wood grain formula:
                    # Vertical grain along Z, modulated by subtle waves and multi-octave noise
                    grain_wave = math.sin((z * 0.18 + tint * 10.0) * knot_dist_factor) * 0.6
                    fine_grain = math.sin(z * 0.8 + x * 0.3) * 0.3
                    coarse_noise = fbm_noise(x * 0.4, z * 0.08, octaves=3, seed=500 + p_idx * 17)
                    micro_noise = (hash_noise(x, z, seed=900) - 0.5) * 0.35

                    val = 0.5 + tint + grain_wave * 0.25 + fine_grain * 0.15 + (coarse_noise - 0.5) * 0.45 + micro_noise

                    # Map val (0..1) to wood palette [11..17]
                    if val < 0.20:
                        wood_col = 11
                    elif val < 0.35:
                        wood_col = 12
                    elif val < 0.50:
                        wood_col = 13
                    elif val < 0.65:
                        wood_col = 14
                    elif val < 0.80:
                        wood_col = 15
                    elif val < 0.92:
                        wood_col = 16
                    else:
                        wood_col = 17

                    # Micro surface depth noise (weathered gouges)
                    if micro_noise < -0.15 and hash_noise(x, z, 777) < 0.18:
                        # Slight recess
                        self.set_voxel(x, 8, z, 10)
                    else:
                        self.set_voxel(x, 8, z, wood_col)

                    # Back face of wood (y=10) with matching grain
                    b_val = (val + coarse_noise) * 0.5
                    b_col = 12 if b_val < 0.45 else (13 if b_val < 0.75 else 14)
                    self.set_voxel(x, 10, z, b_col)

    def _build_leaf_border(self):
        # Steel border directly framing the door leaf:
        # Left border: 6..7, z in 3..123, y in 7..9
        # Right border: 56..57, z in 3..123, y in 7..9
        # Bottom border: 6..57, z in 3..5, y in 7..9
        # Top border: 6..57, z in 121..123, y in 7..9
        self.fill_box(6, 7, 3, 8, 9, 123, 22)
        self.fill_box(55, 7, 3, 57, 9, 123, 22)
        self.fill_box(6, 7, 3, 57, 9, 5, 22)
        self.fill_box(6, 7, 121, 57, 9, 123, 22)

        # Chamfer highlights on leaf frame
        for z in range(3, 124):
            # Left edge
            n = hash_noise(6, z, 201)
            self.set_voxel(6, 7, z, 24 if n > 0.6 else 22)
            self.set_voxel(8, 7, z, 20 if n > 0.5 else 21) # shadow drop onto wood
            # Right edge
            n = hash_noise(57, z, 202)
            self.set_voxel(57, 7, z, 24 if n > 0.6 else 22)
            self.set_voxel(55, 7, z, 20 if n > 0.5 else 21)

        # Top and bottom highlights
        for x in range(6, 58):
            self.set_voxel(x, 7, 123, 25) # top rim highlight
            self.set_voxel(x, 7, 121, 20) # shadow
            self.set_voxel(x, 7, 5, 20)
            self.set_voxel(x, 7, 3, 23)

        # Heavy corner reinforcement gusset plates (L-brackets at 4 corners):
        # Bottom-Left
        self.fill_box(6, 6, 3, 12, 7, 9, 22)
        self._add_rivet(9, 5, 6, size=2, highlight_col=26, shadow_col=20)
        # Bottom-Right
        self.fill_box(51, 6, 3, 57, 7, 9, 22)
        self._add_rivet(54, 5, 6, size=2, highlight_col=26, shadow_col=20)
        # Top-Left
        self.fill_box(6, 6, 117, 12, 7, 123, 22)
        self._add_rivet(9, 5, 120, size=2, highlight_col=26, shadow_col=20)
        # Top-Right
        self.fill_box(51, 6, 117, 57, 7, 123, 22)
        self._add_rivet(54, 5, 120, size=2, highlight_col=26, shadow_col=20)

    def _build_reinforcing_straps(self):
        # 3 Massive horizontal iron crossbars spanning the width (x in 6..57)
        # Strap 1 (Bottom): z in 18..26 (height 9)
        # Strap 2 (Middle): z in 58..66 (height 9)
        # Strap 3 (Top):    z in 98..106 (height 9)
        # Depth y=6..7 (protruding 2 voxels in front of wood!)
        straps_z = [
            (18, 26),
            (58, 66),
            (98, 106),
        ]

        # Rivet X positions across the door (spaced evenly across planks)
        rivet_xs = [9, 17, 25, 33, 41, 49, 55]

        for z0, z1 in straps_z:
            # Main strap bar volume
            for x in range(6, 58):
                for z in range(z0, z1 + 1):
                    # Texture with iron noise
                    n = hash_noise(x, z, seed=z0 * 13)
                    if z == z1:
                        c = 24  # Top beveled edge highlight
                    elif z == z0:
                        c = 20  # Bottom shadow edge
                    elif x == 6 or x == 57:
                        c = 23
                    else:
                        c = 22 if n > 0.35 else (23 if n > 0.15 else 21)
                    self.set_voxel(x, 6, z, c)
                    self.set_voxel(x, 7, z, 21)

            # Shadow cast onto wood right below and above the strap
            for x in range(8, 56):
                if z0 - 1 >= 5:
                    self.set_voxel(x, 8, z0 - 1, 10)
                if z1 + 1 <= 122:
                    self.set_voxel(x, 8, z1 + 1, 10)

            # Heavy protruding rivets / bolts along each strap
            mid_z = (z0 + z1) // 2
            for rx in rivet_xs:
                self._add_rivet(rx, 5, mid_z, size=2, highlight_col=26, shadow_col=20)

    def _add_rivet(self, x: int, y: int, z: int, size: int = 2, highlight_col: int = 26, shadow_col: int = 20):
        # 2x2 round bolt head protruding at y
        self.set_voxel(x, y, z + 1, highlight_col)   # Top-left specular glint
        self.set_voxel(x + 1, y, z + 1, 24)         # Top-right highlight
        self.set_voxel(x, y, z, 23)                 # Bottom-left mid
        self.set_voxel(x + 1, y, z, shadow_col)     # Bottom-right shadow

    def _build_hinges(self):
        # Heavy multi-segment industrial barrel hinges on the left (x in 2..8)
        # Aligned with upper and lower straps:
        # Lower hinge: z in 16..28
        # Upper hinge: z in 96..108
        hinges = [(16, 28), (96, 108)]

        for z0, z1 in hinges:
            # Frame mounting plate on left jamb (x in 2..5, y in 5..7)
            self.fill_box(2, 5, z0 + 1, 5, 7, z1 - 1, 22)
            # Mounting bolts
            self._add_rivet(3, 4, z0 + 3, size=2, highlight_col=26, shadow_col=20)
            self._add_rivet(3, 4, z1 - 3, size=2, highlight_col=26, shadow_col=20)

            # Cylindrical hinge knuckle / pin barrel at x=5..7, y=4..6
            for z in range(z0, z1 + 1):
                # Knuckle segment division (3 segments: frame, door, frame)
                seg = (z - z0) // 4
                base_c = 23 if seg % 2 == 0 else 22
                
                # Cross section of cylindrical pin (rounded shape)
                self.set_voxel(5, 5, z, base_c)
                self.set_voxel(6, 5, z, base_c)
                self.set_voxel(7, 5, z, base_c)
                self.set_voxel(6, 4, z, 25 if z in (z0, z1) else 24) # front highlight
                self.set_voxel(5, 4, z, 26 if z in (z0, z1) else 25)
                self.set_voxel(7, 4, z, 23)

            # Hinge pin top and bottom caps
            self.set_voxel(6, 4, z1 + 1, 26)
            self.set_voxel(6, 5, z1 + 1, 24)
            self.set_voxel(6, 4, z0 - 1, 20)
            self.set_voxel(6, 5, z0 - 1, 20)

    def _build_lock_and_handle(self):
        # Heavy armored deadbolt lock box (aligned with middle strap, x in 50..58, z in 58..66)
        # Protrudes out to y=4..6
        self.fill_box(50, 4, 59, 57, 6, 65, 31)

        # Beveled edges on lock box
        for x in range(50, 58):
            self.set_voxel(x, 4, 65, 33) # top edge highlight
            self.set_voxel(x, 4, 59, 30) # bottom edge shadow
        for z in range(59, 66):
            self.set_voxel(50, 4, z, 33) # left edge highlight
            self.set_voxel(57, 4, z, 30) # right edge shadow

        # Heavy deadbolt bar extending into the right door jamb (x in 57..60, y in 5..6, z in 61..63)
        self.fill_box(57, 5, 61, 60, 6, 63, 24)

        # Mortise / Keyway / Latch slot detail on face (x=53..54, z=61..63)
        self.set_voxel(53, 4, 62, 20) # keyhole slot
        self.set_voxel(54, 4, 62, 20)
        self.set_voxel(53, 4, 61, 20)

        # Heavy Industrial Grab Handle (Right side: x in 44..46, z in 68..88)
        # Stand-offs at top and bottom extending from door leaf (y=7) forward to y=3:
        # Top standoff: z in 86..88, x in 44..46
        self.fill_box(44, 4, 86, 46, 6, 88, 31)
        self._add_rivet(45, 3, 87, size=2, highlight_col=34, shadow_col=30) # mounting flange bolt
        
        # Bottom standoff: z in 68..70, x in 44..46
        self.fill_box(44, 4, 68, 46, 6, 70, 31)
        self._add_rivet(45, 3, 69, size=2, highlight_col=34, shadow_col=30)

        # Vertical tubular grip bar: z in 70..86, x in 44..45, y in 3..4
        for z in range(70, 87):
            # Curved tubular grip profile
            self.set_voxel(44, 3, z, 33) # front-left highlight
            self.set_voxel(45, 3, z, 32) # front-right
            self.set_voxel(44, 4, z, 32)
            self.set_voxel(45, 4, z, 30) # inner shadow

        # Elbow bends at top and bottom of handle grip
        self.set_voxel(44, 3, 87, 34)
        self.set_voxel(44, 3, 69, 31)

    def _add_weathering(self):
        # Subtle rust and wear accents around lower strap and sill
        for x in range(6, 58):
            for z in range(16, 20):
                if hash_noise(x, z, seed=444) < 0.12:
                    if (x, 6, z) in self.voxels:
                        self.set_voxel(x, 6, z, 28) # dark rust
                    elif (x, 7, z) in self.voxels:
                        self.set_voxel(x, 7, z, 29) # warm rust speckle

        # Rust around door sill (z in 2..4)
        for x in range(6, 58):
            if hash_noise(x, 3, seed=555) < 0.20:
                self.set_voxel(x, 5, 3, 28)

def export_vox(builder: BunkerDoorBuilder, output_paths: list[Path]):
    """Export to MagicaVoxel .vox binary format"""
    num_voxels = len(builder.voxels)
    size_chunk_size = 12
    size_chunk_child = 0
    xyzi_chunk_size = 4 + (num_voxels * 4)
    xyzi_chunk_child = 0
    rgba_chunk_size = 256 * 4
    rgba_chunk_child = 0
    main_chunk_size = 0
    main_chunk_child = 8 + size_chunk_size + 8 + xyzi_chunk_size + 8 + rgba_chunk_size

    for path in output_paths:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, 'wb') as f:
            f.write(b'VOX ')
            f.write(struct.pack('<I', 150))
            f.write(b'MAIN')
            f.write(struct.pack('<I', main_chunk_size))
            f.write(struct.pack('<I', main_chunk_child))
            # SIZE
            f.write(b'SIZE')
            f.write(struct.pack('<I', size_chunk_size))
            f.write(struct.pack('<I', size_chunk_child))
            f.write(struct.pack('<I', SIZE_X))
            f.write(struct.pack('<I', SIZE_Y))
            f.write(struct.pack('<I', SIZE_Z))
            # XYZI
            f.write(b'XYZI')
            f.write(struct.pack('<I', xyzi_chunk_size))
            f.write(struct.pack('<I', xyzi_chunk_child))
            f.write(struct.pack('<I', num_voxels))
            for (x, y, z), c in builder.voxels.items():
                f.write(struct.pack('<B', x))
                f.write(struct.pack('<B', y))
                f.write(struct.pack('<B', z))
                f.write(struct.pack('<B', c))
            # RGBA
            f.write(b'RGBA')
            f.write(struct.pack('<I', rgba_chunk_size))
            f.write(struct.pack('<I', rgba_chunk_child))
            for r, g, b, a in PALETTE:
                f.write(struct.pack('<B', r))
                f.write(struct.pack('<B', g))
                f.write(struct.pack('<B', b))
                f.write(struct.pack('<B', a))
        print(f"Saved .vox: {path} ({num_voxels} voxels)")

def export_obj_mesh(builder: BunkerDoorBuilder, obj_path: Path, mtl_path: Path, png_path: Path):
    """
    Exports voxel model to Wavefront OBJ with greedy meshing and 256x256 palette texture.
    Matches MagicaVoxel coordinate convention and Godot 4 standard.
    """
    voxels = builder.voxels

    # 1. Export Palette PNG (256x256, column X has palette color X)
    img = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
    for x in range(256):
        col = PALETTE[x]
        for y in range(256):
            img.putpixel((x, y), col)
    img.save(png_path)
    print(f"Saved palette texture: {png_path}")

    # 2. Export MTL
    with open(mtl_path, 'w') as f:
        f.write("# MagicaVoxel @ Ephtracy / White King\n\n")
        f.write("newmtl palette\n")
        f.write("illum 1\n")
        f.write("Ka 0.000 0.000 0.000\n")
        f.write("Kd 1.000 1.000 1.000\n")
        f.write("Ks 0.000 0.000 0.000\n")
        f.write(f"map_Kd {png_path.name}\n")
    print(f"Saved material: {mtl_path}")

    # 3. Greedy Meshing for exposed faces
    # 6 directions:
    # +X: dir=(+1, 0, 0), u_axis=Z, v_axis=Y
    # -X: dir=(-1, 0, 0), u_axis=Z, v_axis=Y
    # +Y_vox: (-Z in OBJ), dir=(0, +1, 0), u_axis=X, v_axis=Z
    # -Y_vox: (+Z in OBJ), dir=(0, -1, 0), u_axis=X, v_axis=Z
    # +Z_vox: (+Y in OBJ), dir=(0, 0, +1), u_axis=X, v_axis=Y
    # -Z_vox: (-Y in OBJ), dir=(0, 0, -1), u_axis=X, v_axis=Y

    vertices = []
    texcoords = []
    normals = [
        (-1.0, 0.0, 0.0),  # vn 1: -X
        (1.0, 0.0, 0.0),   # vn 2: +X
        (0.0, 0.0, 1.0),   # vn 3: +Z (which is -Y in voxel!)
        (0.0, 0.0, -1.0),  # vn 4: -Z (which is +Y in voxel!)
        (0.0, -1.0, 0.0),  # vn 5: -Y (which is -Z in voxel!)
        (0.0, 1.0, 0.0),   # vn 6: +Y (which is +Z in voxel!)
    ]

    vert_map = {}
    def get_vert_idx(pt):
        # Round to 4 decimal places for deduplication
        key = (round(pt[0], 4), round(pt[1], 4), round(pt[2], 4))
        if key not in vert_map:
            vert_map[key] = len(vertices) + 1
            vertices.append(pt)
        return vert_map[key]

    uv_map = {}
    def get_uv_idx(color_idx):
        if color_idx not in uv_map:
            u = (color_idx + 0.5) / 256.0
            v = 0.5
            uv_map[color_idx] = len(texcoords) + 1
            texcoords.append((u, v))
        return uv_map[color_idx]

    faces = [] # list of (v1, v2, v3, vt, vn)

    def to_obj_coords(vx, vy, vz):
        ox = (vx - SIZE_X / 2.0) * 0.1
        oy = vz * 0.1
        oz = (SIZE_Y / 2.0 - vy) * 0.1
        return (ox, oy, oz)

    # 1. Faces along X axis (+X and -X)
    for x in range(SIZE_X):
        # Check +X face: solid at x, empty at x+1
        mask_pos = {}
        # Check -X face: solid at x, empty at x-1
        mask_neg = {}
        for y in range(SIZE_Y):
            for z in range(SIZE_Z):
                c = voxels.get((x, y, z), 0)
                if c > 0:
                    if voxels.get((x + 1, y, z), 0) == 0:
                        mask_pos[(z, y)] = c
                    if voxels.get((x - 1, y, z), 0) == 0:
                        mask_neg[(z, y)] = c

        # Mesh mask_pos (+X face, vn 2: 1 0 0)
        # 2D greedy in (z, y)
        for (z, y), c in list(mask_pos.items()):
            if (z, y) not in mask_pos:
                continue
            # expand w along z
            w = 1
            while (z + w, y) in mask_pos and mask_pos[(z + w, y)] == c:
                w += 1
            # expand h along y
            h = 1
            while True:
                if all((z + i, y + h) in mask_pos and mask_pos[(z + i, y + h)] == c for i in range(w)):
                    h += 1
                else:
                    break
            # Remove merged
            for i in range(w):
                for j in range(h):
                    mask_pos.pop((z + i, y + j), None)

            # Quad at x1 = x + 1, z in [z, z+w], y in [y, y+h]
            # Normal is +X: vertices CCW viewed from +X
            p0 = to_obj_coords(x + 1, y + h, z)
            p1 = to_obj_coords(x + 1, y + h, z + w)
            p2 = to_obj_coords(x + 1, y, z + w)
            p3 = to_obj_coords(x + 1, y, z)
            
            v0 = get_vert_idx(p0)
            v1 = get_vert_idx(p1)
            v2 = get_vert_idx(p2)
            v3 = get_vert_idx(p3)
            vt = get_uv_idx(c)
            faces.append((v0, v1, v2, vt, 2))
            faces.append((v0, v2, v3, vt, 2))

        # Mesh mask_neg (-X face, vn 1: -1 0 0)
        for (z, y), c in list(mask_neg.items()):
            if (z, y) not in mask_neg:
                continue
            w = 1
            while (z + w, y) in mask_neg and mask_neg[(z + w, y)] == c:
                w += 1
            h = 1
            while True:
                if all((z + i, y + h) in mask_neg and mask_neg[(z + i, y + h)] == c for i in range(w)):
                    h += 1
                else:
                    break
            for i in range(w):
                for j in range(h):
                    mask_neg.pop((z + i, y + j), None)

            # Quad at x0 = x, z in [z, z+w], y in [y, y+h]
            # Normal is -X: vertices CCW viewed from -X
            p0 = to_obj_coords(x, y, z)
            p1 = to_obj_coords(x, y, z + w)
            p2 = to_obj_coords(x, y + h, z + w)
            p3 = to_obj_coords(x, y + h, z)

            v0 = get_vert_idx(p0)
            v1 = get_vert_idx(p1)
            v2 = get_vert_idx(p2)
            v3 = get_vert_idx(p3)
            vt = get_uv_idx(c)
            faces.append((v0, v1, v2, vt, 1))
            faces.append((v0, v2, v3, vt, 1))

    # 2. Faces along Y axis in voxel:
    # -Y in voxel is +Z in OBJ (vn 3: 0 0 1, FRONT facing inside bunker)
    # +Y in voxel is -Z in OBJ (vn 4: 0 0 -1, BACK facing outside)
    for y in range(SIZE_Y):
        mask_front = {} # solid at y, empty at y-1 (points in -Y_vox = +Z_obj)
        mask_back = {}  # solid at y, empty at y+1 (points in +Y_vox = -Z_obj)
        for x in range(SIZE_X):
            for z in range(SIZE_Z):
                c = voxels.get((x, y, z), 0)
                if c > 0:
                    if voxels.get((x, y - 1, z), 0) == 0:
                        mask_front[(x, z)] = c
                    if voxels.get((x, y + 1, z), 0) == 0:
                        mask_back[(x, z)] = c

        # Mesh mask_front (-Y in voxel, +Z in OBJ, vn 3)
        for (x, z), c in list(mask_front.items()):
            if (x, z) not in mask_front:
                continue
            w = 1
            while (x + w, z) in mask_front and mask_front[(x + w, z)] == c:
                w += 1
            h = 1
            while True:
                if all((x + i, z + h) in mask_front and mask_front[(x + i, z + h)] == c for i in range(w)):
                    h += 1
                else:
                    break
            for i in range(w):
                for j in range(h):
                    mask_front.pop((x + i, z + j), None)

            # Quad at y in voxel (plane at y, z_obj = size_y/2 - y)
            p0 = to_obj_coords(x, y, z)
            p1 = to_obj_coords(x + w, y, z)
            p2 = to_obj_coords(x + w, y, z + h)
            p3 = to_obj_coords(x, y, z + h)

            v0 = get_vert_idx(p0)
            v1 = get_vert_idx(p1)
            v2 = get_vert_idx(p2)
            v3 = get_vert_idx(p3)
            vt = get_uv_idx(c)
            faces.append((v0, v1, v2, vt, 3))
            faces.append((v0, v2, v3, vt, 3))

        # Mesh mask_back (+Y in voxel, -Z in OBJ, vn 4)
        for (x, z), c in list(mask_back.items()):
            if (x, z) not in mask_back:
                continue
            w = 1
            while (x + w, z) in mask_back and mask_back[(x + w, z)] == c:
                w += 1
            h = 1
            while True:
                if all((x + i, z + h) in mask_back and mask_back[(x + i, z + h)] == c for i in range(w)):
                    h += 1
                else:
                    break
            for i in range(w):
                for j in range(h):
                    mask_back.pop((x + i, z + j), None)

            # Quad at y+1 in voxel
            p0 = to_obj_coords(x + w, y + 1, z)
            p1 = to_obj_coords(x, y + 1, z)
            p2 = to_obj_coords(x, y + 1, z + h)
            p3 = to_obj_coords(x + w, y + 1, z + h)

            v0 = get_vert_idx(p0)
            v1 = get_vert_idx(p1)
            v2 = get_vert_idx(p2)
            v3 = get_vert_idx(p3)
            vt = get_uv_idx(c)
            faces.append((v0, v1, v2, vt, 4))
            faces.append((v0, v2, v3, vt, 4))

    # 3. Faces along Z axis in voxel (+Z_vox = +Y_obj vn 6, -Z_vox = -Y_obj vn 5)
    for z in range(SIZE_Z):
        mask_top = {}
        mask_bot = {}
        for x in range(SIZE_X):
            for y in range(SIZE_Y):
                c = voxels.get((x, y, z), 0)
                if c > 0:
                    if voxels.get((x, y, z + 1), 0) == 0:
                        mask_top[(x, y)] = c
                    if voxels.get((x, y, z - 1), 0) == 0:
                        mask_bot[(x, y)] = c

        # Top faces (+Z_vox = +Y_obj, vn 6)
        for (x, y), c in list(mask_top.items()):
            if (x, y) not in mask_top:
                continue
            w = 1
            while (x + w, y) in mask_top and mask_top[(x + w, y)] == c:
                w += 1
            h = 1
            while True:
                if all((x + i, y + h) in mask_top and mask_top[(x + i, y + h)] == c for i in range(w)):
                    h += 1
                else:
                    break
            for i in range(w):
                for j in range(h):
                    mask_top.pop((x + i, y + j), None)

            p0 = to_obj_coords(x, y, z + 1)
            p1 = to_obj_coords(x + w, y, z + 1)
            p2 = to_obj_coords(x + w, y + h, z + 1)
            p3 = to_obj_coords(x, y + h, z + 1)

            v0 = get_vert_idx(p0)
            v1 = get_vert_idx(p1)
            v2 = get_vert_idx(p2)
            v3 = get_vert_idx(p3)
            vt = get_uv_idx(c)
            faces.append((v0, v1, v2, vt, 6))
            faces.append((v0, v2, v3, vt, 6))

        # Bottom faces (-Z_vox = -Y_obj, vn 5)
        for (x, y), c in list(mask_bot.items()):
            if (x, y) not in mask_bot:
                continue
            w = 1
            while (x + w, y) in mask_bot and mask_bot[(x + w, y)] == c:
                w += 1
            h = 1
            while True:
                if all((x + i, y + h) in mask_bot and mask_bot[(x + i, y + h)] == c for i in range(w)):
                    h += 1
                else:
                    break
            for i in range(w):
                for j in range(h):
                    mask_bot.pop((x + i, y + j), None)

            p0 = to_obj_coords(x, y + h, z)
            p1 = to_obj_coords(x + w, y + h, z)
            p2 = to_obj_coords(x + w, y, z)
            p3 = to_obj_coords(x, y, z)

            v0 = get_vert_idx(p0)
            v1 = get_vert_idx(p1)
            v2 = get_vert_idx(p2)
            v3 = get_vert_idx(p3)
            vt = get_uv_idx(c)
            faces.append((v0, v1, v2, vt, 5))
            faces.append((v0, v2, v3, vt, 5))

    # Write OBJ file
    with open(obj_path, 'w') as f:
        f.write("# MagicaVoxel @ Ephtracy / White King Bunker Door\n\n")
        f.write("o Door\n\n")
        f.write(f"mtllib {mtl_path.name}\n")
        f.write("usemtl palette\n\n")

        # Normals
        f.write("# normals\n")
        for nx, ny, nz in normals:
            f.write(f"vn {nx:.4f} {ny:.4f} {nz:.4f}\n")
        f.write("\n")

        # Texcoords
        f.write("# texcoords\n")
        for u, v in texcoords:
            f.write(f"vt {u:.6f} {v:.6f}\n")
        f.write("\n")

        # Vertices
        f.write("# verts\n")
        for vx, vy, vz in vertices:
            f.write(f"v {vx:.4f} {vy:.4f} {vz:.4f}\n")
        f.write("\n")

        # Faces
        f.write("# faces\n")
        for v1, v2, v3, vt, vn in faces:
            f.write(f"f {v1}/{vt}/{vn} {v2}/{vt}/{vn} {v3}/{vt}/{vn}\n")

    print(f"Saved OBJ mesh: {obj_path} ({len(vertices)} verts, {len(faces)} tris)")

def render_preview_image(builder: BunkerDoorBuilder, output_path: Path):
    """Render a 2D orthographic front preview of the door with depth shading"""
    scale = 4
    img_w = SIZE_X * scale
    img_h = SIZE_Z * scale
    img = Image.new('RGB', (img_w, img_h), (25, 25, 28))
    pixels = img.load()

    # Front view looks in direction of +Y (low Y closest)
    depth_buf = {}
    for (x, y, z), c in builder.voxels.items():
        if c == 0:
            continue
        key = (x, z)
        # Closer voxel has lower y
        if key not in depth_buf or y < depth_buf[key][0]:
            depth_buf[key] = (y, c)

    for (x, z), (y, c) in depth_buf.items():
        r, g, b, _ = PALETTE[c]
        # Depth shading: front features (low y) slightly brighter, deep features slightly shadowed
        shade = 1.0 - (y - 3) * 0.04
        shade = max(0.65, min(1.15, shade))
        cr = int(min(255, max(0, r * shade)))
        cg = int(min(255, max(0, g * shade)))
        cb = int(min(255, max(0, b * shade)))

        for sx in range(scale):
            for sz in range(scale):
                px = x * scale + sx
                # Invert Z for image Y (z=127 is top)
                py = (SIZE_Z - 1 - z) * scale + sz
                pixels[px, py] = (cr, cg, cb)

    img.save(output_path)
    print(f"Saved preview render: {output_path}")

def main():
    print("=== Generating Bunker Door ===")
    builder = BunkerDoorBuilder()
    builder.build()

    # Vox output locations
    vox_targets = [
        MV_APP_VOX / "door.vox",
        MV_REPO_VOX / "door.vox",
        PROJECT_ROOT / "assets" / "door.vox",
    ]
    export_vox(builder, vox_targets)

    # OBJ output locations
    obj_path = PROJECT_ROOT / "assets" / "obj" / "door.obj"
    mtl_path = PROJECT_ROOT / "assets" / "obj" / "door.mtl"
    png_path = PROJECT_ROOT / "assets" / "obj" / "door.png"
    export_obj_mesh(builder, obj_path, mtl_path, png_path)

    # Preview image
    preview_path = PROJECT_ROOT / "assets" / "door_preview.png"
    render_preview_image(builder, preview_path)
    print("=== Generation Complete! ===")

if __name__ == "__main__":
    main()
