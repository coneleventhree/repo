-- Headless stand-in for the Roblox world used by the tests:
--   * a ground made of the real road triangles plus a flat grass plane
--   * a rigid-body integrator for the kart chassis box (240 Hz, like Roblox)
-- The kart model (KartPhysics) runs once per 60 Hz frame and its force and
-- torque are held for the substeps, which is what VectorForce/Torque do.

local TrackMath = require("../../src/shared/TrackMath")
local TrackLayout = require("../../src/shared/TrackLayout")

local World = {}

export type Tri = { a: vector, b: vector, c: vector, n: vector, grip: number, roll: number }

----------------------------------------------------------------------------
-- Ground
----------------------------------------------------------------------------
local CELL = 16

local Ground = {}
Ground.__index = Ground

function World.newGround(planeY: number, planeGrip: number?, planeRoll: number?)
	return setmetatable({
		tris = {} :: { Tri },
		grid = {} :: { [number]: { number } },
		planeY = planeY,
		planeGrip = planeGrip or 0.5,
		planeRoll = planeRoll or 7,
	}, Ground)
end

local function key(cx: number, cz: number): number
	return (cx + 4096) * 8192 + (cz + 4096)
end

function Ground:addTri(a: vector, b: vector, c: vector, grip: number, roll: number)
	local n = vector.normalize(vector.cross(b - a, c - a))
	if n.y < 0 then
		n = -n
	end
	table.insert(self.tris, { a = a, b = b, c = c, n = n, grip = grip, roll = roll })
	local id = #self.tris
	local minX = math.floor(math.min(a.x, b.x, c.x) / CELL)
	local maxX = math.floor(math.max(a.x, b.x, c.x) / CELL)
	local minZ = math.floor(math.min(a.z, b.z, c.z) / CELL)
	local maxZ = math.floor(math.max(a.z, b.z, c.z) / CELL)
	for cx = minX, maxX do
		for cz = minZ, maxZ do
			local k = key(cx, cz)
			local list = self.grid[k]
			if not list then
				list = {}
				self.grid[k] = list
			end
			table.insert(list, id)
		end
	end
end

-- Adds the road surface of a built track (same triangulation as the game).
-- `bands` (studs): also a level verge that far out from both edges, at the
-- edge's height like the game's turf / run-off (matters on a raised road).
function Ground:addTrack(track: TrackMath.Track, grip: number?, roll: number?, bands: number?)
	local n = track.n
	for i = 1, n do
		local s0 = track.samples[i]
		local s1 = track.samples[TrackMath.wrap(i + 1, n)]
		local l0, r0 = TrackMath.edges(s0)
		local l1, r1 = TrackMath.edges(s1)
		-- the same pieces as the game's road (twisted quads split, TrackLayout)
		local across, along = TrackLayout.roadSplit(track, i)
		if self.plainRoad then
			across, along = 1, 1
		end
		for _, t in TrackLayout.roadTriangles(track, i, across, along) do
			self:addTri(t[1], t[2], t[3], grip or 1, roll or 1)
		end
		if bands then
			local function out(s, e, side)
				local f = vector.normalize(vector.create(s.right.x, 0, s.right.z)) * side
				return e + f * bands
			end
			local lo0, lo1 = out(s0, l0, -1), out(s1, l1, -1)
			local ro0, ro1 = out(s0, r0, 1), out(s1, r1, 1)
			local g, r = 0.75, 4
			self:addTri(lo0, l0, l1, g, r)
			self:addTri(lo0, l1, lo1, g, r)
			self:addTri(r0, ro0, ro1, g, r)
			self:addTri(r0, ro1, r1, g, r)
		end
	end
end

-- Moller-Trumbore. Returns distance along the unit direction or nil.
local function rayTri(o: vector, d: vector, t: Tri): number?
	local e1 = t.b - t.a
	local e2 = t.c - t.a
	local p = vector.cross(d, e2)
	local det = vector.dot(e1, p)
	if math.abs(det) < 1e-9 then
		return nil
	end
	local inv = 1 / det
	local s = o - t.a
	local u = vector.dot(s, p) * inv
	if u < -1e-6 or u > 1 + 1e-6 then
		return nil
	end
	local q = vector.cross(s, e1)
	local v = vector.dot(d, q) * inv
	if v < -1e-6 or u + v > 1 + 1e-6 then
		return nil
	end
	local dist = vector.dot(e2, q) * inv
	if dist < 0 then
		return nil
	end
	return dist
end

-- Same contract as the Roblox adapter: returns a KartPhysics.Hit or nil.
function Ground:raycast(origin: vector, dir: vector)
	local len = vector.magnitude(dir)
	local d = dir / len
	local best, bestTri = math.huge, nil
	-- the rays are short and nearly vertical: check the cells around both ends
	local seen = {}
	for _, pnt in { origin, origin + dir } do
		local cx, cz = math.floor(pnt.x / CELL), math.floor(pnt.z / CELL)
		local list = self.grid[key(cx, cz)]
		if list then
			for _, id in list do
				if not seen[id] then
					seen[id] = true
					local t = self.tris[id]
					local dist = rayTri(origin, d, t)
					if dist and dist <= len and dist < best then
						best, bestTri = dist, t
					end
				end
			end
		end
	end
	-- grass plane
	if d.y < -1e-6 then
		local dist = (self.planeY - origin.y) / d.y
		if dist >= 0 and dist <= len and dist < best then
			return { dist = dist, normal = vector.create(0, 1, 0), grip = self.planeGrip, roll = self.planeRoll }
		end
	end
	if bestTri then
		return { dist = best, normal = bestTri.n, grip = bestTri.grip, roll = bestTri.roll }
	end
	return nil
