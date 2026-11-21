-- Dialogues de hexa_core (exécuté seulement dans la ressource hexa_core) : formulaire, saisie,
-- confirmation, aide à l'écran. Les autres ressources passent par Hexa.Input / Hexa.Form /
-- Hexa.Confirm / Hexa.Help (client.lua), qui appellent les exports ci-dessous.
-- La page (web/) n'a aucune règle : chaque réponse est vérifiée ici.
local cfg = Hexa.Config.Dialog or {}
local currency = cfg.Currency or '$'
local english = Hexa.Config.Locale == 'en'
local T = Hexa.Locale({
    fr = {
        submit = 'Valider', cancel = 'Annuler', yes = 'Oui', no = 'Non',
        required = 'Ce champ est obligatoire.', must_check = 'Cochez cette case pour continuer.',
        not_number = 'Entrez un nombre.', whole = 'Entrez un nombre entier.',
        too_small = 'Minimum : %s.', too_big = 'Maximum : %s.',
        too_short = 'Au moins %s caractères.', too_long = 'Au plus %s caractères.',
        bad_choice = 'Choisissez dans la liste.', bad_date = 'Date invalide.',
        date_min = 'Au plus tôt le %s.', date_max = 'Au plus tard le %s.',
        range = 'Entre %s et %s', at_least = 'Au moins %s', at_most = 'Au plus %s',
        chars = '%s / %s caractères', choose = 'Choisir…',
        esx_invalid = 'Cette valeur n’est pas autorisée.',
        bad_pin = 'Entrez exactement %s chiffres.', bad_time = 'Heure invalide (HH:MM).', bad_step = 'Valeur non autorisée.',
        menu_empty = 'Aucune option.',
    },
    en = {
        submit = 'Confirm', cancel = 'Cancel', yes = 'Yes', no = 'No',
        required = 'This field is required.', must_check = 'Tick this box to continue.',
        not_number = 'Enter a number.', whole = 'Enter a whole number.',
        too_small = 'Minimum: %s.', too_big = 'Maximum: %s.',
        too_short = 'At least %s characters.', too_long = 'At most %s characters.',
        bad_choice = 'Pick an option from the list.', bad_date = 'Invalid date.',
        date_min = 'No earlier than %s.', date_max = 'No later than %s.',
        range = 'Between %s and %s', at_least = 'At least %s', at_most = 'At most %s',
        chars = '%s / %s characters', choose = 'Choose…',
        esx_invalid = 'That value is not allowed.',
        bad_pin = 'Enter exactly %s digits.', bad_time = 'Invalid time (HH:MM).', bad_step = 'Value not allowed.',
        menu_empty = 'No options.',
    },
})

-- Nombres et dates lisibles -----------------------------------------------------------------------------
local function format(n)
    local whole, decimals = tostring(n):match('^(-?%d+)(%.?%d*)$')
    if not whole then return tostring(n) end
    local sep = english and ',' or ' '
    whole = whole:reverse():gsub('(%d%d%d)', '%1' .. sep):reverse():gsub('^(-?)' .. sep, '%1')
    return whole .. decimals:gsub('%.', english and '.' or ',')
end

local function readableDate(iso)
    local y, m, d = tostring(iso):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not y then return tostring(iso) end
    return english and ('%s/%s/%s'):format(m, d, y) or ('%s/%s/%s'):format(d, m, y)
end

