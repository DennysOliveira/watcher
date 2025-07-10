local api = require("api")
local ui = require("watcher/ui")
local watcherHistoryUI = require("watcher/watcher_history_ui")
local helpers = require("watcher/helpers")

local watcher_addon = {
    name = "Watcher: Economy",
    author = "Winterflame",
    version = "1.0",
    desc = "Economy tracking, simplified."
}



local watcherWnd
local playerId = api.Unit:GetUnitId('player')
local playerInfo = api.Unit:GetUnitInfoById(playerId)

-- UI variables
local bagButton
local uiShowed = false
local WINDOW
local updateUI

-- Event association variables
local pendingLaborEvent = nil
local pendingMoneyEvent = nil
local associationTimer = nil
local ASSOCIATION_WINDOW_MS = 1000 -- 1 second window to associate events

-- Pagination variables
local currentPage = 1
local entriesPerPage = 18
local totalPages = 1

-- Session
local session = nil
local globalBaseSessionsDir = "watcher/data/sessions/"
local globalIndexFile = "watcher/data/session_index.txt"

-- UI
local watcherWindowControls = {}

-- Simplified data functions
local function getCharacterSessionFile(sessId)
    local playerSessionFilename = globalBaseSessionsDir .. playerInfo.name .. "_" .. sessId .. ".txt"
    return playerSessionFilename
end

local function addSessionToIndex(sessId, name, path)
    local indexFile = "watcher/session_index.txt"
    local index = api.File:Read(indexFile)
    if type(index) ~= "table" then index = {} end
    table.insert(index, { id = sessId, name = name, path = path })
    api.File:Write(indexFile, index)
end

local function createSession()
    local now = api.Time:GetLocalTime()
    local startMoney = X2Util.GetMyMoneyString()
    local newSess = {
        id = now,
        name = "Session",
        started = now,
        ended = nil,
        startMoney = startMoney,
        stamps = {}
    }
    -- Add to session index
    local sessionFile = getCharacterSessionFile(newSess.id)
    addSessionToIndex(newSess.id, newSess.name, sessionFile)
    return newSess
end

local function getSessionData()
    if session == nil then
        session = createSession()
        -- api.Log:Info("Created a new session. Session ID: " .. session.id)
        api.File:Write(getCharacterSessionFile(session.id), session)
        return session
    end

    return api.File:Read(getCharacterSessionFile(session.id))
end

local function getData()
    -- api.Log:Info("getData")
    local data = getSessionData()
    if data == nil then
        -- api.Log:Info("gotSessionData: nil")
        return {}
    end
    -- Print the full table if possible
    if type(data) == "table" then
        for k, v in pairs(data) do
            -- api.Log:Info("SessionData[" .. tostring(k) .. "] = " .. tostring(v))
        end
    else
        -- api.Log:Info("gotSessionData: " .. tostring(data))
    end
    
    return data
end

-- Calculate session labor and gold aggregates
local function calculateSessionLaborAndGold(sessionData)
    local usedLabor, earnedLabor, usedMoney, earnedMoney = 0, 0, 0, 0
    if not sessionData or not sessionData.stamps then return usedLabor, earnedLabor, usedMoney, earnedMoney end
    for _, stamp in ipairs(sessionData.stamps) do
        if stamp.labor and tonumber(stamp.labor.change) then
            local lc = tonumber(stamp.labor.change)
            if lc < 0 then usedLabor = usedLabor + math.abs(lc) end
            if lc > 0 then earnedLabor = earnedLabor + lc end
        end
        if stamp.gold and tonumber(stamp.gold.change) then
            local gc = tonumber(stamp.gold.change)
            if gc < 0 then usedMoney = usedMoney + math.abs(gc) end
            if gc > 0 then earnedMoney = earnedMoney + gc end
        end
    end
    return usedLabor, earnedLabor, usedMoney, earnedMoney
end

-- Update sessionData with aggregate values
local function updateSessionAggregates(sessionData)
    local usedLabor, earnedLabor, usedMoney, earnedMoney = calculateSessionLaborAndGold(sessionData)
    sessionData.usedLabor = usedLabor
    sessionData.earnedLabor = earnedLabor
    sessionData.usedMoney = usedMoney
    sessionData.earnedMoney = earnedMoney
