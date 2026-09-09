-- Creation visibility and scoreboard privacy for vampire factions.
-- Loaded clientside by Helix from this plugin's derma directory.

local function IsCitizenFaction(index)
	return ix.vampire and ix.vampire.IsCitizenFaction(index)
end

local function IsVampireFaction(index)
	return ix.vampire and ix.vampire.GetSectByFaction(index) != nil
end

-- Stock ixCharMenuNew calls this function when constructing its faction list.
-- Restricting it here also hides stale faction whitelists left in local data.
if (!ix.faction.afterlightOriginalHasWhitelist) then
	ix.faction.afterlightOriginalHasWhitelist = ix.faction.HasWhitelist

	function ix.faction.HasWhitelist(faction)
		if (!IsCitizenFaction(faction)) then
			return false
		end

		return ix.faction.afterlightOriginalHasWhitelist(faction)
	end
end

local function PatchCharacterInfo()
	local information = vgui.GetControlTable("ixCharacterInfo")
	if (!information or information.afterlightVampireInfo) then
		return information != nil
	end

	information.afterlightVampireInfo = true
	local originalUpdate = information.Update

	local function CreateRow(category)
		local row = category:Add("ixListRow")
		row:SetList(category.list)
		row:Dock(TOP)
		row:SetVisible(false)
		return row
	end

	function information:Update(character)
		originalUpdate(self, character)
		if (!character or !IsValid(self.characterInfo)) then return end

		local category = self.characterInfo

		-- v1.0-v1.6 created these controls through character-info hooks. Remove
		-- them after the stock update so an older loaded copy cannot leave the
		-- duplicate Вид / Раса-клан / Поколение block shown in the screenshot.
		for _, field in ipairs({"vampireSpecies", "vampireRace", "vampireGeneration"}) do
			local legacy = category[field]
			if (IsValid(legacy)) then legacy:Remove() end
			category[field] = nil
		end

		local clan = character.GetVampireClan and character:GetVampireClan()
		local vampireFaction = IsVampireFaction(character:GetFaction())
		local visible = vampireFaction or clan != nil or
			(character.GetSpecies and character:GetSpecies() == "vampire")

		-- Rows are created lazily. A regular Citizen therefore never receives
		-- placeholder ixListRow controls with their default "Label / Text".
		if (visible and !IsValid(category.afterlightVampireSpecies)) then
			category.afterlightVampireSpecies = CreateRow(category)
			category.afterlightVampireClan = CreateRow(category)
			category.afterlightVampireGeneration = CreateRow(category)
		end

		local species = category.afterlightVampireSpecies
		local clanRow = category.afterlightVampireClan
		local generation = category.afterlightVampireGeneration
		if (!IsValid(species)) then return end

		species:SetVisible(visible)
		clanRow:SetVisible(visible)
		generation:SetVisible(visible)

		if (visible) then
			species:SetLabelText("Вид")
			species:SetText("Вампир")
			clanRow:SetLabelText("Клан")
			clanRow:SetText(clan and clan.name or "Не назначен")
			generation:SetLabelText("Поколение")
			generation:SetText(tostring(character:GetGeneration()))
			species:SizeToContents()
			clanRow:SizeToContents()
			generation:SizeToContents()
		end

		category:SizeToContents()
	end

	return true
end

local function PatchScoreboard()
	local category = vgui.GetControlTable("ixScoreboardFaction")
	if (!category or category.afterlightVampireMerged) then
		return category != nil
	end

	category.afterlightVampireMerged = true
	local originalUpdate = category.Update

	function category:Update()
		local faction = self.faction
		if (!faction) then return end

		-- Vampire section headers must never disclose sect population.
		if (IsVampireFaction(faction.index)) then
			self:SetVisible(false)
			return
		end

		-- Non-vampire, non-Citizen factions retain stock scoreboard behavior.
		if (!IsCitizenFaction(faction.index)) then
			return originalUpdate(self)
		end

		-- The Citizen section is the public player pool: regular Citizens and all
		-- vampires are listed together, without separate Camarilla/Sabbat/Anarch
		-- categories. Rows still use the stock recognition/privacy mechanics.
		local merged = {}
		for _, client in ipairs(player.GetAll()) do
			if (IsValid(client) and client:GetCharacter()) then
				local clientFaction = client:Team()
				if (IsCitizenFaction(clientFaction) or IsVampireFaction(clientFaction)) then
					merged[#merged + 1] = client
				end
			end
		end

		local hasPlayers = false
		for index, client in ipairs(merged) do
			if (!IsValid(client.ixScoreboardSlot)) then
				if (self:AddPlayer(client, index)) then
					hasPlayers = true
				end
			else
				client.ixScoreboardSlot:Update()
				hasPlayers = true
			end
		end

		self:SetVisible(hasPlayers)
	end

	return true
end

-- Usually available immediately; timer also covers unusual UI/plugin order.
local function InstallClientPatches()
	return PatchCharacterInfo() and PatchScoreboard()
end

if (!InstallClientPatches()) then
	timer.Create("AfterlightVampireClientPatches", 0.1, 100, function()
		if (InstallClientPatches()) then
			timer.Remove("AfterlightVampireClientPatches")
		end
	end)
end

hook.Add("InitPostEntity", "AfterlightVampireClientPatches", function()
	-- Never return InstallClientPatches() here. A non-nil hook result stops
	-- Garry's Mod before GM:InitPostEntity can run; Helix creates ix.gui.bars
	-- and synchronizes client options in that gamemode callback.
	InstallClientPatches()
end)
