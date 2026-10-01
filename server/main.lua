local function registerSzCoreCallback(name, fn)
    CreateThread(function()
        local deadline = GetGameTimer() + 15000

        while GetGameTimer() < deadline do
            if GetResourceState('szcore') == 'started' then
                local ok, success, err = pcall(function()
                    return exports['szcore']:CreateCallback(name, fn)
                end)

                if ok and success ~= false then
                    return
                end

                if ok and success == false then
                    print(('[%s] SzCore callback registration rejected: %s (%s)'):format(
                        GetCurrentResourceName(),
                        tostring(name),
                        tostring(err)
                    ))
                    return
                end
            end

            Wait(100)
        end

        print(('[%s] SzCore callback registration timed out: %s'):format(
            GetCurrentResourceName(),
            tostring(name)
        ))
    end)
end

local sessionKeys={};local rate={};local initialized={};local policeAlertRate={}
local function trim(s)return type(s)=='string'and s:gsub('^%s*(.-)%s*$','%1')or''end
local function player(src)return exports.szcore:GetPlayer(src)end
local function allow(src,key,ms)local n=GetGameTimer();rate[src]=rate[src]or{};local p=rate[src][key]or 0;if n-p<ms then return false end;rate[src][key]=n;return true end
local function nearEntity(source,entity,max)
    local ped=GetPlayerPed(source);if ped==0 or entity==0 or not DoesEntityExist(entity)then return false end
    local a,b=GetEntityCoords(ped),GetEntityCoords(entity);local x,y,z=a.x-b.x,a.y-b.y,a.z-b.z;return x*x+y*y+z*z<=(max or SzCoreVehicleKeysConfig.maxLockDistance)^2
end
local function stateGroupAccess(source,entity)
    local p=player(source);if not p then return false end
    local groups=Entity(entity).state.szcoreSharedKeyGroups;if type(groups)~='table'then return false end
    if #groups>0 then for i=1,#groups do if p.hasGroup('jobs',groups[i],0)or p.hasGroup('gangs',groups[i],0)then return true end end;return false end
    for name,grade in pairs(groups)do if p.hasGroup('jobs',name,grade)or p.hasGroup('gangs',name,grade)then return true end end
    return false
end
local function prefixAccess(source,plate)
    local p=player(source);if not p then return false end
    for job,prefixes in pairs(SzCoreVehicleKeysConfig.jobPlatePrefixes or{})do
        if p.hasGroup('jobs',job,0)then for i=1,#prefixes do if plate:upper():sub(1,#prefixes[i])==prefixes[i]:upper()then return true end end end
    end
    return false
end
local function has(source,plate,netId)
    local p=player(source);plate=trim(plate);if not p or plate==''then return false end
    local entity=netId and NetworkGetEntityFromNetworkId(tonumber(netId)or 0)or 0
    if entity~=0 and DoesEntityExist(entity)and stateGroupAccess(source,entity)then return true end
    if prefixAccess(source,plate)then return true end
    local v=exports.szcore_vehicles:GetVehicleByPlate(plate)
    if v then
        if v.citizenid==p.PlayerData.citizenid then return true end
        if MySQL.scalar.await('SELECT 1 FROM szcore_vehicle_keys WHERE vehicle_id=? AND citizenid=? AND (expires_at IS NULL OR expires_at>CURRENT_TIMESTAMP)',{v.id,p.PlayerData.citizenid})then return true end
    end
    local id=p.PlayerData.citizenid;local k=sessionKeys[id]and sessionKeys[id][plate]
    return k~=nil and(k==0 or k>os.time())
end
local function grantSession(source,plate,minutes)
    local p=player(source);if not p then return false end;plate=trim(plate);local id=p.PlayerData.citizenid
    sessionKeys[id]=sessionKeys[id]or{};sessionKeys[id][plate]=minutes and(os.time()+math.max(1,minutes)*60)or 0
    TriggerClientEvent('szcore_vehiclekeys:keyChanged',source,plate,true);return true
