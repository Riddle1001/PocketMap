-- Run from PocketMap: lua tests/entity_refresh.lua
local now, frame, destroyed, left, loaderSteps = 0, 1, 0, 0, 0
local noop = function() end
function Vector() return {} end
function Angle() return {} end
function Color() return {} end
function Matrix() return {} end
function FrameNumber() return frame end
function RealTime() return now end
function CurTime() return now end
function SysTime() return now end
function IsValid(e) return e and e.valid ~= false end
function table.Count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
function include() end
ENT = {}
local hooks = {}
PocketMap = {
	Hooks = {Register=function(event, name, fn) hooks[name]=fn end, SetActive=noop},
	Loader = {Run=noop, Step=function() loaderSteps=loaderSteps+1 end},
	MapIO = {Destroy=noop}, Water = {Free=noop}, Sky = {Free=noop},
	Props = {Destroy=noop}, Effects = {Destroy=noop},
	RT = {Release=noop, IsAtMapLimit=function() return false end},
	Walk = {Leave=function() left=left+1 PocketMap.Walk.session=nil end},
}
dofile('lua/pocketmap/cl_miniature.lua')
dofile('lua/entities/ent_pocketmap/cl_init.lua')
local function block()
	local e=setmetatable({valid=true, creation=17, name='same_map'}, {__index=ENT})
	function e:GetCreationID() return self.creation end
	function e:GetMapName() return self.name end
	function e:IsDormant() return self.dormant end
	function e:SetRenderMode() end
	function e:SetNextClientThink() end
	local m=PocketMap.NewMiniature(e,e.name)
	m.state='ready'
	m.objects={{Destroy=function() destroyed=destroyed+1 end}}
	e.Miniature,e.LoadedMap=m,e.name
	return e,m
end
local function tick(dt)
	now,frame=now+(dt or .1),frame+1
	hooks.PocketMap_Load()
end
local e,m=block()
local walk={mini=m,inputs={[12]=true},io={door='open'},move={x=123}}
PocketMap.Walk.session=walk
e:OnRemove(true)
assert(m.entityRefresh and m.state=='ready' and destroyed==0 and left==0)
assert(next(walk.inputs)==nil,'old commands survived suspension')
m:UpdateEntityRefresh()
assert(m.entityRefresh,'resumed during the removal frame')
e.valid=false;tick()
assert(PocketMap.Active[m] and m.entityRefresh and loaderSteps==0,'invalid refresh was destroyed or loaded')
e.valid=true;e.name='';tick();e:FollowMapName('')
assert(e.Miniature==m and m.entityRefresh and destroyed==0,'transient empty network string dropped meshes')
e:Initialize()
assert(e.LoadedMap=='same_map','reinitialization forgot the selected map')
e.name='same_map';tick()
assert(not m.entityRefresh and e.Miniature==m and e.LoadedMap=='same_map')
assert(PocketMap.Walk.session==walk and walk.io.door=='open' and walk.move.x==123,'recovery reset the virtual world')
assert(destroyed==0 and left==0,'recovery freed resources or ejected the player')
e:OnRemove(false)
assert(m.state=='removed' and not PocketMap.Active[m] and not e.Miniature and left==1 and destroyed==1)
m:Destroy();assert(destroyed==1 and left==1,'cleanup ran twice')

local changed,cm=block()
changed:OnRemove(true);changed.name='different_map';tick()
assert(cm.state=='removed' and not changed.Miniature,'a changed map inherited the old meshes')
local reused,rm=block()
reused:OnRemove(true);reused.creation=18;tick()
assert(rm.state=='removed','a reused entity identity inherited the old meshes')
local missing,mm=block()
missing:OnRemove(true);local expires=mm.entityRefresh.expires
missing:OnRemove(true)
assert(mm.entityRefresh.expires==expires,'repeat full updates extended retention indefinitely')
missing.valid=false;tick(11)
assert(mm.state=='removed' and not PocketMap.Active[mm],'a missing entity leaked resources')
local clear,empty=block()
clear:OnRemove(true);clear.name='';tick(11)
assert(empty.state=='removed','a genuine map clear retained resources indefinitely')
local ordinary,om=block()
ordinary.name='different_map';ordinary:FollowMapName(ordinary.name)
assert(om.state=='removed' and not ordinary.Miniature,'normal map changes no longer clean up')
local deleted,dm=block()
deleted:OnRemove(true);deleted:OnRemove(false)
assert(dm.state=='removed','real deletion during a refresh was ignored')
print('PASS entity refresh: temporary invalidity, same-frame guard, network strings, identity, session preservation, deletion, changes, expiry, idempotent cleanup')
