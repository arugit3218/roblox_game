--!strict
-- Tiny declarative helpers for building ScreenGui trees in code.

local UI = {}

UI.colors = {
	panel = Color3.fromRGB(14, 38, 66),
	panelLight = Color3.fromRGB(26, 62, 100),
	accent = Color3.fromRGB(70, 210, 255),
	good = Color3.fromRGB(70, 200, 120),
	warn = Color3.fromRGB(255, 180, 60),
	bad = Color3.fromRGB(230, 80, 90),
	muted = Color3.fromRGB(150, 175, 200),
	text = Color3.fromRGB(240, 248, 255),
	disabled = Color3.fromRGB(70, 85, 105),
}

UI.font = Enum.Font.FredokaOne

function UI.new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UI.corner(radius: number?): UICorner
	-- Scales a ScreenGui with screen height so HUD/menus fit phones and small windows.
	function UI.autoScale(gui: ScreenGui, designHeight: number?)
		local scale = Instance.new("UIScale")
		scale.Parent = gui
		local camera = workspace.CurrentCamera
		local function update()
			local h = camera.ViewportSize.Y
			scale.Scale = math.clamp(h / (designHeight or 900), 0.55, 1.15)
		end
		update()
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end

	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function UI.padding(px: number): UIPadding
	-- Scales a ScreenGui with screen height so HUD/menus fit phones and small windows.
	function UI.autoScale(gui: ScreenGui, designHeight: number?)
		local scale = Instance.new("UIScale")
		scale.Parent = gui
		local camera = workspace.CurrentCamera
		local function update()
			local h = camera.ViewportSize.Y
			scale.Scale = math.clamp(h / (designHeight or 900), 0.55, 1.15)
		end
		update()
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end

	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

function UI.label(text: string, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Text = text,
		Font = UI.font,
		TextColor3 = UI.colors.text,
		TextScaled = true,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local label = UI.new("TextLabel", base)
	UI.new("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 10, Parent = label })
	return label
end

function UI.button(
	text: string,
	color: Color3,
	onClick: (() -> ())?,
	props: { [string]: any }?
): TextButton
	local base: { [string]: any } = {
		Text = text,
		Font = UI.font,
		TextColor3 = UI.colors.text,
		TextScaled = true,
		BackgroundColor3 = color,
		AutoButtonColor = onClick ~= nil,
		RichText = true,
	}
	if props then
		for k, v in props do
			base[k] = v
		end
	end
	local button = UI.new("TextButton", base, { UI.corner(8), UI.padding(4) })
	UI.new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 10, Parent = button })
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- Scales a ScreenGui with screen height so HUD/menus fit phones and small windows.
function UI.autoScale(gui: ScreenGui, designHeight: number?)
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local camera = workspace.CurrentCamera
	local function update()
		local h = camera.ViewportSize.Y
		scale.Scale = math.clamp(h / (designHeight or 900), 0.55, 1.15)
	end
	update()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
end

return UI
