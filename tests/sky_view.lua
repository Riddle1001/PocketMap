-- The walking scene owns the entire viewport; the external miniature still
-- requires its block mask. Exercise the actual 3D sky entry point in both.
local f=assert(io.open('lua/pocketmap/cl_sky.lua','r'))
local source=f:read('*a');f:close()
local first=assert(source:find('local function drawSkyContents(',1,true))
local masked,cleared,stencilled,fullCleared,objects,props=0,0,0,0,0,0
local sky={}
local env={Sky=sky,updateSkyMatrix=function()return {GetScale=function()return {x=1}end}end,
    maskBlock=function()masked=masked+1 end,clearDepthInMask=function()cleared=cleared+1 end,
    stencilForTheMap=function()stencilled=stencilled+1 end,
    render={OverrideDepthEnable=function()end,ClearDepth=function()fullCleared=fullCleared+1 end},
    PocketMap={Materials={DrawOptions=function(o)return o end},
        Props={DrawSky=function()props=props+1 end}}}
setmetatable(env,{__index=_G})
local chunk=assert(loadstring(source:sub(first)));setfenv(chunk,env);chunk()
local mini={skyOrigin={},skyObjects={{DrawOpaque=function()objects=objects+1 end,
    DrawTranslucent=function()objects=objects+1 end}}}
sky.Draw3D(mini,{},true)
assert(masked==0 and cleared==0 and stencilled==0 and fullCleared==1 and objects==2 and props==2,
    'direct walking view lost sky geometry to the block stencil')
sky.Draw3D(mini,{})
assert(masked==1 and cleared==1 and stencilled==1 and fullCleared==1 and objects==4 and props==4,
    'external miniature lost its sky stencil')
print('sky view: complete walking sky and external block stencil passed')
