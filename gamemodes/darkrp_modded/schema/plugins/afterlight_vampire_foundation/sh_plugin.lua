local PLUGIN = PLUGIN

PLUGIN.name = "Afterlight Vampire Foundation"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Vampire species/races, sect factions, roles, generation and controlled whitelist foundation."
PLUGIN.version = "1.10"

ix.lang.AddTable("russian", {
	vampireNoAssignment = "Для этой секты вам не назначены раса/клан и поколение.",
	vampireInvalidRace = "Указана неизвестная вампирская раса/клан.",
	vampireInvalidSect = "Указана неизвестная вампирская секта.",
	vampireRoleAppointment = "Эта роль назначается руководством секты.",
	citizenOnlyCreation = "Новых персонажей можно создавать только во фракции Citizen. Вампиризм и секта назначаются после создания администрацией."
})

ix.lang.AddTable("english", {
	vampireNoAssignment = "No vampire race/clan and generation have been assigned for this sect.",
	vampireInvalidRace = "Unknown vampire race/clan.",
	vampireInvalidSect = "Unknown vampire sect.",
	vampireRoleAppointment = "This role must be appointed by sect leadership.",
	citizenOnlyCreation = "New characters can only be created in the Citizen faction. Vampirism and sect are assigned afterwards by administration."
})

local function RegisterVampireFlag(flag, description)
	local existing = ix.flag.list[flag]

	-- Helix keeps a shared flag registry and this shared plugin can be included
	-- again during refresh/reconnect. The foundation only checks possession of
	-- these flags and needs no callback, so an existing entry can be reused.
	if (existing) then
		existing.afterlightVampire = true
		return true
	end

	ix.flag.Add(flag, description)
	ix.flag.list[flag].afterlightVampire = true
	return true
end

RegisterVampireFlag("V", "Персонаж является вампиром.")
RegisterVampireFlag("M", "Персонаж принадлежит Камарилье.")
RegisterVampireFlag("S", "Персонаж принадлежит Шабашу.")
RegisterVampireFlag("A", "Персонаж принадлежит Анархам.")

print("[Vampire Foundation] v1.10 loaded; persistent sect classes are active.")

ix.char.RegisterVar("species", {
	field = "species",
	fieldType = ix.type.string,
	default = "human",
	bNoDisplay = true
})

-- По уточнению владельца схемы расой вампира является его клан.
ix.char.RegisterVar("vampireRace", {
	field = "vampire_race",
	fieldType = ix.type.string,
	default = "",
	bNoDisplay = true,
	OnValidate = function(self, value)
		if (value == nil or value == "") then return end
		value = string.lower(tostring(value))
		if (!ix.vampire.clans.Get(value)) then return false, "vampireInvalidRace" end
		return value
	end
})

ix.char.RegisterVar("generation", {
	field = "vampire_generation",
	fieldType = ix.type.number,
	default = 13,
	bNoDisplay = true,
	OnValidate = function(self, value)
		value = math.floor(tonumber(value) or 13)
		return math.Clamp(value, 5, 15)
	end
})

-- Prepared now, but no discipline behavior is implemented in this foundation.
-- Learned disciplines are independent from native clan disciplines, allowing
-- any clan to receive an out-of-clan discipline later.
ix.char.RegisterVar("vampireDisciplines", {
	field = "vampire_disciplines",
	fieldType = ix.type.text,
	default = {},
	bNoDisplay = true,
	isLocal = true
})

function PLUGIN:GetState()
	local state = self:GetData({apex = {}}, false, true)
	state.apex = state.apex or {}
	return state
end

function PLUGIN:SaveState(state)
	self:SetData(state, false, true)
end

function PLUGIN:GetVampireProfile(client)
	return client:GetData("vampireProfile", nil)
end

function PLUGIN:SetVampireProfile(target, clanID, generation, actor)
	local clan = ix.vampire.clans.Get(clanID)
	if (!clan) then return false, "Неизвестная раса/клан." end

	target:SetData("vampireProfile", {
		clan = clanID,
		generation = math.Clamp(math.floor(tonumber(generation) or 13), 5, 15),
		grantedBy = IsValid(actor) and actor:SteamID64() or "CONSOLE",
		grantedAt = os.time()
	})
	target:SaveData()
	return true
end

function PLUGIN:ClearSectFlags(character)
	character:TakeFlags("MSA")
end

