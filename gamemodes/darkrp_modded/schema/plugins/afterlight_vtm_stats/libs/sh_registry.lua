ix.vtm = ix.vtm or {}
ix.vtm.stats = ix.vtm.stats or {}
ix.vtm.stats.list = {}
ix.vtm.stats.groups = {}
ix.vtm.stats.order = {}

ix.vtm.stats.MAX_VALUE = 5
ix.vtm.stats.CREATION_POINTS = {attributes = 12, abilities = 17, virtues = 7}
ix.vtm.stats.VAMPIRE_BONUS = {attributes = 3, abilities = 8, virtues = 0}
ix.vtm.stats.CATEGORIES = {"attributes", "abilities", "virtues"}
ix.vtm.stats.POINT_CATEGORIES = {"attributes", "abilities", "virtues", "disciplines"}

local function Register(id, name, category, group, base)
	local definition = {
		id = id, name = name, category = category, group = group,
		base = base, max = ix.vtm.stats.MAX_VALUE,
		index = #ix.vtm.stats.order + 1
	}
	ix.vtm.stats.list[id] = definition
	ix.vtm.stats.order[#ix.vtm.stats.order + 1] = id
	ix.vtm.stats.groups[category] = ix.vtm.stats.groups[category] or {}
	ix.vtm.stats.groups[category][group] = ix.vtm.stats.groups[category][group] or {}
	table.insert(ix.vtm.stats.groups[category][group], id)
	return definition
end

-- Characteristics: every value starts at one.
Register("strength", "Сила", "attributes", "physical", 1)
Register("dexterity", "Ловкость", "attributes", "physical", 1)
Register("stamina", "Выносливость", "attributes", "physical", 1)
Register("charisma", "Харизма", "attributes", "social", 1)
Register("manipulation", "Манипуляция", "attributes", "social", 1)
Register("appearance", "Привлекательность", "attributes", "social", 1)
Register("perception", "Восприятие", "attributes", "mental", 1)
Register("intelligence", "Интеллект", "attributes", "mental", 1)
Register("wits", "Смекалка", "attributes", "mental", 1)

-- Talents from the supplied VTM character sheet.
Register("athletics", "Атлетика", "abilities", "talents", 0)
Register("alertness", "Бдительность", "abilities", "talents", 0)
Register("brawl", "Драка", "abilities", "talents", 0)
Register("intimidation", "Запугивание", "abilities", "talents", 0)
Register("expression", "Красноречие", "abilities", "talents", 0)
Register("leadership", "Лидерство", "abilities", "talents", 0)
Register("streetwise", "Уличное чутьё", "abilities", "talents", 0)
Register("subterfuge", "Хитрость", "abilities", "talents", 0)
Register("awareness", "Шестое чувство", "abilities", "talents", 0)
ix.vtm.stats.list.awareness.vampireOnly = true
Register("empathy", "Эмпатия", "abilities", "talents", 0)

-- Skills from the supplied VTM character sheet.
Register("drive", "Вождение", "abilities", "skills", 0)
Register("larceny", "Воровство", "abilities", "skills", 0)
Register("survival", "Выживание", "abilities", "skills", 0)
Register("performance", "Исполнение", "abilities", "skills", 0)
Register("animal_ken", "Обр. с животными", "abilities", "skills", 0)
Register("crafts", "Ремесло", "abilities", "skills", 0)
Register("stealth", "Скрытность", "abilities", "skills", 0)
Register("firearms", "Стрельба", "abilities", "skills", 0)
Register("melee", "Хол. оружие", "abilities", "skills", 0)
Register("etiquette", "Этикет", "abilities", "skills", 0)

-- Knowledges from the supplied VTM character sheet.
Register("academics", "Гуманитарные науки", "abilities", "knowledges", 0)
Register("science", "Естественные науки", "abilities", "knowledges", 0)
Register("law", "Законы", "abilities", "knowledges", 0)
Register("computer", "Информатика", "abilities", "knowledges", 0)
Register("medicine", "Медицина", "abilities", "knowledges", 0)
Register("occult", "Оккультизм", "abilities", "knowledges", 0)
Register("politics", "Политика", "abilities", "knowledges", 0)
Register("investigation", "Расследование", "abilities", "knowledges", 0)
Register("finance", "Финансы", "abilities", "knowledges", 0)
Register("technology", "Электроника", "abilities", "knowledges", 0)

-- Virtues: every value starts at one; humans and vampires share seven points.
Register("conscience", "Совесть / Решимость", "virtues", "virtues", 1)
Register("self_control", "Самоконтроль / Инстинкты", "virtues", "virtues", 1)
Register("courage", "Смелость", "virtues", "virtues", 1)

ix.vtm.stats.groupNames = {
	physical = "Физические", social = "Социальные", mental = "Ментальные",
	talents = "Таланты", skills = "Навыки", knowledges = "Знания",
	virtues = ""
}

-- v1.0 Bloodlines ability IDs are converted without discarding invested dots.
ix.vtm.stats.legacyAliases = {
	dodge = "athletics",
	security = "larceny",
	scholarship = "academics"
}

function ix.vtm.stats.ResolveID(id)
	id = string.lower(tostring(id or ""))
	return ix.vtm.stats.legacyAliases[id] or id
end

function ix.vtm.stats.GetDefinition(id)
	return ix.vtm.stats.list[ix.vtm.stats.ResolveID(id)]
end

function ix.vtm.stats.GetCategory(id)
	local definition = ix.vtm.stats.GetDefinition(id)
	return definition and definition.category
end
