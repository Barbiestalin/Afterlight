ix.vitae = ix.vitae or {}

-- Edit this table to rebalance capacity. Missing generations use 0 and are
-- therefore rejected by all gain/spend operations.
ix.vitae.maxByGeneration = {
	[5] = 40,
	[6] = 30,
	[7] = 20,
	[8] = 20,
	[9] = 20,
	[10] = 18,
	[11] = 16,
	[12] = 14,
	[13] = 12,
	[14] = 10,
	[15] = 10
}

ix.vitae.SOURCE = {
	ITEM = "item",
	FORCED_FEED = "forced_feed",
	VOLUNTARY_FEED = "voluntary_feed",
	HUMAN_CORPSE = "human_corpse",
	ADMIN = "admin",
	DISCIPLINE = "discipline",
	HEALING = "healing",
	OTHER = "other"
}

function ix.vitae.IsVampire(character)
	return character and character.IsVampire and character:IsVampire()
end

function ix.vitae.GetMax(character)
	if (!ix.vitae.IsVampire(character)) then return 0 end
	return ix.vitae.maxByGeneration[math.floor(tonumber(character:GetGeneration()) or 0)] or 0
end

function ix.vitae.Get(character)
	if (!ix.vitae.IsVampire(character)) then return 0 end
	return math.Clamp(math.floor(tonumber(character:GetVitae()) or 0), 0, ix.vitae.GetMax(character))
end

function ix.vitae.GetFraction(character)
	local maximum = ix.vitae.GetMax(character)
	return maximum > 0 and ix.vitae.Get(character) / maximum or 0
end

function ix.vitae.CanAfford(character, amount)
	amount = math.max(math.floor(tonumber(amount) or 0), 0)
	return ix.vitae.IsVampire(character) and ix.vitae.Get(character) >= amount
end

if (SERVER) then
	function ix.vitae.SyncChange(character, oldValue, newValue, source)
		local client = character:GetPlayer()
		if (!IsValid(client)) then return end

		net.Start("AfterlightVitaeChanged")
			net.WriteUInt(math.Clamp(oldValue, 0, 255), 8)
			net.WriteUInt(math.Clamp(newValue, 0, 255), 8)
			net.WriteUInt(math.Clamp(ix.vitae.GetMax(character), 0, 255), 8)
			net.WriteString(tostring(source or ix.vitae.SOURCE.OTHER))
		net.Send(client)
	end

	function ix.vitae.Set(character, amount, source, context)
		if (!ix.vitae.IsVampire(character)) then return false, "notVampire" end
		local maximum = ix.vitae.GetMax(character)
		if (maximum <= 0) then return false, "invalidGeneration" end

		local oldValue = ix.vitae.Get(character)
		local newValue = math.Clamp(math.floor(tonumber(amount) or oldValue), 0, maximum)
		if (hook.Run("CanCharacterChangeVitae", character, newValue - oldValue, source, context) == false) then
			return false, "notAllowed"
		end

		if (newValue == oldValue) then return true, 0, newValue end
		character:SetVitae(newValue)
		ix.vitae.SyncChange(character, oldValue, newValue, source)
		hook.Run("OnCharacterVitaeChanged", character, oldValue, newValue, source, context)
		if (newValue == 0) then hook.Run("OnCharacterVitaeDepleted", character, source, context) end
		if (newValue == maximum) then hook.Run("OnCharacterVitaeFilled", character, source, context) end
		return true, newValue - oldValue, newValue
	end

	function ix.vitae.Add(character, amount, source, context)
		if (!ix.vitae.IsVampire(character)) then return false, "notVampire" end
		amount = math.max(math.floor(tonumber(amount) or 0), 0)
		if (amount <= 0) then return false, "invalidAmount" end

		local modified = hook.Run("ModifyVitaeGain", character, amount, source, context)
		if (isnumber(modified)) then amount = math.max(math.floor(modified), 0) end
		if (amount <= 0) then return false, "noGain" end
		return ix.vitae.Set(character, ix.vitae.Get(character) + amount, source, context)
	end

	function ix.vitae.Spend(character, amount, source, context)
		if (!ix.vitae.IsVampire(character)) then return false, "notVampire" end
		amount = math.max(math.floor(tonumber(amount) or 0), 0)
		local modified = hook.Run("ModifyVitaeCost", character, amount, source, context)
		if (isnumber(modified)) then amount = math.max(math.floor(modified), 0) end
		if (amount <= 0) then return true, 0, ix.vitae.Get(character) end
		if (hook.Run("CanCharacterSpendVitae", character, amount, source, context) == false) then return false, "notAllowed" end
		if (!ix.vitae.CanAfford(character, amount)) then return false, "notEnoughVitae" end
		return ix.vitae.Set(character, ix.vitae.Get(character) - amount, source, context)
	end

	function ix.vitae.Transfer(donor, recipient, amount, source, context)
		if (!ix.vitae.IsVampire(donor) or !ix.vitae.IsVampire(recipient)) then return false, "notVampire" end
		amount = math.max(math.floor(tonumber(amount) or 0), 0)
		amount = math.min(amount, ix.vitae.Get(donor), ix.vitae.GetMax(recipient) - ix.vitae.Get(recipient))
		if (amount <= 0) then return false, "noTransfer" end

		local spent = ix.vitae.Spend(donor, amount, source, context)
		if (!spent) then return false, "donorRejected" end
		local gained, reason = ix.vitae.Add(recipient, amount, source, context)
		if (!gained) then
			-- Roll back through the central API if a recipient hook rejects transfer.
			ix.vitae.Add(donor, amount, ix.vitae.SOURCE.OTHER, {rollback = true, original = context})
			return false, reason
		end
		return true, amount
	end

	-- Adapter for future blood bag items. The item is removed only after an
	-- actual gain, preventing loss when the reservoir is full or access fails.
	function ix.vitae.ConsumeItem(client, item, amount, context)
		local character = IsValid(client) and client:GetCharacter()
		local inventory = character and character:GetInventory()
		local ownedItems = inventory and inventory:GetItems() or {}
		if (!character or !item or ownedItems[item.id] != item) then return false, "invalidItem" end
		local success, delta = ix.vitae.Add(character, amount, ix.vitae.SOURCE.ITEM, context or {item = item})
		if (success and delta > 0 and ix.item.instances[item.id]) then item:Remove() end
		return success, delta
	end

	-- Human feeding/corpse plugins call Add with their own validated victim.
	function ix.vitae.GainFromFeeding(feeder, victim, amount, voluntary, context)
		local character = IsValid(feeder) and feeder:GetCharacter()
		context = context or {}
		context.victim = victim
		return ix.vitae.Add(character, amount,
			voluntary and ix.vitae.SOURCE.VOLUNTARY_FEED or ix.vitae.SOURCE.FORCED_FEED, context)
	end

	function ix.vitae.GainFromHumanCorpse(feeder, corpse, amount, context)
		local character = IsValid(feeder) and feeder:GetCharacter()
		context = context or {}
		context.corpse = corpse
		return ix.vitae.Add(character, amount, ix.vitae.SOURCE.HUMAN_CORPSE, context)
	end
end
