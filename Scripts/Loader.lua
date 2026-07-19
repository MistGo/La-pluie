---@diagnostic disable

if not sm.rendezvous then
    local function notReady(name)
        error(string.format("'%s' is unavailable: API is waiting for the game world to load.", name), 2)
    end

    sm.rendezvous = {
        initializedByTool = false,
        isGameHooked      = false,

        commands          = {},
        pendingCommands   = {},

        hooks             = {},
        pendingHooks      = {},

        isLoaded          = function() notReady("isLoaded") end,
        getClasses        = function() notReady("getClasses") end,
        getType           = function() notReady("getType") end,
        hasMethod         = function() notReady("hasMethod") end
    }

    sm.rendezvous.assert = function(value, argIndex, str, override)
        if value then return end

        local errorMsg = override and str or string.format("bad argument #%d (%s)", argIndex, str)

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

    local CLASS_SIGNATURES = { ShapeClass = { colorHighlight = true, colorNormal = true, connectionInput = true, connectionOutput = true, maxChildCount = true, maxParentCount = true, client_onTinker = true, client_canTinker = true, client_onInteractThroughJoint = true, client_canInteractThroughJoint = true, client_canCarry = true, client_getAvailableParentConnectionCount = true, client_getAvailableChildConnectionCount = true }, ToolClass = { client_onEquip = true, client_onUnequip = true, client_onEquippedUpdate = true, onToggle = true, client_canEquip = true, client_equipWhileSeated = true }, CharacterClass = { client_onGraphicsLoaded = true, client_onGraphicsUnloaded = true, client_onEvent = true }, UnitClass = { server_onUnitUpdate = true, server_onCharacterChangedColor = true }, PlayerClass = { server_onShapeRemoved = true, server_onInventoryChanges = true, client_onCancel = true, client_onReload = true }, HarvestableClass = { server_onReceiveUpdate = true, server_onRemoved = true }, GameClass = { defaultInventorySize = true, enableAggro = true, enableAmmoConsumption = true, enableFuelConsumption = true, enableLimitedInventory = true, enableRestrictions = true, enableUpgrade = true }, WorldClass = { cellMaxX = true, cellMaxY = true, cellMinX = true, cellMinY = true, enableAssets = true, enableClutter = true, enableCreations = true, enableHarvestables = true, enableKinematics = true, enableNodes = true, enableSurface = true, groundMaterialSet = true, isIndoor = true, isStatic = true, renderMode = true, terrainScript = true, worldBorder = true }, ScriptableObjectClass = { isSaveObject = true } }

    function sm.rendezvous.isLoaded(className)
        sm.rendezvous.assertArgument(className, 1, { "string" })

        local classTable = _G[className]

        return type(classTable) == "table" and classTable == classTable.__index
    end

    function sm.rendezvous.getClasses()
        local loadedClasses = {}

        for className, _ in pairs(_G) do
            if sm.rendezvous.isLoaded(className) then
                table.insert(loadedClasses, className)
            end
        end

        return loadedClasses
    end

    function sm.rendezvous.getType(className)
        sm.rendezvous.assertArgument(className, 1, { "string" })

        local cached = _G.ClassTypeCache[className]
        if cached then
            return cached
        end

        if not sm.rendezvous.isLoaded(className) then
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

    function sm.rendezvous.hasMethod(className, methodName)
        sm.rendezvous.assertArgument(className, 1, { "string" })
        sm.rendezvous.assertArgument(methodName, 2, { "string" })

        if not sm.rendezvous.isLoaded(className) then
            return false
        end

        return type(_G[className][methodName]) == "function"
    end

    local function wrapMethod(originalMethod, callbacks)
        return function(...)
            local beforeHooks = callbacks[0]
            for i = 1, #beforeHooks do
                beforeHooks[i].callback(...)
            end

            local returns = { originalMethod(...) }

            local afterHooks = callbacks[1]
            for i = 1, #afterHooks do
                afterHooks[i].callback(...)
            end

            return unpack(returns)
        end
    end

    local allowedTypes = {
        GameClass = true,
        CharacterClass = true,
        PlayerClass = true,
        WorldClass = true
    }

    for className, classTable in pairs(_G) do
        local classType = sm.rendezvous.getType(className)

        if allowedTypes[classType] then
            classTable.rdv_onEvent = function(self) end

            if classType == "GameClass" then
                classTable.rdv_bindChatCommands = function(self, pendingCommands)
                    for i = 1, #pendingCommands do
                        local name = pendingCommands[i]
                        local commandData = sm.rendezvous.commands[name]

                        if type(commandData) == "table" and not commandData.bound then
                            local cleanName = commandData.command:gsub("/", "")
                            local methodSelector = "rdv_cmd_" .. cleanName

                            classTable[methodSelector] = commandData.callback

                            if pcall(sm.game.bindChatCommand, commandData.command, commandData.params, methodSelector, commandData.help) then
                                commandData.bound = true
                            end
                        end
                    end
                end

                classTable.rdv_injectHooks = function(self, pendingHooks)
                    self.rdv = self.rdv or { hooks = {} }

                    for i = 1, #pendingHooks do
                        local hookName = pendingHooks[i]
                        local hookData = sm.rendezvous.hooks[hookName]

                        if type(hookData) == "table" and not hookData.injected then
                            local clsName = hookData.class
                            local methodName = hookData.method

                            if sm.rendezvous.isLoaded(clsName) then
                                local clsTable = _G[clsName]

                                self.rdv.hooks[clsName] = self.rdv.hooks[clsName] or {}
                                local methodData = self.rdv.hooks[clsName][methodName]

                                if not methodData then
                                    local originalMethod = clsTable[methodName] or function() end

                                    methodData = {
                                        original = originalMethod,
                                        callbacks = { [0] = {}, [1] = {} }
                                    }

                                    self.rdv.hooks[clsName][methodName] = methodData
                                    clsTable[methodName] = wrapMethod(methodData.original, methodData.callbacks)
                                end

                                table.insert(methodData.callbacks[hookData.phase], hookData)

                                table.sort(methodData.callbacks[hookData.phase], function(a, b)
                                    return a.priority < b.priority
                                end)

                                hookData.injected = true
                            end
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

