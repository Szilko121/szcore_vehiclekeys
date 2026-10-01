local cache={};local lastVehicle=0;local lastEngine=false;local lastCarjack=0;local lastHotwire=0
local function notify(t,typ)exports.szcore_ui:Notify({description=t,type=typ or'info'})end
local function closestVehicle(max)
    local ped=PlayerPedId();local inside=GetVehiclePedIsIn(ped,false);if inside~=0 then return inside end
    local p=GetEntityCoords(ped);local best,bestD=0,(max or 8.0)^2
    for _,v in ipairs(GetGamePool('CVehicle'))do local c=GetEntityCoords(v);local x,y,z=p.x-c.x,p.y-c.y,p.z-c.z;local d=x*x+y*y+z*z;if d<bestD then best,bestD=v,d end end
    return best
end
local function plate(v)return GetVehicleNumberPlateText(v):gsub('^%s*(.-)%s*$','%1')end
local function has(v,force)local pl=plate(v);if not force and cache[pl]and cache[pl]>GetGameTimer()then return true end;local ok=exports.szcore:AwaitCallback('szcore_vehiclekeys:has',NetworkGetNetworkIdFromEntity(v));if ok then cache[pl]=GetGameTimer()+5000 end;return ok==true end
local function anim(dict,name,dur)
    RequestAnimDict(dict);local t=GetGameTimer()+3000;while not HasAnimDictLoaded(dict)and GetGameTimer()<t do Wait(0)end
    if HasAnimDictLoaded(dict)then TaskPlayAnim(PlayerPedId(),dict,name,8.0,-8.0,dur or 900,48,0,false,false,false)end
end
local function toggle()
    local v=closestVehicle(SzCoreVehicleKeysConfig.maxLockDistance);if v==0 then return end
    local status=GetVehicleDoorLockStatus(v);local lock=not(status==2 or status==4)
    local ok,err=exports.szcore:AwaitCallback('szcore_vehiclekeys:toggle',NetworkGetNetworkIdFromEntity(v),lock)
    if not ok then return notify(err=='no_key'and'Nincs kulcsod ehhez a járműhöz.'or'Nem sikerült.','error')end
    anim('anim@mp_player_intmenu@key_fob@','fob_click_fp',800);SetVehicleDoorsLocked(v,lock and 2 or 1)
    if SzCoreVehicleKeysConfig.lockSound then PlaySoundFrontend(-1,lock and'NAV_UP_DOWN'or'NAV_LEFT_RIGHT','HUD_FRONTEND_DEFAULT_SOUNDSET',true)end
    if SzCoreVehicleKeysConfig.lockFlash then SetVehicleLights(v,2);Wait(90);SetVehicleLights(v,0);Wait(70);SetVehicleLights(v,2);Wait(90);SetVehicleLights(v,0)end
    notify(lock and'Jármű bezárva.'or'Jármű kinyitva.','success')
end
local function engine()
    local p=PlayerPedId();local v=GetVehiclePedIsIn(p,false);if v==0 or GetPedInVehicleSeat(v,-1)~=p then return end
    local ok,err=exports.szcore:AwaitCallback('szcore_vehiclekeys:engine',NetworkGetNetworkIdFromEntity(v));if not ok then return notify(err=='no_key'and'Nincs indítókulcsod.'or'Nem indítható.','error')end
    local on=GetIsVehicleEngineRunning(v);anim('oddjobs@towing','start_engine',650);Wait(400);SetVehicleEngineOn(v,not on,false,true)
end
local function criminal(v,action,duration,advanced)
    if v==0 then return false end
    local labels={hotwire='Gyújtás átkötése...',search='Kulcsok keresése...',lockpick='Zár feltörése...',carjack='Jármű átvétele...'}
    anim(action=='lockpick'and'veh@break_in@0h@p_m_one@'or'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',action=='lockpick'and'low_force_entry_ds'or'machinic_loop_mechandplayer',duration)
    exports.szcore_ui:Progress({label=labels[action]or'Művelet...',duration=duration})
    ClearPedTasks(PlayerPedId())
    local ok,err=exports.szcore:AwaitCallback('szcore_vehiclekeys:criminal',NetworkGetNetworkIdFromEntity(v),action,advanced==true)
    if ok then cache[plate(v)]=GetGameTimer()+10000;notify('Sikerült megszerezned a kulcsot.','success');SetVehicleDoorsLocked(v,1)else notify(err=='failed'and'A próbálkozás sikertelen.'or(err or'Sikertelen.'),'error')end
    return ok
