local PLUGIN = PLUGIN

PLUGIN.name = "Afterlight Vampire Abilities"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Universal regeneration and blood enhancement for every vampire."
PLUGIN.version = "1.2.4"

local DISCIPLINE_ID = "vampire_abilities"
local BUFF_END_KEY = "afterlightBloodBuffEnd"
local BUFF_HEALTH_KEY = "afterlightBloodBuffHealth"
local BUFF_STATS = {strength = true, dexterity = true, stamina = true}

local BANDS = {
	{minimum = 12, maximum = 15, regeneration = {cost = 4, heal = 20, ticks = 8}, buff = {cost = 5, health = 30}},
	{minimum = 8, maximum = 11, regeneration = {cost = 8, heal = 20, ticks = 12}, buff = {cost = 9, health = 50}},
	{minimum = 5, maximum = 7, regeneration = {cost = 12, heal = 30, ticks = 15}, buff = {cost = 12, health = 70}}
}

local function GetBand(character)
	local generation = character and math.floor(tonumber(character:GetGeneration()) or 0) or 0
	for _, band in ipairs(BANDS) do
		if (generation >= band.minimum and generation <= band.maximum) then return band end
	end
end

local function CanAccess(character)
	return character and character.IsVampire and character:IsVampire() and GetBand(character) != nil
end

local function InstallStatsCompatibility()
	if (!ix.vtm or !ix.vtm.stats or !isfunction(ix.vtm.stats.Get)) then return false end
	if (!isfunction(ix.vtm.stats.GetBase)) then
		-- VTM Stats v1.8 Get is the stored/base accessor. Preserve it once and
		-- layer temporary gameplay values over it without mutating character data.
		ix.vtm.stats.afterlightBaseGet = ix.vtm.stats.afterlightBaseGet or ix.vtm.stats.Get
		function ix.vtm.stats.GetBase(character, statID)
			return ix.vtm.stats.afterlightBaseGet(character, statID)
		end
	end
	if (!isfunction(ix.vtm.stats.GetTemporaryBonus)) then
		function ix.vtm.stats.GetTemporaryBonus(character, statID)
			local definition = ix.vtm.stats.GetDefinition(statID)
			if (!definition) then return 0 end
			local bonus = hook.Run("GetCharacterVTMStatBonus", character, definition.id, definition)
			return math.max(math.floor(tonumber(bonus) or 0), 0)
		end
	end
	if (!ix.vtm.stats.afterlightEffectiveGetInstalled) then
		function ix.vtm.stats.Get(character, statID)
			local definition = ix.vtm.stats.GetDefinition(statID)
			if (!definition) then return 0 end
			return math.min(ix.vtm.stats.GetBase(character, definition.id) +
				ix.vtm.stats.GetTemporaryBonus(character, definition.id), definition.max)
		end
		ix.vtm.stats.afterlightEffectiveGetInstalled = true
	end
	return true
end

