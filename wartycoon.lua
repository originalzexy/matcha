-- ============================================================
--  War Tycoon AutoFarm Script  |  by originalzex
-- ============================================================

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

-- ── State ────────────────────────────────────────────────────
local autoBuyRunning = false

-- ── Task Queue ───────────────────────────────────────────────
-- A sequential task runner. Push named tasks onto it, then call :start().
-- The queue runs each task one at a time and stops early if autoBuyRunning
-- is turned off. Adding a new feature later (oil, airdrops, etc.) is just
-- one farmQueue:push() call in the main loop below.
local farmQueue = {
    _tasks   = {},
    _running = false,
}

function farmQueue:push(label, fn)
    table.insert(self._tasks, { label = label, fn = fn })
end

function farmQueue:clear()
    self._tasks  = {}
    self._running = false
end

function farmQueue:isRunning()
    return self._running
end

function farmQueue:start()
    if self._running then return end
    self._running = true
    task.spawn(function()
        while #self._tasks > 0 do
            if not autoBuyRunning then break end
            local item = table.remove(self._tasks, 1)
            local ok, err = pcall(item.fn)
            if not ok then
                warn("[Queue:" .. item.label .. "] " .. tostring(err))
            end
        end
        self:clear()
    end)
end

-- ── Button restrictions config ────────────────────────────────
-- To add a button: { Name = "exact name in game", Default = true }
-- To add a category: new block with Category, Icon, Buttons
-- Default = true  → autobuy SKIPS this button
-- Default = false → autobuy WILL buy this button
local restrictionCategories = {
    {
        Category = "Helicopters",
        Icon     = "wind",
        Buttons  = {
            { Name = "Mi28 Havoc",        Default = true },
            { Name = "Invictus",          Default = true },
            { Name = "Eurocopter Tiger",  Default = true },
            { Name = "KA-52 Alligator",   Default = true },
            { Name = "AH-64 Apache",      Default = true },
            { Name = "Super Stallion",    Default = true },
            { Name = "UH-60 Black Hawk",  Default = true },
            { Name = "RAH-66 Comanche",   Default = true },
            { Name = "Z-10",              Default = true },
            { Name = "A129 Mangusta",     Default = true },
            { Name = "Raider X",          Default = true },
            { Name = "AH-1Z Viper",       Default = true },
            { Name = "KA-50 Black Shark", Default = true },
        },
    },
    {
        Category = "Ground Vehicles",
        Icon     = "shield",
        Buttons  = {
            { Name = "Speedy Humvee",      Default = true },
            { Name = "HEMTT A3",           Default = true },
            { Name = "Patriot AA",         Default = true },
            { Name = "Humvee Hawkeye",     Default = true },
            { Name = "Lazar 3 APC",        Default = true },
            { Name = "M142 HIMARS ATACMS", Default = true },
            { Name = "Stryker MGS",        Default = true },
            { Name = "M142 HIMARS",        Default = true },
            { Name = "LAV-25",             Default = true },
            { Name = "Pantsir S1",         Default = true },
            { Name = "Type 625E",          Default = true },
            { Name = "M1117 Guardian",     Default = true },
            { Name = "JLTV",               Default = true },
            { Name = "LAV-AD",             Default = true },
            { Name = "Stryker M-SHORAD",   Default = true },
            { Name = "Gunship",            Default = true },
            { Name = "BTR-80",             Default = true },
            { Name = "VCAC Mephisto",      Default = true },
        },
    },
    {
        Category = "Naval",
        Icon     = "anchor",
        Buttons  = {
            { Name = "USS Zumwalt",          Default = true },
            { Name = "Fairmile",             Default = true },
            { Name = "PG-02",                Default = true },
            { Name = "Project 1124",         Default = true },
            { Name = "USS Douglas",          Default = true },
            { Name = "Pr. 206",              Default = true },
            { Name = "USS Independence",     Default = true },
            { Name = "Sigma-Class Corvette", Default = true },
            { Name = "PACV-77 Windshear",    Default = true },
            { Name = "PACV-78 Rampage",      Default = true },
        },
    },
    {
        Category = "Weapons",
        Icon     = "crosshair",
        Buttons  = {
            { Name = "FAMAS Group Gun",        Default = true },
            { Name = "FAL Heavy Giver",        Default = true },
            { Name = "Explosive Sniper Giver", Default = true },
            { Name = "Desert Eagle Giver",     Default = true },
            { Name = "Javelin Giver",          Default = true },
            { Name = "AWP Giver",              Default = true },
            { Name = "Remington ACR Giver",    Default = true },
            { Name = "Gas Grenade Giver",      Default = true },
            { Name = "USP 45 Giver",           Default = true },
            { Name = "AK12 Giver",             Default = true },
            { Name = "Saiga-12k Giver",        Default = true },
            { Name = "Barrett M82 Giver",      Default = true },
            { Name = "Barrett M82",            Default = true },
            { Name = "KSG 12 Giver",           Default = true },
            { Name = "PP19 Bizon Giver",       Default = true },
            { Name = "Hovercraft C4 Giver",    Default = true },
            { Name = "Hovercraft QBZ-95 Giver", Default = true },
            { Name = "Hovercraft QJB-LMG Giver", Default = true },
            { Name = "AVH Reaper",             Default = true },
            { Name = "M1918 BAR Giver" , Default = true },
            { Name = "M14 Rifle Giver", Default = true },
            { Name = "M1903 Springfield Giver",             Default = true },
        },
    },
    {
        Category = "Misc",
        Icon     = "box",
        Buttons  = {
            { Name = "2x Health Armor",   Default = true },
            { Name = "KizmoTek Clothing", Default = true },
            { Name = "WW2 US Army Pack",  Default = true },
            { Name = "Base Shield",       Default = true },
            { Name = "Vietnam Armor",  Default = true },
            { Name = "Vietnam Clothing",       Default = true },
        },
    },
}





