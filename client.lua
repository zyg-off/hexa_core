-- hexa_core côté client.
--     client_script '@hexa_core/client.lua'   (après @hexa_core/shared.lua)
assert(Hexa and Hexa.__shared, 'hexa_core : incluez @hexa_core/shared.lua avant @hexa_core/client.lua')
if Hexa.__client then return end
Hexa.__client = true

local fw, core, isQB = Hexa.framework, Hexa.core, Hexa.isQB

-- Rappels -> serveur -----------------------------------------------------------------------------------
-- local result = Hexa.Request('deposit', { amount = 500 })   -- à appeler dans un thread
-- Si le serveur répond { retry = true } (cooldown), la demande est renvoyée jusqu'à 3 fois.
local pending, lastId = {}, 0

local function send(name, data, timeoutMs)
    lastId = lastId + 1
    local id, result = lastId, promise.new()
    pending[id] = result
    TriggerServerEvent(Hexa.resource .. ':hexa:request', id, name, data or {})
    SetTimeout(timeoutMs or 8000, function()
        if pending[id] then pending[id] = nil; result:resolve({ ok = false, timeout = true }) end
    end)
    return Citizen.Await(result)
end

function Hexa.Request(name, data, timeoutMs)
    local result
    for _ = 1, 3 do
        result = send(name, data, timeoutMs)
        if not (type(result) == 'table' and result.retry) then break end
        Wait(350)
    end
    return type(result) == 'table' and result or { ok = false }
end

RegisterNetEvent(Hexa.resource .. ':hexa:response', function(id, result)
    local entry = pending[id]
    if entry then pending[id] = nil; entry:resolve(result or { ok = false }) end
end)

-- Notifications ----------------------------------------------------------------------------------------
-- Ordre : affichage propre à la ressource (Hexa.SetNotify) > hexa_notify > framework > GTA.
local override

-- fn(message, kind) ; renvoie true si elle a affiché le message elle-même (ex. toast dans l'interface).
function Hexa.SetNotify(fn) override = fn end

function Hexa.Notify(message, kind)
    if not message then return end
    kind = kind or 'info'
    if override and override(message, kind) then return end
    if GetResourceState('hexa_notify') == 'started' then
        local ok = pcall(function() exports.hexa_notify:Notify({ type = kind, message = message }) end)
        if ok then return end
    end
    if fw == 'esx' then return TriggerEvent('esx:showNotification', message, kind) end
    if isQB then
        local qbKind = kind == 'error' and 'error' or kind == 'success' and 'success' or 'primary'
        return TriggerEvent('QBCore:Notify', message, qbKind)
    end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, false)
end

RegisterNetEvent(Hexa.resource .. ':hexa:notify', function(message, kind) Hexa.Notify(message, kind) end)

-- Données du joueur ------------------------------------------------------------------------------------
function Hexa.GetPlayerData()
    if fw == 'esx' then return core.GetPlayerData() or {} end
    if fw == 'qb' then return core.Functions.GetPlayerData() or {} end
    if fw == 'qbx' then
        local ok, data = pcall(function() return exports.qbx_core:GetPlayerData() end)
        return ok and data or {}
    end
    return {}
end

-- Métier : nom, grade, libellé, en service.
function Hexa.Job()
    local job = Hexa.GetPlayerData().job
    if not job then return nil, 0, nil, false end
    if fw == 'esx' then return job.name, tonumber(job.grade) or 0, job.label, true end
    local grade = type(job.grade) == 'table' and job.grade.level or job.grade
    return job.name, tonumber(grade) or 0, job.label, job.onduty ~= false
end

-- Second groupe : gang (QBCore / QBox) ou job2 (versions d'ESX qui l'ont). Nom, grade, libellé, ou nil.
local noGroup = { none = true, unemployed = true, unemployed2 = true }
function Hexa.Gang()
    local data = Hexa.GetPlayerData()
    local gang = fw == 'esx' and data.job2 or data.gang
    if type(gang) ~= 'table' or not gang.name or noGroup[gang.name] then return nil, 0, nil end
    local grade = type(gang.grade) == 'table' and gang.grade.level or gang.grade
    return gang.name, tonumber(grade) or 0, gang.label
end