local function InstallV18SheetCompatibility()
	if (!CLIENT or !vgui) then return true end
	local rowControl = vgui.GetControlTable("AfterlightVTMStatRow")
	local sheetControl = vgui.GetControlTable("AfterlightVTMStatSheet")
	if (!rowControl or !sheetControl) then return false end
	if (isfunction(sheetControl.SetTemporaryBonuses)) then return true end

	local function ApplyTemporaryPaint(row)
		if (!row or !row.dots) then return end
		for _, dot in ipairs(row.dots) do
			dot.Paint = function(button, width, height)
				local active = button.index <= (row.value or 0)
				local temporary = active and button.afterlightTemporary == true
				local color = temporary and Color(35, 115, 220) or
					(active and Color(142, 8, 28) or Color(20, 18, 19))
				if (button:IsHovered()) then
					color = temporary and Color(70, 155, 255) or
						(active and Color(190, 18, 43) or Color(80, 68, 68))
				end
				draw.NoTexture()
				surface.SetDrawColor(color)
				surface.DrawCircle(width * 0.5, height * 0.5, math.min(width, height) * 0.30,
					color.r, color.g, color.b, 255)
				surface.SetDrawColor(210, 198, 185, 190)
				surface.DrawOutlinedRect(2, 2, width - 4, height - 4, 1)
			end
		end
	end

	local originalRowInit = rowControl.Init
	function rowControl:Init()
		originalRowInit(self)
		self.baseValue = self.value or 0
		ApplyTemporaryPaint(self)
	end

	function rowControl:SetValue(value, temporaryBonus)
		self.baseValue = math.Clamp(math.floor(tonumber(value) or 0), 0, ix.vtm.stats.MAX_VALUE)
		local bonus = math.max(math.floor(tonumber(temporaryBonus) or 0), 0)
		self.value = math.min(self.baseValue + bonus, ix.vtm.stats.MAX_VALUE)
		for _, dot in ipairs(self.dots or {}) do
			dot.afterlightTemporary = bonus > 0 and dot.index > self.baseValue and dot.index <= self.value
		end
	end

	function sheetControl:SetTemporaryBonuses(bonuses)
		self.temporaryBonuses = istable(bonuses) and table.Copy(bonuses) or {}
		for _, statID in ipairs(ix.vtm.stats.order) do
			local row = self.rows and self.rows[statID]
			if (IsValid(row)) then
				ApplyTemporaryPaint(row)
				row:SetValue(self.data.values[statID], self.temporaryBonuses[statID])
			end
		end
	end

	local originalSetStatsData = sheetControl.SetStatsData
	function sheetControl:SetStatsData(data, preserveDraft)
		originalSetStatsData(self, data, preserveDraft)
		local character = ix.vtm.stats.openSheets and ix.vtm.stats.openSheets[self]
		if (character) then self:SetTemporaryBonuses(ix.vtm.stats.BuildTemporaryBonuses(character)) end
	end

	function ix.vtm.stats.BuildTemporaryBonuses(character)
		local bonuses = {}
		for _, statID in ipairs(ix.vtm.stats.order) do
			local bonus = ix.vtm.stats.GetTemporaryBonus(character, statID)
			if (bonus > 0) then bonuses[statID] = bonus end
		end
		return bonuses
	end

	function ix.vtm.stats.RefreshTemporaryBonuses(character)
		local bonuses = ix.vtm.stats.BuildTemporaryBonuses(character)
		for sheet, trackedCharacter in pairs(ix.vtm.stats.openSheets or {}) do
			if (IsValid(sheet) and trackedCharacter == character and sheet.SetTemporaryBonuses) then
				sheet:SetTemporaryBonuses(bonuses)
			end
		end
	end

	hook.Add("AfterlightVTMTemporaryBonusesChanged", "AfterlightV18TemporaryDots", function(character)
		if (character) then ix.vtm.stats.RefreshTemporaryBonuses(character) end
	end)
	return true
end

local function RegisterPowers()
	if (!ix.disciplines or !ix.disciplines.RegisterInterfaceDiscipline or !ix.disciplines.RegisterPower) then
		return false
	end

	ix.disciplines.RegisterInterfaceDiscipline(DISCIPLINE_ID, {
		name = "Вампирские способности",
		description = "Неотъемлемые проявления вампирской крови.",
		icon = "afterlight/disciplines/icons/vampire_abilities.png",
		maxLevel = 1,
		CanAccess = CanAccess,
		GetLevel = function(character) return CanAccess(character) and 1 or 0 end
	})

	ix.disciplines.RegisterPower(DISCIPLINE_ID, "regeneration", {
		name = "Регенерация",
		description = "Кровь заставляет раны неестественно затягиваться.",
		level = 1,
		cooldown = 10,
		GetVitaeCost = function(context)
			local band = GetBand(context.character)
			return band and band.regeneration.cost or 0
		end,
		CanActivate = function(context) return GetBand(context.character) != nil, "notAllowed" end,
		OnActivate = function(context) return PLUGIN:ActivateRegeneration(context) end
	})

	ix.disciplines.RegisterPower(DISCIPLINE_ID, "blood_enhancement", {
		name = "Усиление крови",
		description = "На время укрепляет тело и ускоряет рефлексы.",
		level = 1,
		cooldown = 200,
		GetVitaeCost = function(context)
			local band = GetBand(context.character)
			return band and band.buff.cost or 0
		end,
		CanActivate = function(context)
			return GetBand(context.character) != nil and !PLUGIN:IsBuffActive(context.client), "notAllowed"
		end,
		OnActivate = function(context) return PLUGIN:ActivateBloodEnhancement(context) end
	})

	return true
end

-- This call supports safe hot reload when dependencies are already active.
-- During a cold boot the ability plugin can load alphabetically before them;
-- InitializedPlugins below performs the authoritative registration afterwards.
RegisterPowers()