local function validDate(text)
    local y, m, d = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or m < 1 or m > 12 or d < 1 then return false end
    local days = ({ 31, (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[m]
    return d <= days
end

-- Champs -------------------------------------------------------------------------------------------------
local TYPES = { text = 'text', input = 'text', textarea = 'text', number = 'number', amount = 'amount',
    select = 'select', date = 'date', checkbox = 'checkbox', password = 'password', pin = 'pin', slider = 'slider', time = 'time' }

local function isNumeric(kind) return kind == 'number' or kind == 'amount' end

-- Options de l'appelant, nettoyées.
local function normalize(field)
    if type(field) == 'string' then field = { label = field } end
    field = type(field) == 'table' and field or {}
    local f = {
        type = TYPES[field.type] or 'text', name = field.name,
        label = field.label, description = field.description, placeholder = field.placeholder,
        multiline = field.multiline == true or field.type == 'textarea', required = field.required,
        min = field.min, max = field.max, default = field.default,
    }
    if isNumeric(f.type) or f.type == 'text' or f.type == 'password' or f.type == 'slider' then f.min, f.max = tonumber(f.min), tonumber(f.max) end
    if f.type == 'pin' then f.length = math.max(3, math.min(8, math.floor(tonumber(field.length) or 4))) end
    if f.type == 'slider' then
        f.min, f.max = f.min or 0, f.max or 100
        if f.max < f.min then f.min, f.max = f.max, f.min end
        f.step = tonumber(field.step) and tonumber(field.step) > 0 and tonumber(field.step) or 1
        f.unit = type(field.unit) == 'string' and field.unit or nil
    end
    if f.type == 'amount' then
        f.min = math.max(f.min or 1, 0)
        f.max = f.max or 2147483647
    elseif f.type == 'date' then
        f.min = type(f.min) == 'string' and validDate(f.min) and f.min or nil
        f.max = type(f.max) == 'string' and validDate(f.max) and f.max or nil
    elseif f.type == 'select' then
        f.options = {}
        for _, option in ipairs(type(field.options) == 'table' and field.options or {}) do
            if type(option) == 'table' then
                f.options[#f.options + 1] = { value = option.value, label = tostring(option.label or option.text or option.value) }
            else
                f.options[#f.options + 1] = { value = option, label = tostring(option) }
            end
        end
    end
    return f
end

-- Vérifie la réponse d'un champ. Renvoie la valeur, ou nil et le message d'erreur.
local function validate(f, raw)
    if f.type == 'checkbox' then
        local checked = raw == true
        if f.required and not checked then return nil, T('must_check') end
        return checked
    end
    if f.type == 'select' then
        local index = tonumber(raw)
        local option = index and f.options[index]
        if not option then
            if f.required == false and (raw == nil or raw == '' or raw == 0) then return nil end
            return nil, (raw == nil or raw == '' or raw == 0) and T('required') or T('bad_choice')
        end
        return option.value
    end
    if f.type == 'slider' then
        local n = tonumber(raw)
        if not n then return nil, T('not_number') end
        if n < f.min then return nil, T('too_small', format(f.min)) end
        if n > f.max then return nil, T('too_big', format(f.max)) end
        local steps = (n - f.min) / f.step
        if math.abs(steps - math.floor(steps + 0.5)) > 1e-6 then return nil, T('bad_step') end
        return math.tointeger(n) or n
    end
    raw = type(raw) == 'string' and raw or ''
    if f.type == 'pin' then
        if raw == '' then return nil, T('required') end
        if not raw:match('^%d+$') or #raw ~= f.length then return nil, T('bad_pin', f.length) end
        return raw
    end
    if f.type == 'password' then          -- gardé tel quel : ni espaces retirés, ni espaces fusionnés
        local length = utf8.len(raw) or #raw
        if length == 0 then
            if f.required == false then return '' end
            return nil, T('required')
        end
        if f.min and length < f.min then return nil, T('too_short', f.min) end
        if f.max and length > f.max then return nil, T('too_long', f.max) end
        return raw
    end
    if f.type == 'time' then
        raw = raw:gsub('%s', '')
        if raw == '' then
            if f.required == false then return nil end
            return nil, T('required')
        end
        local h, m = raw:match('^(%d%d?)[:hH](%d%d)$')
        h, m = tonumber(h), tonumber(m)
        if not h or h > 23 or m > 59 then return nil, T('bad_time') end
        return ('%02d:%02d'):format(h, m)
    end
    if f.type == 'date' then
        raw = raw:gsub('%s', '')
        if raw == '' then
            if f.required == false then return nil end
            return nil, T('required')
        end
        -- JJ/MM/AAAA (MM/DD/YYYY en anglais) ou AAAA-MM-JJ ; renvoyée au format AAAA-MM-JJ.
        local a, b, y = raw:match('^(%d%d?)[/%.%-](%d%d?)[/%.%-](%d%d%d%d)$')
        if a then
            local d, m = a, b
            if english then d, m = b, a end
            raw = ('%04d-%02d-%02d'):format(tonumber(y), tonumber(m), tonumber(d))
        end
        if not validDate(raw) then return nil, T('bad_date') end
        if f.min and raw < f.min then return nil, T('date_min', readableDate(f.min)) end
        if f.max and raw > f.max then return nil, T('date_max', readableDate(f.max)) end
        return raw
    end
    if isNumeric(f.type) then
        local text = raw:gsub('[%s\194\160\226\128\175]', ''):gsub(currency:gsub('%p', '%%%0'), '')
        if not english or f.type == 'number' then text = text:gsub(',', '.') end
        if f.type == 'amount' then text = text:gsub(',', '') end
        if text == '' then
            if f.required == false then return nil end
            return nil, T('required')
        end
        if not (text:match('^%-?%d+%.?%d*$') or text:match('^%-?%.%d+$')) then return nil, T('not_number') end
        local n = tonumber(text)
        if f.type == 'amount' and n ~= math.floor(n) then return nil, T('whole') end
        if f.min and n < f.min then return nil, T('too_small', format(f.min)) end
        if f.max and n > f.max then return nil, T('too_big', format(f.max)) end
        return math.tointeger(n) or n
    end
    local text = raw:gsub('^%s+', ''):gsub('%s+$', '')
    if not f.multiline then text = text:gsub('%s+', ' ') end
    local length = utf8.len(text) or #text
    if length == 0 then
        if f.required == false then return '' end
        return nil, T('required')
    end
    if f.min and length < f.min then return nil, T('too_short', f.min) end
    if f.max and length > f.max then return nil, T('too_long', f.max) end
    return text
end

-- Indication sous le champ (« Entre 1 et 5 000 $ », « 0 / 20 caractères »).
local function hint(f)
    if isNumeric(f.type) then
        local unit = f.type == 'amount' and (' ' .. currency) or ''
        local high = f.max and f.max < 2147483647 and f.max
        if f.min and high then return T('range', format(f.min), format(high) .. unit) end
        if high then return T('at_most', format(high) .. unit) end
        if f.min and f.type ~= 'amount' then return T('at_least', format(f.min) .. unit) end
    elseif f.type == 'text' and f.max then
        return T('chars')
    elseif f.type == 'date' then
        if f.min and f.max then return T('range', readableDate(f.min), readableDate(f.max)) end
        if f.min then return T('date_min', readableDate(f.min)):gsub('%.$', '') end
        if f.max then return T('date_max', readableDate(f.max)):gsub('%.$', '') end
    end
    return nil
end

-- Ce que la page reçoit pour un champ.
local function view(f)
    local v = {
        type = f.type, label = f.label, description = f.description, placeholder = f.placeholder,
        multiline = f.multiline, required = f.required ~= false, hint = hint(f),
    }
    if f.type == 'checkbox' then
        v.default = f.default == true
    elseif f.type == 'slider' then
        v.min, v.max, v.step, v.unit = f.min, f.max, f.step, f.unit
        local default = tonumber(f.default) or f.min
        v.default = math.max(f.min, math.min(f.max, default))
    elseif f.type == 'select' then
        v.options, v.default, v.placeholder = {}, 0, f.placeholder or T('choose')
        for i, option in ipairs(f.options) do
            v.options[i] = option.label
            if f.default ~= nil and option.value == f.default then v.default = i end
        end
    else
        v.default = f.default ~= nil and tostring(f.default) or nil
        if f.type == 'date' then
            v.default = v.default and validDate(v.default) and readableDate(v.default) or v.default
            v.placeholder = f.placeholder or (english and 'MM/DD/YYYY' or 'JJ/MM/AAAA')
        end
        v.numeric = isNumeric(f.type)
        v.unit = f.type == 'amount' and currency or nil
        v.maxLength = (f.type == 'text' or f.type == 'password') and f.max or nil
        if f.type == 'password' or f.type == 'pin' then v.masked = true end
        if f.type == 'pin' then v.length, v.maxLength, v.numeric, v.default = f.length, f.length, true, nil end
        if f.type == 'time' then v.placeholder = f.placeholder or 'HH:MM' end
    end
    return v
end

-- Ouverture / fermeture ----------------------------------------------------------------------------------
local active   -- { kind, fields, promise }

local function finish(value)
    if not active then return end
    local p = active.promise
    active = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    p:resolve({ value = value })
end

-- Style : 'center' (fenêtre au milieu) ou 'side' (panneau à droite). Touches : Dialog.Keys (noms JavaScript).
local function styleName() return cfg.Style == 'side' and 'side' or 'center' end
local function keyName(value, default) return type(value) == 'string' and value ~= '' and value:sub(1, 12) or default end

-- Manette : les touches du jeu sont lues ici (la page n'a pas la manette) et envoyées à la page.
local PAD = { [188] = 'up', [187] = 'down', [189] = 'left', [190] = 'right', [201] = 'accept', [202] = 'cancel' }
local function padLoop(p)
    for control in pairs(PAD) do DisableControlAction(0, control, true) end
    if not IsInputDisabled(0) then               -- manette en main (pas clavier / souris)
        for control, key in pairs(PAD) do
            if IsDisabledControlJustPressed(0, control) then SendNUIMessage({ action = 'pad', key = key }) end
        end
    end
end

local function open(kind, fields, message)
    if active then return nil end            -- une boîte à la fois
    active = { kind = kind, fields = fields, promise = promise.new() }
    local p = active.promise
    message.action, message.kind = 'open', kind
    message.style = styleName()
    message.keys = { submit = keyName((cfg.Keys or {}).submit, 'Enter'), cancel = keyName((cfg.Keys or {}).cancel, 'Escape') }
    message.texts = { submit = T('submit'), cancel = T('cancel'), yes = T('yes'), no = T('no'), empty = T('menu_empty') }
    SendNUIMessage(message)
    SetNuiFocus(true, true)
    CreateThread(function()                  -- Échap ne doit pas ouvrir le menu pause
        while active and active.promise == p do
            DisableControlAction(0, 199, true)
            DisableControlAction(0, 200, true)
            if cfg.Gamepad ~= false then padLoop(p) end
            Wait(0)
        end
    end)
    return Citizen.Await(p).value
end

-- Formulaire : renvoie { [1] = valeur, [nom] = valeur, … } ou nil si annulé.
local function form(fields, options)
    if type(options) == 'string' then options = { title = options } end
    options = type(options) == 'table' and options or {}
    local list, views = {}, {}
    for i, field in ipairs(type(fields) == 'table' and fields or {}) do
        list[i] = normalize(field)
        views[i] = view(list[i])
    end
    if #list == 0 then return nil end
    return open('form', list, {
        title = options.title, description = options.description, fields = views,
        submitLabel = options.submit, cancelLabel = options.cancel,
    })
end

-- Un seul champ : renvoie directement sa valeur (nil si annulé).
local function input(options)
    if type(options) == 'string' then options = { title = options } end
    options = type(options) == 'table' and options or {}
    local field = Hexa.Copy(options)
    field.title, field.description = nil, nil
    if not options.label then field.label = nil end
    local values = form({ field }, { title = options.title, description = options.description })
    return values and values[1]
end

local function confirm(options)
    if type(options) == 'string' then options = { message = options } end
    options = type(options) == 'table' and options or {}
    return open('confirm', {}, {
        title = options.title, message = options.message, danger = options.danger == true,
        submitLabel = options.confirm, cancelLabel = options.cancel,
    }) == true
end

-- Petit menu liste : { title, description, options = { { label, description, value, disabled }, … } }.
-- Renvoie la valeur de l'option choisie (son numéro si elle n'a pas de `value`) et son numéro, ou nil si annulé.
local function menu(options)
    if type(options) == 'string' then options = { title = options } end
    options = type(options) == 'table' and options or {}
    local items, views = {}, {}
    for _, option in ipairs(type(options.options) == 'table' and options.options or {}) do
        if type(option) ~= 'table' then option = { label = option } end
        local item = { value = option.value, disabled = option.disabled == true }
        items[#items + 1] = item
        views[#views + 1] = { label = tostring(option.label or option.value or ''), description = option.description and tostring(option.description) or nil, disabled = item.disabled }
    end
    local picked = open('menu', items, { title = options.title, description = options.description, items = views, cancelLabel = options.cancel })
    if not picked then return nil end
    local item = items[picked]
    if item.value ~= nil then return item.value, picked end
    return picked, picked
end

RegisterNUICallback('submit', function(body, cb)
    if not active then return cb({ ok = false }) end
    if active.kind == 'menu' then return cb({ ok = false }) end
    if active.kind == 'confirm' then cb({ ok = true }); return finish(true) end
    local raw = type(body.values) == 'table' and body.values or {}
    local values, errors = {}, {}
    for i, f in ipairs(active.fields) do
        local value, err = validate(f, raw[i])
        if err then errors[#errors + 1] = { index = i, error = err } end
        values[i] = value
        if f.name ~= nil and value ~= nil then values[f.name] = value end
    end
    if #errors > 0 then return cb({ ok = false, errors = errors }) end
    cb({ ok = true })
    finish(values)
end)

RegisterNUICallback('choose', function(body, cb)
    if not active or active.kind ~= 'menu' then return cb({ ok = false }) end
    local index = math.floor(tonumber(body and body.index) or 0)
    local item = active.fields[index]
    if not item or item.disabled then return cb({ ok = false }) end
    cb({ ok = true })
    finish(index)
end)

RegisterNUICallback('cancel', function(_, cb)
    cb({ ok = true })
    if active then finish(active.kind == 'confirm' and false or nil) end
end)

exports('Form', form)
exports('Input', input)
exports('Confirm', confirm)
exports('Menu', menu)
exports('IsDialogOpen', function() return active ~= nil end)
exports('CloseDialog', function() if active then finish(active.kind == 'confirm' and false or nil) end end)

-- Aide à l'écran ------------------------------------------------------------------------------------------
-- Les textes GTA (« Appuyez sur ~INPUT_CONTEXT~ ») deviennent « Appuyez sur [E] ».
local INPUTS = {
    INPUT_CONTEXT = { 51, 'E' }, INPUT_PICKUP = { 38, 'E' }, INPUT_CONTEXT_SECONDARY = { 52, 'Q' },
    INPUT_DETONATE = { 47, 'G' }, INPUT_ENTER = { 23, 'F' }, INPUT_VEH_EXIT = { 75, 'F' }, INPUT_RELOAD = { 45, 'R' },
    INPUT_JUMP = { 22, english and 'Space' or 'Espace' }, INPUT_SPRINT = { 21, english and 'Shift' or 'Maj' },
    INPUT_COVER = { 44, 'Q' }, INPUT_VEH_HORN = { 86, 'E' },
    INPUT_FRONTEND_ACCEPT = { 201, english and 'Enter' or 'Entrée' }, INPUT_CELLPHONE_CANCEL = { 177, english and 'Back' or 'Retour' },
    INPUT_INTERACTION_MENU = { 244, 'M' }, INPUT_MULTIPLAYER_INFO = { 20, 'Z' },
}

local function plain(text)
    text = tostring(text or '')
    text = text:gsub('~(INPUT_[%w_]+)~', function(name)
        local entry = INPUTS[name]
        local button = entry and GetControlInstructionalButton(0, entry[1], true)
        local key = type(button) == 'string' and button:match('^t_(.+)$')
        return '[' .. (key or (entry and entry[2]) or name:sub(7)) .. ']'
    end)
    text = text:gsub('~n~', '\n'):gsub('~[%a]~', ''):gsub('~h~', '')
    return text
end

local helpKey, helpUntil

local function showHelp(text, kind)
    text = plain(text)
    if text == '' then return end
    local key = text .. '|' .. tostring(kind)
    if key == helpKey then return end
    helpKey = key
    SendNUIMessage({ action = 'help', text = text, kind = kind, position = cfg.HelpPosition or 'left' })
end

local function hideHelp()
    helpUntil = nil
    if not helpKey then return end
    helpKey = nil
    SendNUIMessage({ action = 'help' })
end

local function pulseHelp(text, kind) showHelp(text, kind); helpUntil = GetGameTimer() + 300 end

exports('ShowHelp', function(text, kind) helpUntil = nil; showHelp(text, kind) end)
exports('HideHelp', hideHelp)
-- À appeler en boucle (comme l'aide de GTA) : disparaît seule 300 ms après le dernier appel.
exports('PulseHelp', pulseHelp)
exports('IsHelpVisible', function() return helpKey ~= nil end)

CreateThread(function()
    while true do
        Wait(100)
        if helpUntil and GetGameTimer() > helpUntil then hideHelp() end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and active then SetNuiFocus(false, false) end
end)

-- Pour core/compat.lua et les tests.
HexaDialog = {
    form = form, input = input, confirm = confirm, menu = menu, finish = finish, showHelp = showHelp, hideHelp = hideHelp,
    pulseHelp = pulseHelp, normalize = normalize, validate = validate, hint = hint, plain = plain, format = format,
    isOpen = function() return active ~= nil end, T = T,
}
