-- Namespace and Event Handling
local AddonName = "BankRouter"
local BR = CreateFrame("Frame")
BR:RegisterEvent("ADDON_LOADED")

-- Helper: Print to Chat
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[BankRouter]|r " .. msg)
end

-- Helper: Get Item Name from Link
local function GetItemNameFromLink(link)
    if not link then return nil end
    local _, _, name = string.find(link, "%[(.+)%]")
    return name
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
    for itemName, recipientName in pairs(BankRouterDB.routes) do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetWidth(260)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", 0, 0)
        text:SetText("|cffffd100" .. itemName .. "|r  ->  " .. recipientName)

        local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        delBtn:SetWidth(20)
        delBtn:SetHeight(20)
        delBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        delBtn:SetText("X")
        delBtn.itemName = itemName 
        
        delBtn:SetScript("OnClick", function()
            local itemToDelete = this.itemName
            if itemToDelete then
                BankRouterDB.routes[itemToDelete] = nil
                UpdateRouteList(scrollChild)
                Print("Removed route for: " .. itemToDelete)
            end
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
--  MAIL BATCH LOGIC
-- =============================================================

local function PrepareNextBatch()
    -- 1. Scan bags and find the FIRST recipient that has available items
    local foundItems = {} -- Key: Recipient, Value: { {bag=, slot=, name=} }
    
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            -- GetContainerItemInfo returns texture, count, locked, quality, readable
            -- We MUST check 'locked'. If it's locked, it's already in the mail window or being moved.
            local texture, count, locked = GetContainerItemInfo(bag, slot)
            
            if texture and not locked then
                local link = GetContainerItemLink(bag, slot)
                local name = GetItemNameFromLink(link)
                local recipient = BankRouterDB.routes[name]
                
                if recipient then
                    if not foundItems[recipient] then foundItems[recipient] = {} end
                    table.insert(foundItems[recipient], {bag=bag, slot=slot, name=name})
                end
            end
        end
    end

    -- 2. Pick the first recipient that has items
    local targetRecipient, items = next(foundItems)
    
    if not targetRecipient then
        Print("No more items found to route.")
        return
    end

    -- 3. Prepare the Mail Frame
    -- Switch to Send Tab
    MailFrameTab2:Click() 
    
    -- Clear previous info just in case (though usually sending clears it)
    SendMailNameEditBox:SetText("")
    SendMailSubjectEditBox:SetText("")
    
    SendMailNameEditBox:SetText(targetRecipient)
    SendMailSubjectEditBox:SetText("BankRouter Shipment")
    
    -- 4. Attach up to 12 items
    local attachedCount = 0
    for _, itemData in ipairs(items) do
        if attachedCount >= 12 then break end
        
        -- UseContainerItem puts it in the mail slot
        UseContainerItem(itemData.bag, itemData.slot)
        attachedCount = attachedCount + 1
    end
    
    Print("Prepared batch for " .. targetRecipient .. " (" .. attachedCount .. " items). Press Send when ready.")
end

-- =============================================================
--  MAILBOX GUI BUTTON
-- =============================================================
local function CreateMailboxButton()
    local btn = CreateFrame("Button", "BankRouterPrepareButton", MailFrame, "UIPanelButtonTemplate")
    btn:SetWidth(100)
    btn:SetHeight(25)
    
    -- Position: Below the standard "Send" button (SendMailMailButton)
    -- We attach it to the SendMailMailButton so it moves with it if the UI scales
    btn:SetPoint("TOP", "SendMailMailButton", "BOTTOM", 0, -5)
    
    btn:SetText("Prepare Batch")
    
    btn:SetScript("OnClick", function()
        PrepareNextBatch()
    end)
    
    -- Optional: Only show this button when on the "Send Mail" tab (Tab 2)
    -- But in 1.12 simple is better; it will be visible on the frame.
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
        CreateMailboxButton()
        Print("Loaded.")
    end
end)