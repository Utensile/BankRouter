-- Namespace and Event Handling
local AddonName = "BankRouter"
local BR = CreateFrame("Frame")
BR:RegisterEvent("ADDON_LOADED")
BR:RegisterEvent("MAIL_CLOSED")
BR:RegisterEvent("MAIL_SEND_SUCCESS")

-- State Variables
local isProcessing = false
local queue = {}
local currentQueueIndex = 0

-- Helper: Print to Chat
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[BankRouter]|r " .. msg)
end

-- Helper: Get Item Name from Link
local function GetItemNameFromLink(link)
    if not link then return nil end
    local name = string.find(link, "%[(.+)%]")
    if name then
        return string.sub(link, name + 1, string.len(link) - 4)
    end
    return nil
end

-- =============================================================
--  MINIMAP BUTTON
-- =============================================================
local function CreateMinimapButton()
    local btn = CreateFrame("Button", "BankRouterMinimapButton", Minimap)
    btn:SetWidth(32)
    btn:SetHeight(32)
    btn:SetFrameStrata("LOW")
    
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Letter_15")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 1)
    
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(54)
    border:SetHeight(54)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

    local function UpdatePosition()
        local pos = BankRouterDB.minimapPos or 45
        local radius = 80
        local x = math.cos(math.rad(pos)) * radius
        local y = math.sin(math.rad(pos)) * radius
        btn:SetPoint("CENTER", "Minimap", "CENTER", x, y)
    end

    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function() btn:StartMoving() end)
    btn:SetScript("OnDragStop", function()
        btn:StopMovingOrSizing()
        local mx, my = Minimap:GetCenter()
        local px, py = btn:GetCenter()
        local dx, dy = px - mx, py - my
        local angle = math.deg(math.atan2(dy, dx))
        if angle < 0 then angle = angle + 360 end
        BankRouterDB.minimapPos = angle
        UpdatePosition()
    end)
    btn:SetScript("OnClick", function() 
        if BankRouterFrame:IsShown() then 
            BankRouterFrame:Hide() 
        else 
            BankRouterFrame:Show() 
        end 
    end)
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:AddLine("BankRouter")
        GameTooltip:AddLine("Click to configure routes", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UpdatePosition()
end

-- =============================================================
--  CONFIGURATION GUI
-- =============================================================
local function UpdateRouteList(scrollChild)
    local kids = {scrollChild:GetChildren()}
    for _, child in ipairs(kids) do
        child:Hide()
        child:SetParent(nil)
    end

    local yOffset = 0
    for item, recipient in pairs(BankRouterDB.routes) do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetWidth(260)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", 0, 0)
        text:SetText("|cffffd100" .. item .. "|r  ->  " .. recipient)

        local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        delBtn:SetWidth(20)
        delBtn:SetHeight(20)
        delBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        delBtn:SetText("X")
        delBtn:SetScript("OnClick", function()
            BankRouterDB.routes[item] = nil
            UpdateRouteList(scrollChild)
            Print("Removed route for: " .. item)
        end)
        yOffset = yOffset - 22
    end
end

local function CreateConfigFrame()
    local f = CreateFrame("Frame", "BankRouterFrame", UIParent)
    f:SetWidth(300)
    f:SetHeight(400)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -15)
    title:SetText("BankRouter Config")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    local itemInput = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    itemInput:SetWidth(120)
    itemInput:SetHeight(20)
    itemInput:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -50)
    itemInput:SetAutoFocus(false)
    
    local itemLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemLabel:SetPoint("BOTTOMLEFT", itemInput, "TOPLEFT", -5, 0)
    itemLabel:SetText("Item Name (Case Sensitive)")

    local recInput = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    recInput:SetWidth(100)
    recInput:SetHeight(20)
    recInput:SetPoint("LEFT", itemInput, "RIGHT", 10, 0)
    recInput:SetAutoFocus(false)

    local recLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recLabel:SetPoint("BOTTOMLEFT", recInput, "TOPLEFT", -5, 0)
    recLabel:SetText("Recipient Name")

    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetWidth(250)
    addBtn:SetHeight(25)
    addBtn:SetPoint("TOP", f, "TOP", 0, -85)
    addBtn:SetText("Add / Update Route")

    -- FIX: Added specific name "BankRouterConfigScrollFrame" so the template works
    local scrollFrame = CreateFrame("ScrollFrame", "BankRouterConfigScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -120)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -35, 15)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(250)
    scrollChild:SetHeight(300)
    scrollFrame:SetScrollChild(scrollChild)

    addBtn:SetScript("OnClick", function()
        local item = itemInput:GetText()
        local to = recInput:GetText()
        if item and item ~= "" and to and to ~= "" then
            BankRouterDB.routes[item] = to
            itemInput:SetText("")
            recInput:SetText("")
            itemInput:ClearFocus()
            recInput:ClearFocus()
            UpdateRouteList(scrollChild)
            Print("Route added: " .. item .. " -> " .. to)
        else
            Print("Please enter both Item Name and Recipient.")
        end
    end)

    f:SetScript("OnShow", function() UpdateRouteList(scrollChild) end)
end

-- =============================================================
--  MAIL LOGIC & QUEUE
-- =============================================================

local timer = 0
local QueueFrame = CreateFrame("Frame")
QueueFrame:Hide()

QueueFrame:SetScript("OnUpdate", function()
    timer = timer + arg1
    if timer > 1.5 then
        timer = 0
        if currentQueueIndex > table.getn(queue) then
            QueueFrame:Hide()
            isProcessing = false
            Print("Done routing items.")
            return
        end

        local task = queue[currentQueueIndex]
        
        MailFrameTab2:Click()
        SendMailNameEditBox:SetText("")
        SendMailSubjectEditBox:SetText("")
        SendMailNameEditBox:SetText(task.recipient)
        SendMailSubjectEditBox:SetText("BankRouter: " .. task.itemName)
        
        local slotsFilled = 0
        for i=1, 12 do
            if task.slots[i] then
                local bag = task.slots[i].bag
                local slot = task.slots[i].slot
                local texture, count = GetContainerItemInfo(bag, slot)
                if texture then
                    PickupContainerItem(bag, slot)
                    ClickSendMailItemButton(i)
                    slotsFilled = slotsFilled + 1
                end
            end
        end

        if slotsFilled > 0 then
            Print("Sending batch to " .. task.recipient .. "...")
            SendMail(task.recipient, "BankRouter: " .. task.itemName, "Auto forwarded by BankRouter.")
        else
            currentQueueIndex = currentQueueIndex + 1
        end
    end
end)

local function BuildMailQueue()
    queue = {}
    currentQueueIndex = 1
    
    local tasksByRecipient = {} 

    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name = GetItemNameFromLink(link)
                local recipient = BankRouterDB.routes[name]
                if recipient then
                    if not tasksByRecipient[recipient] then tasksByRecipient[recipient] = {} end
                    table.insert(tasksByRecipient[recipient], {bag=bag, slot=slot, name=name})
                end
            end
        end
    end

    for recipient, items in pairs(tasksByRecipient) do
        local count = 0
        local batch = {}
        for _, itemData in ipairs(items) do
            table.insert(batch, itemData)
            count = count + 1
            if count == 12 then
                table.insert(queue, {recipient = recipient, itemName = "Mixed Batch", slots = batch})
                batch = {}
                count = 0
            end
        end
        if count > 0 then
            table.insert(queue, {recipient = recipient, itemName = "Mixed Batch", slots = batch})
        end
    end

    if table.getn(queue) > 0 then
        Print("Found items to route. Starting...")
        isProcessing = true
        QueueFrame:Show()
    else
        Print("No configured items found in bags.")
    end
end

-- =============================================================
--  MAILBOX GUI BUTTON
-- =============================================================
local function CreateMailboxButton()
    -- Create a button attached to the MailFrame
    local btn = CreateFrame("Button", "BankRouterSendButton", MailFrame, "UIPanelButtonTemplate")
    btn:SetWidth(100)
    btn:SetHeight(25)
    -- Position it at the top left of the MailFrame
    btn:SetPoint("TOPLEFT", MailFrame, "TOPLEFT", 60, -15)
    btn:SetText("Router Send")
    
    btn:SetScript("OnClick", function()
        BuildMailQueue()
    end)
    
    -- Only show the button when we are on the Send Mail tab (optional, but cleaner)
    -- For simplicity in 1.12, showing it always on the frame is fine, or we can hook the tabs.
    -- We will leave it visible on the MailFrame generally.
end

-- =============================================================
--  EVENT HANDLERS
-- =============================================================
BR:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == AddonName then
        if not BankRouterDB then BankRouterDB = {} end
        if not BankRouterDB.routes then BankRouterDB.routes = {} end
        if not BankRouterDB.minimapPos then BankRouterDB.minimapPos = 45 end
        
        CreateConfigFrame()
        CreateMinimapButton()
        CreateMailboxButton() -- Create the trigger button
        Print("Loaded.")
        
    elseif event == "MAIL_SEND_SUCCESS" then
        if isProcessing then
            currentQueueIndex = currentQueueIndex + 1
        end
        
    elseif event == "MAIL_CLOSED" then
        if isProcessing then
            isProcessing = false
            QueueFrame:Hide()
            Print("Mail closed. Routing stopped.")
        end
    end
end)