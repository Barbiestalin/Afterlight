if (!CLIENT) then return end

ix.vtm = ix.vtm or {}
ix.vtm.bars = ix.vtm.bars or {}
ix.vtm.bars.observedHealthBase = ix.vtm.bars.observedHealthBase or {}
ix.vtm.bars.observedStaminaBase = ix.vtm.bars.observedStaminaBase or {}
ix.vtm.bars.lastHealthState = ix.vtm.bars.lastHealthState or {}
ix.vtm.bars.lastStaminaState = ix.vtm.bars.lastStaminaState or {}

local function CharacterKey(character)
	return character and tostring(character:GetID()) or "none"
end

local function ResolveBase(cache, key, suppliedBase, currentMaximum, hasExplicitBonus)
	if (!cache[key]) then cache[key] = math.max(suppliedBase, 1) end
	if (!hasExplicitBonus and currentMaximum < cache[key]) then cache[key] = currentMaximum end
	return math.max(cache[key], 1)
end

local function TargetWidth(normalWidth, maximum, baseMaximum, maximumScreenFraction)
	local ratio = math.max(maximum, 1) / math.max(baseMaximum, 1)
	local screenLimit = ScrW() * (maximumScreenFraction or 1)
	return math.Clamp(normalWidth * ratio, normalWidth * 0.25, math.min(screenLimit, ScrW() - 8))
end

local function ApproachPanelWidth(info, targetWidth, normalWidth)
	if (!info or !IsValid(info.panel)) then return end
	local speed = math.max(normalWidth * FrameTime() * 2.6, 1)
	local oldWidth = info.panel:GetWide()
	local newWidth = math.Approach(oldWidth, targetWidth, speed)
	if (newWidth != oldWidth) then
		info.panel:SetWide(newWidth)
		-- ixInfoBar creates its coloured fill and label as Dock(FILL) children.
		-- A raw SetWide does not reliably refresh their cached dock geometry.
		info.panel:InvalidateLayout(true)
		if (IsValid(info.panel.bar)) then info.panel.bar:InvalidateLayout(true) end
		if (IsValid(info.panel.label)) then info.panel.label:InvalidateLayout(true) end
	end
end

local function WakeHealthBar(info, characterKey, client, maximum)
	if (!info or !IsValid(info.panel)) then return end
	local health = client:Health()
	local previous = ix.vtm.bars.lastHealthState[characterKey]
	if (!previous or previous.health != health or previous.maximum != maximum) then
		ix.vtm.bars.lastHealthState[characterKey] = {health = health, maximum = maximum}
		info.panel:SetLifetime(CurTime() + 5)
		info.panel:SetVisible(true)
	end
end

local function WakeStaminaBar(info, characterKey, client, maximum)
	if (!info or !IsValid(info.panel)) then return end
	local stamina = tonumber(client:GetLocalVar("stm", 100)) or 100
	local previous = ix.vtm.bars.lastStaminaState[characterKey]
	if (!previous or previous.stamina != stamina or previous.maximum != maximum) then
		ix.vtm.bars.lastStaminaState[characterKey] = {stamina = stamina, maximum = maximum}
		info.panel:SetLifetime(CurTime() + 5)
		info.panel:SetVisible(true)
	end
end

