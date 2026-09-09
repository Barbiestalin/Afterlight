ix.disciplines = ix.disciplines or {}
ix.disciplines.powers = ix.disciplines.powers or {}
ix.disciplines.interfaceDisciplines = ix.disciplines.interfaceDisciplines or {list = {}, order = {}}

ix.disciplines.interfaceIcons = {
	animalism = "afterlight/disciplines/icons/animalism.png",
	celerity = "afterlight/disciplines/icons/celerity.png",
	vicissitude = "afterlight/disciplines/icons/vicissitude.png",
	potence = "afterlight/disciplines/icons/potence.png",
	dominate = "afterlight/disciplines/icons/dominate.png",
	presence = "afterlight/disciplines/icons/presence.png",
	auspex = "afterlight/disciplines/icons/auspex.png",
	dementation = "afterlight/disciplines/icons/dementation.png",
	fortitude = "afterlight/disciplines/icons/fortitude.png",
	protean = "afterlight/disciplines/icons/protean.png",
	thanatosis = "afterlight/disciplines/icons/thanatosis.png",
	obfuscate = "afterlight/disciplines/icons/obfuscate.png",
	obtenebration = "afterlight/disciplines/icons/obtenebration.png",
	chimerstry = "afterlight/disciplines/icons/chimerstry.png",
	valeren = "afterlight/disciplines/icons/valeren.png",
	necromancy = "afterlight/disciplines/icons/necromancy.png",
	serpentis = "afterlight/disciplines/icons/serpentis.png",
	thaumaturgy_blood = "afterlight/disciplines/icons/thaumaturgy.png",
	thaumaturgy_fire = "afterlight/disciplines/icons/thaumaturgy.png",
	thaumaturgy_conjuring = "afterlight/disciplines/icons/thaumaturgy.png",
	thaumaturgy_hearth = "afterlight/disciplines/icons/thaumaturgy.png"
}

function ix.disciplines.ApplyInterfaceIcons()
	if (!ix.disciplines.list) then return false end
	for id, icon in pairs(ix.disciplines.interfaceIcons) do
		if (ix.disciplines.list[id]) then ix.disciplines.list[id].icon = icon end
	end
	return true
end

local function ResolveID(id)
	if (ix.disciplines.ResolveID) then return ix.disciplines.ResolveID(id) end
	return string.lower(string.Trim(tostring(id or "")))
end

