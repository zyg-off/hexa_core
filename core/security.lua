-- Sécurité des exports sensibles (suppression de personnage, instances, lecture des logs).
--  • Une ressource qui n'est pas Hexa et appelle un de ces exports est signalée une fois (console + logs).
--    L'appel n'est pas bloqué : on prévient, on ne casse pas vos scripts.
--  • Au-delà de Security.maxCallsPerMinute appels par minute et par ressource, les appels sont refusés
--    jusqu'à la minute suivante (protège contre une boucle folle).
local T = Hexa.Locale({
    fr = {
        foreign = 'La ressource « %s » appelle %s (export sensible de hexa_core).',
        limit = 'La ressource « %s » dépasse %s appels/minute vers hexa_core : appels refusés jusqu’à la minute suivante.',
    },
    en = {
        foreign = 'Resource "%s" calls %s (sensitive hexa_core export).',
        limit = 'Resource "%s" exceeds %s calls/minute to hexa_core: calls refused until the next minute.',
    },
})

local cfg = Hexa.ServerConfig.Security or {}
local MAX = math.max(0, math.floor(tonumber(cfg.maxCallsPerMinute) or 600))
local counters, warned = {}, {}

-- exports('X', HexaGuard('X', function(...) ... end, valeurSiRefusé))
function HexaGuard(name, fn, refused)
    return function(...)
        local caller = GetInvokingResource() or Hexa.resource
        local key = caller .. ':' .. name
        if caller ~= Hexa.resource and not caller:find('^hexa_') and not warned[key] then
            warned[key] = true
            local message = T('foreign', caller, name)
            Hexa.Print(message, 'warn')
            Hexa.Log('security', message, nil, nil, 'warning')
        end
        if MAX > 0 then
            local now = GetGameTimer()
            local c = counters[caller]
            if not c or now - c.start >= 60000 then c = { start = now, count = 0 }; counters[caller] = c end
            c.count = c.count + 1
            if c.count > MAX then
                if not c.warned then
                    c.warned = true
                    local message = T('limit', caller, MAX)
                    Hexa.Print(message, 'warn')
                    Hexa.Log('security', message, nil, nil, 'warning')
                end
                return refused
            end
        end
        return fn(...)
    end
end

HexaSecurity = { counters = counters, warned = warned, max = MAX }
