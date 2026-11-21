-- hexa_core côté serveur.
--     server_script '@hexa_core/server.lua'   (après @hexa_core/shared.lua)
assert(Hexa and Hexa.__shared, 'hexa_core : incluez @hexa_core/shared.lua avant @hexa_core/server.lua')
if Hexa.__server then return end
Hexa.__server = true

local fw, core, isQB = Hexa.framework, Hexa.core, Hexa.isQB

Hexa.ServerConfig = Hexa.__readConfig('config_server.lua', 'HexaServerConfig')
Hexa.ServerConfig.Admin = Hexa.ServerConfig.Admin or { ace = 'hexa.admin', groups = { 'admin', 'superadmin', 'god' } }
Hexa.ServerConfig.Logs = Hexa.ServerConfig.Logs or {}

local T = Hexa.Locale({
    fr = { no_permission = 'Vous n’avez pas la permission.', player = 'Joueur', identifier = 'Identifiant',
        register_unsupported = 'Objet « %s » non enregistré : cet inventaire n’accepte pas de nouveaux objets en cours de route. Déclarez-le dans sa liste d’objets.',
        duty_unsupported = 'Le service (en service / hors service) n’existe pas sous ESX : Hexa.SetDuty ne fait rien.',
        society_create = 'Création du compte « %s » impossible : aucun système de comptes ne le permet par une fonction officielle.' },
    en = { no_permission = 'You do not have permission.', player = 'Player', identifier = 'Identifier',
        register_unsupported = 'Item "%s" not registered: this inventory does not accept new items at runtime. Declare it in its item list.',
        duty_unsupported = 'On/off duty does not exist on ESX: Hexa.SetDuty does nothing.',
        society_create = 'Cannot create account "%s": no account system offers an official function for it.' },
})

-- Appelle un export d'une autre ressource sans planter. Renvoie ok, résultats…
local function try(resource, fn, ...)
    if GetResourceState(resource) ~= 'started' then return false end
    local res, args = exports[resource], table.pack(...)
    return pcall(function() return res[fn](res, table.unpack(args, 1, args.n)) end)
end
Hexa.__try = try

-- Attend une réponse par callback (esx_license, esx_status…), `nil` après `timeout` ms.
local function await(start, timeout)
    local result, done = promise.new(), false
    local function finish(...) if not done then done = true; result:resolve(table.pack(...)) end end
    start(finish)
    SetTimeout(timeout or 3000, function() finish(nil) end)
    local values = Citizen.Await(result)
    return table.unpack(values, 1, values.n)
end

-- Joueur -----------------------------------------------------------------------------------------------
function Hexa.GetPlayer(source)
    source = tonumber(source)
    if not source then return nil end
    if fw == 'esx' then return core.GetPlayerFromId(source) end
    if fw == 'qb' then return core.Functions.GetPlayer(source) end
    if fw == 'qbx' then
        local ok, player = try('qbx_core', 'GetPlayer', source)
        return ok and player or nil
    end
end

-- Identifiant stable du personnage (ESX : identifier, QBCore / QBox : citizenid).
function Hexa.Identifier(source)
    local player = Hexa.GetPlayer(source)
    if not player then return nil end
    if fw == 'esx' then return player.identifier end
    return player.PlayerData.citizenid
end

-- Nom du personnage (pas celui du compte FiveM).
function Hexa.Name(source)
    local player = Hexa.GetPlayer(source)
    if player and fw == 'esx' and player.getName then
        local ok, name = pcall(player.getName)
        if ok and name and name ~= '' then return name end
    elseif player and isQB then
        local info = player.PlayerData.charinfo or {}
        if info.firstname then return (('%s %s'):format(info.firstname, info.lastname or ''):gsub('%s+$', '')) end
    end
    return GetPlayerName(source) or '?'
end

-- Identité du personnage : { firstname, lastname, birthdate, sex = 'm' / 'f', height (cm), birthplace, nationality }
-- (champs inconnus : nil). ESX : esx_identity ; QBCore / QBox : charinfo. Taille, lieu de naissance et
-- nationalité viennent aussi des métadonnées du personnage (remplies par hexa_character).
function Hexa.Identity(source)
    local player = Hexa.GetPlayer(source)
    if not player then return nil end
    local function text(value) return type(value) == 'string' and value ~= '' and value or nil end
    local function meta(key) local ok, value = pcall(Hexa.GetMeta, source, key); return ok and value or nil end
    if fw == 'esx' then
        local get = player.get or function() return nil end
        local sex = get('sex')
        return {
            firstname = get('firstName'), lastname = get('lastName'), birthdate = get('dateofbirth'),
            sex = (sex == 'm' or sex == 'f') and sex or nil,
            height = tonumber(get('height')) or tonumber(meta('height')),
            birthplace = text(meta('birthplace')), nationality = text(meta('nationality')),
        }
    end
    local info = player.PlayerData.charinfo or {}
    local gender = tonumber(info.gender)
    return {
        firstname = info.firstname, lastname = info.lastname, birthdate = info.birthdate,
        sex = gender == 0 and 'm' or gender == 1 and 'f' or nil,
        height = tonumber(meta('height')), birthplace = text(meta('birthplace')) or text(info.birthplace),
        nationality = text(meta('nationality')) or text(info.nationality),
    }
end

-- Métier : nom, grade (nombre), en service. Sur ESX, avoir le métier = être en service.
function Hexa.Job(source)
    local player = Hexa.GetPlayer(source)
    if not player then return nil, 0, false end
    if fw == 'esx' then
        local job = player.job or {}
        return job.name, tonumber(job.grade) or 0, job.name ~= nil
    end
    local job = player.PlayerData.job or {}
    local grade = type(job.grade) == 'table' and job.grade.level or job.grade
    return job.name, tonumber(grade) or 0, job.onduty ~= false
end

-- Second groupe : gang (QBCore / QBox) ou job2 (versions d'ESX qui l'ont). Nom, grade, libellé, ou nil.
local noGroup = { none = true, unemployed = true, unemployed2 = true }
function Hexa.Gang(source)
    local player = Hexa.GetPlayer(source)
    if not player then return nil, 0, nil end
    local gang
    if fw == 'esx' then gang = player.job2 else gang = player.PlayerData.gang end
    if type(gang) ~= 'table' or not gang.name or noGroup[gang.name] then return nil, 0, nil end
    local grade = type(gang.grade) == 'table' and gang.grade.level or gang.grade
    return gang.name, tonumber(grade) or 0, gang.label
end

-- A le métier `name` (ou l'un d'une liste) avec au moins le grade `minGrade` ?
-- Le gang (QBCore / QBox) et le job2 (ESX) comptent aussi.
function Hexa.HasJob(source, name, minGrade)
    local job, grade = Hexa.Job(source)
    local gang, gangGrade = Hexa.Gang(source)
    minGrade = minGrade or 0
    for _, wanted in ipairs(type(name) == 'table' and name or { name }) do
        if job and job == wanted and grade >= minGrade then return true end
        if gang and gang == wanted and gangGrade >= minGrade then return true end
    end
    return false
end

