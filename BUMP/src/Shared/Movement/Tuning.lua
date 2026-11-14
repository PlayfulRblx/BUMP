--!nonstrict
--[[
	MoveConfig, readable live.

	    local Jump = Tuning.Of("Jump")
	    ... Jump.Single ...      -- read it where it is used, never cache the number

	In a published game this is MoveConfig and nothing else. In Studio the server publishes every
	number as an attribute on ReplicatedStorage.BumpTuning ("Jump_Single", "Run_Speed"...), and a
	read returns the attribute. So a number can be changed in the Properties panel while playing
	and felt at once: select BumpTuning in the Explorer with the Server view showing. Copy the
	numbers you like back into MoveConfig; the attributes are gone when Play stops.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MoveConfig = require("@Shared/Movement/MoveConfig")

local Tuning = {}

local HOLDER_NAME = "BumpTuning"
local LIVE = RunService:IsStudio()
local holder: Instance? = nil
local proxies = {}

local function find(): Instance?
	if holder and holder.Parent then
		return holder
	end
	holder = ReplicatedStorage:FindFirstChild(HOLDER_NAME)
	return holder
end

function Tuning.Of(group: string)
	if proxies[group] then
		return proxies[group]
	end
	local source = MoveConfig[group]
	assert(type(source) == "table", "Tuning.Of: no MoveConfig group " .. tostring(group))
	local proxy = setmetatable({}, {
		__index = function(_, key)
			local base = source[key]
			if LIVE and type(base) == "number" then
				local at = find()
				local live = at and at:GetAttribute(group .. "_" .. key)
				if type(live) == "number" then
					return live
				end
			end
			return base
		end,
		__newindex = function()
			error("Tuning tables are read-only: change MoveConfig, or the attribute in Studio")
		end,
	})
	proxies[group] = proxy
	return proxy
end

-- Server, Studio only: puts every number where the Properties panel can change it.
function Tuning.Publish()
	if not LIVE or not RunService:IsServer() then
		return
	end
	local old = ReplicatedStorage:FindFirstChild(HOLDER_NAME)
	if old then
		old:Destroy()
	end
	local configuration = Instance.new("Configuration")
	configuration.Name = HOLDER_NAME
	for group, values in pairs(MoveConfig) do
		for key, value in pairs(values) do
			if type(value) == "number" then
				configuration:SetAttribute(group .. "_" .. key, value)
			end
		end
	end
	configuration.Parent = ReplicatedStorage
	holder = configuration
end

return Tuning
