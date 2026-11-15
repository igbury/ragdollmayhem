-- Separate entry/exit clips live in AnimationClips; these are the low movement loops.
local clips = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("AnimationClips"))
return function(kind: string): KeyframeSequence
	assert(kind == "slide" or kind == "crouch" or kind == "crouchIdle", "Unknown low movement: " .. kind)
	return clips.build(kind == "crouchIdle" and "CrouchIdle" or kind)
end
