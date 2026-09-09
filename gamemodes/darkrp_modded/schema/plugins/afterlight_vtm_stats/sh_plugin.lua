local PLUGIN = PLUGIN

PLUGIN.name = "Afterlight VTM Character Sheet"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Bloodlines-style categorized attributes and abilities with secure point pools."
PLUGIN.version = "1.10.4"

function PLUGIN:InitializedPlugins()
	if (!ix.vampire or !ix.meta.character.IsVampire or !ix.char.vars.vampireDisciplines) then
		ErrorNoHalt("[Afterlight VTM Stats] afterlight_vampire_foundation is missing or outdated; disciplines are unavailable.\n")
	end
	if (ix.plugin.Get("afterlight_disciplines_core")) then
		ErrorNoHalt("[Afterlight VTM Stats] remove afterlight_disciplines_core: its v1.1 service is integrated into VTM Stats v1.8.\n")
	end
end

ix.lang.AddTable("russian", {
	afterlightVTMStats = "Характеристики и способности",
	vtmStatsInvalid = "Некорректные значения характеристик, способностей или добродетелей.",
	vtmStatsOverspent = "Распределено больше доступного количества очков.",
	vtmStatsNotConfirmed = "Подтвердите распределение очков кнопкой «Подтвердить».",
	vtmStatsUnspent = "Перед подтверждением распределите все очки Характеристик, Способностей и Добродетелей.",
	vtmAwarenessVampireOnly = "Люди не могут развивать способность «Шестое чувство»."
})

ix.lang.AddTable("english", {
	afterlightVTMStats = "Attributes and Abilities",
	vtmStatsInvalid = "Invalid character-sheet values.",
	vtmStatsOverspent = "More points were allocated than available.",
	vtmStatsNotConfirmed = "Confirm the point allocation before creating the character.",
	vtmStatsUnspent = "Allocate every Attribute, Ability and Virtue point before confirming.",
	vtmAwarenessVampireOnly = "Humans cannot develop Sixth Sense."
})

if (SERVER) then
	util.AddNetworkString("AfterlightVTMCommit")
	util.AddNetworkString("AfterlightVTMStatsSync")
	util.AddNetworkString("AfterlightVTMAdminRequest")
	util.AddNetworkString("AfterlightVTMAdminSheet")
	util.AddNetworkString("AfterlightVTMAdminAction")
end

ix.char.RegisterVar("afterlightVTMStats", {
	field = "afterlight_vtm_stats",
	fieldType = ix.type.text,
	default = {},
	isLocal = true,
	category = "attributes",

	OnDisplay = function(self, container, payload)
		if (!CLIENT) then return end
		local data = ix.vtm.stats.BuildCreation(payload.afterlightVTMStats or {})
		payload:Set("afterlightVTMStats", data)

		local sheet = container:Add("AfterlightVTMStatSheet")
		sheet:Dock(TOP)
		sheet:SetMode("creation")
		sheet:SetStatsData(data)
		sheet:SetChangeCallback(function(updated)
			payload:Set("afterlightVTMStats", updated)
		end)
		return sheet
	end,

	OnValidate = function(self, value)
		local valid, result = ix.vtm.stats.ValidateCreation(value)
		if (!valid) then return false, result end
		return result
	end,

	OnAdjust = function(self, client, data, value, newData)
		local valid, normalized = ix.vtm.stats.ValidateCreation(value)
		if (valid) then newData.afterlightVTMStats = normalized end
	end
})

if (CLIENT and ix.char.vars.attributes) then
	-- Replace only the old creation UI. The original data and APIs remain so
	-- legacy plugins do not crash while new gameplay moves to ix.vtm.stats.
	ix.char.vars.attributes.afterlightOldShouldDisplay =
		ix.char.vars.attributes.afterlightOldShouldDisplay or ix.char.vars.attributes.ShouldDisplay
	ix.char.vars.attributes.ShouldDisplay = function()
		return false
	end
end