-- Build live lookup table from the config above
local restrictedButtons = {}
for _, category in ipairs(restrictionCategories) do
    for _, entry in ipairs(category.Buttons) do
        restrictedButtons[entry.Name] = entry.Default
    end
end

-- ── Oil deposit CFrames (per tycoon name) ────────────────────
local oilDeposits = {
    ["Alpha"]   = CFrame.new(-879.42,  65.52, -4862.38,  0.28, -0, -0.96, -0, 1, -0, 0.96, 0,  0.28),
    ["Bravo"]   = CFrame.new( 103.88,  65.37, -4906.46, -0,   -0, -1,    -0, 1, -0, 1,    0, -0),
    ["Charlie"] = CFrame.new(1107.75,  67.35, -4643.60, -0.22, -0, -0.97,  0, 1, -0, 0.97, -0, -0.22),
    ["Delta"]   = CFrame.new(2264.97,  68.31, -3745.31, -0.70, -0, -0.71,  0, 1, -0, 0.71, -0, -0.70),
    ["Echo"]    = CFrame.new(2867.60,  67.62, -2731.19, -0.90, -0, -0.43, -0, 1, -0, 0.43,  0, -0.90),
    ["Hotel"]   = CFrame.new(3221.24,  66.51,   904.23, -0.98, -0,  0.18, -0, 1,  0, -0.18, 0, -0.98),
}

-- ── Static locations ─────────────────────────────────────────
local staticLocations = {
    ["Oil Rig 1"]     = CFrame.new( 1705.62, 120.95,  3778.51, -1,    0, -0,    0, 1,  0,  0,    0, -1) + Vector3.new(0, 8, 0),
    ["Oil Rig 2"]     = CFrame.new(-1937.25, 120.95, -3697.70,  1,   -0,  0.04, 0, 1,  0, -0.04,-0,  1),
    ["Oil Warehouse"] = CFrame.new(-1209.48,  72.70,  -879.73,  0.75, 0, -0.67,-0, 1, -0,  0.67, 0,  0.75),
    ["Control Point"] = CFrame.new( -502.28, 177.04, -1029.86, -0.94,-0,  0.35,-0, 1,  0, -0.35, 0, -0.94),
}