end
local function give(source,plate,target,temporaryMinutes)
    local a,b=player(source),player(target);plate=trim(plate);if not a or not b or not has(source,plate)then return false,'no_key'end
    if not exports.szcore:ValidateDistance(source,target,SzCoreVehicleKeysConfig.handKeyDistance)then return false,'too_far'end
    local v=exports.szcore_vehicles:GetVehicleByPlate(plate)
    if not v then grantSession(target,plate,temporaryMinutes or SzCoreVehicleKeysConfig.temporaryWorldKeyMinutes);return true end
    local kind=temporaryMinutes and'temporary'or'shared'
    local expires=temporaryMinutes and os.date('!%Y-%m-%d %H:%M:%S',os.time()+math.max(1,tonumber(temporaryMinutes)or 1)*60)or nil
    MySQL.prepare.await([[INSERT INTO szcore_vehicle_keys (vehicle_id,citizenid,key_type,expires_at) VALUES (?,?,?,?)
      ON DUPLICATE KEY UPDATE key_type=VALUES(key_type),expires_at=VALUES(expires_at)]],{v.id,b.PlayerData.citizenid,kind,expires})
    TriggerClientEvent('szcore_vehiclekeys:keyChanged',target,plate,true);exports.szcore:Audit('vehiclekey.give',source,b.PlayerData.citizenid,{plate=plate});return true
end
local function revoke(source,plate,cid)
    local p=player(source);local v=exports.szcore_vehicles:GetVehicleByPlate(trim(plate));if not p or not v or v.citizenid~=p.PlayerData.citizenid then return false end
    return MySQL.update.await("DELETE FROM szcore_vehicle_keys WHERE vehicle_id=? AND citizenid=? AND key_type<>'owner'",{v.id,cid})>0
end
local function alertPolice(source,entity,action)
    if not SzCoreVehicleKeysConfig.policeAlert.enabled then return end
    local now=GetGameTimer();if policeAlertRate[source] and now-policeAlertRate[source]<SzCoreVehicleKeysConfig.policeAlert.cooldown then return end;policeAlertRate[source]=now
    local hour=tonumber(os.date('%H'))or 12;local chance=(hour>=20 or hour<6)and SzCoreVehicleKeysConfig.policeAlert.nightChance or SzCoreVehicleKeysConfig.policeAlert.dayChance
    if math.random()>chance then return end
    local c=GetEntityCoords(entity);local plate=trim(GetVehicleNumberPlateText(entity))
    for _,sid in ipairs(exports.szcore:GetPlayerSourcesByJob('police',true))do TriggerClientEvent('szcore_vehiclekeys:policeAlert',sid,{x=c.x,y=c.y,z=c.z,plate=plate,action=action})end
