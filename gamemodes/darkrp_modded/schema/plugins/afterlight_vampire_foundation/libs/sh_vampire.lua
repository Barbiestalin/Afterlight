ix.vampire = ix.vampire or {}
ix.vampire.clans = ix.vampire.clans or {}
ix.vampire.clans.list = ix.vampire.clans.list or {}

-- Replace this table with Schema.vampireModels in schema/sh_schema.lua.
-- The one fallback model only prevents Helix's creation menu from receiving
-- an empty model list before server-specific model paths are configured.
ix.vampire.models = Schema.vampireModels or {
	"models/Humans/Group01/male_01.mdl"
}

ix.vampire.sects = {
	camarilla = {name = "Камарилья", flag = "M", apexRole = "camarilla_prince"},
	sabbat = {name = "Шабаш", flag = "S", apexRole = "sabbat_bishop"},
	anarch = {name = "Анархи", flag = "A", apexRole = "anarch_baron"}
}

local allSects = {camarilla = true, sabbat = true, anarch = true}

function ix.vampire.clans.Register(id, data)
	assert(isstring(id) and id != "", "invalid vampire race/clan id")
	data.id = id
	data.allowedSects = data.allowedSects or table.Copy(allSects)
	data.nativeDisciplines = data.nativeDisciplines or {}
	ix.vampire.clans.list[id] = data
	return data
end

function ix.vampire.clans.Get(id)
	return ix.vampire.clans.list[string.lower(tostring(id or ""))]
end

function ix.vampire.clans.IsAllowedInSect(clanID, sectID)
	local clan = ix.vampire.clans.Get(clanID)
	return clan != nil and clan.allowedSects[sectID] == true
end

function ix.vampire.GetSectByFaction(factionIndex)
	local faction = ix.faction and ix.faction.indices[factionIndex]
	return faction and faction.vampireSect or nil
end

-- New characters always begin as regular Citizens. Vampire identity and sect
-- membership are applied later by the server-side administrative workflow.
function ix.vampire.IsCitizenFaction(factionIndex)
	local index = tonumber(factionIndex)
	local faction = index and ix.faction.indices[index] or ix.faction.Get(factionIndex)

	if (!faction) then return false end
	if (FACTION_CITIZEN and faction.index == FACTION_CITIZEN) then return true end

	return faction.uniqueID == "citizen"
end

function ix.vampire.GetFactionBySect(sectID)
	for _, faction in ipairs(ix.faction.indices or {}) do
		if (faction.vampireSect == sectID) then return faction.index end
	end
end

function ix.vampire.GetClassByUniqueID(uniqueID)
	for index, class in ipairs(ix.class.list or {}) do
		if (class.uniqueID == uniqueID) then return index, class end
	end
end

function ix.vampire.GetDefaultClass(factionIndex)
	for index, class in ipairs(ix.class.list or {}) do
		if (class.faction == factionIndex and class.isDefault) then return index, class end
	end
end

local definitions = {
	{"tremere", "Тремер", "Кровавые узы и зависимость от клановой иерархии.", {"auspex", "dominate", "blood_sorcery"}},
	{"toreador", "Тореадор", "Поглощённость красотой и объектами восхищения.", {"auspex", "celerity", "presence"}},
	{"ventrue", "Вентру", "Избирательное питание только подходящим типом крови.", {"dominate", "fortitude", "presence"}},
	{"brujah", "Бруха", "Повышенная склонность к ярости и безумию.", {"celerity", "potence", "presence"}},
	{"gangrel", "Гангрел", "Звериные черты после приступов безумия.", {"animalism", "fortitude", "protean"}},
	{"lasombra_antitribu", "Ласомбра Антитрибу", "Клановое проклятие Ласомбра и статус отступников.", {"dominate", "oblivion", "potence"}},
	{"nosferatu", "Носферату", "Неустранимая чудовищная внешность.", {"animalism", "obfuscate", "potence"}},
	{"tzimisce", "Цимисхи", "Привязанность к родной земле и месту покоя.", {"animalism", "auspex", "vicissitude"}},
	{"lasombra", "Ласомбра", "Отсутствие нормального отражения и конфликт с технологиями.", {"dominate", "oblivion", "potence"}},
	{"pander", "Пандер", "Отсутствие признанной крови и тяжёлая социальная стигма.", {}},
	{"malkavian", "Малкавиан", "Неизлечимое психическое расстройство.", {"auspex", "dominate", "obfuscate"}},
	{"gargoyle", "Горгульи", "Искусственное происхождение и уязвимость перед контролем создателей.", {"flight", "fortitude", "potence", "visceratika"}},
	{"setite", "Последователи Сета", "Особая уязвимость к яркому свету.", {"obfuscate", "presence", "serpentis"}},
	{"ravnos", "Равнос", "Навязчивая порочная склонность, требующая регулярного удовлетворения.", {"animalism", "chimerstry", "fortitude"}},
	{"samedi", "Самеди", "Неустранимый облик разлагающегося мертвеца.", {"fortitude", "obfuscate", "thanatosis"}},
	{"salubri", "Салюбри", "Третий глаз и преследование со стороны других вампиров.", {"auspex", "fortitude", "obeah"}}
}

for _, data in ipairs(definitions) do
	ix.vampire.clans.Register(data[1], {
		name = data[2],
		weakness = {id = data[1] .. "_weakness", description = data[3]},
		nativeDisciplines = data[4],
		allowedSects = table.Copy(allSects)
	})
end

local charMeta = ix.meta.character

function charMeta:IsVampire()
	return self:GetSpecies() == "vampire" and ix.vampire.clans.Get(self:GetVampireRace()) != nil
end

function charMeta:GetVampireClan()
	return ix.vampire.clans.Get(self:GetVampireRace())
end

function charMeta:GetVampireSect()
	return ix.vampire.GetSectByFaction(self:GetFaction())
end
