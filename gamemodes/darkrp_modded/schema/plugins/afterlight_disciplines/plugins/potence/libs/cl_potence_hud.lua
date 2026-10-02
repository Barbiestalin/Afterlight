local PLUGIN = PLUGIN

-- Кровавая аура Могущества по краям экрана (эстетика VTM Bloodlines):
-- два слоя красных молний (прозрачность запечена в png), пульсация, мерцание-обрывы,
-- плавные появление и затухание за 1 секунду.
ix.potence.fx = ix.potence.fx or {alpha = 0, nextSwap = 0, layer = 1, flicker = 1}

local LAYERS = {"potence_fx_a", "potence_fx_b"}
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

	-- Молнии «то появляются, то прерываются»: слои меняются короткими
	-- случайными вспышками, каждая со своей яркостью.
	if (now >= fx.nextSwap) then
		fx.nextSwap = now + math.Rand(0.08, 0.22)
		fx.layer = (fx.layer % 2) + 1
		fx.flicker = math.Rand(0.55, 1)
	end

	-- Мистическая пульсация ауры.
	local pulse = 0.7 + 0.3 * math.sin(now * 5.2)
	local alpha = math.Clamp(255 * fx.alpha * pulse * fx.flicker, 0, 255)

	local material = GetFxMaterial(LAYERS[fx.layer])
	if (material) then
		surface.SetDrawColor(255, 255, 255, alpha)
		surface.SetMaterial(material)
		surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
	end

	-- Второй слой — в противофазе и тише: края «дышат», а не мигают плоско.
	local second = GetFxMaterial(LAYERS[(fx.layer % 2) + 1])
	if (second) then
		surface.SetDrawColor(255, 255, 255, math.Clamp(alpha * 0.35 * (1.1 - pulse), 0, 255))
		surface.SetMaterial(second)
		surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
	end
end)