end
registerSzCoreCallback('szcore_vehiclekeys:has',function(source,netId)
    local entity=NetworkGetEntityFromNetworkId(tonumber(netId)or 0);if entity==0 then return false end;return has(source,GetVehicleNumberPlateText(entity),netId)
end)
registerSzCoreCallback('szcore_vehiclekeys:toggle',function(source,netId,locked)
    if not allow(source,'toggle',300)then return false,'rate_limited'end
    local entity=NetworkGetEntityFromNetworkId(tonumber(netId)or 0);if not nearEntity(source,entity,SzCoreVehicleKeysConfig.maxLockDistance)then return false,'too_far'end
    local plate=trim(GetVehicleNumberPlateText(entity));if not has(source,plate,netId)then return false,'no_key'end
    SetVehicleDoorsLocked(entity,locked and 2 or 1);Entity(entity).state:set('szcoreLocked',locked==true,true);return true
end)
registerSzCoreCallback('szcore_vehiclekeys:engine',function(source,netId)
    local entity=NetworkGetEntityFromNetworkId(tonumber(netId)or 0);if not nearEntity(source,entity,8.0)then return false,'too_far'end
    if GetPedInVehicleSeat(entity,-1)~=GetPlayerPed(source)then return false,'not_driver'end
    return has(source,GetVehicleNumberPlateText(entity),netId),'no_key'
end)
registerSzCoreCallback('szcore_vehiclekeys:initWorld',function(source,netId)
    local entity=NetworkGetEntityFromNetworkId(tonumber(netId)or 0);if not nearEntity(source,entity,12.0)then return nil end
    local n=tonumber(netId);if initialized[n]~=nil then return initialized[n]end
    local persistent=Entity(entity).state.szcoreVehicleId;if persistent then initialized[n]=GetVehicleDoorLockStatus(entity)==2;return initialized[n]end
    local locked=math.random()<SzCoreVehicleKeysConfig.randomWorldLockChance;initialized[n]=locked;SetVehicleDoorsLocked(entity,locked and 2 or 1);Entity(entity).state:set('szcoreLocked',locked,true);return locked
end)
registerSzCoreCallback('szcore_vehiclekeys:criminal',function(source,netId,action,advanced)
    local actions={hotwire=true,search=true,lockpick=true,carjack=true,running=true};if not actions[action] then return false,'invalid_action' end
    if not allow(source,'criminal',1200)then return false,'cooldown'end
    local entity=NetworkGetEntityFromNetworkId(tonumber(netId)or 0);if not nearEntity(source,entity,8.0)then return false,'too_far'end
    local ped=GetPlayerPed(source);local plate=trim(GetVehicleNumberPlateText(entity));if has(source,plate,netId)then return true,'already_has_key'end
    if action=='hotwire' or action=='search' or action=='running' then if GetPedInVehicleSeat(entity,-1)~=ped then return false,'not_driver' end end
    if action=='running' and (type(GetIsVehicleEngineRunning)~='function' or not GetIsVehicleEngineRunning(entity)) then return false,'engine_not_running' end
    if action=='lockpick' then
        local p=player(source);local inv=p and ('player:'..p.PlayerData.citizenid);local item=advanced and 'advancedlockpick' or 'lockpick'
        if not inv or exports.szcore_inventory:GetItemCount(inv,item)<1 then return false,'missing_lockpick' end
    end
    local chance=.3
    if action=='hotwire'then chance=SzCoreVehicleKeysConfig.hotwire.successChance
    elseif action=='search'then chance=SzCoreVehicleKeysConfig.searchKeys.successChance
    elseif action=='lockpick'then chance=advanced and SzCoreVehicleKeysConfig.lockpick.advancedChance or SzCoreVehicleKeysConfig.lockpick.successChance
    elseif action=='carjack'then chance=SzCoreVehicleKeysConfig.carjack.successChance
    elseif action=='running'then chance=1.0 end
    if action~='running' then alertPolice(source,entity,action) end
    if math.random()<=chance then
        grantSession(source,plate,SzCoreVehicleKeysConfig.temporaryWorldKeyMinutes);SetVehicleDoorsLocked(entity,1);Entity(entity).state:set('szcoreLocked',false,true)
        exports.szcore:Audit('vehiclekey.'..action,source,plate,{});return true
    end
    return false,'failed'
end)
RegisterNetEvent('szcore_vehiclekeys:giveClosest',function(target,netId,minutes)
    local src=source;local entity=NetworkGetEntityFromNetworkId(tonumber(netId)or 0);if entity==0 then return end
    give(src,GetVehicleNumberPlateText(entity),tonumber(target),tonumber(minutes))
end)
exports('HasKey',has);exports('GiveKey',give);exports('RevokeKey',revoke);exports('GrantSessionKey',grantSession)
CreateThread(function()
    while GetResourceState('szcore_inventory')~='started'do Wait(500)end
    exports.szcore_inventory:RegisterUsableItem('lockpick',function(src)TriggerClientEvent('szcore_vehiclekeys:useLockpick',src,false);return true end)
    exports.szcore_inventory:RegisterUsableItem('advancedlockpick',function(src)TriggerClientEvent('szcore_vehiclekeys:useLockpick',src,true);return true end)
end)
AddEventHandler('entityRemoved',function(entity)local n=NetworkGetNetworkIdFromEntity(entity);if n and n~=0 then initialized[n]=nil end end)
AddEventHandler('playerDropped',function()rate[source]=nil;policeAlertRate[source]=nil end)
RegisterNetEvent('szcore_vehiclekeys:consumeLockpick',function(advanced)
    local src=source;local p=player(src);if not p or math.random()>=SzCoreVehicleKeysConfig.lockpick.breakChance then return end
    local inv='player:'..p.PlayerData.citizenid;exports.szcore_inventory:RemoveItem(inv,advanced and'advancedlockpick'or'lockpick',1);TriggerClientEvent('szcore_inventory:refresh',src)
end)
