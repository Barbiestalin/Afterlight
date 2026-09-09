local PLUGIN = PLUGIN

PLUGIN.name = "Afterlight Discipline Interface"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Vampire-only radial discipline selection, active-power HUD and secure activation gateway."
PLUGIN.version = "1.8"

ix.char.RegisterVar("selectedDisciplinePower", {
	field = "selected_discipline_power",
	fieldType = ix.type.text,
	default = {},
	bNoDisplay = true,
	isLocal = true,
	OnValidate = function(self, value)
		if (!istable(value)) then return {} end
		return {
			disciplineID = string.lower(string.Trim(tostring(value.disciplineID or ""))),
			powerID = string.lower(string.Trim(tostring(value.powerID or "")))
		}
	end
})

function PLUGIN:InitializedPlugins()
	ix.disciplines.ApplyInterfaceIcons()
	local statsPlugin = ix.plugin.Get("afterlight_vtm_stats")
	if (!statsPlugin or !ix.vtm or !ix.vtm.stats or !ix.vtm.stats.GetData) then
		ErrorNoHalt("[Afterlight Discipline Interface] compatible afterlight_vtm_stats API is unavailable.\n")
	end
	if (!ix.meta.character.IsVampire or !ix.disciplines.GetCharacterData) then
		ErrorNoHalt("[Afterlight Discipline Interface] vampire/discipline APIs are unavailable.\n")
	end
end

