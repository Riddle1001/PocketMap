local result = {}
for _, ent in ipairs(ents.FindByClass("ent_pocketmap")) do
	local mini = ent.Miniature
	result[#result + 1] = {
		map = ent:GetMapName(), state = mini and mini.state or "absent",
		status = mini and mini.status or "", progress = mini and mini.progress or 0,
		dynamicMeshes = mini and mini.dynamicMeshes and #mini.dynamicMeshes or 0,
		useTargets = mini and mini.mapIO and #mini.mapIO.useTargets or 0,
	}
end
return util.TableToJSON(result, true)
