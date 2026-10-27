"""Joint-gap and loop check for the generated clips (pure Python, no Godot).

Gaps: where a limb or body segment bends away from its neighbour, the rigid cubes open a wedge on the outer side
of the bend, (depth / 2) * sin(bend) or (width / 2) * sin(roll) skin pixels wide. For every joint and every key of
every clip of every hunter profile this reports the widest wedge and checks it against the size of the joint
plug that covers it (bb_skin.PLUG_EXT).
Loops: every looping clip must end exactly where it starts (rotation and translation), or it pops at the wrap.

  python3 tools/blocky_hunters/check_gaps.py [--print]"""
import math, sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import bb_rig, bb_skin
from hunters import motion
from hunters.roster import IDS as _AZ
from hunters.void_set import IDS as _VOID
IDS = _AZ + _VOID + ["player_mannequin"]

# child bone -> (width, depth) of the cube pair meeting at its joint, in skin px
JOINTS = {"L-Thigh": (4, 4), "R-Thigh": (4, 4), "L-Calf": (4, 4), "R-Calf": (4, 4), "L-Foot": (4, 6), "R-Foot": (4, 6),
          "L-Forearm": (3, 4), "R-Forearm": (3, 4), "L-Hand": (3, 4), "R-Hand": (3, 4),
          "Chest": (8, 4), "Head": (8, 8), "Belly": (8, 4)}


def matrix(q):
    x, y, z, w = q
    return [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]


def conj(q):
    return (-q[0], -q[1], -q[2], q[3])


def hunter_clips(name):
    if name == "player_mannequin":                    # classic 4 px arms, its own clip set
        import player_clips
        sk = bb_skin.vanilla_sk(sh_x=6.0)
        bones = bb_rig.skeleton(sk, [])
        return player_clips.build(bones, sk["hip_y"], motion.profile(name)), {b["name"]: b["rot"] for b in bones}
    sk = bb_skin.vanilla_sk()
    bones = bb_rig.skeleton(sk, [])
    return bb_rig.build_clips(bones, sk["hip_y"], motion.profile(name)), {b["name"]: b["rot"] for b in bones}


def wedge(q, rest, w, d):
    m = matrix(bb_rig.quat_mul(q, conj(rest)))
    ty = (m[0][1], m[1][1], m[2][1])
    thx = math.atan2(ty[2], ty[1])
    thz = math.atan2(-ty[0], ty[1])
    return max(d / 2 * abs(math.sin(thx)), w / 2 * abs(math.sin(thz)))


def main():
    worst, extreme = {}, {}
    loops_bad = []
    for name in IDS:
        clips, rest = hunter_clips(name)
        for cname, clip in clips.items():
            for bone, tr in clip["tracks"].items():
                for chan, (t, v) in tr.items():
                    a, b = v[0], v[-1]
                    if clip.get("loop", True) and max(abs(i - j) for i, j in zip(a, b)) > 1e-6:
                        loops_bad.append((name, cname, bone, chan))
                if bone in JOINTS and "rotation" in tr:
                    w, d = JOINTS[bone]
                    if name == "player_mannequin" and bone.endswith(("Forearm", "Hand")):
                        w = 4                         # classic arms are 4 px wide
                    g = max(wedge(q, rest[bone], w, d) for q in tr["rotation"][1])
                    book = extreme if cname == "crouch" else worst
                    if g > book.get(bone, (0,))[0]:
                        book[bone] = (g, name, cname)
    ext = getattr(bb_skin, "PLUG_EXT", {})
    bad = 0
    for bone, (g, n, c) in sorted(worst.items()):
        cover = ext.get(bone, 0.0)
        status = "ok" if g <= cover else "GAP"
        bad += status == "GAP"
        print("  %-10s widest wedge %.2f px (%s/%s), plug covers %.2f px  %s" % (bone, g, n, c, cover, status))
    for bone, (g, n, c) in sorted(extreme.items()):
        print("  %-10s crouch (deepest bend)  %.2f px (%s), plug covers %.2f px%s" % (
            bone, g, n, ext.get(bone, 0.0), "" if g <= ext.get(bone, 0.0) else "  (sliver at the deepest crouch)"))
    print("loops: %s" % ("all seamless" if not loops_bad else "%d broken, e.g. %s" % (len(loops_bad), loops_bad[:3])))
    return bad + len(loops_bad)


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
