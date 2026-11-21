-- Points d'intérêt de tout le serveur, gérés par la ressource hexa_core : une seule boucle,
-- quel que soit le nombre de ressources. Les ressources passent par Hexa.AddPoint / Hexa.RemovePoint.
-- Avec hexa_interact : Alt + clic. Sans : marqueur au sol + touche (E par défaut) + aide à l'écran.
local points, nextId = {}, 0
local near, allowed, inside, checkedAt = {}, {}, {}, {}    -- état de la boucle d'affichage (points « own »)
local SESSION = ('%x%x'):format(GetGameTimer(), math.random(0, 0xffffff))   -- change à chaque démarrage de hexa_core
local D = HexaDialog
local MARKER = { type = 27, size = 0.9, color = { 154, 174, 179, 120 } }   -- accent neutre HEXA_IDENTITY
local cfg = Hexa.Config.Points or {}
-- Fréquence fixe de la recherche des points proches (ms), réglable : config.lua → Points.interval.
local INTERVAL = math.max(50, math.min(1000, math.floor(tonumber(cfg.interval) or 200)))

local function started(name) return GetResourceState(name) == 'started' end
local function zoneName(id) return 'hexa_core:point:' .. id end

local function call(fn, ...)
    if not fn then return true end
    local ok, result = pcall(fn, ...)
    return ok and result == true
end

-- Formes ---------------------------------------------------------------------------------------------------
-- Sphère (par défaut), boîte (box = { size = vector3, heading = 0.0 }) ou polygone
-- (polygon = { points = { vector3, … }, thickness = 4.0 }).
local function shapeOf(point)
    if type(point.polygon) == 'table' and type(point.polygon.points) == 'table' and #point.polygon.points >= 3 then return 'polygon' end
    if type(point.box) == 'table' and point.box.size then return 'box' end
    return 'sphere'
end

