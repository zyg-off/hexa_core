-- Logs de tout le serveur, gérés par la ressource hexa_core : base (table hexa_logs), fichier du jour et
-- un seul salon Discord (avec regroupement des logs identiques et limite par minute).
-- Les ressources passent par Hexa.Log, qui envoie l'événement hexa_core:server:log reçu ici.
local cfg = Hexa.ServerConfig.Logs
local queue, ready = {}, false
local MAX_QUEUE = 5000          -- base en panne : on garde les plus récents

-- Discord ------------------------------------------------------------------------------------------------
local colorsByLevel = { info = 3447003, success = 3066993, warning = 15105570, error = 15158332 }
local discord, sending = {}, false
local groups = {}               -- logs identiques regroupés : [clé] = { at, count, entry }
local minuteStart, sentThisMinute, dropped = GetGameTimer(), 0, 0

local function valid(url) return type(url) == 'string' and url:find('^https://') ~= nil end
local function webhookUrl()
    if valid(cfg.webhook) then return cfg.webhook end
    if valid(cfg.default) then return cfg.default end
end
local function perMinute() return math.max(1, math.floor(tonumber(cfg.maxPerMinute) or 30)) end
local function windowMs() return math.max(0, math.floor((tonumber(cfg.groupSeconds) or 10) * 1000)) end

local function pump()
    if sending then return end
    sending = true
    CreateThread(function()
        while #discord > 0 do
            local item = table.remove(discord, 1)
            local wait = 1000
            PerformHttpRequest(item.url, function(status, _, headers)
                if status == 429 then
                    item.tries = item.tries + 1
                    if item.tries <= 5 then table.insert(discord, 1, item) end
                    local retry = tonumber(headers and (headers['Retry-After'] or headers['retry-after']))
                    wait = math.floor((retry or 2) * 1000)
                end
            end, 'POST', item.body, { ['Content-Type'] = 'application/json' })
            Wait(wait)
        end
        sending = false
    end)
end

