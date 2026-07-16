---@diagnostic disable

if not sm.rendezvous then
    sm.rendezvous = {
        initializedByTool = false,
        isGameHooked = false,

        hasUnboundCommand = false,
        unboundCommands = {},

        classExists = function()
            error("sm.rendezvous.classExists cannot be called yet: the game world has not finished loading.")
        end,
        getLoadedClasses = function()
            error("sm.rendezvous.getLoadedClasses cannot be called yet: the game world has not finished loading.")
        end
    }
end

if sm.rendezvous.initializedByTool then
    local gameEnv = _G
    local CLASS_RULES = {}

    function sm.rendezvous.classExists(className)
        assert(type(className) == "string", "Error: Expected class name as a string, received: " .. type(className))

        local classTable = gameEnv[className]

        return type(classTable) == "table" and classTable == classTable.__index
    end

    function sm.rendezvous.getLoadedClasses()
        local loadedClasses = {}

        for className, _ in pairs(gameEnv) do
            if sm.rendezvous.classExists(className) then
                table.insert(loadedClasses, className)
            end
        end

        return loadedClasses
    end

    function sm.rendezvous.getClassType(className)
        assert(type(className) == "string", "Error: Expected class name as a string, received: " .. type(className))

        if not sm.rendezvous.classExists(className) then return "Unknown" end

        local targetClass = gameEnv[className]

        for i = 1, #CLASS_RULES do
            local rule = CLASS_RULES[i]
            local keys = rule.keys

            for j = 1, #keys do
                if targetClass[keys[j]] ~= nil then
                    return rule.type
                end
            end
        end

        return "Unknown"
    end

    for className, classTable in pairs(gameEnv) do
        if sm.rendezvous.getClassType(className) == "GameClass" then
            if type(classTable.server_onCreate) == "function" and type(classTable.client_onCreate) == "function" then
                classTable.rdv_bindChatCommand = function(self, new)
                    local commandData = sm.rendezvous.unboundCommands[new]

                    if commandData and not commandData.bound then
                        local command  = commandData.command
                        local params   = commandData.params
                        local callback = commandData.callback
                        local help     = commandData.help

                        local cleanName = command:gsub("/", "")
                        local methodSelector = "rdv_cmd_" .. cleanName

                        classTable[methodSelector] = callback

                        commandData.command  = nil
                        commandData.params   = nil
                        commandData.callback = nil
                        commandData.help     = nil
                        commandData.bound    = true

                        sm.game.bindChatCommand(command, params, methodSelector, help)
                    end
                end
            end
        end
    end

    sm.rendezvous.isGameHooked = true

    return
end

sm.rendezvous.initializedByTool = true

Loader = class()

function sm.rendezvous.bindChatCommand(command, params, callback, help)
    assert(type(command) == "string", string.format("bad argument #1 (string expected, got %s)", type(command)))
    assert(type(params) == "table", string.format("bad argument #2 (table expected, got %s)", type(params)))
    assert(type(callback) == "function", string.format("bad argument #3 (function expected, got %s)", type(callback)))
    assert(type(help) == "string", string.format("bad argument #4 (string expected, got %s)", type(help)))

    if string.sub(command, 1, 1) ~= "/" then
        command = "/" .. command
    end

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
        sm.gui.chatMessage("[sm.rendezvous] Failed to hook game env.")
    end

    print(sm.rendezvous.getLoadedClasses())
end

function Loader:client_onRefresh()
    sm.rendezvous.bindChatCommand(
        "/thecraving",
        { { "int", "1st", false } },
        function(self, params)
            print("crash test dummy", params)
        end,
        "twenty one pilots"
    )

    self:client_onCreate()
end

function Loader:client_onFixedUpdate(timeStep)
    if not sm.rendezvous.hasUnboundCommand then return end

    for commandName, commandData in pairs(sm.rendezvous.unboundCommands) do
        if not commandData.bound then
            sm.event.sendToGame("rdv_bindChatCommand", commandName)
        end
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
