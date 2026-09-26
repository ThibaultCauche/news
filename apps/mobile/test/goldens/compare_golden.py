#!/usr/bin/env python3
"""Compare un golden Flutter à la maquette Figma correspondante.

Usage :
    python compare_golden.py <golden.png> <maquette.png> [--crop x,y,w,h] [--out diff.png]

Écrit une image de différence (rouge = pixel différent) et affiche le
pourcentage d'écart. `--crop` restreint la comparaison à une zone de la
maquette (par ex. la bande de la tab bar) quand le golden ne couvre pas tout
l'écran 390×844.
"""

import argparse
import sys

from PIL import Image, ImageChops


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("golden", help="PNG généré par flutter test --update-goldens")
    parser.add_argument("maquette", help="PNG de référence dans docs/maquettes/")
    parser.add_argument("--crop", help="x,y,w,h à découper dans la maquette avant comparaison")
    parser.add_argument("--golden-crop", help="x,y,w,h à découper dans le golden avant comparaison")
    parser.add_argument("--out", default="diff.png", help="Chemin de l'image de différence (défaut: diff.png)")
    args = parser.parse_args()

    golden = Image.open(args.golden).convert("RGB")
    maquette = Image.open(args.maquette).convert("RGB")

    if args.crop:
        x, y, w, h = (int(v) for v in args.crop.split(","))
        maquette = maquette.crop((x, y, x + w, y + h))
    if args.golden_crop:
        x, y, w, h = (int(v) for v in args.golden_crop.split(","))
        golden = golden.crop((x, y, x + w, y + h))

    if golden.size != maquette.size:
        print(f"Tailles différentes : golden {golden.size} vs maquette (découpée) {maquette.size}", file=sys.stderr)
        return 1

    diff = ImageChops.difference(golden, maquette)
    diff_data = diff.getdata()
    total_pixels = len(diff_data)
    # Un pixel "différent" tolère un petit écart d'anti-aliasing (< 8 par canal).
    changed = sum(1 for r, g, b in diff_data if max(r, g, b) > 8)
    percent = 100 * changed / total_pixels

    # Image de diff : fond noir, rouge plein sur chaque pixel qui dépasse le seuil.
    highlight = Image.new("RGB", diff.size, (0, 0, 0))
    highlight_data = [(255, 0, 0) if max(r, g, b) > 8 else (0, 0, 0) for r, g, b in diff_data]
    highlight.putdata(highlight_data)
    highlight.save(args.out)

    print(f"Écart : {percent:.2f}% des pixels ({changed}/{total_pixels}) — diff écrite dans {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
