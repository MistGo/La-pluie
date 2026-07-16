---@diagnostic disable

if not sm.rendezvous then
    sm.rendezvous = {
        initializedByTool = false,
        isGameHooked = false,

        commands = {},
        pendingCommands = {},
    }

    sm.rendezvous.assertArgument = function(value, argIndex, allowedTypes)
        local actualType = type(value)

        local typeIsValid = false
        for _, expectedType in ipairs(allowedTypes) do
            if actualType == expectedType then
                typeIsValid = true
                break
            end
        end

        if not typeIsValid then
            local expectedStr = table.concat(allowedTypes, " or ")

            local errorMsg = string.format(
                "bad argument #%d (%s expected, got %s)", 
                argIndex, 
                expectedStr, 
                actualType
            )

            error(errorMsg, 2)
        end
    end
end

if not Loader and sm.rendezvous.initializedByTool then
    local gameEnv = _G

    function sm.rendezvous.isClassLoaded(className)
        sm.rendezvous.assertArgument(className, 1, {"string"})

        local classTable = gameEnv[className]

        return type(classTable) == "table" and classTable == classTable.__index
    end

    function sm.rendezvous.getAllLoadedClasses()
        local loadedClasses = {}

        for className, _ in pairs(gameEnv) do
            if sm.rendezvous.isClassLoaded(className) then
                table.insert(loadedClasses, className)
            end
        end

        return loadedClasses
    end

    for className, classTable in pairs(gameEnv) do
        if type(classTable) == "table" and (classTable.defaultInventorySize or classTable.enableAggro or classTable.enableAmmoConsumption or classTable.enableFuelConsumption or classTable.enableLimitedInventory or classTable.enableRestrictions or classTable.enableUpgrade) and (classTable.server_onCreate ~= nil and classTable.client_onCreate ~= nil) then
            classTable.rdv_bindChatCommands = function (self, unboundCommands)
                for _, name in ipairs(unboundCommands) do
                    local commandData = sm.rendezvous.commands[name]

                    if type(commandData) == "table" and not commandData.bound then
                        local command  = commandData.command
                        local params   = commandData.params
                        local callback = commandData.callback
                        local help     = commandData.help

                        local cleanName = command:gsub("/", "")
                        cleanName = cleanName:gsub("[^%w_]", "_")

                        local methodSelector = "rdv_cmd_" .. cleanName
                        classTable[methodSelector] = callback
                    
                        commandData.command = nil
                        commandData.params = nil
                        commandData.callback = nil
                        commandData.help = nil
                        commandData.bound = true

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

function sm.rendezvous.bindChatCommand(command, params, callback, help) -- GOGI стилизовать ошибки под игру
    sm.rendezvous.assertArgument(command, 1, {"string"})
    sm.rendezvous.assertArgument(params, 1, {"table"})
    sm.rendezvous.assertArgument(callback, 1, {"function"})
    sm.rendezvous.assertArgument(help, 1, {"string"})

    if string.sub(command, 1, 1) ~= "/" then
        command = "/" .. command
    end

    if #command == 1 then
        return
    end

    if sm.rendezvous.commands[command] ~= nil then return end

    local exists, description = pcall(sm.json.open, "$CONTENT_DATA/description.json")
    if not exists or type(description) ~= "table" or not description.localId then return end

    local trace = select(2, pcall(error, "", 3))
    local uuid, path, line = trace:match("([%w%-]+)/([^%]]+)\"%]:(%d+)")

    if not uuid or not path or not line then return end
    if not string.find(description.localId, uuid, 1, true) then return end

    local owner = {
        localId = description.localId,
        name = description.name,
        source = "$CONTENT_" .. description.localId .. "/" .. path .. ":" .. line
    }

    sm.rendezvous.commands[command] = {
        command = command,
        params = params,
        callback = callback,
        help = help,
        owner = owner
    }

    table.insert(sm.rendezvous.pendingCommands, command)
end

function Loader:client_onCreate()
    if not sm.rendezvous.isGameHooked then
        sm.gui.chatMessage("[sm.rendezvous] Failed to hook game env.")
    end
end

function Loader:client_onRefresh()
    self:client_onCreate()
end

function Loader:client_onFixedUpdate()
    local pendingCommands = sm.rendezvous.pendingCommands
    if #pendingCommands == 0 then return end

    if sm.event.sendToGame("rdv_bindChatCommands", pendingCommands) then
        sm.rendezvous.pendingCommands = {}
    end
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
