-- Redirection des dialogues des scripts tiers vers ceux de hexa_core (exécuté dans hexa_core seulement).
-- Désactivable dans config.lua : Dialog.Redirect = { esx = false, qb = false }.
local redirect = (Hexa.Config.Dialog or {}).Redirect or {}
local D = HexaDialog

-- Répond à exports['autre_ressource']:Fonction(...) quand cette ressource n'est pas démarrée.
local function provide(resource, name, fn)
    AddEventHandler(('__cfx_export_%s_%s'):format(resource, name), function(setCB) setCB(fn) end)
end

-- ESX ------------------------------------------------------------------------------------------------------
if redirect.esx ~= false then
    -- esx_textui : ESX.TextUI(message, type) / ESX.HideUI(). ESX appelle exports['esx_textui'] :
    -- esx_textui doit être DÉMARRÉ (le client le voit absent sinon), mais vidé de ses scripts : hexa_core répond.
    local function textUI(message, kind) D.showHelp(message, kind) end
    exports('TextUI', textUI)
    exports('HideUI', D.hideHelp)
    provide('esx_textui', 'TextUI', textUI)
    provide('esx_textui', 'HideUI', D.hideHelp)

    -- esx_menu_dialog : ESX.UI.Menu.Open('dialog', …) ouvre notre boîte, même comportement qu'avant
    -- (valeur arrondie si c'est un nombre, refus de 0 et des nombres négatifs).
    local esxMenu

    local function esxDialog(ESX, namespace, name, data)
        local menu = {}
        esxMenu = menu
        CreateThread(function()
            while true do
                local value = D.input({ title = data.title, default = data.value, multiline = data.type == 'big', required = false })
                if esxMenu ~= menu then return end       -- fermé par le script entre-temps
                local opened = ESX.UI.Menu.GetOpened('dialog', namespace, name)
                if not opened then esxMenu = nil; return end
                local reply = { _namespace = namespace, _name = name }
                if value == nil then
                    esxMenu = nil
                    if opened.cancel then opened.cancel(reply, opened) end
                    return
                end
                local number = tonumber(value)
                if number then value = math.floor(number + 0.5) end
                if number and value <= 0 then
                    ESX.ShowNotification(D.T('esx_invalid'))
                else
                    esxMenu = nil
                    reply.value = value
                    if opened.submit then opened.submit(reply, opened) end
                    return
                end
            end
        end)
    end

    local function esxClose()
        if not esxMenu then return end
        esxMenu = nil
        if D.isOpen() then D.finish(nil) end
    end

    CreateThread(function()
        if GetResourceState('es_extended') == 'missing' then return end
        for _ = 1, 100 do
            if GetResourceState('es_extended') == 'started' then break end
            Wait(100)
        end
        local ok, ESX = pcall(function() return exports.es_extended:getSharedObject() end)
        if not ok or type(ESX) ~= 'table' then return end
        if ESX.UI and ESX.UI.Menu and ESX.UI.Menu.RegisterType then
            ESX.UI.Menu.RegisterType('dialog', function(namespace, name, data) esxDialog(ESX, namespace, name, data or {}) end, esxClose)
        end

        -- ESX.ShowHelpNotification écrit son texte dans l'entrée « esxHelpNotification » puis affiche l'aide de GTA.
        -- On lit ce texte, on l'affiche dans notre panneau, on vide l'entrée et on masque l'aide de GTA.
        -- shortcut: une aide ESX affichée une seule fois (pas en boucle) ne reste visible que 300 ms ; les scripts ESX
        -- l'appellent presque toujours en boucle. À revoir si un script tiers l'utilise autrement.
        local active = 0
        while true do
            local text = GetLabelText('esxHelpNotification')
            if text ~= '' and text ~= 'NULL' then
                D.pulseHelp(text)
                AddTextEntry('esxHelpNotification', '')
                if active < GetGameTimer() then ClearAllHelpMessages() end
                active = GetGameTimer() + 300
            end
            if active >= GetGameTimer() then HideHelpTextThisFrame() end
            Wait(0)      -- chaque image : sinon l'aide de GTA apparaît une fraction de seconde
        end
    end)
end

-- QBCore : qb-input ----------------------------------------------------------------------------------------
-- exports['qb-input']:ShowInput({ header, submitText, inputs = { { text, name, type, isRequired, default, options } } })
-- Actif seulement si qb-input n'est pas démarré (sinon c'est lui qui répond).
local QB_TYPES = { text = 'text', password = 'text', color = 'text', number = 'number', radio = 'select', select = 'select' }

local function showInput(data)
    data = type(data) == 'table' and data or {}
    local fields, map = {}, {}
    for _, entry in ipairs(type(data.inputs) == 'table' and data.inputs or {}) do
        if entry.type == 'checkbox' then
            for _, option in ipairs(type(entry.options) == 'table' and entry.options or {}) do
                fields[#fields + 1] = { type = 'checkbox', label = option.text or option.value, default = option.checked == true }
                map[#fields] = { key = option.value, checkbox = true }
            end
        else
            local options
            if type(entry.options) == 'table' then
                options = {}
                for i, option in ipairs(entry.options) do options[i] = { value = option.value, label = option.text or option.value } end
            end
            fields[#fields + 1] = {
                type = QB_TYPES[entry.type] or 'text', label = entry.text, required = entry.isRequired == true,
                default = entry.default, options = options,
            }
            map[#fields] = { key = entry.name }
        end
    end
    local values = D.form(fields, { title = data.header, submit = data.submitText })
    if not values then return nil end
    local result = {}
    for i, target in pairs(map) do
        local value = values[i]
        if target.checkbox then result[target.key] = value == true and 'true' or 'false'
        elseif target.key ~= nil then result[target.key] = value ~= nil and tostring(value) or '' end
    end
    return result
end

exports('ShowInput', showInput)
if redirect.qb ~= false and GetResourceState('qb-input') ~= 'started' then
    provide('qb-input', 'ShowInput', showInput)
end

HexaCompat = { showInput = showInput }
