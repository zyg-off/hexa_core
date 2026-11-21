# Hexa Core

Fondation commune de toutes les ressources **Hexa Studio**. Gratuite, en clair, **obligatoire**.

> **Version 1.0.0-beta.1** (bêta). Le *niveau d'API* reste `1.4.0` : les ressources Hexa écrites pour le core 1.4.0 démarrent sans rien changer. `Hexa.version` = version réelle, `Hexa.apiLevel` = niveau de fonctions (il ne fait qu'augmenter). `Hexa.RequireVersion('1.4.0')` compare au niveau d'API ; `Hexa.RequireVersion('1.0.0-beta.2')` compare à la version réelle (beta.10 est plus récente que beta.9).

**Démarrage** : sans **oxmysql** ou sans framework (ESX / QBCore / QBox), hexa_core l'écrit en rouge dans la console (avec la ligne `ensure` à ajouter) et s'arrête proprement, au lieu de planter plus loin.

Elle écrit une seule fois ce que chaque ressource refaisait de son côté :

- détection d'**ESX Legacy**, **QBCore** ou **QBox** ;
- **IDs permanents** : un par joueur, un par personnage ;
- joueur : identifiant, nom, métier, métadonnées, faim / soif, mort ;
- **argent**, paiements et banque via **hexa_banking** quand il tourne ;
- **objets et armes**, via **hexa_inventory** quand il tourne (sinon ESX, qb-inventory ou ox_inventory) ;
- **permis**, **véhicules** (propriétaire, clés via le futur **hexa_keys**) ;
- **admin**, commandes, **logs Discord** ;
- **base de données**, **langues FR / EN**, **contrôle de version** ;
- **rappels** client → serveur avec anti double-clic, **notifications**.
- **dialogues** au style Hexa : saisie, formulaire (texte, nombre, montant, liste, date, case à cocher), confirmation, aide « [E] Action » — et ceux d'**ESX** et de **qb-input** redirigés ;
- **gangs** (QBCore / QBox) et **job2** (ESX), **comptes d'entreprise**, **grades et embauche** (même hors ligne) ;
- **registre d'objets** commun, **instances**, **points d'intérêt** centralisés ;
- **logs** Discord **et en base**, **debug par ressource**, **vérification de nouvelle version**.

## Installation (serveur)

1. Placez `hexa_core` dans `resources/[hexa_studio]/`. **Le dossier doit s'appeler exactement `hexa_core`** (si vous téléchargez depuis GitHub, renommez `hexa_core-main` en `hexa_core`).
2. Dans `server.cfg`, démarrez-le **après** le framework et **avant** les autres ressources Hexa :
   ```
   ensure oxmysql            # obligatoire (IDs permanents)
   ensure es_extended        # ou qb-core, ou qbx_core
   ensure hexa_core
   ensure hexa_inventory
   ensure [hexa_studio]
   ```
3. `config.lua` : framework, langue (`fr` / `en`), noms des comptes, dialogues. **Une seule fois pour tout l'écosystème.**
4. `config_server.lua` : webhooks Discord et administrateurs. Ce fichier **n'est jamais envoyé aux joueurs**.
5. Admins par permission ACE (facultatif), dans `server.cfg` :
   ```
   add_ace group.admin hexa.admin allow
   ```
6. **ESX seulement :** `esx_textui`, `esx_notify` et `esx_progressbar` ne sont pas fournies (les anciennes coquilles ont été retirées). Ne gardez pas les originales si vous voulez que les messages passent par Hexa : `ESX.ShowNotification` et `ESX.TextUI` s'appuient sur elles, voyez la section « Limites connues ».
7. **QBCore :** pour que `qb-input` passe par hexa_core, arrêtez `qb-input`.

Au démarrage, la console affiche : `[hexa_core] v1.0.0-beta.1 — framework : esx — langue : fr`.

Sans framework démarré, la console affiche une erreur rouge et les fonctions renvoient des valeurs neutres (0, false, nil) : rien ne plante.

## Comment ça marche

hexa_core fonctionne comme **ox_lib** : une ressource Hexa *inclut* ses fichiers, qui s'exécutent **à l'intérieur** de cette ressource. Chaque ressource obtient sa propre table `Hexa`, sans passer par un export à chaque appel.

```lua
-- fxmanifest.lua d'une ressource Hexa
dependency 'hexa_core'

shared_scripts { '@hexa_core/shared.lua', 'config.lua' }        -- toujours en premier
server_scripts { '@oxmysql/lib/MySQL.lua', '@hexa_core/server.lua', 'server/main.lua' }
client_scripts { '@hexa_core/client.lua', 'client/main.lua' }
```