-- Species/race, clan and generation are completely independent from faction.
-- Only server administration is allowed to call this through exposed commands.
function PLUGIN:ApplyVampireProfile(target, clanID, generation)
	local character = target:GetCharacter()
	local clan = ix.vampire.clans.Get(clanID)
	if (!character or !clan) then return false, "Некорректная раса/клан." end

	character:SetSpecies("vampire")
	character:SetVampireRace(clanID)
	character:SetGeneration(math.Clamp(math.floor(tonumber(generation) or 13), 5, 15))
	character:GiveFlags("V")

	local sectID = character:GetVampireSect()
	if (sectID and ix.vampire.sects[sectID]) then
		self:ClearSectFlags(character)
		character:GiveFlags(ix.vampire.sects[sectID].flag)
	end

	hook.Run("OnVampireProfileApplied", target, character, clanID)
	return true
end

local PERSISTENT_CLASS_KEY = "afterlightVampireClass"

-- Helix class is a runtime character variable and is not stored in the
-- ix_characters table by default. Store the stable class uniqueID separately;
-- numeric class indices may change when plugin load order changes.
function PLUGIN:SetPersistentVampireClass(character, classIndex, saveNow)
	if (!character or !character:IsVampire()) then return false, "Цель не является вампиром." end
	local class = ix.class.list[classIndex]
	if (!class or class.faction != character:GetFaction()) then
		return false, "Класс не принадлежит текущей секте персонажа."
	end

	character:SetClass(classIndex)
	character:SetData(PERSISTENT_CLASS_KEY, class.uniqueID)
	if (saveNow != false) then character:Save() end
	hook.Run("OnVampireClassPersisted", character, classIndex, class.uniqueID)
	return true, class
end

function PLUGIN:RestorePersistentVampireClass(character)
	if (!character or !character:IsVampire()) then return false, "notVampire" end
	local sectID = character:GetVampireSect()
	local sect = sectID and ix.vampire.sects[sectID]
	if (!sect) then return false, "missingSect" end

	local storedID = character:GetData(PERSISTENT_CLASS_KEY, nil)
	local classIndex, class
	if (isstring(storedID) and storedID != "") then
		classIndex, class = ix.vampire.GetClassByUniqueID(storedID)
	end

	-- Never restore an apex role unless this exact character still owns the
	-- separately persisted apex slot for its sect.
	if (class and class.uniqueID == sect.apexRole) then
		local state = self:GetState()
		if (tonumber(state.apex[sectID]) != character:GetID()) then
			classIndex, class = nil, nil
		end
	end

	if (!class or class.faction != character:GetFaction()) then
		classIndex, class = ix.vampire.GetDefaultClass(character:GetFaction())
	end
	if (!classIndex or !class) then return false, "missingDefaultClass" end

	local changed = character:GetClass() != classIndex or storedID != class.uniqueID
	character:SetClass(classIndex)
	character:SetData(PERSISTENT_CLASS_KEY, class.uniqueID)
	if (changed) then character:Save() end
	hook.Run("OnVampireClassRestored", character, classIndex, class.uniqueID)
	return true, class
end

-- Faction admission never changes species, clan or generation.
function PLUGIN:ApplySect(target, sectID)
	local character = target:GetCharacter()
	local sect = ix.vampire.sects[sectID]
	local faction = ix.vampire.GetFactionBySect(sectID)
	if (!character or !character:IsVampire()) then return false, "Цель не является вампиром." end
	if (!sect or !faction) then return false, "Неизвестная секта." end
	if (!ix.vampire.clans.IsAllowedInSect(character:GetVampireRace(), sectID)) then return false, "Раса/клан несовместима с сектой." end

	character:SetFaction(faction)
	self:ClearSectFlags(character)
	character:GiveFlags(sect.flag)
	local defaultClass = ix.vampire.GetDefaultClass(faction)
	if (defaultClass) then self:SetPersistentVampireClass(character, defaultClass) end
	hook.Run("OnVampireSectApplied", target, character, sectID)
	return true
end

-- Fully remove vampirism from an active character and return it to Citizen.
-- Kept as a server API so future administration tools can use the same safe path.
function PLUGIN:RemoveVampirism(target, actor)
	if (!IsValid(target)) then return false, "Игрок не найден." end
	local character = target:GetCharacter()
	if (!character) then return false, "У игрока нет активного персонажа." end

	local citizenFaction
	for _, faction in ipairs(ix.faction.indices or {}) do
		if (ix.vampire.IsCitizenFaction(faction.index)) then
			citizenFaction = faction.index
			break
		end
	end
	if (!citizenFaction) then return false, "Стандартная faction Citizen не найдена." end

	local state = self:GetState()
	local changedState = false
	for sectID, characterID in pairs(state.apex) do
		if (tonumber(characterID) == character:GetID()) then
			state.apex[sectID] = nil
			changedState = true
		end
	end
	if (changedState) then self:SaveState(state) end

	character:TakeFlags("VMSA")
	character:SetSpecies("human")
	character:SetVampireRace("")
	character:SetGeneration(13)
	character:SetVampireDisciplines({})
	character:SetFaction(citizenFaction)

	local defaultClass
	for index, class in pairs(ix.class.list or {}) do
		if (class.faction == citizenFaction and class.isDefault) then
			defaultClass = index
			break
		end
	end
	character:SetClass(defaultClass)
	character:SetData(PERSISTENT_CLASS_KEY, nil)

	for _, faction in ipairs(ix.faction.indices or {}) do
		if (faction.vampireSect) then
			target:SetWhitelisted(faction.index, false)
		end
	end

	target:SetData("vampireProfile", nil)
	target:SaveData()
	hook.Run("OnVampirismRemoved", actor, target, character)
	return true
