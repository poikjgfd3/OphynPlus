-- src/utilities/http.lua
-- One place for "which HTTP function does this executor have" and "download + loadstring".
-- Before this, the same `request or http_request or (syn and syn.request) or ...` line was
-- copy-pasted in ui.lua (twice), platoboost.lua and the custom service builder.

local Http = {}

local remoteCache = {} -- url -> loaded library

function Http.request()
	return request
		or http_request
		or (syn and syn.request)
		or (http and http.request)
		or (fluxus and fluxus.request)
end

-- GET with optional retries. Returns body, or nil + reason.
function Http.get(url, retries)
	local lastErr = "request failed"
	for attempt = 0, retries or 0 do
		if attempt > 0 then
			task.wait(0.4 * attempt)
		end

		local req = Http.request()
		if req then
			local ok, res = pcall(req, { Url = url, Method = "GET" })
			if ok and type(res) == "table" then
				if res.StatusCode == 200 and type(res.Body) == "string" and res.Body ~= "" then
					return res.Body
				end
				lastErr = "HTTP " .. tostring(res.StatusCode)
			elseif not ok then
				lastErr = tostring(res)
			end
		end

		local ok, body = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(body) == "string" and body ~= "" then
			return body
		end
		if not ok then
			lastErr = tostring(body)
		end
	end
	return nil, lastErr
end

-- Downloads a Lua file, runs it and returns whatever it returns (cached per url).
-- Returns lib, or nil + reason.
function Http.loadRemote(url, retries)
	if remoteCache[url] ~= nil then
		return remoteCache[url]
	end
	if not loadstring then
		return nil, "loadstring is not available"
	end

	local body, err = Http.get(url, retries or 1)
	if not body then
		return nil, err
	end

	local fn, compileErr = loadstring(body)
	if not fn then
		return nil, tostring(compileErr)
	end

	local ok, lib = pcall(fn)
	if not ok then
		return nil, tostring(lib)
	end

	remoteCache[url] = lib
	return lib
end

return Http
