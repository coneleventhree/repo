# Design scripts (not part of the game)

Scratch tools the circuits and promo images were made with. They were written in
a throwaway workspace, so each has its folder paths as constants near the top
(`W = ...`, `S = ...`, `RENDER = ...`): point those at your own folders first.
Python 3 with numpy, scipy, matplotlib and Pillow.

## suzuka/ (how Suzuka was fitted and checked)
Data (download yourself, not included):
- Centre line: TUMFTM racetrack-database `tracks/Suzuka.csv`
  (https://github.com/TUMFTM/racetrack-database, LGPL-3.0). It was resampled to
  1 m steps into `work/res.npy` (columns s, x, y, curvature).
- Heights: GSI 5 m laser elevation keys every 50 m, collected in `dl/suzuka.toml`.

Pipeline:
1. `fit2.py K RMIN WIDTH KY SEP` - straights + arcs least-squares fitted to the real
   line (K = studs per metre, SEP = min centre-line gap between non-adjacent roads)
   -> `suzuka_fit2.json`. `check_fit.py` / `dev_check.py` plot it and list close
   approaches and deviation per segment; `raw_ang.py` / `curv.py` show the real
   curvature per range.
2. `gen_lua.py fit.json out.lua KY LOW DECK` - heights per segment end (start straight
   level, Last Curve slope, the dip under the bridge, deck height) -> Lua segments.
3. `put_track.py out.lua` - writes the Suzuka block into `src/shared/TrackData.luau`.
4. `luau tests/tools/dump_track.luau -a Suzuka > track.csv`, then `analyse.py` (bridge
   headroom, crossing angle, grades), `preview.py` (plan + height + speed figure,
   needs the speedmap csv), `view3d2.py` (side view of the hills).
5. In-game look: `luau tests/tools/dump_world.luau -a Suzuka > world.txt`, then
   `views.py` (camera views at track samples) or `topdown.py` (orthographic plan).

## promo/
`promo.py` renders thumbnails from `tests/tools/dump_scene.luau` output (adds simple
drivers); `make_icon.py` made the 512 px icon.

## gp/ (Catalunya, Zandvoort, Yas Marina)
Unlike suzuka/, these run as they are: `common.py` reads the work folder from
`GP_WORK` (default: the scratchpad it was made in). Put in it:
- `es-1991.geojson`, `nl-1948.geojson`, `ae-2009.geojson` from
  https://github.com/bacinger/f1-circuits (`circuits/`, MIT): current layouts,
  lap starting at the start line.
- The Copernicus GLO-30 DEM tiles named in `common.DEM`
  (`https://copernicus-dem-30m.s3.amazonaws.com/<name>/<name>.tif`).
Python also needs rasterio.

1. `tracks.py` - per circuit: scale K, min radius, centre-line gap SEP, height
   scale KY and grade limit, straights to shorten (`cuts`, each with the
   straights pointing the other way that give up the same length so the
   corners in between stay put), corner names by real distance, banking,
   height floors/caps (`ymin`/`ymax`).
2. `python3 -I fit_gp.py <id> --plot` - segments from the curvature, least
   squares fit to the (shortened) real line, heights from the DEM ->
   `<id>.lua`, `<id>.json`, `<id>.png` (plan vs real, height profile).
3. `python3 -I put_tracks.py` - writes the three into `src/shared/TrackData.luau`
   (replaces their blocks, adds them to Order / Tracks).
4. `luau tests/layout_test.luau`, `luau tests/physics_test.luau`,
   `luau tests/tools/laps.luau`.