end

local function saveData(data)
    -- api.Log:Info("Writing new data to file.")
    api.File:Write(getCharacterSessionFile(session.id), data)
end

local function saveStamp(laborChange, currentLabor, moneyChange, currentMoney)
    -- api.Log:Info("Money change received as param: ".. tostring(moneyChange))
    local data = getData()
    local timestamp = tostring(api.Time:GetLocalTime())

    -- Use last stamp's gold.current or session startMoney
    local lastMoney = data.startMoney or "0"
    local lastLabor = 0
    if data.stamps and #data.stamps > 0 then
        lastMoney = data.stamps[#data.stamps].gold.current
        lastLabor = data.stamps[#data.stamps].labor.current or 0
    end

    if moneyChange == nil then
        moneyChange = X2Util:StrNumericSub(currentMoney, lastMoney)
    end

    -- If currentLabor is nil or 0 (gold-only event), use last known labor value
    if (currentLabor == nil or currentLabor == 0) and lastLabor ~= 0 then
        currentLabor = lastLabor
    end

    local stamp = {
        timestamp = timestamp,
        gold = {
            current = currentMoney,
            change = moneyChange
        },
        labor = {
            change = laborChange or 0,
            current = currentLabor or 0
        }
    }

    table.insert(data.stamps, stamp)
    -- Log the new stamp and count
    -- api.Log:Info("Inserted new stamp: " .. tostring(stamp.timestamp) .. ", total stamps: " .. tostring(#data.stamps))
    if data.stamps[#data.stamps] then
        for k, v in pairs(data.stamps[#data.stamps]) do
            -- api.Log:Info("NewStamp[" .. tostring(k) .. "] = " .. tostring(v))
        end
    end
    -- Save the updated data
    saveData(data)
    -- Log after save
    local verifyData = getData()
    if verifyData.stamps and #verifyData.stamps > 0 then
        local last = verifyData.stamps[#verifyData.stamps]
        -- api.Log:Info("After save, last stamp: " .. tostring(last.timestamp))
        for k, v in pairs(last) do
            -- api.Log:Info("SavedStamp[" .. tostring(k) .. "] = " .. tostring(v))
        end
    else
        -- api.Log:Info("After save, no stamps found!")
    end
    -- Log to console for immediate feedback
    if laborChange and laborChange ~= 0 then
        local laborChangeType = laborChange > 0 and "earned" or "used"
        -- api.Log:Info(string.format("[Watcher] Labor %s: %d (Total: %d)", laborChangeType, math.abs(laborChange), currentLabor))
    end
    if moneyChange and moneyChange ~= "0" then
        local moneyChangeType = tonumber(moneyChange) > 0 and "earned" or "spent"
        -- api.Log:Info(string.format("[Watcher] Money %s: %s (Total: %s)", moneyChangeType, moneyChange, currentMoney))
    end
end


-- Event association functions
local function clearAssociationTimer()
    if associationTimer then
        associationTimer = nil
    end
end

local function processPendingEvents()
    local currentTime = api.Time:GetLocalTime()
    
    -- If we have both events, associate them
    if pendingLaborEvent and pendingMoneyEvent then
        local timeDiff = currentTime - pendingLaborEvent.timestamp
        if timeDiff <= ASSOCIATION_WINDOW_MS then
            -- Events happened within the association window, combine them
            saveStamp(
                pendingLaborEvent.laborChange, 
                pendingLaborEvent.currentLabor,
                nil, -- always let saveStamp calculate moneyChange
                pendingMoneyEvent.currentMoney
            )
        else
            -- Events happened too far apart, save them separately
            saveStamp(
                pendingLaborEvent.laborChange, 
                pendingLaborEvent.currentLabor,
                nil,
                pendingLaborEvent.currentMoney
            )
            saveStamp(
                nil, 
                0,
                nil,
                pendingMoneyEvent.currentMoney
            )
        end
    elseif pendingLaborEvent then
        -- Only labor event, save it
        saveStamp(
            pendingLaborEvent.laborChange, 
            pendingLaborEvent.currentLabor,
            nil,
            pendingLaborEvent.currentMoney
        )
    elseif pendingMoneyEvent then
        -- Only money event, save it
        saveStamp(
            nil, 
            0,
            nil,
            pendingMoneyEvent.currentMoney
        )
    end
    
    -- Clear pending events
    pendingLaborEvent = nil
    pendingMoneyEvent = nil
    clearAssociationTimer()
    
    -- Reset to first page when new data is added (to show most recent entries)
    currentPage = 1
    
    -- Update UI if it's currently shown (move this to the very end)
    if uiShowed then 
        -- Use a timer to ensure UI updates after all data is written
        api:DoIn(10, function() updateUI() end)
    end
end

local function startAssociationTimer()
    clearAssociationTimer()
    associationTimer = api:DoIn(ASSOCIATION_WINDOW_MS, function()
        processPendingEvents()
    end)
end

local function handleLaborEvent(laborChange, currentLabor)
    local currentTime = api.Time:GetLocalTime()
    local currentMoney = X2Util.GetMyMoneyString()
    
    pendingLaborEvent = {
        timestamp = currentTime,
        laborChange = laborChange,
        currentLabor = currentLabor,
        currentMoney = currentMoney
    }
    
    if pendingMoneyEvent then
        -- We already have a money event, process immediately
        processPendingEvents()
    else
        -- Start timer to wait for potential money event
        startAssociationTimer()
    end
end

local function handleMoneyEvent()
    local currentTime = api.Time:GetLocalTime()
    local currentMoney = X2Util.GetMyMoneyString()
    -- Do not pre-calculate moneyChange; let saveStamp handle it
    pendingMoneyEvent = {
        timestamp = currentTime,
        currentMoney = currentMoney
    }
    if pendingLaborEvent then
        -- We already have a labor event, process immediately
        processPendingEvents()
    else
        -- Start timer to wait for potential labor event
        startAssociationTimer()
    end
end

-- UI helper functions
local function createButton(id, parent, text, x, y, width, height, anchor)
    local button = api.Interface:CreateWidget('button', id, parent)
    button:AddAnchor(anchor or "TOPLEFT", x, y)
    button:SetText(text)
    local buttonSkin = {
        path = "ui/common/default.dds",
        fontColor = {
            normal = {
                0.407843,
                0.266667,
                0.0705882,
                1,
            },
            pushed = {
                0.407843,
                0.266667,
                0.0705882,
                1,
            },
            highlight = {
                0.603922,
                0.376471,
                0.0627451,
                1,
            },
            disabled = {
                0.360784,
                0.360784,
                0.360784,
                1,
            },
        },
        coords = {
            normal = {
                727,
                247,
                60,
                25,
            },
            disable = {
                788,
                273,
                60,
                25,
            },
            over = {
                727,
                273,
                60,
                25,
            },
            click = {
                788,
                247,
                60,
                25,
            },
        },
        fontInset = {
            top = 0,
            right = 11,
            left = 11,
            bottom = 0,
        },
        width or 80,
        height or 20,
        autoResize = true,
        drawableType = "ninePart",
        coordsKey = "btn",
    }
    api.Interface:ApplyButtonSkin(button, buttonSkin)
    button:Show(true)
    return button
end

local function createLabel(id, parent, text, x, y, fontSize, anchor)
    local label = api.Interface:CreateWidget('label', id, parent)
    label:AddAnchor(anchor or "TOPLEFT", x, y)
    label:SetExtent(255, 20)
    label:SetText(text)
    label.style:SetColor(FONT_COLOR.TITLE[1], FONT_COLOR.TITLE[2], FONT_COLOR.TITLE[3], 1)
    label.style:SetAlign(ALIGN.LEFT)
    label.style:SetFontSize(fontSize or 14)
    label:Show(true)
    return label
end


local function formatTimestamp(timestamp)
    if not timestamp then return "Unknown" end
    
    local timeTable = api.Time:TimeToDate(timestamp)
    if not timeTable then return "Invalid" end
    
    -- Format as HH:MM
    local hour = timeTable.hour or 0
    local minute = timeTable.minute or 0
    
    -- Ensure two-digit format
    local hourStr = hour < 10 and "0" .. tostring(hour) or tostring(hour)
    local minuteStr = minute < 10 and "0" .. tostring(minute) or tostring(minute)
    
    -- Check if it's today or yesterday for better context
    local currentTime = api.Time:GetLocalTime()
    local currentTimeTable = api.Time:TimeToDate(currentTime)
    
    if currentTimeTable then
        local dayDiff = (currentTimeTable.day or 0) - (timeTable.day or 0)
        local monthDiff = (currentTimeTable.month or 0) - (timeTable.month or 0)
        local yearDiff = (currentTimeTable.year or 0) - (timeTable.year or 0)
        
        if yearDiff == 0 and monthDiff == 0 then
            if dayDiff == 0 then
                -- Today
                return hourStr .. ":" .. minuteStr
            elseif dayDiff == 1 then
                -- Yesterday
                return "Yesterday " .. hourStr .. ":" .. minuteStr
            elseif dayDiff <= 7 then
                -- Within a week, show day name
                local dayNames = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
                local dayOfWeek = dayNames[((timeTable.day or 0) % 7) + 1] or "???"
                return dayOfWeek .. " " .. hourStr .. ":" .. minuteStr
            end
        end
    end
    
    -- Fallback: show date and time
    local day = timeTable.day or 0
    local month = timeTable.month or 0
    local dayStr = day < 10 and "0" .. tostring(day) or tostring(day)
    local monthStr = month < 10 and "0" .. tostring(month) or tostring(month)
    
    return dayStr .. "-" .. monthStr .. " " .. hourStr .. ":" .. minuteStr
end

local function drawHistoryLineBackground(parent, x, y, width, height, colorMode)
    local bg = parent:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    if colorMode == "positive" then
        bg:SetColor(ConvertColor(80), ConvertColor(210), ConvertColor(84), 0.25) -- greenish
    elseif colorMode == "negative" then
        bg:SetColor(ConvertColor(210), ConvertColor(94), ConvertColor(84), 0.35) -- reddish
    else
        bg:SetColor(ConvertColor(100), ConvertColor(100), ConvertColor(100), 0.15) -- default
    end
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", parent, x-2, y)
    bg:SetExtent(width+2, height+4)
    bg:Show(true)
    return bg
end

local function logTable(tbl, prefix)
    prefix = prefix or ""
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            -- api.Log:Info(prefix .. tostring(k) .. " = {")
            logTable(v, prefix .. "  ")
            -- api.Log:Info(prefix .. "}")
        else
            -- api.Log:Info(prefix .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

local function drawHistoryLine(baseId, parent, i, first, stamp, x, y)
    -- api.Log:Info("drawHistoryLine called for index " .. tostring(i) .. ", stamp:")
    if type(stamp) == "table" then
        logTable(stamp, "  ")
    else
        -- api.Log:Info("  (not a table): " .. tostring(stamp))
    end
    local controls = {}
    local winWidth = 570 -- assuming window width is 600, minus some padding
    local rowHeight = 20
    local goldChange = tonumber(stamp.gold.change) or 0
    local colorMode = goldChange > 0 and "positive" or (goldChange < 0 and "negative" or nil)
    -- Draw background for the line
    local bg = drawHistoryLineBackground(parent, x, y, winWidth, rowHeight, colorMode)
    table.insert(controls, bg)
    local col1X = x
    local col2X = x + math.floor(winWidth / 3) -30
    local col3X = x + 2 * math.floor(winWidth / 3)
    local laborChange = tonumber(stamp.labor.change) or 0
    local goldChangeAbs = math.abs(goldChange)
    local goldChangeStr = (goldChange > 0 and "+" or (goldChange < 0 and "-" or "")) .. helpers.formatGold(goldChangeAbs)
    local laborChangeStr = (laborChange > 0 and "+" or "") .. tostring(laborChange)
    local goldCurrentStr = helpers.formatGold(stamp.gold.current)
    -- Column 1: number and timestamp
    local formattedTime = formatTimestamp(stamp.timestamp)
    local col1Text = string.format("%d: %s", i, formattedTime)
    -- Column 2: gold and change
    local col2Text = string.format("Gold: %s (%s)", goldCurrentStr, goldChangeStr)
    -- Column 3: labor and change
    local col3Text = string.format("Labor: %s (%s)", tostring(stamp.labor.current), laborChangeStr)
    local labelId1 = baseId .. "_col1_" .. (i - first + 1)
    local labelId2 = baseId .. "_col2_" .. (i - first + 1)
    local labelId3 = baseId .. "_col3_" .. (i - first + 1)
    local label1 = createLabel(labelId1, parent, col1Text, col1X, y, 12, "TOPLEFT")
    local label2 = createLabel(labelId2, parent, col2Text, col2X, y, 12, "TOPLEFT")
    local label3 = createLabel(labelId3, parent, col3Text, col3X, y, 12, "TOPLEFT")
    table.insert(controls, label1)
    table.insert(controls, label2)
    table.insert(controls, label3)
    return controls
end

local function createHistoryLines(baseId, parent, data, x, y, page, entriesPerPage)
    local controls = {}
    local totalEntries = #data
    local totalPages = math.ceil(totalEntries / entriesPerPage)
    
    -- Ensure current page is valid
    if page < 1 then page = 1 end
    if page > totalPages then page = totalPages end
    if totalPages == 0 then page = 1 end
    
    -- Calculate start and end indices for current page
    local startIndex = (page - 1) * entriesPerPage + 1
    local endIndex = math.min(page * entriesPerPage, totalEntries)
    
    local paddingY = y
    if totalEntries == 0 then
        local emptyLabel = createLabel(baseId .. '_empty', parent, 'Waiting actions, no session data to display yet.', x+ 20, paddingY + 160, 12)
        table.insert(controls, emptyLabel)
        return controls, totalPages, page
    end
    for i = startIndex, endIndex do
        local stamp = data[i]
        if stamp and stamp.timestamp and stamp.gold and stamp.labor then
            local lineControls = drawHistoryLine(baseId, parent, i, startIndex, stamp, x, paddingY)
            for _, ctrl in ipairs(lineControls) do table.insert(controls, ctrl) end
            paddingY = paddingY + 20
        end
    end
    
    return controls, totalPages, page
end

-- Calculation functions for session start and end money
local function getSessionStartMoney(data)
    if data and data.stamps and #data.stamps > 0 then
        return tonumber(data.stamps[1].gold.current) or 0
    elseif data and data.startMoney then
        return tonumber(data.startMoney) or 0
    end
    return 0
end

local function getSessionEndMoney(data)
    if data and data.stamps and #data.stamps > 0 then
        return tonumber(data.stamps[#data.stamps].gold.current) or 0
    elseif data and data.startMoney then
        return tonumber(data.startMoney) or 0
    end
    return 0
end

local function closeAllOpenSessions()
    local indexFile = "watcher/session_index.txt"
    local index = api.File:Read(indexFile)
    if type(index) ~= "table" then return end

    for _, entry in ipairs(index) do
        local sessionData = api.File:Read(entry.path)
        if sessionData and not sessionData.ended then
            sessionData.ended = api.Time:GetLocalTime()
            api.File:Write(entry.path, sessionData)
        end
    end
end

local function updateUI()
    local data = getData()
    local characterName = playerInfo.name
    
    -- Update header labels for session start and end money
    if watcherWindowControls.startMoneyLabel then
        watcherWindowControls.startMoneyLabel:SetText('Session Start: ' .. helpers.formatGold(getSessionStartMoney(data)))
    end
    if watcherWindowControls.endMoneyLabel then
        watcherWindowControls.endMoneyLabel:SetText('Session End: ' .. helpers.formatGold(getSessionEndMoney(data)))
    end

    -- Update header labels
    if watcherWindowControls.currentMoneyLabel then
        watcherWindowControls.currentMoneyLabel:SetText("Money: " .. helpers.formatGold(X2Util.GetMyMoneyString()))
    end
    
    -- Hide old history labels
    if watcherWindowControls.historyLabels then
        for _, label in ipairs(watcherWindowControls.historyLabels) do
            label:Show(false)
        end
    end
    
    -- Draw new history labels with pagination
    local stamps = data and data.stamps or {}
    local historyControls, calculatedTotalPages, calculatedCurrentPage = createHistoryLines("historyLabel_", WINDOW, stamps, 15, 120, currentPage, entriesPerPage)
    watcherWindowControls.historyLabels = historyControls
    
    -- Update pagination info
    totalPages = calculatedTotalPages
    currentPage = calculatedCurrentPage
    
    -- Update pagination label if it exists
    if watcherWindowControls.paginationLabel then
        local paginationText = string.format("Page %d of %d", currentPage, totalPages)
        watcherWindowControls.paginationLabel:SetText(paginationText)
    end
    
    -- Update navigation button states
    if watcherWindowControls.prevButton then
        watcherWindowControls.prevButton:SetEnabled(currentPage > 1)
    end
    if watcherWindowControls.nextButton then
        watcherWindowControls.nextButton:SetEnabled(currentPage < totalPages)
    end
end

local function toggleUI(state)
    if state then
        WINDOW:Show(true)
        uiShowed = true
        updateUI()
    else
        WINDOW:Show(false)
        uiShowed = false
    end
end

-- Pagination navigation functions
local function goToPage(page)
    if page >= 1 and page <= totalPages then
        currentPage = page
        updateUI()
    end
end

local function goToPreviousPage()
    if currentPage > 1 then
        goToPage(currentPage - 1)
    end
end

local function goToNextPage()
    if currentPage < totalPages then
        goToPage(currentPage + 1)
    end
end

local function goToFirstPage()
    goToPage(1)
end

local function goToLastPage()
    goToPage(totalPages)
end

-- Calculate total used labor for a session
local function calculateUsedLabor(sessionData)
    if not sessionData or not sessionData.stamps then return 0 end
    local used = 0
    for _, stamp in ipairs(sessionData.stamps) do
        if stamp.labor and tonumber(stamp.labor.change) and tonumber(stamp.labor.change) < 0 then
            used = used + math.abs(tonumber(stamp.labor.change))
        end
    end
    return used
end


local function endCurrentSession()
    if session and not session.ended then
        -- Always read the latest file data
        local sessionFile = getCharacterSessionFile(session.id)
        local fileData = api.File:Read(sessionFile)
        
        updateSessionAggregates(fileData)

        if fileData and not fileData.ended then
            fileData.ended = api.Time:GetLocalTime()
            api.File:Write(sessionFile, fileData)
        end

        -- Also update in-memory session object
        session.ended = fileData and fileData.ended or api.Time:GetLocalTime()
    end
end


local function startNewSession()
    -- Create a new session and update the global session variable
    session = createSession()
    api.File:Write(getCharacterSessionFile(session.id), session)
    currentPage = 1
    -- Update UI to reflect the new session
    updateUI()
end

local function cleanupStaleSessions()
    local indexFile = "watcher/session_index.txt"
    local index = api.File:Read(indexFile)
    if type(index) ~= "table" then return end
    local newIndex = {}
    for _, entry in ipairs(index) do
        local sessionData = api.File:Read(entry.path)
        local isStale = false
        if sessionData then
            updateSessionAggregates(sessionData)
            local hasNoStamps = not sessionData.stamps or #sessionData.stamps == 0
            local allZero = (tonumber(sessionData.earnedLabor or 0) == 0)
                and (tonumber(sessionData.usedLabor or 0) == 0)
                and (tonumber(sessionData.earnedMoney or 0) == 0)
                and (tonumber(sessionData.usedMoney or 0) == 0)
            if hasNoStamps or allZero then
                isStale = true
            end
        else
            isStale = true
        end
        if not isStale then
            table.insert(newIndex, entry)
        end
    end
    api.File:Write(indexFile, newIndex)
end


local function createWindow()
    WINDOW = api.Interface:CreateWindow('watcherWindow', 'Watcher', 600, 600)
    WINDOW:AddAnchor("CENTER", "UIParent", 0, 0)
    WINDOW:SetHandler("OnCloseByEsc", function() toggleUI(false) end)
    function WINDOW:OnClose() toggleUI(false) end

    local paddingX = 15
    local paddingY = 30

    -- Session History button (top right corner)
    local sessionHistoryButton = ui.createButton('sessionHistoryButton', WINDOW, 'Session History', 450, 10, 120, 25)
    function sessionHistoryButton:OnClick()
        watcherHistoryUI.showSessionHistoryWindow(session)
    end
    sessionHistoryButton:SetHandler("OnClick", sessionHistoryButton.OnClick)
    watcherWindowControls.sessionHistoryButton = sessionHistoryButton

    -- Header section: Session Start and End Money
    local data = getData()
    local startMoney = getSessionStartMoney(data)
    local endMoney = getSessionEndMoney(data)
  

    paddingY = 50
    -- Current values
    local currentLabel = createLabel('currentLabel', WINDOW, 'Current Values:', paddingX, paddingY, 14)
    watcherWindowControls.currentLabel = currentLabel
    
    paddingY = 70
    local currentMoney = X2Util.GetMyMoneyString()
    local currentMoneyLabel = createLabel('moneyLabel', WINDOW, 'Money: ' .. helpers.formatGold(currentMoney), paddingX, paddingY, 12)
    watcherWindowControls.currentMoneyLabel = currentMoneyLabel

    local startMoneyLabel = createLabel('startMoneyLabel', WINDOW, 'Session Start: ' .. helpers.formatGold(startMoney), paddingX + 150, paddingY, 12)
    watcherWindowControls.startMoneyLabel = startMoneyLabel
    local endMoneyLabel = createLabel('endMoneyLabel', WINDOW, 'Session End: ' .. helpers.formatGold(endMoney), paddingX + 350, paddingY, 12)
    watcherWindowControls.endMoneyLabel = endMoneyLabel

    paddingY = 100
    local historyLabel = createLabel('historyLabel', WINDOW, 'Recent History:', paddingX, paddingY, 14)
    watcherWindowControls.historyLabel = historyLabel
    paddingY = 120

    local stamps = data and data.stamps or {}
    watcherWindowControls.historyLabels = createHistoryLines("historyLabel_", WINDOW, stamps, 15, 120, currentPage, entriesPerPage)

    -- Pagination controls
    paddingY = 480
    
    -- Pagination label
    local paginationLabel = createLabel('paginationLabel', WINDOW, 'Page 1 of 1', 250, paddingY, 12, "TOPLEFT")
    watcherWindowControls.paginationLabel = paginationLabel
    
    paddingY = 510
    
    -- Navigation buttons
    local firstButton = createButton('firstButton', WINDOW, '<<', paddingX, paddingY)
    function firstButton:OnClick() goToFirstPage() end
    firstButton:SetHandler("OnClick", firstButton.OnClick)
    watcherWindowControls.firstButton = firstButton
    
    local prevButton = createButton('prevButton', WINDOW, '<', paddingX + 50, paddingY)
    function prevButton:OnClick() goToPreviousPage() end
    prevButton:SetHandler("OnClick", prevButton.OnClick)
    watcherWindowControls.prevButton = prevButton
    
    local nextButton = createButton('nextButton', WINDOW, '>', paddingX + 100, paddingY)
    function nextButton:OnClick() goToNextPage() end
    nextButton:SetHandler("OnClick", nextButton.OnClick)
    watcherWindowControls.nextButton = nextButton
    
    local lastButton = createButton('lastButton', WINDOW, '>>', paddingX + 150, paddingY)
    function lastButton:OnClick() goToLastPage() end
    lastButton:SetHandler("OnClick", lastButton.OnClick)
    watcherWindowControls.lastButton = lastButton

    paddingY = 550

    -- Buttons
    local refreshButton = createButton('refreshButton', WINDOW, 'Refresh', paddingX, paddingY)
    function refreshButton:OnClick() updateUI() end
    refreshButton:SetHandler("OnClick", refreshButton.OnClick)

    local closeButton = createButton('closeButton', WINDOW, 'Close', paddingX + 100, paddingY)
    function closeButton:OnClick() toggleUI(false) end
    closeButton:SetHandler("OnClick", closeButton.OnClick)

    -- Place New Session button in the lower right corner
    local buttonWidth = 120
    local windowWidth = 600
    local buttonPadding = 20
    local newSessionButtonX = windowWidth - buttonWidth - buttonPadding
    local newSessionButtonY = paddingY
    local newSessionButton = createButton('newSessionButton', WINDOW, 'New Session', newSessionButtonX, newSessionButtonY, buttonWidth)
    function newSessionButton:OnClick()
        endCurrentSession()
        startNewSession()
    end
    newSessionButton:SetHandler("OnClick", newSessionButton.OnClick)
    watcherWindowControls.newSessionButton = newSessionButton
end

local function createMainButton()
    local bagMngr = ADDON:GetContent(UIC.BAG)
    bagButton = createButton('myBagButton', bagMngr, 'Open Watcher', -180, -67, 200, 20, "BOTTOMRIGHT")

    if bagButton == nil then
        api.Log:Info("[Watcher] Could not load bag manager button.")
    end

    function bagButton:OnClick() 
        toggleUI(not uiShowed)
    end
    bagButton:SetHandler("OnClick", bagButton.OnClick)
end


local function OnLoad()
    cleanupStaleSessions()
    watcherWnd = api.Interface:CreateEmptyWindow("watcherWnd", "UIParent")

    closeAllOpenSessions()
    
    -- Current existing events
    -- LABORPOWER_CHANGED
    -- BAG_UPDATE
    -- MAIL_INBOX_UPDATE
    -- MAIL_INBOX_ITEM_TAKEN
    -- MAIL_INBOX_MONEY_TAKEN
    -- INTERACTION_END
    -- PLAYER_MONEY

    -- Currently watched events:
    -- LABORPOWER_CHANGED -> update player labor history accordingly
    -- PLAYER_MONEY -> update player money history accordingly
    -- If the same happened at the same time, we will attach both together in a same history change (future implementation to enhance watcher_addon history)

    function watcherWnd:OnEvent(event, ...)
        if event == "LABORPOWER_CHANGED" then
            if arg ~= nil then 
                -- arg[1] = labor change (positive = earned, negative = used)
                -- arg[2] = current labor value
                local laborChange = arg[1]
                local currentLabor = arg[2]
                
                if laborChange and currentLabor then
                    handleLaborEvent(laborChange, currentLabor)
                end
            end 
            if uiShowed then updateUI() end
        end

        if event == "PLAYER_MONEY" then
            -- PLAYER_MONEY has no ARGS, we fetch current player money data
            handleMoneyEvent()
            if uiShowed then updateUI() end
        end
    end
    
    -- Register for LABORPOWER_CHANGED events
    watcherWnd:SetHandler("OnEvent", watcherWnd.OnEvent)
    watcherWnd:RegisterEvent("LABORPOWER_CHANGED")

    watcherWnd:RegisterEvent("PLAYER_MONEY")
    watcherWnd:Show(true)
    
    -- Create UI
    createMainButton()
    createWindow()
    
    -- api.Log:Info("[Watcher] Loaded")
end

local function OnUnload()
    -- End the current session if open
    endCurrentSession()
    -- Clear any pending events and timer
    clearAssociationTimer()
    pendingLaborEvent = nil
    pendingMoneyEvent = nil
    
    if watcherWnd ~= nil then
        watcherWnd:ReleaseHandler("LABORPOWER_CHANGED")
        watcherWnd:ReleaseHandler("OnEvent")
        watcherWnd:Show(false)
        watcherWnd = nil
    end
    
    if bagButton ~= nil then
        bagButton:Show(false)
        bagButton = nil
    end
    
    if WINDOW ~= nil then
        WINDOW:Show(false)
        WINDOW = nil
    end
    
    watcherHistoryUI:onUnload()
    -- api.Log:Info("[Watcher] Unloaded")
end

watcher_addon.OnLoad = OnLoad
watcher_addon.OnUnload = OnUnload

return watcher_addon 

