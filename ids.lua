-- IDs permanents (uniquement dans la ressource hexa_core).
--   ID joueur     : un par compte FiveM (licence Rockstar), le même pour tous ses personnages.
--   ID personnage : un par personnage du framework (identifier ESX / citizenid QB, QBox).
-- Courts (1, 2, 3…), attribués une seule fois, JAMAIS réutilisés (même si le framework recrée un
-- personnage avec le même identifiant : ESX réutilise « char1:… »).
-- Les autres ressources les lisent avec Hexa.PlayerId / Hexa.CharId (exports ci-dessous).

local fw = Hexa.framework

local T = Hexa.Locale({
    fr = {
        migrated = 'IDs : %s personnage(s) du framework numéroté(s) par ordre de création.',
        migrated_alpha = 'IDs : le framework ne note pas la date de création des personnages : numérotés par ordre alphabétique de l’identifiant.',
        migrate_failed = 'IDs : migration impossible (%s). Elle sera retentée au prochain démarrage.',
    },
    en = {
        migrated = 'IDs: %s framework character(s) numbered in creation order.',
        migrated_alpha = 'IDs: the framework does not record when characters were created: numbered alphabetically by identifier.',
        migrate_failed = 'IDs: migration failed (%s). It will be retried at the next start.',
    },
})