local function prepare(point)
    point.coords = vector3(point.coords.x, point.coords.y, point.coords.z)
    point.shape = shapeOf(point)
    if point.shape == 'polygon' then
        local list, sx, sy, sz = {}, 0.0, 0.0, 0.0
        for i, p in ipairs(point.polygon.points) do
            list[i] = vector3(p.x, p.y, p.z)
            sx, sy, sz = sx + p.x, sy + p.y, sz + p.z
        end
        point.polygon = { points = list, thickness = tonumber(point.polygon.thickness) or 4.0 }
        point.coords = vector3(sx / #list, sy / #list, sz / #list)        -- centre : sert à la distance d'affichage
        local far = 0.0
        for _, p in ipairs(list) do far = math.max(far, #(p - point.coords)) end
        point.drawDistance = math.max(point.drawDistance or 12.0, far + 8.0)
    elseif point.shape == 'box' then
        local size = point.box.size
        point.box = { size = vector3(size.x, size.y, size.z), heading = tonumber(point.box.heading) or 0.0 }
        point.drawDistance = math.max(point.drawDistance or 12.0, math.max(size.x, size.y) + 8.0)
    end
end

local function insidePolygon(point, coords)
    local list = point.polygon.points
    local half = point.polygon.thickness / 2
    if math.abs(coords.z - point.coords.z) > half then return false end
    local inside, j = false, #list
    for i = 1, #list do
        local a, b = list[i], list[j]
        if (a.y > coords.y) ~= (b.y > coords.y) and coords.x < (b.x - a.x) * (coords.y - a.y) / (b.y - a.y) + a.x then inside = not inside end
        j = i
    end
    return inside
end

local function insideBox(point, coords)
    local d = coords - point.coords
    local h = math.rad(point.box.heading)
    local lx, ly = d.x * math.cos(h) + d.y * math.sin(h), -d.x * math.sin(h) + d.y * math.cos(h)
    local size = point.box.size
    return math.abs(lx) <= size.x / 2 and math.abs(ly) <= size.y / 2 and math.abs(d.z) <= size.z / 2
end

-- Le joueur est-il « dans » le point (assez près pour interagir) ?
local function isInside(point, coords)
    if point.shape == 'polygon' then return insidePolygon(point, coords) end
    if point.shape == 'box' then return insideBox(point, coords) end
    return #(coords - point.coords) <= (point.distance or 2.0)
end

-- Qui gère le point : hexa_interact (Alt + clic), sinon ox_target, sinon la boucle ci-dessous.
local function backendFor(point)
    if started('hexa_interact') and point.shape ~= 'polygon' then return 'interact' end
    if started('ox_target') then return 'ox' end
    return 'own'
end

local function oxOptions(id, point)
    return { {
        name = zoneName(id), label = point.label, icon = point.icon or 'fa-solid fa-hand-pointer', distance = (point.distance or 2.0) + 0.5,
        canInteract = point.canInteract and function() return call(point.canInteract) end or nil,
        onSelect = function() CreateThread(function() pcall(point.onSelect) end) end,
    } }
end

local function registerZone(id, point)
    point.backend = backendFor(point)
    point.zone = nil
    if point.backend == 'interact' then
        pcall(function()
            local options = {
                name = zoneName(id), label = point.label, description = point.description, icon = point.icon or '◆',
                distance = (point.distance or 2.0) + 0.5,
                canInteract = point.canInteract and function() return call(point.canInteract) end or nil,
                onSelect = function() CreateThread(function() pcall(point.onSelect) end) end,
            }
            if point.shape == 'box' then
                exports.hexa_interact:AddBoxZone({ coords = point.coords, size = point.box.size, rotation = point.box.heading, name = zoneName(id) }, options)
            else
                exports.hexa_interact:AddSphereZone({ coords = point.coords, radius = point.radius or 1.2, name = zoneName(id) }, options)
            end
        end)
    elseif point.backend == 'ox' then
        pcall(function()
            if point.shape == 'polygon' then
                point.zone = exports.ox_target:addPolyZone({ points = point.polygon.points, thickness = point.polygon.thickness, options = oxOptions(id, point) })
            elseif point.shape == 'box' then
                point.zone = exports.ox_target:addBoxZone({ coords = point.coords, size = point.box.size, rotation = point.box.heading, options = oxOptions(id, point) })
            else
                point.zone = exports.ox_target:addSphereZone({ coords = point.coords, radius = point.radius or 1.2, options = oxOptions(id, point) })
            end
        end)
    end
end

local function removeZone(id, point)
    if point.backend == 'interact' and started('hexa_interact') then pcall(function() exports.hexa_interact:RemoveZone(zoneName(id)) end)
    elseif point.backend == 'ox' and point.zone and started('ox_target') then pcall(function() exports.ox_target:removeZone(point.zone) end) end
    point.backend, point.zone = nil, nil
end

-- Icône sur la carte : blip = { sprite = 1, color = 0, scale = 0.8, label = 'Garage' } (label : celui du point par défaut).
local function addBlip(point)
    local blip = point.blip
    if type(blip) ~= 'table' then return end
    local handle = AddBlipForCoord(point.coords.x, point.coords.y, point.coords.z)
    SetBlipSprite(handle, math.floor(tonumber(blip.sprite) or 1))
    SetBlipColour(handle, math.floor(tonumber(blip.color) or 0))
    SetBlipScale(handle, tonumber(blip.scale) or 0.8)
    SetBlipAsShortRange(handle, blip.shortRange ~= false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(tostring(blip.label or point.label or ''))
    EndTextCommandSetBlipName(handle)
    point.blipHandle = handle
end

local function removeBlip(point)
    if point.blipHandle then RemoveBlip(point.blipHandle); point.blipHandle = nil end
end

-- point : coords, onSelect (obligatoires), label, description, icon, distance (2.0), radius (1.2),
-- key (38 = E), help (texte d'aide), marker (false, ou { type, size, color = { r, g, b, a } }), canInteract,
-- box, polygon, blip, text3d (texte flottant : true = le libellé).
exports('AddPoint', function(point)
    if type(point) ~= 'table' or not point.coords or not point.onSelect then return nil end
    nextId = nextId + 1
    prepare(point)
    point.owner = GetInvokingResource() or GetCurrentResourceName()
    points[nextId] = point
    registerZone(nextId, point)
    addBlip(point)
    return nextId, SESSION
end)

local function drop(id)
    local point = points[id]
    if not point then return false end
    points[id] = nil
    near[id], allowed[id], inside[id], checkedAt[id] = nil, nil, nil, nil
    removeZone(id, point)
    removeBlip(point)
    return true
end

exports('RemovePoint', drop)

-- Une ressource s'arrête : ses points disparaissent avec elle.
AddEventHandler('onResourceStop', function(resource)
    for id, point in pairs(points) do
        if point.owner == resource then drop(id) end
    end
end)

-- hexa_interact ou ox_target (re)démarré : on lui redonne les zones.
local function registerAgain(resource)
    if resource ~= 'ox_target' and resource ~= 'hexa_interact' then return end
    for id, point in pairs(points) do
        removeZone(id, point); registerZone(id, point)
        if point.backend ~= 'own' then near[id], allowed[id], inside[id], checkedAt[id] = nil, nil, nil, nil end
    end
end
AddEventHandler('hexa_interact:client:ready', function() registerAgain('hexa_interact') end)
AddEventHandler('onClientResourceStart', registerAgain)

-- Boucle unique du serveur pour les points qui ne dépendent ni de hexa_interact ni d'ox_target :
-- la recherche des points proches tourne à fréquence fixe (INTERVAL) ; l'affichage ne tourne à chaque image
-- que tant qu'un point est à portée. canInteract est demandé 4 fois par seconde au plus.
local function scan(now)
    local coords = GetEntityCoords(PlayerPedId())
    for id, point in pairs(points) do
        if point.backend == 'own' or (point.backend == nil and backendFor(point) == 'own') then
            point.backend = 'own'
            if #(coords - point.coords) < (point.drawDistance or 12.0) then
                if not checkedAt[id] or now - checkedAt[id] >= 250 then
                    allowed[id], checkedAt[id] = call(point.canInteract), now
                end
                near[id], inside[id] = true, isInside(point, coords)
            else
                near[id], allowed[id], inside[id], checkedAt[id] = nil, nil, nil, nil
            end
        elseif near[id] then
            near[id], allowed[id], inside[id], checkedAt[id] = nil, nil, nil, nil
        end
    end
    for id in pairs(near) do if not points[id] then near[id], allowed[id], inside[id], checkedAt[id] = nil, nil, nil, nil end end
end

local function text3d(point)
    local text = point.text3d == true and point.label or point.text3d
    if not text then return end
    local onScreen, x, y = World3dToScreen2d(point.coords.x, point.coords.y, point.coords.z + 0.3)
    if not onScreen then return end
    SetTextScale(0.0, 0.32)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(tostring(text))
    EndTextCommandDisplayText(x, y)
end

local function draw()
    for id in pairs(near) do
        local point = points[id]
        if point and allowed[id] then
            if point.marker ~= false then
                local m = type(point.marker) == 'table' and point.marker or MARKER
                local c, size = m.color or MARKER.color, m.size or MARKER.size
                DrawMarker(m.type or MARKER.type, point.coords.x, point.coords.y, point.coords.z - 0.97, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    size, size, size, c[1], c[2], c[3], c[4] or 120, false, false, 2, false, nil, nil, false)
            end
            if point.text3d then text3d(point) end
            if inside[id] then
                D.pulseHelp(point.help or (point.key and point.label or ('~INPUT_PICKUP~ ' .. tostring(point.label or ''))))
                if IsControlJustReleased(0, point.key or 38) then CreateThread(function() pcall(point.onSelect) end) end
            end
        end
    end
end

CreateThread(function()
    local lastScan = 0
    while true do
        local wait = INTERVAL
        if next(points) then
            local now = GetGameTimer()
            if now - lastScan >= INTERVAL then lastScan = now; scan(now) end
            if next(near) then wait = 0; draw() end
        end
        Wait(wait)
    end
end)

-- hexa_core (re)démarré : les ressources renvoient leurs points (voir client.lua).
CreateThread(function() Wait(0); TriggerEvent('hexa_core:client:ready', SESSION) end)

HexaPoints = { points = points, interval = INTERVAL, near = near }
