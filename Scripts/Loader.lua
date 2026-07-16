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
    if not sm.rendezvous.hasUnboundCommand then return end

    for commandName, _ in pairs(sm.rendezvous.unboundCommands) do
        sm.event.sendToGame("rdv_bindChatCommand", commandName)
    end

    sm.rendezvous.hasUnboundCommand = false
end

local isHooked = false

local funcsToHook = {
    { sm.world, "createWorld" },
    { sm.world, "loadWorld" },
    { sm.game,  "bindChatCommand" },
    { sm.gui,   "createSurvivalHudGui" }
}

for _, funcData in ipairs(funcsToHook) do
    local namespace = funcData[1]
    local method = funcData[2]

    local originalFunc = namespace[method]

    if originalFunc then
        namespace[method] = function(...)
            if not isHooked then
                isHooked = true
                sm.rendezvous.hookedFrom = method

                dofile("$CONTENT_ac2379db-1c7d-49fd-9d2e-4ccc6d11ce93/Scripts/Loader.lua")
            end

            return originalFunc(...)
        end
    end
end