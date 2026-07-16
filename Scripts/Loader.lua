---@diagnostic disable

if not sm.rendezvous then
    sm.rendezvous = {
        initializedByTool = false,
        isGameHooked = false,

        commands = {},

        classExists = function()
            error("sm.rendezvous.classExists cannot be called yet: the game world has not finished loading.")
        end,
        getLoadedClasses = function()
            error("sm.rendezvous.getLoadedClasses cannot be called yet: the game world has not finished loading.")
        end
    }

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
end

if sm.rendezvous.initializedByTool then
    local gameEnv = _G
    local CLASS_RULES = {
        {
            type = "ScriptableObjectClass",
            keys = { "isSaveObject" }
        },
        {
            type = "WorldClass",
            keys = {
                "cellMaxX", "cellMaxY", "cellMinX", "cellMinY", "enableAssets", "enableClutter",
                "enableCreations", "enableHarvestables", "enableKinematics", "enableNodes",
                "enableSurface", "groundMaterialSet", "isIndoor", "isStatic", "renderMode",
                "terrainScript", "worldBorder"
            }
        },
        {
            type = "GameClass",
            keys = {
                "defaultInventorySize", "enableAggro", "enableAmmoConsumption",
                "enableFuelConsumption", "enableLimitedInventory", "enableRestrictions", "enableUpgrade"
            }
        },
        {
            type = "PlayerClass",
            keys = { "server_onShapeRemoved", "server_onInventoryChanges", "client_onCancel", "client_onReload" }
        },
        {
            type = "UnitClass",
            keys = { "server_onUnitUpdate", "server_onCharacterChangedColor" }
        },
        {
            type = "CharacterClass",
            keys = { "client_onGraphicsLoaded", "client_onGraphicsUnloaded", "client_onEvent" }
        },
        {
            type = "ToolClass",
            keys = {
                "client_onEquip", "client_onUnequip", "client_onEquippedUpdate",
                "onToggle", "client_canEquip", "client_equipWhileSeated"
            }
        },
        {
            type = "HarvestableClass",
            keys = { "server_onReceiveUpdate", "server_onRemoved" }
        },
        {
            type = "ShapeClass",
            keys = {
                "colorHighlight", "colorNormal", "connectionInput", "connectionOutput",
                "maxChildCount", "maxParentCount", "client_onTinker", "client_canTinker",
                "client_onInteractThroughJoint", "client_canInteractThroughJoint", "client_canCarry",
                "client_getAvailableParentConnectionCount", "client_getAvailableChildConnectionCount"
            }
        }
    }

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

    function sm.rendezvous.getClassType(className) -- GOGI переписать эту залупу и придумать точный определитель.
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
            classTable.rdv_bindChatCommands = function(self, unboundCommands)
                for _, name in ipairs(unboundCommands) do
                    local commandData = sm.rendezvous.commands[name]

                    if commandData and not commandData.bound then
                        local command  = commandData.command
                        local params   = commandData.params
                        local callback = commandData.callback
                        local help     = commandData.help

                        local cleanName = command:gsub("/", "")
                        cleanName = cleanName:gsub("[^%w_]", "_")

                        local methodSelector = "rdv_cmd_" .. cleanName
                        classTable[methodSelector] = callback
                    
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
    assert(type(command) == "string", string.format("bad argument #1 (string expected, got %s)", type(command)))
    assert(type(params) == "table", string.format("bad argument #2 (table expected, got %s)", type(params)))
    assert(type(callback) == "function", string.format("bad argument #3 (function expected, got %s)", type(callback)))
    assert(type(help) == "string", string.format("bad argument #4 (string expected, got %s)", type(help)))

    if string.sub(command, 1, 1) ~= "/" then
        command = "/" .. command
    end

    assert(sm.rendezvous.commands[command] == nil, string.format("Command %s already exists", command))

    local owner = {}

    local exists, description = pcall(sm.json.open, "$CONTENT_DATA/description.json")
    assert(exists, "[sm.rendezvous] Failed to load description.json. Make sure this is a valid Scrap Mechanic mod.")
    assert(type(description) == "table" and description.type == "Blocks and Parts", "[sm.rendezvous] This mod is not a valid Blocks and Parts mod (invalid description.json)")

    local trace = select(2, pcall(error, "", 3))

    owner.localId = description.localId
    owner.name = description.name
    owner.source = trace:match("([^%s]+:%d+)") -- GOGI

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
    local pendingCommands = sm.rendezvous.pendingCommands
    if #pendingCommands == 0 then return end

    if sm.event.sendToGame("rdv_bindChatCommands", pendingCommands) then
        sm.rendezvous.pendingCommands = {}
    end
end


-- 065a0d50ffba10dcbe972b39f700cc439e0d40823f77540ac620e58435c5f384a0d89946e7b6f7ad9aee450a38ac3939165a556706a0868e3427edc7a40383b8f1ace54418c0892d08f3e3928aa2eafb24ed68206c016ca8d75c93828b5bc7403cd3ac1d979e83ebe1957601ead163a5d326369e2f347fa30365baf4fe61abd60d115f6007b0f7e26603d6085a831ef6f2d122348894b20f813fdb4dc6feadb4f63bb82cf07cba7c0c38bce40c66a3e9cc6f43b16ef61c59489f31834eca87665268a4bc151921c9abdd32336d45e072a0692beff6df90d668b3b8c7f4a7bd34bc61bb465bc432dc490ea67c18aa9c98cd0ec9f0483ac08e251dce834ee5c9be7d7d3f81548f61f5f11135e76b2b89ad2f7308144284ecd1a27eedb78eeb685b17ea12d4f85b4dd8b86a2b80742c243b70bebafebec704ce0fee6ef99f51e7d72d27c78d6d4df548c9d045f0f3da0da591398fda3845f3a63ba7598e5c037885c00c740c47f254edc100236f9b5140cf57137efcce6d10019403d85466687ee3e8cabcee554a73a51fdc7b8eda01951357cce7f171816713b20ed567b522fcbf99e0bfc0bb99ab960f8ba0b930ed43b73d3a14fa766401e1d58dead1249146e2dff90163c8ef3db1f9c9a60490db8877b44988261041acacad48ebbc175d64b136db39ca3cf9247b378b35e75d21183d8d12b72b7b787b520ff46c35c9aa69c6206140bf14d23a2248aeae1ce2b33a83af4bb8de7f4432e1bd3fe1ed9694ca20b829f1832c1f061214bfbe13bfc2dfb1a7e7e6fbf07b909f1d3d8af3fbfe259bab2d2d4bae4bc9dbf6a51a060362703db060687b543846c261c06162bd3c6d40a84a261e03cdce713a241463c629eb29d6dbb0144a9e19473cdb5200524b9667