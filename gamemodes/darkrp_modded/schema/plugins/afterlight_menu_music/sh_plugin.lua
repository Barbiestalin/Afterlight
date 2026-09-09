PLUGIN.name = "Afterlight Menu Music"
PLUGIN.author = "Afterlight"
PLUGIN.description = "Controls looping music for intro, character menu and Helix menu."

if (SERVER) then
	resource.AddFile("sound/afterlight/intro_music.mp3")
end

ix.util.Include("cl_plugin.lua")