-- Boots the real game scripts inside the mock Roblox runtime.
local Roblox = require("../mock/roblox")
local chunks = require("../mock/gen/index")

local Game = {}

local function module(name: string, key: string)
	return { name = name, class = "ModuleScript", source = key }
end

Game.SharedSpec = {
	name = "Shared",
	class = "Folder",
	children = {
		module("Config", "src_shared_Config_luau"),
		module("TrackMath", "src_shared_TrackMath_luau"),
		module("TrackData", "src_shared_TrackData_luau"),
		module("TrackLayout", "src_shared_TrackLayout_luau"),
		module("KartPhysics", "src_shared_KartPhysics_luau"),
		module("RaceProgress", "src_shared_RaceProgress_luau"),
		module("SteerFilter", "src_shared_SteerFilter_luau"),
		module("CockpitRig", "src_shared_CockpitRig_luau"),
		module("TrackLimits", "src_shared_TrackLimits_luau"),
	},
}

Game.ServerSpec = {
	name = "Server",
	class = "Script",
	source = "src_server_init_server_luau",
	children = {
		module("Build", "src_server_Build_luau"),
		module("TrackBuilder", "src_server_TrackBuilder_luau"),
		module("Scenery", "src_server_Scenery_luau"),
		module("KartFactory", "src_server_KartFactory_luau"),
		module("RaceManager", "src_server_RaceManager_luau"),
		module("Stats", "src_server_Stats_luau"),
		module("Session", "src_server_Session_luau"),
		module("SharedStore", "src_server_SharedStore_luau"),
		module("Matchmaker", "src_server_Matchmaker_luau"),
		module("Rooms", "src_server_Rooms_luau"),
		module("Lobby", "src_server_Lobby_luau"),
	},
}

Game.ClientSpec = {
	name = "Client",
	class = "LocalScript",
	source = "src_client_init_client_luau",
	children = {
		module("Settings", "src_client_Settings_luau"),
		module("Sfx", "src_client_Sfx_luau"),
		module("SettingsMenu", "src_client_SettingsMenu_luau"),
		module("Input", "src_client_Input_luau"),
		module("KartController", "src_client_KartController_luau"),
		module("KartVisuals", "src_client_KartVisuals_luau"),
		module("ChaseCamera", "src_client_ChaseCamera_luau"),
		module("Hud", "src_client_Hud_luau"),
		module("Menu", "src_client_Menu_luau"),
		module("TrackLoader", "src_client_TrackLoader_luau"),
		module("TrackOutline", "src_client_TrackOutline_luau"),
	},
}

-- ReplicatedFirst.Loading: the loading screen
Game.FirstSpec = {
	name = "Loading",
	class = "LocalScript",
	source = "src_first_init_client_luau",
	children = {
		module("LoadingGui", "src_first_LoadingGui_luau"),
	},
}

-- Builds the world and runs the server until the circuit is ready.
-- opts.reserved = { mode = ..., track = ... }: the server is a reserved one
-- made for that (its role waits in the MemoryStore map, as the lobby leaves
-- it); otherwise it is a public server, i.e. a lobby. opts.studio = false:
-- behave like a published game (teleports) instead of Studio.
function Game.boot(opts: { [string]: any }?)
	local o = opts or {}
	o.chunks = chunks
	if o.reserved then
		o.privateServerId = o.privateServerId or "psid-test"
	end
	local G = Roblox.new(o)
	if o.reserved then
		G.memMap("A1Servers")
		G.memory.A1Servers[o.privateServerId] = { value = o.reserved, expires = math.huge }
	end
	local rs = G.game:GetService("ReplicatedStorage")
	G.shared = G.mount(rs, Game.SharedSpec)
	G.first = G.mount(G.game:GetService("ReplicatedFirst"), Game.FirstSpec)
	local sss = G.game:GetService("ServerScriptService")
	G.serverScript = G.mount(sss, Game.ServerSpec)
	G.runScript(G.serverCtx, G.serverScript)
	if o.wait == false then
		-- (a reserved server waiting for its first player to say what it is)
		return G
	end
	local ok = G.run(120, function()
		return G.workspace:GetAttribute("TrackReady") == true
	end)
	assert(ok, "server never set TrackReady")
	local circuit = G.workspace:FindFirstChild("Circuit")
	G.groundFilter = { circuit:FindFirstChild("Track") }
	return G
end

-- Runs the loading screen (ReplicatedFirst) in a player's client context.
function Game.startLoading(G, ctx)
	G.runScript(ctx, G.first)
end

-- A client-side require for a player's context (modules are cached per context).
function Game.clientModule(G, ctx, name: string)
	local ps = ctx.player:FindFirstChild("PlayerScripts")
	local client = ps:FindFirstChild("Client")
	return ctx.require(client:FindFirstChild(name))
end

function Game.sharedModule(G, ctx, name: string)
	ctx.require = ctx.require or G.makeRequire(ctx)
	return ctx.require(G.shared:FindFirstChild(name))
end

return Game
