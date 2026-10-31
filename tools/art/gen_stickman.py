#!/usr/bin/env python3
"""Placeholder stick-figure sprites, drawn procedurally so they animate properly.

    py -3 tools/art/gen_stickman.py [character-dir]

Writes char.json, reference-less base pose and one magenta strip per state into
<character-dir>/.frames/, then runs prepare.py + extract.py so the result is a
normal spritesheet.png + atlas.json that the game loads unchanged.

Angles are degrees from straight down; positive is forward (the sprite faces right).
"""

import json
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

TOOLS = Path(__file__).resolve().parent.parent
STATES = json.loads((TOOLS / "frames" / "states.json").read_text())

STRIP_SIZES = {3: (1024, 512), 4: (1024, 512), 5: (1024, 512), 6: (1152, 512), 8: (1536, 512)}
GROUND_Y = 440
BODY = (200, 205, 220)
FAR = (148, 152, 176)
JOINT = (200, 205, 220)
CHROMA = (255, 0, 255)

HIP_Y = 96.0
TORSO = 56.0
HEAD_R = 19.0
UPPER_ARM = 33.0
FOREARM = 31.0
THIGH = 47.0
SHIN = 47.0


def polar(origin, length, angle):
    radians = math.radians(angle)
    return (origin[0] + length * math.sin(radians), origin[1] + length * math.cos(radians))


def limb(draw, origin, upper_angle, fore_angle, color, fist=False):
    elbow = polar(origin, UPPER_ARM, upper_angle)
    hand = polar(elbow, FOREARM, upper_angle + fore_angle)
    draw.line([origin, elbow], fill=color, width=10)
    draw.line([elbow, hand], fill=color, width=9)
    draw.ellipse([elbow[0] - 5, elbow[1] - 5, elbow[0] + 5, elbow[1] + 5], fill=color)
    radius = 8 if fist else 6
    draw.ellipse([hand[0] - radius, hand[1] - radius, hand[0] + radius, hand[1] + radius], fill=color)


def leg(draw, origin, thigh_angle, knee_angle, color):
    knee = polar(origin, THIGH, thigh_angle)
    foot = polar(knee, SHIN, thigh_angle + knee_angle)
    draw.line([origin, knee], fill=color, width=11)
    draw.line([knee, foot], fill=color, width=10)
    draw.ellipse([knee[0] - 6, knee[1] - 6, knee[0] + 6, knee[1] + 6], fill=color)
    draw.line([(foot[0] - 6, foot[1]), (foot[0] + 9, foot[1])], fill=color, width=7)


def draw_figure(draw, cx, pose):
    """cx is the character's vertical axis; feet sit on GROUND_Y."""
    hip = (cx, GROUND_Y - HIP_Y + pose.get("hip", 0.0))
    lean = pose.get("lean", 0.0)
    neck = polar(hip, TORSO, 180.0 + lean)
    head = polar(neck, HEAD_R + 6.0, 180.0 + lean * 1.6 + pose.get("head", 0.0))

    far_arm, near_arm = pose["arms"]
    far_leg, near_leg = pose["legs"]

    limb(draw, neck, far_arm[0], far_arm[1], FAR)
    leg(draw, hip, far_leg[0], far_leg[1], FAR)

    draw.line([hip, neck], fill=BODY, width=14)
    draw.ellipse([head[0] - HEAD_R, head[1] - HEAD_R, head[0] + HEAD_R, head[1] + HEAD_R], fill=BODY)
    # A nose dot makes the facing direction readable at a glance.
    draw.ellipse([head[0] + HEAD_R * 0.42, head[1] - 3.0, head[0] + HEAD_R * 0.78, head[1] + 3.0], fill=(90, 95, 115))

    leg(draw, hip, near_leg[0], near_leg[1], BODY)
    limb(draw, neck, near_arm[0], near_arm[1], BODY, fist=True)

    for point in (hip, neck):
        draw.ellipse([point[0] - 6, point[1] - 6, point[0] + 6, point[1] + 6], fill=JOINT)


