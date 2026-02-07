local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst");
local RunService = game:GetService("RunService");

local Modules = ReplicatedStorage:WaitForChild("Modules");

local jecs = require(Modules.ECS.ECS.jecs);
local ECS = require(Modules.ECS.ECS);
local Jecs = require(Modules.ECS.ECS.jecs);
local TypeData = require(Modules.Data.Types);
local Components = require(Modules.ECS.ECS.Components);
local Blink = require(ReplicatedFirst.Modules.Blink.Client);
local Sift = require(Modules.Util.Sift);
local Map = require(ReplicatedFirst.Modules.ECS.ClientMap);

local World = ECS.world;

local Syncer = {
	__frame = 0,	
};

function Syncer:sync_frame(frame)
	self.__frame = frame;
end

function Syncer:get_frame()
	return self.__frame;
end

--< TODO: Create frame timers >--

function Syncer:process_packet(entity: number, packet)
	local event = packet[1]; --< 0 = add, 1 = change, 2 = remove
	local Component = packet[2];
	local value = packet[3]; --< Optional on remove (2)

	local client_entity = Map:get_client_from_server(entity);

	if event == 0 or event == 1 then
		--< Add >--
		World:set(client_entity, Components[Component], value);
	elseif event == 2 then
		--< Remove >--
		World:remove(client_entity, Components[Component]);
	end
end

function Syncer:process_packets(packets)
	for entity,entity_packets in pairs(Sift.Dictionary.filter(packets, function(v, k) return k ~= 'n'; end)) do
		for _,packet in pairs(entity_packets) do
			self:process_packet(entity, packet);
		end
	end
end

function Syncer:init()	
	Blink.Syncer.init.On(function(packet)
		for server_entity,components in pairs(packet) do
			local client_entity = Map:get_client_from_server(server_entity);

			for component, value in pairs(components) do
				World:set(client_entity, Components[component], value);
			end
		end
	end)

	Blink.Syncer.Sync.On(function(packet)
		self:sync_frame(packet[1]);
		
		if packet[2].n > 0 then
			self:process_packets(packet[2]);
		end
	end)
end
return Syncer;
