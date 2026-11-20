--!strict
-- The hit of an aimed swing (aimSwing weapons) follows the line drawn on the circle: the blade sweeps
-- from the opposite side, through the crosshair, out to where the line points. Rays are cast along
-- that arc in swing order; the first one that meets a body wins (it is what the weapon meets first),
-- otherwise the crosshair ray's own result (a wall, the floor) stands. A plain swing (no line) stays
-- one ray down the crosshair. Server and client share this so the predicted sound matches the hit.
local SwingArc = {}

SwingArc.HALF = math.rad(55) -- the arc reaches this far either side of the crosshair
SwingArc.RAYS = 9 -- odd, so the middle one is the crosshair ray

-- The directions along the arc in swing order (start .. end), or just { dir } for a plain swing.
function SwingArc.dirs(dir: Vector3, swing: any): { Vector3 }
	if typeof(swing) ~= "Vector3" then return { dir } end
	local side = Vector3.new(swing.X, swing.Y, 0)
	if side.Magnitude < 0.3 or side.Magnitude ~= side.Magnitude then return { dir } end
	side = side.Unit
	local right = dir:Cross(Vector3.yAxis)
	right = right.Magnitude > 0.01 and right.Unit or Vector3.xAxis
	local up = right:Cross(dir).Unit
	local toward = (right * side.X + up * side.Y).Unit -- where the line points, across the view
	local axis = dir:Cross(toward).Unit -- turning dir about this swings it toward `toward`
	local out = table.create(SwingArc.RAYS)
	for i = 0, SwingArc.RAYS - 1 do
		local t = i / (SwingArc.RAYS - 1) * 2 - 1 -- -1 (cocked side) .. 1 (the line's end)
		table.insert(out, CFrame.fromAxisAngle(axis, t * SwingArc.HALF):VectorToWorldSpace(dir))
	end
	return out
end

-- Sweep the arc. isBody(instance) says whether a hit counts as meeting someone. Returns the result
-- and the direction of the ray that found it (nil, dir when nothing is in reach).
function SwingArc.cast(origin: Vector3, dir: Vector3, swing: any, range: number, params: RaycastParams,
	isBody: (Instance) -> boolean): (RaycastResult?, Vector3)
	local dirs = SwingArc.dirs(dir, swing)
	local middle = (#dirs + 1) // 2
	local fallback, fallbackDir = nil, dir
	for i, d in dirs do
		local result = workspace:Raycast(origin, d * range, params)
		if result and isBody(result.Instance) then return result, d end
		if i == middle then fallback, fallbackDir = result, d end
	end
	return fallback, fallbackDir
end

return SwingArc
