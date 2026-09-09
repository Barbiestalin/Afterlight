PLUGIN.name = "Bot Commands"
PLUGIN.author = "Afterlight"

if (SERVER) then
	ix.command.Add("BotSpawn", {
		description = "Spawn test bots",
		adminOnly = true,
		arguments = ix.type.number,
		OnRun = function(self, client, amount)
			amount = amount or 1

			for i = 1, amount do
				local bot = player.CreateNextBot("Bot_" .. math.random(1000, 9999))

				if (IsValid(bot)) then
					-- Создаём персонажа правильно
					local data = {
						name = "Bot " .. math.random(10000, 99999),
						model = "models/player/group01/male_02.mdl", -- можно поменять
						faction = FACTION_CITIZEN, -- убедись, что такая фракция существует
						description = "Test bot"
					}

					ix.char.Create(data, function(id)
						local char = ix.char.loaded[id]
						if (char and IsValid(bot)) then
							char:SetPlayer(bot)
							bot:SetCharacter(char)
						end
					end)
				end
			end

			return "Заспавнено ботов: " .. amount
		end
	})

	ix.command.Add("BotKick", {
		description = "Kick all bots",
		adminOnly = true,
		OnRun = function()
			for _, bot in ipairs(player.GetBots()) do
				bot:Kick()
			end
			return "Все боты удалены."
		end
	})
end