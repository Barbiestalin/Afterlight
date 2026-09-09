local PLUGIN = PLUGIN

PLUGIN.name = "Afterlight Vitae"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Server-authoritative vitae reservoir and an atmospheric vampire-only HUD."

ix.util.Include("cl_hud.lua")

if (SERVER) then
	resource.AddFile("materials/afterlight/vitae/frame.png")
	util.AddNetworkString("AfterlightVitaeChanged")
end

ix.config.Add("vitaeStartPercent", 100, "Процент заполнения Витэ при первом создании или конвертации вампира.", nil, {
	data = {min = 0, max = 100}, category = "Витэ"
})
ix.config.Add("vitaeHUDEnabled", true, "Показывать атмосферный индикатор Витэ справа.", nil, {
	category = "Витэ"
})
ix.config.Add("vitaePulseDuration", 1.4, "Продолжительность свечения индикатора после изменения Витэ.", nil, {
	data = {min = 0.2, max = 5, decimals = 1}, category = "Витэ"
})

function PLUGIN:InitializedPlugins()
	if (!ix.vampire or !ix.meta.character.IsVampire) then
		ErrorNoHalt("[Afterlight Vitae] afterlight_vampire_core is missing; Vitae will remain disabled.\n")
	end
end

ix.char.RegisterVar("vitae", {
	field = "vitae",
	fieldType = ix.type.number,
	default = 0,
	bNoDisplay = true,
	isLocal = true,
	OnValidate = function(self, value)
		return math.max(math.floor(tonumber(value) or 0), 0)
	end
})

function PLUGIN:InitializeVitae(character, force)
	if (!SERVER or !ix.vitae.IsVampire(character)) then return end
	if (!force and character:GetData("afterlightVitaeInitialized", false)) then
		-- Generation may have changed while the plugin was absent.
		local maximum = ix.vitae.GetMax(character)
		if (character:GetVitae() > maximum) then ix.vitae.Set(character, maximum, "generation_clamp") end
		return
	end

	local maximum = ix.vitae.GetMax(character)
	local fraction = math.Clamp(ix.config.Get("vitaeStartPercent", 100), 0, 100) / 100
	local success = ix.vitae.Set(character, math.floor(maximum * fraction + 0.5), "initialization")
	if (success) then character:SetData("afterlightVitaeInitialized", true) end
end

function PLUGIN:OnCharacterCreated(client, character)
	if (SERVER) then timer.Simple(0, function() if character then self:InitializeVitae(character, true) end end) end
end

function PLUGIN:PlayerLoadedCharacter(client, character)
	if (SERVER) then self:InitializeVitae(character, false) end
end

function PLUGIN:OnVampireProfileApplied(client, character)
	if (SERVER) then self:InitializeVitae(character, true) end
end

function PLUGIN:CharacterVarChanged(character, key, oldValue, value)
	if (!SERVER or key != "generation" or !ix.vitae.IsVampire(character)) then return end
	local maximum = ix.vitae.GetMax(character)
	if (character:GetVitae() > maximum) then ix.vitae.Set(character, maximum, "generation_clamp") end
end

ix.command.Add("VitaeSet", {
	description = "Установить точный запас Витэ вампира.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.number},
	OnRun = function(self, client, target, amount)
		local character = target:GetCharacter()
		if (!ix.vitae.IsVampire(character)) then return "Цель не является вампиром." end
		local success, reason, value = ix.vitae.Set(character, amount, ix.vitae.SOURCE.ADMIN, {admin = client})
		if (!success) then return "Изменение Витэ отклонено: " .. tostring(reason) end
		return string.format("Запас Витэ %s установлен на %d/%d.", character:GetName(), value, ix.vitae.GetMax(character))
	end
})

ix.command.Add("VitaeAdd", {
	description = "Пополнить запас Витэ вампира.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.number},
	OnRun = function(self, client, target, amount)
		local character = target:GetCharacter()
		if (!ix.vitae.IsVampire(character)) then return "Цель не является вампиром." end
		local success, delta, value = ix.vitae.Add(character, amount, ix.vitae.SOURCE.ADMIN, {admin = client})
		if (!success) then return "Пополнение Витэ отклонено: " .. tostring(delta) end
		return string.format("Добавлено %d Витэ. Текущий запас %d/%d.", delta, value, ix.vitae.GetMax(character))
	end
})

ix.command.Add("VitaeTake", {
	description = "Отнять Витэ у вампира.",
	adminOnly = true,
	arguments = {ix.type.player, ix.type.number},
	OnRun = function(self, client, target, amount)
		local character = target:GetCharacter()
		if (!ix.vitae.IsVampire(character)) then return "Цель не является вампиром." end
		local success, delta, value = ix.vitae.Spend(character, amount, ix.vitae.SOURCE.ADMIN, {admin = client})
		if (!success) then return "Списание Витэ отклонено: " .. tostring(delta) end
		return string.format("Списано %d Витэ. Текущий запас %d/%d.", math.abs(delta), value, ix.vitae.GetMax(character))
	end
})