function PLUGIN:InitializedPlugins()
	local interfacePlugin = ix.plugin.Get("afterlight_discipline_interface")
	local statsPlugin = ix.plugin.Get("afterlight_vtm_stats")
	local vitaePlugin = ix.plugin.Get("afterlight_vitae")
	local hasInterfaceAPI = ix.disciplines and
		isfunction(ix.disciplines.RegisterInterfaceDiscipline) and
		isfunction(ix.disciplines.GetInterfaceDiscipline) and
		isfunction(ix.disciplines.CanAccessInterfaceDiscipline) and
		isfunction(ix.disciplines.GetAccessibleInterfaceDisciplines) and
		isfunction(ix.disciplines.CanAccessPower)

	if (!interfacePlugin) then
		ErrorNoHalt("[Afterlight Vampire Abilities] afterlight_discipline_interface plugin is missing.\n")
		return
	end

	if (!hasInterfaceAPI) then
		ErrorNoHalt("[Afterlight Vampire Abilities] Discipline Interface is loaded, but its virtual-discipline API is missing. Install the supplied compatible Interface update.\n")
		return
	end

	if (!statsPlugin) then
		ErrorNoHalt("[Afterlight Vampire Abilities] afterlight_vtm_stats plugin is missing.\n")
		return
	end

	if (!InstallStatsCompatibility()) then
		ErrorNoHalt("[Afterlight Vampire Abilities] VTM Stats base API is unavailable.\n")
		return
	end

	if (CLIENT and !InstallV18SheetCompatibility()) then
		ErrorNoHalt("[Afterlight Vampire Abilities] VTM Stats character-sheet controls are unavailable.\n")
		return
	end

	if (!vitaePlugin) then
		ErrorNoHalt("[Afterlight Vampire Abilities] afterlight_vitae plugin is missing.\n")
		return
	end

	if (!RegisterPowers()) then
		ErrorNoHalt("[Afterlight Vampire Abilities] compatible Discipline Interface API could not register the powers.\n")
		return
	end

	-- Spend is deliberately server-only in Afterlight Vitae and must never be
	-- required by the client-side dependency check.
	if (SERVER and (!ix.vitae or !ix.vitae.Spend)) then
		ErrorNoHalt("[Afterlight Vampire Abilities] server-side Vitae spending API is unavailable.\n")
	end
end

function PLUGIN:GetCharacterVTMStatBonus(character, statID)
	if (!BUFF_STATS[statID]) then return end
	local client = character and character:GetPlayer()
	if (IsValid(client) and client:GetNW2Float(BUFF_END_KEY, 0) > CurTime()) then return 1 end
end