end

function PLUGIN:IsApex(client, sectID)
	if (!IsValid(client) or !client:GetCharacter()) then return false end
	local character = client:GetCharacter()
	if (character:GetVampireSect() != sectID) then return false end

	local state = self:GetState()
	local class = ix.class.list[character:GetClass()]
	return class and class.uniqueID == ix.vampire.sects[sectID].apexRole and
		tonumber(state.apex[sectID]) == character:GetID()
end

function PLUGIN:CanManageSect(client, sectID)
	return IsValid(client) and (client:IsAdmin() or self:IsApex(client, sectID))
end

function PLUGIN:CanUseManagementCommands(client)
	if (!IsValid(client)) then return false end
	if (client:IsAdmin()) then return true end
	local character = client:GetCharacter()
	local sectID = character and character:GetVampireSect()
	if (!sectID) then return false end

	if (CLIENT) then
		local class = ix.class.list[character:GetClass()]
		return class and class.uniqueID == ix.vampire.sects[sectID].apexRole
	end

	return self:IsApex(client, sectID)
end

function PLUGIN:GrantSectWhitelist(actor, target, sectID)
	local faction = ix.vampire.GetFactionBySect(sectID)
	if (!faction or !ix.vampire.sects[sectID]) then return false, "Неизвестная секта." end
	if (!self:CanManageSect(actor, sectID)) then return false, "Вы не управляете этой сектой." end
	if (!self:GetVampireProfile(target)) then return false, "Администрация ещё не выдала игроку вампирскую расу/клан." end

	target:SetWhitelisted(faction, true)
	hook.Run("OnVampireSectWhitelistGranted", actor, target, sectID)
	return true
end

function PLUGIN:CanPlayerCreateCharacter(client, payload)
	-- The public character creator is Citizen-only. Vampire factions are never
	-- valid creation payloads, even if an obsolete Helix whitelist remains in
	-- the player's local data. Administrators convert and transfer afterwards.
	if (!ix.vampire.IsCitizenFaction(payload.faction)) then
		return false, "citizenOnlyCreation"
	end
end

function PLUGIN:AdjustCreationPayload(client, payload, newPayload)
	local sectID = ix.vampire.GetSectByFaction(payload.faction)
	if (!sectID) then return end
	local profile = self:GetVampireProfile(client)
	if (!profile) then return end

	newPayload.species = "vampire"
	newPayload.vampireRace = profile.clan
	newPayload.generation = math.Clamp(math.floor(profile.generation or 13), 5, 15)
	newPayload.vampireDisciplines = {}
end

function PLUGIN:OnCharacterCreated(client, character)
	local sectID = character:GetVampireSect()
	if (!sectID or character:GetSpecies() != "vampire") then return end

	local sect = ix.vampire.sects[sectID]
	self:ClearSectFlags(character)
	character:GiveFlags("V" .. sect.flag)
	local defaultClass = ix.vampire.GetDefaultClass(character:GetFaction())
	if (defaultClass) then self:SetPersistentVampireClass(character, defaultClass) end
end