hook.Add("Think", "AfterlightAdaptiveHelixBars", function()
	local manager = ix.gui and ix.gui.bars
	if (!ix.bar or !IsValid(manager) or !ix.vtm.bars.GetHealthMaximum) then return end
	local client = LocalPlayer()
	local character = IsValid(client) and client:GetCharacter()
	if (!character) then return end

	local key = CharacterKey(character)
	-- Never derive these from manager:GetWide(): the manager itself expands.
	-- Health intentionally starts at half Helix's ordinary width and is capped
	-- at half the screen, preventing extreme MaxHealth from crossing the HUD.
	local normalWidth = ScrW() * 0.35
	local healthNormalWidth = ScrW() * 0.175
	local healthInfo = ix.bar.Get("health")
	local staminaInfo = ix.bar.Get("stm")

	local healthMaximum = ix.vtm.bars.GetHealthMaximum(client)
	local healthSuppliedBase = ix.vtm.bars.GetHealthBaseMaximum(client, healthMaximum)
	local healthHasBonus = healthMaximum > healthSuppliedBase + 0.001
	local healthBase = ResolveBase(ix.vtm.bars.observedHealthBase, key,
		healthSuppliedBase, healthMaximum, healthHasBonus)
	local healthTarget = TargetWidth(healthNormalWidth, healthMaximum, healthBase, 0.5)
	WakeHealthBar(healthInfo, key, client, healthMaximum)
	if (healthInfo and IsValid(healthInfo.panel)) then
		-- Do not depend solely on ixInfoBarManager's cached GetValue pass. Feed
		-- the real fraction directly so every external heal is reflected.
		healthInfo.panel:SetValue(math.Clamp(client:Health() / math.max(healthMaximum, 1), 0, 1))
	end

	local staminaTarget = normalWidth
	if (staminaInfo) then
		local staminaMaximum = ix.vtm.bars.GetStaminaMaximum(client)
		local staminaSuppliedBase = ix.vtm.bars.GetStaminaBaseMaximum(client, staminaMaximum)
		local staminaHasBonus = staminaMaximum > staminaSuppliedBase + 0.001
		local staminaBase = ResolveBase(ix.vtm.bars.observedStaminaBase, key,
			staminaSuppliedBase, staminaMaximum, staminaHasBonus)
		staminaTarget = TargetWidth(normalWidth, staminaMaximum, staminaBase)
		WakeStaminaBar(staminaInfo, key, client, staminaMaximum)
	end

	-- ixInfoBarManager clips child panels to its own width. Expand the invisible
	-- parent to the longest target before growing either child. During shrink,
	-- retain enough parent width for the still-animating child to avoid erasing
	-- its right border—the exact artifact visible in the reported screenshot.
	local managerTarget = math.max(normalWidth, healthTarget, staminaTarget,
		IsValid(healthInfo and healthInfo.panel) and healthInfo.panel:GetWide() or 0,
		IsValid(staminaInfo and staminaInfo.panel) and staminaInfo.panel:GetWide() or 0)
	manager:SetWide(math.min(managerTarget, ScrW() - manager:GetX() - 4))

	ApproachPanelWidth(healthInfo, healthTarget, healthNormalWidth)
	ApproachPanelWidth(staminaInfo, staminaTarget, normalWidth)
end)

hook.Add("OnCharacterDisconnect", "AfterlightAdaptiveBarCacheCleanup", function(character)
	local key = CharacterKey(character)
	ix.vtm.bars.observedHealthBase[key] = nil
	ix.vtm.bars.observedStaminaBase[key] = nil
	ix.vtm.bars.lastHealthState[key] = nil
	ix.vtm.bars.lastStaminaState[key] = nil
end)

concommand.Add("afterlight_bar_capacity_debug", function()
	local client = LocalPlayer()
	local character = IsValid(client) and client:GetCharacter()
	if (!character or !ix.vtm.bars.GetHealthMaximum) then
		print("[Afterlight Bars] character/API unavailable")
		return
	end
	local healthMaximum = ix.vtm.bars.GetHealthMaximum(client)
	local staminaMaximum = ix.vtm.bars.GetStaminaMaximum(client)
	local manager = ix.gui and ix.gui.bars
	local health = ix.bar and ix.bar.Get("health")
	local stamina = ix.bar and ix.bar.Get("stm")
	print("[Afterlight Bars] health:", healthMaximum, "/ base:",
		ix.vtm.bars.GetHealthBaseMaximum(client, healthMaximum), "stamina:", staminaMaximum,
		"/ base:", ix.vtm.bars.GetStaminaBaseMaximum(client, staminaMaximum),
		"manager width:", IsValid(manager) and manager:GetWide() or "none",
		"health width:", health and IsValid(health.panel) and health.panel:GetWide() or "none",
		"stamina width:", stamina and IsValid(stamina.panel) and stamina.panel:GetWide() or "none")
end)