-- Joueur connecté qui joue ce personnage, ou nil.
function Hexa.SourceOf(identifier)
    if not identifier then return nil end
    local player
    if fw == 'esx' and core.GetPlayerFromIdentifier then player = core.GetPlayerFromIdentifier(identifier)
    elseif fw == 'qb' then player = core.Functions.GetPlayerByCitizenId(identifier)
    elseif fw == 'qbx' then local ok, p = try('qbx_core', 'GetPlayerByCitizenId', identifier); player = ok and p or nil end
    if not player then return nil end
    return fw == 'esx' and player.source or player.PlayerData.source
end

-- IDs permanents et courts, attribués par hexa_core (voir ids.lua). nil tant qu'ils ne sont pas prêts
-- (quelques ms après la connexion / le choix du personnage).
local function ids(fn, value)
    local ok, result = try('hexa_core', fn, value)
    return ok and result or nil
end
function Hexa.PlayerId(source) return ids('GetPlayerId', source) end          -- un par compte FiveM
function Hexa.CharId(source) return ids('GetCharId', source) end              -- un par personnage
function Hexa.SourceOfPlayerId(id) return ids('GetSourceByPlayerId', id) end
function Hexa.SourceOfCharId(id) return ids('GetSourceByCharId', id) end
function Hexa.CharIdOf(identifier) return ids('GetCharIdByIdentifier', identifier) end    -- hors ligne aussi
function Hexa.IdentifierOfCharId(id) return ids('GetIdentifierByCharId', id) end
function Hexa.LastSeen(playerId) return ids('GetLastSeen', playerId) end                 -- secondes depuis 1970, hors ligne aussi

-- Personnage supprimé : à appeler par la ressource qui supprime (wipe, suppression). Prévient les autres
-- ressources par l'événement ci-dessous, pour qu'elles purgent leurs données. L'ID n'est jamais redonné.
function Hexa.DeleteCharacter(identifier) return ids('DeleteCharacter', identifier) end
function Hexa.OnCharacterDeleted(callback)       -- callback(charId, identifier)
    AddEventHandler('hexa_core:characterDeleted', callback)
end

function Hexa.Distance(source, coords)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not coords then return math.huge end
    return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z))
end

function Hexa.IsNear(source, coords, maxDistance)
    return Hexa.Distance(source, coords) <= (maxDistance or 3.0)
end

-- Métadonnées ------------------------------------------------------------------------------------------
-- ESX Legacy : xPlayer.getMeta / setMeta. QBCore / QBox : PlayerData.metadata.
function Hexa.GetMeta(source, key)
    local player = Hexa.GetPlayer(source)
    if not player then return nil end
    if fw == 'esx' then return player.getMeta and player.getMeta(key) or nil end
    return (player.PlayerData.metadata or {})[key]
end

function Hexa.SetMeta(source, key, value)
    local player = Hexa.GetPlayer(source)
    if not player then return false end
    if fw == 'esx' then
        if not player.setMeta then return false end
        player.setMeta(key, value)
        return true
    end
    player.Functions.SetMetaData(key, value)
    return true
end

local function percent(value) return math.max(0, math.min(100, math.floor((tonumber(value) or 0) + 0.5))) end

-- Faim et soif en % (0 à 100), ou nil si inconnues. ESX : via esx_status.
function Hexa.GetNeeds(source)
    if isQB then
        local hunger, thirst = Hexa.GetMeta(source, 'hunger'), Hexa.GetMeta(source, 'thirst')
        return hunger and percent(hunger), thirst and percent(thirst)
    end
    if GetResourceState('esx_status') ~= 'started' then return nil, nil end
    local function read(name)
        local status = await(function(done) TriggerEvent('esx_status:getStatus', source, name, done) end, 1000)
        return status and status.val and percent(status.val / 10000) or nil
    end
    return read('hunger'), read('thirst')
end

-- Fixe la faim ou la soif (`need` = 'hunger' / 'thirst') à `value` %.
function Hexa.SetNeed(source, need, value)
    if need ~= 'hunger' and need ~= 'thirst' then return false end
    value = percent(value)
    if isQB then
        if not Hexa.SetMeta(source, need, value) then return false end
        local hunger, thirst = Hexa.GetNeeds(source)
        TriggerClientEvent('hud:client:UpdateNeeds', source, hunger, thirst)
        return true
    end
    if GetResourceState('esx_status') ~= 'started' then return false end
    TriggerClientEvent('esx_status:set', source, need, value * 10000)
    return true
end

-- Mort ou à terre (QBCore / QBox : isdead / inlaststand ; partout : santé à 0).
function Hexa.IsDead(source)
    if isQB and (Hexa.GetMeta(source, 'isdead') or Hexa.GetMeta(source, 'inlaststand')) then return true end
    local state = Player(source).state
    if state and state.isDead then return true end
    local ped = GetPlayerPed(source)
    return ped ~= 0 and GetEntityHealth(ped) <= 0
end