-- Le gang (QBCore / QBox) et le job2 (ESX) comptent aussi.
function Hexa.HasJob(name, minGrade)
    local job, grade = Hexa.Job()
    local gang, gangGrade = Hexa.Gang()
    minGrade = minGrade or 0
    for _, wanted in ipairs(type(name) == 'table' and name or { name }) do
        if job and job == wanted and grade >= minGrade then return true end
        if gang and gang == wanted and gangGrade >= minGrade then return true end
    end
    return false
end

-- IDs permanents (affichage seulement : le serveur fait foi pour toute vérification).
function Hexa.PlayerId() return LocalPlayer.state.hexaPlayerId end
function Hexa.CharId() return LocalPlayer.state.hexaCharId end

function Hexa.IsDead()
    if isQB then
        local metadata = Hexa.GetPlayerData().metadata or {}
        if metadata.isdead or metadata.inlaststand then return true end
    end
    if LocalPlayer.state.isDead then return true end
    return IsEntityDead(PlayerPedId())
end

-- Plaque comparable d'un véhicule (majuscules, sans espaces autour).
function Hexa.GetPlate(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return Hexa.Plate(GetVehicleNumberPlateText(vehicle))
end

-- Joueur chargé / déchargé / changement de métier ------------------------------------------------------
Hexa.loaded = false
local onLoaded, onUnloaded, onJob = {}, {}, {}

local function setLoaded(value)
    if Hexa.loaded == value then return end
    Hexa.loaded = value
    for _, callback in ipairs(value and onLoaded or onUnloaded) do CreateThread(callback) end
end

-- Le métier vient de l'événement : le framework n'a peut-être pas encore mis à jour ses données.
local function jobChanged(job)
    if not job then return end
    local grade = type(job.grade) == 'table' and job.grade.level or job.grade
    for _, callback in ipairs(onJob) do CreateThread(function() callback(job.name, tonumber(grade) or 0) end) end
end

-- Si le joueur est déjà chargé (ressource redémarrée en jeu), le rappel part tout de suite.
function Hexa.OnPlayerLoaded(callback)
    onLoaded[#onLoaded + 1] = callback
    if Hexa.loaded then CreateThread(callback) end
end

function Hexa.OnPlayerUnloaded(callback) onUnloaded[#onUnloaded + 1] = callback end

-- callback(nomDuMétier, grade)
function Hexa.OnJobChange(callback) onJob[#onJob + 1] = callback end

if fw == 'esx' then
    RegisterNetEvent('esx:playerLoaded', function() setLoaded(true) end)
    RegisterNetEvent('esx:onPlayerLogout', function() setLoaded(false) end)
    RegisterNetEvent('esx:setJob', jobChanged)
elseif isQB then
    -- QBox déclenche les mêmes événements que QBCore.
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() setLoaded(true) end)
    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function() setLoaded(false) end)
    RegisterNetEvent('QBCore:Client:OnJobUpdate', jobChanged)
end

CreateThread(function()
    Wait(500)
    if fw == 'esx' and core.IsPlayerLoaded and core.IsPlayerLoaded() then setLoaded(true)
    elseif isQB and LocalPlayer.state.isLoggedIn then setLoaded(true) end
end)

-- Outils -----------------------------------------------------------------------------------------------

-- Dialogues et aide à l'écran -------------------------------------------------------------------------
-- Affichés par la ressource hexa_core (fenêtre au style Hexa). Input, Form et Confirm attendent la
-- réponse du joueur : à appeler depuis un thread. Voir le README pour tous les types de champs.
local function coreCall(fn, ...)
    local args = table.pack(...)
    return pcall(function() return exports.hexa_core[fn](exports.hexa_core, table.unpack(args, 1, args.n)) end)
end

-- Clavier de GTA, si hexa_core ne répond pas (ne devrait pas arriver : il est obligatoire).
local function keyboard(options)
    AddTextEntry('HEXA_CORE_INPUT', tostring(options.title or options.label or ''))
    DisplayOnscreenKeyboard(1, 'HEXA_CORE_INPUT', '', tostring(options.default or ''), '', '', '', tonumber(options.max) or 64)
    while UpdateOnscreenKeyboard() == 0 do Wait(0) end
    if UpdateOnscreenKeyboard() ~= 1 then return nil end
    local value = GetOnscreenKeyboardResult()
    if options.type == 'number' or options.type == 'amount' then return tonumber(value) end
    return value
end

-- local montant = Hexa.Input({ title = 'Retrait', type = 'amount', max = 5000 })   -- nil si annulé
function Hexa.Input(options)
    local ok, value = coreCall('Input', options)
    if ok then return value end
    return keyboard(type(options) == 'table' and options or { title = options })
end

-- local r = Hexa.Form({ { type = 'text', name = 'motif', label = 'Motif' }, { type = 'amount', name = 'montant' } }, { title = 'Amende' })
-- r.motif, r.montant (ou r[1], r[2]) ; nil si annulé.
function Hexa.Form(fields, options)
    local ok, values = coreCall('Form', fields, options)
    return ok and values or nil
end

-- true (Oui) ou false (Non, Échap).
function Hexa.Confirm(options)
    local ok, value = coreCall('Confirm', options)
    return ok and value == true
end

-- Petit menu liste : renvoie la valeur choisie (ou son numéro), puis le numéro ; nil si annulé.
-- Hexa.Menu({ title = 'Garage', options = { { label = 'Sortir', value = 'out' }, { label = 'Réparer', description = '150 $', value = 'fix' } } })
function Hexa.Menu(options)
    local ok, value, index = coreCall('Menu', options)
    if ok then return value, index end
    return nil
end

-- Même forme que lib.inputDialog d'ox_lib : renvoie la liste des valeurs dans l'ordre des lignes, ou nil si annulé.
--   local r = Hexa.InputDialog('Amende', { { type = 'input', label = 'Motif', required = true }, { type = 'number', label = 'Montant', min = 1 } })
--   if r then print(r[1], r[2]) end
-- Types reconnus : input (password = true), textarea, number, slider, select, checkbox (checked = true), date, time.
local OX = { input = 'text', textarea = 'textarea', number = 'number', slider = 'slider', select = 'select', checkbox = 'checkbox', date = 'date', time = 'time' }
function Hexa.InputDialog(heading, rows, options)
    local fields = {}
    for i, row in ipairs(type(rows) == 'table' and rows or {}) do
        if type(row) == 'string' then row = { type = 'input', label = row } end
        local f = {
            type = OX[row.type] or 'text', label = row.label, description = row.description, placeholder = row.placeholder,
            required = row.required == true, min = row.min, max = row.max, default = row.default, step = row.step,
            options = row.options,
        }
        if row.type == 'input' and row.password then f.type = 'password' end
        if row.type == 'checkbox' then f.default = row.checked == true; f.required = false end
        if row.type == 'select' and row.clearable then f.required = false end
        fields[i] = f
    end
    local title = type(heading) == 'table' and heading.title or heading
    local values = Hexa.Form(fields, { title = title, submit = type(options) == 'table' and options.confirm or nil, cancel = type(options) == 'table' and options.cancel or nil })
    if not values then return nil end
    local list = {}
    for i = 1, #fields do list[i] = values[i] end
    return list
end

-- Aide qui reste affichée jusqu'à Hexa.HideHelp(). kind : 'success', 'error', 'warning' (facultatif).
function Hexa.ShowHelp(text, kind) coreCall('ShowHelp', text, kind) end
function Hexa.HideHelp() coreCall('HideHelp') end

-- Aide « Appuyez sur ~INPUT_CONTEXT~ … », à appeler à chaque image (comme l'aide de GTA) :
-- renvoyée au plus toutes les 100 ms à hexa_core, disparaît seule quand on arrête de l'appeler.
local lastHelp, lastHelpAt = nil, 0
function Hexa.Help(text)
    local now = GetGameTimer()
    if text == lastHelp and now - lastHelpAt < 100 then return end
    if coreCall('PulseHelp', text) then lastHelp, lastHelpAt = text, now; return end
    lastHelp = nil
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

-- Points d'interaction --------------------------------------------------------------------------------
-- Un comptoir, un vestiaire, un guichet… : Alt + clic avec hexa_interact s'il est démarré,
-- sinon marqueur au sol + touche E. Tous les points du serveur sont gérés par UNE boucle, dans hexa_core.
-- local id = Hexa.AddPoint({
--     coords = vector3(...), label = 'Ouvrir la banque', description = 'Fleeca', icon = 'money',
--     distance = 2.0,                 -- portée (défaut 2.0)
--     radius = 1.2,                   -- taille de la zone hexa_interact (défaut 1.2)
--     key = 38,                       -- touche sans hexa_interact (défaut 38 = E)
--     marker = true,                  -- false : pas de marqueur ; ou { type = 27, size = 0.9, color = { 154, 174, 179, 120 } }
--     help = 'Appuyez sur ~INPUT_CONTEXT~ pour ouvrir la banque',   -- défaut : « [E] » + le label
--     canInteract = function() return true end,
--     onSelect = function() ... end,  -- appelé dans un thread
-- })
-- Hexa.RemovePoint(id)
local points, nextPoint = {}, 0     -- [id] = { point, remote, session }

-- Confie le point à hexa_core. false s'il ne répond pas : la ressource le gère alors elle-même (plus bas).
local function share(entry)
    local ok, remote, session = pcall(function() return exports.hexa_core:AddPoint(entry.point) end)
    if ok and remote then entry.remote, entry.session = remote, session; return true end
    entry.remote, entry.session = nil, nil
    return false
end

function Hexa.AddPoint(point)
    assert(type(point) == 'table' and point.coords and point.onSelect, 'Hexa.AddPoint : coords et onSelect sont obligatoires')
    nextPoint = nextPoint + 1
    point.coords = vector3(point.coords.x, point.coords.y, point.coords.z)
    local entry = { point = point }
    points[nextPoint] = entry
    if not share(entry) then
        -- repli : zone hexa_interact gérée ici
        if GetResourceState('hexa_interact') == 'started' then
            pcall(function()
                exports.hexa_interact:AddSphereZone({ coords = point.coords, radius = point.radius or 1.2, name = Hexa.resource .. ':point:' .. nextPoint }, {
                    name = Hexa.resource .. ':point:' .. nextPoint, label = point.label, description = point.description, icon = point.icon or '◆',
                    distance = (point.distance or 2.0) + 0.5,
                    canInteract = point.canInteract and function() return point.canInteract() == true end or nil,
                    onSelect = function() CreateThread(point.onSelect) end,
                })
            end)
        end
    end
    return nextPoint
end

function Hexa.RemovePoint(id)
    local entry = points[id]
    if not entry then return false end
    points[id] = nil
    if entry.remote then pcall(function() exports.hexa_core:RemovePoint(entry.remote) end)
    elseif GetResourceState('hexa_interact') == 'started' then
        pcall(function() exports.hexa_interact:RemoveZone(Hexa.resource .. ':point:' .. id) end)
    end
    return true
end

-- hexa_core (re)démarré : on lui redonne les points qu'il ne connaît pas.
AddEventHandler('hexa_core:client:ready', function(session)
    if Hexa.resource == 'hexa_core' then return end
    for _, entry in pairs(points) do
        if entry.session ~= session then share(entry) end
    end
end)

-- Repli si hexa_core ne répond pas : marqueur + touche, dans cette ressource.
CreateThread(function()
    while true do
        local sleep = 1000
        if next(points) and GetResourceState('hexa_interact') ~= 'started' then
            local coords = GetEntityCoords(PlayerPedId())
            for _, entry in pairs(points) do
                local point = entry.point
                if not entry.remote then
                    local distance = #(coords - point.coords)
                    if distance < 12.0 and (not point.canInteract or point.canInteract() == true) then
                        sleep = 0
                        if point.marker ~= false then
                            DrawMarker(27, point.coords.x, point.coords.y, point.coords.z - 0.97, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                                0.9, 0.9, 0.9, 154, 174, 179, 120, false, false, 2, false, nil, nil, false)
                        end
                        if distance <= (point.distance or 2.0) then
                            Hexa.Help(point.help or (point.key and point.label or ('~INPUT_PICKUP~ ' .. point.label)))
                            if IsControlJustReleased(0, point.key or 38) then CreateThread(point.onSelect) end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- Blip sur la carte. options : sprite, color, scale, label, shortRange (vrai par défaut).
function Hexa.Blip(coords, options)
    options = options or {}
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, options.sprite or 1)
    SetBlipColour(blip, options.color or 0)
    SetBlipScale(blip, options.scale or 0.8)
    SetBlipAsShortRange(blip, options.shortRange ~= false)
    if options.label then
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(options.label)
        EndTextCommandSetBlipName(blip)
    end
    return blip
end
