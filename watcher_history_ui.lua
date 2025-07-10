local api = require("api")
local ui = require("watcher/ui")
local helpers = require("watcher/helpers")
local WINDOW = nil

local paginationLabel = nil

-- Scaffold: Read all session files and build session summaries
local function loadAllSessionSummaries()
    api.Log:Info("[SessionHistory] loadAllSessionSummaries: start (using session_index.txt)")
    local summaries = {}
    local indexFile = "watcher/data/session_index.txt"
    local index = api.File:Read(indexFile)
    if not index or type(index) ~= "table" then
        api.Log:Info("[SessionHistory] No session index found or not a table.")
        return summaries
    end
    api.Log:Info("[SessionHistory] Found " .. tostring(#index) .. " session index entries.")
    for _, entry in ipairs(index) do
        api.Log:Info("[SessionHistory] Loading session file: " .. tostring(entry.path))
        local sessionData = api.File:Read(entry.path)
        if sessionData then
            local first = sessionData.stamps and sessionData.stamps[1] or nil
            local last = sessionData.stamps and sessionData.stamps[#sessionData.stamps] or nil
            table.insert(summaries, {
                id = entry.id,
                name = entry.name,
                startGold = first and first.gold and first.gold.current or sessionData.startMoney or 0,
                endGold = last and last.gold and last.gold.current or sessionData.startMoney or 0,
                startLabor = first and first.labor and first.labor.current or 0,
                endLabor = last and last.labor and last.labor.current or 0,
                started = sessionData.started,
                ended = sessionData.ended,
                earnedLabor = sessionData.earnedLabor,
                usedLabor = sessionData.usedLabor,
                earnedMoney = sessionData.earnedMoney,
                usedMoney = sessionData.usedMoney
            })
        else
            api.Log:Info("[SessionHistory] Failed to load session file: " .. tostring(entry.path))
        end
    end
    api.Log:Info("[SessionHistory] loadAllSessionSummaries: end")
    return summaries
end

-- Format timestamp and duration
local function formatSessionTime(started, ended)
    local function fmt(ts)
        if not ts then
            api.Log:Info("Invalid timestamp: " .. tostring(ts))
            return "?"
        end
        -- Always pass as string
        local t = api.Time:TimeToDate(tostring(ts))
        if not t then
            api.Log:Info("TimeToDate failed for: " .. tostring(ts))
            return "?"
        end
        return string.format("%02d-%02d %02d:%02d",  t.day,t.month,  t.hour, t.minute)
    end
    local duration = (ended and started) and (ended - started) or 0
    local hours = math.floor(duration / 3600)
    local mins = math.floor((duration % 3600) / 60)
    -- return string.format("%dh %dm (%s to %s)", hours, mins, fmt(started), fmt(ended))
    return string.format("%dh %dm (%s)", hours, mins, fmt(started))
end


local function drawSessionHistoryLineBackground(parent, x, y, width, height, colorMode)
    local bg = parent:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
    if colorMode == "positive" then
        bg:SetColor(ConvertColor(80), ConvertColor(210), ConvertColor(84), 0.25)
    elseif colorMode == "negative" then
        bg:SetColor(ConvertColor(210), ConvertColor(94), ConvertColor(84), 0.35)
    else
        bg:SetColor(ConvertColor(100), ConvertColor(100), ConvertColor(100), 0.15)
    end
    bg:SetTextureInfo("bg_quest")
    bg:AddAnchor("TOPLEFT", parent, x-2, y)
    bg:SetExtent(width+2, height+4)
    bg:Show(true)
    return bg
end

local function showSessionHistoryWindow(currentSession)
    api.Log:Info("[SessionHistory] showSessionHistoryWindow: start")
    local windowWidth, windowHeight = 800, 600
    WINDOW = api.Interface:CreateWindow('sessionHistoryWindow', 'Session History', windowWidth, windowHeight)
    api.Log:Info("[SessionHistory] Window created")
    WINDOW:AddAnchor("CENTER", "UIParent", 0, 0)
    WINDOW:SetHandler("OnCloseByEsc", function() WINDOW:Show(false) end)
    function WINDOW:OnClose() WINDOW:Show(false) end

    local paddingX, paddingY = 20, 50
    local rowHeight = 24
    local colWidths = {120, 100, 220, 100, 180}
    local entriesPerPage = 15
    local currentPage = 1
    api.Log:Info("[SessionHistory] Calling loadAllSessionSummaries")
    local sessionSummaries = loadAllSessionSummaries()
    local totalEntries = #sessionSummaries
    local totalPages = math.ceil((totalEntries > 0 and totalEntries or 1) / entriesPerPage)
    api.Log:Info("[SessionHistory] sessionSummaries loaded, totalEntries: " .. tostring(totalEntries))

    -- Set currentPage to last page (most recent sessions)
    currentPage = totalPages

    -- Header labels
    local headers = {"Session ID", "Start Gold", "End Gold", "Used Labor", "Elapsed Time"}
    local x = paddingX
    for i, header in ipairs(headers) do
        ui.createLabel('header_'..i, WINDOW, header, x, paddingY, 14)
        x = x + colWidths[i]
    end

    -- Container for row labels
    local rowLabels = {}
    local function clearRows()
        for _, row in ipairs(rowLabels) do
            for _, widget in ipairs(row) do
                widget:Show(false)
            end
        end
        rowLabels = {}
    end

    local function drawRows(page)
        api.Log:Info("[SessionHistory] drawRows called for page: " .. tostring(page))
        clearRows()
        local startIdx = (page - 1) * entriesPerPage + 1
        local endIdx = math.min(startIdx + entriesPerPage - 1, totalEntries)
        api.Log:Info("[SessionHistory] Drawing rows from index " .. tostring(startIdx) .. " to " .. tostring(endIdx))
        for i = startIdx, endIdx do
            local sess = sessionSummaries[i]
            if not sess then
                api.Log:Info("[SessionHistory] No session summary at index " .. tostring(i))
            else
                api.Log:Info(string.format("[SessionHistory] Session %d: id=%s, startGold=%s, endGold=%s, startLabor=%s, endLabor=%s, started=%s, ended=%s", i, tostring(sess.id), tostring(sess.startGold), tostring(sess.endGold), tostring(sess.startLabor), tostring(sess.endLabor), tostring(sess.started), tostring(sess.ended)))
            end
            local y = paddingY + 30 + ((i - startIdx) * rowHeight)
            -- Calculate gold difference and color mode
            local goldDiff = sess and (tonumber(sess.endGold) - tonumber(sess.startGold)) or 0
            local colorMode = nil
            if goldDiff > 0 then colorMode = "positive" elseif goldDiff < 0 then colorMode = "negative" end
            -- Draw background for the row (always, with colorMode)
            local bg = drawSessionHistoryLineBackground(WINDOW, paddingX, y, windowWidth - 2*paddingX - 20, rowHeight, colorMode)
            bg:Show(true) -- Ensure background is always shown
            local row = {bg}
            -- End Gold display: show endGold and (earned/used money)
            local endGoldDisplay = "-"
            if sess and sess.ended then
                local moneyChange = (tonumber(sess.earnedMoney or 0) - tonumber(sess.usedMoney or 0))
                local moneyChangeStr = (moneyChange > 0 and "+" or (moneyChange < 0 and "-" or "")) .. helpers.formatGold(math.abs(moneyChange))
                endGoldDisplay = helpers.formatGold(sess.endGold) .. " (" .. moneyChangeStr .. ")"
            end
            -- Used Labor display
            local usedLaborDisplay = sess and sess.usedLabor and tostring(sess.usedLabor) or "-"
            local values = {
                (sess and currentSession and sess.id == currentSession.id) and "Current Session" or (sess and sess.id or "?"),
                sess and helpers.formatGold(tostring(sess.startGold)) or "?",
                endGoldDisplay,
                usedLaborDisplay,
                sess and formatSessionTime(sess.started, sess.ended) or "-"
            }
            local x = paddingX
            for j, value in ipairs(values) do
                local label = ui.createLabel('row_'..i..'_'..j, WINDOW, value, x, y, 13)
                table.insert(row, label)
                x = x + colWidths[j]
            end
            table.insert(rowLabels, row)
        end
    end

    -- -- Pagination controls
    paginationLabel = ui.createLabel('paginationLabel', WINDOW, '', windowWidth/2 - 40, windowHeight - 40, 13)
    
    local function updatePaginationLabel()
        paginationLabel:SetText(string.format("Page %d of %d", currentPage, totalPages))
    end

    local prevButton = ui.createButton('prevButton', WINDOW, '<', windowWidth/ 2 - 140, windowHeight - 45, 30, 25)
    local nextButton = ui.createButton('nextButton', WINDOW, '>', windowWidth/ 2 + 60, windowHeight - 45, 30, 25)
    function prevButton:OnClick()
        if currentPage > 1 then
            currentPage = currentPage - 1
            drawRows(currentPage)
            updatePaginationLabel()
        end
    end
    prevButton:SetHandler("OnClick", prevButton.OnClick)
    function nextButton:OnClick()
        if currentPage < totalPages then
            currentPage = currentPage + 1
            drawRows(currentPage)
            updatePaginationLabel()
        end
    end
    nextButton:SetHandler("OnClick", nextButton.OnClick)

    -- -- Initial draw
    api.Log:Info("[SessionHistory] Initial drawRows call")
    clearRows()
    drawRows(currentPage)
    updatePaginationLabel()

    -- Add general overview statistics at the bottom
    local totalUsedLabor, totalEarnedLabor, totalUsedMoney, totalEarnedMoney = 0, 0, 0, 0
    for _, sess in ipairs(sessionSummaries) do
        totalUsedLabor = totalUsedLabor + (tonumber(sess.usedLabor) or 0)
        totalEarnedLabor = totalEarnedLabor + (tonumber(sess.earnedLabor) or 0)
        totalUsedMoney = totalUsedMoney + (tonumber(sess.usedMoney) or 0)
        totalEarnedMoney = totalEarnedMoney + (tonumber(sess.earnedMoney) or 0)
    end
    local goldDiff = totalEarnedMoney - totalUsedMoney
    local goldDiffStr = (goldDiff > 0 and "+" or (goldDiff < 0 and "-" or "")) .. helpers.formatGold(math.abs(goldDiff))
    local statsY = windowHeight - 145
    local leftX = paddingX
    local rightX = windowWidth / 2 + 20
    -- Labor context (left)
    ui.createLabel('overviewStatsLaborHeader', WINDOW, 'Labor', leftX, statsY, 16)
    ui.createLabel('overviewStatsLaborUsed', WINDOW, 'Total Used: ' .. tostring(totalUsedLabor), leftX, statsY + 24, 14)
    ui.createLabel('overviewStatsLaborEarned', WINDOW, 'Total Earned: ' .. tostring(totalEarnedLabor), leftX, statsY + 44, 14)
    -- Money context (right)
    ui.createLabel('overviewStatsMoneyHeader', WINDOW, 'Money', rightX, statsY, 16)
    ui.createLabel('overviewStatsMoneyUsed', WINDOW, 'Total Used: ' .. helpers.formatGold(totalUsedMoney), rightX, statsY + 24, 14)
    ui.createLabel('overviewStatsMoneyEarned', WINDOW, 'Total Earned: ' .. helpers.formatGold(totalEarnedMoney), rightX, statsY + 44, 14)
    ui.createLabel('overviewStatsMoneyDiff', WINDOW, 'Gold Difference: ' .. goldDiffStr, rightX, statsY + 64, 14)

    api.Log:Info("[SessionHistory] showSessionHistoryWindow: end")
    WINDOW:Show(true)
    return WINDOW
end

local function onUnload()
    WINDOW:Show(false)
    WINDOW = nil
end

return {
    showSessionHistoryWindow = showSessionHistoryWindow,
    onUnload = onUnload
} 
