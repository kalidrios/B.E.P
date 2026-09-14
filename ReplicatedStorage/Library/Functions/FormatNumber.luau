--[[
	© DestructionSimulator [2025]
	Library/Functions/FormatNumber — Global number abbreviator (e.g. 1000 -> 1k, 1251 -> 1,25k, 1000000 -> 1M)
--]]

local suffixes = {
	{ 1e33, "Dc" },
	{ 1e30, "No" },
	{ 1e27, "Oc" },
	{ 1e24, "Sp" },
	{ 1e21, "Sx" },
	{ 1e18, "Qi" },
	{ 1e15, "Qa" },
	{ 1e12, "T" },
	{ 1e9,  "B" },
	{ 1e6,  "M" },
	{ 1e3,  "k" },
}

local function formatNumber(val)
	local n = tonumber(val) or 0
	if n ~= n then return "0" end
	if n == math.huge then return "∞" end
	if n == -math.huge then return "-∞" end

	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end

	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end

	for _, entry in ipairs(suffixes) do
		local threshold = entry[1]
		local suffix = entry[2]
		if n >= threshold then
			local divided = n / threshold
			local formatted = string.format("%.2f", divided)
			-- Trim trailing zeros and point
			formatted = formatted:gsub("0+$", ""):gsub("%.+$", "")
			-- Replace dot with comma for Portuguese formatting (e.g. 1,25k)
			formatted = formatted:gsub("%.", ",")
			return sign .. formatted .. suffix
		end
	end

	return sign .. tostring(math.floor(n))
end

-- Also expose globally for easy UI access anywhere in client/server scripts
_G.FormatNumber = formatNumber

return formatNumber