-- Fiche du joueur en une seule table (tout ce que les autres fonctions donnent, au même endroit).
-- options.needs = false : saute la faim et la soif (sur ESX elles passent par esx_status, jusqu'à 1 s chacune).
-- Champs absents : nil. Le service et la langue ne sont pas là : le service viendra avec Hexa.OnDuty,
-- et FiveM ne donne pas la langue du joueur au serveur.
function Hexa.Profile(source, options)
    source = tonumber(source)
    if not source or not Hexa.GetPlayer(source) then return nil end
    local identity = Hexa.Identity(source) or {}
    local job, grade, duty = Hexa.Job(source)
    local gang, gangGrade = Hexa.Gang(source)
    local profile = {
        source = source, playerId = Hexa.PlayerId(source), charId = Hexa.CharId(source), identifier = Hexa.Identifier(source),
        name = Hexa.Name(source), firstname = identity.firstname, lastname = identity.lastname,
        birthdate = identity.birthdate, sex = identity.sex, height = identity.height,
        birthplace = identity.birthplace, nationality = identity.nationality,
        job = job, grade = grade, duty = duty, gang = gang, gangGrade = gang and gangGrade or nil,
        admin = Hexa.IsAdmin(source), dead = Hexa.IsDead(source),
    }
    local player = Hexa.GetPlayer(source)
    if fw == 'esx' then profile.metadata = player.metadata else profile.metadata = player.PlayerData.metadata end
    if not options or options.needs ~= false then profile.hunger, profile.thirst = Hexa.GetNeeds(source) end
    local ped = GetPlayerPed(source)
    if ped ~= 0 then
        local coords = GetEntityCoords(ped)
        profile.coords = { x = coords.x, y = coords.y, z = coords.z }
    end
    local ok, phone = try('hexa_phone', 'GetNumber', source)
    profile.phone = ok and phone or nil
    return profile
end

-- Argent : `kind` = 'cash' ou 'bank' --------------------------------------------------------------------
local function accountName(kind) return ((Hexa.Config.Accounts or {})[fw] or {})[kind] end

-- hexa_banking est la caisse de l'écosystème : la banque passe par lui (historique du joueur).
local function useBanking()
    return Hexa.resource ~= 'hexa_banking' and GetResourceState('hexa_banking') == 'started'
end

function Hexa.Balance(source, kind)
    local player, account = Hexa.GetPlayer(source), accountName(kind)
    if not player or not account then return 0 end
    if fw == 'esx' then
        local data = player.getAccount and player.getAccount(account)
        return math.floor(data and tonumber(data.money) or 0)
    end
    return math.floor(tonumber((player.PlayerData.money or {})[account]) or 0)
end

function Hexa.AddMoney(source, kind, amount, reason)
    local player, account = Hexa.GetPlayer(source), accountName(kind)
    amount = Hexa.Amount(amount)
    if not player or not account or not amount or amount == 0 then return false end
    if kind == 'bank' and useBanking() then
        local ok, result = try('hexa_banking', 'AddBankMoney', source, amount, reason)
        return ok and result ~= false
    end
    if fw == 'esx' then player.addAccountMoney(account, amount, reason); return true end
    return player.Functions.AddMoney(account, amount, reason) ~= false
end

-- Retire seulement si le solde suffit.
function Hexa.RemoveMoney(source, kind, amount, reason)
    local player, account = Hexa.GetPlayer(source), accountName(kind)
    amount = Hexa.Amount(amount)
    if not player or not account or not amount or amount == 0 then return false end
    if Hexa.Balance(source, kind) < amount then return false end
    if kind == 'bank' and useBanking() then
        local ok, result = try('hexa_banking', 'RemoveBankMoney', source, amount, reason)
        return ok and result ~= false
    end
    if fw == 'esx' then player.removeAccountMoney(account, amount, reason); return true end
    return player.Functions.RemoveMoney(account, amount, reason) ~= false
end

-- Encaisse `amount` sur le premier compte assez approvisionné. Renvoie true, compte débité.
function Hexa.Pay(source, amount, reason, order)
    amount = Hexa.Amount(amount)
    if not amount then return false end
    if amount == 0 then return true, nil end
    if useBanking() then
        local ok, paid, account = try('hexa_banking', 'Pay', source, amount, reason, order)
        if ok then return paid == true, account end
        -- On ne retente pas en direct : le débit a peut-être déjà eu lieu.
        Hexa.Print('hexa_banking:Pay : ' .. tostring(paid), 'error')
        return false
    end
    for _, kind in ipairs(order or Hexa.Config.PaymentOrder) do
        if Hexa.RemoveMoney(source, kind, amount, reason) then return true, kind end
    end
    return false
end

-- Rembourse sur le compte renvoyé par Hexa.Pay.
function Hexa.Refund(source, account, amount, reason)
    if not account then return false end
    if useBanking() then
        local ok, result = try('hexa_banking', 'Refund', source, account, amount, reason)
        if not ok then Hexa.Print('hexa_banking:Refund : ' .. tostring(result), 'error') end
        return ok and result ~= false
    end
    return Hexa.AddMoney(source, account, amount, reason)
end

-- Objets et armes --------------------------------------------------------------------------------------
-- Ordre : hexa_inventory > inventaire du framework (ESX, qb-inventory, ox_inventory pour QBox).
local function hexaInventory() return GetResourceState('hexa_inventory') == 'started' end

-- QBCore : noms en minuscules. QBox (ox_inventory) : objets en minuscules, armes en majuscules.
local function itemName(name)
    if type(name) ~= 'string' then return nil end
    if fw == 'qb' then return name:lower() end
    if fw == 'qbx' then return Hexa.IsWeapon(name) and name:upper() or name:lower() end
    return name
end

function Hexa.ItemLabel(name)
    name = itemName(name)
    if not name then return nil end
    if fw == 'esx' then
        if Hexa.IsWeapon(name) then
            local found, label = pcall(function() return core.GetWeaponLabel and core.GetWeaponLabel(name) end)   -- ESX : erreur si arme inconnue
            if not found then label = nil end
            if label and label ~= '' and label ~= name then return label end
            return (name:sub(8):gsub('_', ' '):lower():gsub('^%l', string.upper))
        end
        if core.GetItemLabel then return core.GetItemLabel(name) end
        local items = core.GetItems and core.GetItems() or core.Items or {}
        return items[name] and (items[name].label or name) or nil
    end
    if fw == 'qb' then
        local item = (core.Shared and core.Shared.Items or {})[name]
        return item and (item.label or name) or nil
    end
    if fw == 'qbx' then
        local ok, item = try('ox_inventory', 'Items', name)
        return ok and item and (item.label or name) or nil
    end
end

function Hexa.ItemCount(source, name)
    name = itemName(name)
    if not name then return 0 end
    if hexaInventory() then
        local ok, count = try('hexa_inventory', 'GetItemCount', source, name)
        if ok and tonumber(count) then return tonumber(count) end
    end
    if fw == 'qbx' then
        local ok, count = try('ox_inventory', 'GetItemCount', source, name)
        return ok and tonumber(count) or 0
    end
    local player = Hexa.GetPlayer(source)
    if not player then return 0 end
    if fw == 'esx' then
        if Hexa.IsWeapon(name) then return player.hasWeapon and player.hasWeapon(name) and 1 or 0 end
        local item = player.getInventoryItem and player.getInventoryItem(name)
        return item and tonumber(item.count) or 0
    end
    local ok, count = try('qb-inventory', 'GetItemCount', source, name)
    if ok and tonumber(count) then return tonumber(count) end
    local item = player.Functions.GetItemByName and player.Functions.GetItemByName(name)
    return item and tonumber(item.amount or item.count) or 0
end

function Hexa.HasItem(source, name, count)
    return Hexa.ItemCount(source, name) >= (count or 1)
end

function Hexa.CanCarry(source, name, count)
    name, count = itemName(name), Hexa.Amount(count or 1)
    if not name or not count then return false end
    if hexaInventory() then
        local ok, result = try('hexa_inventory', 'CanCarryItem', source, name, count)
        if ok then return result == true end
    end
    if fw == 'qbx' then
        local ok, result = try('ox_inventory', 'CanCarryItem', source, name, count)
        return ok and result == true
    end
    local player = Hexa.GetPlayer(source)
    if not player then return false end
    if fw == 'esx' then
        if Hexa.IsWeapon(name) then return not (player.hasWeapon and player.hasWeapon(name)) end
        return not player.canCarryItem or player.canCarryItem(name, count) == true
    end
    local ok, result = try('qb-inventory', 'CanAddItem', source, name, count)
    return not ok or result == true   -- ancien qb-core : pas de vérification disponible
end

-- metadata : métadonnées de l'objet (numéro de série, munitions d'arme…).
function Hexa.AddItem(source, name, count, metadata)
    name, count = itemName(name), Hexa.Amount(count or 1)
    if not name or not count or count == 0 then return false end
    if hexaInventory() then
        -- hexa_inventory suit la signature qb-inventory sur QBCore : (source, nom, quantité, case, infos)
        local ok, result
        if isQB then ok, result = try('hexa_inventory', 'AddItem', source, name, count, nil, metadata)
        else ok, result = try('hexa_inventory', 'AddItem', source, name, count, metadata) end
        return ok and result == true
    end
    if fw == 'qbx' then
        local ok, result = try('ox_inventory', 'AddItem', source, name, count, metadata)
        return ok and result == true
    end
    local player = Hexa.GetPlayer(source)
    if not player then return false end
    if fw == 'esx' then
        if Hexa.IsWeapon(name) then
            if player.hasWeapon(name) then return false end
            player.addWeapon(name, metadata and tonumber(metadata.ammo) or 0)
            return true
        end
        if player.canCarryItem and not player.canCarryItem(name, count) then return false end
        player.addInventoryItem(name, count, metadata)
        return true
    end
    local ok, result = try('qb-inventory', 'AddItem', source, name, count, nil, metadata, Hexa.resource)
    if ok then return result == true end
    return player.Functions.AddItem(name, count, nil, metadata) == true