local function getModOwner()
    local exists, description = pcall(sm.json.open, "$CONTENT_DATA/description.json")
    if not exists or type(description) ~= "table" or not description.localId then
        return
    end

    local trace = select(2, pcall(error, "", 4))
    local uuid, path, line = trace:match("([%w%-]+)/([^%]]+)\"%]:(%d+)")

    if not uuid or not path or not line then
        return
    end

    if not string.find(description.localId, uuid, 1, true) then
        return
    end

    return {
        localId = description.localId,
        name = description.name,
        source = "$CONTENT_" .. description.localId .. "/" .. path .. ":" .. line
    }
end

function sm.rendezvous.bindChatCommand(command, params, callback, help)
    sm.rendezvous.assertArgument(command, 1, { "string" })
    sm.rendezvous.assertArgument(params, 2, { "table" })
    sm.rendezvous.assertArgument(callback, 3, { "function" })
    sm.rendezvous.assertArgument(help, 4, { "string" })

    sm.rendezvous.assert(command:sub(1, 1) == "/", 1, "Command must start with '/'")
    sm.rendezvous.assert(#command > 1, 1, "Command is empty")

    if sm.rendezvous.commands[command] ~= nil then return end

    local owner = getModOwner()
    sm.rendezvous.assert(owner, 1, "Failed to verify mod description or identity", true)

    sm.rendezvous.commands[command] = {
        command = command,
        params = params,
        callback = callback,
        help = help,

        owner = owner
    }

    table.insert(sm.rendezvous.pendingCommands, command)
end

function sm.rendezvous.hook(className, methodName, callback, priority, phase)
    sm.rendezvous.assertArgument(className, 1, { "string" })
    sm.rendezvous.assertArgument(methodName, 2, { "string" })
    sm.rendezvous.assertArgument(callback, 3, { "function" })
    sm.rendezvous.assertArgument(priority, 4, { "number" })
    sm.rendezvous.assertArgument(phase, 5, { "number" })

    local funcId = tostring(callback):gsub("function: ", "")
    local hookName = className .. "." .. methodName .. "." .. funcId

    if sm.rendezvous.hooks[hookName] ~= nil then return end -- GOGI решить проблему с названием хуков

    sm.rendezvous.assert(priority > 0 and priority <= 100, 4, "Priority must be a number between 1 and 100")
    sm.rendezvous.assert(phase == 0 or phase == 1, 5,
        "Phase must be 0 (execution at the start) or 1 (execution at the end)")

    local owner = getModOwner()
    sm.rendezvous.assert(owner, 1, "Failed to verify mod description or identity", true)

    sm.rendezvous.hooks[hookName] = {
        class = className,
        method = methodName,
        callback = callback,
        priority = priority,
        phase = phase,

        owner = owner
    }

    table.insert(sm.rendezvous.pendingHooks, hookName)
end

function Loader:client_onCreate()
    if not sm.rendezvous.isReady() then
        sm.gui.chatMessage("[sm.rendezvous] Failed to hook game env.")
    end

    if sm.rendezvous and sm.rendezvous.isReady() then
        sm.rendezvous.injectHook(
            "CreativePlayer",
            "client_onReload",
            function(self)
                print("[TEST-BEFORE] Хук сработал!")
            end,
            50,
            0)
    end
end

function Loader:client_onRefresh()
    self:client_onCreate()
end

function Loader:client_onFixedUpdate()
    local pendingCommands = sm.rendezvous.pendingCommands
    if #pendingCommands > 0 then
        if sm.event.sendToGame("rdv_bindChatCommands", pendingCommands) then
            sm.rendezvous.pendingCommands = {}
        end
    end

    local pendingHooks = sm.rendezvous.pendingHooks
    if #pendingHooks > 0 then
        if sm.event.sendToGame("rdv_injectHooks", pendingHooks) then
            sm.rendezvous.pendingHooks = {}
        end
    end
end

local funcsToHook = {
    { sm.world, "createWorld" },
    { sm.world, "loadWorld" },
    { sm.game,  "bindChatCommand" },
    { sm.gui,   "createSurvivalHudGui" }
}

for i = 1, #funcsToHook do
    local namespace = funcsToHook[i][1]
    local method = funcsToHook[i][2]
    local originalFunc = namespace[method]

    if originalFunc then
        namespace[method] = function(...)
            if not sm.rendezvous.hookedFrom then
                sm.rendezvous.hookedFrom = method
                dofile("$CONTENT_ac2379db-1c7d-49fd-9d2e-4ccc6d11ce93/Scripts/Loader.lua")
            end
            return originalFunc(...)
        end
    end
end
