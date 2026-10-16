#!/usr/bin/env python3
"""
Original flat pastel campus character roster generator.

Outputs (overwrites):
  characters_sheet.png  13 frames x 10 rows  (1248x1200) — 96x120 px frames
  dead_body_sheet.png    1 frame  x 10 rows  (96x1200)   — 96x120 px frames

Grid and frame size match the previous sheets exactly, so CrewSheet slicing
(Crewmate.swift: frameCols=13, colorRows=10) works UNCHANGED.

Row order (must match CrewColor order and ThemeColors.playerPastels):
  0 rose        backpack student      straps + side pack
  1 sky         headphones student    arc + ear cups
  2 mint        glasses student       round glasses + notebook
  3 peach       graduate              mortarboard cap + tassel
  4 apricot     professor             tie + mug
  5 lemon       librarian             cardigan buttons + book
  6 periwinkle  lab student           white coat + forehead goggles
  7 blush       athlete               jersey number + headband
  8 lilac       art student           beret + paintbrush
  9 aqua        exchange student      scarf + tail

Frame roles: 0 = idle, 1..12 = walk cycle (alternating leg/arm swing + bob).
Style: flat vector, rounded shapes, no outlines. All art is original —
not derived from any existing game.
"""
from PIL import Image, ImageDraw
import math

FRAME_W, FRAME_H = 96, 120
COLS, ROWS = 13, 10
SS = 4  # supersampling factor for smooth edges

PASTELS = [0xE8A0A4, 0xA3C7E8, 0xA8D5BA, 0xF5C6A5, 0xF2B880,
           0xF2DE8A, 0x9BA8D9, 0xF3D9D9, 0xC6AFE3, 0xA3DED8]

CHARCOAL = (58, 58, 74, 255)      # #3A3A4A
WOOD     = (217, 196, 168, 255)
PAPER    = (255, 255, 255, 255)


def rgb(hexv):
    return ((hexv >> 16) & 255, (hexv >> 8) & 255, hexv & 255, 255)


def mix(c1, c2, t):
    return tuple(round(a + (b - a) * t) for a, b in zip(c1[:3], c2[:3])) + (255,)


def rrect(d, x1, y1, x2, y2, r, fill):
    d.rounded_rectangle([round(x1 * SS), round(y1 * SS), round(x2 * SS), round(y2 * SS)],
                        radius=round(r * SS), fill=fill)


def ell(d, x1, y1, x2, y2, fill):
    d.ellipse([round(x1 * SS), round(y1 * SS), round(x2 * SS), round(y2 * SS)], fill=fill)


def line(d, xy, fill, w):
    d.line([round(v * SS) for v in xy], fill=fill, width=round(w * SS), joint="curve")


def capsule(d, x1, y1, x2, y2, w, fill):
    line(d, (x1, y1, x2, y2), fill, w)
    r = w / 2
    for cx, cy in ((x1, y1), (x2, y2)):
        ell(d, cx - r, cy - r, cx + r, cy + r, fill)


# ---------------------------------------------------------------- character

