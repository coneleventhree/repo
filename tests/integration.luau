-- 실제 서버/클라이언트 스크립트를 가짜 Roblox 런타임(RobloxShim)에서 실행하는 통합 테스트.
-- 서버 1개 + 클라이언트 2개를 네트워크 지연(50ms)과 스냅샷 손실(5%)을 둔 채 연결하고
-- 메뉴 → AI 대결 → 온라인 매칭 → 경기 종료 → 기권 → 접속 종료까지 버튼 클릭과 키 입력으로 진행한다.
-- 실행: lune run tests/integration
local process = require("@lune/process")
local Shim = require("./RobloxShim")

local Enum = Shim.Enum
local FRAME = 1 / 60
local LATENCY = 0.05
local SNAPSHOT_DROP = 0.05

local now = 0
local function clock(): number
	return now
end

local seed = 12345
local function random(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local failures = 0
local function check(condition: any, message: string)
	if condition then
		print("  ok   " .. message)
	else
		failures += 1
		print("  FAIL " .. message)
	end
end

-- 네트워크 ------------------------------------------------------------------

local deliveries = {}
local sequence = 0
local function deliver(fn: () -> ())
	sequence += 1
	table.insert(deliveries, { at = now + LATENCY, sequence = sequence, fn = fn })
end
local function flushNetwork()
	table.sort(deliveries, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.sequence < b.sequence
	end)
	while deliveries[1] and deliveries[1].at <= now do
		table.remove(deliveries, 1).fn()
	end
end

local server = Shim.newWorld(clock)
Shim.startServer(server)
local serverRemotes = server.game:GetService("ReplicatedStorage"):FindFirstChild("BadmintonRemotes")
assert(serverRemotes, "server did not create the remotes folder")

local clientByServerPlayer = {}
local clients = {}

for _, remote in serverRemotes:GetChildren() do
	Shim.setInternal(remote, "__fireClient", function(player, ...)
		local client = clientByServerPlayer[player]
		if not client or client.left then
			return
		end
		if remote.ClassName == "UnreliableRemoteEvent" and random() < SNAPSHOT_DROP then
			return
		end
		local args = Shim.deepCopy(table.pack(...))
		deliver(function()
			client.remotes[remote.Name].OnClientEvent:Fire(table.unpack(args, 1, args.n))
		end)
	end)
end

local function addClient(userId: number, name: string)
	local serverPlayer = Shim.newInstance("Player")
	serverPlayer.Name = name
	serverPlayer.DisplayName = name
	serverPlayer.UserId = userId
	serverPlayer.Parent = server.game:GetService("Players")

	local world = Shim.newWorld(clock)
	local folder = Shim.newInstance("Folder")
	folder.Name = serverRemotes.Name
	for _, remote in serverRemotes:GetChildren() do
		local replica = Shim.newInstance(remote.ClassName)
		replica.Name = remote.Name
		replica.Parent = folder
		Shim.setInternal(replica, "__fireServer", function(...)
			local args = Shim.deepCopy(table.pack(...))
			deliver(function()
				remote.OnServerEvent:Fire(serverPlayer, table.unpack(args, 1, args.n))
			end)
		end)
	end
	folder.Parent = world.game:GetService("ReplicatedStorage")

	local client = { name = name, world = world, remotes = folder, serverPlayer = serverPlayer, left = false }
	clientByServerPlayer[serverPlayer] = client
	table.insert(clients, client)
	client.player = Shim.startClient(world, userId, name)
	return client
end

local function step(frames: number, each: (() -> ())?)
	for _ = 1, frames do
		now += FRAME
		flushNetwork()
		if each then
			each()
		end
		server.game:GetService("RunService").Heartbeat:Fire(FRAME)
		for _, client in clients do
			if not client.left then
				client.world.game:GetService("RunService").RenderStepped:Fire(FRAME)
			end
		end
	end
end

-- UI 헬퍼 -------------------------------------------------------------------

local function gui(client)
	return client.player:FindFirstChild("PlayerGui")
end

local function isVisible(instance): boolean
	local node = instance
	while node and node.ClassName ~= "PlayerGui" do
		if node.Visible == false or node.Enabled == false then
			return false
		end
		node = node.Parent
	end
	return node ~= nil
end

local function find(client, predicate: (any) -> boolean)
	for _, d in gui(client):GetDescendants() do
		if predicate(d) then
			return d
		end
	end
	return nil
end

local function panelVisible(client, name: string): boolean
	local panel = find(client, function(d)
		return d.Name == name and d.ClassName == "Frame"
	end)
	return panel ~= nil and isVisible(panel)
end

local function click(client, text: string)
	local button = find(client, function(d)
		return d.ClassName == "TextButton" and d.Text == text and isVisible(d)
	end)
	if not button then
		error(client.name .. " has no visible button '" .. text .. "'", 2)
	end
	button.Activated:Fire()
end

local function resultTitle(client): string?
	local result = find(client, function(d)
		return d.Name == "Result" and d.ClassName == "Frame"
	end)
	if not result or not isVisible(result) then
		return nil
	end
	for _, d in result:GetDescendants() do
		if d.ClassName == "TextLabel" and (d.Text == "승리!" or d.Text == "패배") then
			return d.Text
		end
	end
	return nil
end

local function resultText(client): string
	local texts = {}
	local result = find(client, function(d)
		return d.Name == "Result" and d.ClassName == "Frame"
	end)
	for _, d in result:GetDescendants() do
		if d.ClassName == "TextLabel" then
			table.insert(texts, d.Text)
		end
	end
	return table.concat(texts, " | ")
end

local function nameTagX(client, text: string): number?
	local arena = gui(client):FindFirstChild("BadmintonArena")
	for _, d in arena:GetDescendants() do
		if d.ClassName == "TextLabel" and d.Text == text then
			return d.Position.X.Scale
		end
	end
	return nil
end

local function key(client, name: string, down: boolean)
	local uis = client.world.game:GetService("UserInputService")
	local input = { KeyCode = Enum.KeyCode[name], UserInputType = Enum.UserInputType.Keyboard }
	if down then
		uis.InputBegan:Fire(input, false)
	else
		uis.InputEnded:Fire(input, false)
	end
end

-- 아무렇게나 누르는 플레이어
local function masher(...)
	local players = { ... }
	return function()
		for _, client in players do
			if random() < 0.03 then
				key(client, "A", false)
				key(client, "D", false)
				local r = random()
				if r < 0.4 then
					key(client, "A", true)
				elseif r < 0.8 then
					key(client, "D", true)
				end
			end
			if random() < 0.06 then
				key(client, "J", true)
				key(client, "J", false)
			end
			if random() < 0.02 then
				key(client, "K", true)
				key(client, "K", false)
			end
			if random() < 0.01 then
				key(client, "Space", true)
			elseif random() < 0.05 then
				key(client, "Space", false)
			end
		end
	end
end

local function runUntil(maxSeconds: number, condition: () -> boolean, each: (() -> ())?): boolean
	local frames = 0
	while frames < maxSeconds / FRAME do
		if condition() then
			return true
		end
		step(1, each)
		frames += 1
	end
	return condition()
end

-- 시나리오 ------------------------------------------------------------------

print("Startup")
local alice = addClient(101, "Alice")
local bob = addClient(102, "Bob")
step(600)
check(
	gui(alice):FindFirstChild("BadmintonArena") and gui(alice):FindFirstChild("BadmintonUI"),
	"client builds the arena and UI"
)
check(panelVisible(alice, "Menu") and panelVisible(bob, "Menu"), "menu is shown with a demo match behind it")
check(server.game:GetService("Players").CharacterAutoLoads == false, "server disables 3D characters")

print("AI match")
click(alice, "보통")
step(5)
check(not panelVisible(alice, "Menu") and panelVisible(alice, "Hud"), "AI match starts and shows the HUD")
local finished = runUntil(20 * 60, function()
	return resultTitle(alice) ~= nil
end, masher(alice))
check(finished, "AI match reaches the result screen")
print("       result: " .. resultText(alice))
click(alice, "다시 하기")
step(30)
check(panelVisible(alice, "Hud") and not panelVisible(alice, "Result"), "rematch starts a new AI match")
click(alice, "메뉴로")
step(5)
check(panelVisible(alice, "Menu"), "menu button returns to the menu")

print("Online match")
click(alice, "온라인 1:1")
step(10)
check(panelVisible(alice, "Queue"), "first player waits in the queue")
click(bob, "온라인 1:1")
step(30)
check(panelVisible(alice, "Hud") and panelVisible(bob, "Hud"), "two queued players are matched")
local aliceX, bobX = nameTagX(alice, "Alice"), nameTagX(bob, "Bob")
check(aliceX and aliceX < 0.5, "Alice sees herself on the left")
check(bobX and bobX < 0.5, "Bob (right side on the server) also sees himself on the left")
local done = runUntil(30 * 60, function()
	return resultTitle(alice) ~= nil and resultTitle(bob) ~= nil
end, masher(alice, bob))
check(done, "online match finishes on both clients")
local a, b = resultTitle(alice), resultTitle(bob)
check(a ~= b and (a == "승리!" or b == "승리!"), "exactly one player wins")
print("       Alice: " .. resultText(alice))
print("       Bob:   " .. resultText(bob))
step(5 * 60)

print("Rematch and forfeit")
click(alice, "다시 매칭")
click(bob, "다시 매칭")
step(30)
check(panelVisible(alice, "Hud") and panelVisible(bob, "Hud"), "players can queue again after a match")
step(120, masher(alice, bob))
click(bob, "기권")
step(30)
check(panelVisible(bob, "Menu"), "forfeiting player returns to the menu")
check(
	resultTitle(alice) == "승리!" and resultText(alice):find("상대가 나갔습니다") ~= nil,
	"opponent wins by forfeit"
)

print("Disconnect")
click(alice, "메뉴로")
click(alice, "온라인 1:1")
click(bob, "온라인 1:1")
step(30)
check(panelVisible(alice, "Hud"), "matched again")
bob.left = true
server.game:GetService("Players").PlayerRemoving:Fire(bob.serverPlayer)
bob.serverPlayer.Parent = nil
step(30)
check(resultTitle(alice) == "승리!", "remaining player wins when the opponent leaves")

print("Queue cancel")
click(alice, "메뉴로")
click(alice, "온라인 1:1")
step(10)
click(alice, "취소")
step(30)
check(panelVisible(alice, "Menu"), "cancelling the queue returns to the menu")
local carol = addClient(103, "Carol")
step(10)
click(carol, "온라인 1:1")
step(60)
check(panelVisible(carol, "Queue"), "a cancelled player is no longer matched")

for _, client in clients do
	for _, warning in client.world.warnings do
		check(false, client.name .. " warned: " .. warning)
	end
end
for _, warning in server.warnings do
	check(false, "server warned: " .. warning)
end

print(string.format("\nsimulated %.0f seconds, %d failures", now, failures))
if failures > 0 then
	process.exit(1)
end
