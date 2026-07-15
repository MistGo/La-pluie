---@diagnostic disable

if not sm.rendezvous then
    sm.rendezvous = {
        initializedByTool = false,
        isGameHooked = false,

        hasUnboundCommand = false,
        unboundCommands = {},

        classExists = function(className) end,
        getLoadedClasses = function() return {} end
    }
end

if sm.rendezvous.initializedByTool then
    sm.rendezvous.isGameHooked = true

    local gameEnv = _G

    function sm.rendezvous.classExists(className)
        local expected = gameEnv[className]

        return type(expected) == "table" and expected == expected.__index
    end

    function sm.rendezvous.getLoadedClasses()
        local loadedClasses = {}

        for className, classTable in pairs(gameEnv) do
            if type(classTable) == "table" and classTable == classTable.__index then
                table.insert(loadedClasses, className)
            end
        end

        return loadedClasses
    end

    for className, classTable in pairs(gameEnv) do
        if type(classTable) == "table" and (classTable.defaultInventorySize or classTable.enableAggro or classTable.enableAmmoConsumption or classTable.enableFuelConsumption or classTable.enableLimitedInventory or classTable.enableRestrictions or classTable.enableUpgrade or classTable.worldScriptFilename or classTable.worldScriptClass) then
            if type(classTable.server_onCreate) == "function" and type(classTable.client_onCreate) == "function" then
                classTable.rdv_bindChatCommand = function(self, new)
                    local cmdData = sm.rendezvous.unboundCommands[new]

                    if cmdData and not cmdData.bound then
                        local command = cmdData.command -- string
                        local params = cmdData.params   -- table
                        local callback = cmdData.callback
                        local help = cmdData.help       -- string

                        local cleanName = command:gsub("/", "")
                        local methodSelector = "rdv_cmd_" .. cleanName

                        classTable[methodSelector] = callback

                        cmdData.bound = true

                        sm.game.bindChatCommand(command, params, methodSelector, help)
                    end
                end
            end
        end
    end

    return
end

sm.rendezvous.initializedByTool = true

Loader = class()
Loader.isHooked = false

function sm.rendezvous.bindChatCommand(command, params, callback, help)
    if type(command) ~= "string" or type(params) ~= "table" or type(callback) ~= "function" or type(help) ~= "string" then return end
    if string.sub(command, 1, 1) ~= "/" then command = "/" .. command end

    sm.rendezvous.unboundCommands[command] = sm.rendezvous.unboundCommands[command] or {
        command = command,
        params = params,
        callback = callback,
        help = help
    }

    sm.rendezvous.hasUnboundCommand = true
end

function sm.rendezvous.hookClass()

end

function Loader:client_onCreate()
    if not sm.rendezvous.isGameHooked or not sm.rendezvous.hookedFrom then
        sm.gui.chatMessage("[sm.rendezvous] Failed to hook game enclassTable.")
    end

    sm.rendezvous.getLoadedClasses()
end

function Loader:client_onRefresh()
    sm.rendezvous.bindChatCommand(
        "/thecraving",
        {
            {
                "int",
                "1st",
                false
            },
            {
                "string",
                "snd",
                false
            }
        },

        function(self, params)
            print("crash test dummy", params)
        end,
        "twenty one pilots"
    )
    self:client_onCreate()
end

