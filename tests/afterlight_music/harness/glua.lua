--[[
	Переводчик GLua -> Lua 5.1 для стенда.

	GLua расширяет Lua оператором "!" и ключевым словом "continue" (а также
	"!="). Файлы Helix и плагинов Afterlight написаны на GLua, поэтому перед
	загрузкой в LuaJIT их нужно привести к стандартному синтаксису. Переводчик
	пропускает строки и комментарии, чтобы не портить текст.

	Файл написан на чистом Lua 5.1: он загружается первым и переводит все
	остальные, включая сам стенд.
]]

local function isWordChar(c)
	return c:match("[%w_]") ~= nil
end

local function translate(source)
	local out = {}
	local index = 1
	local length = #source
	local frames = {}
	local labelCounter = 0
	local pending = {}

	local function emit(text)
		out[#out + 1] = text
	end

	while (index <= length) do
		local char = source:sub(index, index)
		local two = source:sub(index, index + 1)

		if (two == "--") then
			if (source:sub(index, index + 3) == "--[[") then
				local stop = source:find("]]", index + 4, true) or (length + 1)
				emit(source:sub(index, stop + 1))
				index = stop + 2
			else
				local stop = source:find("\n", index, true) or (length + 1)
				emit(source:sub(index, stop - 1))
				index = stop
			end

		elseif (char == "\"" or char == "'") then
			local stop = index + 1

			while (stop <= length) do
				local c = source:sub(stop, stop)

				if (c == "\\") then
					stop = stop + 2
				elseif (c == char) then
					break
				else
					stop = stop + 1
				end
			end

			emit(source:sub(index, stop))
			index = stop + 1

		elseif (two == "[[") then
			local close = source:find("]]", index + 2, true)

			if (close) then
				emit(source:sub(index, close + 1))
				index = close + 2
			else
				emit(char)
				index = index + 1
			end

		elseif (two == "!=") then
			emit("~=")
			index = index + 2

		elseif (char == "!") then
			emit("not ")
			index = index + 1

		elseif (isWordChar(char)) then
			local stop = index

			while (stop <= length and isWordChar(source:sub(stop, stop))) do
				stop = stop + 1
			end

			local word = source:sub(index, stop - 1)

			if (word == "continue") then
				-- continue -> goto в конец ближайшего цикла
				labelCounter = labelCounter + 1
				local name = "__continue" .. labelCounter

				for i = #frames, 1, -1 do
					if (frames[i] == "loop") then
						pending[i] = pending[i] or {}
						table.insert(pending[i], name)
						break
					end
				end

				emit("goto " .. name)
				index = stop
			else
				local top = frames[#frames]

				if (word == "for" or word == "while") then
					-- do у цикла кадр не добавляет
					frames[#frames + 1] = "loop"
				elseif (word == "if") then
					frames[#frames + 1] = "ifpending"
				elseif (word == "elseif") then
					frames[#frames + 1] = "elseif"
				elseif (word == "then") then
					if (top == "ifpending" or top == "elseif") then
						frames[#frames] = "if"
					else
						frames[#frames + 1] = "if"
					end
				elseif (word == "do") then
					if (top ~= "loop") then
						frames[#frames + 1] = "do"
					end
				elseif (word == "function" or word == "repeat") then
					frames[#frames + 1] = word
				elseif (word == "end" or word == "until") then
					local labels = pending[#frames]

					if (labels) then
						for _, name in ipairs(labels) do
							emit("::" .. name .. ":: ")
						end

						pending[#frames] = nil
					end

					frames[#frames] = nil
				end

				emit(word)
				index = stop
			end
		else
			emit(char)
			index = index + 1
		end
	end

	return table.concat(out)
end

return translate
