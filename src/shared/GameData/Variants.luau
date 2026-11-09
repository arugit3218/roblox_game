--!strict
-- Rare pet variants rolled at hatch. Multiply aquarium income and caviar output.

export type VariantDef = {
	name: string,
	multiplier: number,
	chance: number, -- base chance per hatch (before luck)
	color: Color3,
	label: string,
}

local Variants: { [string]: VariantDef } = {
	Normal = {
		name = "Normal",
		multiplier = 1,
		chance = 1,
		color = Color3.new(1, 1, 1),
		label = "",
	},
	Golden = {
		name = "Golden",
		multiplier = 2,
		chance = 0.06,
		color = Color3.fromRGB(255, 205, 60),
		label = "✨ GOLDEN",
	},
	Rainbow = {
		name = "Rainbow",
		multiplier = 5,
		chance = 0.012,
		color = Color3.fromRGB(255, 110, 230),
		label = "🌈 RAINBOW",
	},
}

local VariantsModule = {
	defs = Variants,
}

function VariantsModule.get(name: string?): VariantDef
	return Variants[name or "Normal"] or Variants.Normal
end

-- Rarest first so luck can't push Golden past Rainbow.
function VariantsModule.roll(rng: Random, luck: number): string
	local roll = rng:NextNumber()
	if roll < Variants.Rainbow.chance * luck then
		return "Rainbow"
	elseif roll < (Variants.Rainbow.chance + Variants.Golden.chance) * luck then
		return "Golden"
	end
	return "Normal"
end

return VariantsModule