if (SERVER) then
	util.AddNetworkString("AfterlightDisciplineSelect")
	util.AddNetworkString("AfterlightDisciplineSelection")
	util.AddNetworkString("AfterlightDisciplineUse")
	util.AddNetworkString("AfterlightDisciplineFeedback")
	util.AddNetworkString("AfterlightDisciplineCooldown")

	-- Source materials must live under garrysmod/materials, not inside the
	-- schema plugin directory. Register every file for non-Workshop clients.
	resource.AddFile("materials/afterlight/disciplines/wheel_background.png")
	resource.AddFile("materials/afterlight/disciplines/hud_frame.png")
	resource.AddFile("resource/fonts/afterlight_cormorant.ttf")
	resource.AddFile("resource/fonts/afterlight_cormorant_bold.ttf")
	local addedIcons = {}
	for _, iconPath in pairs(ix.disciplines.interfaceIcons or {}) do
		if (!addedIcons[iconPath]) then
			addedIcons[iconPath] = true
			resource.AddFile("materials/" .. iconPath)
		end
	end

	local nextSelect, nextUse = {}, {}

	local function IsVampire(character)
		return character and character.IsVampire and character:IsVampire()
	end

	local function CanSelect(character, disciplineID, powerID)
		if (!IsVampire(character)) then return false, "notVampire" end
		local power = ix.disciplines.GetPower(disciplineID, powerID)
		if (!power) then return false, "invalidPower" end
		if (!ix.disciplines.CanAccessInterfaceDiscipline(character, power.disciplineID)) then
			return false, "disciplineNotGranted"
		end
		if (!ix.disciplines.CanAccessPower(character, power)) then return false, "levelTooLow" end
		return true, power
	end

	local function SendSelection(character)
		local client = character and character:GetPlayer()
		if (!IsValid(client)) then return end
		net.Start("AfterlightDisciplineSelection")
			net.WriteTable(character:GetSelectedDisciplinePower() or {})
		net.Send(client)
	end

	function ix.disciplines.SelectPower(character, disciplineID, powerID)
		local valid, power = CanSelect(character, disciplineID, powerID)
		if (!valid) then return false, power end
		if (hook.Run("CanCharacterSelectDisciplinePower", character, power) == false) then
			return false, "notAllowed"
		end
		character:SetSelectedDisciplinePower({disciplineID = power.disciplineID, powerID = power.id})
		SendSelection(character)
		hook.Run("OnCharacterSelectedDisciplinePower", character, power)
		return true, power
	end

	function ix.disciplines.ClearSelectedPower(character)
		if (!character or !character.SetSelectedDisciplinePower) then return false end
		character:SetSelectedDisciplinePower({})
		SendSelection(character)
		return true
	end

	local feedbackText = {
		notVampire = "Способности дисциплин доступны только вампирам.",
		invalidPower = "Выбранная способность больше не зарегистрирована.",
		disciplineNotGranted = "Эта дисциплина отсутствует в чарлисте.",
		levelTooLow = "Недостаточный уровень дисциплины.",
		notAllowed = "Использование способности сейчас запрещено.",
		notAlive = "Способность нельзя использовать в текущем состоянии.",
		notImplemented = "Эта способность пока не имеет реализации.",
		cooldown = "Способность ещё восстанавливается.",
		noVitae = "Недостаточно Витэ."
	}

	local function Feedback(client, success, reason)
		net.Start("AfterlightDisciplineFeedback")
			net.WriteBool(success)
			net.WriteString(feedbackText[reason] or tostring(reason or ""))
		net.Send(client)
	end

	local function SendCooldown(client, character, power, remaining)
		net.Start("AfterlightDisciplineCooldown")
			net.WriteUInt(math.max(tonumber(character and character:GetID()) or 0, 0), 32)
			net.WriteString(power.disciplineID)
			net.WriteString(power.id)
			net.WriteFloat(math.max(tonumber(remaining) or 0, 0))
		net.Send(client)
	end

	net.Receive("AfterlightDisciplineSelect", function(_, client)
		if ((nextSelect[client] or 0) > CurTime()) then return end
		nextSelect[client] = CurTime() + 0.12
		local disciplineID, powerID = net.ReadString(), net.ReadString()
		local character = client:GetCharacter()
		local success, result = ix.disciplines.SelectPower(character, disciplineID, powerID)
		if (!success) then Feedback(client, false, result) end
	end)

	net.Receive("AfterlightDisciplineUse", function(_, client)
		if ((nextUse[client] or 0) > CurTime()) then return end
		nextUse[client] = CurTime() + 0.2
		local character = client:GetCharacter()
		if (!IsVampire(character)) then return Feedback(client, false, "notVampire") end
		if (!client:Alive() or client:GetMoveType() == MOVETYPE_NOCLIP) then
			return Feedback(client, false, "notAlive")
		end

		local selected = character:GetSelectedDisciplinePower()
		selected = istable(selected) and selected or {}
		local valid, power = CanSelect(character, selected.disciplineID, selected.powerID)
		if (!valid) then
			ix.disciplines.ClearSelectedPower(character)
			return Feedback(client, false, power)
		end

		local context = {
			client = client,
			character = character,
			disciplineID = power.disciplineID,
			powerID = power.id,
			power = power,
			trace = client:GetEyeTrace()
		}
		if (hook.Run("CanCharacterUseDisciplinePower", character, power, context) == false) then
			return Feedback(client, false, "notAllowed")
		end
		character.afterlightDisciplineCooldowns = character.afterlightDisciplineCooldowns or {}
		local cooldownKey = power.disciplineID .. ":" .. power.id
		local cooldownEnd = character.afterlightDisciplineCooldowns[cooldownKey] or 0
		if (cooldownEnd > CurTime()) then
			SendCooldown(client, character, power, cooldownEnd - CurTime())
			return Feedback(client, false, "cooldown")
		end
		if (power.CanActivate) then
			local ok, allowed, deniedReason = pcall(power.CanActivate, context)
			if (!ok) then
				ErrorNoHalt("[Afterlight Discipline Interface] CanActivate error: " .. tostring(allowed) .. "\n")
				return Feedback(client, false, "notAllowed")
			end
			if (allowed == false) then return Feedback(client, false, deniedReason or "notAllowed") end
		end
		if (!power.OnActivate) then return Feedback(client, false, "notImplemented") end

		local vitaeCost = power.vitaeCost
		if (power.GetVitaeCost) then
			local ok, calculated = pcall(power.GetVitaeCost, context)
			if (!ok) then
				ErrorNoHalt("[Afterlight Discipline Interface] GetVitaeCost error: " .. tostring(calculated) .. "\n")
				return Feedback(client, false, "notAllowed")
			end
			vitaeCost = math.max(math.floor(tonumber(calculated) or 0), 0)
		end
		context.vitaeCost = vitaeCost

		local spentVitae = 0
		if (vitaeCost > 0) then
			if (!ix.vitae or !ix.vitae.Spend) then return Feedback(client, false, "noVitae") end
			local spent, delta = ix.vitae.Spend(character, vitaeCost,
				(ix.vitae.SOURCE and ix.vitae.SOURCE.DISCIPLINE) or "discipline", context)
			if (!spent) then return Feedback(client, false, "noVitae") end
			spentVitae = math.abs(tonumber(delta) or vitaeCost)
		end

		local ok, success, reason = pcall(power.OnActivate, context)
		if (!ok or success == false) then
			if (spentVitae > 0 and ix.vitae and ix.vitae.Add) then
				ix.vitae.Add(character, spentVitae,
					(ix.vitae.SOURCE and ix.vitae.SOURCE.OTHER) or "other",
					{rollback = true, original = context})
			end
			if (!ok) then ErrorNoHalt("[Afterlight Discipline Interface] OnActivate error: " .. tostring(success) .. "\n") end
			return Feedback(client, false, !ok and "notAllowed" or (reason or "notAllowed"))
		end
		local cooldown = math.max(tonumber(power.cooldown) or 0, 0)
		character.afterlightDisciplineCooldowns[cooldownKey] = CurTime() + cooldown
		SendCooldown(client, character, power, cooldown)
		Feedback(client, true, power.name)
		hook.Run("OnCharacterUsedDisciplinePower", character, power, context)
	end)

	function PLUGIN:PlayerLoadedCharacter(client, character)
		character.afterlightDisciplineCooldowns = character.afterlightDisciplineCooldowns or {}
		timer.Simple(0, function()
			if (!IsValid(client) or client:GetCharacter() != character) then return end
			local power = ix.disciplines.GetSelectedPower(character)
			if (power and CanSelect(character, power.disciplineID, power.id)) then
				SendSelection(character)
			else
				ix.disciplines.ClearSelectedPower(character)
			end
		end)
	end

	function PLUGIN:OnCharacterDisciplineChanged(character)
		local power = ix.disciplines.GetSelectedPower(character)
		if (power and !CanSelect(character, power.disciplineID, power.id)) then
			ix.disciplines.ClearSelectedPower(character)
		end
	end

	function PLUGIN:OnCharacterDisciplineRemoved(character)
		self:OnCharacterDisciplineChanged(character)
	end

	function PLUGIN:OnCharacterDisciplinesCleared(character)
		ix.disciplines.ClearSelectedPower(character)
	end

	function PLUGIN:OnVampirismRemoved(actor, target, character)
		ix.disciplines.ClearSelectedPower(character)
	end

	hook.Add("PlayerDisconnected", "AfterlightDisciplineInterfaceRateLimit", function(client)
		nextSelect[client], nextUse[client] = nil, nil
	end)
