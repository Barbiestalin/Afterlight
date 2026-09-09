--[[
	Afterlight — генератор хроник ночи
	------------------------------------------------------------------
	Небольшой автономный модуль: никаких зависимостей от Helix, GMOD
	или сетевых библиотек. Работает и в Garry's Mod (как обычный
	 autorun-скрипт), и под «чистым» Lua 5.1+ из консоли.

	Использование:
		AfterlightChronicle.Seed(20260909)
		print(AfterlightChronicle.Format(AfterlightChronicle.NewChronicle()))

	Демонстрационный запуск при загрузке файла намеренно отключён:
		AFTERLIGHT_CHRONICLE_DEMO = true
--]]

AfterlightChronicle = AfterlightChronicle or {}
local Chronicle = AfterlightChronicle

Chronicle.version = "1.0.0"

----------------------------------------------------------------------
-- Детерминированный генератор случайных чисел.
-- math.random() в Garry's Mod расшарен на весь проект, поэтому
-- генератор держит собственное зерно и никого не «портит».
----------------------------------------------------------------------

-- Множитель подобран так, что seed * MULTIPLIER < 2^53: все промежуточные
-- вычисления остаются точными и на doubles (в Garry's Mod числа именно такие),
-- иначе младшие биты «съедаются» и генератор залипает.
local MODULUS = 2147483647 -- 2^31 - 1, простое число Мерсенна
local MULTIPLIER = 48271   -- проверенный множитель Парка-Миллера

Chronicle.seed = 1

function Chronicle.Seed(value)
	value = tonumber(value) or os.time()
	Chronicle.seed = (math.floor(value) % MODULUS)
	if (Chronicle.seed <= 0) then
		Chronicle.seed = Chronicle.seed + MODULUS - 1
	end
	return Chronicle.seed
end

function Chronicle.Next()
	Chronicle.seed = (Chronicle.seed * MULTIPLIER) % MODULUS
	return Chronicle.seed / MODULUS
end

function Chronicle.randomInt(min, max)
	if (max < min) then
		min, max = max, min
	end
	return min + math.floor(Chronicle.Next() * (max - min + 1))
end

function Chronicle.chance(probability)
	return Chronicle.Next() < (probability or 0.5)
end

function Chronicle.pick(list)
	if (#list == 0) then
		return nil
	end
	return list[Chronicle.randomInt(1, #list)]
end

function Chronicle.shuffle(list)
	local result = {}
	for index = 1, #list do
		result[index] = list[index]
	end
	for index = #result, 2, -1 do
		local other = Chronicle.randomInt(1, index)
		result[index], result[other] = result[other], result[index]
	end
	return result
end

----------------------------------------------------------------------
-- Словари. Кириллица оставлена «как есть»: файл читается в UTF-8.
----------------------------------------------------------------------

Chronicle.words = {
	firstNames = {"Северин", "Астарот", "Лилит", "Вальтер", "Изабель", "Морриган", "Кассий", "Эвелина", "Родерик", "Ноктис"},
	lastNames = {"фон Врац", "Кровавый", "Пепельный", "Ночной", "Безмолвный", "Тёмный", "Изгард", "Теневой"},
	titles = {"Хранитель клятвы", "Хроникёр ночи", "Собиратель теней", "Ключник склепа", "Последний свидетель"},
	places = {"Старый собор", "Розарий", "Колодец шёпота", "Библиотека Пепла", "Восточная галерея", "Часовая башня"},
	-- Те же места в предложном падеже: для шаблонов вида «в ... найдено».
	placesIn = {"Старом соборе", "Розарии", "Колодце шёпота", "Библиотеке Пепла", "Восточной галерее", "Часовой башне"},
	omens = {"погасла свеча", "троекратно прокричал ворон", "зеркало покрылось инеем", "часы пошли вспять", "розы расцвели в январе"},
	relics = {"серебряный ключ", "обсидиановый крест", "сожжённая молитва", "перстень без камня", "фонарь с синим стеклом"},
	traces = {"тишина вместо ответа", "след, уходящий в стену", "запах гари и роз", "опрокинутый подсвечник", "нить от плаща на решётке", "надпись, стёртая ладонью"}
}

----------------------------------------------------------------------
-- Генераторы
----------------------------------------------------------------------

function Chronicle.NewName()
	local words = Chronicle.words
	local name = Chronicle.pick(words.firstNames) .. " " .. Chronicle.pick(words.lastNames)
	if (Chronicle.chance(0.35)) then
		name = name .. ", " .. Chronicle.pick(words.titles)
	end
	return name
end

-- Шаблоны намеренно составлены из существительных: так генератор
-- не ломает русскую грамматику на родовых окончаниях глаголов.
local EVENT_TEMPLATES = {
	"%s — %s, %s.",
	"В %s найдено: %s. Со слов: %s.",
	"%s: «%s»."
}

function Chronicle.NewEvent()
	local words = Chronicle.words
	local template = Chronicle.pick(EVENT_TEMPLATES)

	if (template == EVENT_TEMPLATES[2]) then
		return string.format(template, Chronicle.pick(words.placesIn), Chronicle.pick(words.traces), Chronicle.NewName())
	end

	if (template == EVENT_TEMPLATES[3]) then
		return string.format(template, Chronicle.NewName(), Chronicle.pick(words.traces))
	end

	return string.format(template, Chronicle.NewName(), Chronicle.pick(words.places), Chronicle.pick(words.traces))
end

function Chronicle.NewOmen()
	return "Знамение: " .. Chronicle.pick(Chronicle.words.omens) ..
		" (" .. Chronicle.randomInt(1, 28) .. " число, " ..
		string.format("%02d:%02d", Chronicle.randomInt(0, 23), Chronicle.randomInt(0, 59)) .. ")."
end

-- Собирает запись хроники: заголовок, место, знамение и 1-3 события.
function Chronicle.NewChronicle()
	local entry = {
		index = Chronicle.randomInt(1, 999),
		author = Chronicle.NewName(),
		place = Chronicle.pick(Chronicle.words.places),
		relic = Chronicle.pick(Chronicle.words.relics),
		omen = Chronicle.NewOmen(),
		events = {}
	}

	local count = Chronicle.randomInt(1, 3)
	for _ = 1, count do
		entry.events[#entry.events + 1] = Chronicle.NewEvent()
	end

	return entry
end

function Chronicle.Format(entry)
	entry = entry or Chronicle.NewChronicle()

	local lines = {}
	lines[#lines + 1] = string.format("=== Запись №%d ===", entry.index)
	lines[#lines + 1] = "Место: " .. entry.place
	lines[#lines + 1] = "Автор: " .. entry.author
	lines[#lines + 1] = "Находка: " .. entry.relic
	lines[#lines + 1] = entry.omen

	for index = 1, #entry.events do
		lines[#lines + 1] = "— " .. entry.events[index]
	end

	return table.concat(lines, "\n")
end

----------------------------------------------------------------------
-- Демонстрация (включается глобальным флагом)
----------------------------------------------------------------------

function Chronicle.demo(seed)
	Chronicle.Seed(seed)
	for _ = 1, 3 do
		print(Chronicle.Format(Chronicle.NewChronicle()))
		print("")
	end
end

if (rawget(_G, "AFTERLIGHT_CHRONICLE_DEMO")) then
	Chronicle.demo(rawget(_G, "AFTERLIGHT_CHRONICLE_DEMO"))
end

return Chronicle