`@oxmysql/lib/MySQL.lua` est facultatif : `Hexa.DB` passe sinon par les exports d'oxmysql.

En tête du code de la ressource, exigez la version du core dont elle a besoin :

```lua
if not Hexa.RequireVersion('1.0.0') then return end
```

## API — partagée (client et serveur)

```lua
Hexa.framework        -- 'esx', 'qb', 'qbx' ou nil
Hexa.isQB             -- vrai pour QBCore ET QBox (même PlayerData)
Hexa.core             -- objet ESX ou QBCore (nil sous QBox : exports qbx_core)
Hexa.resource         -- nom de la ressource qui utilise hexa_core
Hexa.Config           -- réglages de config.lua

Hexa.Print('Démarré', 'info')         -- [hexa_banking] Démarré   (info, warn, error, debug)

local T = Hexa.Locale({
    fr = { paid = 'Payé : %s.' },
    en = { paid = 'Paid: %s.' },
})
T('paid', Hexa.Money(12500))          -- langue de config.lua ; traduction manquante -> français

Hexa.Amount(valeur, max)              -- entier ≥ 0 et ≤ max, sinon nil (TOUT montant venu d'un client)
Hexa.CleanText(valeur, 120)           -- texte nettoyé, sinon nil (TOUT texte venu d'un client)
Hexa.Plate(' ab 123 ')                -- 'AB 123'
Hexa.IsWeapon('weapon_pistol')        -- true
Hexa.Copy(table)
Hexa.VersionAtLeast('1.10.0', '1.9')  -- true
Hexa.RequireVersion('1.2.0')

Hexa.Debug('Achat', item, count)      -- affiché seulement en mode debug pour cette ressource
Hexa.IsDebug()
```

**Debug par ressource**, dans `server.cfg` : `setr hexa_debug "hexa_shops,hexa_police"` (ou `"all"`). `Debug = true` dans `config.lua` l'active pour toutes.

## API — serveur

### Joueur

```lua
Hexa.GetPlayer(source)                -- xPlayer (ESX) ou Player (QBCore / QBox)
Hexa.Identifier(source)               -- identifier (ESX) / citizenid (QB, QBox)
Hexa.Name(source)                     -- nom du personnage
Hexa.Identity(source)                 -- { firstname, lastname, birthdate, sex = 'm' / 'f', height, birthplace, nationality }
Hexa.Job(source)                      -- nom, grade, enService
Hexa.Gang(source)                     -- nom, grade, libellé du gang (QBCore / QBox) ou du job2 (ESX), ou nil
Hexa.HasJob(source, 'police', 3)      -- ou { 'police', 'sheriff' } ; le gang / job2 compte aussi
Hexa.SourceOf(identifier)             -- joueur connecté qui joue ce personnage, ou nil
Hexa.Distance(source, coords) / Hexa.IsNear(source, coords, 2.0)

Hexa.GetMeta(source, 'stress') / Hexa.SetMeta(source, 'stress', 20)
Hexa.GetNeeds(source)                 -- faim, soif en % (ESX : via esx_status)
Hexa.SetNeed(source, 'hunger', 100)
Hexa.IsDead(source)                   -- mort ou à terre
Hexa.LastSeen(source)                 -- dernière déconnexion (secondes Unix) ou nil
Hexa.Profile(source, { needs = true }) -- fiche complète en un appel : ids, identité, métier, grade, service,
                                      -- gang, position, téléphone (hexa_phone), mort, admin, faim / soif, métadonnées
```

### IDs permanents

hexa_core donne à chacun deux **numéros courts et définitifs**, stockés en base (`hexa_players`, `hexa_characters`) et **jamais réutilisés**, identiques sur ESX, QBCore et QBox :

| | Exemple | Unique par | Change ? |
| --- | --- | --- | --- |
| **ID joueur** | `#12` | compte FiveM (licence Rockstar) | jamais, même après un wipe des personnages |
| **ID personnage** | `#31` | personnage (identifier ESX / citizenid) | jamais ; un nouveau personnage reçoit un nouvel ID |

