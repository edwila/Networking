--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local valid = require(Modules.Data.Validator)
local handler = require(ServerStorage.Modules.Data.DataHandler)

local ECS = require(Modules.ECS.ECS)
local Components = require(Modules.ECS.ECS.Components)
local Blink = require(ServerStorage.Modules.Blink.Server)

local world = ECS.world
local map = ECS.map

local BuildingAction = {}

local function setAttrs(p: Player, playerData: any)
	p:SetAttribute("Gold", playerData.Gold or 0)
end

function BuildingAction:OnReceive(player: Player, packet: any)
	if typeof(packet) ~= "table" or typeof(packet.action_type) ~= "number" or type(packet.meta) ~= "table" then
		warn("Invalid BuildingAction packet from", player)
		return
	end

	if packet.action_type == 0 then
		self:handle_buy(player, packet.meta)
	elseif packet.action_type == 1 then
		self:handle_move(player, packet.meta)
	elseif packet.action_type == 2 then
		self:handle_upgrade(player, packet.meta)
	elseif packet.action_type == 3 then
		self:handle_cancel(player, packet.meta)
	end
end

function BuildingAction:handle_buy(p: Player, meta: any)
	local buildingType = meta.building_type
	local pos = meta.position
	local rot = meta.rotation

	if typeof(buildingType) ~= "number" or typeof(pos) ~= "Vector3" then return end
	if rot ~= nil and typeof(rot) ~= "number" then rot = nil end

	local playerEntity = map:get(p)
	local playerData = world:get(playerEntity, Components.Data)

	local details = valid.canPurchase(playerData, buildingType, 1)
	if not details.ok then return end
	if not valid.canPlace(playerData, buildingType, pos, rot) then return end

	local uuid = handler:create_building(p, buildingType, pos, rot, details.amount or 0)

	-- update UI attrs
	playerData = world:get(playerEntity, Components.Data)
	setAttrs(p, playerData)

	task.delay(details.time, function()
		handler:finish_construction(uuid)
	end)
end

function BuildingAction:handle_move(p: Player, meta: any)
	local uuid = meta.uuid
	local pos = meta.position
	local rot = meta.rotation

	if typeof(uuid) ~= "string" or typeof(pos) ~= "Vector3" then return end
	if rot ~= nil and typeof(rot) ~= "number" then rot = nil end

	local buildingEntity = valid.getBuildingEntityByUUID(uuid)
	if not buildingEntity then print("Invalid building uuid") return end

	local playerEntity = map:get(p)
	local playerData = world:get(playerEntity, Components.Data)

	if not playerData then return end;

	handler:place_building(playerEntity, uuid, pos, rot)
	world:set(playerEntity, Components.Data, playerData)
end

function BuildingAction:handle_upgrade(p: Player, meta: any)
	local uuid = meta.uuid
	if typeof(uuid) ~= "string" then return end

	local buildingEntity = valid.getBuildingEntityByUUID(uuid)
	if not buildingEntity then print("Invalid building uuid") return end

	local playerEntity = map:get(p)
	local playerData = world:get(playerEntity, Components.Data)

	if not playerData then print("Invalid player data") return end;

	-- find buildingType (quick scan)
	local buildingType: number? = nil
	if type(playerData.Buildings) == "table" then
		for bt, dict in pairs(playerData.Buildings) do
			if type(dict) == "table" and ((dict.builds and dict.builds[uuid]) or dict[uuid]) then
				buildingType = bt
				break
			end
		end
	end
	if not buildingType then print("Invalid building type") return end

	local details = valid.canUpgrade(playerData, buildingType, uuid)
	if not details.ok then print(details.reason) return end

	handler:upgrade_building(playerData, buildingEntity, uuid, details.amount or 0)
	world:set(playerEntity, Components.Data, playerData)

	setAttrs(p, playerData)

	task.delay(details.time or 0, function()
		handler:finish_construction(uuid)
	end)
end

function BuildingAction:handle_cancel(p: Player, meta: any)
	local uuid = meta.uuid
	if typeof(uuid) ~= "string" then return end

	local buildingEntity = handler:resolve_entity_from_uuid(uuid)
	if not buildingEntity then return end

	local playerEntity = map:get(p)
	local playerData = world:get(playerEntity, Components.Data)

	if not playerData then return end;

	handler:cancel_construction(playerData, buildingEntity, 0)
	world:set(playerEntity, Components.Data, playerData)

	setAttrs(p, playerData)
end

function BuildingAction:init()
	Blink.Actions.BuildingAction.On(function(player, packet)
		BuildingAction:OnReceive(player, packet)
	end)
end
return BuildingActi