end

-- Height of the ground under (x, z) looking down from `fromY`.
function Ground:heightAt(x: number, z: number, fromY: number): number
	local h = self:raycast(vector.create(x, fromY, z), vector.create(0, -400, 0))
	if h then
		return fromY - h.dist
	end
	return -math.huge
end

----------------------------------------------------------------------------
-- Rigid body (the chassis box)
----------------------------------------------------------------------------
local Body = {}
Body.__index = Body

local function rotate(v: vector, axis: vector, angle: number): vector
	-- Rodrigues
	local c, s = math.cos(angle), math.sin(angle)
	return v * c + vector.cross(axis, v) * s + axis * (vector.dot(axis, v) * (1 - c))
end

-- `size` is the massive core (mass and inertia), `hitSize` the collision box.
function World.newBody(size: { number }, density: number, pos: vector, look: vector, hitSize: { number }?, hitOffsetY: number?, hitOffsetZ: number?)
	local sx, sy, sz = size[1], size[2], size[3]
	local mass = sx * sy * sz * density
	look = vector.normalize(look)
	local right = vector.normalize(vector.cross(look, vector.create(0, 1, 0)))
	local up = vector.cross(right, look)
	return setmetatable({
		size = hitSize or size,
		hitOffsetY = hitOffsetY or 0,
		hitOffsetZ = hitOffsetZ or 0,
		mass = mass,
		-- principal inertia in local axes (x right, y up, z length)
		ix = mass * (sy * sy + sz * sz) / 12,
		iy = mass * (sx * sx + sz * sz) / 12,
		iz = mass * (sx * sx + sy * sy) / 12,
		pos = pos,
		vel = vector.zero,
		angVel = vector.zero,
		right = right,
		up = up,
		look = look,
		bottomHits = 0,
	}, Body)
end

function Body:snapshot()
	return {
		pos = self.pos,
		com = self.pos,
		right = self.right,
		up = self.up,
		look = self.look,
		vel = self.vel,
		angVel = self.angVel,
		mass = self.mass,
	}
end

-- Integrates one substep with a constant external force/torque plus gravity.
function Body:integrate(force: vector, torque: vector, gravity: number, dt: number)
	local acc = force / self.mass + vector.create(0, -gravity, 0)
	self.vel += acc * dt
	-- angular: work in local principal axes (local z = -look)
	local back = -self.look
	local w = self.angVel
	local wl = vector.create(vector.dot(w, self.right), vector.dot(w, self.up), vector.dot(w, back))
	local tl = vector.create(vector.dot(torque, self.right), vector.dot(torque, self.up), vector.dot(torque, back))
	local Iw = vector.create(self.ix * wl.x, self.iy * wl.y, self.iz * wl.z)
	local gyro = vector.cross(wl, Iw)
	local al = vector.create((tl.x - gyro.x) / self.ix, (tl.y - gyro.y) / self.iy, (tl.z - gyro.z) / self.iz)
	wl += al * dt
	self.angVel = self.right * wl.x + self.up * wl.y + back * wl.z
	self.pos += self.vel * dt
	local wmag = vector.magnitude(self.angVel)
	if wmag > 1e-9 then
		local axis = self.angVel / wmag
		local ang = wmag * dt
		self.right = rotate(self.right, axis, ang)
		self.up = rotate(self.up, axis, ang)
		self.look = rotate(self.look, axis, ang)
	end
	-- re-orthonormalise
	self.look = vector.normalize(self.look)
	self.right = vector.normalize(vector.cross(self.look, self.up))
	self.up = vector.cross(self.right, self.look)
end

-- Very simple box-vs-ground contact on the 8 corners (only matters when the
-- suspension bottoms out or the kart rolls). Counts how often it happens.
function Body:collideGround(ground, dt: number)
	local hx, hy, hz = self.size[1] / 2, self.size[2] / 2, self.size[3] / 2
	local touched = false
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local p = self.pos + self.right * (sx * hx) + self.up * (sy * hy + self.hitOffsetY) + self.look * (sz * hz + self.hitOffsetZ)
				local gy = ground:heightAt(p.x, p.z, p.y + 3)
				local pen = gy - p.y
				if pen > 0 then
					touched = true
					local r = p - self.pos
					local vp = self.vel + vector.cross(self.angVel, r)
					local nUp = vector.create(0, 1, 0)
					local vn = vector.dot(vp, nUp)
					-- push out and kill the approaching velocity at the corner (crudely)
					self.pos += nUp * pen
					if vn < 0 then
						local j = -vn * self.mass * 0.25
						local fric = vector.create(vp.x, 0, vp.z) * (-0.3 * self.mass * 0.25)
						local imp = nUp * j + fric
						self.vel += imp / self.mass
						-- angular response approximated with the yaw/pitch/roll inertia
						local ti = vector.cross(r, imp)
						local back = -self.look
						local tl = vector.create(vector.dot(ti, self.right) / self.ix, vector.dot(ti, self.up) / self.iy, vector.dot(ti, back) / self.iz)
						self.angVel += self.right * tl.x + self.up * tl.y + back * tl.z
					end
				end
			end
		end
	end
	if touched then
		self.bottomHits += 1
	end
end

-- Roll and pitch angles (degrees) relative to the world.
function Body:attitude(): (number, number)
	local roll = math.deg(math.asin(math.clamp(self.right.y, -1, 1)))
	local pitch = math.deg(math.asin(math.clamp(self.look.y, -1, 1)))
	return roll, pitch
end

World.Body = Body
World.Ground = Ground
return World