Au premier démarrage, les personnages déjà existants sont numérotés **dans l'ordre de création** (QBCore / QBox : `players.id` ; ESX : colonne `created_at` si elle existe, sinon ordre alphabétique, avec un avertissement). Un personnage supprimé garde son ID : `Hexa.DeleteCharacter(identifier)` le marque supprimé (ou efface la ligne avec `Ids.OnDelete = 'remove'`, sans jamais redonner le numéro) et envoie l'événement `hexa_core:characterDeleted` ; `Hexa.OnCharacterDeleted(function(id, identifier) … end)` l'écoute. ESX réutilise parfois le même identifiant pour un nouveau personnage : il reçoit un **nouvel** ID.

À ne pas confondre avec le numéro de la console (`source`), qui change à chaque connexion.

```lua
Hexa.PlayerId(source)            -- 12 (nil quelques ms après la connexion)
Hexa.CharId(source)              -- 31 (nil tant qu'aucun personnage n'est choisi)
Hexa.SourceOfPlayerId(12)        -- numéro de console s'il est connecté, sinon nil
Hexa.SourceOfCharId(31)
Hexa.CharIdOf(identifier)        -- personnage hors ligne -> ID
Hexa.IdentifierOfCharId(31)      -- ID -> identifier, hors ligne aussi
```

Côté client : `Hexa.PlayerId()` et `Hexa.CharId()`, **pour l'affichage seulement** : toute vérification se fait côté serveur.

Les IDs sont stockés dans les tables `hexa_players` et `hexa_characters`, créées automatiquement. Les logs Discord les affichent (`#12 / #31`).

### Métiers, grades, entreprises

```lua
Hexa.JobInfo('police')                -- { name, label, grades = { { grade = 0, name, label, salary, boss }, … } }
Hexa.JobInfo('ballas', true)          -- un gang (QBCore / QBox)
Hexa.SetJob(source, 'police', 2)      -- refusé si le métier ou le grade n'existe pas
Hexa.SetJobOffline(identifier, 'unemployed', 0)   -- connecté ou non (renvoi, promotion…)
Hexa.JobMembers('police')             -- { { identifier, name, grade, source si connecté }, … } du plus haut grade au plus bas
Hexa.SetGrade(source, 3)              -- change seulement le grade du métier actuel
Hexa.SetGang(source, 'ballas', 1)     -- gang (QBCore / QBox) ou job2 (ESX qui l'a) ; refusé si inexistant
Hexa.FireJob(identifier)              -- renvoi : retour au chômage, connecté ou non

Hexa.OnDuty(source)                   -- en service ? (ESX : avoir un métier = en service)
Hexa.SetDuty(source, false)           -- QBCore / QBox ; ESX n'a pas cette notion : renvoie false et le dit une fois

Hexa.SocietyBalance('police')         -- solde, ou nil si aucun système de comptes
Hexa.AddSocietyMoney('police', 500, 'Amende')              -- 4e paramètre facultatif : auteur (numéro du joueur ou texte)
Hexa.RemoveSocietyMoney('police', 200, 'Réparation')       -- refusé si le solde ne suffit pas (voir découvert)
Hexa.SocietyCanWithdraw(source, 'police')                  -- le joueur est-il patron (ou au grade réglé) ?
Hexa.SocietyWithdraw(source, 'police', 200, 'Achat')       -- retrait : le grade est vérifié ici
Hexa.SocietyTransfer('police', 'ems', 100, 'Aide')         -- virement ; dépôt impossible = retrait annulé
Hexa.SocietyHistory('police', 50)                          -- derniers mouvements, du plus récent : { amount, balance, reason, author, at }
Hexa.CreateSociety('taxi')                                 -- seulement avec hexa_banking (il crée le compte à la demande)
```

Comptes d'entreprise : **hexa_banking** s'il tourne, sinon `esx_addonaccount` (`society_police`), `qb-banking`, `qb-management` ou `Renewed-Banking`. Les comptes de gang fonctionnent de la même façon (nom du gang).

Réglages dans `config_server.lua` → `Society` : `withdrawGrade` (`'boss'` ou un grade), `maxOverdraft` (découvert autorisé, 0 par défaut), `journal` (table `hexa_society_log`, créée toute seule). Le découvert ne s'applique que là où le core vérifie lui-même le solde ; hexa_banking garde sa propre règle. Il n'existe pas de fonction pour supprimer un compte : aucun des systèmes ne l'offre de façon officielle.

### Argent — `'cash'` ou `'bank'`

