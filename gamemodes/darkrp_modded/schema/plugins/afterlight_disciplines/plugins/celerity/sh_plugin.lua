local PLUGIN = PLUGIN

PLUGIN.name = "Afterlight Celerity"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Стремительность: пять по отдельности выбираемых уровней — скорость, спринт, темп ближнего боя и перезарядки, временная Ловкость, трейл воздуха и уклонения."
PLUGIN.version = "1.0.0"

-- Каждый уровень дисциплины — отдельная «способность» в колесе интерфейса
-- (afterlight_discipline_interface): игрок видит уровни 1..N по своим точкам
-- в чарлисте, выбирает нужный сегмент и активирует его своей кнопкой.
-- Трата крови, кулдауны, проверки доступа и обратная связь — на стороне
-- интерфейсного шлюза; здесь только параметры и реализация эффектов.
function PLUGIN:InitializedPlugins()
	if (!ix.disciplines or !isfunction(ix.disciplines.RegisterPower)) then
		ErrorNoHalt("[Afterlight Celerity] API Discipline Interface недоступно — способности не зарегистрированы.\n")
		return
	end

	for level = 1, 5 do
		local data = ix.celerity.GetLevelData(level)

		-- В сегментах колеса имя рисуется целиком, поэтому слово
		-- «Стремительность» не дублируем: центр колеса показывает дисциплину.
		ix.disciplines.RegisterPower("celerity", "celerity_" .. level, {
			name = "Уровень " .. level,
			description = string.format("Стремительность %d: Ловкость +%d, действует %d секунд.",
				level, data.dexterity, data.duration),
			level = level,
			cooldown = 0,
			GetVitaeCost = function()
				return data.vitae
			end,
			CanActivate = function(context)
				return IsValid(context.client) and context.client:Alive(), "notAlive"
			end,
			OnActivate = function(context)
				return PLUGIN:ActivateCelerity(context.client, context.character, level)
			end
		})
	end
end