end
RegisterNetEvent('szcore_vehiclekeys:keyChanged',function(p,h)if h then cache[p]=GetGameTimer()+10000 else cache[p]=nil end end)
RegisterNetEvent('szcore_vehiclekeys:useLockpick',function(advanced)
    if not SzCoreVehicleKeysConfig.lockpick.enabled then return notify('A zárfeltörés ki van kapcsolva.','error')end
    local v=closestVehicle(4.0);if v==0 then return notify('Nincs jármű a közelben.','error')end
    local ok=criminal(v,'lockpick',SzCoreVehicleKeysConfig.lockpick.duration,advanced)
    if not ok then TriggerServerEvent('szcore_vehiclekeys:consumeLockpick',advanced)end
end)
RegisterNetEvent('szcore_vehiclekeys:policeAlert',function(d)
    notify(('Járműlopási riasztás: %s'):format(d.plate or'Ismeretlen'),'error')
    local b=AddBlipForCoord(d.x,d.y,d.z);SetBlipSprite(b,161);SetBlipColour(b,1);SetBlipScale(b,1.1)
    BeginTextCommandSetBlipName('STRING');AddTextComponentString('Járműlopási riasztás');EndTextCommandSetBlipName(b)
    SetTimeout(45000,function()RemoveBlip(b)end)
end)
RegisterCommand('vehiclelock',toggle,false);RegisterKeyMapping('vehiclelock','Jármű zárása/nyitása','keyboard','L')
RegisterCommand('vehicleengine',engine,false);RegisterKeyMapping('vehicleengine','Jármű motor indítás/leállítás','keyboard','X')
RegisterCommand('givekeys',function()
    local v=closestVehicle(5.0);if v==0 or not has(v,true)then return notify('Nincs átadható kulcs.','error')end
    local mp=GetEntityCoords(PlayerPedId());local closest,dist=nil,16.0
    for _,pid in ipairs(GetActivePlayers())do if pid~=PlayerId()then local pp=GetEntityCoords(GetPlayerPed(pid));local d=#(mp-pp);if d<dist then dist=d;closest=GetPlayerServerId(pid)end end end
    if not closest then return notify('Nincs játékos a közelben.','error')end
    TriggerServerEvent('szcore_vehiclekeys:giveClosest',closest,NetworkGetNetworkIdFromEntity(v),nil);notify('Kulcs átadva.','success')
end,false)
CreateThread(function()
    while true do
        local ped=PlayerPedId();local v=GetVehiclePedIsIn(ped,false)
        if v==0 then
            if lastVehicle~=0 and DoesEntityExist(lastVehicle) then
                if SzCoreVehicleKeysConfig.keepEngineOnExit and lastEngine then SetVehicleEngineOn(lastVehicle,true,true,true) end
                local shared=Entity(lastVehicle).state.szcoreSharedKeyGroups
                if SzCoreVehicleKeysConfig.autoLockJobVehicles and type(shared)=='table' then
                    local old=lastVehicle;SetTimeout(SzCoreVehicleKeysConfig.autoLockDelay,function()if DoesEntityExist(old) then exports.szcore:AwaitCallback('szcore_vehiclekeys:toggle',NetworkGetNetworkIdFromEntity(old),true) end end)
                end
            end
            lastVehicle=0;lastEngine=false;exports.szcore_ui:HideTextUI();Wait(700)
        else
            if lastVehicle~=v then lastVehicle=v;exports.szcore:AwaitCallback('szcore_vehiclekeys:initWorld',NetworkGetNetworkIdFromEntity(v))end
            lastEngine=GetIsVehicleEngineRunning(v)
            if GetPedInVehicleSeat(v,-1)==ped and not has(v)then
                if SzCoreVehicleKeysConfig.getKeysWhenEngineRunning and GetIsVehicleEngineRunning(v)then criminal(v,'running',350,false)
                else
                    SetVehicleEngineOn(v,false,true,true)
                    local hints={};if SzCoreVehicleKeysConfig.hotwire.enabled then hints[#hints+1]='[H] Hotwire' end;if SzCoreVehicleKeysConfig.searchKeys.enabled then hints[#hints+1]='[K] Kulcskeresés' end
                    if #hints>0 then exports.szcore_ui:ShowTextUI(table.concat(hints,'   ')) end
                    if SzCoreVehicleKeysConfig.hotwire.enabled and IsControlJustReleased(0,74)and GetGameTimer()-lastHotwire>SzCoreVehicleKeysConfig.hotwire.cooldown then lastHotwire=GetGameTimer();criminal(v,'hotwire',SzCoreVehicleKeysConfig.hotwire.duration,false)end
                    if SzCoreVehicleKeysConfig.searchKeys.enabled and IsControlJustReleased(0,311)then criminal(v,'search',math.random(SzCoreVehicleKeysConfig.searchKeys.minTime,SzCoreVehicleKeysConfig.searchKeys.maxTime),false)end
                end
            else exports.szcore_ui:HideTextUI()end
            Wait(100)
        end
    end
end)
CreateThread(function()
    while true do
        if SzCoreVehicleKeysConfig.carjack.enabled and IsPlayerFreeAiming(PlayerId())then
            local _,ent=GetEntityPlayerIsFreeAimingAt(PlayerId())
            if ent and ent~=0 and IsEntityAPed(ent)and not IsPedAPlayer(ent)and IsPedArmed(PlayerPedId(),4)then
                local v=GetVehiclePedIsIn(ent,false)
                if v~=0 and #(GetEntityCoords(PlayerPedId())-GetEntityCoords(ent))<8.0 then
                    exports.szcore_ui:ShowTextUI('[G] Jármű elvétele')
                    if IsControlJustReleased(0,47)and GetGameTimer()-lastCarjack>SzCoreVehicleKeysConfig.carjack.cooldown then
                        lastCarjack=GetGameTimer();TaskLeaveVehicle(ent,v,0);Wait(700);TaskSmartFleePed(ent,PlayerPedId(),100.0,-1,false,false);criminal(v,'carjack',SzCoreVehicleKeysConfig.carjack.duration,false)
                    end
                    Wait(0)
                else Wait(300)end
            else Wait(300)end
        else Wait(400)end
    end
end)
AddStateBagChangeHandler('szcoreLocked',nil,function(bag,_,value)local e=GetEntityFromStateBagName(bag);if e~=0 and DoesEntityExist(e)then SetVehicleDoorsLocked(e,value and 2 or 1)end end)
exports('HasKey',has);exports('ToggleLock',toggle);exports('ToggleEngine',engine)