local function SyncToOwner(character)
	if (!SERVER or !character) then return end
	local client = character:GetPlayer()
	if (!IsValid(client)) then return end
	local isVampire = character.IsVampire and character:IsVampire()
	net.Start("AfterlightVTMStatsSync")
		net.WriteTable(ix.vtm.stats.GetData(character))
		net.WriteTable(isVampire and ix.disciplines.GetCharacterData(character) or {})
	net.Send(client)
end

function PLUGIN:OnCharacterCreated(client, character)
	if (!SERVER) then return end
	local data = ix.vtm.stats.GetData(character)
	-- OnAdjust normally writes version 2; this fallback covers custom creators.
	if (character:GetAfterlightVTMStats().version != 2) then
		data.unspent.attributes = ix.vtm.stats.CREATION_POINTS.attributes
		data.unspent.abilities = ix.vtm.stats.CREATION_POINTS.abilities
		data.unspent.virtues = ix.vtm.stats.CREATION_POINTS.virtues
		ix.vtm.stats.SetData(character, data, true)
	end
end

function PLUGIN:PlayerLoadedCharacter(client, character)
	if (!SERVER) then return end
	ix.vtm.stats.Migrate(character)

	-- Existing vampires receive the conversion bonus once. The migration and
	-- persistent marker prevent cure/re-conversion point farming.
	if (character.IsVampire and character:IsVampire()) then
		self:GrantVampireBonus(character, "legacy_migration")
	else
		local data = ix.vtm.stats.GetData(character)
		local awareness = data.values.awareness or 0
		if (awareness > 0) then
			data.values.awareness = 0
			data.unspent.abilities = data.unspent.abilities + awareness
			ix.vtm.stats.SetData(character, data, true)
		end
	end
	SyncToOwner(character)
end

function PLUGIN:GrantVampireBonus(character, source)
	if (!SERVER or !character or !character.IsVampire or !character:IsVampire()) then return false end
	local data = ix.vtm.stats.GetData(character)
	if (data.vampireBonusGranted) then return true, false end

	data.unspent.attributes = data.unspent.attributes + ix.vtm.stats.VAMPIRE_BONUS.attributes
	data.unspent.abilities = data.unspent.abilities + ix.vtm.stats.VAMPIRE_BONUS.abilities
	data.vampireBonusGranted = true
	ix.vtm.stats.SetData(character, data, true)
	SyncToOwner(character)
	hook.Run("OnVTMVampireBonusGranted", character, source)
	return true, true
end

function PLUGIN:OnVampireProfileApplied(client, character)
	if (SERVER) then self:GrantVampireBonus(character, "vampire_conversion") end
end

function PLUGIN:OnVampirismRemoved(actor, target, character)
	if (!SERVER or !character) then return end
	local data = ix.vtm.stats.GetData(character)
	local awareness = data.values.awareness or 0
	data.unspent.disciplines = 0
	if (awareness > 0) then
		data.values.awareness = 0
		data.unspent.abilities = data.unspent.abilities + awareness
	end
	ix.vtm.stats.SetData(character, data, true)
	-- Foundation has already cleared vampireDisciplines at this point.
	SyncToOwner(character)
end

