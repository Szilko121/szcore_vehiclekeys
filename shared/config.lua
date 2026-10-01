SzCoreVehicleKeysConfig = {
    maxLockDistance = 7.5, handKeyDistance = 4.0,
    getKeysWhenEngineRunning = true, keepEngineOnExit = true,
    randomWorldLockChance = 0.45, temporaryWorldKeyMinutes = 120,
    lockFlash = true, lockSound = true,
    autoLockJobVehicles = true, autoLockDelay = 2500,
    searchKeys = {enabled=true,minTime=8000,maxTime=14000,successChance=.30,cooldown=10000},
    hotwire = {enabled=true,duration=9000,successChance=.48,cooldown=5000},
    lockpick = {enabled=true,duration=6000,successChance=.55,advancedChance=.78,breakChance=.25},
    carjack = {enabled=true,duration=6500,cooldown=10000,successChance=.80},
    policeAlert = {enabled=true,dayChance=.65,nightChance=.40,cooldown=10000},
    jobPlatePrefixes = { police={'LSPD','POL'}, ambulance={'EMS','AMB'} },
}
