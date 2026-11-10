-- Simulate one E press against the current virtual aim target in a live walk.
local walk = PocketMap and PocketMap.Walk and PocketMap.Walk.session
if not walk then return "No active miniature walk" end
local IO = PocketMap.MapIO
local move, state = walk.move, walk.io
local eye, forward = move.origin + Vector(0, 0, 64), move.angles:Forward()
local button, nearest = nil, 96

for _, record in ipairs(state.world.useTargets) do
	if IO.classes[record.class] and IO.classes[record.class].use then
		local lo, hi = IO.Bounds(record, state)
		if lo then
			local enter, leave = 0, nearest
			for _, axis in ipairs({ "x", "y", "z" }) do
				local speed = forward[axis]
				if math.abs(speed) < 0.000001 then
					if eye[axis] < lo[axis] or eye[axis] > hi[axis] then leave = -1 break end
				else
					local a, b = (lo[axis] - eye[axis]) / speed, (hi[axis] - eye[axis]) / speed
					if a > b then a, b = b, a end
					enter, leave = math.max(enter, a), math.min(leave, b)
				end
			end
			if enter <= leave and enter < nearest then button, nearest = record, enter end
		end
	end
end

if not button then return "Nothing in use range" end
if button.class ~= "func_button" then return "Aimed at " .. button.class .. " instead of func_button" end
local event = button.outputs.onpressed and button.outputs.onpressed[1]
local door = event and state.world.names[event.target] and state.world.names[event.target][1]
local before = door and IO.State(state, door).door
local oldGoal = before and before.goal

local savedButtons, savedOldButtons = move.buttons, move.oldButtons
move.buttons = bit.bor(savedButtons, IN_USE)
move.oldButtons = bit.band(savedOldButtons, bit.bnot(IN_USE))
IO.Step(walk, engine.TickInterval())
move.buttons, move.oldButtons = savedButtons, savedOldButtons

local buttonState = IO.State(state, button).button
local after = door and IO.State(state, door).door
return util.TableToJSON({
	button = button.name, distance = nearest, pressed = buttonState and buttonState.goal == 1,
	outputTarget = event and event.target, targetClass = door and door.class,
	doorBefore = oldGoal, doorAfter = after and after.goal,
}, true)
