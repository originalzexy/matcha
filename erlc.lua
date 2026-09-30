--[[
    WANTED OVERLAY
    A draggable wanted board plus red star markers over wanted players.

    Both features share ONE collector and ONE render connection.
    Board  - red bar chart of the wanted list, hottest first, real display
             names resolved through the Roblox API and cached to disk.
    Stars  - see-through-walls red star over each wanted player who has a
             streamed body on this client.

    CONTROLS / API
      drag the board          press and hold anywhere on the panel
      Wanted.getWanted()      { user, uid, disp, level }, hottest first
      Wanted.debug()          display-name source breakdown
      Wanted.stats()          wanted / streamedOut / drawn / err
      Wanted.toggle()         hide or show the board
      Wanted.move(dx, dy)     nudge the board
      Wanted.selfTest()       star + row on yourself, to verify rendering
      Wanted.clearSelfTest()   release it
      Wanted.stop()           remove every overlay (ALWAYS run this)
]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local LocalPlayer  = Players.LocalPlayer
local sandbox      = getfenv and getfenv(1) or _G

-- ============================== CONFIG ==============================
local Config = {
    PollSeconds       = 2,
    Board = {
        MaxRows      = 16,
        BarWidth     = 240,
        RowHeight    = 30,
        Padding      = 10,
        HeaderHeight = 26,
        HotThreshold = 300,
        PositionFile = "wanted_board_pos.txt",
    },
    Names = {
        CacheFile     = "wanted_names.txt",
        ApiUrl        = "https://users.roblox.com/v1/usernames/users",
        Cooldown      = 4,
        RetryInterval = 12,
    },
    Stars = {
        MaxTargets   = 24,
        MaxDistance  = 900,
        MinSize      = 18,
        MaxSize      = 90,
        SizeConstant = 2000,
        MoveEpsilon  = 0.5,
    },
}

local Colour = {
    BarNormal     = Color3.fromRGB(220, 70, 70),
    BarHot        = Color3.fromRGB(255, 60, 60),
    StarBody      = Color3.fromRGB(235, 45, 45),
    StarLabel     = Color3.fromRGB(235, 45, 45),
    RowBackdrop   = Color3.fromRGB(20, 22, 28),
    PanelFill     = Color3.fromRGB(10, 11, 15),
    PrimaryText   = Color3.fromRGB(240, 240, 245),
    SecondaryText = Color3.fromRGB(150, 155, 165),
    FaintText     = Color3.fromRGB(110, 115, 125),
    TitleText     = Color3.fromRGB(255, 90, 90),
}

-- ============================== STATE ==============================
local isRunning         = true
local isBoardVisible    = true
local isDragging        = false
local dragOffsetX       = 0
local dragOffsetY       = 0
local boardPositionX    = 20
local boardPositionY    = 110
local positionNeedsSave = false
local lastPositionSave  = 0

local wantedRoster      = {}
local selfTestRoster    = nil
local totalPlayerCount  = 0
local wantedCount       = 0
local streamedOutCount  = 0
local drawnStarCount    = 0
local renderError       = nil

local displayNameByUserId = {}
local lastNameAttemptAt  = {}
local nameCacheDirty     = false
local lastApiCallAt      = 0
local lastNameSaveAt     = 0

local boardVersion     = 0
local lastDrawnVersion = -1

local visibleRowCount = 0
local highestLevel    = 1
local boardWidth      = 0
local boardHeight     = 0
local boardRows       = {}
for rowIndex = 1, Config.Board.MaxRows do
    boardRows[rowIndex] = {
        displayName = "", subtitle = "", offsetY = 0, barWidth = 0, isHot = false,
    }
end

local nameSourceCounts = {
    fromApi = 0, fromMdt = 0, fromUsername = 0, pendingRequests = 0,
}

-- ====================== DISPLAY NAME RESOLUTION ======================
-- Matcha has no JSONEncode/JSONDecode and Player.DisplayName is unreadable, so
-- the request body is hand-built and the response is parsed with patterns.
local function fetchDisplayNames(usernames)
    if #usernames == 0 then return end
    local now = os.clock()
    if now - lastApiCallAt < Config.Names.Cooldown then return end
    lastApiCallAt = now

    for startIndex = 1, #usernames, 100 do
        local batch = {}
        for offset = startIndex, math.min(startIndex + 99, #usernames) do
            batch[#batch + 1] = usernames[offset]
        end
        local quoted = {}
        for index, username in ipairs(batch) do quoted[index] = '"' .. username .. '"' end

        local requestBody = '{"usernames":[' .. table.concat(quoted, ",")
            .. '],"excludeBannedUsers":false}'
        local succeeded, response = pcall(function()
            return httppost(Config.Names.ApiUrl, requestBody, "application/json")
        end)

        if succeeded and type(response) == "string" and #response > 0 then
            for object in response:gmatch("{(.-)}") do
                local name    = object:match('"name":"([^"]*)"')
                local display = object:match('"displayName":"([^"]*)"')
                local userId  = object:match('"id":(%d+)')
                if name and display and userId and display ~= "" then
                    displayNameByUserId[userId] = display
                    nameCacheDirty = true
                end
            end
        end
    end

    if nameCacheDirty and os.clock() - lastNameSaveAt > 10 then
        local lines = {}
        for userId, display in pairs(displayNameByUserId) do
            lines[#lines + 1] = userId .. "=" .. display
        end
        pcall(writefile, Config.Names.CacheFile, table.concat(lines, "\n"))
        lastNameSaveAt = os.clock()
        nameCacheDirty = false
    end
end

-- Fallback only. The MDT list is transient UI that the game frequently clears,
-- so it can never be the primary source.
local function scrapeMdtDisplayNames()
    local names = {}
    local node = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local path = { "GameMenus", "MDT", "ScreensHolder", "Screens", "Dashboard", "Wanted", "List" }
    for _, step in ipairs(path) do
        if not node then return names end
        local found, child = pcall(function() return node:FindFirstChild(step) end)
        node = found and child or nil
    end
    if not node then return names end
    local gotList, children = pcall(function() return node:GetChildren() end)
    if not gotList then return names end

    for _, entry in ipairs(children) do
        local labels = {}
        local function harvest(instance, depth)
            if depth > 5 or #labels >= 5 then return end
            local gotKids, kids = pcall(function() return instance:GetChildren() end)
            if not gotKids then return end
            for _, kid in ipairs(kids) do
                if kid.ClassName == "TextLabel" or kid.ClassName == "TextButton" then
                    local gotText, text = pcall(function() return kid.Text end)
                    if gotText and type(text) == "string" and text ~= "" then
                        labels[#labels + 1] = text
                    end
                end
                harvest(kid, depth + 1)
            end
        end
        harvest(entry, 0)
        for _, label in ipairs(labels) do
            if label ~= entry.Name and label ~= "WANTED" and label ~= "Wanted" then
                names[entry.Name] = label
                break
            end
        end
    end
    return names
end

-- ============================== PERSISTENCE ==============================
local function loadFiles()
    local gotPosition, positionData = pcall(readfile, Config.Board.PositionFile)
    if gotPosition and type(positionData) == "string" then
        local x, y = positionData:match("^(%-?%d+),(%-?%d+)$")
        if x then boardPositionX, boardPositionY = tonumber(x), tonumber(y) end
    end

    local gotNames, nameData = pcall(readfile, Config.Names.CacheFile)
    if gotNames and type(nameData) == "string" then
        for line in nameData:gmatch("[^\r\n]+") do
            local userId, display = line:match("^(%-?%d+)=(.+)$")
            if userId and display then displayNameByUserId[userId] = display end
        end
    end
end

local function savePosition()
    pcall(writefile, Config.Board.PositionFile,
        string.format("%d,%d", math.floor(boardPositionX), math.floor(boardPositionY)))
end

local function saveNameCache()
    local lines = {}
    for userId, display in pairs(displayNameByUserId) do
        lines[#lines + 1] = userId .. "=" .. display
    end
    pcall(writefile, Config.Names.CacheFile, table.concat(lines, "\n"))
end

local function clampBoardToViewport()
    local camera = workspace.CurrentCamera
    local viewportSize = camera and camera.ViewportSize
    local screenWidth, screenHeight = 1920, 1080
    if viewportSize then
        local gotWidth, width = pcall(function() return viewportSize.X end)
        local gotHeight, height = pcall(function() return viewportSize.Y end)
        if gotWidth and type(width) == "number" then screenWidth = width end
        if gotHeight and type(height) == "number" then screenHeight = height end
    end
    boardPositionX = math.max(0, math.min(boardPositionX, screenWidth - boardWidth))
    boardPositionY = math.max(0, math.min(boardPositionY, screenHeight - boardHeight))
end

-- ============================== MOUSE INPUT ==============================
-- getmouseposition and GetMouseLocation are absent in Matcha.
-- LocalPlayer:GetMouse() is the working source; the resolver prefers the
-- standard bindings if they are ever injected.
local mouseReference
do
    local gotMouse, mouse = pcall(function() return LocalPlayer:GetMouse() end)
    if gotMouse then mouseReference = mouse end
end

local function extractScreenPoint(value)
    if value == nil then return nil end
    local gotX, x = pcall(function() return value.X end)
    local gotY, y = pcall(function() return value.Y end)
    -- Vector2 is userdata in Matcha, so read fields, never type-check
    if gotX and gotY and type(x) == "number" and type(y) == "number" then return x, y end
    return nil
end

local function getMouseScreenPosition()
    if type(sandbox.getmouseposition) == "function" then
        local ok, value = pcall(sandbox.getmouseposition)
        if ok then
            local x, y = extractScreenPoint(value)
            if x then return x, y end
        end
    end
    if mouseReference ~= nil then
        local x, y = extractScreenPoint(mouseReference)
        if x then return x, y end
        local ok, fresh = pcall(function() return LocalPlayer:GetMouse() end)
        if ok and fresh then
            mouseReference = fresh
            return extractScreenPoint(fresh)
        end
    end
    return nil
end

local function isLeftMouseDown()
    if type(sandbox.ismouse1pressed) == "function" then
        local ok, pressed = pcall(sandbox.ismouse1pressed)
        if ok and pressed ~= nil then return pressed and true or false end
    end
    return false
end

-- ============================== STAR GEOMETRY ==============================
-- Drawing has no polygon primitive, so a 5-point star is fanned from 10
-- triangles over pre-computed unit vertices (outer R=1, inner 0.382R, tip up).
local STAR_POINT_COUNT = 10
local starVertexX, starVertexY = {}, {}
for index = 0, STAR_POINT_COUNT - 1 do
    local angleRadians = math.rad(-90 + index * 36)
    local radius = (index % 2 == 0) and 1 or 0.382
    starVertexX[index + 1] = math.cos(angleRadians) * radius
    starVertexY[index + 1] = math.sin(angleRadians) * radius
end

-- ============================== DRAWING POOLS ==============================
-- Fixed pools, created once. Drawing objects are never garbage collected.
local boardPool = {}
for index = 1, Config.Board.MaxRows do
    local slot = {
        backdrop = Drawing.new("Square"),
        bar      = Drawing.new("Square"),
        name     = Drawing.new("Text"),
        meta     = Drawing.new("Text"),
    }
    slot.backdrop.Filled = true
    slot.backdrop.Color = Colour.RowBackdrop
    slot.backdrop.Transparency = 0.35
    slot.bar.Filled = true
    slot.name.Size, slot.name.Font, slot.name.Outline = 14, 2, true
    slot.name.Color = Colour.PrimaryText
    slot.meta.Size, slot.meta.Font, slot.meta.Outline = 11, 1, true
    slot.meta.Color = Colour.SecondaryText
    slot.backdrop.Visible, slot.bar.Visible = false, false
    slot.name.Visible, slot.meta.Visible = false, false
    boardPool[index] = slot
end

local boardPanel = Drawing.new("Square")
boardPanel.Filled, boardPanel.Color = true, Colour.PanelFill
boardPanel.Transparency, boardPanel.Visible = 0.15, false

local boardTitle = Drawing.new("Text")
boardTitle.Text, boardTitle.Size, boardTitle.Font, boardTitle.Outline = "WANTED", 16, 2, true
boardTitle.Color, boardTitle.Visible = Colour.TitleText, false

local boardCountLabel = Drawing.new("Text")
boardCountLabel.Size, boardCountLabel.Font, boardCountLabel.Outline = 12, 1, true
boardCountLabel.Color, boardCountLabel.Visible = Colour.SecondaryText, false

local boardEmptyLabel = Drawing.new("Text")
boardEmptyLabel.Text, boardEmptyLabel.Size, boardEmptyLabel.Font = "no active wanted", 12, 1
boardEmptyLabel.Color, boardEmptyLabel.Visible = Colour.SecondaryText, false

local boardHintLabel = Drawing.new("Text")
boardHintLabel.Text, boardHintLabel.Size, boardHintLabel.Font = "drag to move", 10, 1
boardHintLabel.Outline, boardHintLabel.Color = true, Colour.FaintText
boardHintLabel.Visible = false

local starPool = {}
for index = 1, Config.Stars.MaxTargets do
    local slot = {
        triangles = {}, stem = Drawing.new("Line"),
        tag = Drawing.new("Text"), banner = Drawing.new("Text"),
    }
    for pointIndex = 1, STAR_POINT_COUNT do
        local triangle = Drawing.new("Triangle")
        triangle.Filled, triangle.Color = true, Colour.StarBody
        triangle.Transparency, triangle.Visible, triangle.ZIndex = 0, false, 5
        slot.triangles[pointIndex] = triangle
    end
    slot.stem.Thickness, slot.stem.Color, slot.stem.Transparency = 1, Colour.StarBody, 0.3
    slot.stem.Visible, slot.stem.ZIndex = false, 4
    slot.tag.Size, slot.tag.Font, slot.tag.Center, slot.tag.Outline = 12, 1, true, true
    slot.tag.Color, slot.tag.Visible, slot.tag.ZIndex = Colour.PrimaryText, false, 6
    -- banner text is static, so it is never rewritten, only repositioned
    slot.banner.Text, slot.banner.Size, slot.banner.Font = "WANTED", 13, 2
    slot.banner.Center, slot.banner.Outline, slot.banner.Color = true, true, Colour.StarLabel
    slot.banner.Visible, slot.banner.ZIndex = false, 6
    -- per-slot draw cache, so an unchanged target costs zero property writes
    slot.wasVisible = false
    slot.drawnUserIdKey = nil
    slot.drawnCentreX, slot.drawnCentreY, slot.drawnRadius = 0, 0, 0
    starPool[index] = slot
end

-- ============================== COLLECTOR ==============================
-- One pass feeds both features. Every instance lookup in the overlay happens
-- here, never inside the render loop.
local function collect()
    if selfTestRoster then
        wantedRoster = selfTestRoster
        wantedCount, streamedOutCount = #selfTestRoster, 0
    else
        local players = Players:GetPlayers()
        totalPlayerCount = #players

        -- pre-warm names for EVERY player, so nobody becomes wanted and then
        -- sits on a fallback. Keyed by UserId so renames do not invalidate.
        local namesToFetch, now = {}, os.clock()
        for _, player in ipairs(players) do
            local userIdKey = tostring(player.UserId)
            if displayNameByUserId[userIdKey] == nil
               and now - (lastNameAttemptAt[userIdKey] or -999) > Config.Names.RetryInterval then
                namesToFetch[#namesToFetch + 1] = player.Name
                lastNameAttemptAt[userIdKey] = now
            end
        end
        nameSourceCounts.pendingRequests = #namesToFetch
        fetchDisplayNames(namesToFetch)

        wantedRoster = {}
        wantedCount, streamedOutCount = 0, 0
        for _, player in ipairs(players) do
            local wantedValue = player:FindFirstChild("Is_Wanted")
            if wantedValue then
                wantedCount = wantedCount + 1
                local character = player.Character
                -- HumanoidRootPart's ClassName is "Part", not "BasePart", so this
                -- must be a name lookup. A nil root means the body is not streamed.
                local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                local gotLevel, rawLevel = pcall(function() return wantedValue.Value end)
                local level = (gotLevel and tonumber(rawLevel)) or 0
                if level > 0 then
                    wantedRoster[#wantedRoster + 1] = {
                        player    = player,
                        userIdKey = tostring(player.UserId),
                        level     = level,
                        rootPart  = rootPart,
                        headPart  = rootPart and character:FindFirstChild("Head") or nil,
                    }
                end
                if not rootPart then streamedOutCount = streamedOutCount + 1 end
            end
        end
    end

    table.sort(wantedRoster, function(a, b) return a.level > b.level end)

    highestLevel = (wantedRoster[1] and wantedRoster[1].level) or 1
    if highestLevel <= 0 then highestLevel = 1 end
    visibleRowCount = #wantedRoster > Config.Board.MaxRows
        and Config.Board.MaxRows or #wantedRoster

    local mdtNames
    nameSourceCounts.fromApi, nameSourceCounts.fromMdt, nameSourceCounts.fromUsername = 0, 0, 0
    for rowIndex = 1, visibleRowCount do
        local entry = wantedRoster[rowIndex]
        local row = boardRows[rowIndex]
        local display = displayNameByUserId[entry.userIdKey]
        if display then
            nameSourceCounts.fromApi = nameSourceCounts.fromApi + 1
        else
            if not mdtNames then mdtNames = scrapeMdtDisplayNames() end
            display = mdtNames[entry.player.Name]
            if display then
                nameSourceCounts.fromMdt = nameSourceCounts.fromMdt + 1
            else
                display = entry.player.Name
                nameSourceCounts.fromUsername = nameSourceCounts.fromUsername + 1
            end
        end
        row.displayName = display
        row.subtitle = "@" .. entry.player.Name .. "  ·  " .. entry.level
        row.isHot = entry.level >= Config.Board.HotThreshold
        local fraction = entry.level / highestLevel
        if fraction < 0.06 then fraction = 0.06 elseif fraction > 1 then fraction = 1 end
        row.barWidth = Config.Board.BarWidth * fraction
        row.offsetY = Config.Board.Padding + Config.Board.HeaderHeight
            + (rowIndex - 1) * Config.Board.RowHeight
    end

    boardWidth = Config.Board.BarWidth + Config.Board.Padding * 2
    boardHeight = Config.Board.Padding * 2 + Config.Board.HeaderHeight
        + (visibleRowCount > 0 and visibleRowCount or 1) * Config.Board.RowHeight
    clampBoardToViewport()
    boardVersion = boardVersion + 1
end

loadFiles()
collect()
task.spawn(function()
    while isRunning do
        pcall(collect)
        task.wait(Config.PollSeconds)
    end
end)

-- ============================== BOARD RENDER ==============================
local function drawBoard()
    local padding, rowHeight = Config.Board.Padding, Config.Board.RowHeight
    local barWidth = Config.Board.BarWidth

    boardPanel.Visible = true
    boardPanel.Position = Vector2.new(boardPositionX, boardPositionY)
    boardPanel.Size = Vector2.new(boardWidth, boardHeight)

    boardTitle.Visible = true
    boardTitle.Position = Vector2.new(boardPositionX + padding, boardPositionY + padding)

    local hiddenCount = #wantedRoster - visibleRowCount
    boardCountLabel.Text = visibleRowCount .. " active / " .. totalPlayerCount .. " players"
        .. (hiddenCount > 0 and ("  +" .. hiddenCount) or "")
    boardCountLabel.Position = Vector2.new(boardPositionX + padding + 64,
        boardPositionY + padding + 3)
    boardCountLabel.Visible = true

    boardEmptyLabel.Visible = visibleRowCount == 0
    boardEmptyLabel.Position = Vector2.new(boardPositionX + padding + 4,
        boardPositionY + padding + Config.Board.HeaderHeight + 6)

    boardHintLabel.Visible = true
    boardHintLabel.Position = Vector2.new(boardPositionX + padding,
        boardPositionY + boardHeight - padding - 10)

    for rowIndex = 1, Config.Board.MaxRows do
        local slot, row = boardPool[rowIndex], boardRows[rowIndex]
        if rowIndex <= visibleRowCount then
            local screenY = boardPositionY + row.offsetY
            slot.backdrop.Position = Vector2.new(boardPositionX + padding, screenY)
            slot.backdrop.Size = Vector2.new(barWidth, rowHeight - 5)
            slot.backdrop.Visible = true

            slot.bar.Position = Vector2.new(boardPositionX + padding, screenY)
            slot.bar.Size = Vector2.new(row.barWidth, rowHeight - 5)
            slot.bar.Color = row.isHot and Colour.BarHot or Colour.BarNormal
            slot.bar.Visible = true

            slot.name.Text = row.displayName
            slot.name.Position = Vector2.new(boardPositionX + padding + 7, screenY + 1)
            slot.name.Visible = true

            slot.meta.Text = row.subtitle
            slot.meta.Position = Vector2.new(boardPositionX + padding + 7, screenY + 16)
            slot.meta.Visible = true
        else
            slot.backdrop.Visible, slot.bar.Visible = false, false
            slot.name.Visible, slot.meta.Visible = false, false
        end
    end
end

local function hideBoard()
    boardPanel.Visible, boardTitle.Visible = false, false
    boardCountLabel.Visible = false
    boardEmptyLabel.Visible = false
    boardHintLabel.Visible = false
    for rowIndex = 1, Config.Board.MaxRows do
        local slot = boardPool[rowIndex]
        slot.backdrop.Visible, slot.bar.Visible = false, false
        slot.name.Visible, slot.meta.Visible = false, false
    end
end

-- ============================== STAR RENDER ==============================
local currentCamera
local viewportWidth, viewportHeight = 1920, 1080

local function hideAllStars()
    for index = 1, Config.Stars.MaxTargets do
        local slot = starPool[index]
        if slot.wasVisible then
            for pointIndex = 1, STAR_POINT_COUNT do
                slot.triangles[pointIndex].Visible = false
            end
            slot.stem.Visible, slot.tag.Visible, slot.banner.Visible = false, false, false
            slot.wasVisible = false
        end
    end
    drawnStarCount = 0
end

local function drawStars()
    local camera = workspace.CurrentCamera
    if camera then
        currentCamera = camera
        local gotSize, size = pcall(function() return camera.ViewportSize end)
        if gotSize and size then
            local gotWidth, width = pcall(function() return size.X end)
            local gotHeight, height = pcall(function() return size.Y end)
            if gotWidth and type(width) == "number" then viewportWidth = width end
            if gotHeight and type(height) == "number" then viewportHeight = height end
        end
    end

    if #wantedRoster == 0 or currentCamera == nil then
        hideAllStars()
        return
    end

    local cameraPosition = currentCamera.Position
    if cameraPosition == nil then return end
    local cameraX, cameraY, cameraZ = cameraPosition.X, cameraPosition.Y, cameraPosition.Z
    local minX, maxX = -300, viewportWidth + 300
    local minY, maxY = -300, viewportHeight + 300
    local maxDistanceSquared = Config.Stars.MaxDistance * Config.Stars.MaxDistance
    local limit = #wantedRoster > Config.Stars.MaxTargets
        and Config.Stars.MaxTargets or #wantedRoster
    local drawn = 0

    for index = 1, limit do
        local entry = wantedRoster[index]
        local rootPart = entry.rootPart
        if rootPart ~= nil then
            local rootPosition = rootPart.Position
            if rootPosition ~= nil then
                local anchorX = rootPosition.X
                local anchorY = rootPosition.Y + 1.6
                local anchorZ = rootPosition.Z
                local headPart = entry.headPart
                if headPart ~= nil then
                    local headPosition = headPart.Position
                    if headPosition ~= nil then
                        anchorX, anchorY, anchorZ =
                            headPosition.X, headPosition.Y, headPosition.Z
                    end
                end

                local offsetX = anchorX - cameraX
                local offsetY = anchorY - cameraY
                local offsetZ = anchorZ - cameraZ
                -- squared compare first: avoids sqrt for the culled majority
                local distanceSquared =
                    offsetX * offsetX + offsetY * offsetY + offsetZ * offsetZ

                if distanceSquared <= maxDistanceSquared then
                    local projected, isOnScreen = WorldToScreen(
                        Vector3.new(anchorX, anchorY + 0.7, anchorZ))
                    if isOnScreen and projected
                       and projected.X > minX and projected.X < maxX
                       and projected.Y > minY and projected.Y < maxY then
                        local distance = math.sqrt(distanceSquared)
                        local starSize =
                            Config.Stars.SizeConstant / (distance > 1 and distance or 1)
                        if starSize < Config.Stars.MinSize then
                            starSize = Config.Stars.MinSize
                        elseif starSize > Config.Stars.MaxSize then
                            starSize = Config.Stars.MaxSize
                        end
                        local centreX = projected.X
                        local centreY = projected.Y - 26 - starSize * 0.5

                        drawn = drawn + 1
                        local slot = starPool[drawn]
                        -- the key includes UserId because slots are positional:
                        -- a reorder can hand this slot a DIFFERENT target
                        local unchanged = slot.wasVisible
                            and slot.drawnUserIdKey == entry.userIdKey
                            and math.abs(centreX - slot.drawnCentreX) < Config.Stars.MoveEpsilon
                            and math.abs(centreY - slot.drawnCentreY) < Config.Stars.MoveEpsilon
                            and starSize == slot.drawnRadius

                        if not unchanged then
                            local nextIndex = 1
                            for pointIndex = 1, STAR_POINT_COUNT do
                                local triangle = slot.triangles[pointIndex]
                                triangle.PointA = Vector2.new(centreX, centreY)
                                triangle.PointB = Vector2.new(
                                    centreX + starVertexX[pointIndex] * starSize,
                                    centreY + starVertexY[pointIndex] * starSize)
                                triangle.PointC = Vector2.new(
                                    centreX + starVertexX[nextIndex] * starSize,
                                    centreY + starVertexY[nextIndex] * starSize)
                                triangle.Visible = true
                                nextIndex = pointIndex + 1
                                if nextIndex > STAR_POINT_COUNT then nextIndex = 1 end
                            end

                            slot.stem.From = Vector2.new(centreX, centreY + starSize)
                            slot.stem.To = Vector2.new(projected.X, projected.Y + 2)
                            slot.stem.Visible = true

                            slot.banner.Position = Vector2.new(centreX, centreY - starSize - 9)
                            slot.banner.Visible = true

                            slot.tag.Text = entry.player.Name .. "  " .. entry.level
                                .. "  " .. math.floor(distance) .. "m"
                            slot.tag.Position = Vector2.new(centreX, centreY + starSize + 4)
                            slot.tag.Visible = true

                            slot.wasVisible = true
                            slot.drawnUserIdKey = entry.userIdKey
                            slot.drawnCentreX, slot.drawnCentreY = centreX, centreY
                            slot.drawnRadius = starSize
                        end
                    end
                end
            end
        end
    end

    for index = drawn + 1, Config.Stars.MaxTargets do
        local slot = starPool[index]
        if slot.wasVisible then
            for pointIndex = 1, STAR_POINT_COUNT do
                slot.triangles[pointIndex].Visible = false
            end
            slot.stem.Visible, slot.tag.Visible, slot.banner.Visible = false, false, false
            slot.wasVisible = false
        end
    end
    drawnStarCount = drawn
end

-- ============================== DRAG ==============================
local heartbeatConnection
heartbeatConnection = RunService.Heartbeat:Connect(function()
    if not isRunning or not isBoardVisible then return end
    local mouseX, mouseY = getMouseScreenPosition()
    if not mouseX then return end
    local mouseDown = isLeftMouseDown()

    if mouseDown and not isDragging then
        local insideX = mouseX >= boardPositionX and mouseX <= boardPositionX + boardWidth
        local insideY = mouseY >= boardPositionY and mouseY <= boardPositionY + boardHeight
        if insideX and insideY then
            isDragging = true
            dragOffsetX = mouseX - boardPositionX
            dragOffsetY = mouseY - boardPositionY
        end
    elseif (not mouseDown) and isDragging then
        isDragging = false
        savePosition()
        positionNeedsSave = false
    end

    if isDragging then
        boardPositionX = mouseX - dragOffsetX
        boardPositionY = mouseY - dragOffsetY
        clampBoardToViewport()
        boardVersion = boardVersion + 1
        positionNeedsSave = true
        local now = os.clock()
        if now - lastPositionSave > 2 then
            savePosition(); lastPositionSave = now; positionNeedsSave = false
        end
    end
end)

-- ============================== SINGLE RENDER LOOP ==============================
-- The board is gated on a version counter, so an unchanged frame writes nothing.
-- Stars run every frame because targets move, but each slot early-outs.
local renderConnection
renderConnection = RunService.RenderStepped:Connect(function()
    if not isRunning then return end
    local succeeded, failure = pcall(function()
        if isBoardVisible and boardVersion ~= lastDrawnVersion then
            lastDrawnVersion = boardVersion
            drawBoard()
        elseif not isBoardVisible and lastDrawnVersion ~= -2 then
            lastDrawnVersion = -2
            hideBoard()
        end
        drawStars()
    end)
    if not succeeded then
        renderError = tostring(failure)
        drawnStarCount = 0
    end
end)

-- ============================== PUBLIC API ==============================
Wanted = {}

function Wanted.getWanted()
    local result = {}
    for rowIndex = 1, visibleRowCount do
        local entry = wantedRoster[rowIndex]
        result[#result + 1] = {
            user  = entry.player.Name,
            uid   = entry.player.UserId,
            disp  = boardRows[rowIndex].displayName,
            level = entry.level,
        }
    end
    return result
end

function Wanted.debug()
    return {
        active          = visibleRowCount,
        total           = totalPlayerCount,
        fromApi         = nameSourceCounts.fromApi,
        fromMdt         = nameSourceCounts.fromMdt,
        fromUsername    = nameSourceCounts.fromUsername,
        pendingRequests = nameSourceCounts.pendingRequests,
    }
end

function Wanted.stats()
    return {
        wanted      = wantedCount,
        streamedOut = streamedOutCount,
        drawn       = drawnStarCount,
        err         = renderError,
    }
end

-- Re-applies itself on every poll, so the collector cannot wipe it.
function Wanted.selfTest()
    local character = LocalPlayer.Character
    if not character then return "no character" end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return "no HumanoidRootPart" end
    selfTestRoster = { {
        player    = LocalPlayer,
        userIdKey = tostring(LocalPlayer.UserId),
        level     = 0,
        rootPart  = rootPart,
        headPart  = character:FindFirstChild("Head"),
    } }
    collect()
    boardRows[1].displayName = LocalPlayer.Name .. " [SELFTEST]"
    boardRows[1].subtitle = "@" .. LocalPlayer.Name
    boardVersion = boardVersion + 1
    return "self test armed"
end

function Wanted.clearSelfTest()
    selfTestRoster = nil
    collect()
    return "self test cleared"
end

function Wanted.toggle()
    isBoardVisible = not isBoardVisible
    boardVersion = boardVersion + 1
end

function Wanted.move(deltaX, deltaY)
    boardPositionX = boardPositionX + (deltaX or 0)
    boardPositionY = boardPositionY + (deltaY or 0)
    clampBoardToViewport()
    boardVersion = boardVersion + 1
end

function Wanted.stop()
    isRunning = false
    if positionNeedsSave then savePosition() end
    if nameCacheDirty then saveNameCache() end
    if renderConnection then renderConnection:Disconnect() end
    if heartbeatConnection then heartbeatConnection:Disconnect() end

    for index = 1, Config.Board.MaxRows do
        local slot = boardPool[index]
        slot.backdrop:Remove(); slot.bar:Remove()
        slot.name:Remove(); slot.meta:Remove()
    end
    boardPanel:Remove(); boardTitle:Remove()
    boardCountLabel:Remove(); boardEmptyLabel:Remove(); boardHintLabel:Remove()

    for index = 1, Config.Stars.MaxTargets do
        local slot = starPool[index]
        for pointIndex = 1, STAR_POINT_COUNT do
            slot.triangles[pointIndex]:Remove()
        end
        slot.stem:Remove(); slot.tag:Remove(); slot.banner:Remove()
    end
    print("Wanted.stop() ran -- board and stars removed")
end
