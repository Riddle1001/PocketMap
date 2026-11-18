-- The rotated box must contain every transformed model-bounds corner.
local vec={}vec.__index=vec
local function Vector(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},vec)end
function vec.__add(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
function vec.__sub(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
function vec.__mul(a,b)return Vector(a.x*b,a.y*b,a.z*b)end
function vec:Length()return math.sqrt(self.x^2+self.y^2+self.z^2)end
local function angle(p,y,r)
    p,y,r=math.rad(p),math.rad(y),math.rad(r)
    local sp,cp,sy,cy,sr,cr=math.sin(p),math.cos(p),math.sin(y),math.cos(y),math.sin(r),math.cos(r)
    local forward=Vector(cp*cy,cp*sy,-sp)
    local right=Vector(-sr*sp*cy+cr*sy,-sr*sp*sy-cr*cy,-sr*cp)
    local up=Vector(cr*sp*cy+sr*sy,cr*sp*sy-sr*cy,cr*cp)
    return {Forward=function()return forward end,Right=function()return right end,Up=function()return up end}
end
local function transform(v,_,origin,a)return origin+a:Forward()*v.x-a:Right()*v.y+a:Up()*v.z end
local env={Vector=Vector,LocalToWorld=transform,ZERO_ANGLE=angle(0,0,0),FRUSTUM_PAD=4}
setmetatable(env,{__index=_G})
local f=assert(io.open('lua/pocketmap/cl_props.lua','r'));local src=f:read('*a');f:close()
local first=assert(src:find('local function propSphere(',1,true))
local last=assert(src:find('---Props are placed',first,true))
local chunk=assert(loadstring(src:sub(first,last-1)..' return propSphere'))setfenv(chunk,env)
local bounds=chunk()
local mini={mapCenter=Vector(10,20,30),boxCenter=Vector(40,50,60)}
local lo,hi=Vector(-20,-4,0),Vector(80,9,7)
for _,rotation in ipairs({angle(0,0,0),angle(20,45,80),angle(-70,-160,40),angle(90,0,90)})do
    for _,scale in ipairs({.01,1,3})do
        local prop={Origin=Vector(100,200,300),Angles=rotation,UniformScale=2}
        local center,radius,extent=bounds(mini,prop,lo,hi,scale)
        for _,x in ipairs({lo.x,hi.x})do for _,y in ipairs({lo.y,hi.y})do for _,z in ipairs({lo.z,hi.z})do
            local world=transform(Vector(x,y,z)*2,nil,prop.Origin,rotation)
            local delta=(world-mini.mapCenter)*scale+mini.boxCenter-center
            assert(math.abs(delta.x)<=extent.x+1e-5 and math.abs(delta.y)<=extent.y+1e-5
                and math.abs(delta.z)<=extent.z+1e-5,'rotated model corner escaped its box')
            assert(delta:Length()<=radius+1e-5)
        end end end
    end
end
assert(bounds(mini,{},nil,nil,1)==nil,'animated/unknown model bounds must fail open')
print('prop bounds: arbitrary pitch/yaw/roll, model scale, block scale and unknown bounds passed')