local function embed(entry, text, extra)
    local list = {}
    if entry.name or entry.identifier then
        local labels = entry.labels or {}
        list[#list + 1] = { name = labels.player or 'Player', value = ('%s (%s)'):format(entry.name or '?', entry.source or '?'), inline = true }
        list[#list + 1] = { name = labels.identifier or 'Identifier', value = tostring(entry.identifier or '?'), inline = true }
        list[#list + 1] = { name = 'ID', value = ('#%s / #%s'):format(entry.playerId or '?', entry.charId or '?'), inline = true }
    end
    for name, value in pairs(type(entry.fields) == 'table' and entry.fields or {}) do
        list[#list + 1] = { name = tostring(name), value = tostring(value), inline = true }
    end
    return json.encode({
        username = cfg.name or 'Hexa Studio',
        embeds = { {
            title = ('%s · %s'):format(entry.resource or '?', entry.category or '?'),
            description = (text or tostring(entry.message or '')):sub(1, 4000),
            color = colorsByLevel[entry.level or 'info'] or colorsByLevel.info,
            fields = list,
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        } },
    })
end

local function rollMinute(t)
    if t - minuteStart < 60000 then return end
    local url = webhookUrl()
    if dropped > 0 and url then
        discord[#discord + 1] = { url = url, tries = 0, body = embed({ resource = 'hexa_core', category = 'logs', level = 'warning' },
            ('%d log(s) non envoyé(s) à Discord (limite : %d par minute). Ils sont dans la base et le fichier du jour.'):format(dropped, perMinute())) }
        pump()
    end
    minuteStart, sentThisMinute, dropped = t, 0, 0
end

local function sendDiscord(entry, repeated)
    local url = webhookUrl()
    if not url then return end
    local t = GetGameTimer()
    rollMinute(t)
    if sentThisMinute >= perMinute() then dropped = dropped + 1; return end
    sentThisMinute = sentThisMinute + 1
    local text
    if repeated and repeated > 0 then
        text = ('%s\n*(+%d identique(s) en %d s)*'):format(tostring(entry.message or ''), repeated, math.floor(windowMs() / 1000))
    end
    discord[#discord + 1] = { url = url, tries = 0, body = embed(entry, text) }
    pump()
end

local function toDiscord(entry)
    if not webhookUrl() then return end
    local window = windowMs()
    if window <= 0 then return sendDiscord(entry) end
    local key = table.concat({ tostring(entry.resource), tostring(entry.category), tostring(entry.level), tostring(entry.message), tostring(entry.identifier) }, '\1')
    local group, t = groups[key], GetGameTimer()
    if group and t - group.at < window then
        group.count, group.entry = group.count + 1, entry
    else
        groups[key] = { at = t, count = 0, entry = entry }
        sendDiscord(entry)
    end
end

-- Chaque seconde : les groupes arrivés au bout de leur fenêtre sont résumés, puis oubliés.
CreateThread(function()
    while true do
        Wait(1000)
        if next(groups) or dropped > 0 then
            local t = GetGameTimer()
            for key, group in pairs(groups) do
                if t - group.at >= windowMs() then
                    groups[key] = nil
                    if group.count > 0 then sendDiscord(group.entry, group.count) end
                end
            end
            rollMinute(t)
        end
    end
end)

-- Fichier du jour -------------------------------------------------------------------------------------------
-- logs/jour_NN.log : un fichier par jour, réutilisé tous les `keepDays` jours (FiveM ne permet pas d'en effacer :
-- le plus ancien est donc simplement réécrit). La première ligne donne la date.
local fileLines, fileWarned = {}, false
local MAX_FILE = 2 * 1024 * 1024

local function fileName()
    local days = math.max(1, math.floor(tonumber(cfg.keepDays) or 30))
    return ('logs/jour_%02d.log'):format(math.floor(os.time() / 86400) % days + 1), os.date('!%Y-%m-%d')
end

local function writeFile()
    if #fileLines == 0 then return end
    local name, today = fileName()
    local current = LoadResourceFile(GetCurrentResourceName(), name) or ''
    local header = '# ' .. today .. '\n'
    if current:sub(1, #header) ~= header then current = header end
    if #current > MAX_FILE then
        if not fileWarned then fileWarned = true; Hexa.Print('Fichier de logs du jour plein (2 Mo) : le reste va dans la base seulement.', 'warn') end
        fileLines = {}
        return
    end
    local data = current .. table.concat(fileLines, '\n') .. '\n'
    fileLines = {}
    if not SaveResourceFile(GetCurrentResourceName(), name, data, -1) and not fileWarned then
        fileWarned = true
        Hexa.Print('Impossible d\'écrire logs/ : le dossier hexa_core/logs doit exister (il est livré avec le core).', 'warn')
    end
end

local function fileLine(entry)
    local who = entry.identifier and (' [' .. entry.identifier .. ']') or ''
    local line = ('%s [%s] [%s/%s]%s %s'):format(os.date('!%H:%M:%S'), tostring(entry.level or 'info'), tostring(entry.resource or '?'),
        tostring(entry.category or '?'), who, (tostring(entry.message or ''):gsub('[\r\n]+', ' ')))
    if type(entry.fields) == 'table' and next(entry.fields) then line = line .. ' ' .. json.encode(entry.fields) end
    fileLines[#fileLines + 1] = line
    if #fileLines > MAX_QUEUE then table.remove(fileLines, 1) end
end

AddEventHandler('hexa_core:server:log', function(entry)
    if type(entry) ~= 'table' then return end
    toDiscord(entry)
    if cfg.file ~= false then fileLine(entry) end
    if cfg.database == false then return end
    if #queue >= MAX_QUEUE then table.remove(queue, 1) end
    queue[#queue + 1] = entry
end)

local function purge()
    local days = math.max(1, tonumber(cfg.keepDays) or 30)
    local ok, err = pcall(Hexa.DB.update, 'DELETE FROM `hexa_logs` WHERE `created_at` < NOW() - INTERVAL ? DAY', { days })
    if not ok then Hexa.Print('SQL : ' .. tostring(err), 'error') end
end

local function write(entry)
    local fields = type(entry.fields) == 'table' and next(entry.fields) and json.encode(entry.fields) or nil
    return pcall(Hexa.DB.insert, [[INSERT INTO `hexa_logs`
        (`resource`, `category`, `level`, `message`, `player_name`, `identifier`, `player_id`, `char_id`, `fields`)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
        tostring(entry.resource or '?'):sub(1, 64), tostring(entry.category or '?'):sub(1, 64),
        tostring(entry.level or 'info'):sub(1, 16), tostring(entry.message or ''):sub(1, 4000),
        entry.name and tostring(entry.name):sub(1, 100) or nil, entry.identifier and tostring(entry.identifier):sub(1, 80) or nil,
        tonumber(entry.playerId), tonumber(entry.charId), fields,
    })
end

CreateThread(function()
    if cfg.database == false then
        while true do Wait(2000); writeFile() end
    end
    for _ = 1, 100 do
        if GetResourceState('oxmysql') == 'started' then break end
        Wait(100)
    end
    local ok, err = pcall(Hexa.DB.query, [[
        CREATE TABLE IF NOT EXISTS `hexa_logs` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `resource` VARCHAR(64) NOT NULL,
            `category` VARCHAR(64) NOT NULL,
            `level` VARCHAR(16) NOT NULL DEFAULT 'info',
            `message` TEXT NOT NULL,
            `player_name` VARCHAR(100) NULL,
            `identifier` VARCHAR(80) NULL,
            `player_id` INT UNSIGNED NULL,
            `char_id` INT UNSIGNED NULL,
            `fields` LONGTEXT NULL,
            PRIMARY KEY (`id`),
            KEY `created_at` (`created_at`),
            KEY `category` (`category`),
            KEY `identifier` (`identifier`)
        )
    ]])
    if not ok then return Hexa.Print('Logs en base désactivés (SQL : ' .. tostring(err) .. ')', 'error') end
    ready = true
    purge()
    local lastPurge = GetGameTimer()
    while true do
        Wait(2000)
        writeFile()
        while #queue > 0 do
            local entry = table.remove(queue, 1)
            local written, failure = write(entry)
            if not written then
                Hexa.Print('SQL : ' .. tostring(failure), 'error')
                table.insert(queue, 1, entry)       -- on réessaie au prochain tour
                break
            end
        end
        if GetGameTimer() - lastPurge > 86400000 then lastPurge = GetGameTimer(); purge() end
    end
end)

-- Pour un futur panneau d'administration :
-- exports.hexa_core:GetLogs({ category = 'money', resource = 'hexa_banking', identifier = 'char:1', search = 'retrait', limit = 100 })
exports('GetLogs', HexaGuard('GetLogs', function(filter)
    if not ready then return {} end
    filter = type(filter) == 'table' and filter or {}
    local where, params = {}, {}
    for _, key in ipairs({ 'category', 'resource', 'identifier', 'level' }) do
        if type(filter[key]) == 'string' then where[#where + 1] = ('`%s` = ?'):format(key); params[#params + 1] = filter[key] end
    end
    if type(filter.search) == 'string' and filter.search ~= '' then
        where[#where + 1] = '`message` LIKE ?'
        params[#params + 1] = '%' .. filter.search:gsub('[%%_\\]', '\\%0') .. '%'
    end
    params[#params + 1] = math.max(1, math.min(500, math.floor(tonumber(filter.limit) or 100)))
    local query = 'SELECT * FROM `hexa_logs`' .. (#where > 0 and (' WHERE ' .. table.concat(where, ' AND ')) or '')
        .. ' ORDER BY `id` DESC LIMIT ?'
    local ok, rows = pcall(Hexa.DB.query, query, params)
    return ok and rows or {}
end, {}))

HexaLogs = { queue = queue, purge = purge }
