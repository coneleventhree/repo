"""Draws the GUI dumps from tests/tools/dump_gui.luau as PNGs (an
approximation of Roblox's layout: UDim2 sizes/positions, anchor points,
UIScale, UIPadding, UIListLayout, UIGridLayout, AutomaticSize Y, UICorner,
UIStroke, text alignment/wrapping/TextScaled; Gotham is drawn with DejaVu
Sans Bold). The 3D world behind is a flat grey.

    python3 tests/tools/render_gui.py gui.txt out/ [scene ...]
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

INSET = 58  # Roblox top bar height (ScreenGui.IgnoreGuiInset = false)
FONT_DIR = "/usr/share/fonts/truetype/dejavu/"
_fonts = {}


def font(name, size):
    mono = "Mono" in name or "Code" in name or "Roboto" in name
    medium = "Medium" in name or name in ("Gotham", "SourceSans", "Legacy")
    file = "DejaVuSansMono-Bold.ttf" if mono else ("DejaVuSans.ttf" if medium else "DejaVuSans-Bold.ttf")
    size = max(6, int(round(size)))
    key = (file, size)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(FONT_DIR + file, size)
    return _fonts[key]


def parse(path):
    scenes, cur = [], None
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith("== SCENE "):
            _, _, name, w, h = line.split(" ")
            cur = {"name": name, "w": int(w), "h": int(h), "nodes": []}
            scenes.append(cur)
        elif line.startswith("{") and cur is not None:
            cur["nodes"].append(json.loads(line))
    return scenes


GUI = {"Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame"}


class Scene:
    def __init__(self, sc):
        self.w, self.h = sc["w"], sc["h"]
        self.byId = {n["id"]: n for n in sc["nodes"]}
        self.kids = {}
        for n in sc["nodes"]:
            self.kids.setdefault(n["parent"], []).append(n)
        self.draws = []  # (order key, kind, data)

    def mods(self, n, cls):
        return [c for c in self.kids.get(n["id"], []) if c["class"] == cls]

    def mod(self, n, cls):
        m = self.mods(n, cls)
        return m[0] if m else None

    # ------------------------------------------------------------------
    def layout_children(self, n, rect, k, depth, order):
        x, y, w, h = rect
        pad = self.mod(n, "UIPadding")
        if pad:
            l, r, t, b = pad["pad"]
            x += l[0] * w + l[1] * k
            y += t[0] * h + t[1] * k
            w -= (l[0] + r[0]) * w + (l[1] + r[1]) * k
            h -= (t[0] + b[0]) * h + (t[1] + b[1]) * k
        kids = [c for c in self.kids.get(n["id"], []) if c["class"] in GUI]
        lst = self.mod(n, "UIListLayout")
        grid = self.mod(n, "UIGridLayout")
        placed = {}
        if lst or grid:
            vis = sorted([c for c in kids if c.get("visible")], key=lambda c: c.get("order", 0))
            if grid:
                cw = grid["cell"][0] * w + grid["cell"][1] * k
                ch = grid["cell"][2] * h + grid["cell"][3] * k
                px = grid["cellPad"][0] * w + grid["cellPad"][1] * k
                py = grid["cellPad"][2] * h + grid["cellPad"][3] * k
                per = max(1, int((w + px) / (cw + px) + 1e-6)) if cw > 0 else 1
                if grid.get("maxCells", 0) > 0:
                    per = min(per, grid["maxCells"])
                for i, c in enumerate(vis):
                    placed[c["id"]] = (x + (i % per) * (cw + px), y + (i // per) * (ch + py), cw, ch)
            else:
                gap = lst["padding"][0] * (h if lst["dir"] == "Vertical" else w) + lst["padding"][1] * k
                cx, cy = x, y
                for c in vis:
                    cw = c["size"][0] * w + c["size"][1] * k
                    chh = self.auto_height(c, cw, c["size"][2] * h + c["size"][3] * k, k)
                    if lst["dir"] == "Vertical":
                        ox = x + (w - cw) / 2 if lst["hAlign"] == "Center" else (x + w - cw if lst["hAlign"] == "Right" else x)
                        placed[c["id"]] = (ox, cy, cw, chh)
                        cy += chh + gap
                    else:
                        placed[c["id"]] = (cx, y, cw, chh)
                        cx += cw + gap
        kids.sort(key=lambda c: c.get("z", 1))
        for c in kids:
            self.place(c, (x, y, w, h), k, depth + 1, order, placed.get(c["id"]))

    def content_extent(self, n, w, h, k):
        """Height the children need (for AutomaticSize Y)."""
        tmp = Scene.__new__(Scene)
        tmp.w, tmp.h, tmp.byId, tmp.kids, tmp.draws = self.w, self.h, self.byId, self.kids, []
        tmp.extent = 0
        tmp.measuring = True
        tmp.layout_children(n, (0, 0, w, h), k, 0, [0])
        pad = self.mod(n, "UIPadding")
        bottom = pad["pad"][3][1] * k if pad else 0
        return tmp.extent + bottom

    def auto_height(self, n, w, h, k):
        if n.get("auto") in ("Y", "XY"):
            return max(h, self.content_extent(n, w, h, k))
        return h

    def place(self, n, prect, k, depth, order, forced=None):
        if not n.get("visible", True):
            return
        px, py, pw, ph = prect
        if forced:
            x, y, w, h = forced
        else:
            s, p, a = n["size"], n["pos"], n["anchor"]
            w = s[0] * pw + s[1] * k
            h = s[2] * ph + s[3] * k
            h = self.auto_height(n, w, h, k)
            x = px + p[0] * pw + p[1] * k - a[0] * w
            y = py + p[2] * ph + p[3] * k - a[1] * h
        sc = self.mod(n, "UIScale")
        kk = k
        if sc:
            s = sc["scale"]
            ax = x + n["anchor"][0] * w
            ay = y + n["anchor"][1] * h
            w, h = w * s, h * s
            x, y = ax - n["anchor"][0] * w, ay - n["anchor"][1] * h
            kk = k * s
        if getattr(self, "measuring", False):
            self.extent = max(self.extent, y + h)
        else:
            order[0] += 1
            self.draws.append((order[0], n, (x, y, w, h), kk))
        self.layout_children(n, (x, y, w, h), kk, depth, order)

    def run(self):
        guis = [n for n in self.kids.get(0, []) if n["class"] == "ScreenGui" and n.get("enabled", True)]
        guis.sort(key=lambda g: g.get("order", 0))
        order = [0]
        for g in guis:
            top = INSET if g.get("inset") else 0
            rect = (0, top, self.w, self.h - top)
            sc = self.mod(g, "UIScale")
            k = sc["scale"] if sc else 1
            self.layout_children(g, rect, k, 0, order)


def rgba(c, t):
    return (c[0], c[1], c[2], int(round(255 * (1 - max(0.0, min(1.0, t))))))


def wrap(draw, text, f, width):
    out = []
    for para in text.split("\n"):
        words = para.split(" ")
        line = ""
        for wd in words:
            test = (line + " " + wd) if line else wd
            if draw.textlength(test, font=f) <= width or not line:
                line = test
            else:
                out.append(line)
                line = wd
        out.append(line)
    return out


def render(sc, out_dir, zoom):
    s = Scene(sc)
    s.run()
    W, H = s.w * zoom, s.h * zoom
    img = Image.new("RGBA", (W, H), (88, 98, 92, 255))
    for _, n, (x, y, w, h), k in s.draws:
        X, Y, Wd, Hd = x * zoom, y * zoom, w * zoom, h * zoom
        if Wd < 0.5 or Hd < 0.5:
            continue
        # (the mock reads an unset UIStroke.Enabled as false; the game never turns one off)
        strokes = [st for st in s.mods(n, "UIStroke") if st["t"] < 1 and n["class"] != "TextLabel"]
        if n.get("bgT", 1) >= 1 and not n.get("text") and not strokes:
            continue
        # draw into a small layer around the box (text may spill over a little)
        m = int(60 * zoom)
        ox, oy = int(X) - m, int(Y) - m
        lw, lh_ = int(Wd) + 2 * m + 2, int(Hd) + 2 * m + 2
        layer = Image.new("RGBA", (lw, lh_), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        X, Y = X - ox, Y - oy
        box = [X, Y, X + Wd, Y + Hd]
        corner = s.mod(n, "UICorner")
        r = 0
        if corner:
            r = (corner["radius"][0] * min(w, h) + corner["radius"][1] * k) * zoom
            r = min(r, Wd / 2, Hd / 2)
        if n.get("bgT", 1) < 1:
            d.rounded_rectangle(box, radius=r, fill=rgba(n["bg"], n["bgT"]))
        for st in strokes:
            d.rounded_rectangle(box, radius=r, outline=rgba(st["color"], st["t"]), width=max(1, int(round(st["thickness"] * zoom))))
        text = n.get("text")
        if text:
            # the object's own UIPadding narrows the text area
            pad = s.mod(n, "UIPadding")
            if pad:
                l, r_, t, b = pad["pad"]
                X += (l[0] * w + l[1] * k) * zoom
                Wd -= ((l[0] + r_[0]) * w + (l[1] + r_[1]) * k) * zoom
                Y += (t[0] * h + t[1] * k) * zoom
                Hd -= ((t[0] + b[0]) * h + (t[1] + b[1]) * k) * zoom
            size = n["textSize"] * k * zoom
            if n.get("scaled"):
                # TextScaled: as big as fits the box
                size = Hd * 0.9
                while size > 6 and d.textlength(text, font=font(n.get("font", ""), size)) > Wd:
                    size -= 1
            f = font(n.get("font", ""), size)
            lines = wrap(d, text, f, Wd) if n.get("wrapped") else [text]
            if not n.get("wrapped") and not n.get("scaled") and d.textlength(text, font=f) > Wd + 1:
                # (most labels truncate: TextTruncate.AtEnd)
                cut = text
                while cut and d.textlength(cut + "...", font=f) > Wd:
                    cut = cut[:-1]
                lines = [cut + "..."]
            lh = size * 1.15
            total = lh * len(lines)
            ya = n.get("yAlign", "Center")
            ty = Y if ya == "Top" else (Y + Hd - total if ya == "Bottom" else Y + (Hd - total) / 2)
            for i, line in enumerate(lines):
                tw = d.textlength(line, font=f)
                xa = n.get("xAlign", "Center")
                tx = X if xa == "Left" else (X + Wd - tw if xa == "Right" else X + (Wd - tw) / 2)
                d.text((tx, ty + i * lh + (lh - size) / 2), line, font=f, fill=rgba(n["textColor"], n.get("textT", 0)))
        # paste the part of the layer that is on screen
        sx0, sy0 = max(0, ox), max(0, oy)
        sx1, sy1 = min(W, ox + lw), min(H, oy + lh_)
        if sx1 > sx0 and sy1 > sy0:
            part = layer.crop((sx0 - ox, sy0 - oy, sx1 - ox, sy1 - oy))
            img.alpha_composite(part, dest=(sx0, sy0))
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, sc["name"] + ".png")
    img.convert("RGB").save(path)
    return path


def main():
    path, out = sys.argv[1], sys.argv[2]
    want = set(sys.argv[3:])
    for sc in parse(path):
        if want and sc["name"] not in want:
            continue
        zoom = 2 if sc["w"] < 1000 else 1
        print(render(sc, out, zoom))


if __name__ == "__main__":
    main()