function PLUGIN:ValidateCharacter(character, repair)
	if (!character:IsVampire()) then return true, {} end
	local issues = {}
	local sectID = character:GetVampireSect()
	local sect = sectID and ix.vampire.sects[sectID]

	if (!character:HasFlags("V")) then issues[#issues + 1] = "missing V flag" end
	if (!sect) then issues[#issues + 1] = "missing vampire sect" end
	if (sect and !character:HasFlags(sect.flag)) then issues[#issues + 1] = "missing sect flag" end
	if (character:GetGeneration() < 5 or character:GetGeneration() > 15) then issues[#issues + 1] = "generation out of range" end
	if (!ix.vampire.clans.Get(character:GetVampireRace())) then issues[#issues + 1] = "invalid vampire race" end

	if (repair and sect) then
		character:SetSpecies("vampire")
		character:SetGeneration(math.Clamp(character:GetGeneration(), 5, 15))
		self:ClearSectFlags(character)
		character:GiveFlags("V" .. sect.flag)
		local class = ix.class.list[character:GetClass()]
		if (!class or class.faction != character:GetFaction()) then
			local defaultClass = ix.vampire.GetDefaultClass(character:GetFaction())
			if (defaultClass) then self:SetPersistentVampireClass(character, defaultClass) end
		end
	end

	return #issues == 0, issues
end

function PLUGIN:PlayerLoadedCharacter(client, character)
	if (!character:IsVampire()) then return end

	-- Run after Helix and other plugins finish their immediate character-load
	-- setup. Otherwise a later default-class assignment can overwrite Sheriff,
	-- Primogen and other persisted roles in the same frame.
	local characterID = character:GetID()
	timer.Simple(0, function()
		if (!IsValid(client)) then return end
		local active = client:GetCharacter()
		if (!active or active:GetID() != characterID or !active:IsVampire()) then return end

		self:RestorePersistentVampireClass(active)
		self:ValidateCharacter(active, true)
	end)
end

local function ResolveRole(roleID)
	local index, class = ix.vampire.GetClassByUniqueID(string.lower(tostring(roleID or "")))
	return index, class
end

ix.command.Add("VampireWhitelist", {
	description = "Административно выдать вампирскую расу/клан и поколение независимо от секты.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.string, bit.bor(ix.type.number, ix.type.optional)},
	OnRun = function(self, client, target, clanID, generation)
		clanID = string.lower(clanID)
		local success, reason = PLUGIN:SetVampireProfile(target, clanID, generation or 13, client)
		if (!success) then return reason end
		return string.format("Игроку %s выдан вампирский профиль; раса/клан: %s; поколение: %d.",
			target:GetName(), ix.vampire.clans.Get(clanID).name,
			math.Clamp(math.floor(generation or 13), 5, 15))
	end
})

ix.command.Add("VampireConvert", {
	description = "Административно превратить активного персонажа, не меняя его faction.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.string, bit.bor(ix.type.number, ix.type.optional)},
	OnRun = function(self, client, target, clanID, generation)
		clanID = string.lower(clanID)
		local saved, reason = PLUGIN:SetVampireProfile(target, clanID, generation or 13, client)
		if (!saved) then return reason end
		local success, applyReason = PLUGIN:ApplyVampireProfile(target, clanID, generation or 13)
		if (!success) then return applyReason end
		return "Персонаж превращён в вампира; его faction не изменена."
	end
})

ix.command.Add("VampireRemove", {
	description = "Полностью убрать вампирский вид у активного персонажа и вернуть его в Citizen.",
	adminOnly = true,
	arguments = ix.type.player,
	OnRun = function(self, client, target)
		local character = target:GetCharacter()
		local name = character and character:GetName() or target:GetName()
		local success, reason = PLUGIN:RemoveVampirism(target, client)
		if (!success) then return reason end
		return string.format("У персонажа %s удалён вампирский вид; персонаж возвращён в Citizen.", name)
	end
})

ix.command.Add("VampireSectWhitelist", {
	description = "Разрешить уже одобренному администрацией вампиру создание персонажа в секте.",
	arguments = {ix.type.player, ix.type.string},
	OnCheckAccess = function(self, client)
		return PLUGIN:CanUseManagementCommands(client)
	end,
	OnRun = function(self, client, target, sectID)
		sectID = string.lower(sectID)
		local success, reason = PLUGIN:GrantSectWhitelist(client, target, sectID)
		if (!success) then return reason end
		return string.format("Игрок %s допущен в секту %s. Его раса и поколение не изменены.",
			target:GetName(), ix.vampire.sects[sectID].name)
	end
})

ix.command.Add("VampireSectSet", {
	description = "Перевести существующего вампира в секту без изменения расы и поколения.",
	arguments = {ix.type.player, ix.type.string},
	OnCheckAccess = function(self, client)
		return PLUGIN:CanUseManagementCommands(client)
	end,
	OnRun = function(self, client, target, sectID)
		sectID = string.lower(sectID)
		if (!PLUGIN:CanManageSect(client, sectID)) then return "Вы не управляете этой сектой." end
		local faction = ix.vampire.GetFactionBySect(sectID)
		if (!faction) then return "Неизвестная секта." end
		target:SetWhitelisted(faction, true)
		local success, reason = PLUGIN:ApplySect(target, sectID)
		if (!success) then return reason end
		return string.format("Персонаж принят в секту %s без изменения расы и поколения.", ix.vampire.sects[sectID].name)
	end
})

ix.command.Add("VampireApex", {
	description = "Назначить административно Князя, Епископа или Барона текущей секты персонажа.",
	adminOnly = true,
	arguments = ix.type.player,
	OnRun = function(self, client, target)
		local character = target:GetCharacter()
		if (!character or !character:IsVampire()) then return "Цель не является вампиром." end
		local sectID = character:GetVampireSect()
		local sect = sectID and ix.vampire.sects[sectID]
		if (!sect) then return "У цели нет вампирской секты." end
		local classIndex = ix.vampire.GetClassByUniqueID(sect.apexRole)
		if (!classIndex) then return "Класс высшей роли не найден." end

		local state = PLUGIN:GetState()
		local previousID = tonumber(state.apex[sectID])
		if (previousID and previousID != character:GetID()) then
			local previous = ix.char.loaded[previousID]
			if (previous) then
				local defaultClass = ix.vampire.GetDefaultClass(previous:GetFaction())
				if (defaultClass) then PLUGIN:SetPersistentVampireClass(previous, defaultClass) end
			end
		end

		state.apex[sectID] = character:GetID()
		PLUGIN:SaveState(state)
		PLUGIN:SetPersistentVampireClass(character, classIndex)
		return string.format("%s назначен на высшую роль секты %s.", character:GetName(), sect.name)
	end
})

ix.command.Add("VampireRole", {
	description = "Назначить роль вампиру. Высшие роли назначаются только через /VampireApex.",
	arguments = {ix.type.player, ix.type.string},
	OnCheckAccess = function(self, client)
		return PLUGIN:CanUseManagementCommands(client)
	end,
	OnRun = function(self, client, target, roleID)
		local character = target:GetCharacter()
		if (!character or !character:IsVampire()) then return "Цель не является вампиром." end
		local sectID = character:GetVampireSect()
		if (!PLUGIN:CanManageSect(client, sectID)) then return "Вы не управляете этой сектой." end

		local classIndex, class = ResolveRole(roleID)
		if (!classIndex or class.faction != character:GetFaction()) then return "Роль не существует в секте цели." end
		if (class.uniqueID == ix.vampire.sects[sectID].apexRole) then return "Высшую роль назначает только администрация." end
		local persisted, persistReason = PLUGIN:SetPersistentVampireClass(character, classIndex)
		if (!persisted) then return persistReason end
		return string.format("%s получил роль %s.", character:GetName(), class.name)
	end
})

ix.command.Add("VampireClan", {
	description = "Административно изменить расу/клан существующего вампира.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.string},
	OnRun = function(self, client, target, clanID)
		local character = target:GetCharacter()
		if (!character or !character:IsVampire()) then return "Цель не является вампиром." end
		local sectID = character:GetVampireSect()
		clanID = string.lower(clanID)
		if (!ix.vampire.clans.Get(clanID)) then return "Неизвестная раса/клан." end
		if (sectID and !ix.vampire.clans.IsAllowedInSect(clanID, sectID)) then return "Раса/клан несовместима с сектой." end
		character:SetVampireRace(clanID)
		return string.format("Раса/клан %s изменена на %s.", character:GetName(), ix.vampire.clans.Get(clanID).name)
	end
})

ix.command.Add("VampireRoleClear", {
	description = "Вернуть вампира в класс секты по умолчанию.",
	arguments = ix.type.player,
	OnCheckAccess = function(self, client)
		return PLUGIN:CanUseManagementCommands(client)
	end,
	OnRun = function(self, client, target)
		local character = target:GetCharacter()
		if (!character or !character:IsVampire()) then return "Цель не является вампиром." end
		local sectID = character:GetVampireSect()
		if (!PLUGIN:CanManageSect(client, sectID)) then return "Вы не управляете этой сектой." end
		local defaultClass = ix.vampire.GetDefaultClass(character:GetFaction())
		if (!defaultClass) then return "Класс по умолчанию не найден." end
		local persisted, persistReason = PLUGIN:SetPersistentVampireClass(character, defaultClass)
		if (!persisted) then return persistReason end
		return "Персонаж возвращён в класс секты по умолчанию."
	end
})

ix.command.Add("VampireGeneration", {
	description = "Установить поколение вампира от 5 до 14.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.number},
	OnRun = function(self, client, target, generation)
		local character = target:GetCharacter()
		if (!character or !character:IsVampire()) then return "Цель не является вампиром." end
		generation = math.Clamp(math.floor(generation), 5, 15)
		character:SetGeneration(generation)
		return string.format("Поколение %s установлено на %d.", character:GetName(), generation)
	end
})

