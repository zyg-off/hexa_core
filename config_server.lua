-- Réglages SERVEUR uniquement : ce fichier n'est jamais envoyé aux joueurs.
HexaServerConfig = {
    -- Administrateurs ------------------------------------------------------------------------------------
    -- Un joueur est admin s'il a la permission ACE ci-dessous (server.cfg :
    --   add_ace group.admin hexa.admin allow)
    -- ou l'un des groupes du framework listés.
    Admin = {
        ace = 'hexa.admin',
        groups = { 'admin', 'superadmin', 'god' },
    },

    -- Logs ----------------------------------------------------------------------------------------------
    -- Tous les logs (argent, objets, admin, sécurité, une catégorie par ressource…) vont dans UN SEUL salon Discord ;
    -- la catégorie est écrite en titre de chaque message. Webhook vide = pas de Discord.
    Logs = {
        name = 'Hexa Studio',
        webhook = '',       -- https://discord.com/api/webhooks/...

        -- Anti-spam Discord : les logs identiques (même ressource, catégorie, message et joueur) arrivés dans cette
        -- fenêtre (en secondes) sont regroupés en un seul message « +N identiques ». 0 = pas de regroupement.
        groupSeconds = 10,
        -- Nombre maximum de messages envoyés à Discord par minute. Les autres restent dans la base et le fichier.
        maxPerMinute = 30,

        -- Copie de tous les logs dans la table hexa_logs (même sans webhook). false pour désactiver.
        database = true,
        -- Copie de tous les logs dans un fichier par jour, dossier hexa_core/logs. false pour désactiver.
        file = true,
        -- Les logs plus vieux que ce nombre de jours sont supprimés de la base ; les fichiers sont réécrits en cycle.
        keepDays = 30,
    },

    -- Instances (routing buckets) ----------------------------------------------------------------------------
    Instances = {
        -- Premier numéro de bucket donné (les suivants : +1). Les scripts qui utilisent 1, 2, 3… à la main restent en dessous.
        firstBucket = 1000,
        -- hexa_core remet dans leur instance les joueurs qu'IL y a placés si un autre script change leur bucket.
        enforce = true,
    },

    -- Sécurité -----------------------------------------------------------------------------------------------
    Security = {
        -- Appels sensibles à hexa_core (suppression de personnage, instances, lecture des logs) autorisés
        -- par minute et par ressource. 0 = pas de limite.
        maxCallsPerMinute = 600,
    },

    -- Comptes d'entreprise ---------------------------------------------------------------------------------
    Society = {
        -- Qui peut retirer de l'argent avec Hexa.SocietyWithdraw : 'boss' = les grades « patron » du framework,
        -- ou un nombre = ce grade et au-dessus (ex. 3).
        withdrawGrade = 'boss',
        -- Découvert autorisé (en $) quand le core vérifie lui-même le solde (esx_addonaccount, qb-banking,
        -- qb-management, Renewed-Banking). 0 = jamais négatif. hexa_banking garde sa propre règle.
        maxOverdraft = 0,
        -- Journal des mouvements dans la table hexa_society_log (auteur, raison, montant, solde, date).
        journal = true,
    },

    -- Nouvelles versions ----------------------------------------------------------------------------------
    -- Au démarrage, la console signale les ressources Hexa qui ont une version plus récente.
    -- Rien n'est envoyé : hexa_core lit seulement ce fichier public.
    VersionCheck = {
        enabled = true,
        url = 'https://raw.githubusercontent.com/zyg-off/hexa-versions/main/versions.json',
    },
}