```lua
Hexa.Balance(source, 'bank')
Hexa.AddMoney(source, 'cash', 500, 'Raison')
Hexa.RemoveMoney(source, 'bank', 200, 'Raison')               -- false si solde insuffisant
local ok, account = Hexa.Pay(source, 80, 'Boutique')          -- espèces puis banque
local ok, account = Hexa.Pay(source, 80, 'Amende', { 'bank' })
Hexa.Refund(source, account, 80, 'Annulé')
```

Si **hexa_banking** est démarré :

- `Pay` et `Refund` passent par lui ;
- les mouvements **banque** de `AddMoney` / `RemoveMoney` aussi (ils apparaissent dans l'historique du joueur) ;
- si hexa_banking renvoie une erreur, l'opération est **refusée**, jamais retentée en direct (pas de double débit).

### Objets et armes

```lua
Hexa.ItemLabel('bread')               -- 'Pain' (nil si l'objet n'existe pas)
Hexa.ItemCount(source, 'bread') / Hexa.HasItem(source, 'bread', 2)
Hexa.CanCarry(source, 'water', 3)
Hexa.AddItem(source, 'document', 1, { serial = 'A-123' })
Hexa.AddItem(source, 'WEAPON_PISTOL', 1, { ammo = 24 })
Hexa.RemoveItem(source, 'bread', 1)
Hexa.RegisterUsableItem('phone', function(source, item) ... end)
```

Ordre : **hexa_inventory** → inventaire du framework (ESX, qb-inventory, **ox_inventory sous QBox**). Les noms sont mis à la bonne casse (QBCore : minuscules ; QBox : objets en minuscules, armes en majuscules). Sur ESX sans hexa_inventory, les armes vont dans le loadout.

### Registre d'objets

```lua
Hexa.Item('bread')   -- { name, label, weight, image, usable, unique, stackable, limit, category, weapon, rare, description } ou nil
Hexa.Items()         -- { [nom] = { … } } : tous les objets
Hexa.RegisterItem('id_card', { label = 'Carte', weight = 5, unique = true })  -- true / false
```

**Une seule source** : ox_inventory s'il tourne, sinon la liste du framework (celle d'hexa_inventory sur ESX). `RegisterItem` passe par hexa_inventory ou par QBCore (`Functions.AddItem`) ; sans moyen officiel (ESX seul, QBox), il renvoie `false` et le dit en console : l'objet se déclare alors dans la configuration de l'inventaire.

Lu dans ESX, QBCore ou ox_inventory (QBox). `image` est une adresse `nui://` vers hexa_inventory, ox_inventory ou qb-inventory (le premier démarré). `usable` : enregistré comme objet utilisable.

### Instances (routing buckets)

```lua
Hexa.SetInstance(source)                          -- seul (appartement, création de personnage…)
Hexa.SetInstance(source, 'appart_12')             -- partagée : tous ceux qui entrent dans 'appart_12' se voient
Hexa.SetInstance(source, 'course', { population = true, vehicle = true })   -- garder PNJ et circulation, emmener le véhicule
Hexa.GetInstance(source)                          -- nom, numéro (nil dans le monde normal)
Hexa.LeaveInstance(source)                        -- retour dans l'instance d'avant
```

Numéros attribués par hexa_core pour tout le serveur (à partir de `Instances.firstBucket`, 1000 par défaut, dans `config_server.lua`) : deux ressources ne se gênent jamais. Une instance vide est libérée.

Si un autre script change le bucket d'un joueur que hexa_core a placé, hexa_core le remet dans son instance (toutes les 5 s, seulement s'il y a des joueurs placés) et avertit **une fois** en console et dans les logs (`Instances.enforce = false` pour désactiver).

### Permis

```lua
Hexa.HasLicense(source, 'driver')     -- ESX : esx_license ; QB / QBox : metadata.licences
Hexa.AddLicense(source, 'weapon')
Hexa.RemoveLicense(source, 'driver')
```

### Véhicules et clés

```lua
Hexa.VehicleOwner('AB 123')           -- identifiant du propriétaire (owned_vehicles / player_vehicles)
Hexa.IsVehicleOwner(source, 'AB 123')
Hexa.GiveKeys(source, plate) / Hexa.RemoveKeys(source, plate) / Hexa.HasKeys(source, plate)
```

Les clés sont réservées au futur **hexa_keys**. Tant qu'il n'est pas démarré, ces trois fonctions renvoient `false`. Contrat attendu de hexa_keys : exports serveur `GiveKeys`, `RemoveKeys`, `HasKeys(source, plaque) -> true / false`.

### Base de données

