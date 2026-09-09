ix.vtm = ix.vtm or {}
ix.vtm.stats = ix.vtm.stats or {}

local function EmptyValues()
	local values = {}
	for _, id in ipairs(ix.vtm.stats.order) do values[id] = ix.vtm.stats.list[id].base end
	return values
end

function ix.vtm.stats.Normalize(raw)
	raw = istable(raw) and raw or {}
	local values = EmptyValues()
	local source = istable(raw.values) and raw.values or raw

	for rawID, rawValue in pairs(source) do
		local id = ix.vtm.stats.ResolveID(rawID)
		local definition = ix.vtm.stats.list[id]
		if (definition) then
			local value = math.Clamp(math.floor(tonumber(rawValue) or definition.base), definition.base, definition.max)
			values[id] = math.max(values[id] or definition.base, value)
		end
	end

	local unspent = istable(raw.unspent) and raw.unspent or {}
	return {
		version = 2,
		values = values,
		unspent = {
			attributes = math.max(math.floor(tonumber(unspent.attributes) or 0), 0),
			abilities = math.max(math.floor(tonumber(unspent.abilities) or 0), 0),
			virtues = math.max(math.floor(tonumber(unspent.virtues) or 0), 0),
			disciplines = math.max(math.floor(tonumber(unspent.disciplines) or 0), 0)
		},
		vampireBonusGranted = raw.vampireBonusGranted == true,
		creationConfirmed = raw.creationConfirmed == true
	}
end

function ix.vtm.stats.BuildCreation(raw)
	raw = ix.vtm.stats.Normalize(raw)
	local spent = {attributes = 0, abilities = 0, virtues = 0}
	for _, id in ipairs(ix.vtm.stats.order) do
		local definition = ix.vtm.stats.list[id]
		spent[definition.category] = spent[definition.category] + (raw.values[id] - definition.base)
	end
	for _, category in ipairs(ix.vtm.stats.CATEGORIES) do
		raw.unspent[category] = math.max(ix.vtm.stats.CREATION_POINTS[category] - spent[category], 0)
	end
	raw.unspent.disciplines = 0
	return raw, spent
end

function ix.vtm.stats.ValidateCreation(raw)
	if (!istable(raw)) then return false, "vtmStatsInvalid" end
	if (raw.creationConfirmed != true) then return false, "vtmStatsNotConfirmed" end
	local normalized, spent = ix.vtm.stats.BuildCreation(raw)
	local source = istable(raw.values) and raw.values or raw

	for rawID, rawValue in pairs(source) do
		local definition = ix.vtm.stats.GetDefinition(rawID)
		if (definition) then
			rawValue = tonumber(rawValue)
			if (!rawValue or rawValue < definition.base or rawValue > definition.max or rawValue % 1 != 0) then
				return false, "vtmStatsInvalid"
			end
		end
	end
	for _, category in ipairs(ix.vtm.stats.CATEGORIES) do
		if (spent[category] > ix.vtm.stats.CREATION_POINTS[category]) then return false, "vtmStatsOverspent" end
		if (normalized.unspent[category] > 0) then return false, "vtmStatsUnspent" end
	end
	if ((normalized.values.awareness or 0) > 0) then return false, "vtmAwarenessVampireOnly" end
	return true, normalized
end

function ix.vtm.stats.GetData(character)
	if (!character or !character.GetAfterlightVTMStats) then return ix.vtm.stats.Normalize({}) end
	return ix.vtm.stats.Normalize(character:GetAfterlightVTMStats())
end

function ix.vtm.stats.GetBase(character, id)
	local definition = ix.vtm.stats.GetDefinition(id)
	if (!definition) then return 0 end
	if (definition.vampireOnly and (!character or !character.IsVampire or !character:IsVampire())) then return definition.base end
	return ix.vtm.stats.GetData(character).values[definition.id] or definition.base
end

function ix.vtm.stats.GetTemporaryBonus(character, id)
	local definition = ix.vtm.stats.GetDefinition(id)
	if (!definition) then return 0 end
	local bonus = hook.Run("GetCharacterVTMStatBonus", character, definition.id, definition)
	return math.max(math.floor(tonumber(bonus) or 0), 0)
end

function ix.vtm.stats.Get(character, id)
	local definition = ix.vtm.stats.GetDefinition(id)
	if (!definition) then return 0 end
	return math.min(ix.vtm.stats.GetBase(character, definition.id) +
		ix.vtm.stats.GetTemporaryBonus(character, definition.id), definition.max)
end

function ix.vtm.stats.GetUnspent(character, category)
	return math.max(tonumber(ix.vtm.stats.GetData(character).unspent[category]) or 0, 0)
end

function ix.vtm.stats.GetPool(character, ...)
	local total = 0
	for i = 1, select("#", ...) do total = total + ix.vtm.stats.Get(character, select(i, ...)) end
	return total
