-- Run from the PocketMap root: lua tests/compare.lua
local vector = {}
vector.__index = vector
function Vector(x,y,z) return setmetatable({ x=x or 0,y=y or 0,z=z or 0 },vector) end
function vector.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function vector.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function vector:DistToSqr(b) local d=self-b return d.x*d.x+d.y*d.y+d.z*d.z end
function IsValid(value) return type(value)=="table" and value.valid~=false end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
local ply={pos=Vector(10,20,30),angle=Angle(0,45,0),moveType=2}
function ply:Alive() return true end
function ply:IsAdmin() return false end
function ply:GetPos() return self.pos end
function ply:EyePos() return self.pos+Vector(0,0,64) end
function ply:EyeAngles() return self.angle end
function ply:GetMoveType() return self.moveType end
function ply:SetPos(p) self.pos=p end
function ply:SetEyeAngles(a) self.angle=a end
function ply:SetMoveType(t) self.moveType=t end
function ply:SetLocalVelocity(v) self.velocity=v end
local block={map="test_map"}
function block:GetMapName() return self.map end
function block:GetClass() return "ent_pocketmap" end
function block:NearestPoint(eye) return eye end
MOVETYPE_NOCLIP=8
game={GetMap=function()return "test_map" end,SinglePlayer=function()return false end}
PocketMap={}
util={AddNetworkString=function()end}
local receivers,hooks,request,message={},{},{},{}
hook={Add=function(event,name,fn)hooks[event]=fn end}
net={
	Receive=function(name,fn)receivers[name]=fn end,
	ReadBool=function()return request.returning end,ReadEntity=function()return request.block end,
	ReadVector=function()return request.eye end,ReadAngle=function()return request.angle end,
	Start=function()message={}end,WriteUInt=function(n)message.mode=n end,
	WriteVector=function(v)message.eye=v end,WriteAngle=function(a)message.angle=a end,
	WriteString=function(s)message.error=s end,Send=function()end,
}
dofile("lua/pocketmap/sv_compare.lua")
local function send(returning,eye,angle)
	request={returning=returning,block=block,eye=eye or Vector(1000,2000,3000),angle=angle or Angle(10,90,0)}
	receivers.PocketMap_Compare(0,ply)
end
local initialPos,initialAngles=ply.pos,ply.angle
send(false)
assert(message.mode==2 and ply.pos==initialPos,"unprivileged comparison moved the player")
ply.PocketMapCanCompare=true
block.map="other_map"
send(false)
assert(message.mode==2 and not PocketMap.CompareReturns[ply],"mismatched map was accepted")
block.map="test_map"
send(false,Vector(0/0,0,0))
assert(message.mode==2 and not PocketMap.CompareReturns[ply],"invalid position was accepted")
send(false)
assert(message.mode==0 and ply:EyePos():DistToSqr(request.eye)<0.000001,"native eye position changed")
assert(ply.angle==request.angle and ply.moveType==MOVETYPE_NOCLIP,"native viewing angle or noclip was lost")
send(false)
assert(message.mode==2,"duplicate entry replaced return state")
local nativeEye,nativeAngle=Vector(1200,2100,3200),Angle(-20,150,0)
ply.pos,ply.angle=nativeEye-Vector(0,0,64),nativeAngle
send(true)
assert(message.mode==1 and message.eye:DistToSqr(nativeEye)<0.000001 and message.angle==nativeAngle,"return lost the native view")
assert(ply.pos==initialPos and ply.angle==initialAngles and ply.moveType==2,"return did not restore the real player")
assert(not PocketMap.CompareReturns[ply],"return state leaked")
send(false)
hooks.PlayerDisconnected(ply)
assert(not PocketMap.CompareReturns[ply],"disconnect retained comparison state")
-- Exercise the client command and both acknowledgement paths.
local commands={}
local sent, response = 0, {}
function LocalPlayer() return ply end
function RealTime() return 100 end
chat={AddText=function()end}
concommand={Add=function(name,fn)commands[name]=fn end}
net.WriteBool=function(value)message.returning=value end
net.WriteEntity=function(value)message.block=value end
net.SendToServer=function()sent=sent+1 end
net.ReadUInt=function()return response.mode end
net.ReadVector=function()return response.eye end
net.ReadAngle=function()return response.angle end
net.ReadString=function()return response.error end
local io={touching={old=true},queue={"door state"}}
local mini={ent=block,mapName="test_map",state="ready"}
local old={mini=mini,io=io,move={origin=Vector(200,300,400),angles=Angle(5,60,0)}}
PocketMap.Walk={session=old,EyeOffset=function()return Vector(0,0,64)end}
function PocketMap.Walk.Leave() PocketMap.Walk.session=nil end
function PocketMap.Walk.Enter() PocketMap.Walk.session={mini=mini,move={}} end
dofile("lua/pocketmap/cl_compare.lua")
commands.pocketmap_compare()
assert(PocketMap.Compare.pending and PocketMap.Compare.saved==old and not message.returning,"client failed to request native comparison")
assert(message.eye:DistToSqr(Vector(200,300,464))<0.000001 and message.angle==old.move.angles,"client sent a different view")
commands.pocketmap_compare()
assert(sent==1,"pending request was duplicated")
response={mode=0}
receivers.PocketMap_Compare()
assert(not PocketMap.Walk.session and PocketMap.Compare.saved==old and not PocketMap.Compare.pending,"native acknowledgement lost saved session")
commands.pocketmap_compare()
assert(message.returning and PocketMap.Compare.pending,"native view failed to request return")
response={mode=1,eye=Vector(250,350,500),angle=Angle(-10,120,0)}
receivers.PocketMap_Compare()
local resumed=PocketMap.Walk.session
assert(resumed.move.origin:DistToSqr(Vector(250,350,436))<0.000001 and resumed.move.angles==response.angle,"return changed the rendered eye or angles")
assert(resumed.io==io and resumed.io.queue[1]=="door state" and not next(resumed.io.touching),"comparison lost map logic or retained stale touches")
assert(not PocketMap.Compare.saved and not PocketMap.Compare.pending and resumed.enteredAt==98,"return did not clear transition state")
mini.mapName="other_map"
commands.pocketmap_compare()
assert(sent==2,"client accepted a mismatched map")
print("PASS comparison: permission, map matching, finite coordinates, exact native view, return view, body restoration, cleanup")
