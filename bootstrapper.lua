local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SelfStorage = RunService:IsClient() and game:GetService("ReplicatedFirst") or game:GetService("ServerStorage")

local shared_Modules = ReplicatedStorage:WaitForChild("Modules")
local self_Modules = SelfStorage:WaitForChild("Modules")

local bootstrapper = {
	_module_cache = {},
}

function bootstrapper:register(...)
	local args = { ... } :: { ModuleScript | Folder }

	for _, module in pairs(args) do
		if module:IsA("ModuleScript") then
			if module ~= script then
				local success, err = pcall(function()
					self._module_cache[module] = require(module)
				end)

				if not success then
					warn(
						(`Bootstrapper ran into an issue while attempting to load module: {module.Name} ({module:GetFullName()}): {err}`)
					)
					continue
				end
			end
		else
			-- Folder
			if module then
				for _, _module in pairs(module:GetDescendants()) do
					if _module:IsA("ModuleScript") then
						self:register(_module)
					end
				end
			end
		end
	end
end

function bootstrapper:runRegistered()
	for module, req in pairs(self._module_cache) do
		if typeof(req) == "table" then
			-- IMPORTANT: rawget avoids metatable __index loops
			local initFn = rawget(req, "init")
			if typeof(initFn) == "function" then
				local success, err = pcall(initFn, req)
				if not success then
					warn(
						(`Bootstrapper ran into an issue while attempting to initialize module: {module.Name} ({module:GetFullName()}): {err}`)
					)
					continue
				end
			end
		end
	end
end

bootstrapper.init = function(preloads: { ModuleScript }? | ModuleScript?)
	if preloads then
		if typeof(preloads) == "table" then
			for _, module in pairs(preloads) do
				bootstrapper:register(module)
			end
		else
			bootstrapper:register(preloads)
		end
	end

	bootstrapper:register(shared_Modules, self_Modules)
	bootstrapper:runRegistered()
end

return bootstrapper