if (SERVER) then
	util.AddNetworkString("AfterlightVampireAbilitySound")
	util.AddNetworkString("AfterlightVampireAbilityPrivateMessage")
	util.AddNetworkString("AfterlightVampireAbilityStatsChanged")

	resource.AddFile("materials/afterlight/disciplines/icons/vampire_abilities.png")
	resource.AddFile("sound/afterlight/disciplines/blood_heal.mp3")
	resource.AddFile("sound/afterlight/disciplines/blood_buff.mp3")

	PLUGIN.buffs = PLUGIN.buffs or {}
	PLUGIN.preDamageHealth = PLUGIN.preDamageHealth or {}

	local function TimerName(client, suffix)
		return "AfterlightVampireAbility." .. (client:SteamID64() or client:EntIndex()) .. "." .. suffix
	end

	function PLUGIN:PlayOwnerSound(client, path, duration, fadeDuration)
		net.Start("AfterlightVampireAbilitySound")
			net.WriteString(path)
			net.WriteFloat(duration)
			net.WriteFloat(fadeDuration)
		net.Send(client)
	end

	function PLUGIN:RefreshOwnerStats(client)
		net.Start("AfterlightVampireAbilityStatsChanged")
		net.Send(client)
	end

	function PLUGIN:IsBuffActive(client)
		local state = self.buffs[client]
		return state != nil and state.expiresAt > CurTime() and client:GetNW2Float(BUFF_END_KEY, 0) > CurTime()
	end

	function PLUGIN:ClearBloodEnhancement(client, removeRemainder)
		local state = self.buffs[client]
		if (!state) then return end
		timer.Remove(TimerName(client, "BloodEnhancement"))
		if (IsValid(client)) then
			local restoredHealth = client:Health()
			if (removeRemainder and client:Alive()) then
				local remainder = math.max(state.temporaryHealth or 0, 0)
				local removable = math.min(remainder, math.max(restoredHealth - 1, 0))
				restoredHealth = restoredHealth - removable
			end
			local baseMaximum = math.max(math.floor(tonumber(state.baseMaxHealth) or 100), 1)
			client:SetMaxHealth(baseMaximum)
			if (client:Alive()) then client:SetHealth(math.Clamp(restoredHealth, 1, baseMaximum)) end
		end
		self.buffs[client] = nil
		if (IsValid(client)) then
			client:SetNW2Float(BUFF_END_KEY, 0)
			client:SetNW2Int(BUFF_HEALTH_KEY, 0)
			self:RefreshOwnerStats(client)
		end
	end

	function PLUGIN:ActivateRegeneration(context)
		local client, character = context.client, context.character
		local band = GetBand(character)
		if (!band) then return false, "notAllowed" end
		local characterID = character:GetID()
		local timerID = TimerName(client, "Regeneration")
		-- The new activation replaces the old healing schedule instead of stacking.
		timer.Remove(timerID)
		timer.Create(timerID, 1, band.regeneration.ticks, function()
			if (!IsValid(client) or !client:Alive()) then timer.Remove(timerID) return end
			local activeCharacter = client:GetCharacter()
			if (!activeCharacter or activeCharacter:GetID() != characterID or !activeCharacter:IsVampire()) then
				timer.Remove(timerID)
				return
			end
			client:SetHealth(math.min(client:Health() + band.regeneration.heal, client:GetMaxHealth()))
		end)
		self:PlayOwnerSound(client, "afterlight/disciplines/blood_heal.mp3", 8, 0.8)
		if (ix.chat and ix.chat.Send) then
			ix.chat.Send(client, "it", "Раны человека затягиваются, маленькие и тяжёлые увечья неестественно исцеляются.")
		end
		return true
	end

	function PLUGIN:ActivateBloodEnhancement(context)
		local client, character = context.client, context.character
		local band = GetBand(character)
		if (!band or self:IsBuffActive(client)) then return false, "notAllowed" end
		local expiresAt = CurTime() + 120
		local baseMaxHealth = math.max(client:GetMaxHealth(), 1)
		self.buffs[client] = {
			characterID = character:GetID(),
			temporaryHealth = band.buff.health,
			temporaryHealthMaximum = band.buff.health,
			baseMaxHealth = baseMaxHealth,
			expiresAt = expiresAt
		}
		client:SetMaxHealth(baseMaxHealth + band.buff.health)
		client:SetHealth(math.min(client:Health() + band.buff.health, client:GetMaxHealth()))
		self.buffs[client].lastObservedHealth = client:Health()
		client:SetNW2Float(BUFF_END_KEY, expiresAt)
		client:SetNW2Int(BUFF_HEALTH_KEY, band.buff.health)
		timer.Create(TimerName(client, "BloodEnhancement"), 120, 1, function()
			if (IsValid(client)) then self:ClearBloodEnhancement(client, true) end
		end)
		net.Start("AfterlightVampireAbilityPrivateMessage")
			net.WriteString("Ты чувствуешь себя сильнее. Сердце работает быстрее, чем раньше, твои рефлексы становятся лучше")
		net.Send(client)
		self:RefreshOwnerStats(client)
		self:PlayOwnerSound(client, "afterlight/disciplines/blood_buff.mp3", 5, 0.6)
		return true
	end

	function PLUGIN:EntityTakeDamage(entity)
		if (entity:IsPlayer() and self.buffs[entity]) then self.preDamageHealth[entity] = entity:Health() end
	end

	function PLUGIN:PostEntityTakeDamage(entity, damageInfo, tookDamage)
		if (!entity:IsPlayer()) then return end
		local before = self.preDamageHealth[entity]
		self.preDamageHealth[entity] = nil
		local state = self.buffs[entity]
		if (!state or !before or !tookDamage) then return end
		local actualLoss = math.max(before - math.max(entity:Health(), 0), 0)
		state.temporaryHealth = math.max((state.temporaryHealth or 0) - actualLoss, 0)
		state.lastObservedHealth = entity:Health()
		-- Keep MaxHealth and the HUD capacity stable for the full buff duration.
		-- Otherwise equal Health/MaxHealth reductions leave Helix at 100% and its
		-- auto-hidden health bar never wakes after damage. The remaining temporary
		-- layer is tracked server-side and governs expiry/healing independently.
	end

	function PLUGIN:Think()
		if ((self.nextBuffHealthObservation or 0) > CurTime()) then return end
		self.nextBuffHealthObservation = CurTime() + 0.1
		for client, state in pairs(self.buffs) do
			if (IsValid(client) and client:Alive()) then
				local current = client:Health()
				local previous = tonumber(state.lastObservedHealth) or current
				local delta = current - previous
				if (delta > 0) then
					-- Healing restores a consumed temporary layer first. If the layer
					-- is already full, the same healing remains ordinary/base healing.
					state.temporaryHealth = math.min(
						(state.temporaryHealth or 0) + delta,
						state.temporaryHealthMaximum or 0
					)
				elseif (delta < 0) then
					-- Covers direct SetHealth damage that bypasses EntityTakeDamage.
					state.temporaryHealth = math.max((state.temporaryHealth or 0) + delta, 0)
				end
				state.lastObservedHealth = current
			end
		end
	end

	function PLUGIN:PrePlayerLoadedCharacter(client)
		self:ClearBloodEnhancement(client, true)
		timer.Remove(TimerName(client, "Regeneration"))
	end

	function PLUGIN:PlayerDeath(client)
		self:ClearBloodEnhancement(client, false)
		timer.Remove(TimerName(client, "Regeneration"))
	end

	function PLUGIN:PlayerDisconnected(client)
		timer.Remove(TimerName(client, "Regeneration"))
		timer.Remove(TimerName(client, "BloodEnhancement"))
		self.buffs[client] = nil
		self.preDamageHealth[client] = nil
	end

	function PLUGIN:OnVampirismRemoved(actor, target)
		if (!IsValid(target)) then return end
		self:ClearBloodEnhancement(target, true)
		timer.Remove(TimerName(target, "Regeneration"))
	end
