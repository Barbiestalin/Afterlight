local PLUGIN = PLUGIN

PLUGIN.name = "Afterlight Disciplines"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Контейнер вампирских дисциплин: каждая дисциплина — отдельный субплагин в папке plugins/. Первая дисциплина — Могущество."
PLUGIN.version = "1.0.0"

-- Helix сам обходит plugins/<папка плагина>/plugins и загруживает каждую
-- подпапку как субплагин (ix.plugin.LoadFromDir в core/libs/sh_plugin.lua),
-- поэтому файлы дисциплин лежат в plugins/<id_дисциплины>/.
