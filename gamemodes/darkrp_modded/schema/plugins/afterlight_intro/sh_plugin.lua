PLUGIN.name = "Afterlight Intro"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Atmospheric introduction screen for Afterlight."

ix.util.Include("cl_plugin.lua")

if (SERVER) then
	-- Основные пути оставлены без изменений.
	resource.AddFile("materials/afterlight/intro/intro.jpg")

	-- Музыкальный файл принадлежит плагину afterlight_menu_music: он же
	-- добавляет его в список загрузки, чтобы не дублировать ресурс.

	-- Оригинальные декоративные маски интро. PNG содержат прозрачность и
	-- безопасно пропускаются кодом, если администратор ещё не установил файлы.
	resource.AddFile("materials/afterlight/intro/generated/gothic_frame.png")
	resource.AddFile("materials/afterlight/intro/generated/rose_window.png")
	resource.AddFile("materials/afterlight/intro/generated/blood_bloom.png")
	resource.AddFile("materials/afterlight/intro/generated/film_damage.png")

	-- Внешние шрифты больше не нужны: интерфейс использует системные Georgia
	-- и Times New Roman, которые поддерживают кириллицу.
end