def draw_character(d, color_hex, frame, acc):
    """Front-facing flat student. frame 0 = idle, 1..12 = walk phases."""
    pastel = rgb(color_hex)
    light = mix(pastel, PAPER, 0.55)   # head / face
    deep = mix(pastel, CHARCOAL, 0.30)  # limbs / accessory anchors

    ph = 0.0 if frame == 0 else 2 * math.pi * frame / 12
    bob = 0 if frame == 0 else -abs(math.sin(ph)) * 2
    lift_l = 0 if frame == 0 else max(0.0, math.sin(ph)) * 7
    lift_r = 0 if frame == 0 else max(0.0, math.sin(ph + math.pi)) * 7
    swing = 0 if frame == 0 else math.sin(ph) * 3
    arm_l = 0 if frame == 0 else -math.sin(ph) * 4
    arm_r = 0 if frame == 0 else math.sin(ph) * 4

    cx = 48.0
    feet = 86.0 + bob
    y = bob  # vertical shift for upper body

    # legs (drawn first, behind torso)
    capsule(d, cx - 8 + swing, feet - lift_l, cx - 8 - swing * 0.5, feet - 18 + bob, 9, deep)
    capsule(d, cx + 8 - swing, feet - lift_r, cx + 8 + swing * 0.5, feet - 18 + bob, 9, deep)

    # arms (behind torso sides)
    capsule(d, cx - 19, 46 + y + arm_l, cx - 17, 60 + y + arm_l, 7, deep)
    capsule(d, cx + 19, 46 + y + arm_r, cx + 17, 60 + y + arm_r, 7, deep)

    # torso
    rrect(d, cx - 18, 40 + y, cx + 18, 70 + y, 12, pastel)

    # head
    hcx, hcy = cx, 27 + y
    ell(d, hcx - 16, hcy - 16, hcx + 16, hcy + 16, light)

    # face (dot eyes + smile — plain face, no visor)
    for ex in (hcx - 5, hcx + 5):
        ell(d, ex - 1.7, hcy - 2.5, ex + 1.7, hcy + 0.9, CHARCOAL)
    d.arc([round((hcx - 5) * SS), round((hcy + 2) * SS),
           round((hcx + 5) * SS), round((hcy + 8) * SS)], 25, 155, fill=CHARCOAL,
          width=round(1.4 * SS))

    # ---- per-row accessory (anchored to head/torso) ----
    if acc == "backpack":
        rrect(d, cx - 7, 42 + y, cx - 3.5, 66 + y, 1.8, deep)
        rrect(d, cx + 3.5, 42 + y, cx + 7, 66 + y, 1.8, deep)
        rrect(d, cx - 21, 50 + y, cx - 15, 62 + y, 3, deep)
        rrect(d, cx + 15, 50 + y, cx + 21, 62 + y, 3, deep)
    elif acc == "headphones":
        d.arc([round((hcx - 14) * SS), round((hcy - 17) * SS),
               round((hcx + 14) * SS), round((hcy + 4) * SS)], 180, 360,
              fill=deep, width=round(3.6 * SS))
        rrect(d, hcx - 17, hcy - 5, hcx - 11, hcy + 6, 3, deep)
        rrect(d, hcx + 11, hcy - 5, hcx + 17, hcy + 6, 3, deep)
    elif acc == "glasses":
        for gx in (hcx - 5.5, hcx + 5.5):
            d.ellipse([round((gx - 4.5) * SS), round((hcy - 4.5) * SS),
                       round((gx + 4.5) * SS), round((hcy + 4.5) * SS)],
                      outline=CHARCOAL, width=round(1.6 * SS))
        line(d, (hcx - 1.2, hcy - 1, hcx + 1.2, hcy - 1), CHARCOAL, 1.2)
        rrect(d, cx + 8, 50 + y, cx + 20, 63 + y, 2, PAPER)   # notebook
        line(d, (cx + 14, 52 + y, cx + 14, 61 + y), CHARCOAL, 1)
    elif acc == "gradcap":
        d.polygon([(round((hcx - 17) * SS), round((hcy - 8) * SS)),
                   (round(hcx * SS), round((hcy - 16) * SS)),
                   (round((hcx + 17) * SS), round((hcy - 8) * SS)),
                   (round(hcx * SS), round((hcy - 1) * SS))], fill=deep)
        line(d, (hcx + 8, hcy - 8, hcx + 11, hcy + 4), deep, 1.6)
        ell(d, hcx + 9.6, hcy + 3, hcx + 12.6, hcy + 6, deep)
    elif acc == "professor":
        d.polygon([(round(hcx * SS), round((40 + y) * SS)),
                   (round((hcx - 4) * SS), round((45 + y) * SS)),
                   (round(hcx * SS), round((58 + y) * SS)),
                   (round((hcx + 4) * SS), round((45 + y) * SS))], fill=deep)
        rrect(d, cx + 10, 50 + y, cx + 20, 61 + y, 2, PAPER)  # mug
        d.arc([round((cx + 18) * SS), round((51 + y) * SS),
               round((cx + 25) * SS), round((60 + y) * SS)], 270, 90,
              fill=deep, width=round(2 * SS))
    elif acc == "librarian":
        line(d, (cx, 42 + y, cx, 68 + y), deep, 1.4)
        for by in (48, 55, 62):
            ell(d, cx - 1.2, by + y - 1.2, cx + 1.2, by + y + 1.2, deep)
        rrect(d, cx + 9, 52 + y, cx + 21, 63 + y, 2, PAPER)   # book
        line(d, (cx + 15, 54 + y, cx + 15, 61 + y), deep, 1.2)
    elif acc == "labcoat":
        rrect(d, cx - 15, 42 + y, cx + 15, 68 + y, 9, PAPER)
        line(d, (cx, 42 + y, cx, 60 + y), mix(PAPER, CHARCOAL, 0.25), 1.4)
        d.arc([round((hcx - 14) * SS), round((hcy - 14) * SS),
               round((hcx + 14) * SS), round((hcy + 2) * SS)], 200, 340,
              fill=deep, width=round(2.6 * SS))               # goggles band
        for gx in (hcx - 4.5, hcx + 4.5):
            ell(d, gx - 3.4, hcy - 12.4, gx + 3.4, hcy - 5.6, PAPER)
            d.ellipse([round((gx - 3.4) * SS), round((hcy - 12.4) * SS),
                       round((gx + 3.4) * SS), round((hcy - 5.6) * SS)],
                      outline=deep, width=round(1.4 * SS))
    elif acc == "athlete":
        rrect(d, hcx - 14, hcy - 11, hcx + 14, hcy - 6, 2, deep)  # headband
        for gy in (hcy + 20, hcy + 26):                           # jersey "8"
            d.ellipse([round((hcx - 2.6) * SS), round((gy - 2.6) * SS),
                       round((hcx + 2.6) * SS), round((gy + 2.6) * SS)],
                      outline=deep, width=round(1.6 * SS))
    elif acc == "beret":
        ell(d, hcx - 13, hcy - 15, hcx + 13, hcy - 5, deep)
        ell(d, hcx - 1.6, hcy - 18.2, hcx + 1.6, hcy - 15, deep)
        capsule(d, cx + 18, 52 + y, cx + 24, 40 + y, 2.6, deep)   # brush
        ell(d, cx + 22.2, 37.2, cx + 26.2, 41.2, deep)
    elif acc == "scarf":
        rrect(d, cx - 12, 34 + y, cx + 12, 40 + y, 3, CHARCOAL)
        rrect(d, cx - 10, 38 + y, cx + 10, 44 + y, 3, mix(pastel, CHARCOAL, 0.45))
        rrect(d, cx + 3, 42 + y, cx + 9, 56 + y, 2.5, CHARCOAL)


