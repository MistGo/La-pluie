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
            classTable.rdv_bindChatCommands = function(self, unboundCommands)
                for _, name in ipairs(unboundCommands) do
                    local commandData = sm.rendezvous.unboundCommands[name]

                    if commandData and not commandData.bound then
                        local command  = commandData.command
                        local params   = commandData.params
                        local callback = commandData.callback
                        local help     = commandData.help
                        local cleanName = command:gsub("/", "")
                        local methodSelector = "rdv_cmd_" .. cleanName
                        classTable[methodSelector] = callback
                    
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

    assert(sm.rendezvous.unboundCommands[command] == nil, string.format("Command %s already exists", command))

    local owner = {}

    local exists, description = pcall(sm.json.open, "$CONTENT_DATA/description.json")
    assert(exists, "[sm.rendezvous] Failed to load description.json. Make sure this is a valid Scrap Mechanic mod.")
    assert(type(description) == "table" and description.type == "Blocks and Parts", "[sm.rendezvous] This mod is not a valid Blocks and Parts mod (invalid description.json)")


    if exists and type(description) == "table" then
        
    end

    sm.rendezvous.unboundCommands[command] = {
        command = command,
        params = params,
        callback = callback,
        help = help,
        owner = owner
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

    local pending = {}

    for name, data in pairs(sm.rendezvous.unboundCommands) do
        if not data.bound then
            table.insert(pending, name)
        end
    end

    if #pending > 0 then
        sm.event.sendToGame("rdv_bindChatCommands", pending)
    end

    sm.rendezvous.hasUnboundCommand = false
end
