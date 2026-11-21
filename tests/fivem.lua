-- Simulation minimale de FiveM (serveur ou client selon SIDE) pour tester hexa_core.
LOG, PRINTS = {}, {}
print = function(...) PRINTS[#PRINTS + 1] = table.concat({ ... }, ' ') end

local V = {}
V.__index = V
V.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0 }, V) end

-- threads ----------------------------------------------------------------------------------------------
NOW = 100000
THREADS = {}
function GetGameTimer() return NOW end
function Wait(ms) coroutine.yield(ms or 0) end
function CreateThread(fn) THREADS[#THREADS + 1] = { co = coroutine.create(fn), wake = NOW } end
function SetTimeout(ms, fn) THREADS[#THREADS + 1] = { co = coroutine.create(function() Wait(ms); fn() end), wake = NOW } end
Citizen = { CreateThread = CreateThread, Wait = Wait }
function RunThreads(advance)
    local target = NOW + (advance or 0)
    for _ = 1, 10000 do
        local idx
        for i, t in ipairs(THREADS) do
            if coroutine.status(t.co) ~= 'dead' and t.wake <= target and (not idx or t.wake < THREADS[idx].wake) then idx = i end
        end
        if not idx then break end
        local t = THREADS[idx]
        if t.wake > NOW then NOW = t.wake end
        local ok, res = coroutine.resume(t.co)
        if not ok then ERRORS[#ERRORS + 1] = tostring(res); t.wake = math.huge
        else t.wake = NOW + math.max(1, tonumber(res) or 0) end
    end
    NOW = target
end
ERRORS = {}

-- promesses (client) -----------------------------------------------------------------------------------
promise = { new = function()
    local p = { done = false }
    function p:resolve(v) if not self.done then self.done, self.value = true, v end end
    return p
end }
Citizen.Await = function(p) while not p.done do Wait(1) end return p.value end

-- ressources et config ---------------------------------------------------------------------------------
RESOURCE_NAME = RESOURCE_NAME or 'hexa_test'
function GetCurrentResourceName() return RESOURCE_NAME end
function IsDuplicityVersion() return SIDE == 'server' end
STOPPED = {}
function StopResource(name) STOPPED[#STOPPED + 1] = name end
RESOURCES = { hexa_core = 'started' }
function GetResourceState(name) return RESOURCES[name] or 'missing' end
FILES = {}
function SaveResourceFile(resource, file, data) if FILES_READONLY then return false end FILES[resource .. '/' .. file] = data; return true end
function LoadResourceFile(resource, file)
    if FILES[resource .. '/' .. file] then return FILES[resource .. '/' .. file] end
    if resource ~= 'hexa_core' then return nil end
    if file == 'config.lua' and CONFIG_OVERRIDE then return CONFIG_OVERRIDE end
    if file == 'config_server.lua' and SERVER_CONFIG_OVERRIDE then return SERVER_CONFIG_OVERRIDE end
    local f = io.open(ROOT_DIR .. '/' .. file, 'r')
    if not f then return nil end
    local text = f:read('a'); f:close(); return text
end

-- événements -------------------------------------------------------------------------------------------
HANDLERS, CLIENT_EVENTS, SERVER_EVENTS, LOCAL_EVENTS = {}, {}, {}, {}
function AddEventHandler(name, fn) HANDLERS[name] = HANDLERS[name] or {}; table.insert(HANDLERS[name], fn) end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...)
    LOCAL_EVENTS[#LOCAL_EVENTS + 1] = { name = name, args = { ... } }
    for _, fn in ipairs(HANDLERS[name] or {}) do fn(...) end
end
function TriggerClientEvent(name, target, ...) CLIENT_EVENTS[#CLIENT_EVENTS + 1] = { name = name, target = target, args = { ... } } end
function TriggerServerEvent(name, ...)
    SERVER_EVENTS[#SERVER_EVENTS + 1] = { name = name, args = { ... } }
    if SERVER_REPLY then SERVER_REPLY(name, ...) end
end
-- Événement réseau reçu par le serveur depuis le joueur `src`, dans sa propre coroutine.
function FromClient(src, name, ...)
    local args = table.pack(...)
    for _, fn in ipairs(HANDLERS[name] or {}) do
        THREADS[#THREADS + 1] = { co = coroutine.create(function() source = src; fn(table.unpack(args, 1, args.n)) end), wake = NOW }
    end
end
function Fire(name, src, ...) source = src; TriggerEvent(name, ...) end
function ClientEventsFor(target, name)
    local r = {}
    for _, e in ipairs(CLIENT_EVENTS) do if e.target == target and e.name == name then r[#r + 1] = e end end
    return r
end

-- exports ----------------------------------------------------------------------------------------------
EXPORTS, RESOURCE_EXPORTS = {}, {}
exports = setmetatable({}, {
    __call = function(_, name, fn) EXPORTS[name] = fn end,
    __index = function(_, resource)
        return setmetatable({}, { __index = function(_, fname)
            return function(_, ...)
                local res = RESOURCE_EXPORTS[resource]
                if not res or not res[fname] then error(('export %s:%s introuvable'):format(resource, fname)) end
                return res[fname](...)
            end
        end })
    end,
})

-- joueurs (serveur) ------------------------------------------------------------------------------------
PLAYERS = {}
function GetPlayers() local r = {} for src in pairs(PLAYERS) do r[#r + 1] = tostring(src) end return r end
function GetPlayerName(src) local p = PLAYERS[tonumber(src)]; return p and p.name or nil end
function GetPlayerPed(src) local p = PLAYERS[tonumber(src)]; return p and (1000 + src) or 0 end
function GetEntityCoords(ped) local p = PLAYERS[ped - 1000]; return p and p.coords or vector3() end
function GetPlayerIdentifierByType(src, kind) local p = PLAYERS[tonumber(src)]; return p and kind == 'license' and (p.license or ('license:' .. src)) or nil end

function GetEntityHealth(ped) local p = PLAYERS[ped - 1000]; return p and (p.health or 200) or 0 end
STATEBAGS = {}
function Player(src)
    STATEBAGS[src] = STATEBAGS[src] or {}
    STATEBAGS[src].set = STATEBAGS[src].set or function(self, key, value) self[key] = value end
    return { state = STATEBAGS[src] }
end
ACES = {}
function IsPlayerAceAllowed(src, ace) return ACES[tonumber(src) .. ':' .. ace] == true end
COMMANDS = {}
function RegisterCommand(name, fn) COMMANDS[name] = fn end
function RunCommand(src, raw) local args = {} for w in raw:gmatch('%S+') do args[#args + 1] = w end local name = table.remove(args, 1); COMMANDS[name](src, args, raw) end
HTTP, HTTP_STATUS = {}, {}
function PerformHttpRequest(url, cb, method, body, headers)
    HTTP[#HTTP + 1] = { url = url, method = method, body = body, headers = headers }
    local status = table.remove(HTTP_STATUS, 1) or 204
    cb(status, '', status == 429 and { ['Retry-After'] = '1' } or {})
end
-- json minimal (encodage seulement, suffisant pour vérifier le contenu envoyé)
json = { encode = function(v)
    local function enc(x)
        local t = type(x)
        if t == 'string' then return '"' .. x:gsub('[%c"\\]', function(c) return string.format('\\u%04x', c:byte()) end) .. '"' end
        if t == 'number' or t == 'boolean' then return tostring(x) end
        if t ~= 'table' then return 'null' end
        local out = {}
        if #x > 0 then for _, v2 in ipairs(x) do out[#out + 1] = enc(v2) end return '[' .. table.concat(out, ',') .. ']' end
        for k, v2 in pairs(x) do out[#out + 1] = enc(tostring(k)) .. ':' .. enc(v2) end
        return '{' .. table.concat(out, ',') .. '}'
    end
    return enc(v)
end }

-- natives client ---------------------------------------------------------------------------------------
NATIVES = {}
for _, name in ipairs({ 'BeginTextCommandThefeedPost', 'AddTextComponentSubstringPlayerName', 'EndTextCommandThefeedPostTicker',
    'BeginTextCommandDisplayHelp', 'EndTextCommandDisplayHelp', 'SetBlipSprite', 'SetBlipColour', 'SetBlipScale',
    'SetBlipAsShortRange', 'BeginTextCommandSetBlipName', 'EndTextCommandSetBlipName' }) do
    _G[name] = function(...) NATIVES[#NATIVES + 1] = { name = name, args = { ... } } end
end
BLIPS = {}
function AddBlipForCoord(x, y, z) BLIPS[#BLIPS + 1] = { x = x, y = y, z = z }; return 77 end
function RemoveBlip(h) BLIPS.removed = (BLIPS.removed or 0) + 1; BLIPS.last = h end
TEXTS = {}
function World3dToScreen2d(x, y, z) return true, 0.5, 0.5 end
for _, n in ipairs({ 'SetTextScale', 'SetTextFont', 'SetTextCentre', 'SetTextOutline', 'BeginTextCommandDisplayText' }) do _G[n] = function() end end
function EndTextCommandDisplayText(x, y) TEXTS[#TEXTS + 1] = { x = x, y = y } end
function PlayerId() return 1 end
function PlayerPedId() return 1 end
CLIENT_DEAD = false
function IsEntityDead() return CLIENT_DEAD end
function DoesEntityExist(e) return e == 55 end
function GetVehicleNumberPlateText() return ' ab 123 ' end
LocalPlayer = { state = {} }

-- points d'interaction (client)
CLIENT_COORDS = vector3()
CONTROLS = {}
function GetEntityCoords(ped) if SIDE == 'client' then return CLIENT_COORDS end local p = PLAYERS[ped - 1000]; return p and p.coords or vector3() end
function DrawMarker(...) MARKERS = (MARKERS or 0) + 1 end
function IsControlJustReleased(_, key) return CONTROLS[key] == true end

-- Ajouts 1.4.0 : convars, json.decode, NUI, instances, aide ESX ---------------------------------------
CONVARS = {}
function GetConvar(name, default) return CONVARS[name] or default end

-- json.decode minimal (objets, tableaux, textes, nombres, booléens, null)
json.decode = function(text)
    local pos = 1
    local function ws() pos = text:find('[^%s]', pos) or #text + 1 end
    local value
    local function str()
        local out, i = {}, pos + 1
        while true do
            local c = text:sub(i, i)
            if c == '' then error('json : texte non terminé') end
            if c == '"' then pos = i + 1; return table.concat(out) end
            if c == '\\' then
                local n = text:sub(i + 1, i + 1)
                if n == 'u' then out[#out + 1] = utf8.char(tonumber(text:sub(i + 2, i + 5), 16)); i = i + 6
                else out[#out + 1] = ({ n = '\n', t = '\t', r = '\r', b = '\b', f = '\f' })[n] or n; i = i + 2 end
            else out[#out + 1] = c; i = i + 1 end
        end
    end
    function value()
        ws()
        local c = text:sub(pos, pos)
        if c == '{' then
            local t = {}; pos = pos + 1; ws()
            if text:sub(pos, pos) == '}' then pos = pos + 1; return t end
            while true do
                ws(); local k = str(); ws(); pos = pos + 1   -- :
                t[k] = value(); ws()
                local d = text:sub(pos, pos); pos = pos + 1
                if d == '}' then return t end
            end
        elseif c == '[' then
            local t = {}; pos = pos + 1; ws()
            if text:sub(pos, pos) == ']' then pos = pos + 1; return t end
            while true do
                t[#t + 1] = value(); ws()
                local d = text:sub(pos, pos); pos = pos + 1
                if d == ']' then return t end
            end
        elseif c == '"' then return str()
        elseif text:sub(pos, pos + 3) == 'true' then pos = pos + 4; return true
        elseif text:sub(pos, pos + 4) == 'false' then pos = pos + 5; return false
        elseif text:sub(pos, pos + 3) == 'null' then pos = pos + 4; return nil
        else
            local n = text:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
            if not n or n == '' then error('json invalide') end
            pos = pos + #n; return tonumber(n)
        end
    end
    local result = value()
    return result
end

NUI, NUI_CALLBACKS, FOCUS = {}, {}, { false, false }
function SendNUIMessage(m) NUI[#NUI + 1] = m end
function SetNuiFocus(a, b) FOCUS = { a, b } end
function RegisterNUICallback(name, fn) NUI_CALLBACKS[name] = fn end
function Nui(name, body) local out; NUI_CALLBACKS[name](body or {}, function(r) out = r end); return out end
function LastNui(action) for i = #NUI, 1, -1 do if NUI[i].action == action then return NUI[i] end end end
function DisableControlAction() end
KBM, PAD_PRESSED = true, {}      -- true = clavier / souris en main ; touches de manette appuyées
function IsInputDisabled() return KBM end
function IsDisabledControlJustPressed(_, control) return PAD_PRESSED[control] == true end
BUTTONS = {}
function GetControlInstructionalButton(_, control) return BUTTONS[control] end

INVOKER = nil
function GetInvokingResource() return INVOKER end
METADATA = {}
function GetNumResources() local n = 0 for _ in pairs(RESOURCES) do n = n + 1 end return n end
function GetResourceByFindIndex(i) local names = {} for k in pairs(RESOURCES) do names[#names + 1] = k end table.sort(names) return names[i + 1] end
CONVARS = CONVARS or {}
function SetConvar(name, value) CONVARS[name] = value end
function GetResourceMetadata(resource, key) return (METADATA[resource] or {})[key] end

-- instances
BUCKETS, POPULATION, ENTITY_BUCKETS = {}, {}, {}
function GetPlayerRoutingBucket(src) return BUCKETS[tonumber(src)] or 0 end
function SetPlayerRoutingBucket(src, bucket) BUCKETS[tonumber(src)] = bucket end
function SetRoutingBucketPopulationEnabled(bucket, enabled) POPULATION[bucket] = enabled end
function SetEntityRoutingBucket(entity, bucket) ENTITY_BUCKETS[entity] = bucket end
VEHICLE_OF = {}
function GetVehiclePedIsIn(ped) return VEHICLE_OF[ped] or 0 end

-- textes du jeu (aide ESX)
LABELS, HIDDEN_HELP, CLEARED_HELP = {}, 0, 0
function AddTextEntry(key, text) LABELS[key] = text end
function GetLabelText(key) return LABELS[key] or 'NULL' end
function HideHelpTextThisFrame() HIDDEN_HELP = HIDDEN_HELP + 1 end
function ClearAllHelpMessages() CLEARED_HELP = CLEARED_HELP + 1 end
