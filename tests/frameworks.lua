-- Simulations ESX Legacy, QBCore et QBox (serveur et client) pour tester hexa_core.
USABLE, CLIENT_DATA = {}, { job = { name = 'police', grade = { level = 2 }, label = 'LSPD', onduty = true }, metadata = {} }

function NewPlayer(src, opts)
    opts = opts or {}
    local p = { name = 'Joueur ' .. src, identifier = opts.identifier or ('char:' .. src), charName = opts.charName or ('Perso ' .. src),
        job = opts.job, grade = opts.grade, onduty = opts.onduty, coords = opts.coords or vector3(), health = opts.health,
        accounts = { money = opts.cash or 0, bank = opts.bank or 0 }, items = opts.items or {}, weapons = opts.weapons or {},
        meta = opts.meta or {}, group = opts.group or 'user', licenses = opts.licenses or {}, license = opts.license }
    local first, last = p.charName:match('^(%S+)%s*(.*)$')
    p.first, p.last, p.birthdate, p.sex = first, last, opts.birthdate, opts.sex
    p.money = { cash = p.accounts.money, bank = p.accounts.bank }
    p.data = { source = src, citizenid = p.identifier, charinfo = { firstname = first, lastname = last, birthdate = opts.birthdate, gender = opts.sex == 'f' and 1 or opts.sex == 'm' and 0 or nil },
        job = { name = p.job, grade = { level = p.grade or 0 }, onduty = p.onduty ~= false }, money = p.money, metadata = p.meta }
    p.meta.licences = p.meta.licences or p.licenses
    p.data.gang = opts.gang      -- QBCore / QBox : { name, label, grade = { level } }
    p.job2 = opts.job2           -- ESX modifié : { name, label, grade }
    PLAYERS[src] = p
    return p
end

function Cash(src) local p = PLAYERS[src]; return FRAMEWORK == 'esx' and p.accounts.money or p.money.cash end
function Bank(src) local p = PLAYERS[src]; return FRAMEWORK == 'esx' and p.accounts.bank or p.money.bank end
function Items(src, name) return PLAYERS[src].items[name] or 0 end

local function qbPlayer(src)
    local p = PLAYERS[tonumber(src)]; if not p then return nil end
    return { PlayerData = p.data, Functions = {
        AddMoney = function(account, amount) p.money[account] = (p.money[account] or 0) + amount; return true end,
        RemoveMoney = function(account, amount)
            if (p.money[account] or 0) < amount then return false end
            p.money[account] = p.money[account] - amount; return true
        end,
        GetItemByName = function(name) local n = p.items[name]; return n and n > 0 and { name = name, amount = n } or nil end,
        AddItem = function(name, count) p.items[name] = (p.items[name] or 0) + count; return true end,
        RemoveItem = function(name, count) p.items[name] = (p.items[name] or 0) - count; return true end,
        SetMetaData = function(key, value) p.meta[key] = value end,
        SetJob = function(job, grade) p.job, p.grade = job, grade; p.data.job = { name = job, grade = { level = grade } }; return true end,
        SetJobDuty = function(duty) p.data.job.onduty = duty end,
        SetGang = function(gang, grade) p.data.gang = { name = gang, label = gang, grade = { level = grade } }; return true end,
    } }
end
local function byCitizen(cid) for src, p in pairs(PLAYERS) do if p.identifier == cid then return qbPlayer(src) end end end

