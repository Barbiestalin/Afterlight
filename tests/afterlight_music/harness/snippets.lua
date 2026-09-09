--[[
	Фрагменты гейммода Helix, которые управляют жизненным циклом меню.

	Загружать cl_hooks.lua целиком нельзя — это весь клиентский геймmod, он
	тянет за собой ядро. Поэтому здесь приведены ДОСЛОВНЫЕ фрагменты с
	указанием файла и строк в NebulousCloud/helix (master). Скрипт
	check_helix_contract.py проверяет, что эти фрагменты по-прежнему есть в
	исходниках Helix: если Helix поменяется, проверка упадёт и стенд придётся
	обновить вместе с плагинами.
]]

local env = ...

local GM = {}

env.GM = GM

-- [helix] gamemode/core/hooks/cl_hooks.lua:6-10
function GM:ScoreboardShow()
	if (LocalPlayer():GetCharacter()) then
		vgui.Create("ixMenu")
	end
end

-- [helix] gamemode/core/hooks/cl_hooks.lua:12-13
function GM:ScoreboardHide()
end

-- [helix] gamemode/core/hooks/cl_hooks.lua:332-336
function GM:LoadIntro()
	if (!IsValid(ix.gui.intro)) then
		vgui.Create("ixIntro")
	end
end

-- [helix] gamemode/core/hooks/cl_hooks.lua:338-345
function GM:CharacterLoaded()
	local menu = ix.gui.characterMenu

	if (IsValid(menu)) then
		menu:Close((LocalPlayer().GetCharacter and LocalPlayer():GetCharacter()) and true or nil)
	end
end

-- [helix] gamemode/core/libs/sh_character.lua:1121-1134
env.__registerHelixNet = function()
	net.Receive("ixCharacterMenu", function()
		local indices = net.ReadUInt(6)
		local charList = {}

		for _ = 1, indices do
			charList[#charList + 1] = net.ReadUInt(32)
		end

		if (charList) then
			ix.characters = charList
		end

		vgui.Create("ixCharMenu")
	end)

	-- [helix] gamemode/core/libs/sh_character.lua:1205-1207
	net.Receive("ixCharacterLoaded", function()
		hook.Run("CharacterLoaded", ix.char.loaded[net.ReadUInt(32)])
	end)
end

return env
