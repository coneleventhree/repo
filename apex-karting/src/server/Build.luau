--!strict
-- Small helpers for building geometry from code.

local Build = {}

export type Props = { [string]: any }

-- Creates an anchored part with sensible defaults, then applies `props`.
function Build.part(parent: Instance, props: Props, className: string?): BasePart
	local p = Instance.new((className or "Part") :: any) :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanTouch = false
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Purely visual part: no collision, not hit by raycasts, no shadow cost.
function Build.decor(parent: Instance, props: Props, className: string?): BasePart
	local p = Build.part(parent, props, className)
	p.CanCollide = false
	p.CanQuery = false
	return p
end

-- A thin slab lying on a surface between two points (used for painted lines).
function Build.strip(parent: Instance, a: Vector3, b: Vector3, up: Vector3, width: number, props: Props): BasePart
	local len = (b - a).Magnitude
	local mid = (a + b) / 2
	local look = (b - a).Unit
	local right = look:Cross(up).Unit
	local realUp = right:Cross(look)
	local p = Build.decor(parent, props)
	p.Size = Vector3.new(width, 0.05, len + 0.05)
	p.CFrame = CFrame.fromMatrix(mid + realUp * 0.03, right, realUp, -look)
	p.CastShadow = false
	return p
end

-- Fills triangle (a, b, c) with two wedge parts whose top faces lie exactly in
-- the triangle's plane; the slab extends `thickness` below it.
-- `upHint` says which side of the triangle is "up".
function Build.triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, thickness: number, upHint: Vector3, props: Props): (WedgePart?, WedgePart?)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- make bc the longest edge (the hypotenuse of both right-angle wedges)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-6 then
		return nil, nil
	end
	local right = normal.Unit
	local upv = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(upv))
	if height < 1e-3 then
		return nil, nil
	end
	local n = if right:Dot(upHint) >= 0 then right else -right
	local shift = -n * (thickness / 2)

	local w1 = Instance.new("WedgePart")
	w1.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2 + shift, right, upv, back)
	local w2 = Instance.new("WedgePart")
	w2.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2 + shift, -right, upv, -back)
	for _, w in { w1, w2 } do
		w.Anchored = true
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.CanTouch = false
		for k, v in props do
			(w :: any)[k] = v
		end
		w.Parent = parent
	end
	return w1, w2
end

-- The shared modules use Luau's built-in `vector`; in Roblox that is the very
-- same native value as Vector3 (the VM supports x/y/z and X/Y/Z on it), so
-- these are free casts that only keep the type checker informed.
function Build.v3(v: vector): Vector3
	return (v :: any) :: Vector3
end

function Build.vec(v: Vector3): vector
	return (v :: any) :: vector
end

function Build.folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

return Build
