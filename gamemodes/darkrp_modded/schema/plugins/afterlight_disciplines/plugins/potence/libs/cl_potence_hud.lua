local PLUGIN = PLUGIN

-- Кровавая аура Могущества по краям экрана (эстетика VTM Bloodlines):
-- три слоя красных молний (прозрачность запечена в png), у каждого своя
-- плавная огибающая вспышек, третий слой — «дышащая» база ауры; общая
-- пульсация и плавные появление/затухание за 1 секунду.
ix.potence.fx = ix.potence.fx or {alpha = 0, layers = {}}

local LAYERS = {"potence_fx_a", "potence_fx_b", "potence_fx_c"}
local materials = {}

-- Прозрачность запечена в сам PNG (чёрный = прозрачный), поэтому vmt не
-- нужен: стандартный png подхватывается Material() напрямую. Если файла
-- ещё нет у клиента или материал битый (error-«шахматка») — не рисуем
-- ничего и пробуем снова через 5 секунд, чтобы экран не закрывался магентой.
local function GetFxMaterial(name)
	local now = RealTime()
	local entry = materials[name]
	if (entry and (entry.mat or now < entry.nextTry)) then
		return entry.mat
	end

	local path = "afterlight/disciplines/potence/" .. name .. ".png"
	local mat = file.Exists("materials/" .. path, "GAME") and Material(path) or nil
	if (mat and mat:IsError()) then
		mat = nil
	end

	materials[name] = {mat = mat, nextTry = now + 5}
	return mat
end

hook.Add("HUDPaint", "AfterlightPotenceScreenFx", function()
	local client = LocalPlayer()
	if (!IsValid(client)) then return end
	local fx = ix.potence.fx

	local active = client:GetNW2Int("afterlightPotenceLevel", 0) > 0
		and client:GetNW2Float("afterlightPotenceEnd", 0) > CurTime()

	-- Плавные вход и выход: 1 секунда в каждую сторону.
	local target = active and 1 or 0
	local dt = FrameTime()
	if (fx.alpha < target) then
		fx.alpha = math.min(fx.alpha + dt, 1)
	elseif (fx.alpha > target) then
		fx.alpha = math.max(fx.alpha - dt, 0)
	end
	if (fx.alpha <= 0.01) then return end

	local now = RealTime()

	-- Общая мягкая пульсация ауры.
	local pulse = 0.75 + 0.25 * math.sin(now * 3.1)

	for index = 1, #LAYERS do
		local layer = fx.layers[index]
		if (!layer) then
			layer = {env = 0, target = 0, next = 0}
			fx.layers[index] = layer
		end

		-- Каждый слой живёт своей жизнью: вспышка возникает случайно,
		-- её цель плавно распадается, а огибающая гладко тянется к цели —
		-- молнии появляются и прерываются без жёстких переключений.
		layer.target = layer.target * math.exp(-dt * 2.2)
		if (now >= layer.next) then
			layer.next = now + math.Rand(0.3, 1.1)
			layer.target = math.Rand(0.55, 1)
		end
		layer.env = layer.env + (layer.target - layer.env) * math.min(1, dt * 14)

		-- Третий слой — «дыхание» ауры: едва заметная постоянная основа,
		-- даёт эффекту непрерывность и глубину между вспышками.
		local base = index == 3 and 0.3 + 0.2 * math.sin(now * 1.7 + 1) or 0

		local strength = math.Clamp((layer.env + base) * pulse, 0, 1)
		local material = GetFxMaterial(LAYERS[index])
		if (material and strength > 0.02) then
			surface.SetDrawColor(255, 255, 255, math.Clamp(255 * fx.alpha * strength, 0, 255))
			surface.SetMaterial(material)
			surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
		end
	end
end)