end

-- Retire seulement si le joueur en a assez.
function Hexa.RemoveItem(source, name, count)
    name, count = itemName(name), Hexa.Amount(count or 1)
    if not name or not count or count == 0 or Hexa.ItemCount(source, name) < count then return false end
    if hexaInventory() then
        local ok, result = try('hexa_inventory', 'RemoveItem', source, name, count)
        return ok and result == true
    end
    if fw == 'qbx' then
        local ok, result = try('ox_inventory', 'RemoveItem', source, name, count)
        return ok and result == true
    end
    local player = Hexa.GetPlayer(source)
    if not player then return false end
    if fw == 'esx' then
        if Hexa.IsWeapon(name) then player.removeWeapon(name); return true end
        player.removeInventoryItem(name, count)
        return true
    end
    local ok, result = try('qb-inventory', 'RemoveItem', source, name, count, nil, Hexa.resource)
    if ok then return result == true end
    return player.Functions.RemoveItem(name, count) == true
end

function Hexa.RegisterUsableItem(name, callback)
    name = itemName(name)
    local function use(source, item) callback(source, item) end
    if fw == 'esx' then core.RegisterUsableItem(name, use)
    elseif fw == 'qb' then core.Functions.CreateUseableItem(name, use)
    elseif fw == 'qbx' then try('qbx_core', 'CreateUseableItem', name, use) end
end

-- Permis -----------------------------------------------------------------------------------------------
-- ESX : esx_license (table user_licenses). QBCore / QBox : PlayerData.metadata.licences.
local function esxLicense(event, source, license)
    if GetResourceState('esx_license') ~= 'started' then return nil end
    return await(function(done) TriggerEvent(event, source, license, done) end, 3000)
end

function Hexa.HasLicense(source, license)
    if not license then return true end
    if isQB then return (Hexa.GetMeta(source, 'licences') or {})[license] == true end
    return esxLicense('esx_license:checkLicense', source, license) == true
end

local function setQBLicense(source, license, value)
    local licences = Hexa.Copy(Hexa.GetMeta(source, 'licences') or {})
    licences[license] = value
    return Hexa.SetMeta(source, 'licences', licences)
end

function Hexa.AddLicense(source, license)
    if type(license) ~= 'string' or not Hexa.GetPlayer(source) then return false end
    if isQB then return setQBLicense(source, license, true) end
    if Hexa.HasLicense(source, license) then return true end
    if GetResourceState('esx_license') ~= 'started' then return false end
    esxLicense('esx_license:addLicense', source, license)
    return Hexa.HasLicense(source, license)
end

function Hexa.RemoveLicense(source, license)
    if type(license) ~= 'string' or not Hexa.GetPlayer(source) then return false end
    if isQB then return setQBLicense(source, license, false) end
    if GetResourceState('esx_license') ~= 'started' then return false end
    esxLicense('esx_license:removeLicense', source, license)
    return not Hexa.HasLicense(source, license)
end

-- Base de données (oxmysql) ----------------------------------------------------------------------------
-- Fonctionne que la ressource inclue '@oxmysql/lib/MySQL.lua' ou non.
local function db(method, query, params)
    if MySQL and MySQL[method] then return MySQL[method].await(query, params or {}) end
    if GetResourceState('oxmysql') ~= 'started' then error('oxmysql n’est pas démarré') end
    local oxmysql, result = exports.oxmysql, promise.new()
    oxmysql[method](oxmysql, query, params or {}, function(value) result:resolve(value) end)
    return Citizen.Await(result)
end

-- Hexa.DB.query / single / scalar / insert / update(requête, paramètres) : attendent le résultat.
Hexa.DB = {}
for _, method in ipairs({ 'query', 'single', 'scalar', 'insert', 'update' }) do
    Hexa.DB[method] = function(query, params) return db(method, query, params) end
end

-- Crée les tables au démarrage (CREATE TABLE IF NOT EXISTS …). Hexa.DB.ready passe à true après.
Hexa.DB.ready = false
function Hexa.Schema(statements)
    CreateThread(function()
        for _ = 1, 100 do
            if GetResourceState('oxmysql') == 'started' then break end
            Wait(100)
        end
        local ok = true
        for _, statement in ipairs(type(statements) == 'table' and statements or { statements }) do
            local success, err = pcall(db, 'query', statement)
            if not success then ok = false; Hexa.Print('SQL : ' .. tostring(err), 'error') end
        end
        Hexa.DB.ready = ok
    end)
end

-- Véhicules --------------------------------------------------------------------------------------------
-- Propriétaire (identifiant du personnage) d'une plaque, ou nil. Lit owned_vehicles / player_vehicles.
function Hexa.VehicleOwner(plate)
    plate = Hexa.Plate(plate)
    if not plate then return nil end
    local query = fw == 'esx'
        and 'SELECT `owner` FROM `owned_vehicles` WHERE UPPER(TRIM(`plate`)) = ? LIMIT 1'
        or 'SELECT `citizenid` FROM `player_vehicles` WHERE UPPER(TRIM(`plate`)) = ? LIMIT 1'
    local ok, owner = pcall(db, 'scalar', query, { plate })
    if not ok then Hexa.Print('SQL : ' .. tostring(owner), 'error'); return nil end
    return owner
end

function Hexa.IsVehicleOwner(source, plate)
    local identifier = Hexa.Identifier(source)
    return identifier ~= nil and Hexa.VehicleOwner(plate) == identifier
end

-- Clés : délégué au futur hexa_keys. Contrat attendu :
--   exports.hexa_keys:GiveKeys(source, plate) -> true / false
--   exports.hexa_keys:RemoveKeys(source, plate) -> true / false
--   exports.hexa_keys:HasKeys(source, plate) -> true / false
local function keys(fn, source, plate)
    plate = Hexa.Plate(plate)
    if not plate then return false end
    if GetResourceState('hexa_keys') ~= 'started' then
        Hexa.Print(('%s ignoré : hexa_keys n’est pas démarré.'):format(fn), 'debug')
        return false
    end
    local ok, result = try('hexa_keys', fn, source, plate)
    return ok and result == true
end

function Hexa.GiveKeys(source, plate) return keys('GiveKeys', source, plate) end
function Hexa.RemoveKeys(source, plate) return keys('RemoveKeys', source, plate) end
function Hexa.HasKeys(source, plate) return keys('HasKeys', source, plate) end