else
	PLUGIN.soundChannels = PLUGIN.soundChannels or {}
	PLUGIN.soundRequestTokens = PLUGIN.soundRequestTokens or {}

	local function StopSoundChannel(path)
		local entry = PLUGIN.soundChannels[path]
		if (entry and IsValid(entry.channel)) then entry.channel:Stop() end
		PLUGIN.soundChannels[path] = nil
	end

	net.Receive("AfterlightVampireAbilitySound", function()
		local path = net.ReadString()
		local duration = math.max(net.ReadFloat(), 0)
		local fadeDuration = math.Clamp(net.ReadFloat(), 0, duration)
		if (path == "" or duration <= 0) then return end

		StopSoundChannel(path)
		local token = (PLUGIN.soundRequestTokens[path] or 0) + 1
		PLUGIN.soundRequestTokens[path] = token
		sound.PlayFile("sound/" .. path, "noplay noblock", function(channel, errorID, errorName)
			if (PLUGIN.soundRequestTokens[path] != token) then
				if (IsValid(channel)) then channel:Stop() end
				return
			end
			if (!IsValid(channel)) then
				ErrorNoHalt("[Afterlight Vampire Abilities] unable to play " .. path .. ": " ..
					tostring(errorName or errorID or "unknown audio error") .. "\n")
				return
			end
			local now = RealTime()
			PLUGIN.soundChannels[path] = {
				channel = channel,
				fadeAt = now + duration - fadeDuration,
				endsAt = now + duration,
				fadeDuration = fadeDuration
			}
			channel:SetVolume(1)
			channel:Play()
		end)
	end)

	hook.Add("Think", "AfterlightVampireAbilityAudioFade", function()
		local now = RealTime()
		for path, entry in pairs(PLUGIN.soundChannels) do
			if (!IsValid(entry.channel) or now >= entry.endsAt) then
				StopSoundChannel(path)
			elseif (now >= entry.fadeAt and entry.fadeDuration > 0) then
				entry.channel:SetVolume(math.Clamp((entry.endsAt - now) / entry.fadeDuration, 0, 1))
			end
		end
	end)

	net.Receive("AfterlightVampireAbilityPrivateMessage", function()
		chat.AddText(Color(205, 35, 48), net.ReadString())
	end)

	net.Receive("AfterlightVampireAbilityStatsChanged", function()
		hook.Run("AfterlightVTMTemporaryBonusesChanged", LocalPlayer():GetCharacter())
	end)

end

print("[Afterlight Vampire Abilities] v1.2.4 loaded; healing can restore tracked temporary health.")
