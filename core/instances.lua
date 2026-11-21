-- Instances (routing buckets), attribuées par la ressource hexa_core pour tout le serveur.
-- Les ressources passent par Hexa.SetInstance / Hexa.LeaveInstance / Hexa.GetInstance.
local cfg = Hexa.ServerConfig.Instances or {}
-- Premier bucket donné : firstBucket + 1 (config_server.lua → Instances.firstBucket, 1000 par défaut).
local FIRST_BUCKET = math.max(0, math.floor(tonumber(cfg.firstBucket) or 1000))
local named = {}               -- [nom] = { bucket, members = { [source] = true } }
local players = {}             -- [source] = { name, previous, bucket }
local free, last = {}, FIRST_BUCKET

local function allocate()
    local bucket = table.remove(free)
    if bucket then return bucket end
    last = last + 1
    return last
end

-- Retire le joueur de son instance. restore = false : ne pas le replacer (déconnexion).
local function leave(source, restore)
    local entry = players[source]
    if not entry then return false end
    players[source] = nil
    local instance = named[entry.name]
    if instance then
        instance.members[source] = nil
        if not next(instance.members) then
            named[entry.name] = nil
            free[#free + 1] = instance.bucket
        end
    end
    if restore ~= false then SetPlayerRoutingBucket(source, entry.previous or 0) end
    return true
end

exports('SetInstance', HexaGuard('SetInstance', function(source, name, options)
    source = tonumber(source)
    if not source or not GetPlayerName(source) then return nil end
    options = type(options) == 'table' and options or {}
    name = name ~= nil and tostring(name) or ('solo:' .. source)
    local previous = players[source] and players[source].previous or GetPlayerRoutingBucket(source)
    if players[source] then leave(source, false) end
    local instance = named[name]
    if not instance then
        instance = { bucket = allocate(), members = {} }
        named[name] = instance
        SetRoutingBucketPopulationEnabled(instance.bucket, options.population == true)
    end
    instance.members[source] = true
    players[source] = { name = name, previous = previous, bucket = instance.bucket }
    SetPlayerRoutingBucket(source, instance.bucket)
    if options.vehicle then
        local vehicle = GetVehiclePedIsIn(GetPlayerPed(source), false)
        if vehicle and vehicle ~= 0 then SetEntityRoutingBucket(vehicle, instance.bucket) end
    end
    return instance.bucket
end, nil))

exports('LeaveInstance', HexaGuard('LeaveInstance', function(source) return leave(tonumber(source)) end, false))

exports('GetInstance', function(source)
    local entry = players[tonumber(source)]
    if not entry then return nil end
    return entry.name, named[entry.name] and named[entry.name].bucket
end)

AddEventHandler('playerDropped', function() leave(source, false) end)

-- hexa_core garde la main sur les joueurs qu'IL a placés : si un autre script change leur bucket, on les remet
-- dans leur instance (et on le dit une fois par joueur). Les joueurs hors instance ne sont jamais touchés.
local conflicts, warned = 0, {}
local function enforce()
    for source, entry in pairs(players) do
        local actual = GetPlayerRoutingBucket(source)
        if actual ~= entry.bucket then
            conflicts = conflicts + 1
            SetPlayerRoutingBucket(source, entry.bucket)
            if not warned[source] then
                warned[source] = true
                Hexa.Print(('Le bucket du joueur %s a été changé par un autre script (%s au lieu de %s) : remis dans l’instance « %s ».')
                    :format(source, actual, entry.bucket, entry.name), 'warn')
                Hexa.Log('security', ('Bucket du joueur %s modifié par un autre script : remis dans l’instance « %s ».'):format(source, entry.name), source, nil, 'warning')
            end
        end
    end
end

if cfg.enforce ~= false then
    CreateThread(function()
        while true do
            Wait(5000)
            if next(players) then enforce() end
        end
    end)
end

AddEventHandler('playerDropped', function() warned[source] = nil end)

HexaInstances = { named = named, players = players, enforce = enforce, conflicts = function() return conflicts end }