if (SERVER) then
	local nextRequest = {}
	local function CanRequest(client)
		if ((nextRequest[client] or 0) > CurTime()) then return false end
		nextRequest[client] = CurTime() + 0.15
		return true
	end

	net.Receive("AfterlightVTMCommit", function(_, client)
		if (!CanRequest(client)) then return end
		local values = net.ReadTable()
		local disciplineLevels = net.ReadTable()
		local character = client:GetCharacter()
		if (!character) then return end
		ix.vtm.stats.Commit(character, values, {client = client, interface = "character_tab"},
			disciplineLevels)
		SyncToOwner(character)
	end)

	local function SendAdminSheet(admin, target)
		if (!IsValid(admin) or !admin:IsAdmin() or !IsValid(target)) then return false end
		local character = target:GetCharacter()
		if (!character) then return false end

		local faction = ix.faction.indices[character:GetFaction()]
		local class = ix.class.list[character:GetClass()]
		local isVampire = character.IsVampire and character:IsVampire()
		local clan = isVampire and character.GetVampireClan and character:GetVampireClan() or nil
		local species = character.GetSpecies and character:GetSpecies() or nil
		local overview = {
			faction = faction and faction.name or nil,
			money = character:GetMoney(),
			species = species == "vampire" and "Вампир" or (species == "human" and "Человек" or species),
			clan = clan and clan.name or nil,
			generation = isVampire and character.GetGeneration and character:GetGeneration() or nil,
			class = class and class.name or nil
		}

		net.Start("AfterlightVTMAdminSheet")
			net.WriteString(character:GetName())
			net.WriteTable(ix.vtm.stats.GetData(character))
			net.WriteTable(overview)
			net.WriteTable(isVampire and ix.disciplines.GetCharacterData(character) or {})
			net.WriteEntity(target)
		net.Send(admin)
		return true
	end
	PLUGIN.SendAdminSheet = SendAdminSheet

	net.Receive("AfterlightVTMAdminRequest", function(_, client)
		if (!CanRequest(client) or !client:IsAdmin()) then return end
		SendAdminSheet(client, net.ReadEntity())
	end)

	net.Receive("AfterlightVTMAdminAction", function(_, client)
		if (!CanRequest(client) or !client:IsAdmin()) then return end
		local action = net.ReadString()
		local target = net.ReadEntity()
		if (!IsValid(target)) then return end
		local character = target:GetCharacter()
		if (!character) then return end

		local success, reason
		if (action == "add") then
			local category = net.ReadString()
			local amount = math.Clamp(math.floor(net.ReadUInt(8)), 1, 100)
			success, reason = ix.vtm.stats.AddPoints(character, category, amount,
				{admin = client, interface = "admin_sheet"})
		elseif (action == "reset") then
			-- Ordinary sheet reset intentionally preserves enrolled disciplines,
			-- their levels and their currently free discipline pool.
			success, reason = ix.vtm.stats.Reset(character, client)
		elseif (action == "discipline_grant") then
			success, reason = ix.disciplines.Grant(character, net.ReadString(), client,
				{interface = "admin_sheet"})
		elseif (action == "discipline_remove") then
			success, reason = ix.disciplines.Remove(character, net.ReadString(), client,
				{interface = "admin_sheet"})
		elseif (action == "discipline_clear") then
			success, reason = ix.disciplines.Clear(character, client, {interface = "admin_sheet"})
		else
			return
		end
		if (success == false) then client:Notify("Изменение отклонено: " .. tostring(reason)) end

		SyncToOwner(character)
		SendAdminSheet(client, target)
	end)

	hook.Add("PlayerDisconnected", "AfterlightVTMClearRateLimit", function(client)
		nextRequest[client] = nil
	end)
else
	net.Receive("AfterlightVTMStatsSync", function()
		local data = net.ReadTable()
		local disciplineData = net.ReadTable()
		local character = LocalPlayer():GetCharacter()
		if (character) then
			character.vars.afterlightVTMStats = data
			character.vars.vampireDisciplines = disciplineData
			ix.vtm.stats.RefreshOpenSheets(character, data, disciplineData)
		end
	end)

	net.Receive("AfterlightVTMAdminSheet", function()
		ix.vtm.stats.OpenAdminSheet(net.ReadString(), net.ReadTable(), net.ReadTable(),
			net.ReadTable(), net.ReadEntity())
	end)
end

ix.command.Add("VTMCharacterSheet", {
	description = "Открыть полный VTM-лист активного персонажа в режиме просмотра.",
	adminOnly = true,
	arguments = ix.type.player,
	OnRun = function(self, client, target)
		if (!PLUGIN.SendAdminSheet or !PLUGIN.SendAdminSheet(client, target)) then
			return "Не удалось открыть лист: у цели нет активного персонажа."
		end
	end
})

ix.command.Add("VTMStats", {
	description = "Показать VTM-характеристики и способности активного персонажа.",
	adminOnly = true,
	arguments = ix.type.player,
	OnRun = function(self, client, target)
		local character = target:GetCharacter()
		if (!character) then return "У игрока нет активного персонажа." end
		local data = ix.vtm.stats.GetData(character)
		return string.format("%s: свободно характеристик %d, способностей %d, добродетелей %d, дисциплин %d.",
			character:GetName(), data.unspent.attributes, data.unspent.abilities,
			data.unspent.virtues, data.unspent.disciplines)
	end
})

