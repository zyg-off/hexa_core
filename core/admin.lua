-- Commandes d'administration de hexa_core (console du serveur, ou en jeu pour les admins) :
--   hexa_debug            : dit si le debug est actif
--   hexa_debug on / off   : active / coupe le debug de TOUTES les ressources Hexa, sans redémarrer
--   hexa_debug hexa_shops : active le debug d'une seule ressource (ou plusieurs, séparées par des virgules)
--   hexa_check            : bilan de santé (framework, base de données, ressources Hexa, Discord, logs…)
local T = Hexa.Locale({
    fr = {
        debug_state = 'Debug : %s.',
        on = 'actif', off = 'coupé',
        debug_set = 'Debug %s (%s).',
        debug_all = 'toutes les ressources', 
        check_title = 'Bilan de santé hexa_core v%s',
        c_framework = 'Framework : %s',
        c_mysql = 'oxmysql : %s',
        c_db = 'Base de données : %s',
        c_db_ok = 'prête', c_db_wait = 'pas encore prête',
        c_discord = 'Discord : %s',
        c_discord_ok = 'webhook configuré', c_discord_none = 'aucun webhook (logs en base et fichier seulement)',
        c_resources = 'Ressources Hexa démarrées : %s',
        c_none = 'aucune autre',
        c_instances = 'Instances : %s joueur(s) placé(s), %s conflit(s) corrigé(s)',
        c_ok = 'Tout est en ordre.',
        c_problems = '%s problème(s) à regarder.',
    },
    en = {
        debug_state = 'Debug: %s.',
        on = 'on', off = 'off',
        debug_set = 'Debug %s (%s).',
        debug_all = 'all resources',
        check_title = 'hexa_core health check v%s',
        c_framework = 'Framework: %s',
        c_mysql = 'oxmysql: %s',
        c_db = 'Database: %s',
        c_db_ok = 'ready', c_db_wait = 'not ready yet',
        c_discord = 'Discord: %s',
        c_discord_ok = 'webhook configured', c_discord_none = 'no webhook (database and file logs only)',
        c_resources = 'Hexa resources started: %s',
        c_none = 'no other',
        c_instances = 'Instances: %s player(s) placed, %s conflict(s) fixed',
        c_ok = 'Everything looks fine.',
        c_problems = '%s problem(s) to look at.',
    },
})

local function reply(source, message, level)
    if source == 0 or not source then Hexa.Print(message, level) else Hexa.Notify(source, message, level == 'warn' and 'warning' or 'info') end
end

Hexa.Command('hexa_debug', { admin = true, help = 'Debug Hexa : on / off / nom de ressource' }, function(source, args)
    local arg = args[1] and args[1]:lower()
    if not arg then
        return reply(source, T('debug_state', Hexa.IsDebug() and T('on') or T('off')))
    end
    if arg == 'off' or arg == 'false' or arg == '0' then
        SetConvar('hexa_debug', '')
        if Hexa.Config.Debug then reply(source, T('debug_state', T('on')) .. ' (config.lua : Debug = true)', 'warn') end
        return reply(source, T('debug_set', T('off'), T('debug_all')))
    end
    if arg == 'on' or arg == 'all' or arg == 'true' or arg == '1' then
        SetConvar('hexa_debug', 'all')
        return reply(source, T('debug_set', T('on'), T('debug_all')))
    end
    local list = (table.concat(args, ' '):gsub('[%s,]+', ','))
    SetConvar('hexa_debug', list)
    reply(source, T('debug_set', T('on'), list))
end)

local function hexaResources()
    local list = {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and name:find('^hexa_') and name ~= Hexa.resource and GetResourceState(name) == 'started' then list[#list + 1] = name end
    end
    table.sort(list)
    return list
end

-- Renvoie la liste des lignes du bilan et le nombre de problèmes (utilisé aussi par les tests).
function HexaHealth()
    local lines, problems = {}, 0
    local function add(text, bad) lines[#lines + 1] = { text = text, bad = bad or false }; if bad then problems = problems + 1 end end

    add(T('c_framework', tostring(Hexa.framework)), not Hexa.framework)
    local mysql = GetResourceState('oxmysql')
    add(T('c_mysql', mysql), mysql ~= 'started')
    add(T('c_db', Hexa.DB.ready and T('c_db_ok') or T('c_db_wait')), not Hexa.DB.ready)
    local logs = Hexa.ServerConfig.Logs or {}
    local hasWebhook = (type(logs.webhook) == 'string' and logs.webhook:find('^https://') ~= nil)
        or (type(logs.default) == 'string' and logs.default:find('^https://') ~= nil)
    add(T('c_discord', hasWebhook and T('c_discord_ok') or T('c_discord_none')))

    local list = hexaResources()
    local described = {}
    for _, name in ipairs(list) do
        local version = GetResourceMetadata(name, 'version', 0) or '?'
        described[#described + 1] = name .. ' ' .. version
    end
    add(T('c_resources', #list > 0 and table.concat(described, ', ') or T('c_none')))

    if HexaInstances then
        local count = 0
        for _ in pairs(HexaInstances.players) do count = count + 1 end
        add(T('c_instances', count, HexaInstances.conflicts()))
    end
    return lines, problems
end

Hexa.Command('hexa_check', { admin = true, help = 'Bilan de santé des ressources Hexa' }, function(source)
    local lines, problems = HexaHealth()
    reply(source, T('check_title', Hexa.version))
    for _, line in ipairs(lines) do reply(source, (line.bad and '✘ ' or '✔ ') .. line.text, line.bad and 'warn' or 'info') end
    reply(source, problems == 0 and T('c_ok') or T('c_problems', problems), problems == 0 and 'info' or 'warn')
end)