end

if (SERVER) then
	function ix.vtm.stats.SetData(character, data, saveNow)
		if (!character or !character.SetAfterlightVTMStats) then return false, "invalidCharacter" end
		character:SetAfterlightVTMStats(ix.vtm.stats.Normalize(data))
		if (saveNow) then character:Save() end
		return true
	end

	function ix.vtm.stats.Migrate(character)
		if (!character) then return false end
		local raw = character:GetAfterlightVTMStats()
		local oldVersion = istable(raw) and tonumber(raw.version) or 0
		if (oldVersion >= 2) then return true, false end
		local data = ix.vtm.stats.Normalize(raw)
		local isVampire = character.IsVampire and character:IsVampire()

		if (oldVersion == 1) then
			-- Preserve all v1.0 admin adjustments and add only the budget delta.
			if (data.vampireBonusGranted) then
				data.unspent.attributes = data.unspent.attributes + 3 -- 12 old -> 15 new
				data.unspent.abilities = data.unspent.abilities + 9  -- 16 old -> 25 new
			else
				data.unspent.attributes = data.unspent.attributes + 5 -- 7 -> 12
				data.unspent.abilities = data.unspent.abilities + 7  -- 10 -> 17
			end
			data.unspent.virtues = data.unspent.virtues + 7
		else
			data.unspent.attributes = ix.vtm.stats.CREATION_POINTS.attributes
			data.unspent.abilities = ix.vtm.stats.CREATION_POINTS.abilities
			data.unspent.virtues = ix.vtm.stats.CREATION_POINTS.virtues
			if (isVampire) then
				data.unspent.attributes = data.unspent.attributes + ix.vtm.stats.VAMPIRE_BONUS.attributes
				data.unspent.abilities = data.unspent.abilities + ix.vtm.stats.VAMPIRE_BONUS.abilities
				data.vampireBonusGranted = true
			end
		end
		ix.vtm.stats.SetData(character, data, true)
		return true, true
	end

	function ix.vtm.stats.GetDisciplineCapacity(character)
		local capacity = 0
		for id, entry in pairs(ix.disciplines.GetCharacterData(character)) do
			local definition = ix.disciplines.Get(id)
			if (definition) then capacity = capacity + math.max(definition.maxLevel - entry.level, 0) end
		end
		return capacity
	end

	function ix.vtm.stats.AddPoints(character, category, amount, source)
		if (!table.HasValue(ix.vtm.stats.POINT_CATEGORIES, category)) then return false, "invalidCategory" end
		amount = math.floor(tonumber(amount) or 0)
		local data = ix.vtm.stats.GetData(character)
		local old = data.unspent[category]
		local updated = math.max(old + amount, 0)

		if (category == "disciplines") then
			if (!character.IsVampire or !character:IsVampire()) then return false, "notVampire" end
			local capacity = ix.vtm.stats.GetDisciplineCapacity(character)
			if (capacity <= 0 and amount > 0) then return false, "noDisciplineCapacity" end
			updated = math.min(updated, capacity)
		end

		data.unspent[category] = updated
		ix.vtm.stats.SetData(character, data, true)
		hook.Run("OnVTMStatPointsChanged", character, category, old, updated, source)
		return true, updated
	end

	function ix.vtm.stats.Reset(character, actor)
		if (!character) then return false, "invalidCharacter" end
		local isVampire = character.IsVampire and character:IsVampire()
		local oldData = ix.vtm.stats.GetData(character)
		local data = ix.vtm.stats.Normalize({})
		data.unspent.attributes = ix.vtm.stats.CREATION_POINTS.attributes +
			(isVampire and ix.vtm.stats.VAMPIRE_BONUS.attributes or 0)
		data.unspent.abilities = ix.vtm.stats.CREATION_POINTS.abilities +
			(isVampire and ix.vtm.stats.VAMPIRE_BONUS.abilities or 0)
		data.unspent.virtues = ix.vtm.stats.CREATION_POINTS.virtues
		-- Discipline enrollment, levels and their free pool are administered
		-- separately and survive an ordinary stat-sheet reset.
		data.unspent.disciplines = isVampire and (oldData.unspent.disciplines or 0) or 0
		data.vampireBonusGranted = isVampire
		data.creationConfirmed = true
		ix.vtm.stats.SetData(character, data, true)
		hook.Run("OnCharacterVTMStatsReset", character, actor, data)
		return true, data
	end

	function ix.vtm.stats.SpendPoint(character, id, source)
		local definition = ix.vtm.stats.GetDefinition(id)
		if (!definition) then return false, "invalidStat" end
		local data = ix.vtm.stats.GetData(character)
		local id2, category = definition.id, definition.category
		if (definition.vampireOnly and (!character.IsVampire or !character:IsVampire())) then
			return false, "vampireOnly"
		end
		local old = data.values[id2]
		if (old >= definition.max) then return false, "atMaximum" end
		if (data.unspent[category] <= 0) then return false, "noPoints" end
		if (hook.Run("CanCharacterIncreaseVTMStat", character, id2, old, old + 1, source) == false) then return false, "notAllowed" end
		data.values[id2] = old + 1
		data.unspent[category] = data.unspent[category] - 1
		ix.vtm.stats.SetData(character, data, true)
		hook.Run("OnCharacterVTMStatChanged", character, id2, old, old + 1, source)
		return true, old + 1, data.unspent[category]
	end

	function ix.vtm.stats.Commit(character, proposedValues, source, proposedDisciplines)
		if (!character or !istable(proposedValues)) then return false, "invalidData" end
		proposedDisciplines = istable(proposedDisciplines) and proposedDisciplines or {}
		local data = ix.vtm.stats.GetData(character)
		local increases = {attributes = 0, abilities = 0, virtues = 0, disciplines = 0}
		local prepared = {}

		for _, id in ipairs(ix.vtm.stats.order) do
			local definition = ix.vtm.stats.list[id]
			local old = data.values[id]
			local proposed = tonumber(proposedValues[id]) or old
			if (proposed % 1 != 0 or proposed < old or proposed > definition.max) then
				return false, "invalidIncrease"
			end
			if (definition.vampireOnly and proposed > definition.base and
				(!character.IsVampire or !character:IsVampire())) then
				return false, "vampireOnly"
			end
			prepared[id] = proposed
			increases[definition.category] = increases[definition.category] + proposed - old
		end

		local disciplineData = ix.disciplines.GetCharacterData(character)
		local preparedDisciplines = table.Copy(disciplineData)
		for rawID, rawLevel in pairs(proposedDisciplines) do
			local id = ix.disciplines.ResolveID(rawID)
			if (!disciplineData[id] and tonumber(rawLevel) and tonumber(rawLevel) > 0) then
				return false, "disciplineNotGranted"
			end
		end
		for id, entry in pairs(disciplineData) do
			local definition = ix.disciplines.Get(id)
			local old = entry.level
			local proposed = tonumber(proposedDisciplines[id]) or old
			if (!definition or proposed % 1 != 0 or proposed < old or proposed > definition.maxLevel) then
				return false, "invalidDisciplineIncrease"
			end
			if (proposed != old and hook.Run("CanCharacterSetDiscipline", character, id,
				proposed, old, source and source.client, source) == false) then
				return false, "disciplineNotAllowed"
			end
			preparedDisciplines[id].level = proposed
			increases.disciplines = increases.disciplines + proposed - old
		end

		for _, category in ipairs(ix.vtm.stats.POINT_CATEGORIES) do
			if (increases[category] > data.unspent[category]) then return false, "noPoints" end
			if (increases[category] < data.unspent[category]) then return false, "unspentPoints" end
		end
		if (hook.Run("CanCharacterCommitVTMStats", character, prepared, increases, source,
			preparedDisciplines) == false) then return false, "notAllowed" end

		for _, id in ipairs(ix.vtm.stats.order) do
			local old, new = data.values[id], prepared[id]
			data.values[id] = new
			if (new != old) then hook.Run("OnCharacterVTMStatChanged", character, id, old, new, source) end
		end
		for _, category in ipairs(ix.vtm.stats.POINT_CATEGORIES) do
			data.unspent[category] = data.unspent[category] - increases[category]
		end
		ix.vtm.stats.SetData(character, data, true)
		character:SetVampireDisciplines(preparedDisciplines)
		for id, entry in pairs(disciplineData) do
			local newLevel = preparedDisciplines[id].level
			if (newLevel != entry.level) then
				hook.Run("OnCharacterDisciplineChanged", character, id, entry.level, newLevel,
					source and source.client, source)
			end
		end
		hook.Run("OnCharacterVTMStatsCommitted", character, increases, source)
		return true, data
	end

	function ix.vtm.stats.Set(character, id, value, actor)
		local definition = ix.vtm.stats.GetDefinition(id)
		if (!definition) then return false, "invalidStat" end
		local data = ix.vtm.stats.GetData(character)
		local old = data.values[definition.id]
		value = math.Clamp(math.floor(tonumber(value) or old), definition.base, definition.max)
		if (definition.vampireOnly and value > definition.base and
			(!character.IsVampire or !character:IsVampire())) then return false, "vampireOnly" end
		data.values[definition.id] = value
		ix.vtm.stats.SetData(character, data, true)
		hook.Run("OnCharacterVTMStatChanged", character, definition.id, old, value, {admin = actor})
		return true, value
	end
end
