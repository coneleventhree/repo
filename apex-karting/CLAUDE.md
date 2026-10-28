# A1 Kart Racing - notes for Claude
(Formerly "Apex Karting"; renamed by the user. The DataStore name ApexKarting_v1 stays so saved
bests survive. The repo folder is still apex-karting.)

Roblox kart racer (realistic physics, players only, no items, six tracks; Hillside has hills and banking,
Suzuka is a 3D figure of eight with a bridge;
lobby menu with RACE matchmaking / PRACTICE / PRIVATE ROOM and a loading screen). Rojo project.
Made for playing with friends: no anti-cheat / anti-troll work (the user said so).

## Conventions
- Reply to the user in Korean casual 존댓말; explain English technical terms in Korean parentheses.
- Shared modules (`src/shared`) are pure Luau: no Roblox APIs, no `require` between them
  (RaceProgress takes TrackMath as an argument). They use the built-in `vector` library,
  which is Vector3 at runtime in Roblox. Roblox-side code casts with `Build.v3` / `Build.vec`.
- All tunables in `Config`. In-game text ASCII only.
- The place file has no hand-built parts; the server builds everything at start.
- Physics changes: run `luau tests/physics_test.luau` (includes autopilot laps at 60/30/20 fps)
  and `luau tests/tools/agility.luau` (turn radius / lateral g per speed).
- Any script change: `python3 tests/mock/gen.py && luau tests/e2e_test.luau`.
  The mock rejects unknown members and wrong value types using luau-lsp's Roblox definitions
  (`gen.py` takes the path to `globalTypes.d.luau`).
- Type check: `rojo sourcemap default.project.json -o sourcemap.json` then
  `luau-lsp analyze --platform=roblox --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src/`.

## Circuit notes
- Part-built circuits (no Terrain; Hillside's / Suzuka's hills are wedge embankments). Every drivable part has a `Surface` attribute
  naming a `Config.Surfaces` entry; the client reads it for grip.
