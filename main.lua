-- Démarrage : refuse de tourner sans oxmysql ni framework, avec le moyen de corriger.
local T = Hexa.Locale({
    fr = {
        banner = 'hexa_core ne démarre pas :',
        no_mysql = 'oxmysql n’est pas démarré. Ajoutez « ensure oxmysql » dans server.cfg, avant hexa_core.',
        no_framework = 'aucun framework n’est démarré. Ajoutez « ensure es_extended » (ou qb-core, qbx_core) dans server.cfg, avant hexa_core.',
        update = '%s : version %s disponible (installée : %s).%s',
        check_failed = 'Vérification des versions impossible (%s).',
        checked = 'Vérification des versions faite : %s mise(s) à jour disponible(s).',
    },
    en = {
        banner = 'hexa_core is not starting:',
        no_mysql = 'oxmysql is not started. Add "ensure oxmysql" to server.cfg, before hexa_core.',
        no_framework = 'no framework is started. Add "ensure es_extended" (or qb-core, qbx_core) to server.cfg, before hexa_core.',
        update = '%s: version %s available (installed: %s).%s',
        check_failed = 'Version check failed (%s).',
        checked = 'Version check done: %s update(s) available.',
    },
})

local problems = {}
if GetResourceState('oxmysql') ~= 'started' then problems[#problems + 1] = T('no_mysql') end
if not Hexa.framework then problems[#problems + 1] = T('no_framework') end
if #problems > 0 then
    for _, problem in ipairs(problems) do Hexa.Print(T('banner') .. ' ' .. problem, 'error') end
    SetTimeout(0, function() StopResource(Hexa.resource) end)
    return
end

Hexa.Print(('v%s — framework : %s — langue : %s'):format(Hexa.version, Hexa.framework, Hexa.Config.Locale))

exports('Version', function() return Hexa.version end)
exports('ApiLevel', function() return Hexa.apiLevel end)

-- Nouvelles versions des ressources Hexa ---------------------------------------------------------------
-- Lit un petit fichier JSON public (config_server.lua → VersionCheck) :
--   { "hexa_core": { "version": "1.4.0", "notes": "Dialogues intégrés" }, "hexa_shops": "1.1.0" }
-- et signale en console les ressources installées plus anciennes. Aucune donnée n'est envoyée.

function HexaCheckVersions(body)
    local ok, data = pcall(json.decode, body or '')
    if not ok or type(data) ~= 'table' then
        Hexa.Print(T('check_failed', 'fichier illisible / unreadable file'), 'warn')
        return 0
    end
    local count = 0
    for resource, info in pairs(data) do
        local latest = type(info) == 'table' and info.version or info
        local state = type(resource) == 'string' and resource:find('^hexa_') and GetResourceState(resource)
        local current = state and state ~= 'missing' and GetResourceMetadata(resource, 'version', 0)
        if type(latest) == 'string' and current and not Hexa.VersionAtLeast(current, latest) then
            local notes = type(info) == 'table' and type(info.notes) == 'string' and (' ' .. info.notes) or ''
            Hexa.Print(T('update', resource, latest, current, notes), 'warn')
            count = count + 1
        end
    end
    return count
end

local check = Hexa.ServerConfig.VersionCheck or {}
if check.enabled ~= false and type(check.url) == 'string' and check.url:find('^https://') then
    SetTimeout(5000, function()
        PerformHttpRequest(check.url, function(status, body)
            if status ~= 200 then return Hexa.Print(T('check_failed', tostring(status)), 'warn') end
            local count = HexaCheckVersions(body)
            Hexa.Print(T('checked', count), 'debug')
        end, 'GET')
    end)
end