```lua
Hexa.Schema({
    'CREATE TABLE IF NOT EXISTS `hexa_x` (`id` INT NOT NULL AUTO_INCREMENT, PRIMARY KEY (`id`))',
})                                    -- au démarrage ; Hexa.DB.ready = true une fois fait
Hexa.DB.query / single / scalar / insert / update(requête, paramètres)   -- attendent le résultat
```

### Administration et commandes

```lua
Hexa.IsAdmin(source)                  -- console, permission ACE hexa.admin ou groupe du framework
Hexa.Command('heal', { admin = true, help = 'Soigner un joueur' }, function(source, args, raw)
    ...
end)
```

Une commande `admin = true` est refusée (avec un message) aux non-admins et **journalisée** dans la catégorie de logs `admin`. `help` ajoute la suggestion dans le chat.

### Logs Discord

```lua
Hexa.Log('money', 'Retrait de 500 $', source, { Distributeur = 'Legion Square' }, 'warning')
-- niveaux : info, success, warning, error
```

Un **seul salon Discord** : `Logs.webhook` dans `config_server.lua` (l'ancien réglage `default` est toujours lu). Vide ou ne commençant pas par `https://` : pas de Discord, le reste continue. Nom et identifiant du joueur sont ajoutés automatiquement.

Une seule file d'envoi pour tout le serveur, dans hexa_core, avec :
- **regroupement** : les logs de la même catégorie arrivés dans les `groupSeconds` (10) secondes partent dans un seul message ;
- **anti-spam** : au plus `maxPerMinute` (30) messages par minute vers Discord (le surplus est regroupé, rien n'est perdu en base) ;
- renvoi automatique si Discord limite le débit (erreur 429).

**En base :** chaque log est aussi gardé dans la table `hexa_logs` (même sans webhook), puis supprimé après `keepDays` jours (30 par défaut). Si la base est en panne, les logs attendent et sont écrits plus tard. `Logs.database = false` pour désactiver.

**En fichier :** `hexa_core/logs/jour_NN.log`, un fichier par jour sur un cycle de `keepDays` fichiers (FiveM ne sait pas supprimer un fichier : un fichier est simplement réécrit quand son jour revient). Le dossier `logs/` doit exister (livré avec un `LISEZMOI.txt`) ; sinon un avertissement unique s'affiche. `Logs.file = false` pour désactiver. Limite de 2 Mo par fichier.

Lecture pour un futur panneau d'administration :

```lua
exports.hexa_core:GetLogs({ category = 'money', identifier = 'char:1', search = 'retrait', limit = 100 })
```

### Debug, bilan de santé, sécurité

Commandes (console du serveur, ou en jeu pour les admins) :

```
hexa_debug              -- dit si le debug est actif
hexa_debug on / off     -- toutes les ressources Hexa, sans redémarrer
hexa_debug hexa_shops   -- une ou plusieurs ressources (séparées par des virgules)
hexa_check              -- bilan : framework, oxmysql, base, Discord, ressources Hexa et versions, instances
```

`hexa_check` n'affiche jamais le webhook Discord. Chaque ligne est marquée ✔ ou ✘.

Les exports sensibles (`DeleteCharacter`, `SetInstance`, `LeaveInstance`, `GetLogs`) sont surveillés : une ressource qui n'est pas Hexa et les appelle est signalée **une fois** (console + logs, catégorie `security`) sans être bloquée ; au-delà de `Security.maxCallsPerMinute` (600) appels par minute et par ressource, les appels sont refusés jusqu'à la minute suivante (`0` = pas de limite).

### Nouvelles versions

Au démarrage, hexa_core lit un petit fichier public (`VersionCheck.url` dans `config_server.lua`) et signale en console les ressources Hexa installées qui ont une version plus récente. Rien n'est envoyé. Format :

```json
{ "hexa_core": { "version": "1.0.0-beta.1", "notes": "Fondation." }, "hexa_shops": "1.1.0" }
```

### Événements, notifications, rappels

```lua
Hexa.OnPlayerLoaded(function(source) ... end)
Hexa.OnPlayerDropped(function(source, reason) ... end)
Hexa.OnJobChange(function(source, job, grade) ... end)

Hexa.Notify(source, 'Achat effectué', 'success')   -- info, success, error, warning

Hexa.Callback('withdraw', function(source, data)
    local amount = Hexa.Amount(data.amount, 5000)
    if not amount then return { ok = false, message = 'Montant invalide.' } end
    return { ok = Hexa.RemoveMoney(source, 'bank', amount) }
end, { lock = true, cooldown = 300 })
```

- `lock = true` : une seule demande verrouillée à la fois par joueur. Deux clics rapides ne retirent jamais deux fois.
- `cooldown` : délai minimal en ms entre deux appels ; le client réessaie tout seul.

## API — client

```lua
local result = Hexa.Request('withdraw', { amount = 500 })   -- dans un thread ; timeout après 8 s

Hexa.Notify('Message', 'error')
Hexa.SetNotify(function(message, kind)       -- affichage propre à la ressource (toast dans l'interface)
    if not isOpen then return false end      -- false : affichage normal
    SendNUIMessage({ action = 'toast', message = message, kind = kind })
    return true
end)

Hexa.GetPlayerData()
Hexa.Job()                                    -- nom, grade, libellé, enService
Hexa.Gang()                                   -- nom, grade, libellé (gang QBCore / QBox, job2 ESX)
Hexa.HasJob('police', 2)                      -- le gang / job2 compte aussi
Hexa.IsDead()
Hexa.GetPlate(vehicle)

Hexa.loaded
Hexa.OnPlayerLoaded(function() ... end)       -- part tout de suite si déjà chargé
Hexa.OnPlayerUnloaded(function() ... end)
Hexa.OnJobChange(function(job, grade) ... end)

-- Point d'interaction : Alt + clic avec hexa_interact, sinon marqueur + touche E.
local id = Hexa.AddPoint({
    coords = vector3(149.9, -1040.7, 29.4), label = 'Ouvrir la banque', icon = 'money',
    distance = 2.0, canInteract = function() return true end,
    onSelect = function() openBank() end,      -- appelé dans un thread
})
Hexa.RemovePoint(id)

Hexa.Help('Appuyez sur ~INPUT_CONTEXT~ pour ouvrir')    -- à chaque image ; affichée « Appuyez sur [E] pour ouvrir »
Hexa.ShowHelp('[E] Ouvrir le garage', 'warning')         -- reste affichée jusqu'à Hexa.HideHelp()
Hexa.HideHelp()
Hexa.Blip(coords, { sprite = 108, color = 2, scale = 0.7, label = 'Banque' })
```

Les points de **toutes** les ressources sont gérés par une seule boucle, dans hexa_core, et disparaissent (avec leur icône de carte) quand leur ressource s'arrête.

Options :
- `key` (touche, 38 = E), `marker = false` ou `{ type, size, color = { r, g, b, a } }`, `help` ;
- **forme** : sphère par défaut (`distance`, `radius`) ; `box = { size = vector3(4, 10, 3), heading = 90.0 }` ; `polygon = { points = { vector3(…), … }, thickness = 4.0 }` (3 sommets minimum) ;
- `blip = { sprite = 357, color = 3, scale = 0.8, label = 'Parking' }` : icône sur la carte, retirée avec le point ;
- `text3d = true` (ou un texte) : texte flottant au-dessus du point.

Qui s'occupe du point : hexa_interact (sphère et boîte) ; sinon ox_target (sphère, boîte, polygone) ; sinon la boucle de hexa_core. Un polygone passe par ox_target s'il est là, sinon par la boucle de hexa_core. La recherche des points proches tourne à fréquence fixe (`Points.interval` dans `config.lua`, 200 ms, entre 50 et 1000) ; l'affichage ne tourne à chaque image que tant qu'un point est à portée. `canInteract` est demandé 4 fois par seconde au plus.

### Dialogues

Fenêtre au style Hexa (centrée, ou panneau latéral : `Dialog.Style = 'side'`). À appeler depuis un thread : la fonction attend la réponse. C'est toujours hexa_core qui vérifie la réponse, jamais la page : la valeur reçue respecte les règles.

```lua
-- Un champ : renvoie directement la valeur, nil si annulé.
local montant = Hexa.Input({ title = 'Retrait', label = 'Montant', type = 'amount', min = 1, max = 5000 })
local plaque = Hexa.Input('Nouvelle plaque')

-- Plusieurs champs : renvoie une table (par nom et par position), nil si annulé.
local r = Hexa.Form({
    { type = 'select', name = 'motif', label = 'Motif', options = { { value = 'speed', label = 'Excès de vitesse' }, 'Feu rouge' } },
    { type = 'amount', name = 'montant', label = 'Montant', min = 50, max = 5000 },
    { type = 'date', name = 'date', label = 'Date', min = '2026-01-01' },
    { type = 'textarea', name = 'note', label = 'Remarque', required = false, max = 200 },
    { type = 'checkbox', name = 'copie', label = 'Envoyer une copie', default = true },
}, { title = 'Amende', description = 'Contravention', submit = 'Émettre' })
if r then print(r.motif, r.montant, r.date, r.copie) end

if Hexa.Confirm({ title = 'Vendre ?', message = 'Action définitive.', danger = true, confirm = 'Vendre' }) then … end

-- Petit menu liste : renvoie la valeur de l'option (son numéro sans `value`), puis son numéro ; nil si annulé.
local action = Hexa.Menu({ title = 'Garage', options = {
    { label = 'Sortir le véhicule', value = 'out' },
    { label = 'Réparer', description = '150 $', value = 'fix' },
    { label = 'Vendre', value = 'sell', disabled = true },
} })

-- Même forme que lib.inputDialog d'ox_lib : renvoie la liste des valeurs dans l'ordre des lignes, nil si annulé.
local r = Hexa.InputDialog('Amende', {
    { type = 'input', label = 'Motif', required = true },
    { type = 'number', label = 'Montant', min = 1, max = 500 },
    { type = 'input', label = 'Code', password = true },
    { type = 'checkbox', label = 'Copie', checked = true },
})
if r then print(r[1], r[2]) end
```

| Type | Renvoie | Règles |
| --- | --- | --- |
| `text` (défaut) / `textarea` | texte nettoyé | `min` / `max` = longueur ; vide refusé sauf `required = false` |
| `number` | nombre (« 2,5 » ou « 2.5 ») | `min` / `max` = valeurs |
| `amount` | nombre entier | au moins 1 par défaut ; « 1 500 » et « 250 $ » compris |
| `select` | la `value` de l'option choisie | `options` : textes ou `{ value, label }` |
| `date` | `'AAAA-MM-JJ'` | saisie JJ/MM/AAAA (MM/DD/YYYY en anglais) ; `min` / `max` au format AAAA-MM-JJ |
| `checkbox` | true / false | `required = true` : doit être cochée |
| `password` | texte **tel quel** (espaces gardés) | masqué ; `min` / `max` = longueur |
| `pin` | texte de chiffres (« 0042 ») | masqué ; `length` = nombre de chiffres, 3 à 8 (4 par défaut) |
| `slider` | nombre | `min` (0), `max` (100), `step` (1), `unit` ; le pas et les bornes sont revérifiés |
| `time` | `'HH:MM'` | saisie « 21:30 », « 9h05 » ou « 9:05 » |

Autres options d'un champ : `name`, `label`, `description`, `placeholder`, `default`, `required`. Clavier : Entrée valide, Échap annule, Ctrl + Entrée dans une zone de texte ; flèches haut / bas pour passer d'un champ à l'autre dans un menu.

**Réglages** (`config.lua` → `Dialog`) : `Style` (`'center'` ou `'side'`), `Keys` (touches de validation et d'annulation, noms JavaScript : `'Enter'`, `'NumpadEnter'`, `'Escape'`…), `Gamepad` (manette : D-pad pour naviguer, A valide, B annule ; ignorée tant que le clavier est en main), `HelpPosition`, `Currency`. Une touche d'écriture (lettre, Retour arrière) n'annule jamais une saisie.

**Toujours revérifier côté serveur** ce qui touche à l'argent ou aux objets : la boîte aide le joueur, elle ne protège pas d'un tricheur.

### Scripts tiers redirigés (`config.lua` → `Dialog.Redirect`)

| Script | Ce qui change |
| --- | --- |
| esx_menu_dialog | `ESX.UI.Menu.Open('dialog', …)` ouvre la boîte Hexa (même comportement : nombre arrondi, refus de 0 et des négatifs) |
| esx_textui | `ESX.TextUI` / `ESX.HideUI` affichent l'aide Hexa |
| ESX (aide) | `ESX.ShowHelpNotification` s'affiche dans l'aide Hexa |
| qb-input | `exports['qb-input']:ShowInput(…)` ouvre la boîte Hexa (si qb-input est arrêté) |

Les événements réseau portent le nom de la ressource (`hexa_banking:hexa:request`…) : deux ressources Hexa ne reçoivent jamais les messages l'une de l'autre.

## Règles pour faire évoluer le core

- **On ajoute, on ne retire jamais** une fonction : toutes les ressources Hexa installées chez les clients en dépendent.
- Une fonction n'entre dans le core que si **au moins deux ressources** s'en servent.
- Pas de logique de jeu : elle reste dans les ressources. Seule interface du core : les dialogues et l'aide, communs à toutes.

## Migrer une ressource Hexa

Exemple avec hexa_shops :

| Avant (dans la ressource) | Après |
| --- | --- |
| `server/bridge.lua` entier | supprimé |
| `Config.Framework`, `ESXResource`, `QBResource`, comptes | supprimés (dans hexa_core) |
| `Bridge.Identifier / Name / Job` | `Hexa.Identifier / Name / Job` |
| `Bridge.Balance / AddMoney / RemoveMoney` | `Hexa.Balance / AddMoney / RemoveMoney` |
| `Bridge.ItemLabel / AddItem / RemoveItem / ItemCount` | `Hexa.ItemLabel / AddItem / RemoveItem / ItemCount` |
| `Bridge.HasLicense` | `Hexa.HasLicense` |
| `HexaX.T` + textes | `local T = Hexa.Locale({ fr = {...}, en = {...} })` |
| `sendRequest` / `pending` / `:client:response` | `Hexa.Request` / `Hexa.Callback` |
| fonction `notify` côté client | `Hexa.Notify` (+ `Hexa.SetNotify` pour le toast) |

## Tests

`tests/run.py` rejoue 1 757 vérifications sur une simulation d'**ESX**, de **QBCore** et de **QBox** (avec ox_inventory). `--ui` ajoute 60 vérifications de la page des dialogues dans Chromium :

```
pip install lupa
python tests/run.py          # + --ui (npm install playwright)
```

Aperçu des dialogues : ouvrez `web/index.html?demo` dans un navigateur.

## Limites connues

- **QBox** : testé sur simulation uniquement (exports `qbx_core` et `ox_inventory`), pas encore sur un vrai serveur QBox.
- **ESX** : `GetMeta` / `SetMeta` demandent ESX Legacy récent (`xPlayer.getMeta`). Faim / soif et permis demandent `esx_status` et `esx_license`.
- **ox_lib** : `lib.inputDialog` ne peut pas être redirigé proprement (il s'exécute dans ox_lib) ; les scripts ox_lib gardent leur boîte. Pour vos propres scripts, `Hexa.InputDialog` a la même forme.
- **Manette** : lue par hexa_core (D-pad, A, B) ; écrite d'après la documentation de FiveM, pas encore essayée avec une vraie manette. Même chose pour l'aide `DrawText` de qb-core.
- **Aide ESX affichée une seule fois** (pas en boucle) : visible seulement 300 ms dans le panneau Hexa. Les scripts ESX l'appellent presque toujours en boucle.
- **qb-input, cases à cocher** : chaque case devient une case séparée ; la réponse donne `'true'` / `'false'` par option.
- **Embauche hors ligne, liste des employés** : écrites pour les tables standard (`users`, `players`, `player_groups` de QBox), testées sur simulation uniquement.
- **job2 (ESX)** : lu seulement si votre version d'ESX le fournit (`xPlayer.job2`).
- **Salaire d'un grade** : lisible (`JobInfo`), mais à modifier dans la configuration du framework, pas par le core.
- **Registre d'objets** : côté serveur seulement. `RegisterItem` : pas de moyen officiel sous ESX seul ni QBox.
- **Langue du joueur** : FiveM ne la donne pas côté serveur ; la langue vient du réglage du serveur.
- **Ordre des IDs ESX** : la table `users` n'a pas de date de création ; sans colonne `created_at`, l'ordre initial est alphabétique (une seule fois).
- **Mort / menottes** : `IsDead` lit QBCore / QBox, l'état `isDead` et la santé. Il n'existe pas d'état « menotté » standard : il viendra avec hexa_police.
- **Logs** : un seul salon Discord (plus de salon par catégorie). Le fichier du jour ne se supprime pas : il est réécrit quand son jour revient. Mesure `resmon 1` sur un serveur ESX réel (2026-11-20) : **0,03 ms** pour hexa_core au repos.
- **ESX sans esx_textui / esx_notify / esx_progressbar** : testé en jeu (ESX Legacy 1.15, 2026-11-20), console sans erreur. Si une version d'ESX plus ancienne affiche des erreurs à ce sujet, il faut des ressources de ces noms.
- **Sécurité** : les appels d'un script étranger sont signalés, pas bloqués.

## Licence

Usage libre et gratuit, **redistribution interdite** : voir le fichier `LICENSE` (français et anglais). Téléchargez toujours hexa_core depuis la page officielle Hexa Studio.
