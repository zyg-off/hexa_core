-- hexa_core : fondation commune de l'écosystème Hexa Studio.
--
-- Ce fichier s'exécute DANS la ressource qui l'inclut (comme ox_lib) :
--     shared_script '@hexa_core/shared.lua'
-- Chaque ressource a donc son propre `Hexa`, sans appel d'export à chaque utilisation.
if Hexa and Hexa.__shared then return end

Hexa = Hexa or {}
Hexa.__shared = true
Hexa.version = '1.0.0-beta.1'
-- Niveau d'API : monte à chaque fonction ajoutée, ne redescend jamais (on ne retire rien).
-- Hexa.RequireVersion('1.4.0') (sans « -beta ») se compare à ce niveau ; Hexa.RequireVersion('1.0.0-beta.2') à la version.
Hexa.apiLevel = '1.4.0'
Hexa.resource = GetCurrentResourceName()
Hexa.isServer = IsDuplicityVersion()

-- Réglages ---------------------------------------------------------------------------------------------
local defaults = {
    Framework = 'auto', ESXResource = 'es_extended', QBResource = 'qb-core', QBXResource = 'qbx_core',
    Locale = 'fr',
    Accounts = {
        esx = { cash = 'money', bank = 'bank' },
        qb = { cash = 'cash', bank = 'bank' },
        qbx = { cash = 'cash', bank = 'bank' },
    },
    PaymentOrder = { 'cash', 'bank' },
    Debug = false,
    Ids = { OnDelete = 'keep' },
}

-- Lit un fichier de config de hexa_core et renvoie la table globale `name` qu'il définit.
function Hexa.__readConfig(file, name)
    local source = LoadResourceFile('hexa_core', file)
    local env = setmetatable({}, { __index = _G })
    local chunk = source and load(source, '@hexa_core/' .. file, 't', env)
    if chunk then pcall(chunk) end
    return type(env[name]) == 'table' and env[name] or {}
end

Hexa.Config = Hexa.__readConfig('config.lua', 'HexaConfig')
for key, value in pairs(defaults) do
    if Hexa.Config[key] == nil then Hexa.Config[key] = value end
end

-- Console ----------------------------------------------------------------------------------------------
local colors = { info = '^2', warn = '^3', error = '^1', debug = '^5' }

-- Mode debug : Debug = true dans hexa_core/config.lua (toutes les ressources), ou par ressource
-- dans server.cfg :   setr hexa_debug "hexa_shops,hexa_police"   (ou "all").
function Hexa.IsDebug()
    if Hexa.Config.Debug then return true end
    local ok, list = pcall(GetConvar, 'hexa_debug', '')
    if not ok or type(list) ~= 'string' or list == '' then return false end
    if list == 'all' or list == 'true' then return true end
    for name in list:gmatch('[^,%s]+') do
        if name == Hexa.resource then return true end
    end
    return false
end

-- Hexa.Debug('Achat', item, count) : affiché seulement en mode debug pour cette ressource.
function Hexa.Debug(...)
    if not Hexa.IsDebug() then return end
    local parts = {}
    for i = 1, select('#', ...) do
        local value = select(i, ...)
        parts[i] = type(value) == 'table' and json.encode(value) or tostring(value)
    end
    Hexa.Print(table.concat(parts, ' '), 'debug')
end

function Hexa.Print(message, level)
    level = level or 'info'
    if level == 'debug' and not Hexa.IsDebug() then return end
    print(('%s[%s] %s^0'):format(colors[level] or '', Hexa.resource, tostring(message)))
end

-- Langues ----------------------------------------------------------------------------------------------
-- local T = Hexa.Locale({
--     fr = { paid = 'Payé : %s.' },
--     en = { paid = 'Paid: %s.' },
-- })
-- T('paid', '50 $')   -- langue de HexaConfig.Locale, sinon français, sinon la clé.
function Hexa.Locale(tables)
    local lang, fallback = tables[Hexa.Config.Locale] or {}, tables.fr or {}
    return function(key, ...)
        local value = lang[key] or fallback[key] or key
        if select('#', ...) > 0 then return value:format(...) end
        return value
    end
end

local T = Hexa.Locale({
    fr = {
        no_framework = 'Aucun framework compatible (qbx_core / es_extended / qb-core) n’est démarré.',
        forced_missing = 'Framework « %s » demandé mais non démarré.',
        too_old = 'Cette ressource demande hexa_core %s ou plus récent (installé : %s). Mettez hexa_core à jour.',
    },
    en = {
        no_framework = 'No compatible framework (qbx_core / es_extended / qb-core) is started.',
        forced_missing = 'Framework "%s" requested but not started.',
        too_old = 'This resource needs hexa_core %s or newer (installed: %s). Please update hexa_core.',
    },
})
Hexa.__T = T