-- ── Helpers ──────────────────────────────────────────────────
local function getTycoon()
    local team = localPlayer.Team
    if not team then return nil end
    local tycoonRoot = Workspace:FindFirstChild("Tycoon")
    if not tycoonRoot then return nil end
    local tycoonsFolder = tycoonRoot:FindFirstChild("Tycoons")
    if not tycoonsFolder then return nil end
    return tycoonsFolder:FindFirstChild(team.Name)
end

local function getHRP()
    local character = Workspace:FindFirstChild(localPlayer.Name)
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getLeaderstat(name)
    local ls = localPlayer:FindFirstChild("leaderstats")
    if not ls then return 0 end
    local val = ls:FindFirstChild(name)
    return val and val.Value or 0
end

local function getCash()     return getLeaderstat("Cash")     end
local function getRebirths() return getLeaderstat("Rebirths") end

-- ── Price parsing ────────────────────────────────────────────
local function parsePrice(priceText)
    if type(priceText) ~= "string" or priceText:sub(1, 1) ~= "$" then return nil end
    -- () discards gsub's substitution count so tonumber doesn't receive it as a base
    return tonumber((priceText:gsub("[$,]", "")))
end

local function getButtonPrice(button)
    local label = button:FindFirstChild("Neon")
        and button.Neon:FindFirstChild("UI")
        and button.Neon.UI:FindFirstChild("BillboardGui")
        and button.Neon.UI.BillboardGui:FindFirstChild("Frame")
        and button.Neon.UI.BillboardGui.Frame:FindFirstChild("Price")
    if not label then return nil end
    local text = (type(label.Text) == "string" and #label.Text > 0 and label.Text)
              or (type(label:GetAttribute("Text")) == "string" and label:GetAttribute("Text"))
    if not text then return nil end
    return parsePrice(text)
end

local function getRebirthRequirement(button)
    local frame = button:FindFirstChild("Neon")
        and button.Neon:FindFirstChild("UI")
        and button.Neon.UI:FindFirstChild("BillboardGui")
        and button.Neon.UI.BillboardGui:FindFirstChild("Frame")
    if not frame then return 0 end
    local priceLabel = frame:FindFirstChild("Price")
    if not priceLabel then return 0 end
    local text = priceLabel.Text
    if text and text:find("Rebirth") then
        return tonumber((text:match("%d+"))) or 0
    end
    return 0
end

-- ── Movement ─────────────────────────────────────────────────
local function teleportTo(location)
    local hrp = getHRP()
    if not hrp then return end
    if typeof(location) == "CFrame" then
        hrp.CFrame = location + Vector3.new(0, 3, 0)
    elseif location and location.CFrame then
        hrp.CFrame = location.CFrame + Vector3.new(0, 3, 0)
    end
end

local function teleportToButton(button)
    local hrp = getHRP()
    if not hrp or not button.Part then return false end
    hrp.CFrame = button.Part.CFrame + Vector3.new(0, 1, 0)
    return true
end

-- ── Collector ────────────────────────────────────────────────
local function getCollectorPosition()
    local tycoon = getTycoon()
    if not tycoon then return nil end
    local bottom = tycoon:FindFirstChild("Essentials")
        and tycoon.Essentials:FindFirstChild("CollectorParts")
        and tycoon.Essentials.CollectorParts:FindFirstChild("Collector")
        and tycoon.Essentials.CollectorParts.Collector:FindFirstChild("Bottom")
    return bottom and bottom.Position
end

local function collectMoney()
    local hrp = getHRP()
    if not hrp then return end
    local collectorPos = getCollectorPosition()
    if not collectorPos then return end
    local savedPos = hrp.Position
    hrp.Position = collectorPos
    task.wait(0.5)
    hrp.Position = savedPos
end

-- ── Auto-buy (cheapest → most expensive) ─────────────────────
local function autoBuyUpgrades()
    local tycoon = getTycoon()
    if not tycoon then return end

    local unpurchasedButtons = tycoon:FindFirstChild("UnpurchasedButtons")
    if not unpurchasedButtons then return end

    local playerRebirths = getRebirths()

    -- Medbay Start gets priority before the sorted pass
    local medbayStart = unpurchasedButtons:FindFirstChild("Medbay Start")
    if medbayStart then
        teleportToButton(medbayStart)
        task.wait(0.5)
    end

    -- Collect all eligible buttons and their prices
    local eligible = {}
    for _, button in ipairs(unpurchasedButtons:GetChildren()) do
        if not button:IsA("Model") then continue end
        if button.Name:lower():find("gamepass") then continue end
        if restrictedButtons[button.Name] then continue end

        local rebirthReq = getRebirthRequirement(button)
        if playerRebirths < rebirthReq then continue end

        local price = getButtonPrice(button) or 0
        table.insert(eligible, { button = button, price = price })
    end

    -- Sort cheapest to most expensive (free buttons = 0 go first)
    table.sort(eligible, function(a, b)
        return a.price < b.price
    end)

    -- Buy in sorted order
    for _, item in ipairs(eligible) do
        if not autoBuyRunning then break end
        if item.price > 0 then
            if getCash() >= item.price and teleportToButton(item.button) then
                print("Buying ", item.price)
                task.wait(1)
            end
        else
            teleportToButton(item.button)
        end
    end
end

-- ── Barrel collection ────────────────────────────────────────
-- VK codes: W=0x57  A=0x41  S=0x53  D=0x44  Space=0x20
local MOVEMENT_KEYS = { 0x57, 0x41, 0x53, 0x44, 0x20 }

local function isMovementPressed()
    for _, vk in ipairs(MOVEMENT_KEYS) do
        if iskeypressed(vk) then return true end
    end
    return false
end

-- Waits up to `seconds`, polling every 0.1s.
-- Returns true if movement was detected (cancelled), false if elapsed normally.
local function waitOrCancel(seconds)
    local elapsed = 0
    while elapsed < seconds do
        if isMovementPressed() then 
            notify("Oil Cancelled", "Cancelled", 5)
            return true 
        end
        task.wait(0.1)
        elapsed += 0.1
    end
    return false
end

local function getAllBarrels()
    task.wait(1)
    local tycoon = getTycoon()
    if not tycoon then return end

    if not oilDeposits[tycoon.Name] then
        notify("This base is not supported yet.", "Error", 5)
        return
    end

    local deposit = oilDeposits[tycoon.Name]

    -- Returns true if cancelled by movement input
    local function visitRigAndDeposit(rigLocation)
        teleportTo(rigLocation)
        if waitOrCancel(0.5) then return true end

        keypress(0x45)
        if waitOrCancel(2) then keyrelease(0x45) return true end
        keyrelease(0x45)

        teleportTo(deposit)
        if waitOrCancel(0.5) then return true end

        keypress(0x45)
        if waitOrCancel(2) then keyrelease(0x45) return true end
        keyrelease(0x45)

        if waitOrCancel(8) then return true end
        return false
    end

    local rigs = {
        staticLocations["Oil Rig 1"],
        staticLocations["Oil Rig 2"],
        staticLocations["Oil Warehouse"],
    }

    for _, loc in ipairs(rigs) do
        if visitRigAndDeposit(loc) then
            notify("Barrel collection cancelled — movement detected.", "Cancelled", 3)
            return
        end
    end
end

-- ── UI ───────────────────────────────────────────────────────
loadstring(game:HttpGet("https://scripts.wabisabi.mom/wabi-sabi-ui-lib.lua"))()
local Library = WabiSabi

local Window = Library:CreateWindow({
    Title      = "War Tycoon",
    SubTitle   = "by originalzex",
    Size       = Vector2.new(700, 540),
    Resize     = true,
    ConfigName = "wartycoon",
})

-- ── AutoFarm tab ─────────────────────────────────────────────
local farmTab     = Window:AddTab({ Title = "AutoFarm", Icon = "bot" })
local farmSection = farmTab:AddSection("AutoFarm")

farmSection:AddToggle({
    Id       = "AutoBuy",
    Title    = "AutoBuy",
    Default  = false,
    Keybind  = "F1",
    Callback = function(state)
        autoBuyRunning = state
        if not state then farmQueue:clear() end
    end,
})

farmSection:AddButton({
    Title    = "Get All Barrels",
    Callback = function()
        notify("Getting all barrels, movement will cancel", "Barrels", 5)
        task.spawn(getAllBarrels)
    end,
})

-- ── Teleports tab ─────────────────────────────────────────────
local tpTab     = Window:AddTab({ Title = "Teleports", Icon = "map-pin" })
local tpSection = tpTab:AddSection("Locations")

local function addTeleportButton(label, locationKey)
    tpSection:AddButton({
        Title    = label,
        Callback = function()
            if staticLocations[locationKey] then
                teleportTo(staticLocations[locationKey])
                return
            end
            if locationKey == "Base" then
                local tycoon = getTycoon()
                local mainPart = tycoon and tycoon:FindFirstChild("MainPart")
                if mainPart then teleportTo(mainPart.CFrame + Vector3.new(0, 5, 0)) end
            elseif locationKey == "Oil Deposit" then
                local tycoon = getTycoon()
                if tycoon and oilDeposits[tycoon.Name] then
                    teleportTo(oilDeposits[tycoon.Name])
                end
            end
        end,
    })
end

addTeleportButton("Oil Rig 1",     "Oil Rig 1")
addTeleportButton("Oil Rig 2",     "Oil Rig 2")
addTeleportButton("Oil Warehouse", "Oil Warehouse")
addTeleportButton("Base",          "Base")
addTeleportButton("Oil Deposit",   "Oil Deposit")
addTeleportButton("Control Point", "Control Point")

-- ── Restrictions tab ─────────────────────────────────────────
local restrictTab = Window:AddTab({ Title = "Restrictions", Icon = "shield-off" })

local toggleIndex = 0
for _, category in ipairs(restrictionCategories) do
    local section = restrictTab:AddSection(category.Category)
    for _, entry in ipairs(category.Buttons) do
        toggleIndex += 1
        section:AddToggle({
            Id          = "restrict_" .. toggleIndex,
            Title       = entry.Name,
            Description = "ON = skip  |  OFF = allow purchase",
            Default     = entry.Default,
            Callback    = function(state)
                restrictedButtons[entry.Name] = state
            end,
        })
    end
end

-- ── Main farm loop ───────────────────────────────────────────
-- To add a new feature to the cycle, push it here in the order you want.
-- The queue runs each task sequentially and stops if autoBuyRunning is off.
task.spawn(function()
    while not Library.Unloaded do
        task.wait(0.5)
        if autoBuyRunning and not farmQueue:isRunning() then
            farmQueue:push("AutoBuy",      autoBuyUpgrades)
            farmQueue:push("CollectMoney", collectMoney)
            -- Future tasks (uncomment when ready):
            -- farmQueue:push("GetOil",      getAllBarrels)
            -- farmQueue:push("GetAirdrops", getAirdrops)
            farmQueue:start()
        end
    end
end)

-- ── Admin detection loop ─────────────────────────────────────
task.spawn(function()
    while not Library.Unloaded do
        task.wait(0.1)
        for _, player in ipairs(Players:GetPlayers()) do
            local rank = player:FindFirstChild("AdminRank")
            if rank and rank.Value ~= 0 then
                warn("[Admin] Detected:", player.Name)
                notify("Turn off everything — " .. player.Name .. " is present!", "Admin Detected!", 60)
                autoBuyRunning = false
                farmQueue:clear()
                break
            end
        end
    end
end)

notify("Welcome! Script by originalzex", "War Tycoon", 5)
