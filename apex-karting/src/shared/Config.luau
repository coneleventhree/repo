--!strict
-- Every tunable number lives here. Units are studs and seconds.
-- Scale: 1 stud = 0.28 m (Roblox's own guidance), so studs/s is almost km/h
-- (1 stud/s = 1.008 km/h).

local Config = {}

Config.StudMeters = 0.28
Config.KmhPerStudPerSecond = 0.28 * 3.6

Config.Kart = {
	-- The kart feels real-world gravity (9.81 m/s^2 = 35 studs/s^2). Roblox's
	-- default world gravity is much stronger, so the client cancels the
	-- difference on the kart only. Characters keep normal gravity.
	Gravity = 35,

	-- The chassis root is a compact invisible block that carries all the mass;
	-- its size sets the inertia, sized so yaw inertia per kilo matches a real
	-- kart with driver (a big box made the kart lazy to turn). A separate
	-- massless hitbox covers the whole kart for collisions.
	-- Forward is the chassis LookVector. Wheel positions are relative to the
	-- core centre (= centre of mass), which sits 0.3 studs behind the axle
	-- midpoint for a 42/58 front/rear split.
	CoreSize = { 2.8, 0.6, 4.0 }, -- x (width), y (height), z (length)
	BoxSize = { 6.6, 0.8, 6.75 }, -- collision hitbox (massless) round the wraparound bumpers
	BoxOffsetY = 0.15, -- hitbox centre above the core centre (keeps its floor off the kerbs)
	BoxOffsetZ = 0.375, -- hitbox centre ahead of the core (the front bumper reaches further)
	-- Slipstream (see KartPhysics): within Length studs behind another kart
	-- (centre to centre, fading out to Width studs sideways) drag drops by up
	-- to DragCut and the top speed rises by up to TopGain studs/s.
	Slipstream = {
		Gap = 7,
		Length = 34,
		Width = 4.5,
		MinSpeed = 40,
		DragCut = 0.45,
		TopGain = 5,
		Rise = 2.5,
		Fall = 4,
	},
	-- Kart-to-kart contact (see KartPhysics): the wraparound bumper as a
	-- rounded rectangle round the centre of mass. Overlap pushes back at
	-- Stiffness studs/s^2 per stud (at most SpringMax) plus Damping per stud/s
	-- of closing speed, at most MaxAccel in total; Friction is the rubbing
	-- grip between bumpers. Roblox's own collisions between karts are off:
	-- over the network they launch karts.
	Bumper = {
		HalfWidth = 3.3,
		Front = 3.75,
		Rear = 3.0,
		Corner = 0.7,
		Stiffness = 160,
		SpringMax = 160,
		Damping = 10,
		Friction = 0.25,
		MaxAccel = 500,
	},
	Density = 8,
	RideHeight = 0.62, -- core centre (centre of mass) above flat ground at rest; karts sit low
	-- Order matters: front pair then rear pair (anti-roll uses the pairs).
	-- grip: the wide rear slicks grip a little more than the narrow fronts.
	-- radius/width are what you see (the physics only uses the contact point).
	Wheels = {
		{ name = "FL", x = -2.15, f = 2.2, radius = 0.62, width = 0.66, front = true, grip = 1.0 },
		{ name = "FR", x = 2.15, f = 2.2, radius = 0.62, width = 0.66, front = true, grip = 1.0 },
		-- stiffness: the wide rear slicks build grip at smaller slip angles,
		-- which damps the kart's yaw (no overshoot on turn-in, no snap on release)
		{ name = "RL", x = -2.35, f = -1.6, radius = 0.7, width = 1.05, front = false, grip = 1.04, stiffness = 1.6 },
		{ name = "RR", x = 2.35, f = -1.6, radius = 0.7, width = 1.05, front = false, grip = 1.04, stiffness = 1.6 },
	},

	-- Suspension (real karts flex instead; a stiff spring stands in for it)
	SpringHz = 2.8, -- natural frequency of each corner
	DampingRatio = 0.45,
	Travel = 0.32, -- compression before the bump stop
	BumpStopRate = 6, -- bump stop stiffness as a multiple of the spring
	-- Anti-roll as a fraction of the spring rate. A stiffer front takes more of
	-- the load transfer, which keeps the inside rear planted (less snap oversteer).
	AntiRollFront = 0.35,
	AntiRollRear = 0.05,

	-- Tyres: simplified Pacejka "magic formula" on slip angle, combined with
	-- longitudinal force inside a friction circle.
	Mu = 2.0, -- peak friction on dry asphalt (sticky kart slicks pull ~2 g)
	LoadSensitivity = 0.15, -- grip per load falls as load rises
	-- Lateral grip curve: peaks at about 7 degrees of slip, then falls off
	-- (~84% at 20 degrees). Turning the wheels further than the peak makes the
	-- front push wide instead of turning more: understeer, as on a real kart.
	PacejkaB = 12.3,
	PacejkaC = 1.6,
	RollingResistance = 0.015, -- times normal load
	LowSpeedBlend = 4, -- studs/s; below this lateral grip uses a stick model

	-- Engine and brakes (accelerations, so the numbers do not depend on mass).
	-- Modelled on an outdoor rental kart: a single-cylinder 4-stroke of about
	-- 15 hp (Honda GX390 class) with one fixed gear, kart + driver about
	-- 250 kg. Out of a slow corner the pull is limited by engine torque through
	-- the gearing, about 0.24 g (26-30 Nm x ~3.1 / 0.14 m wheel); from about
	-- 60 km/h the engine's power is the limit (~10 kW at the wheels, so the
	-- pull falls as speed rises), and near the top air drag eats almost all of
	-- it. 0-50 km/h takes ~6.5 s and the last 10 km/h come slowly, so a
	-- better corner exit is still worth something at the end of a straight.
	-- (Before: 19 / 860, a ~23 hp kart that hit the governor on every straight.)
	DriveAccel = 8.5, -- torque-limited pull, studs/s^2 (~0.24 g, traction permitting)
	PowerPerMass = 520, -- constant power region: accel = PowerPerMass / speed (~41 W/kg)
	-- Off the throttle the kart coasts: about 0.17 g at 90 km/h (mostly air
	-- drag), 0.07 g at 50 km/h.
	EngineBraking = 0.9, -- decel from the engine when off the throttle
	TopSpeed = 100, -- soft governor (rev limit), studs/s; drag holds a lone kart to ~95, a tow lets it reach this
	DragCoef = 0.00055, -- aero drag accel = DragCoef * v^2
	BrakeAccel = 42, -- total braking demand at full brake (~1.3 g peak)
	BrakeRearBias = 0.25, -- fraction of braking on the rear axle (front brakes, like a KZ kart)
	ReverseAccel = 9,
	ReverseSpeed = 16,
	ReverseDelay = 0.3, -- hold brake while stopped this long to reverse

	-- Steering
	SteerLock = 28, -- degrees at the wheels
	-- How fast the front wheels can physically follow the command (degrees
	-- per second at the wheels, x3 at the steering wheel). The keyboard ramp
	-- in Config.Steering is what you normally feel; this only caps very
	-- quick counter-steer corrections.
	SteerRate = 240,
	SteerReturnRate = 300,
	Ackermann = 1.0, -- 0 = parallel steer, 1 = full Ackermann
	-- Steering assist (on by default, for keyboard/touch): at speed the input
	-- sets the front slip angle relative to the direction of travel, so the
	-- wheels counter-steer by themselves when the rear slides. Physics unchanged.
	SteerAssist = true,
	-- Slide catching: when the rear tyres slip past their peak, the assist
	-- eases the front back towards counter-steer even if the key is held
	-- (per radian of excess rear slip; 0 = off).
	AssistCatch = 1.5,
	SteerAssistSlip = 8, -- front slip angle at full input, degrees (just past the tyre's peak)

	-- Steering wheel (drawn by each client): centre height and forward position,
	-- tilt of its face from vertical, rim radius, wheel turns per road-wheel turn
	SteeringWheel = { Height = 2.0, Forward = 0.75, Tilt = 45, Radius = 0.62, Ratio = 3 },

	-- Recovery
	FlipResetTime = 2.0, -- upside down for this long -> automatic reset
	FallY = -60,
}

-- Keyboard / touch pedals: how fast the throttle and brake reach full when
-- the key is pressed (per second). Analog triggers are used as they are.
-- A brake that bites in over a quarter second is easier to dose with a key.
Config.Pedals = {
	ThrottleRise = 7,
	BrakeRise = 4,
}

-- Steering input smoothing (see SteerFilter). Keys and touch buttons ramp
-- the steering in; the ramp gets slower with speed, like a keyboard in a
-- racing game. Rates are in "full lock per second".
Config.Steering = {
	RiseLow = 6.5, -- 0 -> full in ~0.2 s at parking speed
	RiseHigh = 3.2, -- ... ~0.33 s at RiseSpeed and above
	ReturnLow = 8,
	ReturnHigh = 4.5,
	Counter = 10, -- through centre when switching left <-> right
	RiseSpeed = 70, -- studs/s (about 70 km/h)
	Smoothing = 20,
	StickRate = 8, -- gamepad stick: light rate limit only
	StickCurve = 1.25,
}

-- Other karts reach this client late (their driver -> server -> here), so
-- they are moved ahead along their velocity before bumping into them:
-- Lead seconds plus PingShare of both players' round-trip ping, at most
-- LeadMax. Only karts within Range studs are checked (bumpers and slipstream).
Config.Collision = {
	Range = 40, -- also how far ahead the slipstream looks
	Lead = 0.05,
	PingShare = 0.5,
	LeadMax = 0.25,
}

-- Surface grip. Parts carry a "Surface" attribute naming an entry here
-- (falls back to the material name). `grip` scales Mu, `roll` scales rolling
-- resistance (grass and gravel slow you down hard).
Config.Surfaces = {
	Asphalt = { grip = 1.0, roll = 1 }, -- the racing surface
	Kerb = { grip = 0.9, roll = 1.3 },
	RunOff = { grip = 0.8, roll = 2.5 }, -- painted asphalt run-off
	PitLane = { grip = 0.95, roll = 1 },
	Concrete = { grip = 0.9, roll = 1.2 },
	Turf = { grip = 0.55, roll = 6 }, -- artificial-turf verge
	Grass = { grip = 0.35, roll = 14 },
	Gravel = { grip = 0.4, roll = 30 }, -- gravel trap
	Water = { grip = 0.3, roll = 45 }, -- the lake (a kart wades out at a crawl)
	Default = { grip = 0.8, roll = 2 },
}

Config.Race = {
	MinPlayers = 2, -- fewer than this -> free practice
	MaxRacers = 12,
	IntermissionTime = 20, -- track and length vote; READY from everyone cuts it short
	ReadyCountdown = 3, -- seconds left once everyone is ready
	QualifyingTime = 120, -- default; tracks set their own (TrackData Qualifying)
	QualiOvertime = 90, -- at most this long to finish the lap after the flag
	-- Qualifying is one timed lap with ghosts (user's choice): everyone starts
	-- together this far before the line, picks up speed, and the lap is timed
	-- from the line round to the line. Karts pass through each other (no
	-- bumpers, no slipstream) and the others are see-through.
	QualiRunUp = 70, -- studs
	GhostTransparency = 0.6,
	CountdownTime = 5, -- five red lights, one per second
	FinishGrace = 30, -- after the winner finishes, others get this long
	MaxRaceTime = 600,
	ResultsTime = 8, -- podium, then straight on to the next round
	-- Track limits (all four tyres beyond the kerb): practice and qualifying
	-- strike the lap off; in the race the first TrackLimitWarnings are
	-- warnings, then each one adds TrackLimitPenalty seconds to the result.
	TrackLimitWarnings = 3,
	TrackLimitPenalty = 2,
	GridRowSpacing = 14,
	GridLateral = 8,
	GridStagger = 7,
	GridFirstRowBack = 12, -- studs behind the start line
	ResetCooldown = 3,
	TrackChangeCooldown = 3, -- practice: seconds between track changes
	TrackLoadTime = 3, -- seconds before practice karts return after a track change
	OffTrackAllowance = 60, -- studs beyond the road edge that still count as on course
}

-- The lobby, quick races and private rooms. Every public server is a lobby
-- (the menu over a slow fly-by of a circuit); PRACTICE, RACE and PRIVATE ROOM
-- send players to reserved servers of the same place. In Studio teleports do
-- not work, so the one server switches to the chosen mode in place.
Config.Lobby = {
	QueueMin = 2, -- a quick race needs this many drivers...
	QueueWait = 7, -- ...and starts this many seconds after the QueueMin-th one joined
	QueueMax = 12, -- this many waiting: straight away (Config.Race.MaxRacers)
	QueuePoll = 1.5, -- seconds between reads of the shared queue (each lobby server)
	TicketTtl = 45, -- a ticket left by a server that went away expires after this
	RoomDigits = 4,
	RoomTtl = 6 * 3600,
	RoomRefresh = 600, -- the room server renews its code this often
	ServerTtl = 2 * 3600, -- how long a reserved server's role is kept for it to read
	StudioSolo = true, -- Studio only: a quick race starts with one driver
	FlybySpeed = 24, -- the lobby camera, studs per second along the track
	FlybyHeight = 16,
	FlybySide = 26,
	TeleportDelay = 0.4, -- seconds between "teleporting" on the client and the teleport
	LobbyConfirm = 3, -- the LOBBY button asks to be pressed again within this
	KickConfirm = 3, -- the room's KICK asks to be pressed again within this
	RoomTrackCooldown = 1, -- the waiting room: seconds between the host's track changes
}

-- Player settings (the SETTINGS menu), saved with each player's data. Each
-- item: label, default, and either a numeric range (min, max, step; shown as
-- a percentage when `percent`) or a list of options; true/false otherwise.
Config.Settings = {
	Order = { "MasterVolume", "EngineVolume", "EffectsVolume", "SteerSpeed", "SteerAssist", "Camera", "Units", "Minimap", "Delta" },
	Items = {
		MasterVolume = { label = "Master volume", default = 1, min = 0, max = 1, step = 0.1, percent = true },
		EngineVolume = { label = "Engine volume", default = 0.8, min = 0, max = 1, step = 0.1, percent = true },
		EffectsVolume = { label = "Effects volume", default = 0.8, min = 0, max = 1, step = 0.1, percent = true },
		SteerSpeed = { label = "Steering speed (keys)", default = 1, min = 0.6, max = 1.6, step = 0.1, percent = true },
		SteerAssist = { label = "Steering assist", default = true },
		Camera = { label = "Starting camera", default = "Near", options = { "Cockpit", "Near", "Far" } },
		Units = { label = "Speed units", default = "KMH", options = { "KMH", "MPH" } },
		Minimap = { label = "Minimap", default = "Normal", options = { "Off", "Small", "Normal", "Large" } },
		Delta = { label = "Live lap delta", default = true },
	} :: { [string]: any },
}

-- Sounds: audio asset ids ("rbxassetid://123..."). The sounds/ folder of the
-- project has the original set made for this game; these ids are the user's
-- uploads of it (Oct 2026). A new upload gets a new id: paste it here. An
-- empty id is silent. Loops: the engine (pitched from the engine rpm), the
-- skid (fades with tyre slip), off-track (gravel / grass / water) and kerbs
-- (both fade in with speed); the crowd loops at every grandstand. One-shots:
-- bump = kart contact, beep = each start light, go = lights out, lap = a lap
-- completed, best = personal best / fastest lap / track record, warning =
-- track-limits warning, penalty = lap deleted or a time penalty, flag =
-- qualifying starts / chequered flag, finish = your chequered flag in the
-- race, podium = the results, click = buttons. Volumes are scaled by the
-- player's settings.
-- Volumes were set with a mix simulation (sounds/mix_levels.py: Roblox's volume
-- model, inverse roll-off from the chase camera, phone / laptop / headphone
-- speakers, A-weighting): the engine at full throttle is the loudest steady
-- sound, the slide ~6 dB under it, kerbs and gravel ~4-5 dB under, a nearby
-- grandstand ~15 dB under, the race chimes 0-3 dB over. Before that, on a
-- phone the tyres were 22 dB and the crowd 19 dB louder than the engine.
Config.Audio = {
	EngineSoundId = "rbxassetid://91449674300903",
	EngineVolume = 1.1,
	-- the engine loop (sounds/engine_loop.ogg) is recorded at EngineRpmLoop.
	-- A rental kart: idles, the centrifugal clutch slips at EngineRpmClutch
	-- until the kart is fast enough, then the revs follow the road speed (one
	-- gear) up to EngineRpmMax at top speed. Off the throttle the clutch
	-- holds (engine braking) until the road speed is below EngineRpmRelease.
	EngineRpmLoop = 3000,
	EngineRpmIdle = 1600,
	EngineRpmClutch = 2600,
	EngineRpmRelease = 2000,
	EngineRpmMax = 4200,
	SkidSoundId = "rbxassetid://117100105483453",
	SkidVolume = 0.31,
	OffroadSoundId = "rbxassetid://83887645728236",
	OffroadVolume = 0.52,
	KerbSoundId = "rbxassetid://89095407744124",
	KerbVolume = 0.63,
	BumpSoundId = "rbxassetid://96414496985286",
	BumpVolume = 1.15,
	BeepSoundId = "rbxassetid://106467681472548",
	BeepVolume = 0.22,
	GoSoundId = "rbxassetid://115374666219082",
	GoVolume = 0.31,
	LapSoundId = "rbxassetid://103923634271916",
	LapVolume = 0.3,
	BestSoundId = "rbxassetid://79479200280451",
	BestVolume = 0.54,
	WarningSoundId = "rbxassetid://108778334873385",
	WarningVolume = 0.3,
	PenaltySoundId = "rbxassetid://139070978914964",
	PenaltyVolume = 0.66,
	FlagSoundId = "rbxassetid://80495713260197",
	FlagVolume = 0.27,
	FinishSoundId = "rbxassetid://74463771278347",
	FinishVolume = 0.31,
	PodiumSoundId = "rbxassetid://108771531659515",
	PodiumVolume = 0.71,
	ClickSoundId = "rbxassetid://79417620837900",
	ClickVolume = 1.16,
	CrowdSoundId = "rbxassetid://77498018095928",
	CrowdVolume = 0.33,
	CrowdRollOffMin = 20, -- studs from a grandstand roof at which the crowd is at full volume
}

-- Driving camera. Mouse wheel / pinch / D-pad zoom from far behind the kart
-- all the way into the cockpit (first person); C cycles the presets.
-- Behind the kart, right-drag (or the right stick / a finger drag) swings the
-- camera around the kart and it stays where you put it; V (or R3) puts it
-- back behind. In the cockpit the same controls look around and the view
-- recentres when you let go.
Config.Camera = {
	Distance = 13, -- default chase distance (studs)
	MinDistance = 6, -- zooming in past this switches to the cockpit view
	MaxDistance = 40,
	ZoomStep = 1.18, -- factor per mouse-wheel notch
	ZoomSpeed = 12, -- how fast the camera follows a zoom change
	HeightBase = 1.3, -- chase camera height above the kart = HeightBase + HeightPerStud * distance
	HeightPerStud = 0.24,
	LookAhead = 6,
	FovMin = 70,
	FovMax = 86,
	Stiffness = 9, -- how fast the chase camera swings behind the kart
	FreeLookSensitivity = 0.25, -- degrees per pixel of mouse movement
	TouchSensitivity = 0.35, -- degrees per pixel of finger movement
	StickOrbitSpeed = 160, -- degrees per second at full right stick (behind the kart)
	OrbitPitchMin = -8, -- degrees, camera elevation limits behind the kart
	OrbitPitchMax = 80,
	AutoRecenter = 0, -- seconds of driving before an orbited camera returns behind (0 = never)
	FreeLookReturn = 7, -- how fast the view recentres (cockpit look, V / R3 reset)
	Presets = { 0, 13, 22 }, -- C cycles these (0 = cockpit)
	Cockpit = {
		Eye = { 0, 3.25, -0.2 }, -- x, height above ground, forward, in the kart's frame
		Pitch = -9, -- degrees, looking slightly down the road
		Fov = 72,
		FovSpeedGain = 6, -- extra degrees at top speed
		-- Motion, all eased with critically damped springs (no bounce-back):
		HeadG = 0.045, -- studs the head sways sideways per g of cornering
		HeadGForward = 0.06, -- studs forward per g of braking
		HeadMax = 0.14,
		HeadResponse = 7, -- 1/s
		AccelFilter = 5, -- 1/s, smooths the measured g-forces
		TiltFollow = 0.3, -- share of the kart's roll/pitch you see (0 = horizon locked)
		TiltResponse = 10, -- 1/s
		LookIntoTurn = 0, -- degrees of glance per degree/s of yaw rate ("look to apex"; 0.1 is subtle). Off: it swings the view back when you straighten up
		MaxLookIntoTurn = 6,
		LookResponse = 5, -- 1/s
		Shoulders = { 0.9, 2.55, -0.55 }, -- +-x, height, forward (for the cockpit arms)
	},
}

return Config
