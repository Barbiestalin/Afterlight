local PLUGIN = PLUGIN

PLUGIN.name = "Afterlight Potence"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Могущество: пять по отдельности выбираемых уровней — сила, урон и отброс в ближнем бою, усиленный прыжок, трещины и выбивание дверей."
PLUGIN.version = "1.0.0"

-- Каждый уровень дисциплины — отдельная «способность» в колесе интерфейса
-- (afterlight_discipline_interface): игрок видит уровни 1..N по своим точкам
-- в чарлисте, выбирает нужный сегмент и активирует его своей кнопкой.
-- Трата крови, кулдауны, проверки доступа и обратная связь — на стороне
-- интерфейсного шлюза; здесь только параметры и реализация эффектов.
function PLUGIN:InitializedPlugins()
	if (!ix.disciplines or !isfunction(ix.disciplines.RegisterPower)) then
		ErrorNoHalt("[Afterlight Potence] API Discipline Interface недоступно — способности не зарегистрированы.\n")
		return
	end

	for level = 1, 5 do
		local data = ix.potence.GetLevelData(level)

		ix.disciplines.RegisterPower("potence", "potence_" .. level, {
			name = "Могущество — уровень " .. level,
			description = string.format("Сила +%d, урон в ближнем бою +%d на %d секунд.",
				data.strength, data.damage, data.duration),
			level = level,
			cooldown = 0,
			GetVitaeCost = function()
				return data.vitae
			end,
			CanActivate = function(context)
				return IsValid(context.client) and context.client:Alive(), "notAlive"
			end,
			OnActivate = function(context)
				return PLUGIN:ActivatePotence(context.client, context.character, level)
			end
		})
	end
end