def mirrored(pose):
    def mirror_pair(pair):
        return (-pair[0], pair[1])

    return {
        "hip": pose.get("hip", 0.0),
        "lean": -pose.get("lean", 0.0),
        "head": -pose.get("head", 0.0),
        "arms": [mirror_pair(a) for a in pose["arms"]],
        "legs": [mirror_pair(l) for l in pose["legs"]],
    }


def idle_frames():
    frames = []
    for index in range(6):
        breath = [0.0, 1.5, 3.0, 3.0, 1.5, 0.5][index]
        sway = [0.0, 2.0, 4.0, 2.0, 0.0, -2.0][index]
        frames.append({
            "hip": breath,
            "lean": -3.0,
            "arms": [(14.0, 100.0), (20.0 + sway, 108.0)],
            "legs": [(-14.0, -6.0), (12.0, -6.0)],
        })
    return frames


def walk_frames():
    frames = []
    for index in range(8):
        phase = index / 8.0 * 2.0 * math.pi
        stride = math.sin(phase) * 30.0
        lift = max(0.0, math.sin(phase)) * 34.0
        back_lift = max(0.0, -math.sin(phase)) * 34.0
        frames.append({
            "hip": -abs(math.sin(phase)) * 3.0,
            "lean": 5.0,
            "arms": [(-stride * 0.5, 55.0), (stride * 0.5, 60.0)],
            "legs": [(stride, -16.0 - lift), (-stride, -16.0 - back_lift)],
        })
    return frames


def crouch_frames():
    return [
        {"hip": -18.0, "lean": 10.0, "arms": [(20.0, 112.0), (28.0, 118.0)], "legs": [(-46.0, 96.0), (34.0, 92.0)]},
        {"hip": -25.0, "lean": 12.0, "arms": [(22.0, 116.0), (30.0, 122.0)], "legs": [(-54.0, 104.0), (40.0, 100.0)]},
        {"hip": -25.0, "lean": 12.0, "arms": [(22.0, 116.0), (30.0, 122.0)], "legs": [(-54.0, 104.0), (40.0, 100.0)]},
    ]


def jump_frames():
    return [
        {"hip": -20.0, "lean": 10.0, "arms": [(-10.0, 90.0), (12.0, 96.0)], "legs": [(-42.0, 90.0), (36.0, 86.0)]},
        {"hip": 6.0, "lean": -4.0, "arms": [(140.0, 20.0), (150.0, 14.0)], "legs": [(-6.0, 4.0), (8.0, 2.0)]},
        {"hip": 10.0, "lean": 6.0, "arms": [(118.0, 40.0), (128.0, 34.0)], "legs": [(46.0, -74.0), (18.0, -64.0)]},
        {"hip": 4.0, "lean": 4.0, "arms": [(60.0, 50.0), (70.0, 46.0)], "legs": [(14.0, -14.0), (-10.0, -8.0)]},
        {"hip": -18.0, "lean": 12.0, "arms": [(20.0, 110.0), (28.0, 116.0)], "legs": [(-40.0, 84.0), (32.0, 80.0)]},
    ]


def attack_light_frames():
    return [
        {"hip": -2.0, "lean": 0.0, "arms": [(10.0, 100.0), (30.0, 120.0)], "legs": [(-16.0, 8.0), (14.0, 6.0)]},
        {"hip": 0.0, "lean": 6.0, "arms": [(0.0, 92.0), (88.0, 2.0)], "legs": [(-20.0, 10.0), (18.0, 4.0)]},
        {"hip": -1.0, "lean": 8.0, "arms": [(-4.0, 90.0), (82.0, 8.0)], "legs": [(-22.0, 12.0), (20.0, 4.0)]},
        {"hip": 0.0, "lean": 2.0, "arms": [(12.0, 102.0), (30.0, 116.0)], "legs": [(-16.0, 8.0), (14.0, 6.0)]},
    ]


