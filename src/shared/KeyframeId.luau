-- An animation id for a KeyframeSequence built in memory.
-- A live game can only play uploaded animations, so the uploaded id for the sequence's Name
-- (AnimIds, filled by the upload step) wins. Without one, KeyframeSequenceProvider registers a
-- temporary id; that only works in Studio and errors on a live server, so it fails soft to ""
-- (plays nothing) instead of killing the start-up script.
-- Every sequence seen is also kept in shared.KeyframeSequences, so a Studio session can serialize
-- and upload them (see AnimIds).
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local AnimIds = require(script.Parent:WaitForChild("AnimIds"))

return function(sequence: KeyframeSequence): string
	shared.KeyframeSequences = shared.KeyframeSequences or {}
	shared.KeyframeSequences[sequence.Name] = sequence
	local uploaded = AnimIds[sequence.Name]
	if uploaded then
		return "rbxassetid://" .. uploaded
	end
	local ok, id = pcall(KeyframeSequenceProvider.RegisterKeyframeSequence, KeyframeSequenceProvider, sequence)
	return ok and id or ""
end