ix.command.Add("VTMStatSet", {
	description = "Административно установить параметр VTM от базового значения до 5.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.string, ix.type.number},
	OnRun = function(self, client, target, id, value)
		local character = target:GetCharacter()
		if (!character) then return "У игрока нет активного персонажа." end
		local success, result = ix.vtm.stats.Set(character, id, value, client)
		if (!success) then return "Изменение отклонено: " .. tostring(result) end
		SyncToOwner(character)
		return string.format("%s: %s установлено на %d/5.", character:GetName(), id, result)
	end
})

ix.command.Add("VTMPointsAdd", {
	description = "Добавить нераспределённые очки: attributes, abilities, virtues или disciplines.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.string, ix.type.number},
	OnRun = function(self, client, target, category, amount)
		local character = target:GetCharacter()
		if (!character) then return "У игрока нет активного персонажа." end
		category = string.lower(category)
		local success, result = ix.vtm.stats.AddPoints(character, category, amount, {admin = client})
		if (!success) then return "Изменение отклонено: " .. tostring(result) end
		SyncToOwner(character)
		return string.format("%s: свободные очки %s = %d.", character:GetName(), category, result)
	end
})

local function ResolveDisciplineTarget(target)
	local character = IsValid(target) and target:GetCharacter()
	if (!character) then return nil, "У игрока нет активного персонажа." end
	if (!character.IsVampire or !character:IsVampire()) then return nil, "Цель не является вампиром." end
	return character
end

local function ResolveDiscipline(id)
	local definition = ix.disciplines.Get(id)
	if (!definition) then return nil, "Неизвестная дисциплина. Используйте /DisciplineCatalog." end
	return definition
end