def attack_heavy_frames():
    return [
        {"hip": -4.0, "lean": -10.0, "arms": [(6.0, 92.0), (-46.0, 62.0)], "legs": [(-22.0, 12.0), (18.0, 6.0)]},
        {"hip": -2.0, "lean": 10.0, "arms": [(-2.0, 88.0), (110.0, 8.0)], "legs": [(-28.0, 16.0), (24.0, 6.0)]},
        {"hip": 0.0, "lean": 16.0, "arms": [(-6.0, 84.0), (100.0, 22.0)], "legs": [(-32.0, 20.0), (26.0, 6.0)]},
        {"hip": -2.0, "lean": 6.0, "arms": [(8.0, 96.0), (40.0, 92.0)], "legs": [(-18.0, 10.0), (16.0, 6.0)]},
    ]


def kick_frames():
    return [
        {"hip": -6.0, "lean": 0.0, "arms": [(10.0, 100.0), (20.0, 108.0)], "legs": [(-14.0, 8.0), (44.0, -96.0)]},
        {"hip": -2.0, "lean": 12.0, "arms": [(-4.0, 88.0), (10.0, 96.0)], "legs": [(-16.0, 10.0), (88.0, -2.0)]},
        {"hip": -2.0, "lean": 10.0, "arms": [(-2.0, 90.0), (12.0, 98.0)], "legs": [(-16.0, 10.0), (80.0, 6.0)]},
        {"hip": -8.0, "lean": 2.0, "arms": [(10.0, 98.0), (20.0, 106.0)], "legs": [(-12.0, 8.0), (26.0, -34.0)]},
    ]


def hurt_frames():
    return [
        {"hip": -4.0, "lean": -18.0, "head": -10.0, "arms": [(-48.0, 10.0), (-18.0, 70.0)], "legs": [(-20.0, 14.0), (16.0, 8.0)]},
        {"hip": -6.0, "lean": -24.0, "head": -14.0, "arms": [(-58.0, 6.0), (-26.0, 60.0)], "legs": [(-26.0, 18.0), (14.0, 10.0)]},
        {"hip": -2.0, "lean": -8.0, "head": -4.0, "arms": [(-30.0, 40.0), (-6.0, 86.0)], "legs": [(-14.0, 10.0), (12.0, 6.0)]},
    ]


BUILDERS = {
    "idle": idle_frames,
    "walk": walk_frames,
    "crouch": crouch_frames,
    "jump": jump_frames,
    "attack-light": attack_light_frames,
    "attack-heavy": attack_heavy_frames,
    "kick": kick_frames,
    "hurt": hurt_frames,
}


def render_strip(frames, count, path):
    width, height = STRIP_SIZES.get(count, (1536, 512))
    image = Image.new("RGB", (width, height), CHROMA)
    draw = ImageDraw.Draw(image)
    slot = width / count
    for index, pose in enumerate(frames):
        draw_figure(draw, slot * (index + 0.5), pose)
    image.save(path)


def main():
    char_dir = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path("art/placeholder/stickman").resolve()
    work = char_dir / ".frames"
    (work / "generated").mkdir(parents=True, exist_ok=True)

    (char_dir / "char.json").write_text(json.dumps({
        "name": char_dir.name,
        "displayName": "Stickman",
        "description": "stick figure fighter placeholder",
        "quality": "medium",
    }, ensure_ascii=False, indent=2), encoding="utf-8")

    subprocess.run([sys.executable, str(TOOLS / "frames" / "prepare.py"), str(char_dir)], check=True)

    idle = idle_frames()
    render_strip(idle, 6, work / "generated" / "base.png")

    for state in STATES["states"]:
        name = state["name"]
        if state.get("mirror_of"):
            continue
        frames = BUILDERS[name]()
        if len(frames) != state["frames"]:
            raise SystemExit(f"{name}: built {len(frames)} frames, states.json wants {state['frames']}")
        render_strip(frames, state["frames"], work / "generated" / f"{name}.png")
        print(f"  {name}: {len(frames)} frames")

    subprocess.run([sys.executable, str(TOOLS / "frames" / "extract.py"), str(char_dir)], check=True)
    print(f"\nready: {char_dir / 'spritesheet.png'}")


if __name__ == "__main__":
    main()
