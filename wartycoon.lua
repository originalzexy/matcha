local playersService = game:GetService("Players")
local localPlayer = playersService.LocalPlayer
local playerName = localPlayer.Name

local playersService2 = game:GetService("Players")
local localPlayer2 = playersService2.LocalPlayer
local mouse = localPlayer2:GetMouse()
local workspace = game:GetService("Workspace")
local camera = workspace.CurrentCamera

local function getPlayerTycoon()
    local tycoonRoot = workspace:FindFirstChild("Tycoon")
    local tycoonsFolder = tycoonRoot and tycoonRoot:FindFirstChild("Tycoons")
    if not tycoonsFolder then return nil end
    for i2, tycoon in ipairs(tycoonsFolder:GetChildren()) do
        if tycoon:GetAttribute("Owner") == localPlayer2.Name then
            return tycoon.Name
        end
    end
    return nil
end

local function parsePrice(priceText)
    if not priceText or typeof(priceText) ~= "string" then return nil end
    if string.sub(priceText, 1, 1) ~= "$" then return nil end
    local cleanedPriceText = priceText:gsub("[$,]", "")
    return tonumber(cleanedPriceText)
end

local function getButtonPrice(button)
    local neonPart = button:FindFirstChild("Neon")
    if not neonPart then return nil end
    local uiContainer = neonPart:FindFirstChild("UI")
    if not uiContainer then return nil end
    local billboardGui = uiContainer:FindFirstChild("BillboardGui")
    if not billboardGui then return nil end
    local frame = billboardGui:FindFirstChild("Frame")
    if not frame then return nil end
    local priceLabel = frame:FindFirstChild("Price")
    if not priceLabel then return nil end
    local priceText2 = priceLabel.Text
    if not priceText2 then
        priceText2 = priceLabel:GetAttribute("Text")
    end
    return parsePrice(priceText2)
end


local function getRebirths()
    local leaderstats = localPlayer2:FindFirstChild("leaderstats")
    if not leaderstats then return 0 end
    local rebirthsValue = leaderstats:FindFirstChild("Rebirths")
    if not rebirthsValue then return 0 end
    return rebirthsValue.Value or 0
end

local function getCash()
    local leaderstats = localPlayer2:FindFirstChild("leaderstats")
    if not leaderstats then return 0 end
    local cashValue = leaderstats:FindFirstChild("Cash")
    if not cashValue then return 0 end
    return cashValue.Value or 0
end

local function getHRP()
    local character = workspace:FindFirstChild(localPlayer2.Name)
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
end

local function getTycoon()
    local playerTeamName = localPlayer2.Team and localPlayer2.Team.Name
    if not playerTeamName then return nil end
    local tycoonRootFolder = workspace:FindFirstChild("Tycoon")
    if not tycoonRootFolder then return nil end
    local tycoonsFolder = tycoonRootFolder:FindFirstChild("Tycoons")
    if not tycoonsFolder then return nil end
    return tycoonsFolder:FindFirstChild(playerTeamName)
end

