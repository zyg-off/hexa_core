fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Hexa Studio'
description 'Fondation commune des ressources Hexa Studio (ESX, QBCore, QBox)'
version '1.0.0-beta.1'

ui_page 'web/index.html'

shared_scripts {
    'shared.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'core/security.lua',
    'ids.lua',
    'core/instances.lua',
    'core/logs.lua',
    'core/admin.lua',
    'main.lua'
}

dependency 'oxmysql'

-- client.lua : la partie incluse par chaque ressource Hexa.
-- core/ : ce que seule la ressource hexa_core fait pour tout le serveur (dialogues, points, compatibilité).
client_scripts {
    'client.lua',
    'core/dialog.lua',
    'core/compat.lua',
    'core/points.lua'
}

-- Lus par les autres ressources Hexa (@hexa_core/...) : envoyés aux joueurs.
-- config_server.lua n'est volontairement PAS dans cette liste (webhooks, droits admin).
files {
    'config.lua',
    'shared.lua',
    'client.lua',
    'web/index.html',
    'web/style.css',
    'web/app.js'
}

-- hexa_core est fourni gratuitement et en clair avec chaque ressource Hexa.
escrow_ignore {
    '**/*'
}
