-- Rebuild the virtual I/O index after reloading handlers in a live client.
local walk = PocketMap and PocketMap.Walk and PocketMap.Walk.session
if not walk then return "No active miniature walk" end

walk.io = PocketMap.MapIO.NewSession(walk.mini)
return "registration=" .. tostring(PocketMap.MapIO.registrationVersion)
	.. " targets=" .. tostring(#walk.io.world.useTargets)
	.. " solids=" .. tostring(#walk.io.world.solids)
