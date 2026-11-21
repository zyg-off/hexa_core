-- Réglages communs à TOUTES les ressources Hexa (envoyés aux joueurs : rien de secret ici).
-- Les webhooks Discord et les droits admin sont dans config_server.lua.
HexaConfig = {
    -- 'auto' : qbx_core, puis es_extended, puis qb-core. Forcez 'esx', 'qb' ou 'qbx' si besoin.
    Framework = 'auto',
    ESXResource = 'es_extended',
    QBResource = 'qb-core',
    QBXResource = 'qbx_core',

    -- Langue des textes : 'fr' ou 'en'.
    Locale = 'fr',

    -- IDs permanents : que faire de la ligne d'un personnage supprimé (Hexa.DeleteCharacter) ?
    --   'keep'   = on la garde, marquée « supprimée » (recommandé : le numéro n'est jamais réutilisé)
    --   'remove' = on l'efface (le numéro n'est quand même jamais redonné)
    Ids = { OnDelete = 'keep' },

    -- Noms réels des comptes dans chaque framework.
    Accounts = {
        esx = { cash = 'money', bank = 'bank' },
        qb = { cash = 'cash', bank = 'bank' },
        qbx = { cash = 'cash', bank = 'bank' },
    },

    -- Ordre de débit par défaut de Hexa.Pay (si hexa_banking n'est pas démarré).
    PaymentOrder = { 'cash', 'bank' },

    -- Messages de débogage dans la console, pour TOUTES les ressources Hexa.
    -- Pour une seule ressource, dans server.cfg :   setr hexa_debug "hexa_shops"   (plusieurs : "hexa_shops,hexa_police")
    Debug = false,

    -- Points d'intérêt (Hexa.AddPoint).
    Points = {
        -- Toutes les combien de millisecondes on cherche les points proches du joueur (50 à 1000).
        -- Plus petit = plus réactif, plus grand = plus économe. 200 convient presque toujours.
        interval = 200,
    },

    -- Dialogues (saisie, formulaire, confirmation) et aide à l'écran « [E] Action ».
    Dialog = {
        -- Position de l'aide : 'left' (milieu gauche), 'right' (milieu droit) ou 'bottom' (bas, au centre).
        HelpPosition = 'left',
        -- Style des boîtes : 'center' (fenêtre au milieu de l'écran) ou 'side' (panneau sur le côté droit).
        Style = 'center',
        -- Manette : flèches du D-pad pour naviguer, A pour valider, B pour annuler. false pour désactiver.
        Gamepad = true,
        -- Touches de validation / d'annulation du clavier (noms JavaScript : 'Enter', 'Escape', 'NumpadEnter'…).
        Keys = { submit = 'Enter', cancel = 'Escape' },
        -- Symbole affiché après les montants.
        Currency = '$',
        -- Les dialogues des scripts tiers s'affichent aussi au style Hexa. Mettez false en cas de souci.
        Redirect = {
            esx = true,     -- esx_menu_dialog, esx_textui (ESX.TextUI / ESX.HideUI), ESX.ShowHelpNotification
            qb = true,      -- qb-input (seulement si qb-input est arrêté)
        },
    },
}
