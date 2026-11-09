--!strict
-- Display helpers shared by UI code.

local Format = {}

function Format.number(n: number): string
	n = math.floor(n)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if n < 0 then "-" else "") .. out
end

function Format.duration(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

return Format