if FRAMEWORK == 'esx' then
    RESOURCES.es_extended = 'started'
    local function xPlayer(src)
        local p = PLAYERS[src]; if not p then return nil end
        return {
            source = src, identifier = p.identifier, job = { name = p.job, grade = p.grade or 0 },
            getName = function() return p.charName end,
            get = function(key) return ({ firstName = p.first, lastName = p.last, dateofbirth = p.birthdate, sex = p.sex })[key] end,
            getGroup = function() return p.group end,
            getAccount = function(name) return { name = name, money = p.accounts[name] or 0 } end,
            addAccountMoney = function(name, amount) p.accounts[name] = (p.accounts[name] or 0) + amount end,
            removeAccountMoney = function(name, amount) p.accounts[name] = (p.accounts[name] or 0) - amount end,
            getInventoryItem = function(name) return { name = name, count = p.items[name] or 0 } end,
            canCarryItem = function(name, count) return (p.items[name] or 0) + count <= 50 end,
            addInventoryItem = function(name, count) p.items[name] = (p.items[name] or 0) + count end,
            removeInventoryItem = function(name, count) p.items[name] = (p.items[name] or 0) - count end,
            hasWeapon = function(name) return p.weapons[name] ~= nil end,
            addWeapon = function(name, ammo) p.weapons[name] = ammo end,
            removeWeapon = function(name) p.weapons[name] = nil end,
            job2 = p.job2,
            setJob = function(job, grade) p.job, p.grade = job, grade end,
            setJob2 = function(job, grade) p.job2 = { name = job, label = job, grade = grade } end,
            getMeta = function(key) return p.meta[key] end,
            setMeta = function(key, value) p.meta[key] = value end,
        }
    end
    ESX = {
        GetPlayerFromId = function(src) return xPlayer(tonumber(src)) end,
        GetPlayerFromIdentifier = function(id) for src, p in pairs(PLAYERS) do if p.identifier == id then return xPlayer(src) end end end,
        RegisterUsableItem = function(name, fn) USABLE[name] = fn end,
        IsPlayerLoaded = function() return CLIENT_LOADED == true end,
        GetPlayerData = function() return { job = { name = 'police', grade = 2, label = 'LSPD' } } end,
        GetItemLabel = function(name) return ({ bread = 'Pain' })[name] end,
        GetWeaponLabel = function(name) return ({ WEAPON_PISTOL = 'Pistolet' })[name] end,
    }
    RESOURCE_EXPORTS.es_extended = { getSharedObject = function() return ESX end }

    -- esx_license et esx_status (événements serveur avec callback)
    function StartEsxAddons()
        RESOURCES.esx_license, RESOURCES.esx_status = 'started', 'started'
        AddEventHandler('esx_license:checkLicense', function(src, kind, cb) cb(PLAYERS[src].licenses[kind] == true) end)
        AddEventHandler('esx_license:addLicense', function(src, kind, cb) PLAYERS[src].licenses[kind] = true; if cb then cb() end end)
        AddEventHandler('esx_license:removeLicense', function(src, kind, cb) PLAYERS[src].licenses[kind] = nil; if cb then cb() end end)
        AddEventHandler('esx_status:getStatus', function(src, name, cb) cb({ name = name, val = PLAYERS[src].meta[name] and PLAYERS[src].meta[name] * 10000 }) end)
    end
elseif FRAMEWORK == 'qb' then
    RESOURCES['qb-core'] = 'started'
    QBCore = {
        Functions = {
            GetPlayer = qbPlayer, GetPlayerByCitizenId = byCitizen,
            CreateUseableItem = function(name, fn) USABLE[name] = fn end,
            HasPermission = function(src, group) return PLAYERS[src].group == group end,
            GetPlayerData = function() return CLIENT_DATA end,
        },
        Shared = { Items = { bread = { label = 'Pain' }, weapon_pistol = { label = 'Pistolet' } } },
    }
    RESOURCE_EXPORTS['qb-core'] = { GetCoreObject = function() return QBCore end }
elseif FRAMEWORK == 'qbx' then
    RESOURCES.qbx_core = 'started'
    RESOURCES['qb-core'] = 'started'   -- QBox se présente aussi comme qb-core
    RESOURCES.ox_inventory = 'started'
    RESOURCE_EXPORTS.qbx_core = {
        GetPlayer = qbPlayer, GetPlayerByCitizenId = byCitizen,
        CreateUseableItem = function(name, fn) USABLE[name] = fn end,
        HasPermission = function(src, group) return PLAYERS[src].group == group end,
        GetPlayerData = function() return CLIENT_DATA end,
    }
    RESOURCE_EXPORTS['qb-core'] = { GetCoreObject = function() error('ne doit pas être appelé sous QBox') end }
    local labels = { bread = { label = 'Pain' }, WEAPON_PISTOL = { label = 'Pistolet' } }
    RESOURCE_EXPORTS.ox_inventory = {
        Items = function(name) return labels[name] end,
        GetItemCount = function(src, name) return PLAYERS[src].items[name] or 0 end,
        CanCarryItem = function(src, name, count) return (PLAYERS[src].items[name] or 0) + count <= 50 end,
        AddItem = function(src, name, count, meta)
            if (PLAYERS[src].items[name] or 0) + count > 50 then return false, 'inventory_full' end
            PLAYERS[src].items[name] = (PLAYERS[src].items[name] or 0) + count; LAST_META = meta; return true
        end,
        RemoveItem = function(src, name, count) PLAYERS[src].items[name] = PLAYERS[src].items[name] - count; return true end,
    }
