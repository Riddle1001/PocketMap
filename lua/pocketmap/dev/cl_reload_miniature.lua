-- Rebuild meshes after handlers are hot-loaded into an existing miniature.
local walk = PocketMap and PocketMap.Walk and PocketMap.Walk.session
local ent = walk and walk.mini.ent
if not IsValid(ent) then return "No active miniature to reload" end

local name = ent:GetMapName()
ent:AcceptMap()
return "Reloading " .. name .. "; re-enter the map when loading finishes"
