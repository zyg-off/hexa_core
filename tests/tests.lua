-- Scénarios hexa_core, rejoués pour ESX, QBCore et QBox.
-- Nom « S… » : côté serveur, « C… » : côté client.
local results = {}
local function check(name, cond, detail) results[#results + 1] = { name = name, ok = cond and true or false, detail = tostring(detail or '') } end
local esx, qb, qbx = FRAMEWORK == 'esx', FRAMEWORK == 'qb', FRAMEWORK == 'qbx'
local isQB = qb or qbx

local function load(files)
    for _, f in ipairs(files) do
        -- comme fxmanifest.lua : la sécurité est chargée avant ids / instances / logs
        if (f == 'ids.lua' or f == 'core/instances.lua' or f == 'core/logs.lua') and not HexaGuard then load({ 'core/security.lua' }) end
        local chunk, err = loadfile(ROOT_DIR .. '/' .. f, 't', _ENV)
        if not chunk then error(f .. ': ' .. err) end
        chunk()
    end
end
local function server() load({ 'shared.lua', 'server.lua' }) end
local function client() load({ 'shared.lua', 'client.lua' }) end
local function inThread(fn) local out; CreateThread(function() out = table.pack(fn()) end); RunThreads(20000); return table.unpack(out or {}) end
local function printed(text) return table.concat(PRINTS, '\n'):find(text, 1, true) ~= nil end
-- noms tels que le framework les stocke
local W = qb and 'weapon_pistol' or 'WEAPON_PISTOL'

local tests = {}

-- Démarrage --------------------------------------------------------------------------------------------
tests['S01 Détection du framework'] = function()
    server()
    check('Framework détecté : ' .. FRAMEWORK, Hexa.framework == FRAMEWORK, Hexa.framework)
    check('Objet du framework (sauf QBox : exports)', (Hexa.core ~= nil) == not qbx)
    check('isQB', Hexa.isQB == isQB)
    check('Config lue depuis hexa_core', Hexa.Config.Accounts.qbx.cash == 'cash')
    check('Config serveur lue', Hexa.ServerConfig.Admin.ace == 'hexa.admin')
end

tests['S02 Aucun framework : erreur claire, pas de plantage'] = function()
    CONFIG_OVERRIDE = "HexaConfig = { Framework = 'esx', ESXResource = 'absent' }"
    server()
    check('framework = nil', Hexa.framework == nil)
    check('Erreur « demandé mais non démarré »', printed('« esx » demandé'))
    check('Erreur « aucun framework »', printed('Aucun framework compatible'))
    NewPlayer(1, { cash = 50 })
    check('Les fonctions renvoient des valeurs neutres', Hexa.GetPlayer(1) == nil and Hexa.Balance(1, 'cash') == 0 and not Hexa.Pay(1, 10) and Hexa.ItemCount(1, 'bread') == 0)
end

tests['S03 Config cassée ou en anglais'] = function()
    CONFIG_OVERRIDE = 'HexaConfig = {{{ pas du lua'
    server()
    check('Valeurs par défaut', Hexa.Config.Locale == 'fr' and Hexa.Config.Accounts ~= nil)
    if not esx then return end
    Hexa = nil; PRINTS = {}
    CONFIG_OVERRIDE = "HexaConfig = { Framework = 'qbx', Locale = 'en' }"
    server()
    check('Messages du core en anglais', printed('Framework "qbx" requested'))
end

if qbx then
    tests['S04 QBox prioritaire même si « qb-core » répond'] = function()
        server()
        check('QBox choisi', Hexa.framework == 'qbx')
    end
end

-- Joueur -----------------------------------------------------------------------------------------------
tests['S05 Joueur : identifiant, nom, métier'] = function()
    server()
    NewPlayer(1, { identifier = 'abc', charName = 'Ana Silva', job = 'police', grade = 3, onduty = false })
    check('Identifiant', Hexa.Identifier(1) == 'abc', Hexa.Identifier(1))
    check('Nom du personnage', Hexa.Name(1) == 'Ana Silva', Hexa.Name(1))
    local job, grade, duty = Hexa.Job(1)
    check('Métier et grade', job == 'police' and grade == 3)
    check('Service : ESX toujours, QB/QBox lit onduty', duty == esx, tostring(duty))
    check('HasJob', Hexa.HasJob(1, 'police', 3) and not Hexa.HasJob(1, 'police', 4) and Hexa.HasJob(1, { 'ems', 'police' }))
    check('Joueur inconnu', Hexa.Identifier(99) == nil and Hexa.Job(99) == nil and Hexa.Name(99) == '?')
    check('SourceOf', Hexa.SourceOf('abc') == 1 and Hexa.SourceOf('zzz') == nil)
    NewPlayer(2, { coords = vector3(3, 4, 0) })
    check('Distance / IsNear', math.abs(Hexa.Distance(2, vector3()) - 5) < 0.001 and Hexa.IsNear(2, { x = 0, y = 0, z = 0 }, 5.5) and Hexa.Distance(42, vector3()) == math.huge)
end

tests['S06 Métadonnées, faim/soif, mort'] = function()
    server()
    if esx then StartEsxAddons() end
    NewPlayer(1, { meta = { hunger = 40, thirst = 75.6 } })
    check('GetMeta', Hexa.GetMeta(1, 'hunger') == 40)
    check('SetMeta', Hexa.SetMeta(1, 'stress', 12) and Hexa.GetMeta(1, 'stress') == 12)
    local hunger, thirst = inThread(function() return Hexa.GetNeeds(1) end)
    check('GetNeeds en %', hunger == 40 and thirst == 76, tostring(hunger) .. '/' .. tostring(thirst))
    check('SetNeed', inThread(function() return Hexa.SetNeed(1, 'hunger', 150) end) == true)
    if isQB then
        check('QB : valeur bornée à 100', PLAYERS[1].meta.hunger == 100)
        check('QB : HUD prévenu', #ClientEventsFor(1, 'hud:client:UpdateNeeds') == 1)
    else
        local e = ClientEventsFor(1, 'esx_status:set')
        check('ESX : esx_status:set à 1 000 000', e[1] and e[1].args[2] == 1000000)
    end
    check('SetNeed refuse un autre besoin', not Hexa.SetNeed(1, 'stress', 5))
    check('Vivant', not Hexa.IsDead(1))
    PLAYERS[1].health = 0
    check('Mort (santé 0)', Hexa.IsDead(1))
    PLAYERS[1].health = 200
    STATEBAGS[1] = { isDead = true }
    check('Mort (state bag isDead)', Hexa.IsDead(1))
    STATEBAGS[1] = {}
    if isQB then PLAYERS[1].meta.inlaststand = true; check('QB : à terre (inlaststand)', Hexa.IsDead(1)) end
end

-- Argent -----------------------------------------------------------------------------------------------
tests['S07 Argent'] = function()
    server()
    NewPlayer(1, { cash = 100, bank = 1000 })
    check('Soldes', Hexa.Balance(1, 'cash') == 100 and Hexa.Balance(1, 'bank') == 1000)
    check('Ajout', Hexa.AddMoney(1, 'bank', 50) and Bank(1) == 1050)
    check('Retrait', Hexa.RemoveMoney(1, 'cash', 60) and Cash(1) == 40)
    check('Retrait refusé si insuffisant', not Hexa.RemoveMoney(1, 'cash', 41) and Cash(1) == 40)
    check('Négatif / décimal / texte / infini refusés', not Hexa.AddMoney(1, 'cash', -5) and not Hexa.RemoveMoney(1, 'cash', 1.5) and not Hexa.AddMoney(1, 'cash', 'x') and not Hexa.AddMoney(1, 'cash', math.huge) and Cash(1) == 40)
    check('Compte inconnu refusé', not Hexa.AddMoney(1, 'gold', 5))
end

tests['S08 Banque via hexa_banking (historique)'] = function()
    server()
    NewPlayer(1, { cash = 10, bank = 1000 })
    local calls = {}
    RESOURCES.hexa_banking = 'started'
    RESOURCE_EXPORTS.hexa_banking = {
        AddBankMoney = function(src, amount, label) calls[#calls + 1] = { 'add', amount, label }; return true end,
        RemoveBankMoney = function(src, amount, label) calls[#calls + 1] = { 'remove', amount, label }; return true end,
    }
    check('Dépôt banque délégué', Hexa.AddMoney(1, 'bank', 500, 'Salaire') and calls[1][1] == 'add' and calls[1][3] == 'Salaire' and Bank(1) == 1000)
    check('Retrait banque délégué', Hexa.RemoveMoney(1, 'bank', 200, 'Assurance') and calls[2][1] == 'remove')
    check('Retrait banque refusé si solde insuffisant (sans appel)', not Hexa.RemoveMoney(1, 'bank', 5000) and #calls == 2)
    check('Espèces : jamais déléguées', Hexa.AddMoney(1, 'cash', 5) and Cash(1) == 15 and #calls == 2)
    RESOURCE_EXPORTS.hexa_banking.RemoveBankMoney = function() error('panne') end
    check('hexa_banking en panne : refus', not Hexa.RemoveMoney(1, 'bank', 10))
end

tests['S09 Paiement sans hexa_banking'] = function()
    server()
    NewPlayer(1, { cash = 30, bank = 500 })
    local ok, account = Hexa.Pay(1, 20, 'Test')
    check('Espèces d’abord', ok and account == 'cash' and Cash(1) == 10)
    ok, account = Hexa.Pay(1, 200)
    check('Puis banque', ok and account == 'bank' and Bank(1) == 300 and Cash(1) == 10)
    check('Refus si rien ne suffit, rien débité', not Hexa.Pay(1, 5000) and Bank(1) == 300 and Cash(1) == 10)
    ok, account = Hexa.Pay(1, 5, 'Amende', { 'bank' })
    check('Ordre imposé', ok and account == 'bank' and Bank(1) == 295)
    check('Montant 0', Hexa.Pay(1, 0) == true and Bank(1) == 295)
    check('Montant invalide refusé', not Hexa.Pay(1, -10) and not Hexa.Pay(1, 2.5) and not Hexa.Pay(1, nil))
    check('Remboursement', Hexa.Refund(1, 'bank', 5) and Bank(1) == 300)
    check('Remboursement sans compte refusé', not Hexa.Refund(1, nil, 5))
end

tests['S10 Paiement via hexa_banking'] = function()
    server()
    NewPlayer(1, { cash = 30, bank = 500 })
    local calls = {}
    RESOURCES.hexa_banking = 'started'
    RESOURCE_EXPORTS.hexa_banking = {
        Pay = function(src, amount, reason, order) calls[#calls + 1] = { 'pay', amount, reason }; return true, 'bank' end,
        Refund = function(src, account, amount) calls[#calls + 1] = { 'refund', account, amount }; return true end,
    }
    local ok, account = Hexa.Pay(1, 80, 'Vêtements')
    check('Délégué, sans débit direct', ok and account == 'bank' and calls[1][2] == 80 and Cash(1) == 30 and Bank(1) == 500)
    check('Remboursement délégué', Hexa.Refund(1, 'bank', 80) and calls[2][1] == 'refund')
    RESOURCE_EXPORTS.hexa_banking.Pay = function() error('panne') end
    check('En panne : refus sans débit direct', not Hexa.Pay(1, 10) and Cash(1) == 30 and printed('panne'))
end

tests['S11 hexa_banking lui-même : débit direct'] = function()
    RESOURCE_NAME = 'hexa_banking'
    server()
    NewPlayer(1, { cash = 30, bank = 100 })
    RESOURCES.hexa_banking = 'started'
    RESOURCE_EXPORTS.hexa_banking = { Pay = function() error('boucle') end, AddBankMoney = function() error('boucle') end }
    local ok, account = Hexa.Pay(1, 10)
    check('Pay direct', ok and account == 'cash' and Cash(1) == 20)
    check('AddMoney banque direct', Hexa.AddMoney(1, 'bank', 5) and Bank(1) == 105)
end

-- Objets -----------------------------------------------------------------------------------------------
tests['S12 Objets via le framework'] = function()
    server()
    NewPlayer(1, { items = { bread = 3 } })
    check('Quantité (nom en majuscules accepté)', Hexa.ItemCount(1, 'bread') == 3 and (esx or Hexa.ItemCount(1, 'BREAD') == 3))
    check('HasItem', Hexa.HasItem(1, 'bread', 3) and not Hexa.HasItem(1, 'bread', 4))
    check('Ajout', Hexa.AddItem(1, 'water', 2) and Items(1, 'water') == 2)
    check('Retrait', Hexa.RemoveItem(1, 'bread', 2) and Items(1, 'bread') == 1)
    check('Retrait refusé si insuffisant', not Hexa.RemoveItem(1, 'bread', 5) and Items(1, 'bread') == 1)
    check('Quantité invalide refusée', not Hexa.AddItem(1, 'water', -1) and not Hexa.AddItem(1, 'water', 0.5) and not Hexa.AddItem(1, nil, 1))
    if not qb then check('Poids max respecté', not Hexa.AddItem(1, 'water', 100) and Items(1, 'water') == 2 and not Hexa.CanCarry(1, 'water', 100) and Hexa.CanCarry(1, 'water', 1)) end
    if qbx then
        Hexa.AddItem(1, 'document', 1, { serial = 'A1' })
        check('QBox : métadonnées transmises à ox_inventory', LAST_META and LAST_META.serial == 'A1')
        check('QBox : arme en majuscules', Hexa.AddItem(1, 'weapon_pistol', 1) and Items(1, 'WEAPON_PISTOL') == 1)
    end
end

if esx then
    tests['S13 ESX : armes (loadout)'] = function()
        server()
        NewPlayer(1)
        check('Pas d’arme', Hexa.ItemCount(1, 'WEAPON_PISTOL') == 0)
        check('Donner une arme avec munitions', Hexa.AddItem(1, 'WEAPON_PISTOL', 1, { ammo = 24 }) and PLAYERS[1].weapons.WEAPON_PISTOL == 24)
        check('Compte = 1', Hexa.ItemCount(1, 'WEAPON_PISTOL') == 1)
        check('Doublon refusé', not Hexa.AddItem(1, 'WEAPON_PISTOL', 1) and not Hexa.CanCarry(1, 'WEAPON_PISTOL', 1))
        check('Retirer l’arme', Hexa.RemoveItem(1, 'WEAPON_PISTOL', 1) and PLAYERS[1].weapons.WEAPON_PISTOL == nil)
        check('Pas un objet d’inventaire', Items(1, 'WEAPON_PISTOL') == 0)
    end
end

tests['S14 Objets via hexa_inventory (bonne signature)'] = function()
    server()
    NewPlayer(1, { items = { bread = 3 } })
    local inv, lastArgs = { bread = 7 }, nil
    RESOURCES.hexa_inventory = 'started'
    RESOURCE_EXPORTS.hexa_inventory = {
        GetItemCount = function(_, name) return inv[name] or 0 end,
        CanCarryItem = function() return true end,
        AddItem = function(...) lastArgs = table.pack(...); inv[lastArgs[2]] = (inv[lastArgs[2]] or 0) + lastArgs[3]; return true end,
        RemoveItem = function(_, name, count) inv[name] = inv[name] - count; return true end,
    }
    check('Lit hexa_inventory en priorité', Hexa.ItemCount(1, 'bread') == 7)
    Hexa.AddItem(1, 'document', 1, { serial = 'A1' })
    if isQB then check('QB/QBox : métadonnées en 5ᵉ position (signature qb-inventory)', lastArgs[4] == nil and lastArgs[5].serial == 'A1')
    else check('ESX : métadonnées en 4ᵉ position', lastArgs[4].serial == 'A1') end
    check('Retire via hexa_inventory', Hexa.RemoveItem(1, 'bread', 7) and inv.bread == 0)
    check('Le framework n’est pas touché', Items(1, 'bread') == 3)
    RESOURCE_EXPORTS.hexa_inventory.AddItem = function() error('panne') end
    check('Panne de hexa_inventory : refus', not Hexa.AddItem(1, 'water', 1))
end

tests['S15 Libellés et objets utilisables'] = function()
    server()
    check('Libellé objet', Hexa.ItemLabel('bread') == 'Pain', Hexa.ItemLabel('bread'))
    check('Libellé arme', Hexa.ItemLabel('WEAPON_PISTOL') == 'Pistolet', Hexa.ItemLabel('WEAPON_PISTOL'))
    check('Objet inconnu : nil', Hexa.ItemLabel('licorne') == nil)
    if esx then check('ESX : arme inconnue lisible', Hexa.ItemLabel('WEAPON_COMBAT_PISTOL') == 'Combat pistol', Hexa.ItemLabel('WEAPON_COMBAT_PISTOL')) end
    local used
    Hexa.RegisterUsableItem('Bread', function(src) used = src end)
    local key = esx and 'Bread' or 'bread'
    check('Objet utilisable enregistré', USABLE[key] ~= nil)
    if USABLE[key] then USABLE[key](4) end
    check('Rappel reçoit le joueur', used == 4)
end

-- Permis -----------------------------------------------------------------------------------------------
tests['S16 Permis'] = function()
    server()
    NewPlayer(1, { licenses = { driver = true } })
    if esx then
        check('ESX sans esx_license : refus', inThread(function() return Hexa.HasLicense(1, 'driver') end) == false)
        StartEsxAddons()
    end
    check('A le permis', inThread(function() return Hexa.HasLicense(1, 'driver') end) == true)
    check('N’a pas le permis d’arme', inThread(function() return Hexa.HasLicense(1, 'weapon') end) == false)
    check('Aucun permis demandé : vrai', Hexa.HasLicense(1, nil) == true)
    check('Ajouter', inThread(function() return Hexa.AddLicense(1, 'weapon') end) == true and inThread(function() return Hexa.HasLicense(1, 'weapon') end))
    check('Retirer', inThread(function() return Hexa.RemoveLicense(1, 'driver') end) == true and not inThread(function() return Hexa.HasLicense(1, 'driver') end))
    check('Joueur inconnu', inThread(function() return Hexa.AddLicense(99, 'x') end) == false)
    if isQB then check('QB : la table d’origine n’est pas modifiée en place', PLAYERS[1].meta.licences.weapon == true) end
end

-- Base de données et véhicules -------------------------------------------------------------------------
local function fakeDB()
    local vehicles = { ['AB 123'] = 'abc' }
    local function scalar(q, p)
        local column = esx and '`owner`' or '`citizenid`'
        if not q:find(column, 1, true) then error('mauvaise table : ' .. q) end
        return vehicles[p[1]]
    end
    return scalar, vehicles
end

tests['S17 Véhicules : propriétaire (MySQL.lua inclus)'] = function()
    server()
    local scalar = fakeDB()
    MySQL = { scalar = { await = function(q, p) Wait(5); return scalar(q, p) end } }
    NewPlayer(1, { identifier = 'abc' })
    NewPlayer(2, { identifier = 'zzz' })
    check('Plaque normalisée', Hexa.Plate('  ab 123 ') == 'AB 123' and Hexa.Plate('   ') == nil and Hexa.Plate(5) == nil)
    check('Propriétaire trouvé', inThread(function() return Hexa.VehicleOwner(' ab 123') end) == 'abc')
    check('Plaque inconnue', inThread(function() return Hexa.VehicleOwner('NOPE') end) == nil)
    check('IsVehicleOwner', inThread(function() return Hexa.IsVehicleOwner(1, 'AB 123') end) == true and inThread(function() return Hexa.IsVehicleOwner(2, 'AB 123') end) == false)
    MySQL = { scalar = { await = function() error('table absente') end } }
    check('Erreur SQL : nil + message', inThread(function() return Hexa.VehicleOwner('AB 123') end) == nil and printed('table absente'))
end

tests['S18 Base de données sans MySQL.lua (exports oxmysql)'] = function()
    server()
    MySQL = nil
    local scalar = fakeDB()
    RESOURCES.oxmysql = 'started'
    local created = {}
    RESOURCE_EXPORTS.oxmysql = {
        scalar = function(q, p, cb) SetTimeout(5, function() cb(scalar(q, p)) end) end,
        query = function(q, p, cb) created[#created + 1] = q; SetTimeout(5, function() cb({}) end) end,
    }
    check('Via exports oxmysql', inThread(function() return Hexa.VehicleOwner('AB 123') end) == 'abc')
    check('Hexa.DB.query', inThread(function() return Hexa.DB.query('SELECT 1') end) ~= nil)
    Hexa.Schema({ 'CREATE TABLE IF NOT EXISTS a (id int)', 'CREATE TABLE IF NOT EXISTS b (id int)' })
    RunThreads(500)
    check('Schema : tables créées puis ready', #created == 3 and Hexa.DB.ready == true, #created)
    RESOURCE_EXPORTS.oxmysql.query = function() error('droits insuffisants') end
    Hexa.DB.ready = false
    Hexa.Schema('CREATE TABLE c (id int)')
    RunThreads(500)
    check('Schema en erreur : ready reste false + message', Hexa.DB.ready == false and printed('droits insuffisants'))
end

tests['S19 Clés (futur hexa_keys)'] = function()
    server()
    NewPlayer(1)
    check('Sans hexa_keys : false, sans erreur', Hexa.GiveKeys(1, 'AB 123') == false)
    local given
    RESOURCES.hexa_keys = 'started'
    RESOURCE_EXPORTS.hexa_keys = {
        GiveKeys = function(src, plate) given = plate; return true end,
        HasKeys = function() return true end,
        RemoveKeys = function() error('panne') end,
    }
    check('GiveKeys délégué avec plaque normalisée', Hexa.GiveKeys(1, ' ab 123 ') == true and given == 'AB 123')
    check('HasKeys', Hexa.HasKeys(1, 'AB 123'))
    check('Panne : false', Hexa.RemoveKeys(1, 'AB 123') == false)
    check('Plaque vide refusée', Hexa.GiveKeys(1, '  ') == false)
end

-- Administration et logs -------------------------------------------------------------------------------
tests['S20 Admin et commandes'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Admin = { ace = 'hexa.admin', groups = { 'admin' } }, Logs = { default = 'https://discord.com/api/webhooks/1/x' } }"
    server(); load({ 'core/logs.lua' })
    NewPlayer(1, { group = 'user' })
    NewPlayer(2, { group = 'admin' })
    NewPlayer(3)
    ACES['3:hexa.admin'] = true
    check('Console admin', Hexa.IsAdmin(0))
    check('Joueur normal : non', not Hexa.IsAdmin(1))
    check('Groupe admin du framework', Hexa.IsAdmin(2))
    check('Permission ACE', Hexa.IsAdmin(3))
    check('Inconnu : non', not Hexa.IsAdmin(99))
    local ran = {}
    Hexa.Command('heal', { admin = true, help = 'Soigner' }, function(src, args) ran[#ran + 1] = { src, args[1] } end)
    Hexa.Command('me', {}, function(src) ran[#ran + 1] = { src } end)
    RunCommand(1, 'heal 5')
    check('Refusée au joueur normal + message', #ran == 0 and ClientEventsFor(1, 'hexa_test:hexa:notify')[1] ~= nil)
    RunCommand(2, 'heal 5')
    check('Acceptée pour l’admin', ran[1] and ran[1][1] == 2 and ran[1][2] == '5')
    RunThreads(100)
    check('Commande admin journalisée', HTTP[1] and HTTP[1].body:find('/heal 5', 1, true) ~= nil)
    RunCommand(1, 'me')
    check('Commande publique', ran[2] and ran[2][1] == 1)
    RunThreads(2000)
    local s = ClientEventsFor(-1, 'chat:addSuggestion')
    check('Suggestion de chat pour les commandes avec aide', #s == 1 and s[1].args[1] == '/heal')
end

tests['S21 Logs Discord : un seul salon'] = function()
    check('Aucun webhook : rien envoyé', (function() server(); NewPlayer(1); return Hexa.Log('money', 'x', 1) == false end)())
    Hexa = nil
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Logs = { name = 'Mon serveur', webhook = 'https://d/salon', groupSeconds = 0, maxPerMinute = 1000 } }"
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/logs.lua' })
    NewPlayer(1, { charName = 'Ana Silva', identifier = 'abc' })
    check('Webhook réglé : true', Hexa.Log('money', 'Retrait de 500 $', 1, { Lieu = 'Legion' }, 'warning') == true)
    Hexa.Log('items', 'Pain', 1)
    Hexa.Log('police', 'Amende')
    RunThreads(5000)
    check('3 envois, tous dans le même salon, espacés', #HTTP == 3 and HTTP[1].url == 'https://d/salon' and HTTP[2].url == 'https://d/salon' and HTTP[3].url == 'https://d/salon', #HTTP)
    local body = HTTP[1].body
    check('Contenu : nom, identifiant, champ, ressource et catégorie', body:find('Ana Silva (1)', 1, true) and body:find('abc', 1, true) and body:find('Legion', 1, true) and body:find('hexa_core · money', 1, true) and body:find('Mon serveur', 1, true))
    check('Couleur du niveau', body:find('15105570', 1, true) ~= nil)
    HTTP, HTTP_STATUS = {}, { 429 }
    Hexa.Log('money', 'Limité', 1)
    RunThreads(5000)
    check('429 Discord : renvoyé plus tard', #HTTP == 2 and HTTP[2].body:find('Limité', 1, true) ~= nil, #HTTP)
end

tests['S21b Logs : ancien réglage default accepté, URL invalide'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Logs = { default = 'https://d/ancien', webhook = 'pas une url', groupSeconds = 0 } }"
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/logs.lua' })
    check('webhook invalide : repli sur default', Hexa.Log('money', 'x') == true)
    RunThreads(3000)
    check('Envoyé à l’ancien réglage', #HTTP == 1 and HTTP[1].url == 'https://d/ancien')
    Hexa = nil
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Logs = { webhook = 'http://pas-https' } }"
    server()
    check('http:// refusé : pas de Discord', Hexa.Log('money', 'x') == false)
end

tests['S21c Logs : regroupement des identiques'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Logs = { webhook = 'https://d/s', groupSeconds = 10, maxPerMinute = 1000 } }"
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/logs.lua' })
    NewPlayer(1, { identifier = 'abc' }); NewPlayer(2, { identifier = 'def' })
    for _ = 1, 5 do Hexa.Log('money', 'Retrait', 1) end
    Hexa.Log('money', 'Retrait', 2)             -- autre joueur : pas regroupé
    Hexa.Log('money', 'Autre message', 1)       -- autre message : pas regroupé
    RunThreads(3000)
    check('1er de chaque groupe parti tout de suite : 3 messages', #HTTP == 3, #HTTP)
    RunThreads(12000)
    check('Résumé du groupe de 5 : « +4 identiques »', #HTTP == 4 and HTTP[4].body:find('+4 identique', 1, true) ~= nil, #HTTP)
    for _ = 1, 3 do Hexa.Log('money', 'Retrait', 1) end
    RunThreads(12000)
    check('Après la fenêtre : nouveau départ immédiat', #HTTP == 6 and HTTP[5].body:find('Retrait', 1, true) ~= nil and HTTP[6].body:find('+2 identique', 1, true) ~= nil, #HTTP)
end

tests['S21d Logs : limite par minute'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Logs = { webhook = 'https://d/s', groupSeconds = 0, maxPerMinute = 3, database = true } }"
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/logs.lua' })
    for i = 1, 8 do Hexa.Log('money', 'Log ' .. i) end
    RunThreads(5000)
    check('Seulement 3 envoyés', #HTTP == 3, #HTTP)
    check('Les 8 restent dans la base', #HexaLogs.queue == 8 or #HexaLogs.queue == 0)
    RunThreads(65000)
    check('Une minute plus tard : un résumé des 5 non envoyés', #HTTP == 4 and HTTP[4].body:find('5 log(s) non envoy', 1, true) ~= nil, #HTTP)
    for i = 1, 3 do Hexa.Log('money', 'Après ' .. i) end
    RunThreads(5000)
    check('Le compteur repart à zéro', #HTTP == 7, #HTTP)
end

tests['S21e Logs : fichier du jour'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Logs = { keepDays = 3, database = false } }"
    RESOURCE_NAME = 'hexa_core'
    RESOURCES.oxmysql = 'started'
    server(); load({ 'core/logs.lua' })
    NewPlayer(1, { identifier = 'abc' })
    Hexa.Log('money', 'Retrait de 500 $\nsur deux lignes', 1, { Lieu = 'Legion' }, 'warning')
    Hexa.Log('admin', 'Commande')
    RunThreads(5000)
    local name
    for key in pairs(FILES) do if key:find('^hexa_core/logs/jour_%d%d%.log$') then name = key end end
    check('Fichier logs/jour_NN.log créé', name ~= nil)
    local text = FILES[name]
    check('Première ligne : la date du jour', text:find('^# %d%d%d%d%-%d%d%-%d%d\n') ~= nil)
    check('Une ligne par log, retours à la ligne aplatis', text:find('[warning] [hexa_core/money] [abc] Retrait de 500 $ sur deux lignes', 1, true) and text:find('[hexa_core/admin]', 1, true))
    check('Champs en JSON', text:find('"Lieu":"Legion"', 1, true) ~= nil)
    check('Nombre de fichiers borné par keepDays', tonumber(name:match('jour_(%d%d)')) <= 3)
    -- Un fichier d'un autre jour est réécrit
    FILES[name] = '# 1999-01-01\nvieux log\n'
    Hexa.Log('money', 'Nouveau')
    RunThreads(5000)
    check('Autre date : réécrit, ancien contenu perdu', not FILES[name]:find('vieux log', 1, true) and FILES[name]:find('Nouveau', 1, true))
    -- Ajout à la suite le même jour
    Hexa.Log('money', 'Suite')
    RunThreads(5000)
    check('Même jour : ajouté à la suite', FILES[name]:find('Nouveau', 1, true) and FILES[name]:find('Suite', 1, true))
end

tests['S21f Logs : fichier désactivé, trop gros, dossier absent'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Logs = { file = false, database = false } }"
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/logs.lua' })
    Hexa.Log('money', 'x'); RunThreads(5000)
    local any; for key in pairs(FILES) do if key:find('logs/') then any = true end end
    check('file = false : aucun fichier', not any)
end

tests['S21g Logs : dossier absent'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Logs = { database = false } }"
    RESOURCE_NAME = 'hexa_core'
    FILES_READONLY = true
    server(); load({ 'core/logs.lua' })
    Hexa.Log('money', 'x'); RunThreads(5000)
    check('Écriture impossible : dit une fois', printed('hexa_core/logs'))
    PRINTS = {}
    Hexa.Log('money', 'y'); RunThreads(5000)
    check('… et pas de répétition', not printed('hexa_core/logs'))
    FILES_READONLY = nil
end

tests['S22 config_server.lua jamais envoyé aux joueurs'] = function()
    local f = io.open(ROOT_DIR .. '/fxmanifest.lua'); local manifest = f:read('a'); f:close()
    local files = manifest:match('files%s*(%b{})')
    check('Absent de files {}', files and not files:find('config_server', 1, true))
    check('config.lua sans webhook', not io.open(ROOT_DIR .. '/config.lua'):read('a'):find('discord', 1, true))
end

-- Événements, rappels, notifications ------------------------------------------------------------------
tests['S23 Connexion, déconnexion, métier, notification'] = function()
    server()
    local loaded, dropped, job
    Hexa.OnPlayerLoaded(function(src) loaded = src end)
    Hexa.OnPlayerDropped(function(src, reason) dropped = { src, reason } end)
    Hexa.OnJobChange(function(src, name, grade) job = { src, name, grade } end)
    if esx then
        Fire('esx:playerLoaded', nil, 5, {}, false)
        Fire('esx:setJob', nil, 5, { name = 'ambulance', grade = 2 }, {})
    else
        Fire('QBCore:Server:PlayerLoaded', nil, { PlayerData = { source = 5 } })
        Fire('QBCore:Server:OnJobUpdate', nil, 5, { name = 'ambulance', grade = { level = 2 } })
    end
    check('Connexion', loaded == 5)
    check('Changement de métier', job and job[1] == 5 and job[2] == 'ambulance' and job[3] == 2)
    Fire('playerDropped', 5, 'quit')
    check('Déconnexion', dropped and dropped[1] == 5 and dropped[2] == 'quit')
    Hexa.Notify(5, 'Bonjour', 'success')
    local n = ClientEventsFor(5, 'hexa_test:hexa:notify')
    check('Notification sous le nom de la ressource', n[1] and n[1].args[1] == 'Bonjour' and n[1].args[2] == 'success')
end

tests['S24 Rappels : réponse, erreurs, données invalides'] = function()
    server()
    NewPlayer(1)
    Hexa.Callback('echo', function(src, data) return { ok = true, src = src, value = data.value } end)
    Hexa.Callback('plain', function() return 42 end)
    Hexa.Callback('crash', function() error('boum') end)
    FromClient(1, 'hexa_test:hexa:request', 1, 'echo', { value = 'x' })
    FromClient(1, 'hexa_test:hexa:request', 2, 'plain', 'pas une table')
    FromClient(1, 'hexa_test:hexa:request', 3, 'crash', {})
    FromClient(1, 'hexa_test:hexa:request', 4, 'inconnu', {})
    FromClient(1, 'hexa_test:hexa:request', 'pas un nombre', 'echo', {})
    RunThreads(100)
    local r = {}
    for _, e in ipairs(ClientEventsFor(1, 'hexa_test:hexa:response')) do r[e.args[1]] = e.args[2] end
    check('Réponse au bon joueur', r[1] and r[1].ok and r[1].src == 1 and r[1].value == 'x')
    check('Valeur simple emballée', r[2] and r[2].ok and r[2].value == 42)
    check('Erreur du rappel : ok = false, affichée', r[3] and r[3].ok == false and #ERRORS == 0 and printed('boum'))
    check('Rappel inconnu', r[4] and r[4].error == 'unknown')
    check('Identifiant invalide ignoré', #ClientEventsFor(1, 'hexa_test:hexa:response') == 4)
end

tests['S25 Rappels : verrou anti double-clic'] = function()
    server()
    NewPlayer(1); NewPlayer(2)
    local runs = 0
    Hexa.Callback('withdraw', function() runs = runs + 1; Wait(50); return { ok = true } end, { lock = true })
    FromClient(1, 'hexa_test:hexa:request', 1, 'withdraw', {})
    FromClient(1, 'hexa_test:hexa:request', 2, 'withdraw', {})
    FromClient(2, 'hexa_test:hexa:request', 3, 'withdraw', {})
    RunThreads(200)
    local r = {}
    for _, src in ipairs({ 1, 2 }) do for _, e in ipairs(ClientEventsFor(src, 'hexa_test:hexa:response')) do r[e.args[1]] = e.args[2] end end
    check('Première traitée, deuxième refusée (busy)', r[1].ok and r[2].busy == true)
    check('Autre joueur non bloqué', r[3].ok and runs == 2)
    Hexa.Callback('boom', function() error('x') end, { lock = true })
    FromClient(1, 'hexa_test:hexa:request', 5, 'boom', {})
    FromClient(1, 'hexa_test:hexa:request', 6, 'withdraw', {})
    RunThreads(200)
    local last = ClientEventsFor(1, 'hexa_test:hexa:response')
    check('Verrou libéré même après une erreur', last[#last].args[1] == 6 and last[#last].args[2].ok)
end

tests['S26 Rappels : délai minimal'] = function()
    server()
    NewPlayer(1)
    Hexa.Callback('ping', function() return { ok = true } end, { cooldown = 300 })
    FromClient(1, 'hexa_test:hexa:request', 1, 'ping', {}); RunThreads(10)
    FromClient(1, 'hexa_test:hexa:request', 2, 'ping', {}); RunThreads(400)
    FromClient(1, 'hexa_test:hexa:request', 3, 'ping', {}); RunThreads(10)
    local r = {}
    for _, e in ipairs(ClientEventsFor(1, 'hexa_test:hexa:response')) do r[e.args[1]] = e.args[2] end
    check('Trop rapide : retry, puis accepté', r[1].ok and r[2].retry == true and r[3].ok)
    Fire('playerDropped', 1, 'quit')
    FromClient(1, 'hexa_test:hexa:request', 4, 'ping', {}); RunThreads(10)
    local last = ClientEventsFor(1, 'hexa_test:hexa:response')
    check('Déconnexion : délai effacé', last[#last].args[2].ok)
end

-- Outils -----------------------------------------------------------------------------------------------
tests['S27 Outils, langues, versions'] = function()
    server()
    check('Money', Hexa.Money(12500) == '12 500 $' and Hexa.Money(-1500) == '-1 500 $' and Hexa.Money(1000, '€') == '1 000 €')
    check('Amount', Hexa.Amount('50') == 50 and Hexa.Amount(0) == 0 and Hexa.Amount(-1) == nil and Hexa.Amount(1.5) == nil and Hexa.Amount(0 / 0) == nil and Hexa.Amount(10, 5) == nil)
    check('CleanText', Hexa.CleanText('  <b>Salut</b>  ') == '‹b›Salut‹/b›' and Hexa.CleanText('   ') == nil and Hexa.CleanText('ééé', 3) == 'é')
    check('IsWeapon', Hexa.IsWeapon('weapon_pistol') and not Hexa.IsWeapon('bread') and not Hexa.IsWeapon(nil))
    local a = { x = { y = 1 } }; local b = Hexa.Copy(a); b.x.y = 2
    check('Copy profonde', a.x.y == 1)
    local T = Hexa.Locale({ fr = { paid = 'Payé : %s.', only_fr = 'Seulement FR' }, en = { paid = 'Paid: %s.' } })
    check('Locale FR', T('paid', '5 $') == 'Payé : 5 $.' and T('absent') == 'absent')
    Hexa.Config.Locale = 'en'
    local E = Hexa.Locale({ fr = { paid = 'Payé : %s.', only_fr = 'Seulement FR' }, en = { paid = 'Paid: %s.' } })
    check('Locale EN, repli FR si traduction manquante', E('paid', '5 $') == 'Paid: 5 $.' and E('only_fr') == 'Seulement FR')
    check('VersionAtLeast', Hexa.VersionAtLeast('1.10.0', '1.9.2') and Hexa.VersionAtLeast('1.0.0', '1.0') and not Hexa.VersionAtLeast('1.0.0', '1.0.1'))
    check('RequireVersion OK', Hexa.RequireVersion('1.0.0'))
    check('RequireVersion trop récente : false + message', not Hexa.RequireVersion('2.0.0') and printed('2.0.0'))
end

-- Base SQL minimale pour hexa_players / hexa_characters / hexa_meta (les requêtes de ids.lua, reconnues par leur texte).
-- db.source : personnages du framework dans l'ordre où `ORDER BY` les rendra ; db.orderBy : colonne demandée.
local function idsDB(opts)
    opts = opts or {}
    local db = { players = {}, chars = {}, nextP = 1, nextC = 1, meta = {}, columns = opts.columns or {}, tables = opts.tables or {},
        source = opts.source or {}, queries = 0 }
    local function find(list, key, value) for id, row in pairs(list) do if row[key] == value then return id, row end end end
    db.find = find
    RESOURCES.oxmysql = 'started'
    MySQL = {
        query = { await = function(q, p) Wait(5)
            if q:find('AS identifier FROM', 1, true) then
                db.orderBy = q:match('ORDER BY `([%w_]+)`'); db.queries = db.queries + 1
                local rows = {}
                for i = (p[1] or 0) + 1, math.min(#db.source, (p[1] or 0) + 500) do rows[#rows + 1] = { identifier = db.source[i] } end
                return rows
            end
            return {}
        end },
        single = { await = function(q, p) Wait(5)
            if q:find('`deleted_at` IS NOT NULL AS gone', 1, true) then
                local id, row = find(db.chars, 'identifier', p[1])
                if not id then return nil end
                return { id = id, gone = row.deleted_at and 1 or 0 }
            end
            error('requête inconnue : ' .. q)
        end },
        update = { await = function(q, p) Wait(5)
            if q:find('INTO `hexa_players`', 1, true) then
                local id, row = find(db.players, 'license', p[1])
                if row then row.name = p[2] else db.players[db.nextP] = { license = p[1], name = p[2] }; db.nextP = db.nextP + 1 end
                return 1
            end
            if q:find('INSERT IGNORE INTO `hexa_characters`', 1, true) then
                for _, identifier in ipairs(p) do
                    if not find(db.chars, 'identifier', identifier) then db.chars[db.nextC] = { identifier = identifier }; db.nextC = db.nextC + 1 end
                end
                return 1
            end
            if q:find('SET `player_id`', 1, true) then
                local row = db.chars[p[2]]; if row and not row.player_id then row.player_id = p[1] end; return 1
            end
            if q:find('ADD COLUMN `deleted_at`', 1, true) then db.columns['hexa_characters.deleted_at'] = true; return 1 end
            if q:find('ADD COLUMN `former`', 1, true) then db.columns['hexa_characters.former'] = true; return 1 end
            if q:find('SET `former` = `identifier`', 1, true) then
                local row = db.chars[p[1]]; row.former = row.identifier; row.identifier = '#' .. p[1]; return 1
            end
            if q:find('SET `deleted_at` = CURRENT_TIMESTAMP', 1, true) then db.chars[p[1]].deleted_at = true; return 1 end
            if q:find('DELETE FROM `hexa_characters`', 1, true) then db.chars[p[1]] = nil; return 1 end
            if q:find('UPDATE `hexa_players` SET `last_seen`', 1, true) then db.players[p[1]].last_seen = NOW; return 1 end
            if q:find('INTO `hexa_meta`', 1, true) then db.meta[p[1]] = p[2]; return 1 end
            error('requête inconnue : ' .. q)
        end },
        scalar = { await = function(q, p) Wait(5)
            if q:find('information_schema.COLUMNS', 1, true) then return db.columns[p[1] .. '.' .. p[2]] and 1 or 0 end
            if q:find('information_schema.TABLES', 1, true) then return db.tables[p[1]] and 1 or 0 end
            if q:find('FROM `hexa_meta`', 1, true) then return db.meta[p[1]] end
            if q:find('UNIX_TIMESTAMP', 1, true) then local row = db.players[p[1]]; return row and row.last_seen end
            if q:find('FROM `hexa_players` WHERE `license`', 1, true) then return (find(db.players, 'license', p[1])) end
            if q:find('COALESCE', 1, true) then local row = db.chars[p[1]]; return row and (row.former or row.identifier) end
            if q:find('`identifier` = ? AND `deleted_at` IS NULL', 1, true) then
                local id, row = find(db.chars, 'identifier', p[1]); return (id and not row.deleted_at) and id or nil
            end
            if q:find('SELECT `id` FROM `hexa_characters`', 1, true) then return (find(db.chars, 'identifier', p[1])) end
            error('requête inconnue : ' .. q)
        end },
    }
    return db
end

tests['S29 IDs permanents joueur / personnage'] = function()
    local db = idsDB()
    -- hexa_core lui-même
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'ids.lua' })
    RESOURCE_EXPORTS.hexa_core = EXPORTS
    NewPlayer(1, { identifier = 'charA', license = 'license:aaa' })   -- déjà connecté au démarrage
    RunThreads(2000)
    check('Joueur déjà connecté : IDs au démarrage', Hexa.PlayerId(1) == 1 and Hexa.CharId(1) == 1, tostring(Hexa.PlayerId(1)) .. '/' .. tostring(Hexa.CharId(1)))
    check('State bags pour le client', STATEBAGS[1].hexaPlayerId == 1 and STATEBAGS[1].hexaCharId == 1)

    -- nouveau joueur : connexion puis choix du personnage
    NewPlayer(2, { identifier = 'charB', license = 'license:bbb' })
    Fire('playerJoining', 2); RunThreads(500)
    check('ID joueur dès la connexion, pas encore de personnage', Hexa.PlayerId(2) == 2 and Hexa.CharId(2) == nil)
    local function loaded(src)
        if esx then Fire('esx:playerLoaded', nil, src, {}, false) else Fire('QBCore:Server:PlayerLoaded', nil, { PlayerData = { source = src } }) end
        RunThreads(500)
    end
    loaded(2)
    check('ID personnage après chargement', Hexa.CharId(2) == 2)
    check('Personnage relié au joueur', db.chars[2].player_id == 2)

    -- changement de personnage (multicharacter)
    if esx then Fire('esx:playerLogout', nil, 2) else Fire('QBCore:Server:OnPlayerUnload', nil, 2) end
    check('Déconnexion du personnage : ID effacé', Hexa.CharId(2) == nil and STATEBAGS[2].hexaCharId == nil and Hexa.PlayerId(2) == 2)
    PLAYERS[2].identifier = 'charB2'; PLAYERS[2].data.citizenid = 'charB2'
    loaded(2)
    check('Second personnage : nouvel ID, même joueur', Hexa.CharId(2) == 3 and Hexa.PlayerId(2) == 2 and db.chars[3].player_id == 2)

    -- reconnexion du même compte sous un autre numéro de console, avec son 1er personnage
    Fire('playerDropped', 2, 'quit'); PLAYERS[2] = nil
    check('Départ : IDs oubliés', Hexa.PlayerId(2) == nil and Hexa.SourceOfCharId(3) == nil)
    NewPlayer(7, { identifier = 'charB', license = 'license:bbb' })
    Fire('playerJoining', 7); loaded(7)
    check('Mêmes IDs qu’avant (jamais réattribués)', Hexa.PlayerId(7) == 2 and Hexa.CharId(7) == 2, tostring(Hexa.PlayerId(7)) .. '/' .. tostring(Hexa.CharId(7)) .. ' ' .. table.concat(PRINTS, ' / '))
    check('Pas de doublon en base', db.nextP == 3 and db.nextC == 4)

    check('Recherche inverse', Hexa.SourceOfPlayerId(2) == 7 and Hexa.SourceOfCharId('1') == 1 and Hexa.SourceOfCharId(99) == nil)
    check('Hors ligne : identifier <-> ID', inThread(function() return Hexa.CharIdOf('charB2') end) == 3 and inThread(function() return Hexa.IdentifierOfCharId(3) end) == 'charB2')
end

tests['S30 IDs vus depuis une autre ressource'] = function()
    server()
    NewPlayer(1)
    check('hexa_core absent : nil, sans erreur', Hexa.PlayerId(1) == nil and Hexa.CharId(1) == nil)
    RESOURCE_EXPORTS.hexa_core = { GetPlayerId = function() return 12 end, GetCharId = function() return 31 end }
    check('Lu via hexa_core', Hexa.PlayerId(1) == 12 and Hexa.CharId(1) == 31)
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Logs = { default = 'https://d/x' } }"
    Hexa = nil; server(); load({ 'core/logs.lua' })
    Hexa.Log('money', 'x', 1); RunThreads(100)
    check('Les logs affichent #joueur / #personnage', HTTP[1] and HTTP[1].body:find('#12 / #31', 1, true) ~= nil)
end

tests['C05 IDs côté client'] = function()
    client()
    LocalPlayer.state.hexaPlayerId, LocalPlayer.state.hexaCharId = 12, 31
    check('PlayerId / CharId', Hexa.PlayerId() == 12 and Hexa.CharId() == 31)
end

tests['S31 Identité du personnage'] = function()
    server()
    NewPlayer(1, { charName = 'Ana Silva', birthdate = '1995-04-12', sex = 'f' })
    NewPlayer(2, { charName = 'Rui' })
    local a, b = Hexa.Identity(1), Hexa.Identity(2)
    check('Prénom, nom, naissance, sexe', a.firstname == 'Ana' and a.lastname == 'Silva' and a.birthdate == '1995-04-12' and a.sex == 'f', tostring(a.sex))
    check('Champs inconnus : nil', b.firstname == 'Rui' and b.birthdate == nil and b.sex == nil)
    check('Joueur inconnu : nil', Hexa.Identity(99) == nil)
    check('Sans taille, lieu ni nationalité : nil', b.height == nil and b.birthplace == nil and b.nationality == nil)
    NewPlayer(3, { charName = 'Léa Costa', meta = { height = 168, birthplace = 'Sandy Shores', nationality = 'Portugaise' } })
    local c = Hexa.Identity(3)
    check('Taille, lieu de naissance, nationalité (métadonnées)', c.height == 168 and c.birthplace == 'Sandy Shores' and c.nationality == 'Portugaise',
        tostring(c.height) .. ' ' .. tostring(c.nationality))
end

tests['C06 Points d’interaction : repli si hexa_core ne répond pas'] = function()
    client()
    local opened = 0
    local id = Hexa.AddPoint({ coords = vector3(10, 0, 0), label = 'Ouvrir', distance = 2.0, onSelect = function() opened = opened + 1 end })
    local hidden = Hexa.AddPoint({ coords = vector3(10, 0, 0), label = 'Caché', onSelect = function() opened = opened + 100 end, canInteract = function() return false end })
    -- sans hexa_interact : marqueur + touche E
    CLIENT_COORDS = vector3(50, 0, 0); RunThreads(1500)
    check('Loin : pas de marqueur', (MARKERS or 0) == 0)
    CLIENT_COORDS = vector3(11, 0, 0); RunThreads(1500); CONTROLS[38] = true; RunThreads(1); CONTROLS[38] = false; RunThreads(10)
    check('Proche : marqueur, aide, E ouvre ; point masqué ignoré', (MARKERS or 0) > 0 and opened == 1, opened)
    local helpText
    for _, n in ipairs(NATIVES) do if n.name == 'AddTextComponentSubstringPlayerName' then helpText = n.args[1] end end
    check('Aide : touche indiquée devant le libellé', helpText == '~INPUT_PICKUP~ Ouvrir', helpText)
    -- avec hexa_interact (toujours en repli) : zone enregistrée, plus de marqueur
    local zones, removed = {}, {}
    RESOURCES.hexa_interact = 'started'
    RESOURCE_EXPORTS.hexa_interact = {
        AddSphereZone = function(zone, option) zones[zone.name] = option end,
        RemoveZone = function(name) removed[#removed + 1] = name end,
    }
    local third = Hexa.AddPoint({ coords = vector3(10, 0, 0), label = 'Zone', onSelect = function() opened = opened + 1 end, canInteract = function() return false end })
    local zone = zones['hexa_test:point:' .. third]
    check('Zone hexa_interact', zone and zone.label == 'Zone' and zone.canInteract() == false)
    local before = opened
    zone.onSelect(); RunThreads(10)
    check('Sélection dans hexa_interact', opened == before + 1)
    MARKERS = 0; RunThreads(1500)
    check('Plus de marqueur avec hexa_interact', MARKERS == 0)
    check('Retrait', Hexa.RemovePoint(third) and removed[1] == 'hexa_test:point:' .. third and not Hexa.RemovePoint(third))
    check('Sans coords : erreur claire', not pcall(Hexa.AddPoint, { onSelect = function() end }))
end

tests['S28 Double inclusion sans effet'] = function()
    server()
    local first = Hexa.GetPlayer
    server()
    check('Fonctions inchangées', Hexa.GetPlayer == first)
end

-- Client -----------------------------------------------------------------------------------------------
tests['C01 Request : aller-retour, délai dépassé, retry'] = function()
    client()
    SERVER_REPLY = function(name, id, cb, data)
        SetTimeout(30, function() TriggerEvent('hexa_test:hexa:response', id, { ok = true, echo = data.v, cb = cb }) end)
    end
    local r = inThread(function() return Hexa.Request('deposit', { v = 5 }) end)
    check('Réponse reçue', r and r.ok and r.echo == 5 and r.cb == 'deposit')
    SERVER_REPLY = nil
    r = inThread(function() return Hexa.Request('lent', {}, 1000) end)
    check('Sans réponse : timeout', r.ok == false and r.timeout == true)
    local tries = 0
    SERVER_REPLY = function(name, id)
        tries = tries + 1
        local result = tries < 3 and { ok = false, retry = true } or { ok = true }
        SetTimeout(5, function() TriggerEvent('hexa_test:hexa:response', id, result) end)
    end
    r = inThread(function() return Hexa.Request('ping') end)
    check('Retry automatique puis succès', r.ok and tries == 3)
end

tests['C02 Notifications : ordre de priorité'] = function()
    client()
    TriggerEvent('hexa_test:hexa:notify', 'Salut', 'error')
    local function last(name) for i = #LOCAL_EVENTS, 1, -1 do if LOCAL_EVENTS[i].name == name then return LOCAL_EVENTS[i] end end end
    if esx then check('ESX : esx:showNotification', last('esx:showNotification').args[1] == 'Salut')
    else check('QB/QBox : QBCore:Notify type error', last('QBCore:Notify').args[2] == 'error') end
    local shown
    RESOURCES.hexa_notify = 'started'
    RESOURCE_EXPORTS.hexa_notify = { Notify = function(data) shown = data end }
    Hexa.Notify('Via hexa_notify', 'success')
    check('hexa_notify prioritaire', shown and shown.message == 'Via hexa_notify' and shown.type == 'success')
    local own
    Hexa.SetNotify(function(message) own = message; return true end)
    shown = nil
    Hexa.Notify('Interface')
    check('Affichage de la ressource prioritaire', own == 'Interface' and shown == nil)
    Hexa.SetNotify(function() return false end)
    Hexa.Notify('Repli')
    check('Repli si la ressource ne gère pas', shown and shown.message == 'Repli')
end

tests['C03 Joueur chargé, métier'] = function()
    CLIENT_LOADED = true
    LocalPlayer.state.isLoggedIn = true
    client()
    local count, jobs = 0, {}
    Hexa.OnPlayerLoaded(function() count = count + 1 end)
    Hexa.OnJobChange(function(name, grade) jobs[#jobs + 1] = { name, grade } end)
    RunThreads(1000)
    check('Déjà chargé au redémarrage', Hexa.loaded and count == 1)
    local unloaded = false
    Hexa.OnPlayerUnloaded(function() unloaded = true end)
    TriggerEvent(esx and 'esx:onPlayerLogout' or 'QBCore:Client:OnPlayerUnload')
    RunThreads(10)
    check('Déconnexion du personnage', unloaded and not Hexa.loaded)
    TriggerEvent(esx and 'esx:playerLoaded' or 'QBCore:Client:OnPlayerLoaded')
    RunThreads(10)
    check('Rechargement', Hexa.loaded and count == 2)
    if esx then TriggerEvent('esx:setJob', { name = 'ambulance', grade = 1 }, {})
    else TriggerEvent('QBCore:Client:OnJobUpdate', { name = 'ambulance', grade = { level = 1 } }) end
    RunThreads(10)
    check('Changement de métier (valeur de l’événement)', jobs[1] and jobs[1][1] == 'ambulance' and jobs[1][2] == 1)
    local name, grade, label = Hexa.Job()
    check('Hexa.Job', name == 'police' and grade == 2 and label == 'LSPD', tostring(name) .. ' ' .. tostring(grade))
    check('Hexa.HasJob', Hexa.HasJob('police', 2) and not Hexa.HasJob('police', 3))
end

tests['C04 Mort, plaque, aide, blip'] = function()
    client()
    check('Vivant', not Hexa.IsDead())
    CLIENT_DEAD = true
    check('Mort', Hexa.IsDead())
    CLIENT_DEAD = false
    if not esx then CLIENT_DATA.metadata.inlaststand = true; check('QB/QBox : à terre', Hexa.IsDead()) end
    check('Plaque normalisée', Hexa.GetPlate(55) == 'AB 123' and Hexa.GetPlate(0) == nil and Hexa.GetPlate(12) == nil)
    Hexa.Help('Appuyez sur E')
    check('Aide affichée', NATIVES[#NATIVES].name == 'EndTextCommandDisplayHelp')
    -- hexa_core répond : son panneau, pas l'aide de GTA, et pas à chaque image
    local pulses = {}
    RESOURCE_EXPORTS.hexa_core = { PulseHelp = function(text) pulses[#pulses + 1] = text end }
    local natives = #NATIVES
    for _ = 1, 5 do Hexa.Help('Appuyez sur ~INPUT_PICKUP~') ; NOW = NOW + 16 end
    check('Aide dans le panneau Hexa', #pulses == 1 and pulses[1] == 'Appuyez sur ~INPUT_PICKUP~' and #NATIVES == natives, #pulses)
    NOW = NOW + 100; Hexa.Help('Appuyez sur ~INPUT_PICKUP~')
    check('Renvoyée régulièrement (sinon elle s’efface)', #pulses == 2)
    Hexa.Help('Autre texte')
    check('Nouveau texte envoyé tout de suite', #pulses == 3)
    RESOURCE_EXPORTS.hexa_core = {}
    NOW = NOW + 200; Hexa.Help('Appuyez sur E')
    check('hexa_core ne répond pas : aide de GTA', NATIVES[#NATIVES].name == 'EndTextCommandDisplayHelp' and #NATIVES > natives)
    local blip = Hexa.Blip(vector3(1, 2, 3), { sprite = 108, label = 'Banque' })
    local names = {}
    for _, n in ipairs(NATIVES) do names[n.name] = n.args end
    check('Blip créé et nommé', blip == 77 and names.SetBlipSprite[2] == 108 and names.EndTextCommandSetBlipName ~= nil)
end

-- 1.4.0 : ressource hexa_core côté client (dialogues, compatibilité, points) ----------------------------
local function coreClient()
    RESOURCE_NAME = 'hexa_core'
    load({ 'shared.lua', 'client.lua', 'core/dialog.lua', 'core/compat.lua', 'core/points.lua' })
    RESOURCE_EXPORTS.hexa_core = EXPORTS
    RunThreads(10)
end
-- Lance fn dans un thread ; renvoie une fonction qui donne (fini, résultat).
local function async(fn)
    local box = {}
    CreateThread(function() box.value = table.pack(fn()); box.done = true end)
    RunThreads(10)
    return function() RunThreads(10); if not box.value then return box.done end return box.done, table.unpack(box.value, 1, box.value.n) end
end
local function v(o, raw) return HexaDialog.validate(HexaDialog.normalize(o), raw) end

tests['C07 Dialogues : montants et nombres'] = function()
    coreClient()
    local o = { type = 'amount', max = 5000 }
    check('« 1 500 » → 1500 (entier)', v(o, '1 500') == 1500 and math.type(v(o, '1 500')) == 'integer')
    check('Avec le symbole « 250 $ »', v(o, '250 $') == 250)
    check('Espace insécable', v(o, '1\194\160500') == 1500)
    local _, e = v(o, '0'); check('0 refusé (minimum 1 par défaut)', e == 'Minimum : 1.', e)
    _, e = v(o, '1,5'); check('Décimal refusé', e == 'Entrez un nombre entier.', e)
    _, e = v(o, '6000'); check('Maximum lisible', e == 'Maximum : 5 000.', e)
    _, e = v(o, '0x10'); check('Hexadécimal refusé', e == 'Entrez un nombre.', e)
    _, e = v(o, '1e9'); check('Notation scientifique refusée', e == 'Entrez un nombre.', e)
    _, e = v(o, '  '); check('Vide : obligatoire', e == 'Ce champ est obligatoire.', e)
    check('Plafond 2 147 483 647', v({ type = 'amount' }, '2147483648') == nil)
    check('Nombre : « -2,5 »', v({ type = 'number' }, '-2,5') == -2.5)
    check('Nombre : bornes', v({ type = 'number', min = -10, max = 10 }, '11') == nil and v({ type = 'number', min = -10 }, '-10') == -10)
    check('Nombre facultatif vide : nil sans erreur', select('#', v({ type = 'number', required = false }, '')) >= 0 and v({ type = 'number', required = false }, '') == nil
        and select(2, v({ type = 'number', required = false }, '')) == nil)
end

tests['C08 Dialogues : texte, liste, date, case à cocher'] = function()
    coreClient()
    check('Texte nettoyé', v({}, '  Jean   Dupont ') == 'Jean Dupont')
    check('Zone de texte : lignes gardées', v({ type = 'textarea' }, 'a\nb ') == 'a\nb')
    local _, e = v({ min = 3 }, 'ab'); check('Trop court', e == 'Au moins 3 caractères.', e)
    check('Accents : un caractère chacun', v({ max = 4 }, 'Ééàç') == 'Ééàç')
    check('Texte facultatif vide', v({ required = false }, '') == '')
    local list = { type = 'select', options = { { value = 'speed', label = 'Vitesse' }, 'Feu rouge', { value = 12, label = 'Douze' } } }
    check('Liste : valeur de l’option choisie', v(list, 1) == 'speed' and v(list, 2) == 'Feu rouge' and v(list, 3) == 12)
    _, e = v(list, 0); check('Liste : rien choisi', e == 'Ce champ est obligatoire.', e)
    _, e = v(list, 9); check('Liste : option inexistante refusée', e == 'Choisissez dans la liste.', e)
    _, e = v(list, 'speed'); check('Liste : valeur envoyée directement refusée', e == 'Choisissez dans la liste.', e)
    check('Date valide', v({ type = 'date' }, '2024-02-29') == '2024-02-29')
    _, e = v({ type = 'date' }, '2026-02-29'); check('29 février d’une année non bissextile', e == 'Date invalide.', e)
    _, e = v({ type = 'date' }, '2026/11/06'); check('Format inattendu', e == 'Date invalide.', e)
    check('JJ/MM/AAAA → AAAA-MM-JJ', v({ type = 'date' }, '06/11/2026') == '2026-11-06' and v({ type = 'date' }, '6/1/2026') == '2026-01-06')
    _, e = v({ type = 'date' }, '31/04/2026'); check('31 avril refusé', e == 'Date invalide.', e)
    _, e = v({ type = 'date', min = '2026-01-01' }, '2025-12-31'); check('Avant le minimum', e == 'Au plus tôt le 01/01/2026.', e)
    _, e = v({ type = 'date', max = '2026-12-31' }, '2027-01-01'); check('Après le maximum', e == 'Au plus tard le 31/12/2026.', e)
    check('Case cochée / décochée', v({ type = 'checkbox' }, true) == true and v({ type = 'checkbox' }, false) == false)
    _, e = v({ type = 'checkbox', required = true }, false); check('Case obligatoire', e == 'Cochez cette case pour continuer.', e)
    check('Case : seul true compte', v({ type = 'checkbox' }, 'true') == false)
    check('Date par défaut affichée en JJ/MM/AAAA', (function()
        CreateThread(function() EXPORTS.Form({ { type = 'date', default = '2026-11-06' } }) end); RunThreads(10)
        local f = LastNui('open').fields[1]; EXPORTS.CloseDialog(); RunThreads(10)
        return f.default == '06/11/2026' end)())
end

tests['C18 Dialogues en anglais'] = function()
    CONFIG_OVERRIDE = "HexaConfig = { Locale = 'en' }"
    coreClient()
    local _, e = v({ type = 'amount', max = 5000 }, '6,000')
    check('« 6,000 » = six mille', e == 'Maximum: 5,000.', e)
    check('Date MM/DD/YYYY', v({ type = 'date' }, '11/06/2026') == '2026-11-06')
    _, e = v({ type = 'date', min = '2026-12-01' }, '11/06/2026'); check('Date lisible en anglais', e == 'No earlier than 12/01/2026.', e)
end

tests['C09 Dialogues : formulaire complet'] = function()
    coreClient()
    local result = async(function() return EXPORTS.Form({
        { type = 'select', name = 'motif', label = 'Motif', options = { { value = 'speed', label = 'Vitesse' }, 'Feu rouge' } },
        { type = 'amount', name = 'montant', min = 50, max = 5000 },
        { type = 'date', name = 'date', min = '2026-01-01', max = '2026-12-31' },
        { type = 'checkbox', name = 'copie', label = 'Copie', default = true },
        { type = 'checkbox', name = 'accord', label = 'J’accepte', required = true },
        { type = 'textarea', name = 'note', required = false },
    }, { title = 'Amende', description = 'Contravention' }) end)
    local m = LastNui('open')
    check('Ouvert : formulaire de 6 champs', m and m.kind == 'form' and #m.fields == 6 and m.title == 'Amende' and m.description == 'Contravention')
    check('Liste : libellés seulement, rien choisi', m.fields[1].options[1] == 'Vitesse' and m.fields[1].default == 0 and m.fields[1].placeholder == 'Choisir…')
    check('Indications', m.fields[2].hint == 'Entre 50 et 5 000 $' and m.fields[3].hint == 'Entre 01/01/2026 et 31/12/2026' and m.fields[3].placeholder == 'JJ/MM/AAAA')
    check('Case cochée par défaut', m.fields[4].default == true and m.fields[6].required == false and m.fields[6].multiline == true)
    check('Focus clavier et souris', FOCUS[1] and FOCUS[2])
    local r = Nui('submit', { values = { 0, '20', '30/02/2026', true, false, '' } })
    local idx = {}
    for _, err in ipairs(r.errors or {}) do idx[#idx + 1] = err.index end
    check('Toutes les erreurs d’un coup, par champ', r.ok == false and table.concat(idx, ',') == '1,2,3,5', table.concat(idx, ','))
    check('Boîte toujours ouverte', EXPORTS.IsDialogOpen())
    r = Nui('submit', { values = { 2, '1 200', '06/11/2026', false, true, '  ligne  ' } })
    local done, values = result()
    check('Valeurs par nom', r.ok and done and values.motif == 'Feu rouge' and values.montant == 1200 and values.date == '2026-11-06'
        and values.copie == false and values.accord == true and values.note == 'ligne')
    check('… et par position', values[1] == 'Feu rouge' and values[2] == 1200 and values[5] == true)
    check('Fermé, focus rendu', not EXPORTS.IsDialogOpen() and FOCUS[1] == false and NUI[#NUI].action == 'close')
    check('Formulaire vide : nil, rien ouvert', select(2, async(function() return EXPORTS.Form({}) end)()) == nil and not EXPORTS.IsDialogOpen())
end

tests['C10 Dialogues : saisie simple, confirmation, une à la fois'] = function()
    coreClient()
    local result = async(function() return Hexa.Input({ title = 'Retrait', label = 'Montant', type = 'amount', max = 5000, default = 100 }) end)
    local m = LastNui('open')
    check('Hexa.Input : un champ', #m.fields == 1 and m.title == 'Retrait' and m.fields[1].label == 'Montant' and m.fields[1].default == '100' and m.fields[1].unit == '$')
    check('Une seule boîte à la fois', select(2, async(function() return Hexa.Input('Autre') end)()) == nil)
    local r = Nui('submit', { values = { '9000' } })
    check('Erreur renvoyée à la page', r.ok == false and r.errors[1].error == 'Maximum : 5 000.')
    Nui('submit', { values = { '1 200' } })
    local done, value = result()
    check('Valeur directe (pas une table)', done and value == 1200)
    result = async(function() return Hexa.Input('Plaque') end)
    Nui('cancel')
    done, value = result()
    check('Annuler → nil', done and value == nil)
    result = async(function() return Hexa.Confirm({ title = 'Vendre ?', message = 'Définitif.', danger = true, confirm = 'Vendre' }) end)
    m = LastNui('open')
    check('Confirmation', m.kind == 'confirm' and m.danger == true and m.submitLabel == 'Vendre' and m.texts.no == 'Non')
    Nui('submit', {})
    done, value = result()
    check('Oui → true', done and value == true)
    result = async(function() return Hexa.Confirm('Sûr ?') end)
    Nui('cancel')
    done, value = result()
    check('Non → false', done and value == false)
    result = async(function() return Hexa.Confirm('Sûr ?') end)
    EXPORTS.CloseDialog()
    done, value = result()
    check('Fermée par une ressource → false', done and value == false)
    check('Submit sans boîte : sans effet', Nui('submit', { values = { 'x' } }).ok == false)
end

tests['C11 Aide à l’écran'] = function()
    coreClient()
    BUTTONS[51] = 't_E'
    Hexa.ShowHelp('Appuyez sur ~INPUT_CONTEXT~ pour entrer : ~g~Shop~s~')
    local m = LastNui('help')
    check('~INPUT_CONTEXT~ → [E], couleurs retirées', m.text == 'Appuyez sur [E] pour entrer : Shop', m.text)
    check('Position par défaut', m.position == 'left')
    local count = #NUI
    Hexa.ShowHelp('Appuyez sur ~INPUT_CONTEXT~ pour entrer : ~g~Shop~s~')
    check('Même texte : rien renvoyé', #NUI == count)
    BUTTONS[51] = 't_F'; Hexa.ShowHelp('~INPUT_CONTEXT~ Ouvrir')
    check('Touche choisie par le joueur', LastNui('help').text == '[F] Ouvrir')
    BUTTONS[51] = 'b_1015'; Hexa.ShowHelp('~INPUT_CONTEXT~ Ouvrir')
    check('Souris / manette : touche par défaut', LastNui('help').text == '[E] Ouvrir')
    RunThreads(2000)
    check('ShowHelp reste affichée', EXPORTS.IsHelpVisible())
    Hexa.HideHelp()
    check('HideHelp', not EXPORTS.IsHelpVisible())
    for _ = 1, 5 do Hexa.Help('[E] Garage'); RunThreads(100) end
    local n = 0 for _, x in ipairs(NUI) do if x.text == '[E] Garage' then n = n + 1 end end
    check('Hexa.Help en boucle : un seul envoi à la page', n == 1, n)
    RunThreads(600)
    check('Hexa.Help : disparaît seule', not EXPORTS.IsHelpVisible())
end

tests['C12 Compatibilité ESX'] = function()
    if not esx then
        coreClient()
        check('Hors ESX : pas de lecture de l’aide ESX', (function() LABELS.esxHelpNotification = 'x'; RunThreads(200); return LABELS.esxHelpNotification == 'x' end)())
        return
    end
    -- ESX.UI.Menu minimal, comme es_extended
    local types, opened = {}, {}
    ESX.notified = {}
    ESX.ShowNotification = function(msg) ESX.notified[#ESX.notified + 1] = msg end
    ESX.UI = { Menu = {
        RegisterType = function(kind, open, close) types[kind] = { open = open, close = close } end,
        Open = function(kind, namespace, name, data, submit, cancel)
            local menu = { submit = submit, cancel = cancel }
            menu.close = function() types[kind].close(namespace, name); opened[kind .. namespace .. name] = nil end
            opened[kind .. namespace .. name] = menu
            types[kind].open(namespace, name, data)
            return menu
        end,
        GetOpened = function(kind, namespace, name) return opened[kind .. namespace .. name] end,
    } }
    coreClient()
    check('esx_menu_dialog remplacé', types.dialog ~= nil)
    local got = {}
    local function openDialog(data)
        got = {}
        return ESX.UI.Menu.Open('dialog', 'shop', 'amount', data,
            function(d, menu) got.submit = d; menu.close() end, function(d, menu) got.cancel = d; menu.close() end)
    end
    openDialog({ title = 'Quantité' }); RunThreads(10)
    check('Boîte Hexa ouverte', LastNui('open').title == 'Quantité' and EXPORTS.IsDialogOpen())
    Nui('submit', { values = { '12.6' } }); RunThreads(10)
    check('Nombre arrondi comme avant', got.submit and got.submit.value == 13 and not EXPORTS.IsDialogOpen())
    openDialog({ title = 'Quantité' }); RunThreads(10)
    Nui('submit', { values = { '-3' } }); RunThreads(10)
    check('Négatif refusé, boîte rouverte', #ESX.notified == 1 and EXPORTS.IsDialogOpen() and got.submit == nil)
    Nui('submit', { values = { 'Bonjour' } }); RunThreads(10)
    check('Texte transmis', got.submit and got.submit.value == 'Bonjour')
    openDialog({ title = 'Note', type = 'big', value = 'brouillon' }); RunThreads(10)
    check('Type « big » : zone de texte', LastNui('open').fields[1].multiline == true and LastNui('open').fields[1].default == 'brouillon')
    Nui('cancel'); RunThreads(10)
    check('Annuler → cancel', got.cancel ~= nil and got.submit == nil)
    local menu = openDialog({ title = 'Première' }); RunThreads(10)
    menu.close()
    openDialog({ title = 'Seconde' }); RunThreads(10)
    check('Fermer puis rouvrir : la nouvelle reste ouverte', EXPORTS.IsDialogOpen() and LastNui('open').title == 'Seconde' and got.cancel == nil)
    Nui('submit', { values = { '5' } }); RunThreads(10)
    check('… et répond au script', got.submit and got.submit.value == 5)

    -- esx_textui
    local fn
    TriggerEvent('__cfx_export_esx_textui_TextUI', function(f) fn = f end)
    fn('[E] Coffre', 'error')
    check('exports.esx_textui:TextUI', LastNui('help').text == '[E] Coffre' and LastNui('help').kind == 'error')
    TriggerEvent('__cfx_export_esx_textui_HideUI', function(f) fn = f end)
    fn()
    check('exports.esx_textui:HideUI', not EXPORTS.IsHelpVisible())

    -- ESX.ShowHelpNotification : lu dans l'entrée de texte d'ESX, aide de GTA masquée
    BUTTONS[51] = 't_E'
    for _ = 1, 10 do LABELS.esxHelpNotification = 'Appuyez sur ~INPUT_CONTEXT~ pour ouvrir'; RunThreads(16) end
    check('ShowHelpNotification → panneau Hexa', LastNui('help').text == 'Appuyez sur [E] pour ouvrir', LastNui('help').text)
    check('Aide de GTA masquée', HIDDEN_HELP > 0 and CLEARED_HELP == 1, CLEARED_HELP)
    RunThreads(500)
    check('Le script arrête : l’aide disparaît', not EXPORTS.IsHelpVisible())
end

tests['C13 Compatibilité désactivable, qb-input'] = function()
    CONFIG_OVERRIDE = "HexaConfig = { Dialog = { Redirect = { esx = false, qb = false } } }"
    coreClient()
    LABELS.esxHelpNotification = 'x'; RunThreads(100)
    check('ESX désactivé : aide ESX laissée telle quelle', LABELS.esxHelpNotification == 'x')
    check('esx_textui non fourni', HANDLERS['__cfx_export_esx_textui_TextUI'] == nil)
    check('qb-input non fourni', HANDLERS['__cfx_export_qb-input_ShowInput'] == nil)
end

tests['C14 qb-input redirigé'] = function()
    coreClient()
    local fn
    TriggerEvent('__cfx_export_qb-input_ShowInput', function(f) fn = f end)
    check('exports[\'qb-input\']:ShowInput fourni', type(fn) == 'function')
    local result = async(function() return fn({ header = 'Véhicule', submitText = 'OK', inputs = {
        { text = 'Plaque', name = 'plate', type = 'text', isRequired = true },
        { text = 'Couleur', name = 'color', type = 'select', options = { { value = 'red', text = 'Rouge' }, { value = 'blue', text = 'Bleu' } } },
        { text = 'Options', name = 'opts', type = 'checkbox', options = { { value = 'tint', text = 'Vitres', checked = true }, { value = 'neon', text = 'Néons' } } },
        { text = 'Places', name = 'seats', type = 'number' },
    } }) end)
    local m = LastNui('open')
    check('Titre, bouton, 5 champs (2 cases)', m.title == 'Véhicule' and m.submitLabel == 'OK' and #m.fields == 5 and m.fields[3].default == true)
    Nui('submit', { values = { 'AB12', 2, true, false, '4' } })
    local done, r = result()
    check('Réponse au format qb-input (textes)', done and r.plate == 'AB12' and r.color == 'blue' and r.tint == 'true' and r.neon == 'false' and r.seats == '4')
end

tests['C15 Points d’intérêt centralisés'] = function()
    coreClient()
    local opened, checks = {}, 0
    INVOKER = 'res_a'
    local a = EXPORTS.AddPoint({ coords = vector3(10, 0, 0), label = 'Garage', onSelect = function() opened[#opened + 1] = 'a' end,
        canInteract = function() checks = checks + 1; return true end })
    INVOKER = 'res_b'
    local b = EXPORTS.AddPoint({ coords = vector3(10, 1, 0), label = 'Coffre', key = 47, help = '[G] Coffre', onSelect = function() opened[#opened + 1] = 'b' end,
        marker = { type = 2, size = 0.5, color = { 255, 0, 0, 200 } } })
    INVOKER = nil
    check('Numéros distincts pour deux ressources', a and b and a ~= b)
    CLIENT_COORDS = vector3(50, 0, 0); MARKERS = 0; RunThreads(1500)
    check('Loin : rien', MARKERS == 0 and checks == 0)
    CLIENT_COORDS = vector3(10.5, 0, 0); RunThreads(1000)
    check('Proche : marqueurs', MARKERS > 0)
    check('canInteract demandé 4 fois par seconde au plus', checks >= 3 and checks <= 5, checks)
    BUTTONS[38] = 't_E'
    check('Aide de la ressource, ou « [E] » + libellé', (function()
        for i = #NUI, 1, -1 do if NUI[i].action == 'help' then return NUI[i].text == '[E] Garage' or NUI[i].text == '[G] Coffre' end end
    end)())
    CONTROLS[38] = true; RunThreads(1); CONTROLS[38] = false; RunThreads(10)
    check('E : seulement le point qui utilise E', table.concat(opened, ',') == 'a', table.concat(opened, ','))
    CONTROLS[47] = true; RunThreads(1); CONTROLS[47] = false; RunThreads(10)
    check('Touche propre au point', table.concat(opened, ',') == 'a,b')
    TriggerEvent('onResourceStop', 'res_a')
    check('Ressource arrêtée : ses points disparaissent', HexaPoints.points[a] == nil and HexaPoints.points[b] ~= nil)
    -- hexa_interact
    local zones, removed = {}, {}
    RESOURCES.hexa_interact = 'started'
    RESOURCE_EXPORTS.hexa_interact = { AddSphereZone = function(zone, option) zones[zone.name] = option end, RemoveZone = function(name) removed[#removed + 1] = name end }
    TriggerEvent('hexa_interact:client:ready')
    check('Zones redonnées à hexa_interact', zones['hexa_core:point:' .. b] and zones['hexa_core:point:' .. b].label == 'Coffre')
    MARKERS = 0; RunThreads(1500)
    check('Plus de marqueur avec hexa_interact', MARKERS == 0)
    check('Retrait', EXPORTS.RemovePoint(b) and removed[#removed] == 'hexa_core:point:' .. b and not EXPORTS.RemovePoint(b))
    check('Point invalide refusé', EXPORTS.AddPoint({ coords = vector3() }) == nil)
end

tests['C16 Points : une ressource Hexa et hexa_core qui redémarre'] = function()
    client()
    local added, session = {}, 's1'
    RESOURCE_EXPORTS.hexa_core = {
        AddPoint = function(point) added[#added + 1] = point.label; return #added, session end,
        RemovePoint = function(id) added[id] = 'retiré' end,
    }
    local id = Hexa.AddPoint({ coords = vector3(1, 2, 3), label = 'Guichet', onSelect = function() end })
    check('Confié à hexa_core', #added == 1 and added[1] == 'Guichet')
    MARKERS = 0; CLIENT_COORDS = vector3(1, 2, 3); RunThreads(1500)
    check('Pas de seconde boucle dans la ressource', MARKERS == 0)
    TriggerEvent('hexa_core:client:ready', 's1')
    check('Même hexa_core : pas de doublon', #added == 1)
    session = 's2'
    TriggerEvent('hexa_core:client:ready', 's2')
    check('hexa_core redémarré : point renvoyé', #added == 2 and added[2] == 'Guichet')
    check('Retrait transmis', Hexa.RemovePoint(id) and added[2] == 'retiré')
end

tests['C17 Gang et job2 côté client'] = function()
    if esx then
        local base = ESX.GetPlayerData
        ESX.GetPlayerData = function() local d = base(); d.job2 = { name = 'ballas', grade = 1, label = 'Ballas' }; return d end
    else
        CLIENT_DATA.gang = { name = 'ballas', label = 'Ballas', grade = { level = 1 } }
    end
    client()
    local name, grade, label = Hexa.Gang()
    check('Gang / job2', name == 'ballas' and grade == 1 and label == 'Ballas')
    check('HasJob : métier ou gang', Hexa.HasJob('police') and Hexa.HasJob('ballas', 1) and not Hexa.HasJob('ballas', 2) and Hexa.HasJob({ 'mechanic', 'ballas' }))
    if esx then ESX.GetPlayerData = function() return { job = { name = 'police', grade = 2 }, job2 = { name = 'unemployed2', grade = 0 } } end
    else CLIENT_DATA.gang = { name = 'none', grade = { level = 0 } } end
    check('Aucun gang (none / unemployed2)', Hexa.Gang() == nil and not Hexa.HasJob('none'))
end

-- 1.4.0 : serveur ----------------------------------------------------------------------------------------
tests['S32 Gang et job2 côté serveur'] = function()
    server()
    NewPlayer(1, { job = 'police', grade = 1, gang = { name = 'ballas', label = 'Ballas', grade = { level = 1 } }, job2 = { name = 'ballas', label = 'Ballas', grade = 1 } })
    NewPlayer(2, { job = 'mechanic', gang = { name = 'none', grade = { level = 0 } }, job2 = { name = 'unemployed2', grade = 0 } })
    local name, grade, label = Hexa.Gang(1)
    check('Gang / job2 lu', name == 'ballas' and grade == 1 and label == 'Ballas')
    check('Aucun gang', Hexa.Gang(2) == nil and Hexa.Gang(99) == nil)
    check('HasJob : métier', Hexa.HasJob(1, 'police', 1) and not Hexa.HasJob(1, 'police', 2))
    check('HasJob : gang / job2', Hexa.HasJob(1, 'ballas') and Hexa.HasJob(1, 'ballas', 1) and not Hexa.HasJob(1, 'ballas', 2))
    check('HasJob : liste', Hexa.HasJob(1, { 'mechanic', 'ballas' }) and not Hexa.HasJob(2, { 'ballas', 'none' }))
end

-- Base simulée : chaque requête est notée ; `answer(q, p)` répond.
local function fakeDB(answer)
    local log = {}
    RESOURCES.oxmysql = 'started'
    local function run(q, p) log[#log + 1] = { q = q, p = p }; return answer(q, p or {}) end
    MySQL = {}
    for _, m in ipairs({ 'query', 'single', 'scalar', 'insert', 'update' }) do MySQL[m] = { await = run } end
    return log
end

tests['S33 Métiers, grades, embauche'] = function()
    local updated = 0
    local log = fakeDB(function(q, p)
        if q:find('^UPDATE') then updated = updated + 1; return p[#p] == 'absent' and 0 or 1 end
        if q:find('FROM `users`') then return { { identifier = 'off1', firstname = 'Léa', lastname = 'Costa', job_grade = 1 }, { identifier = 'char:1', firstname = 'X', lastname = 'Y', job_grade = 0 } } end
        if q:find('FROM `player_groups`') then return { { citizenid = 'off1', grade = 1, charinfo = '{"firstname":"Léa","lastname":"Costa"}' } } end
        if q:find('FROM `players`') then return { { citizenid = 'off1', charinfo = '{"firstname":"Léa","lastname":"Costa"}', job = '{"name":"police","grade":{"level":1}}' },
            { citizenid = 'char:1', charinfo = '{}', job = '{"name":"police","grade":{"level":0}}' } } end
        return {}
    end)
    server()
    local info = Hexa.JobInfo('police')
    check('Grades triés', info and info.label == 'LSPD' and #info.grades == 3 and info.grades[1].grade == 0 and info.grades[3].grade == 2)
    check('Salaire, libellé, patron', info.grades[3].salary == 500 and info.grades[3].label == 'Chef' and info.grades[3].boss == true and info.grades[1].boss == false,
        tostring(info.grades[3].label))
    check('Métier inconnu : nil', Hexa.JobInfo('nope') == nil and Hexa.JobInfo(nil) == nil)
    if not esx then check('Gang : grades', Hexa.JobInfo('ballas', true) and #Hexa.JobInfo('ballas', true).grades == 2) end
    NewPlayer(1, { job = 'police', grade = 0 })
    NewPlayer(2, { job = 'mechanic', grade = 0, identifier = 'char:2' })
    check('Promotion', Hexa.SetJob(1, 'police', 2) and select(2, Hexa.Job(1)) == 2)
    check('Grade inexistant refusé', not Hexa.SetJob(1, 'police', 9) and select(2, Hexa.Job(1)) == 2)
    check('Métier inexistant refusé', not Hexa.SetJob(1, 'nope', 0))
    check('Joueur connecté (par identifiant)', Hexa.SetJobOffline('char:2', 'police', 1) and Hexa.Job(2) == 'police' and updated == 0)
    local ok = Hexa.SetJobOffline('off1', 'police', 1)
    if qbx then
        check('QBox hors ligne : qbx_core', ok and QBX_GROUPS.off1.job == 'police' and QBX_GROUPS.off1.primary == 'police' and updated == 0)
    elseif esx then
        check('ESX hors ligne : table users', ok and log[#log].q:find('UPDATE `users`') and log[#log].p[1] == 'police' and log[#log].p[2] == 1 and log[#log].p[3] == 'off1')
    else
        local data = json.decode(log[#log].p[1])
        check('QBCore hors ligne : métier complet en JSON', ok and data.name == 'police' and data.grade.level == 1 and data.grade.name == 'Agent' and data.payment == 200)
    end
    if not qbx then check('Personnage introuvable : false', not Hexa.SetJobOffline('absent', 'police', 0)) end
    check('Hors ligne : grade inexistant refusé', not Hexa.SetJobOffline('off1', 'police', 7))
    local members = Hexa.JobMembers('police')
    local byId = {}
    for _, m in ipairs(members) do byId[m.identifier] = m end
    check('Employés hors ligne', byId.off1 and byId.off1.name == 'Léa Costa' and byId.off1.grade == 1 and byId.off1.source == nil)
    check('Connectés : grade à jour et numéro', byId['char:1'] and byId['char:1'].grade == 2 and byId['char:1'].source == 1)
    check('Connecté qui vient d’être embauché', byId['char:2'] and byId['char:2'].source == 2)
    check('Trié du plus haut grade au plus bas', members[1].grade >= members[#members].grade)
    Hexa.SetJob(1, 'unemployed', 0)
    check('Parti du métier depuis la sauvegarde : retiré', (function() for _, m in ipairs(Hexa.JobMembers('police')) do if m.identifier == 'char:1' then return false end end return true end)())
end

tests['S34 Comptes d’entreprise'] = function()
    server()
    check('Aucun système : nil / false', Hexa.SocietyBalance('police') == nil and not Hexa.AddSocietyMoney('police', 10))
    -- hexa_banking
    local bank = { police = 100 }
    RESOURCES.hexa_banking = 'started'
    RESOURCE_EXPORTS.hexa_banking = {
        GetSocietyBalance = function(job) return bank[job] or 0 end,
        AddSocietyMoney = function(job, amount) bank[job] = (bank[job] or 0) + amount; return true end,
        RemoveSocietyMoney = function(job, amount) if (bank[job] or 0) < amount then return false end bank[job] = bank[job] - amount; return true end,
    }
    check('hexa_banking : solde', Hexa.SocietyBalance('police') == 100)
    check('hexa_banking : dépôt et retrait', Hexa.AddSocietyMoney('police', 50, 'Amende') and Hexa.RemoveSocietyMoney('police', 30) and bank.police == 120)
    check('hexa_banking : solde insuffisant refusé', not Hexa.RemoveSocietyMoney('police', 500) and bank.police == 120)
    check('Montant invalide refusé', not Hexa.AddSocietyMoney('police', -5) and not Hexa.AddSocietyMoney('police', 2.5) and not Hexa.AddSocietyMoney('police', 0))
    check('Nom de métier invalide refusé', Hexa.SocietyBalance('po lice') == nil and not Hexa.AddSocietyMoney("x' OR 1", 5))
    RESOURCES.hexa_banking = nil
    if esx then
        RESOURCES.esx_addonaccount = 'started'
        local account = { money = 100 }
        account.addMoney = function(n) account.money = account.money + n end
        account.removeMoney = function(n) account.money = account.money - n end
        AddEventHandler('esx_addonaccount:getSharedAccount', function(name, cb) cb(name == 'society_police' and account or nil) end)
        check('ESX : esx_addonaccount (society_police)', Hexa.SocietyBalance('police') == 100)
        check('ESX : retrait limité au solde', not Hexa.RemoveSocietyMoney('police', 150) and Hexa.RemoveSocietyMoney('police', 60) and account.money == 40)
        check('ESX : dépôt', Hexa.AddSocietyMoney('police', 10) and account.money == 50)
    else
        local res = qb and 'qb-banking' or 'Renewed-Banking'
        local funds = { police = 100 }
        RESOURCES[res] = 'started'
        RESOURCE_EXPORTS[res] = qb and {
            GetAccountBalance = function(job) return funds[job] end,
            AddMoney = function(job, n) funds[job] = funds[job] + n; return true end,
            RemoveMoney = function(job, n) funds[job] = funds[job] - n; return true end,
        } or {
            getAccountMoney = function(job) return funds[job] end,
            addAccountMoney = function(job, n) funds[job] = funds[job] + n; return true end,
            removeAccountMoney = function(job, n) funds[job] = funds[job] - n; return true end,
        }
        check(res .. ' : solde', Hexa.SocietyBalance('police') == 100)
        check(res .. ' : retrait limité au solde (vérifié avant)', not Hexa.RemoveSocietyMoney('police', 150) and funds.police == 100 and Hexa.RemoveSocietyMoney('police', 60) and funds.police == 40)
        check(res .. ' : dépôt', Hexa.AddSocietyMoney('police', 10) and funds.police == 50)
    end
end

tests['S35 Registre d’objets'] = function()
    server()
    Hexa.RegisterUsableItem('bread', function() end)
    local bread = Hexa.Item('bread')
    check('Libellé et poids', bread and bread.label == 'Pain' and bread.weight > 0 and bread.name == (qb and 'bread' or 'bread'))
    check('Utilisable (enregistré)', bread.usable == true)
    local phone = Hexa.Item('phone')
    if esx then
        check('ESX : sans inventaire, pas d’image', phone.image == nil and phone.usable == false)
        RESOURCES.hexa_inventory = 'started'
        check('Image hexa_inventory', Hexa.Item('phone').image == 'nui://hexa_inventory/web/images/phone.png')
        check('Arme ESX', Hexa.Item('WEAPON_PISTOL') and Hexa.Item('WEAPON_PISTOL').label == 'Pistolet' and Hexa.Item('WEAPON_PISTOL').unique)
    elseif qb then
        check('QBCore : unique, utilisable, description', phone.unique and phone.usable and bread.description == 'Du pain')
        check('QBCore : image sans inventaire connu', phone.image == nil)
        RESOURCES['qb-inventory'] = 'started'
        check('Image qb-inventory', Hexa.Item('phone').image == 'nui://qb-inventory/html/images/phone.png')
        RESOURCES.hexa_inventory = 'started'
        check('hexa_inventory prioritaire', Hexa.Item('phone').image == 'nui://hexa_inventory/web/images/phone.png')
    else
        check('QBox (ox_inventory) : non empilable = unique, image propre', phone.unique and phone.image == 'nui://ox_inventory/web/images/phone_x.png', phone.image)
    end
    check('Inconnu : nil', Hexa.Item('nope') == nil and Hexa.Item(nil) == nil)
    local all = Hexa.Items()
    check('Liste complète', all.bread and all.bread.label == 'Pain' and all.phone ~= nil)
end

tests['S36 Instances'] = function()
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/instances.lua' })
    RESOURCE_EXPORTS.hexa_core = EXPORTS
    for i = 1, 4 do NewPlayer(i) end
    BUCKETS[1] = 5
    local b1 = Hexa.SetInstance(1)
    check('Seul dans une instance privée', b1 == 1001 and BUCKETS[1] == 1001 and POPULATION[1001] == false, b1)
    local name, bucket = Hexa.GetInstance(1)
    check('GetInstance', name == 'solo:1' and bucket == 1001)
    local b2 = Hexa.SetInstance(2, 'appart_12', { population = true })
    check('Instance partagée par nom', Hexa.SetInstance(3, 'appart_12') == b2 and BUCKETS[2] == BUCKETS[3] and b2 ~= b1 and POPULATION[b2] == true)
    check('Retour dans le monde : instance d’origine', Hexa.LeaveInstance(1) and BUCKETS[1] == 5 and Hexa.GetInstance(1) == nil)
    check('Numéro libéré puis réutilisé', Hexa.SetInstance(4, 'garage') == 1001)
    Hexa.SetInstance(2, 'autre')
    check('Changement d’instance : origine gardée', Hexa.LeaveInstance(2) and BUCKETS[2] == 0)
    check('Pas dans une instance : false', not Hexa.LeaveInstance(2))
    Fire('playerDropped', 3, 'quit'); PLAYERS[3] = nil
    check('Départ : instance vidée', HexaInstances.named.appart_12 == nil)
    VEHICLE_OF[1001] = 77
    local b = Hexa.SetInstance(1, 'course', { vehicle = true })
    check('Véhicule emmené', ENTITY_BUCKETS[77] == b)
    check('Joueur inconnu', Hexa.SetInstance(99) == nil)
    -- depuis une autre ressource sans hexa_core
    RESOURCES.hexa_core = 'stopped'
    check('hexa_core arrêté : nil', Hexa.SetInstance(2) == nil and not Hexa.LeaveInstance(1))
end

tests['S36b Instances : bucket réglable, garde la main'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Instances = { firstBucket = 5000 } }"
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/instances.lua' })
    RESOURCE_EXPORTS.hexa_core = EXPORTS
    for i = 1, 3 do NewPlayer(i) end
    check('Premier bucket réglable', Hexa.SetInstance(1) == 5001 and BUCKETS[1] == 5001)
    -- Un autre script change le bucket d'un joueur placé par hexa_core : il est remis, une seule alerte.
    BUCKETS[1] = 0
    RunThreads(6000)
    check('Joueur remis dans son instance', BUCKETS[1] == 5001 and HexaInstances.conflicts() == 1)
    check('Alerte écrite', printed('changé par un autre script') and printed('remis dans l’instance'))
    PRINTS = {}
    BUCKETS[1] = 7; RunThreads(6000)
    check('Remis encore, sans répéter l’alerte', BUCKETS[1] == 5001 and HexaInstances.conflicts() == 2 and not printed('changé par un autre script'))
    -- Un joueur que hexa_core n'a pas placé n'est jamais touché
    BUCKETS[2] = 42; RunThreads(6000)
    check('Joueur hors instance : intact', BUCKETS[2] == 42 and HexaInstances.conflicts() == 2)
    -- Sorti normalement : plus surveillé
    Hexa.LeaveInstance(1); BUCKETS[1] = 99; RunThreads(6000)
    check('Après la sortie : plus surveillé', BUCKETS[1] == 99)
end

tests['S36c Instances : surveillance désactivée'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Instances = { enforce = false } }"
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/instances.lua' })
    RESOURCE_EXPORTS.hexa_core = EXPORTS
    NewPlayer(1)
    Hexa.SetInstance(1); BUCKETS[1] = 0; RunThreads(12000)
    check('enforce = false : rien remis', BUCKETS[1] == 0)
end

tests['S37 Logs en base'] = function()
    local rows, fail = {}, 0
    local log = fakeDB(function(q, p)
        if q:find('INSERT INTO `hexa_logs`') then
            if fail > 0 then fail = fail - 1; error('base en panne') end
            rows[#rows + 1] = p; return #rows
        end
        return {}
    end)
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/logs.lua' })
    RESOURCE_EXPORTS.hexa_core = EXPORTS
    RunThreads(100)
    check('Table créée', log[1] and log[1].q:find('CREATE TABLE IF NOT EXISTS `hexa_logs`'))
    check('Purge au démarrage (30 jours)', (function() for _, e in ipairs(log) do if e.q:find('DELETE FROM `hexa_logs`') then return e.p[1] == 30 end end end)())
    NewPlayer(1, { identifier = 'charA', charName = 'Léa Costa' })
    check('Sans webhook : Discord false', Hexa.Log('money', 'Retrait de 500 $', 1, { Lieu = 'Legion' }, 'warning') == false)
    RunThreads(2500)
    local r = rows[1]
    check('Gardé en base', #rows == 1 and r[1] == 'hexa_core' and r[2] == 'money' and r[3] == 'warning' and r[4] == 'Retrait de 500 $')
    check('Joueur et champs', r[5] == 'Léa Costa' and r[6] == 'charA' and json.decode(r[9]).Lieu == 'Legion')
    fail = 1
    Hexa.Log('admin', '/givecash')
    RunThreads(2500)
    check('Panne : réessayé, puis écrit une fois', #rows == 1 and printed('base en panne'))
    RunThreads(2500)
    check('… écrit au tour suivant', #rows == 2 and rows[2][2] == 'admin' and rows[2][5] == nil)
    local q
    fakeDB(function(query, p) q = { query, p }; return { { id = 1 } } end)
    local found = EXPORTS.GetLogs({ category = 'money', search = '50%', limit = 9999 })
    check('GetLogs : filtres et limite', #found == 1 and q[1]:find('`category` = %?') and q[1]:find('`message` LIKE %?') and q[2][2] == '%50\\%%' and q[2][3] == 500, tostring(q[2][2]))
end

tests['S38 Logs en base désactivés, purge réglable'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Logs = { database = false } }"
    local log = fakeDB(function() return {} end)
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/logs.lua' })
    Hexa.Log('money', 'x'); RunThreads(3000)
    check('Rien en base', #log == 0)
end

tests['S39 Nouvelles versions'] = function()
    RESOURCE_NAME = 'hexa_core'
    RESOURCES.oxmysql = 'started'
    server(); load({ 'main.lua' })
    RunThreads(6000)
    check('Fichier public demandé au démarrage', HTTP[1] and HTTP[1].url:find('versions.json') and HTTP[1].method == 'GET')
    METADATA = { hexa_core = { version = '1.4.0' }, hexa_shops = { version = '1.0.0' }, hexa_phone = { version = '3.0.2' } }
    RESOURCES.hexa_shops, RESOURCES.hexa_phone = 'started', 'started'
    local n = HexaCheckVersions('{"hexa_core":"1.4.0","hexa_shops":{"version":"1.1.0","notes":"Paniers."},"hexa_phone":"3.0.1","hexa_absent":"9.0","ox_lib":"9.9"}')
    check('Une mise à jour signalée', n == 1 and printed('hexa_shops : version 1.1.0 disponible (installée : 1.0.0). Paniers.'), n)
    check('Réponse illisible : rien', HexaCheckVersions('<html>') == 0 and HexaCheckVersions(nil) == 0)
    check('Réponse illisible : dite en console', printed('Vérification des versions impossible'))
    METADATA.hexa_core = { version = '1.0.0-beta.9' }
    check('Bêta : beta.10 plus récente que beta.9', HexaCheckVersions('{"hexa_core":"1.0.0-beta.10"}') == 1)
    METADATA.hexa_core = { version = '1.0.0-beta.10' }
    check('Bêta : installée beta.10, annoncée beta.9 : rien', HexaCheckVersions('{"hexa_core":"1.0.0-beta.9"}') == 0)
    check('Bêta : la version finale est plus récente que sa bêta', HexaCheckVersions('{"hexa_core":"1.0.0"}') == 1)
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { VersionCheck = { enabled = false, url = 'https://x/v.json' } }"
end

tests['S40 Vérification désactivée'] = function()
    RESOURCES.oxmysql = 'started'
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { VersionCheck = { enabled = false, url = 'https://x/v.json' } }"
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'main.lua' })
    RunThreads(6000)
    check('Aucune requête', #HTTP == 0)
end

tests['S41 Debug par ressource'] = function()
    server()
    check('Désactivé par défaut', not Hexa.IsDebug())
    CONVARS.hexa_debug = 'hexa_shops'
    check('Autre ressource : non', not Hexa.IsDebug())
    CONVARS.hexa_debug = 'hexa_shops, hexa_test'
    check('Cette ressource dans la liste', Hexa.IsDebug())
    Hexa.Debug('Achat', { item = 'bread' }, 3)
    check('Message de debug', printed('[hexa_test] Achat {"item":"bread"} 3'))
    CONVARS.hexa_debug = 'all'
    check('« all »', Hexa.IsDebug())
    CONVARS.hexa_debug = nil
    PRINTS = {}
    Hexa.Debug('caché')
    check('Désactivé : rien affiché', #PRINTS == 0)
    check('Version du core : bêta, niveau d’API conservé', Hexa.version == '1.0.0-beta.1' and Hexa.apiLevel == '1.4.0')
end

tests['S42 Version bêta et niveau d’API'] = function()
    RESOURCES.oxmysql = 'started'
    server()
    local at, V = Hexa.VersionAtLeast, Hexa
    check('Numéros classiques', at('1.10.0', '1.9.2') and not at('1.9.2', '1.10.0') and at('1.0.0', '1.0') and not at('1.0.0', '1.0.1') and at('2.0', '1.99.9'))
    check('beta.10 > beta.9 > beta.2 > beta.1', at('1.0.0-beta.10', '1.0.0-beta.9') and not at('1.0.0-beta.9', '1.0.0-beta.10') and at('1.0.0-beta.2', '1.0.0-beta.1') and not at('1.0.0-beta.1', '1.0.0-beta.2'))
    check('Identiques : vrai', at('1.0.0-beta.3', '1.0.0-beta.3') and at('1.0.0', '1.0.0'))
    check('La version finale passe avant sa bêta', at('1.0.0', '1.0.0-beta.99') and not at('1.0.0-beta.99', '1.0.0'))
    check('Bêta d’une version supérieure > finale inférieure', at('1.1.0-beta.1', '1.0.0') and not at('1.0.0-beta.1', '1.1.0'))
    check('Texte et vide ne plantent pas', at(nil, nil) and at('1.0.0', '') and not at('', '1.0.0') and not at('abc', '1.0.0'))
    check('Version du core', V.version == '1.0.0-beta.1' and V.apiLevel == '1.4.0')
    -- Les ressources Hexa déjà écrites exigent « 1.4.0 » : elles doivent démarrer avec le core bêta.
    check('Anciennes exigences (sans bêta) : niveau d’API', V.RequireVersion('1.4.0') and V.RequireVersion('1.1.0') and V.RequireVersion('1.0.0'))
    check('Exigence trop haute refusée', not V.RequireVersion('1.5.0') and printed('1.5.0') and printed('1.0.0-beta.1'))
    check('Exigence bêta : version', V.RequireVersion('1.0.0-beta.1') and not V.RequireVersion('1.0.0-beta.2'))
    RESOURCE_NAME = 'hexa_core'
    load({ 'main.lua' })
    check('Exports Version et ApiLevel', EXPORTS.Version() == '1.0.0-beta.1' and EXPORTS.ApiLevel() == '1.4.0')
end

tests['S43 Démarrage refusé sans oxmysql ni framework'] = function()
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'main.lua' })     -- oxmysql absent
    RunThreads(100)
    check('oxmysql absent : message qui dit quoi faire', printed('hexa_core ne démarre pas') and printed('ensure oxmysql'))
    check('oxmysql absent : le core s’arrête', #STOPPED == 1 and STOPPED[1] == 'hexa_core')
    check('Pas de bannière de succès ni d’exports', not printed('framework :') and EXPORTS.Version == nil)
end

tests['S43b Démarrage refusé : framework absent, anglais, démarrage normal'] = function()
    RESOURCE_NAME = 'hexa_core'
    RESOURCES.oxmysql = 'started'
    CONFIG_OVERRIDE = "HexaConfig = { Framework = 'esx', ESXResource = 'absent', Locale = 'en' }"
    server(); load({ 'main.lua' })
    RunThreads(100)
    check('Framework absent : message anglais', printed('hexa_core is not starting') and printed('ensure es_extended'))
    check('Framework absent : le core s’arrête', STOPPED[1] == 'hexa_core')
end

tests['S43c Démarrage normal'] = function()
    RESOURCE_NAME = 'hexa_core'
    RESOURCES.oxmysql = 'started'
    server(); load({ 'main.lua' })
    RunThreads(100)
    check('Bannière avec la version bêta', printed('v1.0.0-beta.1 — framework : ' .. FRAMEWORK))
    check('Aucun arrêt', #STOPPED == 0 and EXPORTS.Version() == '1.0.0-beta.1')
end

local function startIds(db)
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'ids.lua' })
    RESOURCE_EXPORTS.hexa_core = EXPORTS
    RunThreads(4000)
end
local function sourceTable() return esx and 'users' or 'players' end

tests['S44 IDs : migration des personnages existants'] = function()
    local db = idsDB({ tables = { [sourceTable()] = true }, source = { 'charA', 'charB', 'charC' }, columns = esx and {} or { ['players.id'] = true } })
    db.chars[1] = { identifier = 'charB' }; db.nextC = 2       -- déjà numéroté par une version précédente
    startIds(db)
    check('Colonnes ajoutées sans rien perdre', db.columns['hexa_characters.deleted_at'] and db.columns['hexa_characters.former'])
    check('Ceux qui ont déjà un ID le gardent', db.chars[1].identifier == 'charB')
    check('Les autres suivent, dans l’ordre du framework', db.chars[2].identifier == 'charA' and db.chars[3].identifier == 'charC' and db.nextC == 4)
    check('Ordre demandé', db.orderBy == (esx and 'identifier' or 'id'), db.orderBy)
    check('ESX sans date : prévenu', not esx or printed('ordre alphabétique'))
    check('Marqué fait + résumé', db.meta.ids_migrated == '1' and printed('3 personnage(s)'))
    local before = db.queries
    startIds(db)
    check('Redémarrage : rien n’est refait', db.queries == before and db.nextC == 4)
end

tests['S44b IDs : ordre par date de création, lots, table absente'] = function()
    local db = idsDB({ tables = { [sourceTable()] = true }, source = {}, columns = { [sourceTable() .. (esx and '.created_at' or '.id')] = true } })
    for i = 1, 1200 do db.source[i] = ('id%04d'):format(i) end
    startIds(db)
    check('Ordre : ' .. (esx and 'created_at' or 'id'), db.orderBy == (esx and 'created_at' or 'id'), db.orderBy)
    check('1 200 personnages en 3 lots, sans doublon', db.queries == 3 and db.nextC == 1201 and db.chars[1].identifier == 'id0001' and db.chars[1200].identifier == 'id1200', db.queries .. '/' .. db.nextC)
    check('Pas d’avertissement d’ordre alphabétique', not printed('ordre alphabétique'))
end

tests['S44c IDs : table du framework absente'] = function()
    local db = idsDB({ tables = {}, source = { 'x' } })
    startIds(db)
    check('Rien numéroté, pas de marque (retenté au prochain démarrage)', db.nextC == 1 and db.meta.ids_migrated == nil and db.queries == 0)
end

tests['S45 IDs : personnage supprimé, identifiant réutilisé'] = function()
    local db = idsDB({ tables = {} })
    startIds(db)
    NewPlayer(1, { identifier = 'char1:abc', license = 'license:aaa' })
    Fire('playerJoining', 1); RunThreads(500)
    if esx then Fire('esx:playerLoaded', nil, 1, {}, false) else Fire('QBCore:Server:PlayerLoaded', nil, { PlayerData = { source = 1 } }) end
    RunThreads(500)
    check('ID attribué', Hexa.CharId(1) == 1)
    local deleted = {}
    Hexa.OnCharacterDeleted(function(id, identifier) deleted[#deleted + 1] = { id, identifier } end)
    local ok, id = inThread(function() return Hexa.DeleteCharacter('char1:abc') end)
    check('Suppression acceptée', ok == true)
    check('Ligne gardée, marquée supprimée', db.chars[1] and db.chars[1].deleted_at == true)
    check('Événement envoyé', #deleted == 1 and deleted[1][1] == 1 and deleted[1][2] == 'char1:abc')
    check('Le joueur perd son ID de personnage', Hexa.CharId(1) == nil and STATEBAGS[1].hexaCharId == nil)
    check('Hors ligne : plus d’ID pour cet identifiant', inThread(function() return Hexa.CharIdOf('char1:abc') end) == nil)
    check('Inconnu ou invalide : false', inThread(function() return Hexa.DeleteCharacter('nope') end) ~= true and inThread(function() return Hexa.DeleteCharacter(42) end) ~= true)
    -- ESX réutilise « char1:… » pour un nouveau personnage : il ne doit PAS recevoir l'ancien ID.
    if esx then Fire('esx:playerLogout', nil, 1) else Fire('QBCore:Server:OnPlayerUnload', nil, 1) end
    if esx then Fire('esx:playerLoaded', nil, 1, {}, false) else Fire('QBCore:Server:PlayerLoaded', nil, { PlayerData = { source = 1 } }) end
    RunThreads(500)
    check('Même identifiant, nouvel ID', Hexa.CharId(1) == 2, tostring(Hexa.CharId(1)))
    check('L’ancien garde son ID et son identifiant d’origine', db.chars[1].identifier == '#1' and inThread(function() return Hexa.IdentifierOfCharId(1) end) == 'char1:abc')
    check('Hors ligne : l’identifiant mène au nouveau', inThread(function() return Hexa.CharIdOf('char1:abc') end) == 2)
end

tests['S45b IDs : suppression en mode « remove », dernière connexion'] = function()
    CONFIG_OVERRIDE = "HexaConfig = { Ids = { OnDelete = 'remove' } }"
    local db = idsDB({ tables = {} })
    startIds(db)
    NewPlayer(1, { identifier = 'c1', license = 'license:aaa' })
    Fire('playerJoining', 1); RunThreads(500)
    if esx then Fire('esx:playerLoaded', nil, 1, {}, false) else Fire('QBCore:Server:PlayerLoaded', nil, { PlayerData = { source = 1 } }) end
    RunThreads(500)
    check('Dernière connexion inconnue tant que le joueur n’est pas parti', inThread(function() return Hexa.LastSeen(1) end) == nil)
    NOW = NOW + 5000
    local left = NOW
    Fire('playerDropped', 1, 'quit'); RunThreads(200)
    local seen = db.players[1].last_seen
    check('Départ : date enregistrée', seen and seen >= left and inThread(function() return Hexa.LastSeen(1) end) == seen, tostring(seen))
    check('Mode remove : ligne effacée', inThread(function() return Hexa.DeleteCharacter('c1') end) == true and db.chars[1] == nil)
    check('Jamais redonné : le suivant reçoit 2', (function()
        NewPlayer(2, { identifier = 'c2', license = 'license:bbb' })
        Fire('playerJoining', 2); RunThreads(500)
        if esx then Fire('esx:playerLoaded', nil, 2, {}, false) else Fire('QBCore:Server:PlayerLoaded', nil, { PlayerData = { source = 2 } }) end
        RunThreads(500)
        return Hexa.CharId(2) == 2
    end)())
end

tests['S46 Fiche du joueur'] = function()
    server()
    NewPlayer(1, { charName = 'Ana Silva', birthdate = '1995-04-12', sex = 'f', job = 'police', grade = 3, coords = vector3(10.0, 20.0, 30.0),
        gang = { name = 'ballas', label = 'Ballas', grade = { level = 2 } }, job2 = { name = 'ballas', label = 'Ballas', grade = 2 },
        meta = { height = 170, nationality = 'Portugaise', hunger = 80, thirst = 60 } })
    RESOURCE_EXPORTS.hexa_core = { GetPlayerId = function() return 12 end, GetCharId = function() return 31 end }
    RESOURCES.hexa_phone = 'started'; RESOURCE_EXPORTS.hexa_phone = { GetNumber = function() return '555-0101' end }
    local p = inThread(function() return Hexa.Profile(1) end)
    check('Fiche trouvée', p ~= nil and p.source == 1)
    check('IDs', p.playerId == 12 and p.charId == 31)
    check('Identité', p.name == 'Ana Silva' and p.firstname == 'Ana' and p.lastname == 'Silva' and p.birthdate == '1995-04-12' and p.sex == 'f' and p.height == 170 and p.nationality == 'Portugaise')
    check('Métier et gang', p.job == 'police' and p.grade == 3 and p.duty == true and p.gang == 'ballas' and p.gangGrade == 2)
    check('Position', p.coords and p.coords.x == 10.0 and p.coords.z == 30.0)
    check('Téléphone via hexa_phone', p.phone == '555-0101')
    check('Mort, admin, métadonnées', p.dead == false and p.admin == false and (esx or type(p.metadata) == 'table'))
    if qb or qbx then check('Faim et soif (QB)', p.hunger == 80 and p.thirst == 60) end
    local light = inThread(function() return Hexa.Profile(1, { needs = false }) end)
    check('options.needs = false : sans faim ni soif', light.hunger == nil and light.thirst == nil and light.job == 'police')
    check('Joueur inconnu ou invalide : nil', Hexa.Profile(99) == nil and Hexa.Profile(nil) == nil and Hexa.Profile('x') == nil)
    RESOURCES.hexa_phone = nil
    check('Sans hexa_phone : pas de numéro', inThread(function() return Hexa.Profile(1, { needs = false }) end).phone == nil)
end

tests['S47 Registre : champs, source unique, RegisterItem'] = function()
    server()
    Hexa.RegisterUsableItem('bread', function() end)
    local bread, phone = Hexa.Item('bread'), Hexa.Item('phone')
    check('Empilable / unique', bread.stackable == true and bread.unique == false)
    if qb then check('Unique : non empilable', phone.unique and phone.stackable == false) end
    check('Pas arme / pas rare / pas de limite par défaut', bread.weapon == false and bread.rare == false and bread.limit == nil and bread.category == nil)
    check('Arme reconnue', Hexa.IsWeapon(W) and (qbx or (Hexa.Item(W) and Hexa.Item(W).weapon == true)))
    if esx then
        RESOURCES.ox_inventory = 'started'
        RESOURCE_EXPORTS.ox_inventory = { Items = function() return { bread = { label = 'Pain ox', weight = 250, category = 'food', limit = 10 } } end }
        local ox = Hexa.Item('bread')
        check('ESX + ox_inventory : la liste d’ox fait foi', ox.label == 'Pain ox' and ox.weight == 250 and ox.category == 'food' and ox.limit == 10)
        check('Et seulement elle', Hexa.Item('phone') == nil)
        RESOURCES.ox_inventory = nil
        check('ox_inventory arrêté : retour à la liste du framework', Hexa.Item('bread').label == 'Pain')
    end
    -- RegisterItem
    local seen
    RESOURCES.hexa_inventory = 'started'
    RESOURCE_EXPORTS.hexa_inventory = { RegisterItems = function(items) seen = items; return true end }
    check('hexa_inventory : objet déclaré', Hexa.RegisterItem('id_card', { label = 'Carte', weight = 5.7, unique = true }) == true)
    check('Définition transmise nettoyée', seen and seen[qb and 'id_card' or 'id_card'] and seen.id_card.label == 'Carte' and seen.id_card.weight == 5 and seen.id_card.unique == true)
    RESOURCE_EXPORTS.hexa_inventory = { RegisterItems = function() error('boom') end }
    check('Erreur de l’inventaire : false, sans planter', Hexa.RegisterItem('id_card', { label = 'Carte' }) == false)
    RESOURCES.hexa_inventory = nil
    local added
    if qb then
        Hexa.core.Functions.AddItem = function(name, def) added = { name, def }; return true end
        check('QBCore : Functions.AddItem', Hexa.RegisterItem('Id_Card', { label = 'Carte', weight = 5 }) == true and added[1] == 'id_card' and added[2].label == 'Carte' and added[2].image == 'id_card.png')
    else
        PRINTS = {}
        check('Sans moyen officiel : false + message', Hexa.RegisterItem('id_card', { label = 'Carte' }) == false and printed('non enregistré'))
    end
    check('Arguments invalides : false', Hexa.RegisterItem(nil, {}) == false and Hexa.RegisterItem('x', nil) == false and Hexa.RegisterItem('x', 'y') == false)
end

tests['S48 Service, grade, gang, renvoi'] = function()
    RESOURCES.oxmysql = 'started'
    server()
    NewPlayer(1, { job = 'police', grade = 0, identifier = 'char:1' })
    check('Hexa.OnDuty : en service par défaut', Hexa.OnDuty(1) == true)
    check('Sans métier : pas en service', (function() NewPlayer(2, { identifier = 'char:2' }); return Hexa.OnDuty(2) == false end)())
    check('Joueur inconnu', Hexa.OnDuty(99) == false and Hexa.SetDuty(99, true) == false)
    if esx then
        PRINTS = {}
        check('ESX : SetDuty refusé, dit une fois', Hexa.SetDuty(1, false) == false and Hexa.SetDuty(1, false) == false and printed('n’existe pas sous ESX'))
        check('ESX : reste en service', Hexa.OnDuty(1) == true)
    else
        check('Sortie de service', Hexa.SetDuty(1, false) == true and Hexa.OnDuty(1) == false)
        check('Retour en service', Hexa.SetDuty(1, true) == true and Hexa.OnDuty(1) == true)
        check('Valeur invalide = hors service', Hexa.SetDuty(1, 'oui') == true and Hexa.OnDuty(1) == false)
    end
    check('SetGrade : promotion du métier actuel', Hexa.SetGrade(1, 2) and select(2, Hexa.Job(1)) == 2 and Hexa.Job(1) == 'police')
    check('SetGrade : grade inexistant refusé', not Hexa.SetGrade(1, 9) and select(2, Hexa.Job(1)) == 2)
    check('SetGrade : sans métier refusé', not Hexa.SetGrade(2, 1))
    if esx then
        check('Gang ESX (job2) : accepté si disponible', Hexa.SetGang(1, 'ballas', 1) == false or Hexa.Gang(1) == 'ballas')
    else
        check('SetGang', Hexa.SetGang(1, 'ballas', 1) == true)
        if qb then check('SetGang : lu par Hexa.Gang', Hexa.Gang(1) == 'ballas' and select(2, Hexa.Gang(1)) == 1) end
        if qbx then check('QBox : gang écrit par qbx_core', QBX_GROUPS['char:1'].gang == 'ballas' and QBX_GROUPS['char:1'].primaryGang == 'ballas') end
        check('SetGang : gang ou grade inexistant refusé', not Hexa.SetGang(1, 'nope', 0) and not Hexa.SetGang(1, 'ballas', 9))
    end
    check('SetGang : arguments invalides', not Hexa.SetGang(99, 'ballas', 0) and not Hexa.SetGang(1, nil, 0))
    -- Renvoi : même chemin que l'embauche hors ligne, vers « unemployed ».
    check('FireJob : identifiant invalide refusé', not Hexa.FireJob(nil) and not Hexa.FireJob(5))
    check('FireJob : personnage connecté renvoyé au chômage', Hexa.FireJob('char:1') == true and Hexa.Job(1) == 'unemployed' and select(2, Hexa.Job(1)) == 0)
end

tests['S49 Entreprises : journal, droit de retrait, virement, découvert'] = function()
    local rows, nextId = {}, 1
    fakeDB(function(q, p)
        if q:find('INSERT INTO `hexa_society_log`', 1, true) then rows[#rows + 1] = { job = p[1], amount = p[2], balance = p[3], reason = p[4], author = p[5], at = 1700000000 + #rows }; return #rows end
        if q:find('FROM `hexa_society_log`', 1, true) then
            local out = {}
            local max = tonumber(q:match('LIMIT (%d+)')) or 1000
            for i = #rows, 1, -1 do if rows[i].job == p[1] and #out < max then out[#out + 1] = rows[i] end end
            return out
        end
        return {}
    end)
    server()
    local bank = { police = 100, ems = 10 }
    RESOURCES.hexa_banking = 'started'
    RESOURCE_EXPORTS.hexa_banking = {
        GetSocietyBalance = function(job) bank[job] = bank[job] or 0; return bank[job] end,
        AddSocietyMoney = function(job, n) bank[job] = (bank[job] or 0) + n; return true end,
        RemoveSocietyMoney = function(job, n) if (bank[job] or 0) < n then return false end bank[job] = bank[job] - n; return true end,
    }
    NewPlayer(1, { job = 'police', grade = 2, identifier = 'char:1' })    -- Chef (patron)
    NewPlayer(2, { job = 'police', grade = 0, identifier = 'char:2' })    -- Recrue
    NewPlayer(3, { job = 'mechanic', grade = 0, identifier = 'char:3' })
    check('Patron : peut retirer', Hexa.SocietyCanWithdraw(1, 'police') == true)
    check('Recrue : ne peut pas', Hexa.SocietyCanWithdraw(2, 'police') == false)
    check('Autre métier : non', Hexa.SocietyCanWithdraw(3, 'police') == false)
    check('Nom invalide / inconnu : non', not Hexa.SocietyCanWithdraw(1, 'po lice') and not Hexa.SocietyCanWithdraw(99, 'police'))
    check('Retrait par un patron', Hexa.SocietyWithdraw(1, 'police', 30, 'Achat') == true and bank.police == 70)
    check('Retrait refusé à une recrue : rien ne bouge', Hexa.SocietyWithdraw(2, 'police', 30) == false and bank.police == 70)
    check('Retrait refusé : solde insuffisant', Hexa.SocietyWithdraw(1, 'police', 500) == false and bank.police == 70)
    -- Journal
    Hexa.AddSocietyMoney('police', 50, 'Amende', 2)
    local history = Hexa.SocietyHistory('police')
    check('Journal : mouvements enregistrés, le plus récent d’abord', #history == 2 and history[1].amount == 50 and history[2].amount == -30, #history)
    check('Journal : raison, solde après, auteur', history[1].reason == 'Amende' and history[1].balance == 120 and history[1].author == 'char:2' and history[2].author == 'char:1')
    check('Journal : un refus n’écrit rien', (function() local n = #rows; Hexa.SocietyWithdraw(2, 'police', 5); Hexa.RemoveSocietyMoney('police', 9999); return #rows == n end)())
    check('Journal : limite et nom invalide', #Hexa.SocietyHistory('police', 1) == 1 and #Hexa.SocietyHistory('x y') == 0)
    -- Virement
    check('Virement', Hexa.SocietyTransfer('police', 'ems', 20, 'Aide') == true and bank.police == 100 and bank.ems == 30)
    check('Virement : journal des deux côtés', Hexa.SocietyHistory('ems')[1].amount == 20 and Hexa.SocietyHistory('police')[1].amount == -20)
    check('Virement refusé : solde insuffisant', Hexa.SocietyTransfer('ems', 'police', 999) == false and bank.ems == 30 and bank.police == 100)
    check('Virement refusé : même compte ou invalide', not Hexa.SocietyTransfer('ems', 'ems', 5) and not Hexa.SocietyTransfer('ems', 'a b', 5) and not Hexa.SocietyTransfer('ems', 'police', -5))
    -- Dépôt qui échoue : le retrait est annulé
    RESOURCE_EXPORTS.hexa_banking.AddSocietyMoney = function(job, n) if job == 'ems' then return false end bank[job] = (bank[job] or 0) + n; return true end
    check('Dépôt impossible : argent rendu', Hexa.SocietyTransfer('police', 'ems', 10) == false and bank.police == 100)
    -- Droit par grade numérique
    Hexa.ServerConfig.Society = { withdrawGrade = 1 }
    NewPlayer(4, { job = 'police', grade = 1, identifier = 'char:4' })
    check('Grade minimum réglable', Hexa.SocietyCanWithdraw(4, 'police') == true and Hexa.SocietyCanWithdraw(2, 'police') == false)
    -- Journal désactivable
    Hexa.ServerConfig.Society = { journal = false }
    local n = #rows
    Hexa.AddSocietyMoney('police', 1)
    check('Journal désactivé', #rows == n)
    -- Découvert (systèmes où le core vérifie lui-même)
    RESOURCES.hexa_banking = nil
    Hexa.ServerConfig.Society = { maxOverdraft = 50, journal = false }
    local funds = { police = 20 }
    local res = esx and 'esx_addonaccount' or (qb and 'qb-banking' or 'Renewed-Banking')
    if esx then
        RESOURCES.esx_addonaccount = 'started'
        local account = { money = 20 }
        account.addMoney = function(v) account.money = account.money + v end
        account.removeMoney = function(v) account.money = account.money - v end
        AddEventHandler('esx_addonaccount:getSharedAccount', function(name, cb) cb(name == 'society_police' and account or nil) end)
        check('Découvert : retrait jusqu’à -50', Hexa.RemoveSocietyMoney('police', 60) == true and account.money == -40)
        check('Découvert : au-delà refusé', Hexa.RemoveSocietyMoney('police', 20) == false and account.money == -40)
    else
        RESOURCES[res] = 'started'
        RESOURCE_EXPORTS[res] = qb and {
            GetAccountBalance = function(job) return funds[job] end,
            AddMoney = function(job, v) funds[job] = funds[job] + v; return true end,
            RemoveMoney = function(job, v) funds[job] = funds[job] - v; return true end,
        } or {
            getAccountMoney = function(job) return funds[job] end,
            addAccountMoney = function(job, v) funds[job] = funds[job] + v; return true end,
            removeAccountMoney = function(job, v) funds[job] = funds[job] - v; return true end,
        }
        check('Découvert : retrait jusqu’à -50', Hexa.RemoveSocietyMoney('police', 60) == true and funds.police == -40)
        check('Découvert : au-delà refusé', Hexa.RemoveSocietyMoney('police', 20) == false and funds.police == -40)
    end
    -- Création de compte
    PRINTS = {}
    check('Création sans hexa_banking : refusée avec message', Hexa.CreateSociety('taxi') == false and printed('Création du compte'))
    RESOURCES.hexa_banking = 'started'
    check('Création avec hexa_banking', Hexa.CreateSociety('taxi') == true and bank.taxi == 0)
    check('Création : nom invalide', Hexa.CreateSociety('a b') == false)
end

tests['C20 Dialogues : mot de passe, PIN, curseur, heure'] = function()
    coreClient()
    local result = async(function() return EXPORTS.Form({
        { type = 'password', name = 'mdp', min = 6, max = 20 },
        { type = 'pin', name = 'pin', length = 4 },
        { type = 'slider', name = 'volume', min = 0, max = 100, step = 5, default = 40, unit = '%' },
        { type = 'time', name = 'heure' },
        { type = 'password', name = 'libre', required = false },
    }, { title = 'Coffre' }) end)
    local m = LastNui('open')
    check('Mot de passe masqué, longueur max', m.fields[1].masked == true and m.fields[1].maxLength == 20)
    check('PIN masqué, numérique, longueur', m.fields[2].masked == true and m.fields[2].numeric == true and m.fields[2].length == 4 and m.fields[2].maxLength == 4)
    check('Curseur : bornes, pas, défaut, unité', m.fields[3].min == 0 and m.fields[3].max == 100 and m.fields[3].step == 5 and m.fields[3].default == 40 and m.fields[3].unit == '%')
    check('Heure : indication', m.fields[4].placeholder == 'HH:MM')
    local r = Nui('submit', { values = { 'abc', '12a4', 42, '25:00', '' } })
    local idx = {}
    for _, err in ipairs(r.errors or {}) do idx[#idx + 1] = err.index end
    check('Erreurs : mdp court, PIN invalide, curseur hors pas, heure invalide', r.ok == false and table.concat(idx, ',') == '1,2,3,4', table.concat(idx, ','))
    r = Nui('submit', { values = { 'abc', '123', 105, '9:75', '' } })
    check('Erreurs : PIN trop court, curseur hors bornes, minutes invalides', #r.errors == 4 and r.errors[2].error == 'Entrez exactement 4 chiffres.' and r.errors[4].error == 'Heure invalide (HH:MM).')
    r = Nui('submit', { values = { '  Mot  de passe ', '0042', 45, '9h05', '' } })
    local done, v = result()
    check('Valeurs : mot de passe gardé tel quel (espaces compris)', r.ok and done and v.mdp == '  Mot  de passe ')
    check('Valeurs : PIN en texte (zéros gardés), curseur en nombre, heure normalisée', v.pin == '0042' and v.volume == 45 and v.heure == '09:05')
    check('Mot de passe facultatif vide : texte vide', v.libre == '')
end

tests['C21 Dialogues : curseur et heure, cas limites'] = function()
    coreClient()
    local f = HexaDialog.normalize({ type = 'slider' })
    check('Curseur sans réglage : 0 à 100, pas 1', f.min == 0 and f.max == 100 and f.step == 1)
    f = HexaDialog.normalize({ type = 'slider', min = 10, max = 0, step = -3 })
    check('Bornes inversées remises dans l’ordre, pas invalide = 1', f.min == 0 and f.max == 10 and f.step == 1)
    f = HexaDialog.normalize({ type = 'pin', length = 99 })
    check('PIN : longueur limitée à 8', f.length == 8)
    f = HexaDialog.normalize({ type = 'pin', length = 1 })
    check('PIN : au moins 3 chiffres', f.length == 3)
    local slider = HexaDialog.normalize({ type = 'slider', min = 0, max = 1, step = 0.1 })
    check('Pas décimal accepté (0,3)', HexaDialog.validate(slider, 0.3) == 0.3)
    check('Texte non numérique refusé', select(2, HexaDialog.validate(slider, 'x')) == 'Entrez un nombre.')
    local time = HexaDialog.normalize({ type = 'time' })
    check('Heures valides', HexaDialog.validate(time, '00:00') == '00:00' and HexaDialog.validate(time, '23:59') == '23:59' and HexaDialog.validate(time, ' 7:05 ') == '07:05')
    check('Heures invalides', HexaDialog.validate(time, '24:00') == nil and HexaDialog.validate(time, '12:60') == nil and HexaDialog.validate(time, '1205') == nil and HexaDialog.validate(time, nil) == nil)
    local pin = HexaDialog.normalize({ type = 'pin' })
    check('PIN : seulement des chiffres, longueur exacte', HexaDialog.validate(pin, '1234') == '1234' and HexaDialog.validate(pin, '12 34') == nil and HexaDialog.validate(pin, '１２３４') == nil and HexaDialog.validate(pin, nil) == nil)
end

tests['C22 Menu liste'] = function()
    coreClient()
    local result = async(function() return Hexa.Menu({ title = 'Garage', description = 'Que faire ?', options = {
        { label = 'Sortir', value = 'out' }, { label = 'Réparer', description = '150 $' }, { label = 'Vendre', value = 'sell', disabled = true }, 'Fourrière' } }) end)
    local m = LastNui('open')
    check('Menu ouvert : 4 options, textes', m.kind == 'menu' and #m.items == 4 and m.title == 'Garage' and m.description == 'Que faire ?')
    check('Option : libellé, description, désactivée', m.items[2].description == '150 $' and m.items[3].disabled == true and m.items[4].label == 'Fourrière')
    check('Focus clavier et souris', FOCUS[1] and FOCUS[2])
    check('Option désactivée refusée', Nui('choose', { index = 3 }).ok == false and EXPORTS.IsDialogOpen())
    check('Numéro hors liste refusé', Nui('choose', { index = 9 }).ok == false and Nui('choose', { index = 0 }).ok == false and Nui('choose', { index = 'x' }).ok == false)
    check('« Valider » n’existe pas pour un menu', Nui('submit', { values = { 'x', 'x', 'x', 'x' } }).ok == false and EXPORTS.IsDialogOpen())
    check('Réponse de la page : un seul des deux corps', Nui('choose', { index = 1 }).ok == true)
    local done, value, index = result()
    check('Valeur de l’option et son numéro', done and value == 'out' and index == 1)
    check('Fermé', not EXPORTS.IsDialogOpen() and NUI[#NUI].action == 'close')
    -- Sans `value` : le numéro
    result = async(function() return Hexa.Menu({ options = { 'A', 'B' } }) end)
    Nui('choose', { index = 2 })
    local _, v, i = result()
    check('Sans value : le numéro', v == 2 and i == 2)
    -- Annulation
    result = async(function() return Hexa.Menu({ options = { 'A' } }) end)
    Nui('cancel')
    local _, c = result()
    check('Annulé : nil', c == nil and not EXPORTS.IsDialogOpen())
    -- Menu vide, arguments invalides
    result = async(function() return Hexa.Menu('Titre seul') end)
    check('Chaîne seule = titre, aucune option', LastNui('open').title == 'Titre seul' and #LastNui('open').items == 0)
    Nui('cancel'); result()
    local done, nothing = async(function() return Hexa.Menu(nil) end)()
    check('Rien en argument : ouvre un menu vide, sans planter', LastNui('open').kind == 'menu' and #LastNui('open').items == 0)
    Nui('cancel')
end

tests['C23 Style, touches et manette'] = function()
    coreClient()
    local result = async(function() return Hexa.Confirm('Sûr ?') end)
    local m = LastNui('open')
    check('Style centré par défaut', m.style == 'center')
    check('Touches par défaut', m.keys.submit == 'Enter' and m.keys.cancel == 'Escape')
    -- Manette : seulement quand elle est en main
    NUI = {}
    PAD_PRESSED = { [188] = true }
    KBM = true
    RunThreads(50)
    check('Clavier en main : la manette est ignorée', LastNui('pad') == nil)
    KBM = false
    RunThreads(50)
    local pad = LastNui('pad')
    check('Manette en main : haut envoyé à la page', pad and pad.key == 'up')
    PAD_PRESSED = { [201] = true }; NUI = {}
    RunThreads(50)
    check('A = accept', LastNui('pad') and LastNui('pad').key == 'accept')
    PAD_PRESSED = { [202] = true }; NUI = {}
    RunThreads(50)
    check('B = cancel', LastNui('pad') and LastNui('pad').key == 'cancel')
    PAD_PRESSED, KBM = {}, true
    Nui('cancel'); result()
end

tests['C23b Style latéral, touches choisies, manette coupée'] = function()
    CONFIG_OVERRIDE = "HexaConfig = { Dialog = { Style = 'side', Gamepad = false, Keys = { submit = 'NumpadEnter', cancel = 'Backspace' } } }"
    coreClient()
    local result = async(function() return Hexa.Confirm('Sûr ?') end)
    local m = LastNui('open')
    check('Panneau latéral', m.style == 'side')
    check('Touches choisies', m.keys.submit == 'NumpadEnter' and m.keys.cancel == 'Backspace')
    KBM, PAD_PRESSED = false, { [188] = true }; NUI = {}
    RunThreads(50)
    check('Manette désactivée dans la config', LastNui('pad') == nil)
    KBM, PAD_PRESSED = true, {}
    Nui('cancel'); result()
end

tests['C23c Style inconnu : centré'] = function()
    CONFIG_OVERRIDE = "HexaConfig = { Dialog = { Style = 'autre' } }"
    coreClient()
    local result = async(function() return Hexa.Confirm('Sûr ?') end)
    check('Style inconnu : centré', LastNui('open').style == 'center')
    Nui('cancel'); result()
end

tests['C24 Hexa.InputDialog (forme ox_lib)'] = function()
    coreClient()
    local result = async(function() return Hexa.InputDialog('Amende', {
        { type = 'input', label = 'Motif', required = true },
        { type = 'input', label = 'Code', password = true },
        { type = 'number', label = 'Montant', min = 1, max = 500, default = 50 },
        { type = 'slider', label = 'Gravité', min = 1, max = 5, default = 2 },
        { type = 'select', label = 'Type', options = { { value = 'a', label = 'Alpha' }, { value = 'b', label = 'Beta' } } },
        { type = 'checkbox', label = 'Copie', checked = true },
        { type = 'textarea', label = 'Note' },
        { type = 'date', label = 'Date' },
        { type = 'time', label = 'Heure' },
    }) end)
    local m = LastNui('open')
    check('Titre et 9 lignes', m.title == 'Amende' and #m.fields == 9)
    check('Types convertis', m.fields[2].masked == true and m.fields[3].numeric == true and m.fields[4].step == 1 and m.fields[7].multiline == true)
    check('Obligatoire seulement si demandé (comme ox_lib)', m.fields[1].required == true and m.fields[3].required == false and m.fields[8].required == false)
    check('Case cochée par `checked`', m.fields[6].default == true and m.fields[6].required == false)
    local r = Nui('submit', { values = { '', '', '', 2, 0, true, '', '', '' } })
    check('Seul le champ obligatoire vide est refusé', r.ok == false and #r.errors == 1 and r.errors[1].index == 1, r.errors and #r.errors)
    r = Nui('submit', { values = { 'Vitesse', '1234', '75', 3, 2, false, 'RAS', '06/11/2026', '14:30' } })
    local done, list = result()
    check('Liste de valeurs dans l’ordre des lignes', r.ok and done and #list >= 9 and list[1] == 'Vitesse' and list[2] == '1234' and list[3] == 75 and list[4] == 3 and list[5] == 'b'
        and list[6] == false and list[7] == 'RAS' and list[8] == '2026-11-06' and list[9] == '14:30', list and table.concat({ tostring(list[1]), tostring(list[2]), tostring(list[3]), tostring(list[4]), tostring(list[5]) }, '|'))
    -- Annulation, chaîne seule, lignes invalides
    result = async(function() return Hexa.InputDialog('Titre', { { type = 'input', label = 'X' } }) end)
    Nui('cancel')
    check('Annulé : nil', select(2, result()) == nil)
    result = async(function() return Hexa.InputDialog('Titre', { 'Juste un libellé' }) end)
    check('Ligne en simple texte = champ texte', LastNui('open').fields[1].label == 'Juste un libellé')
    Nui('cancel'); result()
    check('Aucune ligne : nil, rien ouvert', select(2, async(function() return Hexa.InputDialog('Titre', {}) end)()) == nil and not EXPORTS.IsDialogOpen())
end

tests['C28 Points : formes, carte, texte 3D, fréquence'] = function()
    coreClient()
    check('Fréquence fixe : 200 ms par défaut', HexaPoints.interval == 200)
    local hit = {}
    local box = EXPORTS.AddPoint({ coords = vector3(100, 0, 0), label = 'Boîte', box = { size = vector3(4, 10, 3), heading = 90.0 }, onSelect = function() hit.box = true end })
    local poly = EXPORTS.AddPoint({ coords = vector3(0, 0, 0), label = 'Poly', onSelect = function() hit.poly = true end,
        polygon = { points = { vector3(200, 0, 0), vector3(210, 0, 0), vector3(210, 10, 0), vector3(200, 10, 0) }, thickness = 4.0 } })
    check('Boîte et polygone acceptés', box and poly)
    check('Forme reconnue', HexaPoints.points[box].shape == 'box' and HexaPoints.points[poly].shape == 'polygon')
    check('Centre du polygone calculé', HexaPoints.points[poly].coords.x == 205.0 and HexaPoints.points[poly].coords.y == 5.0)
    BUTTONS[38] = 't_E'
    -- Boîte tournée de 90° : longue de 10 sur l'axe X une fois tournée
    CLIENT_COORDS = vector3(104, 0, 0); RunThreads(500)
    check('Boîte tournée : dans la longueur', HexaPoints.near[box] == true)
    CONTROLS[38] = true; RunThreads(1); CONTROLS[38] = false; RunThreads(10)
    check('Boîte : E déclenche dedans', hit.box == true)
    hit.box = nil
    CLIENT_COORDS = vector3(100, 6, 0); RunThreads(500)
    CONTROLS[38] = true; RunThreads(1); CONTROLS[38] = false; RunThreads(10)
    check('Boîte tournée : hors de la largeur, E ne fait rien', hit.box == nil)
    -- Polygone
    CLIENT_COORDS = vector3(205, 5, 0); RunThreads(500)
    CONTROLS[38] = true; RunThreads(1); CONTROLS[38] = false; RunThreads(10)
    check('Polygone : E déclenche dedans', hit.poly == true)
    hit.poly = nil
    CLIENT_COORDS = vector3(212, 5, 0); RunThreads(500)
    CONTROLS[38] = true; RunThreads(1); CONTROLS[38] = false; RunThreads(10)
    check('Polygone : juste à côté, rien', hit.poly == nil)
    CLIENT_COORDS = vector3(205, 5, 3.5); RunThreads(500)
    CONTROLS[38] = true; RunThreads(1); CONTROLS[38] = false; RunThreads(10)
    check('Polygone : trop haut, rien', hit.poly == nil)
    -- Carte, texte 3D
    CLIENT_COORDS = vector3(0, 0, 0)
    local n = #BLIPS
    local b = EXPORTS.AddPoint({ coords = vector3(5, 5, 0), label = 'Garage', text3d = true, blip = { sprite = 357, color = 3, label = 'Parking' }, onSelect = function() end })
    check('Icône de carte créée', #BLIPS == n + 1 and BLIPS[#BLIPS].x == 5)
    local names = {}
    for _, nat in ipairs(NATIVES) do names[#names + 1] = nat.name .. ':' .. tostring(nat.args[2] or nat.args[1]) end
    check('Sprite, couleur, nom', table.concat(names, ' '):find('SetBlipSprite:357', 1, true) and table.concat(names, ' '):find('SetBlipColour:3', 1, true) and table.concat(names, ' '):find('Parking', 1, true))
    TEXTS = {}; CLIENT_COORDS = vector3(5, 5, 0); RunThreads(500)
    check('Texte 3D affiché à portée', #TEXTS > 0)
    check('Retrait : icône de carte retirée', EXPORTS.RemovePoint(b) and BLIPS.removed == 1 and BLIPS.last == 77)
    TEXTS = {}; RunThreads(500)
    check('Retrait : plus de texte', #TEXTS == 0)
    local c = EXPORTS.AddPoint({ coords = vector3(300, 0, 0), label = 'Sans carte', onSelect = function() end })
    check('Sans blip : pas d’icône', #BLIPS == n + 1)
end

tests['C28b Points : fréquence réglable et bornée'] = function()
    CONFIG_OVERRIDE = "HexaConfig = { Points = { interval = 500 } }"
    coreClient()
    check('Fréquence réglée', HexaPoints.interval == 500)
end

tests['C28c Points : fréquence trop basse ou trop haute'] = function()
    CONFIG_OVERRIDE = "HexaConfig = { Points = { interval = 5 } }"
    coreClient()
    check('Minimum 50 ms', HexaPoints.interval == 50)
end

tests['C28d Points : fréquence trop haute'] = function()
    CONFIG_OVERRIDE = "HexaConfig = { Points = { interval = 99999 } }"
    coreClient()
    check('Maximum 1000 ms', HexaPoints.interval == 1000)
end

tests['C29 Points : ox_target et hexa_interact'] = function()
    coreClient()
    local calls = {}
    RESOURCES.ox_target = 'started'
    RESOURCE_EXPORTS.ox_target = {
        addSphereZone = function(z) calls[#calls + 1] = { 'sphere', z }; return 'zs' end,
        addBoxZone = function(z) calls[#calls + 1] = { 'box', z }; return 'zb' end,
        addPolyZone = function(z) calls[#calls + 1] = { 'poly', z }; return 'zp' end,
        removeZone = function(id) calls[#calls + 1] = { 'remove', id } end,
    }
    local selected = 0
    local s = EXPORTS.AddPoint({ coords = vector3(1, 2, 3), label = 'Sphère', onSelect = function() selected = selected + 1 end, canInteract = function() return true end })
    local b = EXPORTS.AddPoint({ coords = vector3(1, 2, 3), label = 'Boîte', box = { size = vector3(2, 3, 2), heading = 45.0 }, onSelect = function() end })
    local p = EXPORTS.AddPoint({ coords = vector3(0, 0, 0), label = 'Poly', polygon = { points = { vector3(0, 0, 0), vector3(5, 0, 0), vector3(5, 5, 0) } }, onSelect = function() end })
    check('ox_target : sphère, boîte, polygone', calls[1][1] == 'sphere' and calls[2][1] == 'box' and calls[3][1] == 'poly')
    check('ox_target : options du point', calls[1][2].options[1].label == 'Sphère' and calls[1][2].options[1].name == 'hexa_core:point:' .. s and calls[1][2].coords.x == 1)
    check('ox_target : boîte tournée', calls[2][2].rotation == 45.0 and calls[2][2].size.y == 3)
    check('ox_target : 3 sommets', #calls[3][2].points == 3)
    calls[1][2].options[1].onSelect({}); RunThreads(10)
    check('Sélection transmise au point', selected == 1)
    check('canInteract transmis', calls[1][2].options[1].canInteract() == true)
    MARKERS = 0; CLIENT_COORDS = vector3(1, 2, 3); RunThreads(1000)
    check('Avec ox_target : pas de marqueur ni de boucle d’affichage', MARKERS == 0 and next(HexaPoints.near) == nil)
    check('Retrait : zone ox_target retirée', EXPORTS.RemovePoint(s) and calls[#calls][1] == 'remove' and calls[#calls][2] == 'zs')
    -- hexa_interact passe avant ox_target ; polygone : ox_target
    local zones = {}
    RESOURCES.hexa_interact = 'started'
    RESOURCE_EXPORTS.hexa_interact = { AddSphereZone = function(z) zones[#zones + 1] = { 'sphere', z } end, AddBoxZone = function(z) zones[#zones + 1] = { 'box', z } end, RemoveZone = function() end }
    local n = #calls
    EXPORTS.AddPoint({ coords = vector3(1, 2, 3), label = 'I1', onSelect = function() end })
    EXPORTS.AddPoint({ coords = vector3(1, 2, 3), label = 'I2', box = { size = vector3(2, 2, 2) }, onSelect = function() end })
    EXPORTS.AddPoint({ coords = vector3(0, 0, 0), label = 'I3', polygon = { points = { vector3(0, 0, 0), vector3(5, 0, 0), vector3(5, 5, 0) } }, onSelect = function() end })
    check('hexa_interact : sphère et boîte', zones[1][1] == 'sphere' and zones[2][1] == 'box' and zones[2][2].size.x == 2)
    check('Polygone : ox_target (hexa_interact ne le gère pas)', #calls == n + 1 and calls[#calls][1] == 'poly')
    -- ox_target redémarre : les zones lui sont redonnées
    n = #calls
    TriggerEvent('onClientResourceStart', 'ox_target')
    check('ox_target redémarré : polygones redonnés', #calls > n)
    -- Aucun des deux : boucle interne
    RESOURCES.ox_target, RESOURCES.hexa_interact = nil, nil
    local own = EXPORTS.AddPoint({ coords = vector3(40, 0, 0), label = 'Interne', onSelect = function() end })
    CLIENT_COORDS = vector3(40.5, 0, 0); MARKERS = 0; RunThreads(1000)
    check('Sans ox_target ni hexa_interact : boucle interne', MARKERS > 0)
end

tests['S40 Sécurité : appels sensibles surveillés et limités'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Security = { maxCallsPerMinute = 3 } }"
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/instances.lua' })
    RESOURCE_EXPORTS.hexa_core = EXPORTS
    NewPlayer(1)
    INVOKER = 'hexa_shops'
    check('Ressource Hexa : pas d’alerte', EXPORTS.SetInstance(1) ~= nil and not printed('export sensible'))
    INVOKER = 'script_pirate'
    EXPORTS.GetInstance(1)
    EXPORTS.LeaveInstance(1)
    check('Ressource étrangère : alerte une fois', printed('script_pirate') and printed('LeaveInstance'))
    PRINTS = {}
    EXPORTS.LeaveInstance(1)
    check('Pas de répétition de l’alerte', not printed('export sensible'))
    -- limite : 3 appels par minute et par ressource (les 3 premiers ci-dessus : hexa_shops=1, script_pirate=2)
    INVOKER = 'hexa_shops'
    check('Sous la limite', EXPORTS.LeaveInstance(1) == false or true)
    PRINTS = {}
    local before = BUCKETS[1]
    local refused
    for i = 1, 5 do refused = EXPORTS.SetInstance(1) end
    check('Au-delà de la limite : refusé', refused == nil and HexaSecurity.counters.hexa_shops.count > 3)
    check('Limite signalée une fois', printed('dépasse 3 appels'))
    -- minute suivante : de nouveau autorisé
    RunThreads(61000)
    check('Minute suivante : autorisé', EXPORTS.SetInstance(1) ~= nil)
    INVOKER = nil
end

tests['S40b Sécurité : limite à 0 = illimité'] = function()
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Security = { maxCallsPerMinute = 0 } }"
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/instances.lua' })
    RESOURCE_EXPORTS.hexa_core = EXPORTS
    NewPlayer(1)
    INVOKER = 'hexa_shops'
    local ok = true
    for i = 1, 50 do if EXPORTS.SetInstance(1) == nil then ok = false end end
    check('Aucune limite', ok)
    INVOKER = nil
end

tests['S41 hexa_debug : activé et coupé sans redémarrer'] = function()
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/admin.lua' })
    check('Coupé au départ', not Hexa.IsDebug())
    RunCommand(0, 'hexa_debug on')
    check('Activé à chaud', Hexa.IsDebug() and CONVARS.hexa_debug == 'all')
    Hexa.resource = 'hexa_autre'
    check('Pour toutes les ressources', Hexa.IsDebug())
    RunCommand(0, 'hexa_debug off')
    check('Coupé à chaud', not Hexa.IsDebug())
    RunCommand(0, 'hexa_debug hexa_shops, hexa_police')
    check('Liste de ressources', CONVARS.hexa_debug == 'hexa_shops,hexa_police' and not Hexa.IsDebug())
    Hexa.resource = 'hexa_police'
    check('Ressource listée : debug actif', Hexa.IsDebug())
    PRINTS = {}
    RunCommand(0, 'hexa_debug')
    check('Sans argument : dit l’état', printed('Debug : actif'))
end

tests['S42 hexa_check : bilan de santé'] = function()
    RESOURCE_NAME = 'hexa_core'
    server(); load({ 'core/instances.lua', 'core/admin.lua' })
    RESOURCES.hexa_shops = 'started'; METADATA.hexa_shops = { version = '1.0.0-beta.1' }
    RESOURCES.oxmysql = 'started'
    local lines, problems = HexaHealth()
    local text = {}
    for _, l in ipairs(lines) do text[#text + 1] = l.text end
    text = table.concat(text, '\n')
    check('Framework affiché', text:find(Hexa.framework, 1, true))
    check('Ressource Hexa listée avec sa version', text:find('hexa_shops 1.0.0-beta.1', 1, true))
    check('Pas de webhook : indiqué sans erreur', text:find('aucun webhook', 1, true))
    RESOURCES.oxmysql = 'stopped'
    local _, p2 = HexaHealth()
    check('oxmysql arrêté : problème signalé', p2 > problems)
    PRINTS = {}
    RunCommand(0, 'hexa_check')
    check('Commande : bilan affiché', printed('Bilan de santé hexa_core') and printed('✘'))
    check('Commande : nombre de problèmes', printed('problème(s) à regarder'))
    -- le webhook n'est jamais affiché
    SERVER_CONFIG_OVERRIDE = "HexaServerConfig = { Logs = { webhook = 'https://discord.com/api/webhooks/1/secret' } }"
end

-- Exécution --------------------------------------------------------------------------------------------
if LIST_ONLY then
    local names = {}
    for name in pairs(tests) do names[#names + 1] = name end
    table.sort(names)
    return names
end
local ok, err = pcall(tests[ONLY])
if not ok then check('Le scénario s’exécute sans erreur', false, err) end
if #ERRORS > 0 then check('Aucune erreur de thread', false, table.concat(ERRORS, ' | ')) end
return results