end

-- Métiers et gangs, au format de chaque framework ------------------------------------------------------
JOB_DATA = {
    police = { label = 'LSPD', grades = { { 0, 'recruit', 'Recrue', 100 }, { 1, 'officer', 'Agent', 200 }, { 2, 'boss', 'Chef', 500, true } } },
    unemployed = { label = 'Sans emploi', grades = { { 0, 'unemployed', 'Sans emploi', 0 } } },
}
GANG_DATA = { ballas = { label = 'Ballas', grades = { { 0, 'recruit', 'Recrue', 0 }, { 1, 'boss', 'Chef', 0, true } } } }
local function frameworkJobs(data, style)
    local out = {}
    for name, job in pairs(data) do
        local grades = {}
        for _, g in ipairs(job.grades) do
            local entry = style == 'esx' and { grade = g[1], name = g[2], label = g[3], salary = g[4] }
                or { name = g[3], payment = g[4], isboss = g[5] or nil }
            grades[style == 'qbx' and g[1] or tostring(g[1])] = entry
        end
        out[name] = { name = name, label = job.label, grades = grades }
    end
    return out
end
if FRAMEWORK == 'esx' then
    ESX.Jobs = frameworkJobs(JOB_DATA, 'esx')
    ESX.GetJobs = function() return ESX.Jobs end
    ESX.GetUsableItems = function() return USABLE end
    ESX.Items = { bread = { label = 'Pain', weight = 1 }, phone = { label = 'Téléphone', weight = 2, rare = false } }
    ESX.GetItems = function() return ESX.Items end
elseif FRAMEWORK == 'qb' then
    QBCore.Shared.Jobs = frameworkJobs(JOB_DATA, 'qb')
    QBCore.Shared.Gangs = frameworkJobs(GANG_DATA, 'qb')
    QBCore.Functions.CanUseItem = function(name) return USABLE[name] end
    QBCore.Shared.Items.bread = { name = 'bread', label = 'Pain', weight = 100, image = 'bread.png', useable = false, unique = false, description = 'Du pain' }
    QBCore.Shared.Items.phone = { name = 'phone', label = 'Téléphone', weight = 700, image = 'phone.png', useable = true, unique = true }
elseif FRAMEWORK == 'qbx' then
    local jobs, gangs = frameworkJobs(JOB_DATA, 'qbx'), frameworkJobs(GANG_DATA, 'qbx')
    local q = RESOURCE_EXPORTS.qbx_core
    q.GetJob = function(name) return jobs[name] end
    q.GetGang = function(name) return gangs[name] end
    q.CanUseItem = function(name) return USABLE[name] end
    QBX_GROUPS = {}
    q.AddPlayerToJob = function(cid, job, grade) QBX_GROUPS[cid] = { job = job, grade = grade }; return true end
    q.SetPlayerPrimaryJob = function(cid, job) QBX_GROUPS[cid].primary = job; return true end
    q.SetJobDuty = function(src, duty) PLAYERS[src].data.job.onduty = duty; return true end
    q.AddPlayerToGang = function(cid, gang, grade) QBX_GROUPS[cid] = QBX_GROUPS[cid] or {}; QBX_GROUPS[cid].gang, QBX_GROUPS[cid].gangGrade = gang, grade; return true end
    q.SetPlayerPrimaryGang = function(cid, gang) QBX_GROUPS[cid].primaryGang = gang; return true end
    local items = { bread = { label = 'Pain', weight = 100 }, phone = { label = 'Téléphone', weight = 700, stack = false, client = { image = 'phone_x.png' } } }
    local base = RESOURCE_EXPORTS.ox_inventory.Items
    RESOURCE_EXPORTS.ox_inventory.Items = function(name) if name == nil then return items end return items[name] or base(name) end
end
