local PLUGIN = PLUGIN

PLUGIN.name = "Afterlight Lootable Corpses"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Creates one persistent, naturally posed corpse with a complete loot inventory and safe Helix money storage."
PLUGIN.hardCorpseMax = 64
PLUGIN.corpses = PLUGIN.corpses or {}

-- Architecture based on NebulousCloud/helix-plugins persistent_corpses.lua
-- (MIT, original author `impulse). This is a new implementation with complete
-- inventory transfer, nested bag support, native money storage and safer cleanup.

ix.lang.AddTable("english", {
	afterlightSearchingCorpse = "Searching the corpse...",
	afterlightCorpse = "Corpse of %s",
	afterlightCorpseBusy = "Someone else is already searching this corpse.",
	afterlightCorpseTooFar = "You are too far away from the corpse."
})

ix.lang.AddTable("russian", {
	afterlightSearchingCorpse = "Обыск тела...",
	afterlightCorpse = "Тело: %s",
	afterlightCorpseBusy = "Этот труп уже обыскивает другой персонаж.",
	afterlightCorpseTooFar = "Вы находитесь слишком далеко от трупа."
})

local category = "Лутабельные тела"

ix.config.Add("alcEnabled", true, "Создавать единственный серверный лутабельный рагдолл при смерти.", nil, {
	category = category
})
ix.config.Add("alcCorpseMax", 16, "Максимальное количество трупов на карте. 0 отключает создание.", nil, {
	data = {min = 0, max = PLUGIN.hardCorpseMax}, category = category
})
ix.config.Add("alcDecayTime", 300, "Время до исчезновения трупа в секундах. 0 — не удалять по времени.", nil, {
	data = {min = 0, max = 3600}, category = category
})
ix.config.Add("alcSearchTime", 2.5, "Продолжительность обыска до открытия инвентаря.", nil, {
	data = {min = 0, max = 60, decimals = 1}, category = category
})
ix.config.Add("alcLootDistance", 128, "Максимальная дистанция начала обыска.", nil, {
	data = {min = 48, max = 256}, category = category
})
ix.config.Add("alcMoneyPercent", 100, "Процент денег персонажа, переносимый в труп.", nil, {
	data = {min = 0, max = 100}, category = category
})
ix.config.Add("alcMultipleLooters", false, "Разрешить нескольким персонажам одновременно обыскивать один труп.", nil, {
	category = category
})
ix.config.Add("alcRemoveWhenEmpty", false, "Удалять полностью опустошённый труп раньше общего времени исчезновения.", nil, {
	category = category
})
ix.config.Add("alcEmptyRemoveDelay", 10, "Задержка удаления пустого трупа в секундах.", nil, {
	data = {min = 0, max = 300, decimals = 1}, category = category
})

if (SERVER) then
	function PLUGIN:ShouldSpawnClientRagdoll(client)
		if (ix.config.Get("alcEnabled", true) and ix.config.Get("alcCorpseMax", 16) > 0) then
			-- The normal Helix/engine ragdoll is never created. DoPlayerDeath below
			-- creates the one authoritative ragdoll, so there is no visible swap.
			return false
		end
	end

	function PLUGIN:ShouldRemoveRagdollOnDeath(client)
		if (ix.config.Get("alcEnabled", true) and ix.config.Get("alcCorpseMax", 16) > 0) then return false end
	end

	function PLUGIN:PlayerSpawn(client)
		client:SetLocalVar("ragdoll", nil)
	end

	function PLUGIN:PlayerInitialSpawn(client)
		self:CleanupCorpses(ix.config.Get("alcCorpseMax", 16))
	end

	function PLUGIN:GetFreeInventoryID()
		for _ = 1, 128 do
			local id = math.random(1000000000, 2147483000)
			if (!ix.item.inventories[id]) then return id end
		end

		local id = 1000000000
		while (ix.item.inventories[id]) do id = id + 1 end
		return id
	end

	function PLUGIN:RemoveEquippableItem(client, item)
		if (!item:GetData("equip")) then return end

		-- Item bases use different names. A protected call prevents one custom
		-- item from aborting creation of the entire corpse.
		if (item.Unequip) then
			pcall(item.Unequip, item, client)
		elseif (item.RemoveOutfit) then
			pcall(item.RemoveOutfit, item, client)
		elseif (item.RemovePart) then
			pcall(item.RemovePart, item, client)
		end
	end

	function PLUGIN:CopyAppearance(client, ragdoll)
		ragdoll:SetSkin(client:GetSkin())
		ragdoll:SetColor(client:GetColor())
		ragdoll:SetMaterial(client:GetMaterial() or "")
		ragdoll:SetModelScale(client:GetModelScale(), 0)

		for i = 0, client:GetNumBodyGroups() - 1 do
			ragdoll:SetBodygroup(i, client:GetBodygroup(i))
		end

		local materials = client:GetMaterials() or {}
		for i = 0, #materials - 1 do
			ragdoll:SetSubMaterial(i, client:GetSubMaterial(i))
		end
	end

	function PLUGIN:TransferCharacterInventory(client, character, corpseInventory)
		local source = character:GetInventory()
		local items = {}

		-- onlyMain is intentional: moving a bag item keeps its own nested Helix
		-- inventory attached. ix.storage automatically synchronizes that nested
		-- inventory, so every backpack cell remains available to the looter.
		for _, item in pairs(source:GetItems(true)) do items[#items + 1] = item end

		-- Empty ordinary/expanded slots first. Equipment and bags are moved last,
		-- because unequipping a backpack can shrink a schema's main inventory.
		table.sort(items, function(a, b)
			local aLate = a.isBag or a:GetData("equip", false)
			local bLate = b.isBag or b:GetData("equip", false)
			if (aLate == bLate) then return a.id < b.id end
			return !aLate and bLate
		end)

		local moved, failed = 0, 0
		for _, item in ipairs(items) do
			if (hook.Run("CanItemMoveToCorpse", client, character, item, corpseInventory) != false) then
				self:RemoveEquippableItem(client, item)
				local x, y = item.gridX, item.gridY
				local called, success, reason = pcall(item.Transfer, item, corpseInventory:GetID(), x, y)
				if (!called) then reason, success = success, false end

				if (success) then
					moved = moved + 1
					if (item.isBag and item.GetInventory and item:GetInventory()) then
						local bagInventory = item:GetInventory()
						bagInventory:RemoveReceiver(client)
						bagInventory:SetOwner(0)
					end
				else
					-- A custom item's global transfer restriction is respected. The item
					-- remains safely in the character inventory instead of being deleted.
					failed = failed + 1
					ErrorNoHalt(string.format("[Afterlight Corpses] Failed to move item #%s (%s): %s\n",
						tostring(item.id), tostring(item.uniqueID), tostring(reason)))
				end
			end
		end

		return moved, failed
	end

	function PLUGIN:IsCorpseEmpty(entity)
		if (!IsValid(entity) or !entity.ixInventory) then return true end
		return next(entity.ixInventory:GetItems()) == nil and (entity:GetMoney() or 0) <= 0
	end

	function PLUGIN:ScheduleEmptyCheck(entity)
		if (!ix.config.Get("alcRemoveWhenEmpty", false) or !IsValid(entity)) then return end

		local timerID = "AfterlightCorpseEmpty" .. entity:EntIndex()
		timer.Create(timerID, math.max(ix.config.Get("alcEmptyRemoveDelay", 10), 0), 1, function()
			if (IsValid(entity) and PLUGIN:IsCorpseEmpty(entity)) then entity:Remove() end
		end)
	end

	function PLUGIN:DisposeInventory(inventory)
		if (!inventory) then return end

		-- Remove nested contents before their bag item. This prevents database
		-- rows from being orphaned when an unlooted corpse decays.
		local items, nestedIDs = {}, {}
		for _, item in pairs(inventory:GetItems()) do
			items[#items + 1] = item
			if (item.isBag and item.GetInventory and item:GetInventory()) then
				nestedIDs[#nestedIDs + 1] = item:GetInventory():GetID()
			end
		end
		table.sort(items, function(a, b) return (a.isBag and 1 or 0) < (b.isBag and 1 or 0) end)

		for _, item in ipairs(items) do
			if (ix.item.instances[item.id]) then
				local removed, reason = pcall(item.Remove, item)
				if (!removed) then ErrorNoHalt("[Afterlight Corpses] Item cleanup failed: " .. tostring(reason) .. "\n") end
			end
		end

		for _, id in ipairs(nestedIDs) do ix.item.inventories[id] = nil end
		ix.item.inventories[inventory:GetID()] = nil
	end

	function PLUGIN:AttachCorpseInventory(client, character, entity)
		local source = character:GetInventory()
		local width, height = source:GetSize()
		local inventory = ix.inventory.Create(width, height, self:GetFreeInventoryID())
		inventory.noSave = true
		inventory.vars = inventory.vars or {}
		inventory.vars.isCorpse = true
		entity.ixInventory = inventory

		local corpseName = character:GetName()
		entity.ixCorpseName = corpseName
		entity.ixCorpseMoney = math.Clamp(math.floor(character:GetMoney() *
			ix.config.Get("alcMoneyPercent", 100) / 100), 0, character:GetMoney())

		-- These methods let the native, validated Helix storage-money protocol do
		-- all withdrawals/deposits. GetInventory/GetDisplayName also make the
		-- official logging plugin safe for ragdolls.
		entity.GetInventory = function(this) return this.ixInventory end
		entity.GetDisplayName = function(this) return L("afterlightCorpse", this.ixCorpseName or corpseName) end
		entity.GetMoney = function(this) return math.max(math.floor(this.ixCorpseMoney or 0), 0) end
		entity.SetMoney = function(this, amount)
			this.ixCorpseMoney = math.max(math.floor(tonumber(amount) or 0), 0)
			PLUGIN:ScheduleEmptyCheck(this)
		end

		if (entity.ixCorpseMoney > 0) then
			character:SetMoney(character:GetMoney() - entity.ixCorpseMoney)
		end

		self:TransferCharacterInventory(client, character, inventory)
		return inventory
	end

	function PLUGIN:RegisterCorpse(client, entity)
		local decayTime = ix.config.Get("alcDecayTime", 300)
		local decayTimer = "AfterlightCorpseDecay" .. entity:EntIndex()
		local emptyTimer = "AfterlightCorpseEmpty" .. entity:EntIndex()
		entity.ixCorpseCreatedAt = CurTime()
		entity.ixCorpseDecayTimer = decayTimer

		entity:RemoveCallOnRemove("fixer")
		entity:CallOnRemove("AfterlightLootableCorpse", function(ragdoll)
			timer.Remove(decayTimer)
			timer.Remove(emptyTimer)

			if (ragdoll.ixInventory) then
				ix.storage.Close(ragdoll.ixInventory)
				PLUGIN:DisposeInventory(ragdoll.ixInventory)
				ragdoll.ixInventory = nil
			end

			if (IsValid(client) and !client:Alive()) then client:SetLocalVar("ragdoll", nil) end
			for i = #PLUGIN.corpses, 1, -1 do
				if (PLUGIN.corpses[i] == ragdoll) then table.remove(PLUGIN.corpses, i) end
			end
		end)

		if (decayTime > 0) then
			timer.Create(decayTimer, decayTime, 1, function()
				if (IsValid(entity)) then entity:Remove() end
			end)
		end

		self.corpses[#self.corpses + 1] = entity
		self:CleanupCorpses(ix.config.Get("alcCorpseMax", 16))
	end

	function PLUGIN:CleanupCorpses(maxCorpses)
		maxCorpses = math.Clamp(tonumber(maxCorpses) or ix.config.Get("alcCorpseMax", 16), 0, self.hardCorpseMax)

		for i = #self.corpses, 1, -1 do
			if (!IsValid(self.corpses[i])) then table.remove(self.corpses, i) end
		end

		while (#self.corpses > maxCorpses) do
			local entity = table.remove(self.corpses, 1)
			if (IsValid(entity)) then entity:Remove() end
		end
	end

	function PLUGIN:DoPlayerDeath(client, attacker, damageInfo)
		if (!ix.config.Get("alcEnabled", true)) then return end
		if (hook.Run("ShouldSpawnPlayerCorpse", client, attacker, damageInfo) == false) then return end
		if (ix.config.Get("alcCorpseMax", 16) <= 0) then return end

		local character = client:GetCharacter()
		if (!character or !character:GetInventory()) then return end

		-- Reuse a pre-existing Helix unconscious ragdoll, otherwise create exactly
		-- one server ragdoll. CreateServerRagdoll copies the current bone pose and
		-- bone velocities, preventing the T-pose/replacement sequence.
		local reused = IsValid(client.ixRagdoll)
		local entity = reused and client.ixRagdoll or client:CreateServerRagdoll()
		if (!IsValid(entity)) then return end

		entity.ixLootableCorpse = true
		entity.ixPlayer = nil
		self:CopyAppearance(client, entity)

		if (!reused and damageInfo) then
			local physics = entity:GetPhysicsObject()
			local force = damageInfo:GetDamageForce()
			if (IsValid(physics) and force:LengthSqr() > 0) then
				physics:ApplyForceOffset(force, damageInfo:GetDamagePosition())
			end
		end

		self:AttachCorpseInventory(client, character, entity)
		self:RegisterCorpse(client, entity)

		-- Break Helix's player-ragdoll ownership only after callbacks were removed.
		-- Respawn can no longer remove this corpse or spawn a replacement.
		client.ixRagdoll = nil
		client:SetLocalVar("ragdoll", entity:EntIndex())

		hook.Run("OnAfterlightCorpseCreated", client, entity, entity.ixInventory)
	end

	function PLUGIN:MaintainCorpses()
		self:CleanupCorpses(ix.config.Get("alcCorpseMax", 16))
		local decayTime = ix.config.Get("alcDecayTime", 300)

		for _, entity in ipairs(table.Copy(self.corpses)) do
			if (IsValid(entity)) then
				local corpse = entity
				local timerID = corpse.ixCorpseDecayTimer
				if (decayTime <= 0) then
					if (timerID) then timer.Remove(timerID) end
				else
					local remaining = corpse.ixCorpseCreatedAt + decayTime - CurTime()
					if (remaining <= 0) then
						corpse:Remove()
					elseif (timerID) then
						timer.Create(timerID, remaining, 1, function()
							if (IsValid(corpse)) then corpse:Remove() end
						end)
					end
				end
			end
		end
	end

	timer.Create("AfterlightCorpseMaintenance", 5, 0, function()
		if (PLUGIN) then PLUGIN:MaintainCorpses() end
	end)

	function PLUGIN:OnUnload()
		timer.Remove("AfterlightCorpseMaintenance")
		for _, entity in ipairs(table.Copy(self.corpses)) do
			if (IsValid(entity)) then entity:Remove() end
		end
		self.corpses = {}
	end

	function PLUGIN:PlayerUse(client, entity)
		if (!ix.config.Get("alcEnabled", true) or !IsValid(entity) or !entity.ixLootableCorpse or !entity.ixInventory) then return end
		if (!client:Alive() or !client:GetCharacter()) then return false end

		local maxDistance = ix.config.Get("alcLootDistance", 128)
		if (client:GetPos():DistToSqr(entity:GetPos()) > maxDistance * maxDistance) then
			client:NotifyLocalized("afterlightCorpseTooFar")
			return false
		end

		if (hook.Run("CanPlayerLootAfterlightCorpse", client, entity) == false) then return false end

		local multiple = ix.config.Get("alcMultipleLooters", false)
		if (!multiple and ix.storage.InUse(entity.ixInventory) and !ix.storage.InUseBy(entity.ixInventory, client)) then
			client:NotifyLocalized("afterlightCorpseBusy")
			return false
		end

		client.ixAfterlightCorpseUse = client.ixAfterlightCorpseUse or 0
		if (client.ixAfterlightCorpseUse > CurTime()) then return false end
		client.ixAfterlightCorpseUse = CurTime() + 0.5

		ix.storage.Open(client, entity.ixInventory, {
			entity = entity,
			name = L("afterlightCorpse", entity.ixCorpseName or "Unknown"),
			bMultipleUsers = multiple,
			searchText = "@afterlightSearchingCorpse",
			searchTime = ix.config.Get("alcSearchTime", 2.5),
			OnPlayerClose = function() PLUGIN:ScheduleEmptyCheck(entity) end
		})

		return false
	end
end
