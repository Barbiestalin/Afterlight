ix.vtm = ix.vtm or {}
ix.vtm.bars = ix.vtm.bars or {}

local STAMINA_MAX_KEY = "afterlightStaminaBarMaximum"
local STAMINA_BASE_KEY = "afterlightStaminaBarBaseMaximum"
local HEALTH_BASE_KEY = "afterlightHealthBarBaseMaximum"

local function GetPlayer(characterOrPlayer)
	if (IsValid(characterOrPlayer) and characterOrPlayer:IsPlayer()) then return characterOrPlayer end
	return characterOrPlayer and characterOrPlayer.GetPlayer and characterOrPlayer:GetPlayer() or nil
end

function ix.vtm.bars.GetHealthMaximum(characterOrPlayer)
	local client = GetPlayer(characterOrPlayer)
	if (!IsValid(client)) then return 100 end
	local character = client:GetCharacter()
	local current = math.max(tonumber(client:GetMaxHealth()) or 100, 1)
	local override = hook.Run("GetCharacterHealthBarMaximum", character, client, current)
	return math.max(tonumber(override) or current, 1)
end

function ix.vtm.bars.GetHealthBaseMaximum(characterOrPlayer, currentMaximum)
	local client = GetPlayer(characterOrPlayer)
	if (!IsValid(client)) then return 100 end
	local character = client:GetCharacter()
	currentMaximum = math.max(tonumber(currentMaximum) or ix.vtm.bars.GetHealthMaximum(client), 1)
	local override = hook.Run("GetCharacterHealthBarBaseMaximum", character, client, currentMaximum)
	if (tonumber(override)) then return math.max(tonumber(override), 1) end
	local networked = client:GetNW2Float(HEALTH_BASE_KEY, 0)
	if (networked > 0) then return networked end
	-- Vampire Abilities exposes the unconsumed temporary layer. Subtracting it
	-- yields the exact ordinary maximum without coupling this service to that plugin.
	local temporary = math.max(client:GetNW2Int("afterlightBloodBuffHealth", 0), 0)
	return math.max(currentMaximum - temporary, 1)
end

function ix.vtm.bars.GetStaminaMaximum(characterOrPlayer)
	local client = GetPlayer(characterOrPlayer)
	if (!IsValid(client)) then return 100 end
	local character = client:GetCharacter()
	local override = hook.Run("GetCharacterStaminaBarMaximum", character, client)
	if (tonumber(override)) then return math.max(tonumber(override), 1) end
	local networked = client:GetNW2Float(STAMINA_MAX_KEY, 0)
	if (networked > 0) then return networked end
	if (client.GetMaxStamina) then
		local value = tonumber(client:GetMaxStamina())
		if (value and value > 0) then return value end
	end
	if (character and character.GetMaxStamina) then
		local value = tonumber(character:GetMaxStamina())
		if (value and value > 0) then return value end
	end
	return math.max(tonumber(client:GetLocalVar("stmMax", client:GetLocalVar("staminaMax", 100))) or 100, 1)
end

function ix.vtm.bars.GetStaminaBaseMaximum(characterOrPlayer, currentMaximum)
	local client = GetPlayer(characterOrPlayer)
	if (!IsValid(client)) then return 100 end
	local character = client:GetCharacter()
	currentMaximum = math.max(tonumber(currentMaximum) or ix.vtm.bars.GetStaminaMaximum(client), 1)
	local override = hook.Run("GetCharacterStaminaBarBaseMaximum", character, client, currentMaximum)
	if (tonumber(override)) then return math.max(tonumber(override), 1) end
	local networked = client:GetNW2Float(STAMINA_BASE_KEY, 0)
	return networked > 0 and networked or 100
end

if (SERVER) then
	function ix.vtm.bars.SetHealthBaseMaximum(client, baseMaximum)
		if (!IsValid(client)) then return false end
		client:SetNW2Float(HEALTH_BASE_KEY, math.max(tonumber(baseMaximum) or 0, 0))
		return true
	end

	-- Future stamina mechanics can call this when their maximum changes. This
	-- controls proportional HUD capacity; the stamina mechanic remains the owner
	-- of regeneration, consumption and its current numeric value.
	function ix.vtm.bars.SetStaminaCapacity(client, maximum, baseMaximum)
		if (!IsValid(client)) then return false end
		maximum = math.max(tonumber(maximum) or 100, 1)
		baseMaximum = math.max(tonumber(baseMaximum) or 100, 1)
		client:SetNW2Float(STAMINA_MAX_KEY, maximum)
		client:SetNW2Float(STAMINA_BASE_KEY, baseMaximum)
		return true
	end
end
