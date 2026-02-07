local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage");
local RunService = game:GetService("RunService");
local Players = game:GetService("Players");

local Modules = ReplicatedStorage:WaitForChild("Modules");

local jecs = require(Modules.ECS.ECS.jecs);
local ECS = require(Modules.ECS.ECS);
local Jecs = require(Modules.ECS.ECS.jecs);
local TypeData = require(Modules.Data.Types);
local Components = require(Modules.ECS.ECS.Components);
local Blink = require(ServerStorage.Modules.Blink.Server);
local Sift = require(Modules.Util.Sift);

local World = ECS.world;
local Map = ECS.map;

local networked_cache = World:query(Components.networked):cached();

local Syncer = {
	
	__event_queue = {  } :: { [number]: { TypeData.packet } }, --< [Entity] = { packets }
	__hooks = {}, --< This will contain entity hooks
	__frame = 0,	
}

setmetatable(Syncer.__event_queue, {
	__index = function(_t, _v)
		--< When the table is indexed by something that doesn't exist, create an entry for it
		Syncer.__event_queue[_v] = {};
				
		return Syncer.__event_queue[_v];
	end,
})

function Syncer:increment_frame()
	self.__frame += 1;
end

function Syncer:get_frame()
	return self.__frame;
end

function Syncer:clear_events()
	self.__event_queue = setmetatable(Sift.Dictionary.map(self.__event_queue, function(v, k, dict)
		v = Sift.Dictionary.filter(v, function(_v, _k)
			return table.find(World:get(k, Components.Locked) or {}, Components[_v[2]]);
		end)

		return (Sift.Dictionary.count(v) >= 1 and v or nil);
	end), {
		__index = function(_t, _v)
			--< When the table is indexed by something that doesn't exist, create an entry for it
			Syncer.__event_queue[_v] = {};

			return Syncer.__event_queue[_v];
		end,
	})
	
	print("event queue:", self.__event_queue);
end

function Syncer:get_events()
	local mapped = Sift.Dictionary.map(self.__event_queue, function(v, k, dict)
		v = Sift.Dictionary.filter(v, function(_v, _k)
			return not table.find(World:get(k, Components.Locked) or {}, Components[_v[2]]);
		end)

		return (Sift.Dictionary.count(v) >= 1 and v or nil);
	end);
	
	mapped = Sift.Dictionary.merge({ n = Sift.Dictionary.count(mapped) or 0 }, mapped);
	
	return mapped;
end

function Syncer:append(packet: TypeData.packet, entity: number)	
	table.insert(self.__event_queue[entity], packet);
end

function Syncer:create_package()	
	return table.freeze({ self:get_frame(), self:get_events() });
end

function Syncer:create_init_package()
	local package = {};
	
	for entity,_ in networked_cache:iter() do
		for comp_name, comp in pairs(Components) do
			if World:has(entity, comp) then
				if not package[entity] then
					package[entity] = {};
				end
				
				package[entity][comp_name] = World:get(entity, comp);
			end
		end
	end
	
	return package;
end

function Syncer:init()
	--< Each frame, when we pass from the server to the client the information, we'll clear our __event_queue
	
	World:added(Components.Instance, function(e, id, instance)
		--< Lets make sure we track the instance in the map as a ref
		Map:set(instance, e);
	end)
	
	World:changed(Components.Instance, function(e, id, value)
		Map:clear(e);
		Map:set(value, e);
	end)
	
	World:removed(Components.Instance, function(e, id)
		Map:clear(e);
	end)
	
	for componentName, Component in Components do
		if table.find({ Components.networked, Components.Locked }, Component) then continue end;

		self.__hooks.added = World:added(Component, function(e, id, value)
			if not World:get(e, Components.networked) then print("NOT NETWORKED! SKIP") return end;
			self:append({ 0, componentName, value }, e);
		end)

		self.__hooks.changed = World:changed(Component, function(e, id, value)
			if not World:get(e, Components.networked) then return end;
			self:append({ 1, componentName, value }, e);
		end)

		self.__hooks.removed = World:removed(Component, function(e, id)
			if not World:get(e, Components.networked) then return end;
			self:append({ 2, componentName }, e);
		end)
	end
	
	RunService.PostSimulation:Connect(function()
		local package: TypeData.package = self:create_package();
		Blink.Syncer.Sync.FireAll(package);
				
		self:increment_frame();
				
		if self:get_events().n > 0 then
			print("fired:", package);
			self:clear_events();
		end
	end)
end

return Syncer
