local PLUGIN = PLUGIN

PLUGIN.name = "Afterlight Fortitude"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Стойкость: пассивный каменный барьер (временные хп с регенерацией после 20с без урона) и активация — добавочный барьер, временная Выносливость и поглощение урона с каждой атаки."
PLUGIN.version = "1.0.0"

-- Каждый уровень дисциплины — отдельная «способность» в колесе интерфейса
-- (afterlight_discipline_interface): игрок видит уровни 1..5 по своим точкам
-- в чарлисте, выбирает нужный сегмент и активирует его своей кнопкой.
-- Трата крови, кулдауны (30с, на 5-м — 40с), проверки доступа и обратная
-- связь — на стороне интерфейсного шлюза; здесь параметры и реализация.
function PLUGIN:InitializedPlugins()
	if (!ix.disciplines or !isfunction(ix.disciplines.RegisterPower)) then
		ErrorNoHalt("[Afterlight Fortitude] API Discipline Interface недоступно — способности не зарегистрированы.\n")
		return
	end

	for level = 1, 5 do
		local data = ix.fortitude.GetLevelData(level)

		-- В сегментах колеса имя рисуется целиком, поэтому слово
		-- «Стойкость» не дублируем: центр колеса показывает дисциплину.
		ix.disciplines.RegisterPower("fortitude", "fortitude_" .. level, {
			name = "Уровень " .. level,
			description = string.format("Стойкость %d: барьер +%d хп, Выносливость +%d, гасит %d урона с каждой атаки, действует %d секунд.",
				level, data.bonus, data.stamina, data.absorb, data.duration),
			level = level,
			cooldown = data.cooldown,
			GetVitaeCost = function()
				return data.vitae
			end,
			CanActivate = function(context)
				return IsValid(context.client) and context.client:Alive(), "notAlive"
			end,
			OnActivate = function(context)
				return PLUGIN:ActivateFortitude(context.client, context.character, level)
			end
		})
	end
end