ACCESSORIES = ["backpack", "headphones", "glasses", "gradcap", "professor",
               "librarian", "labcoat", "athlete", "beret", "scarf"]


def build_characters_sheet():
    img = Image.new("RGBA", (FRAME_W * COLS * SS, FRAME_H * ROWS * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for row in range(ROWS):
        for col in range(COLS):
            ox, oy = col * FRAME_W * SS, row * FRAME_H * SS
            sub = ImageDraw.Draw(img, "RGBA")
            # draw into a temp layer so we can offset — simpler: translate coords
            # by drawing on a frame canvas and pasting.
            frame_img = Image.new("RGBA", (FRAME_W * SS, FRAME_H * SS), (0, 0, 0, 0))
            fd = ImageDraw.Draw(frame_img)
            draw_character(fd, PASTELS[row], col, ACCESSORIES[row])
            img.paste(frame_img, (ox, oy), frame_img)
    del d
    return img.resize((FRAME_W * COLS, FRAME_H * ROWS), Image.LANCZOS)


def draw_sleeping(d, color_hex, acc):
    """Asleep-at-desk — the lighthearted 'distracted' state, same grid."""
    pastel = rgb(color_hex)
    light = mix(pastel, PAPER, 0.55)
    deep = mix(pastel, CHARCOAL, 0.30)
    cx = 48.0

    # torso peeking above the desk
    rrect(d, cx - 15, 26, cx + 15, 52, 10, pastel)
    # desk
    rrect(d, 12, 50, 84, 64, 4, WOOD)
    line(d, (18, 64, 18, 76), mix(WOOD, CHARCOAL, 0.3), 3)
    line(d, (78, 64, 78, 76), mix(WOOD, CHARCOAL, 0.3), 3)
    # arms folded on the desk
    capsule(d, 26, 56, 42, 58, 7, deep)
    capsule(d, 54, 58, 70, 56, 7, deep)
    # paper with scribbles
    rrect(d, 56, 53, 72, 63, 1.5, PAPER)
    line(d, (58, 56, 70, 56), mix(PAPER, CHARCOAL, 0.35), 1)
    line(d, (58, 59, 66, 59), mix(PAPER, CHARCOAL, 0.35), 1)
    # head resting on arms
    hcx, hcy = 40, 42
    ell(d, hcx - 14, hcy - 14, hcx + 14, hcy + 14, light)
    for ex in (hcx - 5, hcx + 5):          # closed eyes (dashes)
        line(d, (ex - 2, hcy, ex + 2, hcy), CHARCOAL, 1.3)
    # feet under the desk
    capsule(d, 38, 64, 37, 74, 7, deep)
    capsule(d, 50, 64, 51, 74, 7, deep)

    # accessory on the resting head (same identity as the walk sheet)
    import math
    if acc == "headphones":
        d.arc([round((hcx - 12) * SS), round((hcy - 13) * SS),
               round((hcx + 12) * SS), round((hcy + 4) * SS)], 180, 360,
              fill=deep, width=round(3.2 * SS))
        rrect(d, hcx - 15, hcy - 4, hcx - 9, hcy + 6, 3, deep)
        rrect(d, hcx + 9, hcy - 4, hcx + 15, hcy + 6, 3, deep)
    elif acc == "glasses":
        rrect(d, hcx - 10, hcy + 3, hcx + 10, hcy + 7, 2, PAPER)
    elif acc == "gradcap":
        d.polygon([(round((hcx - 15) * SS), round((hcy - 7) * SS)),
                   (round(hcx * SS), round((hcy - 14) * SS)),
                   (round((hcx + 15) * SS), round((hcy - 7) * SS)),
                   (round(hcx * SS), round((hcy - 1) * SS))], fill=deep)
    elif acc == "professor":
        rrect(d, hcx + 12, 40, hcx + 21, 50, 2, PAPER)
    elif acc == "librarian":
        rrect(d, hcx + 12, 44, hcx + 24, 54, 2, PAPER)
    elif acc == "labcoat":
        d.arc([round((hcx - 12) * SS), round((hcy - 12) * SS),
               round((hcx + 12) * SS), round((hcy + 1) * SS)], 200, 340,
              fill=deep, width=round(2.4 * SS))
    elif acc == "athlete":
        rrect(d, hcx - 12, hcy - 10, hcx + 12, hcy - 5, 2, deep)
    elif acc == "beret":
        ell(d, hcx - 12, hcy - 14, hcx + 12, hcy - 4, deep)
        ell(d, hcx - 1.5, hcy - 17, hcx + 1.5, hcy - 14, deep)
    elif acc == "scarf":
        rrect(d, cx - 11, 33, cx + 11, 39, 3, CHARCOAL)
    elif acc == "backpack":
        rrect(d, 14, 34, 24, 50, 4, deep)

    # Zzz
    zx, zy, zs = 60, 26, 6.0
    for i in range(3):
        s = zs - i * 1.6
        d.line([round((zx + i * 5) * SS), round(zy * SS),
                round((zx + i * 5 + s) * SS), round(zy * SS)],
               fill=CHARCOAL, width=round(1.3 * SS))
        d.line([round((zx + i * 5 + s) * SS), round(zy * SS),
                round((zx + i * 5) * SS), round((zy - s) * SS)],
               fill=CHARCOAL, width=round(1.3 * SS))
        d.line([round((zx + i * 5) * SS), round((zy - s) * SS),
                round((zx + i * 5 + s) * SS), round((zy - s) * SS)],
               fill=CHARCOAL, width=round(1.3 * SS))
        zy -= 9


def build_dead_sheet():
    img = Image.new("RGBA", (FRAME_W * SS, FRAME_H * ROWS * SS), (0, 0, 0, 0))
    for row in range(ROWS):
        frame_img = Image.new("RGBA", (FRAME_W * SS, FRAME_H * SS), (0, 0, 0, 0))
        fd = ImageDraw.Draw(frame_img)
        draw_sleeping(fd, PASTELS[row], ACCESSORIES[row])
        img.paste(frame_img, (0, row * FRAME_H * SS), frame_img)
    return img.resize((FRAME_W, FRAME_H * ROWS), Image.LANCZOS)


if __name__ == "__main__":
    sheets = build_characters_sheet()
    sheets.save("characters_sheet.png")
    dead = build_dead_sheet()
    dead.save("dead_body_sheet.png")
    print("wrote characters_sheet.png", sheets.size)
    print("wrote dead_body_sheet.png", dead.size)