function ix.disciplines.RegisterInterfaceDiscipline(id, definition)
	id = ResolveID(id)
	definition = istable(definition) and table.Copy(definition) or {}
	assert(id != "" and isstring(definition.name) and definition.name != "", "invalid interface discipline")
	local registry = ix.disciplines.interfaceDisciplines
	if (!registry.list[id]) then registry.order[#registry.order + 1] = id end
	definition.id = id
	definition.interfaceOnly = true
	definition.maxLevel = math.Clamp(math.floor(tonumber(definition.maxLevel) or 1), 1, 5)
	registry.list[id] = definition
	return definition
end

function ix.disciplines.GetInterfaceDiscipline(id)
	id = ResolveID(id)
	return ix.disciplines.interfaceDisciplines.list[id] or
		(ix.disciplines.Get and ix.disciplines.Get(id) or nil)
end

function ix.disciplines.CanAccessInterfaceDiscipline(character, id)
	id = ResolveID(id)
	local definition = ix.disciplines.interfaceDisciplines.list[id]
	if (definition) then
		if (definition.CanAccess) then return definition.CanAccess(character) == true end
		return character and character.IsVampire and character:IsVampire()
	end
	return ix.disciplines.IsGranted and ix.disciplines.IsGranted(character, id) or false
end

function ix.disciplines.GetInterfaceDisciplineLevel(character, id)
	id = ResolveID(id)
	local definition = ix.disciplines.interfaceDisciplines.list[id]
	if (definition) then
		if (definition.GetLevel) then
			return math.Clamp(math.floor(tonumber(definition.GetLevel(character)) or 0), 0, definition.maxLevel)
		end
		return definition.maxLevel
	end
	return ix.disciplines.GetLevel and ix.disciplines.GetLevel(character, id) or 0
end

function ix.disciplines.GetAccessibleInterfaceDisciplines(character)
	local result, seen = {}, {}
	local learned = ix.disciplines.GetCharacterData and ix.disciplines.GetCharacterData(character) or {}
	for _, id in ipairs(ix.disciplines.order or {}) do
		if (learned[id]) then
			result[#result + 1] = {id = id, definition = ix.disciplines.GetInterfaceDiscipline(id), level = learned[id].level}
			seen[id] = true
		end
	end
	for _, id in ipairs(ix.disciplines.interfaceDisciplines.order) do
		if (!seen[id] and ix.disciplines.CanAccessInterfaceDiscipline(character, id)) then
			result[#result + 1] = {
				id = id,
				definition = ix.disciplines.GetInterfaceDiscipline(id),
				level = ix.disciplines.GetInterfaceDisciplineLevel(character, id)
			}
		end
	end
	return result
end

function ix.disciplines.RegisterPower(disciplineID, powerID, definition)
	disciplineID = ResolveID(disciplineID)
	powerID = string.lower(string.Trim(tostring(powerID or "")))
	definition = istable(definition) and table.Copy(definition) or {}
	assert(disciplineID != "" and powerID != "", "invalid discipline power ID")
	assert(isstring(definition.name) and definition.name != "", "discipline power requires a name")
	local registry = ix.disciplines.powers[disciplineID] or {list = {}, order = {}}
	ix.disciplines.powers[disciplineID] = registry
	if (!registry.list[powerID]) then registry.order[#registry.order + 1] = powerID end
	definition.id = powerID
	definition.disciplineID = disciplineID
	definition.level = math.Clamp(math.floor(tonumber(definition.level) or 1), 1, 5)
	definition.vitaeCost = math.max(math.floor(tonumber(definition.vitaeCost) or 0), 0)
	registry.list[powerID] = definition
	table.sort(registry.order, function(a, b)
		local powerA, powerB = registry.list[a], registry.list[b]
		if (powerA.level == powerB.level) then return a < b end
		return powerA.level < powerB.level
	end)
	return definition
end

function ix.disciplines.GetPower(disciplineID, powerID)
	local registry = ix.disciplines.powers[ResolveID(disciplineID)]
	return registry and registry.list[string.lower(string.Trim(tostring(powerID or "")))] or nil
end

function ix.disciplines.GetPowers(disciplineID)
	local registry = ix.disciplines.powers[ResolveID(disciplineID)]
	if (!registry) then return {} end
	local result = {}
	for _, powerID in ipairs(registry.order) do result[#result + 1] = registry.list[powerID] end
	return result
end

function ix.disciplines.GetAvailablePowers(character, disciplineID)
	if (!ix.disciplines.CanAccessInterfaceDiscipline(character, disciplineID)) then return {} end
	local level = ix.disciplines.GetInterfaceDisciplineLevel(character, disciplineID)
	local result = {}
	for _, power in ipairs(ix.disciplines.GetPowers(disciplineID)) do
		if (power.level <= level) then result[#result + 1] = power end
	end
	return result
end

function ix.disciplines.CanAccessPower(character, power)
	return power and ix.disciplines.CanAccessInterfaceDiscipline(character, power.disciplineID) and
		ix.disciplines.GetInterfaceDisciplineLevel(character, power.disciplineID) >= power.level
end

function ix.disciplines.GetSelectedPower(character)
	if (!character or !character.GetSelectedDisciplinePower) then return nil end
	local selected = character:GetSelectedDisciplinePower()
	if (!istable(selected)) then return nil end
	return ix.disciplines.GetPower(selected.disciplineID, selected.powerID), selected
end
