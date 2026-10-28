"""Shared helpers for the GP circuits (Catalunya, Zandvoort, Yas Marina).

Centre lines: bacinger/f1-circuits GeoJSON (MIT, OpenStreetMap based), current
layouts. Heights: Copernicus GLO-30 DEM (30 m) sampled along the line.
W = work folder with the downloads (see README.md).
"""
import json, math, os
import numpy as np

W = os.environ.get("GP_WORK", "/tmp/claude-0/-home-user-repo/68c6e3b1-202e-5933-b202-d4a9689a867b/scratchpad/gp/")

def load_line(gid):
    """GeoJSON id -> (lon, lat) arrays of the closed line (last point not repeated)."""
    g = json.load(open(os.path.join(W, gid + ".geojson")))
    c = np.array(g["features"][0]["geometry"]["coordinates"], float)
    if np.hypot(*(c[0] - c[-1])) < 1e-9:
        c = c[:-1]
    return c[:, 0], c[:, 1]

def project(lon, lat, lon0=None, lat0=None):
    """Equirectangular metres east (x) / north (y) of (lon0, lat0)."""
    lon0 = lon[0] if lon0 is None else lon0
    lat0 = lat[0] if lat0 is None else lat0
    R = 6371008.8
    x = np.radians(lon - lon0) * R * math.cos(math.radians(lat0))
    y = np.radians(lat - lat0) * R
    return x, y

def resample_closed(x, y, step=1.0):
    """Closed polyline -> points every `step` metres (periodic linear)."""
    P = np.c_[x, y]
    P2 = np.vstack([P, P[:1]])
    d = np.hypot(*np.diff(P2, axis=0).T)
    s = np.r_[0, np.cumsum(d)]
    L = s[-1]
    n = int(round(L / step))
    t = np.linspace(0, L, n, endpoint=False)
    return np.interp(t, s, P2[:, 0]), np.interp(t, s, P2[:, 1]), L

def smooth_closed(v, sigma):
    """Periodic Gaussian smoothing (sigma in samples)."""
    n = len(v)
    k = np.arange(-int(4 * sigma), int(4 * sigma) + 1)
    w = np.exp(-0.5 * (k / sigma) ** 2); w /= w.sum()
    out = np.zeros(n)
    for kk, ww in zip(k, w):
        out += ww * np.roll(v, -kk)
    return out

def curvature(x, y):
    """Signed curvature (1/m), + = left turn (anticlockwise) for x east, y north."""
    dx = np.gradient(x); dy = np.gradient(y)
    ddx = np.gradient(dx); ddy = np.gradient(dy)
    dx[0] = (x[1] - x[-1]) / 2; dy[0] = (y[1] - y[-1]) / 2
    dx[-1] = (x[0] - x[-2]) / 2; dy[-1] = (y[0] - y[-2]) / 2
    return (dx * ddy - dy * ddx) / np.power(dx * dx + dy * dy, 1.5)

DEM = {
    "es-1991": "Copernicus_DSM_COG_10_N41_00_E002_00_DEM.tif",
    "nl-1948": "Copernicus_DSM_COG_10_N52_00_E004_00_DEM.tif",
    "ae-2009": "Copernicus_DSM_COG_10_N24_00_E054_00_DEM.tif",
}

def dem_sample(gid, lon, lat):
    """Bilinear DEM heights (m) at lon/lat arrays."""
    import rasterio
    with rasterio.open(os.path.join(W, DEM[gid])) as ds:
        a = ds.read(1).astype(float)
        inv = ~ds.transform
        c, r = inv * (np.asarray(lon), np.asarray(lat))
    c = np.asarray(c) - 0.5; r = np.asarray(r) - 0.5
    c0 = np.floor(c).astype(int); r0 = np.floor(r).astype(int)
    fc = c - c0; fr = r - r0
    return (a[r0, c0] * (1 - fc) * (1 - fr) + a[r0, c0 + 1] * fc * (1 - fr)
            + a[r0 + 1, c0] * (1 - fc) * fr + a[r0 + 1, c0 + 1] * fc * fr)

def unproject(x, y, lon0, lat0):
    R = 6371008.8
    lon = lon0 + np.degrees(np.asarray(x) / (R * math.cos(math.radians(lat0))))
    lat = lat0 + np.degrees(np.asarray(y) / R)
    return lon, lat

def real_line(gid, sigma=6.0):
    """Lap from the GeoJSON start (the start line): 1 m samples, smoothed.
    Returns x, y (m, east/north), heights h (m, DSM, raw), lon0, lat0."""
    lon, lat = load_line(gid)
    x, y = project(lon, lat)
    xr, yr, L = resample_closed(x, y, 1.0)
    xs, ys = smooth_closed(xr, sigma), smooth_closed(yr, sigma)
    lo, la = unproject(xs, ys, lon[0], lat[0])
    h = dem_sample(gid, lo, la)
    return xs, ys, h, lon[0], lat[0]
