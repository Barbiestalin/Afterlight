ix.potence = ix.potence or {}

ix.potence.UNITS_PER_METER = 39.37
-- Трещина на земле (уровни 3+) живёт 8 секунд серверного времени.
ix.potence.CRACK_LIFETIME = 8

-- Звуковые файлы добавляются отдельно (открытые источники): достаточно
-- положить их в garrysmod/sound/afterlight/potence/ под этими именами —
-- код уже ссылается на них и подхватит автоматически.
ix.potence.SOUND_JUMP = "afterlight/potence/jump_air.wav"        -- колебание воздуха при усиленном прыжке (2+)
ix.potence.SOUND_HIT_LIGHT = "afterlight/potence/hit_light.wav" -- удары уровней 1-2, поверх звука оружия
ix.potence.SOUND_HIT_HEAVY = "afterlight/potence/hit_heavy.wav" -- удары уровней 3+

-- Параметры уровней по ТЗ: сила, добавочный урон ближнего боя, импульс
-- отброса (ед/с), высота усиленного прыжка в метрах, длительность,
-- стоимость в витэ и выбивание дверей.
ix.potence.LEVELS = {
	[1] = {strength = 1, damage = 10, knockback = 150, jumpMeters = 0, duration = 10, vitae = 2, doors = false},
	[2] = {strength = 2, damage = 20, knockback = 220, jumpMeters = 2, duration = 15, vitae = 4, doors = false},
	[3] = {strength = 3, damage = 30, knockback = 300, jumpMeters = 4, duration = 15, vitae = 5, doors = false},
	[4] = {strength = 3, damage = 35, knockback = 430, jumpMeters = 5, duration = 20, vitae = 8, doors = true},
	[5] = {strength = 4, damage = 40, knockback = 550, jumpMeters = 7, duration = 25, vitae = 10, doors = true}
}

function ix.potence.GetLevelData(level)
	level = math.Clamp(math.floor(tonumber(level) or 0), 1, 5)
	return ix.potence.LEVELS[level]
end

-- Стартовая вертикальная скорость, чтобы достичь heightMeters при данной
-- гравитации: v = sqrt(2 * g * h). Возвращает единицы Source в секунду.
function ix.potence.JumpVelocity(heightMeters, gravity)
	gravity = tonumber(gravity) or 600
	return math.sqrt(2 * gravity * heightMeters * ix.potence.UNITS_PER_METER)
end