Hexa.Schema({
    [[CREATE TABLE IF NOT EXISTS `hexa_players` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `license` VARCHAR(80) NOT NULL,
        `name` VARCHAR(64) DEFAULT NULL,
        `first_seen` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `last_seen` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `license` (`license`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `hexa_characters` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `identifier` VARCHAR(80) NOT NULL,
        `player_id` INT UNSIGNED DEFAULT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        UNIQUE KEY `identifier` (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `hexa_society_log` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `job` VARCHAR(50) NOT NULL,
        `amount` INT NOT NULL,
        `balance` INT DEFAULT NULL,
        `reason` VARCHAR(120) DEFAULT NULL,
        `author` VARCHAR(80) DEFAULT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `job` (`job`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `hexa_meta` (
        `k` VARCHAR(40) NOT NULL,
        `v` VARCHAR(255) DEFAULT NULL,
        PRIMARY KEY (`k`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
})

-- source -> id. Le serveur fait foi ; les state bags ne servent qu'à l'affichage côté client
-- (un client peut écrire dans son propre state bag : on ne le relit jamais côté serveur).
local playerIds, charIds = {}, {}
local upgraded = false

local function waitReady()
    for _ = 1, 150 do
        if Hexa.DB.ready and upgraded then return true end
        Wait(100)
    end
    return false
end

local function hasColumn(tableName, column)
    local found = tonumber(Hexa.DB.scalar(
        'SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?',
        { tableName, column })) or 0
    return found > 0
end

-- Tables créées par une ancienne version : on ajoute les colonnes qui manquent (sans rien perdre).
local function upgrade()
    for _ = 1, 150 do
        if Hexa.DB.ready then break end
        Wait(100)
    end
    if not Hexa.DB.ready then return end
    local ok, err = pcall(function()
        if not hasColumn('hexa_characters', 'deleted_at') then
            Hexa.DB.update('ALTER TABLE `hexa_characters` ADD COLUMN `deleted_at` TIMESTAMP NULL DEFAULT NULL')
        end
        if not hasColumn('hexa_characters', 'former') then
            Hexa.DB.update('ALTER TABLE `hexa_characters` ADD COLUMN `former` VARCHAR(80) DEFAULT NULL')
        end
    end)
    if not ok then return Hexa.Print('IDs : ' .. tostring(err), 'error') end
    upgraded = true
end

-- Numérote les personnages déjà présents dans le framework, par ordre de création, une seule fois.
-- Ceux qui ont déjà un ID le gardent (INSERT IGNORE). QBCore / QBox : `players.id`. ESX : une colonne de
-- date si la table `users` en a une, sinon ordre alphabétique (ESX ne note pas la création).
local function migrate()
    if Hexa.DB.scalar('SELECT `v` FROM `hexa_meta` WHERE `k` = ?', { 'ids_migrated' }) then return end
    local source = fw == 'esx' and { table = 'users', column = 'identifier', orders = { 'created_at', 'createdat', 'creation_date', 'date_created' } }
        or { table = 'players', column = 'citizenid', orders = { 'id' } }
    if tonumber(Hexa.DB.scalar('SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { source.table })) == 0 then
        return
    end
    local order
    for _, column in ipairs(source.orders) do
        if hasColumn(source.table, column) then order = column break end
    end
    if not order then Hexa.Print(T('migrated_alpha'), 'warn') end
    local orderBy = ('`%s`'):format(order or source.column)
    local count, offset = 0, 0
    while true do
        local rows = Hexa.DB.query(('SELECT `%s` AS identifier FROM `%s` ORDER BY %s LIMIT 500 OFFSET ?'):format(source.column, source.table, orderBy), { offset }) or {}
        if #rows > 0 then
            local marks, values = {}, {}
            for i, row in ipairs(rows) do marks[i] = '(?)'; values[i] = row.identifier end
            Hexa.DB.update('INSERT IGNORE INTO `hexa_characters` (`identifier`) VALUES ' .. table.concat(marks, ','), values)
            count = count + #rows
        end
        offset = offset + #rows
        if #rows < 500 then break end
        Wait(0)
    end
    Hexa.DB.update('INSERT IGNORE INTO `hexa_meta` (`k`, `v`) VALUES (?, ?)', { 'ids_migrated', '1' })
    Hexa.Print(T('migrated', count))
end

CreateThread(function()
    upgrade()
    if not upgraded then return end
    local ok, err = pcall(migrate)
    if not ok then Hexa.Print(T('migrate_failed', tostring(err)), 'warn') end
end)

-- Renvoie l'ID du compte FiveM, en le créant au besoin.
local function playerId(license, name)
    Hexa.DB.update('INSERT INTO `hexa_players` (`license`, `name`) VALUES (?, ?) ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `last_seen` = CURRENT_TIMESTAMP',
        { license, name })
    return tonumber(Hexa.DB.scalar('SELECT `id` FROM `hexa_players` WHERE `license` = ?', { license }))
end

-- Renvoie l'ID du personnage, en le créant au besoin. Si l'identifiant appartient à un personnage supprimé
-- (ESX réutilise « char1:… »), l'ancien garde son ID, le nouveau en reçoit un autre.
local function characterId(identifier)
    local row = Hexa.DB.single('SELECT `id`, `deleted_at` IS NOT NULL AS gone FROM `hexa_characters` WHERE `identifier` = ?', { identifier })
    if row and tonumber(row.gone) == 1 then
        Hexa.DB.update("UPDATE `hexa_characters` SET `former` = `identifier`, `identifier` = CONCAT('#', `id`) WHERE `id` = ?", { row.id })
        row = nil
    end
    if row then return tonumber(row.id) end
    Hexa.DB.update('INSERT IGNORE INTO `hexa_characters` (`identifier`) VALUES (?)', { identifier })
    return tonumber(Hexa.DB.scalar('SELECT `id` FROM `hexa_characters` WHERE `identifier` = ?', { identifier }))
end

local function assignPlayer(source)
    local license = GetPlayerIdentifierByType(source, 'license')
    if not license or not waitReady() then return end
    local ok, id = pcall(playerId, license, GetPlayerName(source))
    if not ok or not id then return Hexa.Print('ID joueur : ' .. tostring(id), 'error') end
    if not GetPlayerName(source) then return end   -- parti pendant la requête
    playerIds[source] = id
    Player(source).state:set('hexaPlayerId', id, true)
end

local function assignCharacter(source)
    local identifier = Hexa.Identifier(source)
    if not identifier or not waitReady() then return end
    local ok, id = pcall(characterId, identifier)
    if not ok or not id then return Hexa.Print('ID personnage : ' .. tostring(id), 'error') end
    if Hexa.Identifier(source) ~= identifier then return end   -- personnage changé pendant la requête
    charIds[source] = id
    Player(source).state:set('hexaCharId', id, true)
    if playerIds[source] then
        pcall(Hexa.DB.update, 'UPDATE `hexa_characters` SET `player_id` = ? WHERE `id` = ? AND `player_id` IS NULL', { playerIds[source], id })
    end
end

local function clearCharacter(source)
    charIds[source] = nil
    if GetPlayerName(source) then Player(source).state:set('hexaCharId', nil, true) end
end

AddEventHandler('playerJoining', function() local src = source; CreateThread(function() assignPlayer(src) end) end)
Hexa.OnPlayerLoaded(function(src)
    CreateThread(function()
        if not playerIds[src] then assignPlayer(src) end
        assignCharacter(src)
    end)
end)
AddEventHandler('esx:playerLogout', function(src) clearCharacter(tonumber(src) or source) end)
AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) clearCharacter(tonumber(src) or source) end)
Hexa.OnPlayerDropped(function(src)
    local id = playerIds[src]
    playerIds[src], charIds[src] = nil, nil
    -- « dernière connexion » = le moment où le joueur est parti.
    if id then CreateThread(function() pcall(Hexa.DB.update, 'UPDATE `hexa_players` SET `last_seen` = CURRENT_TIMESTAMP WHERE `id` = ?', { id }) end) end
end)

-- hexa_core redémarré pendant que des joueurs sont connectés.
CreateThread(function()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        assignPlayer(src)
        if Hexa.GetPlayer(src) then assignCharacter(src) end
    end
end)

local function sourceOf(list, id)
    id = tonumber(id)
    for src, value in pairs(list) do if value == id then return src end end
end

exports('GetPlayerId', function(source) return playerIds[tonumber(source)] end)
exports('GetCharId', function(source) return charIds[tonumber(source)] end)
exports('GetSourceByPlayerId', function(id) return sourceOf(playerIds, id) end)
exports('GetSourceByCharId', function(id) return sourceOf(charIds, id) end)

-- Personnage hors ligne : identifier -> ID (sans en créer), et l'inverse. Un personnage supprimé n'a plus d'identifiant.
exports('GetCharIdByIdentifier', function(identifier)
    return tonumber(Hexa.DB.scalar('SELECT `id` FROM `hexa_characters` WHERE `identifier` = ? AND `deleted_at` IS NULL', { identifier }))
end)
exports('GetIdentifierByCharId', function(id)
    return Hexa.DB.scalar('SELECT COALESCE(`former`, `identifier`) FROM `hexa_characters` WHERE `id` = ?', { tonumber(id) })
end)

-- Dernier départ d'un compte (secondes depuis 1970), ou nil.
exports('GetLastSeen', function(playerId_)
    return tonumber(Hexa.DB.scalar('SELECT UNIX_TIMESTAMP(`last_seen`) FROM `hexa_players` WHERE `id` = ?', { tonumber(playerId_) }))
end)

-- Personnage supprimé (wipe, suppression par le joueur ou un admin). À appeler par la ressource qui supprime.
-- Config.Ids.OnDelete : 'keep' (défaut) garde la ligne, marquée supprimée ; 'remove' l'efface.
-- Dans les deux cas l'ID n'est jamais redonné. L'événement serveur « hexa_core:characterDeleted »
-- (charId, identifier) prévient les ressources, qui purgent leurs données.
exports('DeleteCharacter', HexaGuard('DeleteCharacter', function(identifier)
    if type(identifier) ~= 'string' then return false end
    local id = tonumber(Hexa.DB.scalar('SELECT `id` FROM `hexa_characters` WHERE `identifier` = ? AND `deleted_at` IS NULL', { identifier }))
    if not id then return false end
    if (Hexa.Config.Ids or {}).OnDelete == 'remove' then
        Hexa.DB.update('DELETE FROM `hexa_characters` WHERE `id` = ?', { id })
    else
        Hexa.DB.update('UPDATE `hexa_characters` SET `deleted_at` = CURRENT_TIMESTAMP WHERE `id` = ?', { id })
    end
    for src, value in pairs(charIds) do
        if value == id then clearCharacter(src) end
    end
    TriggerEvent('hexa_core:characterDeleted', id, identifier)
    return true, id
end, false))
