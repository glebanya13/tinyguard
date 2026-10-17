"""Build Bimbleguard GLB assets.

    blender -b --factory-startup --python assets/blender/build_all.py [-- NAME ... [--blend]]

Without names every asset is built. --blend also saves each generated scene
to assets/blender/out/<name>.blend (gitignored) for manual inspection.
"""
import importlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import bpy  # noqa: E402

import tg_common as tg  # noqa: E402

BUILDERS = {
    "hero": "build_hero",
    "tower": "build_tower",
    "chupa": "build_chupa",
    "golem": "build_golem",
    "villager": "build_villager",
    "castle": "build_castle",
    "environment": "build_environment",
    "terrain": "build_terrain",
    "icons": "build_icons",
    "worldmap": "build_worldmap",
}


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    save_blend = "--blend" in argv
    names = [a for a in argv if not a.startswith("--")] or list(BUILDERS)
    results = []
    for name in names:
        module = importlib.import_module(BUILDERS[name])
        tg.reset_scene()
        out = module.build()
        results.extend(out if isinstance(out, list) else [out])
        if save_blend:
            out_dir = HERE / "out"
            out_dir.mkdir(exist_ok=True)
            bpy.ops.wm.save_as_mainfile(filepath=str(out_dir / f"{name}.blend"))
    print("\n[bimbleguard] summary")
    for r in results:
        print(f"  {r['path']:<40} {r['tris']:>6} tris  {r['meshes']:>2} meshes")


main()
