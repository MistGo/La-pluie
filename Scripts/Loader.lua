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

    function sm.rendezvous.classExists(className)
        local expected = _G[className]

        return expected ~= nil and type(expected) == "table"
    end

    function sm.rendezvous.getLoadedClasses()
        local loadedClasses = {}

        for className, classTable in pairs(_G) do
            if type(classTable) == "table" and classTable.__index ~= nil then
                table.insert(loadedClasses, className)
            end
        end

        return loadedClasses
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

function Loader:client_onCreate()
    if not sm.rendezvous.isGameHooked then
        sm.gui.chatMessage("[sm.rendezvous] Failed to hook game enclassTable.")
    end

    -- sm.event.sendToGame("rdv_bindCommand")
end

function Loader:client_onRefresh()
    sm.rendezvous.bindChatCommand("/thecraving", {
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
    }, function (self, params)
        print("crash test dummy", params)
    end, "twenty one pilots")
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