- Road/bands are wedge triangles (`Build.triangle`, EgoMoose's method). Straight runs are
  merged by `TrackBuilder.ribbon`. Lawn top is y = -0.1, everything drivable else ~0 (except on Hillside).
- CFrame.fromMatrix must get a right-handed basis (the mock asserts it).
- Previews: `luau tests/tools/dump_world.luau > world.txt` then `python3 tests/tools/render.py world.txt out/`.
  render.py draws SpecialMesh Sphere parts as ellipsoids; kart_* shots skip the Cockpit folder.

## Kart model notes
- KartFactory bodywork is a rental kart (Sodi RT8/SR5 look, the user's reference photos):
  a continuous bumper ring (walls + lips + round joints) built on the Config.Kart.Bumper
  outline, outside all four wheels; hollow nose with a number panel; side pods; rear wheel
  guards; roll bar with pad; translucent fuel tank; 4-stroke engine. Helpers: `ellipsoid`,
  `between`, `slab`, `ellipsoidBetween`, `faceToward`, `numberPanel`. All bodywork is
  massless and non-colliding. `KART_ONLY=1 python3 tests/tools/render.py ...` renders just
  the kart views.
- No real brand names on the model (air filter says "AK 270"). Use record types, not
  tuple-typed tables, for luau-lsp (`{ { Vector3, number } }` is a syntax error).

## Physics notes
- 1 stud = 0.28 m; kart gravity 35 studs/s^2, the client cancels the rest of workspace gravity.
- Only the compact chassis core (`CoreSize`) has mass; the collision `Hitbox`, bodywork, seat
  and seated character are massless, so the core inertia KartPhysics assumes is what
  Roblox simulates. A big massive box made the kart lazy to turn.
- The client casts two rays per wheel and keeps the nearer hit (seams between road parts).
- Ride on hills (user: "on Hillside the kart rattles going up and down slopes", Oct 28 2026).
  `tests/tools/ride.luau -a "<id> [fps] [plain|fold] [spacing]"` measures it: pitch/roll rate
  minus a 0.15 s average. Hillside was 4.6 deg/s rms (flat circuits ~0.65), Suzuka 2.0. Three
  causes, three fixes: (1) twisted road quads (climbing corners, banking winding on) built as two
  triangles had a fold along the diagonal up to 0.65 studs -> TrackLayout.roadSplit /
  roadTriangles split such quads into a bilinear grid until every fold < RoadFold 0.05
  (TrackBuilder builds those pieces, the ribbon the rest; tests/lib/world uses the same pieces);
  (2) facets of a sloped / banked corner every sample -> hilly circuits use Spacing 5 (every
  sample window in TrackLayout goes through `steps(track, n6)` so it keeps its length in studs);
  (3) at 20-30 fps a wheel crossing a piece edge mid-frame -> KartPhysics casts a second ray per
  wheel at mount + vel*dt and blends height/normal between the two planes over the substeps.
  Now Hillside 0.81 / Suzuka 0.69 at 60 fps, 1.25 / 0.93 at 20 fps. physics_test checks it
  (limits 1.0 / 1.3 / 1.6 at 60 / 30 / 20 fps), layout_test checks every piece's fold.
  Smoothing the heights alone (Catmull-Rom between samples) did nothing; spacing 4 was a bit
  smoother still but +50 % parts. On raised roads the turf base is skipped where both samples
  are plain turf (it only fills tapers), which paid for most of the extra parts; to keep that
  crack-free, ribbon() takes a merge tolerance and raised circuits use 0.002 (was 0.03: two
  ribbons merging different runs left hairline cracks down to the lawn). Parts: Hillside
  18.8k -> 25.3k, Suzuka 26.1k -> 30.0k. With Spacing 5 a Hillside pocket fan (S-bend) folded
  for every hub: pockets() now tries other hubs (outline centroid, band-edge middle, blends),
  and if all fold carries the run's strips on to the lawn (a crease, not a hole).
  `tests/tools/probe_hill.luau [-a Suzuka]` (practice server) lists steps > 2.5 studs beside
  the raised road (Suzuka's are the trench walls and grass steps behind them).
- KartPhysics predicts each frame at 240 Hz against the ground planes from the wheel rays and
  returns the average force/torque: stable down to about 20 fps.
- Steering assist sets front slip angle relative to the front axle's travel direction.
  `KartPhysics.assistSlip` inverts the Pacejka curve so input share = grip share (linear yaw
  response); full input = 8 deg, just past the tyre peak of ~7 deg. inputFor bisects it.
- Keys/touch steering goes through SteerFilter (speed-sensitive ramp, Config.Steering) in
  KartController before KartPhysics; the stick only gets a light rate limit and a curve.
  `luau tests/steering_test.luau` and `luau tests/tools/turnin.luau` check the feel.
- Tyre curve (B 12.3, C 1.6) falls off past the peak, so over-steering the fronts understeers.
  Rear wheels have `stiffness = 1.6` (multiplies B): without it the faster steering ramp made
  yaw overshoot ~22%; with it ~10%.
- `Kart.AssistCatch`: when rear axle slip exceeds 1.15 x rear peak, steerTarget backs the front
  slip off by gain x excess (catches trail-brake slides; keyboard lap max slip 39 -> 5.5 deg).
- Engine = outdoor rental kart (user asked for researched, slower acceleration so corner exit
  and early throttle matter): ~15 hp GX390-class 4-stroke, one gear, ~250 kg with driver.
  DriveAccel 8.5 (torque-limited ~0.24 g), PowerPerMass 520 (~10 kW at the wheels); drag holds a
  lone kart to ~95 km/h, so the TopSpeed 100 governor is only reached in a tow. 0-50 6.8 s,
  0-80 13.4 s. `luau tests/tools/accel.luau` (exit-speed carry-over, tow) and
  `luau tests/tools/laps.luau` (autopilot laps: Tampines ~37.5 s, Silverstone ~83.7 s).
  Old values 19 / 860 (~23 hp) hit the governor on every straight.
- Keyboard W/S ramp in Input with `Config.Pedals` (S ~0.25 s to full). Coast/brake/corner
  numbers: `luau tests/tools/decel.luau`. Autopilot (tests/lib/sim) brakes for the minimum
  planned speed over its look-ahead, so lowering drag/engine braking doesn't make it run wide.

## Bumper notes (kart-to-kart contact)
- Roblox collisions Karts<->Karts are off (init.server). Contact is computed by each driver's
  client inside KartPhysics.step (optional `others: { Obstacle }`): rounded-rectangle bumper
  (`Config.Kart.Bumper`, same shape as the visual ring), outline points of each kart tested
  against the other's signed distance, pen-weighted normal/point; accel =
  clamp(min(Stiffness*pen, SpringMax) - Damping*vn*fade, 0, MaxAccel), fade = min(pen/0.25, 1),
  plus rubbing friction; force horizontal at COM height (yaw torque only), so no launches.
- KartController.nearbyKarts extrapolates other karts by Lead + PingShare*(myPing + theirPing)
  (server sets player attribute Ping every 2 s). collision_test.luau shows the 0.15 s case:
  phantom push 4.2 studs early without lead, at the real touch with it.
- Hitbox covers the bumper ring (BoxSize 6.6 x 6.75, BoxOffsetZ 0.375). World.newBody takes
  hitOffsetZ. The e2e bot passes A's kart as an obstacle; the mock has Player:GetNetworkPing
  (G.pings[p], default 0.06).
- `luau tests/tools/bumps.luau -a "S SM D MA"` prints squash/bounce/peak g for typical hits.

## Camera notes
- ChaseCamera owns the driving camera (Scriptable): zoom 0 = cockpit, otherwise chase distance.
  Wheel/pinch/D-pad zoom, C cycles `Config.Camera.Presets`, RMB / right stick free look.
- Cockpit eye is a fixed point in the kart frame (`Config.Camera.Cockpit.Eye`), not the avatar's
  head, so every avatar gets the same framing. Head/arms/accessories get LocalTransparencyModifier 1;
  KartVisuals draws sleeves + gloves on the steering wheel rim (own kart, cockpit only).
- `tests/tools/dump_world.luau` zooms into the cockpit and prints a CAMERA line; render.py draws it.
- Cockpit view comes from shared `CockpitRig` (critically damped springs, partial horizon lock,
  head sway; look-into-turn off by default because it swings back). `tests/camera_test.luau`.
- Behind the kart, orbit yaw/pitch persist (RMB drag, right stick, touch drag); V / R3 recentre.
  In the cockpit the same inputs are a head look that springs back.

## Tracks
- `TrackData` is a registry: `Tracks[id]` specs, `Order` (vote cards), `Default`, `get(id)`.
  Per-track fields: Name, Blurb, Laps, Bridge, Sky, PitStyle, CornerBoards, Segments.
- init.server builds the default circuit into workspace.Circuit, then the others (task.defer)
  into folders that RaceManager parks in ServerStorage.Circuits (named by id). Switching
  (RaceManager.switchTo) removes all karts, swaps the folders, sets workspace attributes
  Track / TrackName / Laps, calls Stats.setTrack and RaceManager.onTrackChanged (weather).
  Clients refresh ray filters on the Track attribute / Circuit ChildAdded; Hud redraws the minimap.
- Practice: Request("Vote", id) switches at once (cooldown). Intermission: it is a vote
  (Votes_<id> attributes, player attribute Vote); the winner is applied when the grid forms.
- Stats keeps bests per track; DataStore keys for the first track are unchanged
  (`best`, `track_record`), others use `bests[id]` and `track_record_<id>`.
- Consecutive arcs with the same name are one corner (`TrackLayout.corners`): stands at
  >= 90 deg, marshal posts at >= 60 deg, corner boards at every named corner.
- Silverstone was fitted (scratch scripts, not in the repo) to the TUMFTM racetrack-database
  centre line at 1 stud per metre: corners split into arcs by curvature, then lengths, radii
  and angles least-squares fitted so segment ends land on the real line (mean ~4 studs).
  Min radius 30. Racing-line lap ~79 s; physics_test autopilot (centre line) ~84 s
  (scratch trackdb/laptime.py; DA / PPM env vars set the engine).
- Kart circuits Lakeside / Harbour (user: "maps more suitable for karts"; Pine Valley was removed
  at the user's request and Hillside took its slot 4): original
  designs checked against the FIA karting circuit licence criteria at 0.28 m/stud (width >= 8 m,
  start straight 120-200 m, line->T1 >= 50 m, last corner->line ~70 m, straights <= 200 m,
  >= 6 m between parts). Designed with scratch kart/design.py + close.py (stretches straights by
  least squares so the lap closes, keeps two "free"). Autopilot laps ~55 / 49 s.
- Hillside (user: "3D circuit with ups and downs and banked corners", picked layout B of two
  sketches): the only circuit with y / bank. Plateau design (hill climb 0 -> 32 on the east side,
  crest, corkscrew, Karussell 12 deg and Bowl 12 deg banked on the plateau at ~24-28, long
  Downhill to an Eau Rouge dip, Raidillon climb, Long sweeper at y 3). Grid straight
  split in two (120 descending + 131 level) so the grid stays level. Autopilot lap ~58.5 s.
  Rules learnt: (1) banking lowers the inside edge by w/2 sin(bank): the road there must be
  raised so no edge goes under the lawn (layout_test checks); (2) two roads whose bands nearly
  touch must be within ~1.5 studs in height (the plateau exists because the Bowl's gravel nearly
  touches the corkscrew straight); (3) BankSmoothing 40: a fast bank twist (22) rocked the rigid
  kart onto two wheels and at 20 fps the sim went NaN; 15 deg at the Karussell made the 20 fps
  autopilot spin, 12 deg is fine. tests/tools/bank.luau: 12.6 m hairpin 54 km/h flat -> 65 at 12 deg.
- Hillside v2 (user, Oct 28 2026, approved from a before/after preview): "Sling" = right-left kink
  r 85 +-28 deg at the top of the Hill climb (straight B), 44 studs before the Crest (autopilot
  76 km/h with a slight lift: committed but not flat for a keyboard); "Long sweeper" = one 180 deg
  r 72 bank 6 corner replacing the two 90 deg Last corners (65-69 km/h, steering held ~3 s). The
  back straight rose to y 2 (bank 6 put the inside band under the lawn at y 1). Design with
  `tests/tools/speedmap.luau -a <id>` + `speedmap.py` (autopilot speed per sample, corner minima).
  User guideline for all maps: size corners, road width and the whole circuit for the kart's
  speed (lone top ~95 km/h; corners flat above r ~126 studs at Mu 2).
- Suzuka (user: "copy Suzuka with real elevation, not 2D", approved from a preview Oct 28 2026):
  TUMFTM centre line at K = 0.8 studs/m, heights from GSI 5 m laser DEM keys (suzuka.toml)
  x 0.8 with the Second Curve as the lawn (y 0). Fitted with tools/design/suzuka/fit2.py (see tools/design/README.md; paths at the top of each script) (arcs
  incl. the gentle Spoon exit and 130R tail; radius bounds 0.85-1.25x, angles +-8 %; generic
  separation penalty: non-adjacent centre lines >= 50 studs apart except the crossing pair) and
  gen_lua.py (heights per segment end; start straight + T1 level at 0, the main straight split
  120 sloping + 170 level; Last Curve one even slope from the chicane; "Under the bridge"
  straight dips to y 14, the back straight's free part ends at 31 and 130R stays at 31 for
  headroom). Width 28 (main straight 30), Laps 2 (1/2/3), Qualifying 180, Trees, CornerBoards,
  Bridge = "Main straight". Autopilot 69.7 s. Gyaku Bank off-camber was tried: even -1.5 deg
  throws the autopilot off at the left-right flick, so it is flat.
- Crossings (figure of eight): TrackMath accepts corners summing to 0 deg. TrackLayout.crossings
  (cached per Ground): an upper sample over another road's centre line (2D, d < width/2, > 6
  studs higher) -> `deck` = upper samples whose road+bands reach the lower road's band edge + 3,
  `walls` = per lower sample/side where rawGroundY beside the band edge (lower road's own
  samples within 60 left out) is above the edge: top = that + 2.5, capped under the deck at
  road y - RoadThickness - GirderDepth. zones() gives the lower road no run-off/gravel within 13
  samples (underCrossing). skirts(): no strip from an edge standing over a lower road. groundY()
  inside the trench (on the lower road's prepared surface near a crossing) leaves the upper
  road's samples (over +-45) out. Gap walls skip samples nearCrossing(15), tyres nearCrossing(3).
  TrackBuilder.crossings: Girder (per deck pair, blue concrete), Parapets (deck +-3 samples,
  down the girder side over the span), trench walls as sloped-top triangle pairs.
  Kart contact and tow ignore karts > 5 studs apart in height (KartPhysics OTHER_LEVEL;
  KartController skips > 8). TrackMath.nearest is 3D so laps/limits/progress just work.
  Check with `tests/tools/crossing.luau -a Suzuka`; layout_test has the crossing checks.
  render.py (painter's algorithm) draws the girder over the deck road in some views: HIDE it
  (scratch topdown.py) to check.
- Hills: TrackLayout.ground (per-sample band-edge points, cached per track) + groundY(x, z)
  (max of cones falling 1 in EmbankRun = 2.5 from every band edge; 0 on flat tracks) +
  skirts (embankment strips per sample/side: straight out from the band edge, stopped at the
  lawn, where a neighbour's strip crosses (inside corners), where another leg's higher slope
  takes over, or at another road's cross-section -> then ends at that road's edge height).
  TrackBuilder.embankments builds them (Track/Embankments, Surface Grass). Strips that meet
  another road at once are kept at zero length (their tops close thin gaps between two bands);
  a very short strip down to a lower road is capped at 1 in 0.8. Runs of strips that stop
  above the lawn inside a tight corner (`pocket`) are replaced by a fan to one hub
  (TrackLayout.pockets: band-edge points -> hub, hub -> the long strips either side, mouth at
  their toes or where they cross); a fan that would fold keeps its strips (Karussell inside).
  On a raised road TrackBuilder lays a turf "base" band (road edge -> bandEnd, Surface Turf)
  under the kerb/run-off/gravel/turf bands: their tapers leave slivers that are holes up a hill.
  tests/tools/probe_hill.luau lists every step > 2.5 studs beside the raised road (e2e checks
  50 studs out; further out, where strips from two corners cross, ~5-stud grass creases remain
  in the corkscrew pocket). Ribbon merging also requires the strip to stay planar (< 0.002).
  Barriers, marshal
  posts, corner boards, trees and lamp posts take groundY; grandstands: the main one on the
  level (full length, else 200 / 140 slid along the pits), corner ones on the level or, on an
  embankment, raised to the highest ground under them on a concrete Plinth (Hillside: Crest,
  Karussell, Bowl; Suzuka: Gyaku Bank, Hairpin, Spoon);
  the facility margin grows to fit the embankments; paint lines lie on smp.up (banking).
  The test world's addTrack(track, grip, roll, bands) adds level verges (physics_test uses 20).
- Spec flags: Lake (Scenery.water: discs in TrackLayout.openGround's most open spot; openGround's
  `clear` also counts the fence and grandstands, so the lake stays inside; in the Track
  folder with Surface "Water"), Trees (Scenery.trees: pines on open ground >= 50 studs from the
  road), TrackLights (Scenery.trackLights: lamp posts every ~55 studs with wide (150 deg, range 60) SpotLights), Sky
  Sunset / Night (Scenery.lighting also sets Ambient/OutdoorAmbient; floodlight towers get
  SpotLights at night). Vote cards are a 2-column grid (Tracks.Cards.Card_<id>).
- Readability over realism (user: "some maps are too dark to see the road", on a phone): Night
  has ambient 105/110/130, outdoor 125/132/160, exposure 0.6, ColorCorrection Brightness 0.04
  (`lift`) and a thin, lighter haze; Cloudy (Silverstone) exposure 0.2, clouds 0.5, a little more
  ambient. Sunset is unused since Pine Valley went.
- Mock note: a static part that leaves and re-enters workspace keeps its ray-index entry
  (fixed in tests/mock/roblox.luau; before, it became "dynamic" and rays crawled). Likewise
  parts placed while outside workspace (circuits built into ServerStorage after the ray index
  exists) stay static and get indexed when they enter; before, every stored circuit's parts
  were brute-forced on every ray and e2e took 30+ min instead of ~3.

## Race weekend (RaceManager)
- States: (Lobby) / Practice -> Intermission (track vote, length vote Short/Normal/Long from TrackData
  `Lengths`, READY; all ready -> Config.Race.ReadyCountdown) -> Qualifying -> Grid (quali order,
  late joiners at the back) -> Racing -> Results (podium ResultsTime 8 s, "short so the next round
  starts quickly") -> Intermission (race server) / Lobby (a room's waiting room, all NOT READY).
- Qualifying is ONE timed lap with ghosts (user's choice, Oct 28 2026; it replaced the earlier
  "no ghosts" timed session): everyone spawns at the same run-up pose (gridSlot with
  GridFirstRowBack = QualiRunUp 70, no lateral/stagger), quali = RaceProgress session with laps = 1
  (the lap is timed from the line: rolling start), "finish" = the lap is in -> player attribute
  QualiDone + QualiDone event {best, place}. Over when everyone is done (q:allDone) or at the
  track's `Qualifying` seconds (chequered flag: finish the lap, at most QualiOvertime). A deleted
  lap = no time = back of the grid. Workspace attribute Ghost = (state == Qualifying):
  KartController.nearbyKarts returns none (no bumpers, no slipstream), KartVisuals sets
  LocalTransparencyModifier GhostTransparency 0.6 on other karts + their drivers (refreshed
  every 0.5 s; drivers reset to 0 when it goes off, since they outlive the quali karts).
- Workspace attributes: Votes_<id>, LenVotes_<len>, ReadyCount, QualiClosing, Podium; player:
  Vote, LengthVote, Ready, Warnings, Penalty, S_<setting>.
- RaceEvent kinds for the HUD: LapStart, Sector {index, time, colour}, Lap {time, invalid, colour,
  pb, final}, TrackLimits {deleted | warnings, max, added, penalty}, Qualifying, Chequered,
  QualiDone, QualiResult, AllReady, Go, Finish, Results, Standings {mode race|quali}, Record, Track.
- Sector colours: purple session best, green own best, yellow slower, invalid grey (struck-off lap).
- Track limits (shared TrackLimits): all four tyres beyond road edge + kerb + 0.25; counted after
  0.2 s out at >= 8 studs/s, re-armed after 0.4 s back. The search hint is the tracker's own
  `TrackLimits.locate` (not racer.idx, which holds still while RaceProgress rejects a cut or a
  jump: a stale hint made every tyre look off the road). Practice/quali: lap deleted. Race: 3
  warnings then +2 s each (user: 5 s too long for short kart races). Penalties are added in
  classification and shown in results.
- Podium: Scenery.podium in the paddock plaza (Pits/Podium: Step1..3 facing +Z, Camera part,
  Confetti part with ParticleEmitters). ChaseCamera shows it while RaceState=Results and Podium.
- Slipstream: KartPhysics.draftTarget/state.draft (Config.Kart.Slipstream); HUD badge at draft > 0.25.
- Not built (not approved): championship points, reverse grid.

## Lobby, server modes and menus (user-approved design, Oct 28 2026)
- User's choices: lobby + teleport to reserved servers; friends via room codes; quick race starts
  7 s after the 2nd driver (12 = at once; alone = keep waiting); one-lap ghost qualifying.
- Every public server is a lobby (RaceManager state "Lobby", characters frozen, no karts; a
  published lobby builds ONE random circuit for the menu fly-by). Session.resolve: a reserved
  server (PrivateServerId ~= "" and PrivateServerOwnerId == 0) reads its role from MemoryStore
  hash map A1Servers[PrivateServerId] (written by Session.reserve), else the first player's
  TeleportData. Role = {mode = lobby|practice|race|room, track?, code?, host?}. Workspace
  attribute ServerMode; RaceManager.setMode.
- Session.send: RaceEvent "Teleport" {mode, track, code, label} to the clients (Menu puts up the
  LoadingGui and TeleportService:SetTeleportGui), Stats.saveNow, then TeleportAsync with
  TeleportOptions (ReservedServerAccessCode + SetTeleportData). TeleportInitFailed / pcall ->
  "TeleportFailed" event (menu shows the error). Studio (RunService:IsStudio): no teleports; the
  one server switches in place (Session.switchHere -> RaceManager.setMode) with everyone in it.
- Lobby.luau handles Request kinds Practice(trackId) / Queue(true|false) / CreateRoom /
  JoinRoom(code) (lobby only) and ToLobby (elsewhere). Errors -> "MenuError" {message}.
- Matchmaker: shared sorted map A1Queue (key UserId, value {job, t, name}, renewed every
  QueuePoll 1.5 s, TTL 45 s). Start time = free[QueueMin].t + QueueWait (or now at QueueMax);
  the server that gets the A1Locks "queue" lock reserves a race server and writes `code` into
  the first QueueMax tickets; each lobby sends its own players whose ticket has a code. Player
  attributes Queued, QueueCount, QueueGo (server time). Clock = DateTime UTC.
- Rooms: A1Rooms code -> {access, host, name, banned?}; the code is claimed (UpdateAsync) before
  the reserve; the room server renews it (RoomRefresh) and removes it on BindToClose.
- Room waiting room (user: "like an Overwatch custom lobby", Oct 28 2026): a room server rests in
  State "Lobby" (RaceManager idle() = Lobby for lobby/room, Practice otherwise; setState freezes
  characters entering/leaving Lobby). No karts. Host (RoomHost/RoomHostName; next player if they
  leave) picks the track (Vote, RoomTrackCooldown 1 s) and length (Length -> RoomLength); guests
  send Ready true/false (player attribute Ready); "Start" only if guestsReady() (every player
  but the host). After Results: resetVotes, back to Lobby. "Kick" {userId}: host only ->
  kicked[userId] (per room code), RaceManager.onKick -> init.server: Rooms.ban (adds to the
  entry's `banned`, Rooms.join refuses) + Session.kick (teleport to a lobby with TeleportData
  notice, shown by Menu for 9 s; Studio: Player:Kick). A kicked player who arrives anyway is sent
  away again (onPlayer).
- Client: Menu.luau (ScreenGui "Menu": Home, Practice cards (TrackOutline thumbnails, Best_<id>
  player attributes / Record_<id> workspace attributes from Stats), Queue, Room (code TextBox,
  digits only), Records, RoomLobby (Code, PlayersTitle, Slot1..12 {PlayerName, Status, Kick
  (tap twice, KickConfirm)}, Track {TrackName, Info}, Prev/Next or HostPicks, Len_<length>,
  Leave, Status, Action = READY / NOT READY / START RACE), Error, NowShowing, LobbyButton (press
  twice within LobbyConfirm), fly-by camera bound at Camera+5 in the lobby and the waiting room).
  Child labels must not be called "Name" (the property wins: `slot.Name`). SettingsMenu button
  and the Hud are hidden in the lobby and the waiting room.
- Loading screen: src/first (ReplicatedFirst.Loading): RemoveDefaultLoadingScreen, reuses
  TeleportService:GetArrivingTeleportGui() if it is ours (has "Back"), status from
  GetLocalPlayerTeleportData().label, bar to 55% while loading, 95% until TrackReady, min 2 s,
  max 60 s. LoadingGui is plain frames (no images to upload).
- Mock: MemoryStoreService (G.memory[name][key] = {value, expires}, G.memMap, G.memoryFails),
  TeleportService (G.teleports {players, code, data}, G.reservedCount, G.reserveFails,
  G.teleportFails, G.teleportGui[ctx], G.arrivingGui, G.localTeleportData), Game.boot opts
  studio (default true), reserved = role, privateServerId, wait = false; Game.startLoading.
  Test files have no `Enum` global (compare `.Name`). `tests/lobby_test.luau` covers all of it.
- Menu UIScale: fits the biggest screen (814 x 480 + top bar inset from GuiService:GetGuiInset,
  58 fallback) when that is < 1 (phones ~0.67), else Settings.pixelScale. Touch: LOBBY button top
  left under the top bar; Hud's track/vote/room panel centred at the top (y 58) instead of the
  left side, where it covered the steering buttons.
- GUI previews: `luau tests/tools/dump_gui.luau > gui.txt && python3 tests/tools/render_gui.py
  gui.txt out/` (approximate layout: UDim2, anchors, UIScale, UIPadding, list/grid layouts,
  AutomaticSize Y, corners, strokes, TextScaled; DejaVu instead of Gotham). The mock has Roblox's
  real defaults for text alignment, UIListLayout/UIGridLayout, UIPadding, UIStroke, UIScale.

## Touch input (phones)
- The user saw the kart turn in circles by itself on a phone: a touch button's own InputEnded
  does not fire when the finger slides off before lifting, and Input's press counter then kept
  the button held for good. Input now keeps the set of InputObjects holding each button and
  drops one on UserInputService InputEnded / TouchEnded, on WindowFocusReleased, and by polling
  `UserInputState == End/Cancel` every frame. ChaseCamera does the same for its look-around
  finger (`touchDrag`): Roblox recycles touch InputObjects, so a stale one made a finger moving
  on GAS swing the camera.
- `tests/touch_test.luau` (mock: G.touch, G.touchBegin(button?, io?), touchMove, touchEnd(io,
  overButton), touchLost) fails 7/13 on the old code (kart turned 134 deg with no finger down).

## Settings and sound
- Config.Settings (items + order). Server Stats validates (cleanSetting), stores in the player's
  DataStore record (`settings`), publishes S_<key> attributes, saves 8 s after a change.
- Client Settings.get/set/onChange; pending value kept until the server echoes that exact value
  (several clicks in a row stay consistent). SettingsMenu builds rows Row_<key> with Left/Value/Right.
- Sfx: SoundGroups KartEngine / KartEffects (master x engine / effects); one-shots by name from
  Config.Audio <Name>SoundId; crowd loops on Grandstands/*/Roof. KartController plays Bump on contact.
- `sounds/make_sounds.py` synthesises the original .ogg set (numpy, scipy, ffmpeg; pass names to make
  only some: `engine flag`). 16 sounds; Config.Audio has the user's uploaded ids (Oct 27 2026). Sfx.play returns
  false for an empty id, so Hud falls back (Best -> Lap, Warning/Penalty -> Beep).
- Mix (user: "engine almost inaudible, the wind-like sound too loud"): the first 3000 rpm engine
  had its energy below 150 Hz, which a phone speaker cannot play (-40 dB(A) at volume 1 vs the
  crowd's -18), so tyres/crowd noise dominated. The engine was re-synthesised with pipe/muffler
  resonances 85-1750 Hz, a 600 Hz chain whine, clatter and intake (-22 dB(A) on a phone), kerb /
  off-road / bump brightened too, and the volumes solved with `sounds/mix_levels.py` (prints
  dB vs the engine on phone / laptop / headphones). Those 4 files were re-uploaded (new ids in Config.Audio).
- Engine audio is an rpm model (KartVisuals): EngineRpmLoop 3000 is the loop's recorded rpm; idle
  1600; on the throttle the centrifugal clutch slips at 2600 until road rpm (4200 x speed/TopSpeed)
  is higher; off the throttle the revs follow the road until 2000 (clutch releases), then idle.
  Offroad loop: wheels on Gravel (1) / Water (0.8) / Grass, Turf (0.6), x speed/30. Kerb loop:
  wheels on Kerb, PlaybackSpeed = speed / 72 (12 blocks a second in the loop, ~6-stud blocks).
  Own kart casts one extra ray per wheel for this only when either loop has an id.
  `tests/sound_test.luau` checks revs, rumble and kerbs.
- Mock: NumberRange/NumberSequence/ColorSequence(+Keypoint) exist in tests/mock/datatypes and in
  gen.py GLOBALS; add new Roblox globals to both.
- e2e shortens qualifying by editing the server's TrackData (Game.sharedModule(G, G.serverCtx, ...)).

## HUD text sharpness
- The user saw blurry/faint lap times. Causes fixed: UIScale at fractional values (1.07 etc.) put
  every element between pixels; AnchorPoint 0.5 on odd-width screens; TextScaled with regular
  RobotoMono shrinking long lines; a toast fade tween not cancelled when the next toast came
  (and its UIStroke never faded).
- Rules now: UIScale from Settings.pixelScale (1, 2, or < 1 only on small screens); centred
  elements registered with Hud `centre()` and placed on whole pixels (placeCentred on resize);
  times use `fixed(...)` labels (fixed TextSize, MONO_BOLD = RobotoMono Bold FontFace);
  y positions as offsets, not screen fractions.
- Mock: tweens step numbers per frame (Cancel works), Font datatype, G.setViewport(Vector2).

## Known limits / ideas
- The lobby fly-by camera (16 up, 26 aside) can skim Suzuka's bridge / trench walls for a moment.
- Suzuka ideas not done: off-camber Gyaku Bank, a Ferris wheel behind the hairpin.