function Loader:client_onFixedUpdate(timeStep)
    -- print(sm.rendezvous)
    if not sm.rendezvous.hasUnboundCommand then
        -- sm.rendezvous.unboundCommands = (#sm.rendezvous.unboundCommands > 0) and {} or sm.rendezvous.unboundCommands
        return
    end

    for commandName, _ in pairs(sm.rendezvous.unboundCommands) do
        sm.event.sendToGame("rdv_bindChatCommand", commandName)
    end

    sm.rendezvous.hasUnboundCommand = false
end

local funcsToHook = {
    { sm.world, "createWorld" },
    { sm.world, "loadWorld" },
    { sm.game,  "bindChatCommand" },
    { sm.gui,   "createSurvivalHudGui" }
}

for _, funcData in ipairs(funcsToHook) do
    local namespace = funcData[1]
    local methodName = funcData[2]

    local originalFunc = namespace[methodName]

    if originalFunc then
        namespace[methodName] = function(...)
            if not Loader.isHooked then
                Loader.isHooked = true
                sm.rendezvous.hookedFrom = methodName

                dofile("$CONTENT_ac2379db-1c7d-49fd-9d2e-4ccc6d11ce93/Scripts/Loader.lua")
            end

            return originalFunc(...)
        end
    end
end




-- Gemini slop

--[[ if not sm.rendezvous then
    sm.rendezvous = {
        initializedByTool = false,
        isGameHooked = false,
        hasUnboundCommand = false,
        unboundCommands = {},

        -- Сюда будем складывать диспетчеры захуканных методов
        activeHooks = {},

        classExists = function(className)
            local expected = _G[className]
            return expected ~= nil and type(expected) == "table"
        end,
        getLoadedClasses = function()
            local loadedClasses = {}
            for className, classTable in pairs(_G) do
                if type(classTable) == "table" and classTable.__index ~= nil then
                    table.insert(loadedClasses, className)
                end
            end
            return loadedClasses
        end,

        -- ====================================================================
        -- ДИНАМИЧЕСКИЙ МЕНЕДЖЕР ХУКОВ (Мягкое управление)
        -- ====================================================================
        hook = {
            -- Добавить или изменить обработчик
            -- handlerFunc принимает: (self, params, originalFunc)
            -- params — это таблица аргументов, которую можно модифицировать на ходу!
            add = function(className, methodName, id, handlerFunc)
                local classTable = _G[className]
                if not classTable then return false end

                local hookKey = className .. "." .. methodName

                -- Если этот метод ещё ни разу не хукался, создаем для него диспетчер
                if not sm.rendezvous.activeHooks[hookKey] then
                    local originalFunc = classTable[methodName]
                    if not originalFunc then return false end

                    local dispatcher = {
                        original = originalFunc,
                        listeners = {}
                    }
                    sm.rendezvous.activeHooks[hookKey] = dispatcher

                    -- Подменяем оригинальный метод в классе ОДИН раз на диспетчер
                    classTable[methodName] = function(self, ...)
                        local args = { ... }
                        local blockOriginal = false

                        -- Бежим по всем зарегистрированным слушателям
                        for listenerId, listener in pairs(dispatcher.listeners) do
                            if listener.enabled and type(listener.callback) == "function" then
                                -- Вызываем слушатель. Он может вернуть true, чтобы заблокировать вызов оригинала
                                local ok, preventDefault = pcall(listener.callback, self, args, dispatcher.original)
                                if ok and preventDefault == true then
                                    blockOriginal = true
                                elseif not ok then
                                    print("[Rendezvous-Hook] Error in " .. listenerId .. ": " .. tostring(preventDefault))
                                end
                            end
                        end

                        -- Если никто не заблокировал, вызываем оригинал с (возможно измененными) аргументами
                        if not blockOriginal then
                            return dispatcher.original(self, table.unpack(args))
                        end
                    end
                end

                -- Регистрируем или перезаписываем наш обработчик по ID
                sm.rendezvous.activeHooks[hookKey].listeners[id] = {
                    callback = handlerFunc,
                    enabled = true
                }
                print(string.format("[Rendezvous-Hook] Registered/Updated '%s' on %s:%s", id, className, methodName))
                return true
            end,

            -- Полностью удалить обработчик по ID
            remove = function(className, methodName, id)
                local hookKey = className .. "." .. methodName
                local dispatcher = sm.rendezvous.activeHooks[hookKey]
                if dispatcher and dispatcher.listeners[id] then
                    dispatcher.listeners[id] = nil
                    print(string.format("[Rendezvous-Hook] Removed '%s' from %s:%s", id, className, methodName))
                    return true
                end
                return false
            end,

            -- Временно включить или выключить обработчик без удаления
            enable = function(className, methodName, id, bool)
                local hookKey = className .. "." .. methodName
                local dispatcher = sm.rendezvous.activeHooks[hookKey]
                if dispatcher and dispatcher.listeners[id] then
                    dispatcher.listeners[id].enabled = (bool == true)
                    print(string.format("[Rendezvous-Hook] Set '%s' status to %s on %s:%s", id, tostring(bool), className,
                        methodName))
                    return true
                end
                return false
            end
        }
    }
end
 ]]