ix.command.Add("DisciplineCatalog", {
	description = "Показать зарегистрированные ID дисциплин.",
	adminOnly = true,
	OnRun = function(self, client)
		local output = {}
		for _, id in ipairs(ix.disciplines.order) do
			local definition = ix.disciplines.list[id]
			output[#output + 1] = string.format("%s — %s", id, definition.name)
		end
		return table.concat(output, "; ")
	end
})

ix.command.Add("DisciplineList", {
	description = "Показать дисциплины активного вампира.",
	adminOnly = true,
	arguments = ix.type.player,
	OnRun = function(self, client, target)
		local character, reason = ResolveDisciplineTarget(target)
		if (!character) then return reason end
		local output = {}
		local disciplineData = ix.disciplines.GetCharacterData(character)
		for _, id in ipairs(ix.disciplines.order) do
			local entry = disciplineData[id]
			if (entry) then
				output[#output + 1] = string.format("%s: %d/%d", ix.disciplines.list[id].name,
					entry.level, ix.disciplines.MAX_LEVEL)
			end
		end
		return #output > 0 and table.concat(output, "; ") or "У персонажа нет выданных дисциплин."
	end
})

ix.command.Add("DisciplineGrant", {
	description = "Добавить вампиру дисциплину с начальным уровнем 0.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.string},
	OnRun = function(self, client, target, disciplineID)
		local character, reason = ResolveDisciplineTarget(target)
		if (!character) then return reason end
		local definition, definitionReason = ResolveDiscipline(disciplineID)
		if (!definition) then return definitionReason end
		local success, added = ix.disciplines.Grant(character, definition.id, client,
			{command = "DisciplineGrant"})
		if (!success) then return "Выдача отклонена: " .. tostring(added) end
		return added and string.format("%s: дисциплина «%s» добавлена с уровнем 0.",
			character:GetName(), definition.name) or "Эта дисциплина уже находится в чарлисте."
	end
})

ix.command.Add("DisciplineRemove", {
	description = "Полностью удалить выбранную дисциплину из чарлиста вампира.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.string},
	OnRun = function(self, client, target, disciplineID)
		local character, reason = ResolveDisciplineTarget(target)
		if (!character) then return reason end
		local definition, definitionReason = ResolveDiscipline(disciplineID)
		if (!definition) then return definitionReason end
		local success, removeReason = ix.disciplines.Remove(character, definition.id, client,
			{command = "DisciplineRemove"})
		if (!success) then return "Удаление отклонено: " .. tostring(removeReason) end
		return string.format("%s: дисциплина «%s» удалена из чарлиста.",
			character:GetName(), definition.name)
	end
})

ix.command.Add("DisciplineSet", {
	description = "Административно установить уровень уже добавленной дисциплины от 0 до 5.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.string, ix.type.number},
	OnRun = function(self, client, target, disciplineID, level)
		local character, reason = ResolveDisciplineTarget(target)
		if (!character) then return reason end
		local definition, definitionReason = ResolveDiscipline(disciplineID)
		if (!definition) then return definitionReason end
		local success, value = ix.disciplines.SetLevel(character, definition.id, level, client,
			{command = "DisciplineSet"})
		if (!success) then return "Изменение отклонено: " .. tostring(value) end
		SyncToOwner(character)
		return string.format("%s: дисциплина «%s» установлена на %d/%d.",
			character:GetName(), definition.name, value, definition.maxLevel)
	end
})

ix.command.Add("DisciplineAdd", {
	description = "Добавить уровни дисциплины вампира; итог ограничен 0–5.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.string, ix.type.number},
	OnRun = function(self, client, target, disciplineID, amount)
		local character, reason = ResolveDisciplineTarget(target)
		if (!character) then return reason end
		local definition, definitionReason = ResolveDiscipline(disciplineID)
		if (!definition) then return definitionReason end
		local success, value = ix.disciplines.AddLevel(character, definition.id, amount, client,
			{command = "DisciplineAdd"})
		if (!success) then return "Изменение отклонено: " .. tostring(value) end
		SyncToOwner(character)
		return string.format("%s: дисциплина «%s» теперь %d/%d.",
			character:GetName(), definition.name, value, definition.maxLevel)
	end
})

ix.command.Add("DisciplineClear", {
	description = "Удалить все дисциплины вампира.",
	adminOnly = true,
	arguments = ix.type.player,
	OnRun = function(self, client, target)
		local character, reason = ResolveDisciplineTarget(target)
		if (!character) then return reason end
		local success, clearReason = ix.disciplines.Clear(character, client, {command = "DisciplineClear"})
		if (!success) then return "Сброс отклонён: " .. tostring(clearReason) end
		SyncToOwner(character)
		return string.format("Все дисциплины персонажа %s удалены.", character:GetName())
	end
})

if (SERVER) then
	ix.log.AddType("disciplineSet", function(client, targetName, disciplineID, oldLevel, newLevel)
		return string.format("%s changed %s discipline %s from %d to %d.", client:Name(),
			targetName, disciplineID, oldLevel, newLevel)
	end)
end

function PLUGIN:OnCharacterDisciplineChanged(character, disciplineID, oldLevel, newLevel, actor, context)
	if (!SERVER) then return end
	if (IsValid(actor)) then
		ix.log.Add(actor, "disciplineSet", character:GetName(), disciplineID, oldLevel, newLevel)
	end
	-- The unified commit sends one final sync after all rows; direct future API
	-- mutations still refresh the owner here.
	if (!context or context.interface != "character_tab") then SyncToOwner(character) end
end

function PLUGIN:OnCharacterDisciplineGranted(character)
	if (SERVER) then SyncToOwner(character) end
end

function PLUGIN:OnCharacterDisciplineRemoved(character)
	if (!SERVER) then return end
	local data = ix.vtm.stats.GetData(character)
	-- Never leave more free points than the remaining enrolled rows can accept.
	data.unspent.disciplines = math.min(data.unspent.disciplines or 0,
		ix.vtm.stats.GetDisciplineCapacity(character))
	ix.vtm.stats.SetData(character, data, true)
	SyncToOwner(character)
end

function PLUGIN:OnCharacterDisciplinesCleared(character)
	if (!SERVER) then return end
	local data = ix.vtm.stats.GetData(character)
	data.unspent.disciplines = 0
	ix.vtm.stats.SetData(character, data, true)
	SyncToOwner(character)
end

print("[Afterlight VTM Stats] v1.10.3 loaded; live Health fraction is forced into the expanded bar.")
