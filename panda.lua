-- src/utilities/panda.lua
-- PandaAuth v4 adapter.
-- The previous version had `Panda:CheckKey` pasted inside itself (plus a leftover tail of the
-- old implementation), so the unclosed function swallowed the rest of the file and the whole
-- bundle failed to compile. This is a clean single implementation.

local Http = import("utilities/http")

local LIB_URL = "https://secure.pandauth.com/pv4/lib"

local REASONS = {
	INVALID_KEY = "key is invalid.", -- was "invalid or expired": ui.lua counts any reason containing "expir" as an expired key
	RATE_LIMITED = "you are being rate limited, please wait a moment and try again.",
	NETWORK = "network error, please try again.",
	NO_SERVICE = "Panda ServiceId is missing or invalid.",
	NO_KEY = "key is empty.",
	NO_HTTP = "your executor doesn't support HTTP requests.",
	IDENTITY = "couldn't verify the Panda server identity, please try again later.",
	PROTOCOL = "Panda protocol error, please try again later.",
}

local Panda = {}
Panda.__index = Panda

function Panda.new(config)
	config = config or {}
	local self = setmetatable({}, Panda)

	local serviceId = config.ServiceId or config.Service or config.serviceId
	self.serviceId = serviceId ~= nil and tostring(serviceId) or ""
	self.debug = config.Debug == true

	self.lib = nil
	self.loading = false

	-- filled after a successful check
	self.isPremium = nil
	self.expiry = nil
	self.expiryUnix = nil
	self.timeLeft = nil

	if self.serviceId == "" then
		warn("[Panda] ServiceId is missing — check your Panda dashboard")
	end

	return self
end

-- Downloads + configures the Panda library once. Returns lib, or nil + reason.
function Panda:_load()
	if self.lib then
		return self.lib
	end
	if self.serviceId == "" then
		return nil, REASONS.NO_SERVICE
	end

	-- another thread is already loading: wait for it, then reuse its result
	while self.loading do
		task.wait(0.1)
	end
	if self.lib then
		return self.lib
	end

	self.loading = true
	local lib, err
	local ok, thrown = pcall(function()
		local result, loadErr = Http.loadRemote(LIB_URL, 1)
		if not result then
			err = "couldn't load the Panda library: " .. tostring(loadErr)
			return
		end
		if type(result) ~= "table" or type(result.configure) ~= "function" then
			err = "Panda library failed to initialize."
			return
		end

		local okConfig, configError = pcall(result.configure, {
			serviceId = self.serviceId,
			debug = self.debug,
			kickOnDetect = false,
		})
		if not okConfig then
			err = "couldn't configure the Panda library: " .. tostring(configError)
			return
		end
		lib = result
	end)
	self.loading = false -- always reset, even if something above threw

	if not ok then
		return nil, tostring(thrown)
	end
	if lib then
		self.lib = lib
		return lib
	end
	return nil, err
end

-- Returns valid (boolean), reason (string when invalid)
function Panda:CheckKey(key)
	key = tostring(key or ""):match("^%s*(.-)%s*$")
	if key == "" then
		return false, REASONS.NO_KEY
	end

	local lib, err = self:_load()
	if not lib then
		return false, err
	end

	-- Preferred (PandaAuth v4): validateEx -> success, reason, isPremium
	if type(lib.validateEx) == "function" then
		local ok, success, reason, isPremium = pcall(lib.validateEx, key)
		if not ok then
			return false, tostring(success)
		end
		if success then
			self.isPremium = isPremium
			return true
		end
		return false, REASONS[reason] or tostring(reason or "key is invalid.")
	end

	-- Fallback: validate -> table | boolean
	if type(lib.validate) == "function" then
		local ok, result = pcall(lib.validate, key)
		if not ok then
			return false, tostring(result)
		end

		if result == true then
			return true
		end

		if type(result) == "table" then
			if result.success == true then
				self.isPremium = result.isPremium
				self.expiry = result.expiresAt
				self.expiryUnix = result.expiresAtUnix
				self.timeLeft = result.timeLeft
				return true
			end
			local reason = result.reason or result.error
			return false, REASONS[reason] or tostring(reason or "key is invalid.")
		end

		return false, "key is invalid."
	end

	return false, "Unsupported Panda library version."
end

function Panda:GetKeyLink()
	local lib, err = self:_load()
	if not lib then
		return nil, err
	end

	if type(lib.getKeyUrl) ~= "function" then
		return nil, "SDK does not support getKeyUrl()."
	end

	local ok, url = pcall(lib.getKeyUrl)
	if ok and type(url) == "string" and url ~= "" then
		return url
	end

	return nil, "Failed to obtain key link."
end

return Panda