local function getUnpurchasedButtons()
    local tycoon = getTycoon()
    if not tycoon then return {} end
    local buttonsFolder = tycoon:FindFirstChild("UnpurchasedButtons")
    if not buttonsFolder then return {} end
    local unpurchasedButtons = {}
    print("Hi")
    for _, button in ipairs(buttonsFolder:GetChildren()) do
        if button:IsA("Model") then
            table.insert(unpurchasedButtons, button)
            print("Added button: " .. button.Name)
        end
    end
    print("Found", #unpurchasedButtons, "buttons")
    return unpurchasedButtons

end

local function teleportToButton(button)
    print("Attempting to teleport to button: " .. button.Name)
    local hrp = getHRP()
    if not hrp then return end
    local buttonCFrame = button.Part and button.Part.CFrame
    if not buttonCFrame then return end
    hrp.CFrame = buttonCFrame + Vector3.new(0, 1, 0)
    return true
end

local function getRebirthRequirement(button)
    if not button then return 0 end
    local buttonNeon = button:FindFirstChild("Neon")
    if not buttonNeon then return 0 end
    local buttonUI = buttonNeon:FindFirstChild("UI")
    if not buttonUI then return 0 end
    local buttonBillboard = buttonUI:FindFirstChild("BillboardGui")
    if not buttonBillboard then return 0 end

    local price = buttonBillboard.Frame:FindFirstChild("Price") and buttonBillboard.Frame:FindFirstChild("Price").Text
    if not price then return 0 end
    if string.find(price, "Rebirth") then
        local rebirthRequirement = string.match(price, "%d")
        if rebirthRequirement then
            return tonumber(rebirthRequirement) or 0
        end
    end
    return 0
end



local function getCollectorPosition()

    local tycoonModel = getTycoon()
    if not tycoonModel then return nil end
    
    local essentialsFolder = tycoonModel:FindFirstChild("Essentials")
    if not essentialsFolder then return nil end
    
    local cashCollectors = essentialsFolder:FindFirstChild("CollectorParts")
    if not cashCollectors then return nil end
    
    local collector = cashCollectors:FindFirstChild("Collector")
    if not collector then return nil end

    local bottom = collector:FindFirstChild("Bottom")
    if not bottom then return nil end

    print("Collector position: ", bottom.Position)
    return bottom.Position
end

local function collectMoney()
    print("collecting money...")
    local hrp = getHRP()
    if hrp then
        local collectorPos = getCollectorPosition()
        if collectorPos then
            local savedPos = hrp.Position
            hrp.Position = collectorPos
            wait(0.5)
            hrp.Position = savedPos
            autobuyActive = false
        end
    end
end

local function autoBuyUpgrades()    
    local playerTycoon2 = getTycoon()
    if not playerTycoon2 then return end
    
    local unpurchasedButtons = playerTycoon2:FindFirstChild("UnpurchasedButtons")

    if not unpurchasedButtons then return end
    
    local playerRebirths = getRebirths()
    local playerCash = getCash()
    
    local medbayStart = unpurchasedButtons:FindFirstChild("Medbay Start")
    if medbayStart then
        teleportToButton(medbayStart)
        wait(0.5)
    end
    
    for button3, button in ipairs(unpurchasedButtons:GetChildren()) do
        if button:IsA("Model") then
            -- local buttonType = button:GetAttribute("ButtonType")
            -- if buttonType == "Clothing" or buttonType == "Group" or buttonType == "Gamepass" or buttonType == "Reward" or buttonType == "Operation" or buttonType == "Medal" then
            --     -- Skip these button types
            -- else
            if string.find(string.lower(button.Name), "gamepass") or table.find(restrictedButtons, button.Name) then
                -- Skip gamepass buttons
            else
                local price = getButtonPrice(button)
                local rebirthRequirement3 = getRebirthRequirement(button)
                local hasRequiredRebirths = playerRebirths >= rebirthRequirement3
                if price then
                    local canAffordPurchase = playerCash >= price
                    print("Can afford purchase for button: " .. tostring(canAffordPurchase))
                    if canAffordPurchase and hasRequiredRebirths then
                        if teleportToButton(button) then
                            
                            wait(0.1)
                            playerCash = getCash()
                        end
                    end
                else
                    -- No price means it's free
                    if hasRequiredRebirths then
                        teleportToButton(button)
                    end
                end
            end
        end
    end
    
    
end

local function teleportTo(location) 
    local hrp = getHRP()
    if not hrp then return end
    if typeof(location) == "CFrame" then
        hrp.CFrame = location + Vector3.new(0, 3, 0)
        return
    end
    if location then
        hrp.CFrame = location.CFrame + Vector3.new(0, 3, 0)
        return
    end
end

autoBuyRunning = false
autoBuyActive = false

restrictedButtons = {
    "FAMAS Group Gun",
    "2x Health Armor",
    "FAL Heavy Giver",
    "Explosive Sniper Giver",
    "Desert Eagle Giver",
    "Speedy Humvee",
    "HEMTT A3",
    "Patriot AA",
    "Humvee Hawkeye",
    "Lazar 3 APC",
    "M142 HIMARS ATACMS",
    "Stryker MGS",
    "M142 HIMARS",
    "LAV-25",
    "Pantsir S1",
    "Type 625E",
    "M1117 Guardian",
    "KizmoTek Clothing",
    "Javelin Giver",
    "JLTV",
    "LAV-AD",
    "AWP Giver",
    "M142 HIMARS",
    "Remington ACR Giver",
    "Gas Grenade Giver",
    "Stryker M-SHORAD",
    "USP 45 Giver",
    "AK12 Giver",
    "Gunship",
    "Saiga-12k Giver",
    "BTR-80",
    "VCAC Mephisto",
    "Barrett M82 Giver",
    "Barrett M82",
    "Mi28 Havoc",
    "Invictus",
    "Eurocopter Tiger",
    "KA-52 Alligator",
    "AH-64 Apache",
    "Super Stallion",
    "UH-60 Black Hawk",
    "RAH-66 Comanche",
    "Z-10",
    "A129 Mangusta",
    "Raider X",
    "AH-1Z Viper",
    "Invictus",
    "KSG 12 Giver",
    "PP19 Bizon Giver",
    "USS Zumwalt",
    "KA-50 Black Shark",
    "Fairmile",
    "PG-02",
    "Project 1124",
    "USS Douglas",
    "Pr. 206",
    "USS Independence",
    "Sigma-Class Corvette",
}

oilDeposits = {
    ["Alpha"] = CFrame.new(-879.42, 65.52, -4862.38, 0.28, -0, -0.96, -0, 1, -0, 0.96, 0, 0.28),
    ["Bravo"] = CFrame.new(103.88, 65.37, -4906.46, -0, -0, -1, -0, 1, -0, 1, 0, -0),
    ["Charlie"] = CFrame.new(1107.75, 67.35, -4643.60, -0.22, -0, -0.97, 0, 1, -0, 0.97, -0, -0.22),
    ["Delta"] = CFrame.new(2264.97, 68.31, -3745.31, -0.70, -0, -0.71, 0, 1, -0, 0.71, -0, -0.70)


}

locations = {
    ["Oil Rig 1"] = CFrame.new(1705.62, 120.95, 3778.51, -1, 0, -0, 0, 1, 0, 0, 0, -1),
    ["Oil Rig 2"] = CFrame.new(-1937.25, 120.95, -3697.70, 1, -0, 0.04, 0, 1, 0, -0.04, -0, 1),
    ["Oil Warehouse"] = CFrame.new(-1209.48, 72.70, -879.73, 0.75, 0, -0.67, -0, 1, -0, 0.67, 0, 0.75),
    ["Base"] = getTycoon():FindFirstChild("MainPart").CFrame + Vector3.new(0, 5, 0),
    ["Oil Deposit"] = oilDeposits[getTycoon().Name],
    ["Control Point"] = CFrame.new(-502.28, 177.04, -1029.86, -0.94, -0, 0.35, -0, 1, 0, -0.35, 0, -0.94)

}


UI.AddTab("War Tycoon", function(tab)
    local autobuy = tab:Section("AutoBuy", "Left")
    autobuy:Toggle("autobuy_on", "AutoBuy", function(state)
        print("AutoBuy: " .. tostring(state))
        autoBuyRunning = state
    end)
    autobuy:Keybind("enabled_kb", 0x70, "toggle")



    local teleports = tab:Section("Teleports", "Right")
    teleports:Button("Oil Rig 1", function()
        print("Teleporting to Oil 1...")
        teleportTo(locations["Oil Rig 1"])
    end)
    teleports:Button("Oil Rig 2", function()
        print("Teleporting to Oil 2...")
        teleportTo(locations["Oil Rig 2"])
    end)
    teleports:Button("Oil Warehouse", function()
        print("Teleporting to Oil 3...")
        teleportTo(locations["Oil Warehouse"])
    end)
    teleports:Button("Base", function()
        print("Teleporting to Base..." .. getTycoon().Name)
        teleportTo(locations["Base"])
    end)
    teleports:Button("Oil Deposit", function()
        print("Teleporting to Oil Deposit...")
        teleportTo(locations["Oil Deposit"])
    end)
    teleports:Button("Control Point", function()
        print("Teleporting to Control Point...")
        teleportTo(locations["Control Point"])
    
    end)
end)

spawn(function()
    while true do
        wait(0.1)
        if autoBuyRunning and not autoBuyActive then
            autoBuyActive = true
            print("Running auto-buy cycle...")
            autoBuyUpgrades()
            collectMoney()
            autoBuyActive = false
        end
    end
end)

spawn(function()
    while true do
        wait(0.1)
        for i,v in ipairs(playersService:GetPlayers()) do
            if v.AdminRank.Value ~= 0 then
                print("Admin detected: " .. v.Name)
                notify("turn off everything cuz there's an admin", "Admin detected!", 60)
                autoBuyRunning = false
                break
            end
        end
    end
end)

notify("welcome to my script by originalzex", "Executed", 5)
