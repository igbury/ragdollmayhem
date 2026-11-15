-- Impact detection for a ragdoll: each part keeps its recent top speed, which sinks at FADE, and
-- an impact is the speed it lost when something stopped it. A landing spread over a few frames
-- still counts in full; slowing down by sliding or walking never does. Run by the server for loose
-- bodies, and by the client holding one (it owns that body's physics, the server only sees it late).
local Impact = {}

Impact.PARTS = { "Head", "UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
Impact.SPEED = 50 -- studs/s lost before it hurts (calibration knob)
Impact.PER_POWER = 15 -- every this many more studs/s is one more punch's worth
Impact.FADE = 400 -- studs/s² the remembered top speed sinks by (gravity is 196)

function Impact.power(lost: number): number
	return 0.5 + (lost - Impact.SPEED) / Impact.PER_POWER
end

export type State = { peaks: { [string]: any }, pending: any? }

function Impact.new(): State
	return { peaks = {}, pending = nil }
end

-- One frame. Returns the finished impact { lost, part, dir } once the speed has stopped falling away.
function Impact.step(state: State, model: Model, dt: number): { lost: number, part: BasePart, dir: Vector3 }?
	local peaks = state.peaks
	local worst, worstLost, worstPart, worstDir = -math.huge, 0, nil, nil
	for _, name in Impact.PARTS do
		local part = model:FindFirstChild(name) :: BasePart?
		if not part then
			continue
		end
		local v = part.AssemblyLinearVelocity
		local speed = v.Magnitude
		local peak = peaks[name]
		if not peak then
			peak = { speed = 0, dir = Vector3.yAxis, set = false } -- one table per part, reused every frame
			peaks[name] = peak
		end
		if not peak.set or speed >= peak.speed - Impact.FADE * dt then
			peak.speed, peak.dir, peak.set = speed, speed > 0.1 and v.Unit or Vector3.yAxis, true
			continue
		end
		peak.speed -= Impact.FADE * dt
		local lost = peak.speed - speed
		-- the whole body landing at once (standing): the lowest part is the one that hit
		local score = lost - part.Position.Y * 0.05
		if lost > Impact.SPEED and score > worst then
			worst, worstLost, worstPart, worstDir = score, lost, part, peak.dir
		end
	end
	-- a landing takes a few frames: wait until the speed has stopped falling away, then count it all
	local pending = state.pending
	if worstPart and (not pending or worstLost > pending.lost) then
		state.pending = { lost = worstLost, part = worstPart, dir = worstDir }
	elseif pending then
		state.pending = nil
		for _, peak in peaks do
			peak.set = false
		end
		if pending.part.Parent == model then
			return pending
		end
	end
	return nil
end

return Impact
