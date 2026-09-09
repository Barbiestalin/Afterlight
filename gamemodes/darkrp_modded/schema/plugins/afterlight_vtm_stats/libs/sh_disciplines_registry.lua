ix.disciplines = ix.disciplines or {}
ix.disciplines.list = ix.disciplines.list or {}
ix.disciplines.order = ix.disciplines.order or {}
ix.disciplines.aliases = ix.disciplines.aliases or {
	blood_sorcery = "thaumaturgy_blood",
	obeah = "valeren",
	oblivion = "obtenebration"
}
ix.disciplines.MAX_LEVEL = 5

function ix.disciplines.ResolveID(id)
	id = string.lower(string.Trim(tostring(id or "")))
	return ix.disciplines.aliases[id] or id
end

function ix.disciplines.Register(id, name)
	id = ix.disciplines.ResolveID(id)
	assert(id != "" and isstring(name) and name != "", "invalid discipline definition")

	if (!ix.disciplines.list[id]) then
		ix.disciplines.order[#ix.disciplines.order + 1] = id
	end

	ix.disciplines.list[id] = {
		id = id,
		name = name,
		maxLevel = ix.disciplines.MAX_LEVEL,
		index = #ix.disciplines.order
	}

	return ix.disciplines.list[id]
end

function ix.disciplines.Get(id)
	return ix.disciplines.list[ix.disciplines.ResolveID(id)]
end

local definitions = {
	{"animalism", "Анимализм"},
	{"celerity", "Стремительность"},
	{"vicissitude", "Изменчивость"},
	{"potence", "Могущество"},
	{"dominate", "Доминирование"},
	{"presence", "Присутствие"},
	{"auspex", "Прорицание"},
	{"dementation", "Помешательство"},
	{"fortitude", "Стойкость"},
	{"protean", "Превращение"},
	{"thanatosis", "Смертоносность"},
	{"obfuscate", "Затемнение"},
	{"obtenebration", "Власть над тенью"},
	{"chimerstry", "Химерия"},
	{"valeren", "Валерен"},
	{"necromancy", "Некромантия"},
	{"serpentis", "Серпентис"},
	{"thaumaturgy_blood", "Тауматургия - Путь Крови"},
	{"thaumaturgy_fire", "Тауматургия - Путь Огня"},
	{"thaumaturgy_conjuring", "Тауматургия - Сотворение"},
	{"thaumaturgy_hearth", "Тауматургия - Путь Домашнего Очага"}
}

for _, definition in ipairs(definitions) do
	ix.disciplines.Register(definition[1], definition[2])
end

-- Malkavians use Dementation in this ruleset even though an older Foundation
-- build listed Dominate. Other clans use their Foundation native lists, with
-- aliases above translating old Obeah/Oblivion/Blood Sorcery identifiers.
ix.disciplines.nativeOverrides = {
	malkavian = {"auspex", "dementation", "obfuscate"}
}

function ix.disciplines.GetNativeDisciplines(character)
	if (!character or !character.GetVampireClan) then return {} end
	local clan = character:GetVampireClan()
	if (!clan) then return {} end

	local source = ix.disciplines.nativeOverrides[clan.id] or clan.nativeDisciplines or {}
	local result, seen = {}, {}

	for _, id in ipairs(source) do
		id = ix.disciplines.ResolveID(id)
		if (ix.disciplines.list[id] and !seen[id]) then
			seen[id] = true
			result[#result + 1] = id
		end
	end

	return result
end

function ix.disciplines.IsNative(character, disciplineID)
	disciplineID = ix.disciplines.ResolveID(disciplineID)
	for _, id in ipairs(ix.disciplines.GetNativeDisciplines(character)) do
		if (id == disciplineID) then return true end
	end
	return false
end