else
	ix.disciplines.clientCooldowns = ix.disciplines.clientCooldowns or {}

	function ix.disciplines.GetClientCooldown(disciplineID, powerID, character)
		character = character or (IsValid(LocalPlayer()) and LocalPlayer():GetCharacter())
		local characterID = character and character:GetID() or 0
		local key = tostring(characterID) .. ":" .. tostring(disciplineID) .. ":" .. tostring(powerID)
		return math.max((ix.disciplines.clientCooldowns[key] or 0) - CurTime(), 0)
	end

	net.Receive("AfterlightDisciplineCooldown", function()
		local characterID = net.ReadUInt(32)
		local key = tostring(characterID) .. ":" .. net.ReadString() .. ":" .. net.ReadString()
		ix.disciplines.clientCooldowns[key] = CurTime() + math.max(net.ReadFloat(), 0)
	end)

	net.Receive("AfterlightDisciplineSelection", function()
		local character = LocalPlayer():GetCharacter()
		local selected = net.ReadTable()
		if (character) then character.vars.selectedDisciplinePower = selected end
	end)

	ix.disciplines.screenFeedback = ix.disciplines.screenFeedback or {}

	surface.CreateFont("AfterlightDisciplineFeedback", {
		font = "Cormorant Garamond",
		size = 15,
		weight = 500,
		extended = true,
		antialias = true
	})

	net.Receive("AfterlightDisciplineFeedback", function()
		local success, text = net.ReadBool(), net.ReadString()
		if (text == "") then return end
		local now = RealTime()
		ix.disciplines.screenFeedback[#ix.disciplines.screenFeedback + 1] = {
			text = text,
			success = success,
			startedAt = now,
			fadeInEnd = now + 0.25,
			holdEnd = now + 2.5,
			fadeOutEnd = now + 3.1
		}
		while (#ix.disciplines.screenFeedback > 3) do table.remove(ix.disciplines.screenFeedback, 1) end
	end)

	hook.Add("HUDPaint", "AfterlightDisciplineScreenFeedback", function()
		local messages = ix.disciplines.screenFeedback
		local now = RealTime()
		for index = #messages, 1, -1 do
			if (now >= messages[index].fadeOutEnd) then table.remove(messages, index) end
		end

		local baseY = ScrH() - 118
		for index, message in ipairs(messages) do
			local alpha
			if (now < message.fadeInEnd) then
				alpha = 255 * math.TimeFraction(message.startedAt, message.fadeInEnd, now)
			elseif (now <= message.holdEnd) then
				alpha = 255
			else
				alpha = 255 * (1 - math.TimeFraction(message.holdEnd, message.fadeOutEnd, now))
			end
			alpha = math.Clamp(alpha, 0, 255)
			local color = message.success and Color(220, 210, 202, alpha) or Color(215, 48, 58, alpha)
			draw.SimpleText(message.text, "AfterlightDisciplineFeedback", ScrW() * 0.5,
				baseY - (#messages - index) * 19, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end
	end)
end

print("[Afterlight Discipline Interface] v1.8 loaded; gothic wheel, bundled typography and ornate HUD are active.")
