-- Returned to GTerm by PocketMap.GTerm.RunFile; never loaded by autorun.
local walk = PocketMap and PocketMap.Walk and PocketMap.Walk.session
if not walk then return "PocketMap.Walk.session is inactive" end
local state = walk.io
if not state or not state.world then return "Walking session has no Map I/O world" end

local IO = PocketMap.MapIO
local world = state.world
local eye = walk.move.origin + Vector(0, 0, 64)
local forward = walk.move.angles:Forward()
local result = {
	virtualEye = tostring(eye), virtualAngles = tostring(walk.move.angles),
	buttons = walk.move.buttons, oldButtons = walk.move.oldButtons,
	useDown = walk.move:KeyDown(IN_USE),
	entities = #world.entities, useTargets = #world.useTargets,
	solids = world.solids and #world.solids or -1,
	dynamicModels = table.Count(world.dynamicModels),
	dynamicMeshes = walk.mini.dynamicMeshes and #walk.mini.dynamicMeshes or 0,
	registered = {}, nearby = {}, classes = {},
}

for _, class in ipairs({ "func_button", "func_rot_button", "func_door", "func_door_rotating", "prop_door_rotating" }) do
	local handlers = IO.classes[class]
	result.registered[class] = handlers and { use = not not handlers.use, solid = not not handlers.solid } or "missing"
end

for class, records in pairs(world.byClass) do
	if class:find("button") or class:find("door") or class:find("teleport") then
		result.classes[class] = #records
	end
end

for _, record in ipairs(world.useTargets) do
	local lo, hi = IO.Bounds(record, state)
	if lo then
		local enter, leave = 0, 96
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
		if enter <= leave then
			result.nearby[#result.nearby + 1] = {
				class = record.class, name = record.name or "", distance = enter,
				enabled = IO.Enabled(state, record), outputs = record.outputs,
			}
		end
	end
end

table.sort(result.nearby, function(a, b) return a.distance < b.distance end)
while #result.nearby > 5 do table.remove(result.nearby) end
return util.TableToJSON(result, true)