-- Administration ---------------------------------------------------------------------------------------
-- Console (source 0) : toujours admin. Sinon permission ACE ou groupe du framework.
function Hexa.IsAdmin(source)
    source = tonumber(source)
    if source == 0 then return true end
    if not source then return false end
    local admin = Hexa.ServerConfig.Admin
    if admin.ace and IsPlayerAceAllowed(source, admin.ace) then return true end
    local player = Hexa.GetPlayer(source)
    if not player then return false end
    for _, group in ipairs(admin.groups or {}) do
        if fw == 'esx' and player.getGroup and player.getGroup() == group then return true end
        if fw == 'qb' and core.Functions.HasPermission and core.Functions.HasPermission(source, group) then return true end
        if fw == 'qbx' then
            local ok, has = try('qbx_core', 'HasPermission', source, group)
            if ok and has then return true end
        end
    end
    return false
end

-- Commande de chat. options : admin (réservée aux admins, journalisée), help (texte d'aide).
-- Hexa.Command('givecash', { admin = true, help = 'Donner de l’argent' }, function(source, args) ... end)
local commands = {}
function Hexa.Command(name, options, handler)
    options = options or {}
    commands[#commands + 1] = { name = name, help = options.help }
    RegisterCommand(name, function(source, args, raw)
        if options.admin and not Hexa.IsAdmin(source) then
            if source ~= 0 then Hexa.Notify(source, T('no_permission'), 'error') end
            return
        end
        if options.admin and source ~= 0 then Hexa.Log('admin', '`/' .. raw .. '`', source) end
        handler(source, args, raw)
    end, false)
end

-- Suggestions de chat pour chaque joueur qui se connecte (et ceux déjà là au démarrage).
local function suggest(target)
    for _, command in ipairs(commands) do
        if command.help then TriggerClientEvent('chat:addSuggestion', target, '/' .. command.name, command.help) end
    end
end
AddEventHandler('playerJoining', function() suggest(source) end)
CreateThread(function() Wait(1000); if #commands > 0 then suggest(-1) end end)

-- Logs Discord -----------------------------------------------------------------------------------------
-- Hexa.Log('money', 'Retrait de 500 $', source, { Distributeur = 'Legion Square' })
local function valid(url) return type(url) == 'string' and url:find('^https://') ~= nil end

-- Un seul salon Discord : Logs.webhook (ou, comme avant, Logs.default). Vide ou mal saisi : pas de Discord.
local function webhook()
    local logs = Hexa.ServerConfig.Logs
    if valid(logs.webhook) then return logs.webhook end
    if valid(logs.default) then return logs.default end
end

-- Copie dans la table hexa_logs (écrite par la ressource hexa_core), sauf Logs.database = false.
local function storeLog(category, message, source, fields, level)
    local entry = { resource = Hexa.resource, category = tostring(category), level = level or 'info',
        message = tostring(message):sub(1, 4000), fields = fields,
        labels = { player = T('player'), identifier = T('identifier') } }
    source = tonumber(source)
    if source and source > 0 then
        entry.source, entry.name, entry.identifier = source, Hexa.Name(source), Hexa.Identifier(source)
        entry.playerId, entry.charId = Hexa.PlayerId(source), Hexa.CharId(source)
    end
    TriggerEvent('hexa_core:server:log', entry)
end

-- Envoie le log à hexa_core, qui le range dans la base, le fichier du jour et Discord (regroupement des logs
-- identiques et limite par minute : voir config_server.lua → Logs). Renvoie true si un salon Discord est réglé.
function Hexa.Log(category, message, source, fields, level)
    storeLog(category, message, source, fields, level)
    return webhook() ~= nil
end

-- Connexion, déconnexion, métier -----------------------------------------------------------------------
-- QBox déclenche les mêmes événements que QBCore.
function Hexa.OnPlayerLoaded(callback)
    if fw == 'esx' then
        AddEventHandler('esx:playerLoaded', function(source) callback(tonumber(source)) end)
    elseif isQB then
        AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
            callback(tonumber(player and player.PlayerData and player.PlayerData.source))
        end)
    end
end

function Hexa.OnPlayerDropped(callback)
    AddEventHandler('playerDropped', function(reason) callback(tonumber(source), reason) end)
end

-- callback(source, nomDuMétier, grade)
function Hexa.OnJobChange(callback)
    if fw == 'esx' then
        AddEventHandler('esx:setJob', function(source, job) callback(tonumber(source), job and job.name, tonumber(job and job.grade) or 0) end)
    elseif isQB then
        AddEventHandler('QBCore:Server:OnJobUpdate', function(source, job)
            local grade = job and (type(job.grade) == 'table' and job.grade.level or job.grade)
            callback(tonumber(source), job and job.name, tonumber(grade) or 0)
        end)
    end
end

-- Notifications ----------------------------------------------------------------------------------------
-- kind : 'info', 'success', 'error' ou 'warning'. Affichage géré par @hexa_core/client.lua.
function Hexa.Notify(source, message, kind)
    TriggerClientEvent(Hexa.resource .. ':hexa:notify', source, message, kind or 'info')
end

-- Rappels client -> serveur ----------------------------------------------------------------------------
-- Hexa.Callback('deposit', function(source, data) ... return { ok = true } end, { lock = true, cooldown = 300 })
--   lock     : une seule demande verrouillée à la fois par joueur (anti double-clic / duplication)
--   cooldown : délai minimal (ms) entre deux appels de ce rappel par le même joueur
local callbacks, busy, lastCall = {}, {}, {}

function Hexa.Callback(name, handler, options)
    options = options or {}
    callbacks[name] = { handler = handler, lock = options.lock, cooldown = tonumber(options.cooldown) }
end

RegisterNetEvent(Hexa.resource .. ':hexa:request', function(id, name, data)
    local src = source
    if type(id) ~= 'number' or type(name) ~= 'string' then return end
    local function reply(result) TriggerClientEvent(Hexa.resource .. ':hexa:response', src, id, result) end

    local entry = callbacks[name]
    if not entry then return reply({ ok = false, error = 'unknown' }) end

    if entry.cooldown then
        local key, now = src .. ':' .. name, GetGameTimer()
        if lastCall[key] and now - lastCall[key] < entry.cooldown then return reply({ ok = false, retry = true }) end
        lastCall[key] = now
    end
    if entry.lock then
        if busy[src] then return reply({ ok = false, busy = true }) end
        busy[src] = true
    end

    local ok, result = pcall(entry.handler, src, type(data) == 'table' and data or {})
    if entry.lock then busy[src] = nil end
    if not ok then
        Hexa.Print(('Erreur dans le rappel « %s » : %s'):format(name, tostring(result)), 'error')
        result = { ok = false }
    elseif type(result) ~= 'table' then
        result = { ok = result ~= false, value = result }
    end
    reply(result)
end)

AddEventHandler('playerDropped', function()
    local src = source
    busy[src] = nil
    for key in pairs(lastCall) do
        if key:find('^' .. src .. ':') then lastCall[key] = nil end
    end
end)

-- Métiers, grades, embauche ----------------------------------------------------------------------------
-- Hexa.JobInfo('police') -> { name, label, grades = { { grade = 0, name, label, salary, boss }, … } } ou nil.
-- gang = true : un gang QBCore / QBox au lieu d'un métier.
local function gradeList(raw)
    local list = {}
    for key, value in pairs(type(raw) == 'table' and raw or {}) do
        local grade = tonumber(value.grade) or tonumber(key)
        if grade then
            list[#list + 1] = {
                grade = grade, name = value.name, label = value.label or value.name,
                salary = tonumber(value.salary or value.payment) or 0, boss = value.isboss == true or value.name == 'boss',
            }
        end
    end
    table.sort(list, function(a, b) return a.grade < b.grade end)
    return list
end

function Hexa.JobInfo(name, gang)
    if type(name) ~= 'string' then return nil end
    local job
    if fw == 'esx' then
        local jobs = core.GetJobs and core.GetJobs() or core.Jobs or {}
        job = jobs[name]
    elseif fw == 'qb' then
        job = ((core.Shared or {})[gang and 'Gangs' or 'Jobs'] or {})[name]
    elseif fw == 'qbx' then
        local ok, value = try('qbx_core', gang and 'GetGang' or 'GetJob', name)
        job = ok and value or nil
    end
    if type(job) ~= 'table' then return nil end
    return { name = name, label = job.label or name, grades = gradeList(job.grades) }
end

local function gradeExists(info, grade)
    for _, entry in ipairs(info.grades) do if entry.grade == grade then return entry end end
end

-- Change le métier d'un joueur connecté. Refusé si le métier ou le grade n'existe pas.
function Hexa.SetJob(source, job, grade)
    grade = math.floor(tonumber(grade) or 0)
    local info = Hexa.JobInfo(job)
    if not info or not gradeExists(info, grade) then return false end
    local player = Hexa.GetPlayer(source)
    if not player then return false end
    local ok
    if fw == 'esx' then ok = pcall(player.setJob, job, grade)
    else ok = pcall(player.Functions.SetJob, job, grade) end
    return ok
end

-- Même chose pour un personnage connecté ou non (identifiant ESX / citizenid).
function Hexa.SetJobOffline(identifier, job, grade)
    if type(identifier) ~= 'string' then return false end
    local source = Hexa.SourceOf(identifier)
    if source then return Hexa.SetJob(source, job, grade) end
    grade = math.floor(tonumber(grade) or 0)
    local info = Hexa.JobInfo(job)
    local entry = info and gradeExists(info, grade)
    if not entry then return false end
    if fw == 'qbx' then
        local okAdd, added = try('qbx_core', 'AddPlayerToJob', identifier, job, grade)
        if okAdd and added ~= false then
            local okPrimary, primary = try('qbx_core', 'SetPlayerPrimaryJob', identifier, job)
            if okPrimary and primary ~= false then return true end
        end
    end
    local ok, changed
    if fw == 'esx' then
        ok, changed = pcall(db, 'update', 'UPDATE `users` SET `job` = ?, `job_grade` = ? WHERE `identifier` = ?', { job, grade, identifier })
    else
        local data = json.encode({ name = job, label = info.label, payment = entry.salary, onduty = false, isboss = entry.boss,
            grade = { name = entry.label, level = grade } })
        ok, changed = pcall(db, 'update', 'UPDATE `players` SET `job` = ? WHERE `citizenid` = ?', { data, identifier })
    end
    if not ok then Hexa.Print('SQL : ' .. tostring(changed), 'error'); return false end
    return (tonumber(changed) or 0) > 0
end

-- Service : en service ou non. QBCore / QBox ont cette notion ; ESX non (avoir le métier = être en service).
function Hexa.OnDuty(source)
    local name, _, duty = Hexa.Job(source)
    return name ~= nil and duty == true
end

function Hexa.SetDuty(source, duty)
    local player = Hexa.GetPlayer(source)
    if not player then return false end
    duty = duty == true
    if fw == 'qb' then return pcall(player.Functions.SetJobDuty, duty) end
    if fw == 'qbx' then return (try('qbx_core', 'SetJobDuty', tonumber(source), duty)) end
    if not Hexa.__dutyWarned then Hexa.__dutyWarned = true; Hexa.Print(T('duty_unsupported'), 'warn') end
    return false
end

-- Change seulement le grade du métier actuel. Refusé si le grade n'existe pas.
function Hexa.SetGrade(source, grade)
    local job = Hexa.Job(source)
    if not job then return false end
    return Hexa.SetJob(source, job, grade)
end

-- Change le gang (QBCore / QBox) ou le job2 (ESX qui l'a). Refusé si le gang ou le grade n'existe pas.
function Hexa.SetGang(source, gang, grade)
    grade = math.floor(tonumber(grade) or 0)
    local info = Hexa.JobInfo(gang, true)
    if not info then
        if fw ~= 'esx' then return false end
        info = Hexa.JobInfo(gang)       -- job2 d'ESX : mêmes tables que les métiers
    end
    if not info or not gradeExists(info, grade) then return false end
    local player = Hexa.GetPlayer(source)
    if not player then return false end
    if fw == 'esx' then return type(player.setJob2) == 'function' and (pcall(player.setJob2, gang, grade)) or false end
    if fw == 'qb' then return (pcall(player.Functions.SetGang, gang, grade)) end
    local identifier = Hexa.Identifier(source)
    local ok, added = try('qbx_core', 'AddPlayerToGang', identifier, gang, grade)
    if not ok or added == false then return false end
    local okPrimary, primary = try('qbx_core', 'SetPlayerPrimaryGang', identifier, gang)
    return okPrimary and primary ~= false
end

-- Renvoie un personnage (connecté ou non) au chômage, grade 0.
function Hexa.FireJob(identifier)
    return Hexa.SetJobOffline(identifier, 'unemployed', 0)
end

-- Employés d'un métier, connectés ou non : { { identifier, name, grade, source (si connecté) }, … }
local function decode(text)
    if type(text) == 'table' then return text end
    local ok, value = pcall(json.decode, text or '')
    return ok and type(value) == 'table' and value or {}
end

function Hexa.JobMembers(job)
    if type(job) ~= 'string' then return {} end
    local members, byId = {}, {}
    local function add(identifier, name, grade)
        if not identifier or byId[identifier] then return end
        byId[identifier] = { identifier = identifier, name = name, grade = tonumber(grade) or 0 }
        members[#members + 1] = byId[identifier]
    end
    local ok, rows
    if fw == 'esx' then
        ok, rows = pcall(db, 'query', 'SELECT `identifier`, `firstname`, `lastname`, `job_grade` FROM `users` WHERE `job` = ?', { job })
        for _, row in ipairs(ok and rows or {}) do
            add(row.identifier, ('%s %s'):format(row.firstname or '', row.lastname or ''):match('^%s*(.-)%s*$'), row.job_grade)
        end
    elseif fw then
        if fw == 'qbx' then
            ok, rows = pcall(db, 'query', [[SELECT g.`citizenid`, g.`grade`, p.`charinfo` FROM `player_groups` g
                LEFT JOIN `players` p ON p.`citizenid` = g.`citizenid` WHERE g.`group` = ? AND g.`type` = 'job']], { job })
            for _, row in ipairs(ok and rows or {}) do
                local info = decode(row.charinfo)
                add(row.citizenid, ('%s %s'):format(info.firstname or '', info.lastname or ''):match('^%s*(.-)%s*$'), row.grade)
            end
        end
        if fw == 'qb' or not ok then
            ok, rows = pcall(db, 'query', [[SELECT `citizenid`, `charinfo`, `job` FROM `players`
                WHERE JSON_UNQUOTE(JSON_EXTRACT(`job`, '$.name')) = ?]], { job })
            for _, row in ipairs(ok and rows or {}) do
                local info, data = decode(row.charinfo), decode(row.job)
                add(row.citizenid, ('%s %s'):format(info.firstname or '', info.lastname or ''):match('^%s*(.-)%s*$'),
                    type(data.grade) == 'table' and data.grade.level or data.grade)
            end
        end
    end
    -- Les joueurs connectés font foi (base pas encore sauvegardée).
    for _, id in ipairs(GetPlayers()) do
        local source = tonumber(id)
        local name, grade = Hexa.Job(source)
        local identifier = Hexa.Identifier(source)
        if identifier then
            if name == job then
                add(identifier, Hexa.Name(source), grade)
                byId[identifier].grade, byId[identifier].source, byId[identifier].name = grade, source, Hexa.Name(source)
            elseif byId[identifier] then
                byId[identifier].left = true      -- a changé de métier depuis la dernière sauvegarde
            end
        end
    end
    local list = {}
    for _, member in ipairs(members) do if not member.left then list[#list + 1] = member end end
    table.sort(list, function(a, b) return a.grade > b.grade end)
    return list
end

-- Comptes d'entreprise ---------------------------------------------------------------------------------
-- Ordre : hexa_banking > esx_addonaccount (ESX) > qb-banking > qb-management > Renewed-Banking.
local function sharedAccount(job)
    if GetResourceState('esx_addonaccount') ~= 'started' then return nil end
    local account
    TriggerEvent('esx_addonaccount:getSharedAccount', 'society_' .. job, function(value) account = value end)
    return account
end

local function cleanJob(job) return type(job) == 'string' and job:match('^[%w_%-]+$') and job or nil end

-- Solde du compte d'entreprise, ou nil si aucun système de comptes n'est disponible.
function Hexa.SocietyBalance(job)
    job = cleanJob(job)
    if not job then return nil end
    local ok, value = try('hexa_banking', 'GetSocietyBalance', job)
    if ok and tonumber(value) then return tonumber(value) end
    local account = sharedAccount(job)
    if account then return tonumber(account.money) or 0 end
    ok, value = try('qb-banking', 'GetAccountBalance', job)
    if ok and tonumber(value) then return tonumber(value) end
    ok, value = try('qb-management', 'GetAccount', job)
    if ok and tonumber(value) then return tonumber(value) end
    ok, value = try('Renewed-Banking', 'getAccountMoney', job)
    if ok and tonumber(value) then return tonumber(value) end
    return nil
end

local function societyConfig() return Hexa.ServerConfig.Society or {} end

-- Auteur d'un mouvement : un joueur connecté (numéro) ou un texte ; sinon la ressource appelante.
local function authorOf(author)
    if tonumber(author) then return Hexa.Identifier(tonumber(author)) or ('source:' .. tonumber(author)) end
    if type(author) == 'string' and author ~= '' then return author:sub(1, 80) end
    return 'resource:' .. (GetInvokingResource and GetInvokingResource() or Hexa.resource or '?')
end

-- Journal des mouvements, dans la base seulement (table hexa_society_log, créée par hexa_core).
local function journal(job, amount, reason, author)
    if societyConfig().journal == false then return end
    local ok, err = pcall(db, 'insert', 'INSERT INTO `hexa_society_log` (`job`, `amount`, `balance`, `reason`, `author`) VALUES (?, ?, ?, ?, ?)',
        { job, amount, Hexa.SocietyBalance(job), reason and tostring(reason):sub(1, 120) or nil, authorOf(author) })
    if not ok then Hexa.Debug('Journal entreprise : ' .. tostring(err)) end
end

-- Solde minimal autorisé (0, ou négatif si `maxOverdraft` est réglé). Les systèmes qui décident seuls (hexa_banking)
-- gardent leur propre règle.
local function floorBalance() return -math.max(0, math.floor(tonumber(societyConfig().maxOverdraft) or 0)) end

local function moveSociety(job, amount, reason, add, author)
    job, amount = cleanJob(job), Hexa.Amount(amount)
    if not job or not amount or amount == 0 then return false end
    local done = false
    if GetResourceState('hexa_banking') == 'started' then
        local ok, result = try('hexa_banking', add and 'AddSocietyMoney' or 'RemoveSocietyMoney', job, amount, reason)
        done = ok and result == true
    else
        local account = sharedAccount(job)
        if account then
            if add then account.addMoney(amount); done = true
            elseif (tonumber(account.money) or 0) - amount >= floorBalance() then account.removeMoney(amount); done = true end
        elseif add or (Hexa.SocietyBalance(job) or 0) - amount >= floorBalance() then
            -- Ces systèmes ne refusent pas toujours un solde insuffisant : on vérifie avant.
            for _, entry in ipairs({ { 'qb-banking', 'AddMoney', 'RemoveMoney' }, { 'qb-management', 'AddMoney', 'RemoveMoney' },
                { 'Renewed-Banking', 'addAccountMoney', 'removeAccountMoney' } }) do
                if GetResourceState(entry[1]) == 'started' then
                    local ok, result = try(entry[1], add and entry[2] or entry[3], job, amount, reason)
                    done = ok and result ~= false
                    break
                end
            end
        end
    end
    if done then journal(job, add and amount or -amount, reason, author) end
    return done
end

-- `author` (facultatif) : numéro du joueur ou texte, écrit dans le journal.
function Hexa.AddSocietyMoney(job, amount, reason, author) return moveSociety(job, amount, reason, true, author) end
function Hexa.RemoveSocietyMoney(job, amount, reason, author) return moveSociety(job, amount, reason, false, author) end

-- Ce joueur a-t-il le droit de retirer de l'argent du compte `job` ? Il doit en être membre (métier ou gang) avec
-- le grade « patron » ou, si Society.withdrawGrade est un nombre, au moins ce grade.
function Hexa.SocietyCanWithdraw(source, job)
    job = cleanJob(job)
    if not job then return false end
    local rule = societyConfig().withdrawGrade
    local function allowed(grade, gang)
        if type(rule) == 'number' then return grade >= rule end
        local info = Hexa.JobInfo(job, gang)
        local entry = info and gradeExists(info, grade)
        return entry ~= nil and entry.boss == true
    end
    local name, grade = Hexa.Job(source)
    if name == job and allowed(grade, false) then return true end
    local gang, gangGrade = Hexa.Gang(source)
    return gang == job and allowed(gangGrade, true)
end

-- Retrait demandé par un joueur : le grade est vérifié ici, pas par le script appelant.
function Hexa.SocietyWithdraw(source, job, amount, reason)
    if not Hexa.SocietyCanWithdraw(source, job) then return false end
    return moveSociety(job, amount, reason, false, tonumber(source))
end

-- Virement d'un compte à l'autre ; si le dépôt échoue, le retrait est annulé.
function Hexa.SocietyTransfer(from, to, amount, reason, author)
    from, to = cleanJob(from), cleanJob(to)
    if not from or not to or from == to then return false end
    if not moveSociety(from, amount, reason, false, author) then return false end
    if moveSociety(to, amount, reason, true, author) then return true end
    moveSociety(from, amount, reason, true, 'refund')
    return false
end

-- Derniers mouvements d'un compte (le plus récent d'abord) : { { amount, balance, reason, author, at }, … }
function Hexa.SocietyHistory(job, limit)
    job = cleanJob(job)
    if not job then return {} end
    limit = math.max(1, math.min(200, math.floor(tonumber(limit) or 50)))
    local ok, rows = pcall(db, 'query', 'SELECT `amount`, `balance`, `reason`, `author`, UNIX_TIMESTAMP(`created_at`) AS `at` FROM `hexa_society_log` WHERE `job` = ? ORDER BY `id` DESC LIMIT ' .. limit, { job })
    return ok and rows or {}
end

-- Crée le compte d'une entreprise : possible seulement avec hexa_banking (il crée le compte à la demande).
function Hexa.CreateSociety(job)
    job = cleanJob(job)
    if not job then return false end
    if GetResourceState('hexa_banking') == 'started' then
        local ok, value = try('hexa_banking', 'GetSocietyBalance', job)
        return ok and value ~= nil
    end
    Hexa.Print(T('society_create', job), 'warn')
    return false
end

-- Registre d'objets ------------------------------------------------------------------------------------
-- Hexa.Item('bread') -> { name, label, weight, image, usable, unique, stackable, limit, category, weapon, rare,
-- description } ou nil. Une seule source : l'inventaire qui tourne (ox_inventory, sinon la liste du framework,
-- qui est celle de hexa_inventory quand celui-ci tourne). Côté serveur seulement.
local function imagePath(name, file)
    file = file or (name .. '.png')
    if GetResourceState('hexa_inventory') == 'started' then return 'nui://hexa_inventory/web/images/' .. file end
    if GetResourceState('ox_inventory') == 'started' then return 'nui://ox_inventory/web/images/' .. file end
    if GetResourceState('qb-inventory') == 'started' then return 'nui://qb-inventory/html/images/' .. file end
    return nil
end

local function usable(name)
    if fw == 'esx' then
        local list = core.GetUsableItems and core.GetUsableItems() or core.UsableItemsCallbacks or {}
        return list[name] ~= nil
    elseif fw == 'qb' then
        return core.Functions.CanUseItem and core.Functions.CanUseItem(name) ~= nil or false
    elseif fw == 'qbx' then
        local ok, value = try('qbx_core', 'CanUseItem', name)
        return ok and value ~= nil and value ~= false
    end
    return false
end

local function itemEntry(name, raw)
    if type(raw) ~= 'table' then return nil end
    local client = type(raw.client) == 'table' and raw.client or {}
    local image = raw.image or client.image
    if type(image) == 'string' and image:find('^nui://') then image = image else image = imagePath(name, image) end
    local unique = raw.unique == true or raw.stack == false
    return {
        name = name, label = raw.label or name, weight = tonumber(raw.weight) or 0, image = image,
        usable = raw.useable == true or raw.usable == true or usable(name),
        unique = unique, stackable = not unique, limit = tonumber(raw.limit),
        category = type(raw.category) == 'string' and raw.category or nil,
        weapon = Hexa.IsWeapon(name) or raw.type == 'weapon', rare = raw.rare == true,
        description = raw.description,
    }
end

local function rawItems()
    if GetResourceState('ox_inventory') == 'started' then
        local ok, items = try('ox_inventory', 'Items')
        if ok and type(items) == 'table' and next(items) then return items end
    end
    if fw == 'esx' then
        return core.GetItems and core.GetItems() or core.Items or {}
    elseif fw == 'qb' then
        return (core.Shared or {}).Items or {}
    end
    return {}
end

function Hexa.Item(name)
    name = itemName(name)
    if not name then return nil end
    local raw = rawItems()[name]
    if not raw and fw == 'esx' and Hexa.IsWeapon(name) then raw = { label = Hexa.ItemLabel(name), weight = 0, unique = true } end
    return itemEntry(name, raw)
end

-- Tous les objets connus : { [nom] = { … } }
function Hexa.Items()
    local list = {}
    for name, raw in pairs(rawItems()) do list[name] = itemEntry(name, raw) end
    return list
end

-- Déclare un objet depuis une ressource Hexa (hexa_documents : « carte d'identité »…).
-- definition : { label, weight (grammes), unique, image, description }. Renvoie true si l'inventaire l'a pris.
-- hexa_inventory : officiel. QBCore : QBCore.Functions.AddItem. Autres : refusé avec un message en console.
function Hexa.RegisterItem(name, definition)
    name = itemName(name)
    if not name or type(definition) ~= 'table' then return false end
    local label = type(definition.label) == 'string' and definition.label or name
    local weight = math.max(0, math.floor(tonumber(definition.weight) or 0))
    if hexaInventory() then
        local entry = { label = label, weight = weight, unique = definition.unique == true, image = definition.image, description = definition.description }
        local ok, result = try('hexa_inventory', 'RegisterItems', { [name] = entry })
        return ok and result == true
    end
    if fw == 'qb' and core.Functions and core.Functions.AddItem then
        local ok, success = pcall(core.Functions.AddItem, name, {
            name = name, label = label, weight = weight, type = 'item', image = definition.image or (name .. '.png'),
            unique = definition.unique == true, useable = true, shouldClose = true, description = definition.description or '',
        })
        return ok and success ~= false
    end
    Hexa.Print(T('register_unsupported', name), 'warn')
    return false
end

-- Instances (routing buckets) --------------------------------------------------------------------------
-- Attribuées par la ressource hexa_core : deux ressources n'utilisent jamais le même numéro par erreur.
-- Hexa.SetInstance(source)                 -> seul dans une instance privée
-- Hexa.SetInstance(source, 'appart_12')    -> instance partagée par nom (tous ceux qui y entrent se voient)
-- options.population = true : garder les PNJ et la circulation (désactivés par défaut).
function Hexa.SetInstance(source, name, options)
    local ok, bucket = try('hexa_core', 'SetInstance', tonumber(source), name, options)
    return ok and bucket or nil
end

function Hexa.LeaveInstance(source)
    local ok, result = try('hexa_core', 'LeaveInstance', tonumber(source))
    return ok and result == true
end

-- Nom et numéro de l'instance du joueur, ou nil s'il est dans le monde normal.
function Hexa.GetInstance(source)
    local ok, name, bucket = try('hexa_core', 'GetInstance', tonumber(source))
    if not ok then return nil end
    return name, bucket
end
