---@diagnostic disable

if not sm.rendezvous then
    sm.rendezvous = {
        initializedByTool = false,
        isGameHooked = false,

        commands = {},
        pendingCommands = {},

        isClassLoaded = function()
            error("'sm.rendezvous.isClassLoaded' cannot be called yet: the game world has not finished loading.")
        end,
        getAllLoadedClasses = function()
            error("'sm.rendezvous.getAllLoadedClasses' cannot be called yet: the game world has not finished loading.")
        end,
        getClassType = function()
            error("'sm.rendezvous.getClassType' cannot be called yet: the game world has not finished loading.")
        end
    }

    sm.rendezvous.assert = function(value, argIndex, str)
        if value then return end

        local errorMsg = string.format("bad argument #%d (%s)", argIndex, str)

        error(errorMsg, 2)
    end

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
    _G.ClassTypeCache = {}

    local CLASS_SIGNATURES = {
        ShapeClass = {
            colorHighlight = true,
            colorNormal = true,
            connectionInput = true,
            connectionOutput = true,
            maxChildCount = true,
            maxParentCount = true,

            client_onTinker = true,
            client_canTinker = true,
            client_onInteractThroughJoint = true,
            client_canInteractThroughJoint = true,
            client_canCarry = true,

            client_getAvailableParentConnectionCount = true,
            client_getAvailableChildConnectionCount = true
        },

        ToolClass = {
            client_onEquip = true,
            client_onUnequip = true,
            client_onEquippedUpdate = true,
            onToggle = true,
            client_canEquip = true,
            client_equipWhileSeated = true
        },

        CharacterClass = {
            client_onGraphicsLoaded = true,
            client_onGraphicsUnloaded = true,
            client_onEvent = true
        },

        UnitClass = {
            server_onUnitUpdate = true,
            server_onCharacterChangedColor = true
        },

        PlayerClass = {
            server_onShapeRemoved = true,
            server_onInventoryChanges = true,
            client_onCancel = true,
            client_onReload = true
        },

        HarvestableClass = {
            server_onReceiveUpdate = true,
            server_onRemoved = true
        },

        GameClass = {
            defaultInventorySize = true,
            enableAggro = true,
            enableAmmoConsumption = true,
            enableFuelConsumption = true,
            enableLimitedInventory = true,
            enableRestrictions = true,
            enableUpgrade = true
        },

        WorldClass = {
            cellMaxX = true,
            cellMaxY = true,
            cellMinX = true,
            cellMinY = true,

            enableAssets = true,
            enableClutter = true,
            enableCreations = true,
            enableHarvestables = true,
            enableKinematics = true,
            enableNodes = true,
            enableSurface = true,

            groundMaterialSet = true,
            isIndoor = true,
            isStatic = true,
            renderMode = true,
            terrainScript = true,
            worldBorder = true
        },

        ScriptableObjectClass = {
            isSaveObject = true
        }
    }

    function sm.rendezvous.isClassLoaded(className)
        sm.rendezvous.assertArgument(className, 1, { "string" })

        local classTable = _G[className]

        return type(classTable) == "table" and classTable == classTable.__index
    end

    function sm.rendezvous.getAllLoadedClasses()
        local loadedClasses = {}

        for className, _ in pairs(_G) do
            if sm.rendezvous.isClassLoaded(className) then
                table.insert(loadedClasses, className)
            end
        end

        return loadedClasses
    end

    function sm.rendezvous.getClassType(className)
        sm.rendezvous.assertArgument(className, 1, { "string" })

        local cached = _G.ClassTypeCache[className]
        if cached then
            return cached
        end

        if not sm.rendezvous.isClassLoaded(className) then
            return "UnknownClass"
        end

        local classTable = _G[className]

        local bestType = "UnknownClass"
        local bestScore = 0

        for classType, signatures in pairs(CLASS_SIGNATURES) do
            local score = 0

            for key in pairs(signatures) do
                if classTable[key] ~= nil then
                    score = score + 1
                end
            end

            if score > bestScore then
                bestScore = score
                bestType = classType
            end
        end

        _G.ClassTypeCache[className] = bestType
        return bestType
    end

    -- function sm.rendezvous.getClassesOfType(classType)
    --     sm.rendezvous.assertArgument(classType, 1, { "string" })

    --     local loaded 

    -- end

    for className, classTable in pairs(_G) do
        if sm.rendezvous.getClassType(className) == "GameClass" then
            classTable.rdv_bindChatCommands = function(self, unboundCommands)
                for _, name in ipairs(unboundCommands) do
                    local commandData = sm.rendezvous.commands[name]

                    if type(commandData) == "table" and not commandData.bound then
                        local command              = commandData.command
                        local params               = commandData.params
                        local callback             = commandData.callback
                        local help                 = commandData.help

                        local cleanName            = command:gsub("/", "")
                        local methodSelector       = "rdv_cmd_" .. cleanName
                        classTable[methodSelector] = callback

                        if pcall(sm.game.bindChatCommand, command, params, methodSelector, help) then
                            commandData.command = nil
                            commandData.params = nil
                            commandData.callback = nil
                            commandData.help = nil

                            commandData.bound = true
                        end
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
    sm.rendezvous.assertArgument(command, 1, { "string" })
    sm.rendezvous.assertArgument(params, 2, { "table" })
    sm.rendezvous.assertArgument(callback, 3, { "function" })
    sm.rendezvous.assertArgument(help, 4, { "string" })

    sm.rendezvous.assert(command:sub(1, 1) == "/", 1, "Command must start with '/'")
    sm.rendezvous.assert(#command > 1, 1, "Command is empty")

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

function sm.rendezvous.isReady()
    return sm.rendezvous.isGameHooked
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
