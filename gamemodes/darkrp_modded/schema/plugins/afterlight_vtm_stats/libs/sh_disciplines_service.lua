ix.disciplines = ix.disciplines or {}

local function ReadLevel(entry)
	if (isnumber(entry)) then return entry end
	if (istable(entry)) then return entry.level end
	return 0
end

function ix.disciplines.Normalize(data)
	local normalized = {}
	if (!istable(data)) then return normalized end

	for rawID, entry in pairs(data) do
		local id = ix.disciplines.ResolveID(rawID)
		local definition = ix.disciplines.Get(id)

		if (definition) then
			local level = math.Clamp(math.floor(tonumber(ReadLevel(entry)) or 0), 0, definition.maxLevel)
			-- Positive legacy entries are enrolled automatically. A zero-level row
			-- exists only when explicitly granted with unlocked=true, preventing old
			-- v1.0 placeholder tables from reappearing.
			local unlocked = level > 0 or (istable(entry) and entry.unlocked == true)
			if (unlocked) then
				local current = normalized[id]
				local powers = istable(entry) and istable(entry.powers) and table.Copy(entry.powers) or {}
				local experience = istable(entry) and math.max(tonumber(entry.experience) or 0, 0) or 0

				if (!current or level > current.level) then
					normalized[id] = {
						level = level,
						experience = experience,
						powers = powers,
						unlocked = true
					}
				end
			end
		end
	end

	return normalized
end

function ix.disciplines.GetCharacterData(character)
	if (!character or !character.GetVampireDisciplines) then return {} end
	return ix.disciplines.Normalize(character:GetVampireDisciplines())
end

function ix.disciplines.GetLevel(character, disciplineID)
	local id = ix.disciplines.ResolveID(disciplineID)
	local entry = ix.disciplines.GetCharacterData(character)[id]
	return entry and entry.level or 0
end

function ix.disciplines.IsGranted(character, disciplineID)
	return ix.disciplines.GetCharacterData(character)[ix.disciplines.ResolveID(disciplineID)] != nil
end

function ix.disciplines.Has(character, disciplineID, minimumLevel)
	minimumLevel = math.Clamp(math.floor(tonumber(minimumLevel) or 1), 1, ix.disciplines.MAX_LEVEL)
	return ix.disciplines.GetLevel(character, disciplineID) >= minimumLevel
end

if (SERVER) then
	function ix.disciplines.SetLevel(character, disciplineID, level, actor, context)
		if (!character or !character.IsVampire or !character:IsVampire()) then
			return false, "notVampire"
		end

		local id = ix.disciplines.ResolveID(disciplineID)
		local definition = ix.disciplines.Get(id)
		if (!definition) then return false, "invalidDiscipline" end

		level = math.Clamp(math.floor(tonumber(level) or 0), 0, definition.maxLevel)
		local existingData = ix.disciplines.GetCharacterData(character)
		if (!existingData[id]) then return false, "notGranted" end
		local oldLevel = existingData[id].level
		if (oldLevel == level) then return true, level, oldLevel end

		if (hook.Run("CanCharacterSetDiscipline", character, id, level, oldLevel, actor, context) == false) then
			return false, "notAllowed"
		end

		local data = ix.disciplines.GetCharacterData(character)
		local oldEntry = data[id] or {}
		data[id] = {
			level = level,
			experience = math.max(tonumber(oldEntry.experience) or 0, 0),
			powers = istable(oldEntry.powers) and table.Copy(oldEntry.powers) or {},
			unlocked = true
		}

		character:SetVampireDisciplines(data)
		hook.Run("OnCharacterDisciplineChanged", character, id, oldLevel, level, actor, context)
		return true, level, oldLevel
	end

	function ix.disciplines.Grant(character, disciplineID, actor, context)
		if (!character or !character.IsVampire or !character:IsVampire()) then return false, "notVampire" end
		local id = ix.disciplines.ResolveID(disciplineID)
		if (!ix.disciplines.Get(id)) then return false, "invalidDiscipline" end
		local data = ix.disciplines.GetCharacterData(character)
		if (data[id]) then return true, false end
		data[id] = {level = 0, experience = 0, powers = {}, unlocked = true}
		character:SetVampireDisciplines(data)
		hook.Run("OnCharacterDisciplineGranted", character, id, actor, context)
		return true, true
	end

	function ix.disciplines.Remove(character, disciplineID, actor, context)
		if (!character or !character.IsVampire or !character:IsVampire()) then return false, "notVampire" end
		local id = ix.disciplines.ResolveID(disciplineID)
		local data = ix.disciplines.GetCharacterData(character)
		local oldEntry = data[id]
		if (!oldEntry) then return false, "notGranted" end
		if (hook.Run("CanCharacterRemoveDiscipline", character, id, oldEntry, actor, context) == false) then
			return false, "notAllowed"
		end
		data[id] = nil
		character:SetVampireDisciplines(data)
		hook.Run("OnCharacterDisciplineRemoved", character, id, oldEntry, actor, context)
		return true
	end

	function ix.disciplines.AddLevel(character, disciplineID, amount, actor, context)
		amount = math.floor(tonumber(amount) or 0)
		return ix.disciplines.SetLevel(character, disciplineID,
			ix.disciplines.GetLevel(character, disciplineID) + amount, actor, context)
	end

	function ix.disciplines.Clear(character, actor, context)
		if (!character or !character.IsVampire or !character:IsVampire()) then
			return false, "notVampire"
		end

		local oldData = ix.disciplines.GetCharacterData(character)
		if (hook.Run("CanCharacterClearDisciplines", character, actor, context) == false) then
			return false, "notAllowed"
		end

		character:SetVampireDisciplines({})
		hook.Run("OnCharacterDisciplinesCleared", character, oldData, actor, context)
		return true
	end
end
