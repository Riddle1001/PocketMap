-- Opt-in client Lua probes through a dedicated server's GTerm console.
-- Load with: lua_run include('pocketmap/dev/sv_gterm.lua')
PocketMap = PocketMap or {}
PocketMap.GTerm = {}
local GTerm = PocketMap.GTerm
local CHANNEL = "PocketMap_GTerm_Probe"

util.AddNetworkString(CHANNEL)

local nextId, pending = 0, {}

net.Receive(CHANNEL, function(_, ply)
	local id = net.ReadUInt(16)
	local request = pending[id]
	if not request or request ~= ply then return end
	pending[id] = nil
	local ok, result = net.ReadBool(), net.ReadString()
	print("[PocketMap client #" .. id .. " " .. ply:Nick() .. "] " .. (ok and "OK: " or "ERROR: ") .. result)
end)

function GTerm.Run(code, ply)
	ply = ply or player.GetAll()[1]
	if not IsValid(ply) then print("[PocketMap GTerm] No connected player") return end
	if type(code) ~= "string" then print("[PocketMap GTerm] Expected Lua source") return end

	nextId = nextId % 65535 + 1
	local id = nextId
	pending[id] = ply
	local script = string.format([[
		local source = PocketMap_GTerm_Buffers[%d]
		PocketMap_GTerm_Buffers[%d] = nil
		local compiled = CompileString(source, "PocketMap GTerm client", false)
		local ok, result
		if type(compiled) == "function" then
			ok, result = pcall(compiled)
		else
			ok, result = false, compiled
		end
		net.Start(%q)
		net.WriteUInt(%d, 16)
		net.WriteBool(ok)
		net.WriteString(tostring(result))
		net.SendToServer()
	]], id, id, CHANNEL, id)
	-- Newly registered network strings need a tick to reach connected clients.
	timer.Simple(0.5, function()
		if not IsValid(ply) then return end
		-- Player:SendLua is limited to 6144 bytes per call.
		for i = 1, #code, 1900 do
			local chunk = code:sub(i, i + 1899)
			ply:SendLua(string.format([[
				PocketMap_GTerm_Buffers = PocketMap_GTerm_Buffers or {}
				PocketMap_GTerm_Buffers[%d] = (PocketMap_GTerm_Buffers[%d] or "") .. %q
			]], id, id, chunk))
		end
		ply:SendLua(script)
	end)
	timer.Simple(15, function() pending[id] = nil end)
	print("[PocketMap GTerm] Client probe #" .. id .. " queued for " .. ply:Nick())
	return id
end

function GTerm.RunFile(path, ply)
	local source = file.Read(path, "LUA")
	if not source then print("[PocketMap GTerm] Lua file not found: " .. tostring(path)) return end
	return GTerm.Run(source, ply)
end
