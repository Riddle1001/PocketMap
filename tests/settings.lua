-- Functional menu/configuration test. Run from the PocketMap root.
local cvs, writes = {}, 0
function GetConVar(name)return cvs[name]end
function CreateClientConVar(name,default)
	if cvs[name]then return cvs[name]end
	local cv={value=tonumber(default)}
	function cv:GetBool()return self.value~=0 end
	function cv:GetInt()return self.value end
	function cv:SetBool(v)self.value=v and 1 or 0 writes=writes+1 end
	function cv:SetInt(v)self.value=v writes=writes+1 end
	cvs[name]=cv return cv
end
CreateClientConVar('pocketmap_water','1')
function IsValid(v)return type(v)=='table' and v.valid==true end
PocketMap={}
dofile('lua/pocketmap/cl_settings.lua')
local S=PocketMap.Settings
assert(#S.Options==61,'feature catalogue changed; review preset and menu coverage')
for _,preset in ipairs(S.Presets)do
	local values=S.Preset(preset.key)
	for _,o in ipairs(S.Options)do
		assert(type(values[o.key])=='boolean','preset omitted '..o.key)
		assert(o.cost~='' and o.visual~='' and o.detail~='','missing impact information')
	end
	for _,key in ipairs({'minimal_preview','pvs','world_cache','world_frustum_cache','prop_frustum_cache','direct_scene','prop_collision','displacement_collision','dynamic_collision'})do
		assert(values[key],'preset must retain safe optimizations and essential movement')
	end
end
local high,balanced,fast=S.Preset('fidelity'),S.Preset('balanced'),S.Preset('performance')
assert(high.water_reflections and high.water_refractions and high.water_every_frame and high.detail_sprites)
assert(not balanced.water_reflections and balanced.water_refractions and not balanced.water_high_resolution)
assert(not fast.water_reflections and not fast.water_refractions and not fast.particles)
assert(not fast.world_depth_repair and not fast.directional_prop_ambient and not fast.world_normalmaps
	and not fast.world_detailtextures and not fast.world_reflections and fast.defer_world_cache)
assert(high.world_depth_repair and high.directional_prop_ambient and high.world_normalmaps)
assert(S.WaterMode({settings=high},cvs.pocketmap_water)==2)
assert(S.WaterMode({settings=balanced},cvs.pocketmap_water)==1)
assert(S.WaterMode({settings=fast},cvs.pocketmap_water)==0)
local outside=true
local viewed={settings=S.Copy(high),EyeInside=function()return not outside end}
assert(S.MinimalPreview(viewed) and S.Enabled(viewed,'static_props') and S.Enabled(viewed,'lightmaps'),
	'outside preview must not change build-time settings')
PocketMap.Walk={session={mini={}}}
assert(S.MinimalPreview(viewed),'walking in another block must not enable this preview')
outside=false
assert(not S.MinimalPreview(viewed),'entering with the camera must restore the selected features')
outside=true viewed.settings.minimal_preview=false
assert(not S.MinimalPreview(viewed),'the preview override must be optional per block')
assert(not S.MinimalPreview(nil) and not S.MinimalPreview({settings=high}),
	'non-render callers must keep their configured build settings')
local separate={settings=S.Copy(high)}
local ent={valid=true,GetClass=function()return 'ent_pocketmap'end,GetMapName=function()return 'test_map'end,
	CanRetryLoad=function()return false end}
ent.Miniature={settings=S.Read()}
local initial=S.Copy(ent.Miniature.settings)
function ent:AcceptMap()self.builds=(self.builds or 0)+1 self.Miniature={settings=S.Read(self)}end

-- Minimal panels model events and draft state. Layout is checked in the game.
local panels={}
local panel={}
panel.__index=function(self,key)
	if panel[key]then return panel[key]end
	if key:sub(1,3)=='Set' or key=='Dock' or key=='DockMargin' or key=='DockPadding' or key=='InvalidateLayout'
		or key=='SizeToContents' or key=='Center' or key=='MakePopup' then
		return function(p,...)p[key..'Args']={...}end
	end
end
local function new(kind,parent)
	local p=setmetatable({valid=true,kind=kind,parent=parent,visible=true,width=1000,height=700},panel)
	panels[#panels+1]=p return p
end
function panel:SetSize(w,h)self.width,self.height=w,h end
function panel:SetWide(w)self.width=w end
function panel:GetWide()return self.width end
function panel:SetVisible(v)self.visible=v end
function panel:IsVisible()return self.visible end
function panel:SetValue(v)self.checked=v==true or v==1 if self.OnChange then self:OnChange(self.checked)end end
function panel:SetText(v)self.text=v end
function panel:GetValue()return self.text or ''end
function panel:Remove()self.valid=false end
panel.Close=panel.Remove
function panel:Add(kind)return new(kind,self)end
function panel:AddItem(item)end
function panel:AddSheet(name,p)return {Tab=new('DTab',self),Panel=p,Name=name}end
vgui={Create=new}
Color=function(...)return {...}end
color_white=Color(255,255,255)
function ScrW()return 1600 end
function ScrH()return 900 end
TOP,BOTTOM,LEFT,RIGHT,FILL=1,2,3,4,5
string.StripExtension=function(s)return s:gsub('%.%w+$','')end
table.Count=function(t)local n=0 for _ in pairs(t)do n=n+1 end return n end
file={Find=function(pattern)if pattern=='maps/*.bsp'then return {'test_map.bsp','other_map.bsp'}end return {}end}
PocketMap.GroupMaps=function(maps)return {'Test'},{Test=maps}end
local sent={}
net={Receive=function()end,Start=function()end,WriteEntity=function(e)sent.entity=e end,
	WriteString=function(s)sent.name=s end,SendToServer=function()sent.count=(sent.count or 0)+1 end}
dofile('lua/pocketmap/cl_ui.lua')
PocketMap.OpenMenu(ent)
local menu=PocketMap.Menu
assert(menu.PropertySheet.kind=='DPropertySheet' and menu.RebuildButton.text=='OK and Rebuild')
assert(table.Count(menu.SettingsBoxes)==#S.Options,'every option needs a checkbox')
menu.PresetButtons.performance:DoClick()
for _,o in ipairs(S.Options)do assert(menu.SettingsBoxes[o.key].checked==fast[o.key])end
assert(writes==0 and not ent.builds and not sent.count,'preset clicks must only edit the draft')
menu:Close()
PocketMap.OpenMenu(ent)
menu=PocketMap.Menu
for _,o in ipairs(S.Options)do assert(menu.SettingsDraft[o.key]==initial[o.key],'Cancel leaked draft changes')end
menu.PresetButtons.balanced:DoClick()
menu.SettingsBoxes.water_reflections:SetValue(1)
menu.SettingsBoxes.prop_shadows:SetValue(1)
assert(writes==0 and not ent.builds,'individual checkboxes must not apply/rebuild early')
menu.RebuildButton:DoClick()
assert(ent.builds==1 and not menu.valid,'OK must rebuild an already healthy same-map block exactly once')
assert(ent.Miniature.settings.water_reflections and ent.Miniature.settings.prop_shadows,'manual preset overrides were lost')
for _,o in ipairs(S.Options)do assert(separate.settings[o.key]==high[o.key],'another miniature changed')end
local snapshot=S.Read(ent)
snapshot.prop_shadows=false
assert(ent.PocketMapSettings.prop_shadows,'opening/editing settings must use a copy')
PocketMap.OpenMenu(ent)
menu=PocketMap.Menu
for _,p in ipairs(panels)do if p.MapName=='other_map' and p.valid then p:DoClick()end end
assert(not sent.count and ent.builds==1,'map selection must also remain staged')
menu.RebuildButton:DoClick()
assert(sent.count==1 and sent.name=='other_map' and ent.ExpectedMap=='other_map','new-map selection did not use the existing network path')
assert(ent.builds==1,'new-map selection must wait for the server map change before building')
assert(S.Apply(ent,fast))
local fresh=S.Read()
for _,o in ipairs(S.Options)do assert(fresh[o.key]==fast[o.key],'new blocks lost the applied defaults: '..o.key)end
local before=writes
ent.valid=false
assert(not S.Apply(ent,fast) and writes==before,'deleted blocks must not apply client defaults')
local added={minimal_preview=true,world_depth_repair=true,world_source_camera=true,world_normalmaps=true,world_detailtextures=true,
	world_reflections=true,directional_prop_ambient=true,defer_world_cache=true}
local oldOptions={}
for _,o in ipairs(S.Options)do if not added[o.key]then oldOptions[#oldOptions+1]=o end end
local legacy=S.Preset('performance')
for key in pairs(added)do legacy[key]=nil end
local existing={settings=legacy,ent={PocketMapSettings={}}}
for key,value in pairs(legacy)do existing.ent.PocketMapSettings[key]=value end
PocketMap.Active={[existing]=true};S.Options=oldOptions
dofile('lua/pocketmap/cl_settings.lua')
for key in pairs(added)do
	assert(existing.settings[key]==fast[key] and existing.ent.PocketMapSettings[key]==fast[key],
		'new controls must inherit an existing preset instead of silently restoring high-cost defaults: '..key)
end
print('PASS settings/menu: 61 controls, complete presets, optional camera-based preview, build isolation, staged edits/maps, cancellation, rebuild and per-block isolation')