-- Framework --------------------------------------------------------------------------------------------
-- Hexa.framework : 'esx', 'qb', 'qbx' ou nil. Hexa.core : objet ESX ou QBCore (nil pour QBox : exports).
-- QBox passe en premier : il peut aussi se présenter comme qb-core.
local function detect()
    local cfg, wanted = Hexa.Config, Hexa.Config.Framework
    if (wanted == 'qbx' or wanted == 'auto') and GetResourceState(cfg.QBXResource) == 'started' then
        return 'qbx', nil
    end
    if (wanted == 'esx' or wanted == 'auto') and GetResourceState(cfg.ESXResource) == 'started' then
        return 'esx', exports[cfg.ESXResource]:getSharedObject()
    end
    if (wanted == 'qb' or wanted == 'auto') and GetResourceState(cfg.QBResource) == 'started' then
        return 'qb', exports[cfg.QBResource]:GetCoreObject()
    end
    if wanted ~= 'auto' then Hexa.Print(T('forced_missing', wanted), 'error') end
    Hexa.Print(T('no_framework'), 'error')
    return nil, nil
end
Hexa.framework, Hexa.core = detect()
Hexa.isQB = Hexa.framework == 'qb' or Hexa.framework == 'qbx'   -- QBCore et QBox partagent PlayerData

-- Version ----------------------------------------------------------------------------------------------
-- '1.10.0' > '1.9.2' ; '1.0.0-beta.10' > '1.0.0-beta.9' ; '1.0.0' > '1.0.0-beta.9'.
local function parseVersion(text)
    text = tostring(text or '')
    local core, pre = text:match('^[vV]?([%d%.]*)%-?(.*)$')
    local numbers = {}
    for n in (core or ''):gmatch('%d+') do numbers[#numbers + 1] = tonumber(n) end
    local tags = {}
    for tag in (pre or ''):gmatch('[^%.%-]+') do tags[#tags + 1] = tonumber(tag) or tag end
    return numbers, tags
end

function Hexa.VersionAtLeast(current, wanted)
    local a, pa = parseVersion(current)
    local b, pb = parseVersion(wanted)
    for i = 1, math.max(#a, #b, 3) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    if #pa == 0 or #pb == 0 then return #pa == 0 end   -- sans « -beta » = plus récent qu'avec
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i], pb[i]
        if x == nil then return false end              -- 'beta' < 'beta.1'
        if y == nil then return true end
        if x ~= y then
            if type(x) == type(y) then return x > y end
            return type(x) == 'string'                 -- un nombre passe avant un mot : 'beta.1' < 'beta.rc'
        end
    end
    return true
end

-- En tête d'une ressource : Hexa.RequireVersion('1.2.0'). Renvoie false (et l'affiche) si le core est trop vieux.
function Hexa.RequireVersion(wanted)
    local pinned = tostring(wanted):find('-', 1, true) ~= nil   -- « 1.0.0-beta.2 » vise la version, « 1.4.0 » le niveau d'API
    local installed = pinned and Hexa.version or Hexa.apiLevel
    if Hexa.VersionAtLeast(installed, wanted) then return true end
    Hexa.Print(T('too_old', wanted, Hexa.version), 'error')
    return false
end

-- Outils -----------------------------------------------------------------------------------------------

-- 12500 -> « 12 500 $ »
function Hexa.Money(amount, symbol)
    local value = tostring(math.floor(tonumber(amount) or 0))
    local negative = value:sub(1, 1) == '-'
    if negative then value = value:sub(2) end
    value = value:reverse():gsub('(%d%d%d)', '%1 '):reverse():gsub('^ ', '')
    return (negative and '-' or '') .. value .. ' ' .. (symbol or '$')
end

-- Montant envoyé par un client : entier ≥ 0 et ≤ max. Sinon nil.
function Hexa.Amount(value, max)
    value = tonumber(value)
    if not value or value ~= value or value < 0 or value ~= math.floor(value) or value == math.huge then return nil end
    if max and value > max then return nil end
    return math.floor(value)
end

-- Texte envoyé par un client : type, longueur, pas de balises, retours à la ligne limités.
function Hexa.CleanText(value, maxLength)
    if type(value) ~= 'string' then return nil end
    local text = value:gsub('[%c]', function(c) return c == '\n' and '\n' or '' end)
    text = text:gsub('<', '‹'):gsub('>', '›'):gsub('\n\n\n+', '\n\n')
    text = text:match('^%s*(.-)%s*$')
    if text == '' then return nil end
    if maxLength and #text > maxLength then
        -- coupe sans casser un caractère UTF-8
        text = text:sub(1, maxLength)
        while #text > 0 and text:byte(#text) >= 0x80 and text:byte(#text) < 0xC0 do text = text:sub(1, -2) end
        if #text > 0 and text:byte(#text) >= 0xC0 then text = text:sub(1, -2) end
    end
    return text
end

-- Plaque comparable : majuscules, sans espaces autour.
function Hexa.Plate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:upper():match('^%s*(.-)%s*$')
    return plate ~= '' and plate or nil
end

function Hexa.IsWeapon(name)
    return type(name) == 'string' and name:upper():sub(1, 7) == 'WEAPON_'
end

-- Copie profonde d'une table.
function Hexa.Copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = Hexa.Copy(entry) end
    return result
end
