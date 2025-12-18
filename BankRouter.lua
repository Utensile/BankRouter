-- Namespace and Event Handling
local AddonName = "BankRouter"
local BR = CreateFrame("Frame")
BR:RegisterEvent("ADDON_LOADED")

-- Helper: Print to Chat
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[BankRouter]|r " .. msg)
end

local function Debug(msg)
    if(BankRouterDB.debug) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Debug]|r " .. msg)
    end
end

-- Simple non-blocking delay function
local function wait(seconds, callback)
    local timerFrame = CreateFrame("Frame")
    timerFrame.timeElapsed = 0
    timerFrame:SetScript("OnUpdate", function()
        this.timeElapsed = this.timeElapsed + arg1
        if this.timeElapsed >= seconds then
            this:SetScript("OnUpdate", nil) -- Stop the timer
            if callback then callback() end  -- Run the code
        end
    end)
end

-- Helper: Get Item Name from Link
local function GetItemNameFromLink(link)
    if not link then return nil end
    local _, _, name = string.find(link, "%[(.+)%]")
    return name
end

-- =============================================================
--  COLOR HELPERS (Prat "playernames" Support)
-- =============================================================
local function RGBToHex(r, g, b)
    r = r or 1.0; g = g or 1.0; b = b or 1.0;
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function GetRecipientColor(name)
    local hex = "|cff888888" -- Default: Gray
    local class = nil

    -- 1. Try to get class from Prat 'playernames' module
    if Prat and Prat.GetModule then
        -- The module is registered as "playernames" (lowercase) in your file
        local PN = Prat:GetModule("playernames") 
        if PN and PN.Classes then
            -- The file shows data is stored in PN.Classes[Name]
            class = PN.Classes[name]
        end
    end

    -- 2. Fallback: Try standard API if the player is currently targeted
    if not class and UnitName("target") == name then
        _, class = UnitClass("target")
    end

    -- 3. Convert Class to Color
    if class then
        -- Prat might store "Mage" or "MAGE", RAID_CLASS_COLORS requires "MAGE"
        local upperClass = string.upper(class)
        
        if RAID_CLASS_COLORS and RAID_CLASS_COLORS[upperClass] then
            local c = RAID_CLASS_COLORS[upperClass]
            hex = RGBToHex(c.r, c.g, c.b)
        end
    end
    
    return hex
end

-- =============================================================
--  HOOKS (Robust method for Bagshui/OneBag/Stock UI)
-- =============================================================
local function InitHooks()
    Debug("INIT HOOKS STARTED")

    -- 1. Save the original function so we don't break the game when the window is closed
    if not BR_Orig_ContainerFrameItemButton_OnClick then
        BR_Orig_ContainerFrameItemButton_OnClick = ContainerFrameItemButton_OnClick
    end

    -- 2. Define the new function (Standard Left Click Hook)
    ContainerFrameItemButton_OnClick = function(button, ignoreShift)
        Debug("CLICK DETECTED - ".. button)
        -- Check if BankRouter Config Frame is currently open and it is a Left Click
        if BankRouterFrame and BankRouterFrame:IsVisible() and IsShiftKeyDown() and button == "LeftButton" then
            Debug("ITS A LEFT CLICK!!!!")
            -- Get the item info from the button that was clicked
            local bag = this:GetParent():GetID()
            local slot = this:GetID()
            local link = GetContainerItemLink(bag, slot)
            
            Debug("bag: ".. bag.." slot: ".. slot.. "link: "..link)
            if link then
                local name = GetItemNameFromLink(link)
                if name then
                    -- Update the Input Field
                    BankRouterItemInput:SetText(name)
                    -- Move focus to Recipient field for faster entry
                    BankRouterRecInput:SetFocus()
                    
                    Print("Auto-filled: " .. name)
                    
                    -- CRITICAL: Return here to BLOCK the item from being picked up
                    return 
                end
            end
        end

        -- 3. If the window wasn't open (or it wasn't a left click), run the original code
        if BR_Orig_ContainerFrameItemButton_OnClick then
            BR_Orig_ContainerFrameItemButton_OnClick(button, ignoreShift)
        end
    end
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
    -- 1. Clear existing children
    local kids = {scrollChild:GetChildren()}
    for _, child in ipairs(kids) do
        child:Hide()
        child:SetParent(nil)
    end

    -- 2. Convert database to a sortable list
    local sortedRoutes = {}
    for item, recipient in pairs(BankRouterDB.routes) do
        table.insert(sortedRoutes, {item = item, recipient = recipient})
    end

    -- 3. Sort the list: Recipient First, Item Second
    table.sort(sortedRoutes, function(a, b)
        if a.recipient == b.recipient then
            return a.item < b.item
        else
            return a.recipient < b.recipient
        end
    end)

    -- 4. Draw the sorted list
    local yOffset = 0
    for _, route in ipairs(sortedRoutes) do
        local itemName = route.item
        local recipientName = route.recipient
        
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetWidth(240)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)

        -- DELETE BUTTON
        local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        delBtn:SetWidth(20)
        delBtn:SetHeight(20)
        delBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
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

        -- ITEM NAME (Left)
        local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        itemText:SetPoint("LEFT", row, "LEFT", 0, 0)
        itemText:SetWidth(130)
        itemText:SetJustifyH("LEFT")
        itemText:SetText("|cffffd100" .. itemName .. "|r")

        -- RECIPIENT NAME (Right) - COLORED
        local recText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        recText:SetPoint("RIGHT", delBtn, "LEFT", -5, 0)
        recText:SetWidth(90)
        recText:SetJustifyH("RIGHT")
        
        -- Get Color using the fixed helper
        local colorHex = GetRecipientColor(recipientName)
        recText:SetText(colorHex .. recipientName .. "|r")

        -- Arrow Separator
        local arrow = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        arrow:SetPoint("CENTER", row, "CENTER", 0, 0)
        arrow:SetText("|cff555555->|r")
        arrow:SetAlpha(0.5)

        yOffset = yOffset - 22
    end
end

local function CreateConfigFrame()
    -- 1. Main Frame
    local f = CreateFrame("Frame", "BankRouterFrame", UIParent)
    f:SetWidth(340) -- Slightly wider to prevent text cramping
    f:SetHeight(450)
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
    
    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -5)
    subtitle:SetText("(Shift+Click an item to auto-fill)")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    -- 2. Input Fields
    -- We give them Global Names (BankRouterItemInput) so we can find them later in the hook
    local itemInput = CreateFrame("EditBox", "BankRouterItemInput", f, "InputBoxTemplate")
    itemInput:SetWidth(140)
    itemInput:SetHeight(20)
    -- Moved down to -60 to give the labels plenty of room below the title
    itemInput:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -60)
    itemInput:SetAutoFocus(false)
    
    local itemLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Anchored 5 pixels ABOVE the box (TOPLEFT to TOPLEFT with y=15 offset)
    itemLabel:SetPoint("BOTTOMLEFT", itemInput, "TOPLEFT", -5, 4)
    itemLabel:SetText("Item Name")

    local recInput = CreateFrame("EditBox", "BankRouterRecInput", f, "InputBoxTemplate")
    recInput:SetWidth(120)
    recInput:SetHeight(20)
    -- Anchored to the right of the Item Input with 20px padding
    recInput:SetPoint("LEFT", itemInput, "RIGHT", 20, 0)
    recInput:SetAutoFocus(false)

    local recLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Anchored 5 pixels ABOVE the box
    recLabel:SetPoint("BOTTOMLEFT", recInput, "TOPLEFT", -5, 4)
    recLabel:SetText("Recipient Name")

    -- 3. Checkboxes (Auto Send / Debug)
    local autoSendCB = CreateFrame("CheckButton", "BankRouterAutoSendCheck", f, "UICheckButtonTemplate")
    -- Positioned well below the input boxes
    autoSendCB:SetPoint("TOPLEFT", itemInput, "BOTTOMLEFT", -5, -15)
    _G[autoSendCB:GetName().."Text"]:SetText("Auto Send")
    autoSendCB:SetChecked(BankRouterDB.autoSend)
    autoSendCB:SetScript("OnClick", function()
        BankRouterDB.autoSend = this:GetChecked() and true or false
    end)

    local debugCB = CreateFrame("CheckButton", "BankRouterDebugCheck", f, "UICheckButtonTemplate")
    debugCB:SetPoint("LEFT", autoSendCB, "RIGHT", 100, 0)
    _G[debugCB:GetName().."Text"]:SetText("Debug Mode")
    debugCB:SetChecked(BankRouterDB.debug)
    debugCB:SetScript("OnClick", function()
        BankRouterDB.debug = this:GetChecked() and true or false
    end)

    -- 4. Add/Update Button
    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetWidth(250)
    addBtn:SetHeight(25)
    -- Anchored below the checkboxes
    addBtn:SetPoint("TOP", f, "TOP", 0, -135)
    addBtn:SetText("Add / Update Route")

    -- 5. Scroll List
    local scrollFrame = CreateFrame("ScrollFrame", "BankRouterConfigScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -170)
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
            --recInput:SetText("")
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
    -- 0. SAFETY CHECK: IS MAIL ALREADY FULL?
    local currentSubject = SendMailSubjectEditBox:GetText()
    if currentSubject and currentSubject ~= "" then
        Print("Mailbox is busy (Name field is not empty). Please Send or Clear.  ->" .. currentSubject)
        return
    end

    local myName = UnitName("player")
    local targetRecipient = nil
    local targetSubject = nil
    local itemsToAttach = {}
    
    -- 1. Scan to find the FIRST recipient we need to service
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local texture, count, locked = GetContainerItemInfo(bag, slot)
            
            -- If locked, it means the item is currently being moved or attached
            if texture and not locked then
                local link = GetContainerItemLink(bag, slot)
                local name = GetItemNameFromLink(link)
                local routeRecipient = BankRouterDB.routes[name]
                Debug("Item: " .. name .. "Recipient: " .. (routeRecipient or "nil"))
                -- Is there a route? And are we NOT mailing ourselves?
                if routeRecipient and routeRecipient ~= myName then
                    
                    -- Logic:
                    -- If we haven't picked a target yet, pick this one.
                    -- If we HAVE picked a target, only add items if they match that target.
                    Debug("Valid Recipeint detected: ".. routeRecipient)
                    if not targetRecipient then
                        targetRecipient = routeRecipient
                        targetSubject = name -- Use first item name as subject
                    end
                    
                    if routeRecipient == targetRecipient then
                        if table.getn(itemsToAttach) < 12 then
                            table.insert(itemsToAttach, {bag=bag, slot=slot})
                        end
                    end

                    Debug("targetRecipient: " .. targetRecipient)
                end
            end
        end
    end

    if not targetRecipient then
        Print("No routable items found (or all items belong to this character).")
        return
    end

    -- 2. Switch to Send Tab
    MailFrameTab2:Click()
    
    -- 3. Force Update the Name Field
    SendMailNameEditBox:SetText(targetRecipient)
    
    -- 4. Set Subject
    if targetSubject then
        SendMailSubjectEditBox:SetText("BankRouter: " .. targetSubject)
    else
        SendMailSubjectEditBox:SetText("BankRouter Shipment")
    end
    
    -- 5. Attach Items
    local count = 0
    for _, item in ipairs(itemsToAttach) do
        UseContainerItem(item.bag, item.slot)
        count = count + 1
    end
    
    Print("Prepared batch for " .. targetRecipient .. " (" .. count .. " items). Press Send when ready.")
    if BankRouterDB.autoSend and TurtleMail and TurtleMail.send_mail_button_onclick then
        wait(0.2, function ()
            TurtleMail.send_mail_button_onclick()
            wait(1, function ()
                PrepareNextBatch()
            end)
        end)
    end
end

-- =============================================================
--  MAILBOX GUI BUTTON
-- =============================================================
local function CreateMailboxButton()
    local btn = CreateFrame("Button", "BankRouterPrepareButton", MailFrame, "UIPanelButtonTemplate")
    btn:SetWidth(100)
    btn:SetHeight(25)
    
    -- Position: Below the "Send" button
    btn:SetPoint("TOP", "SendMailMailButton", "BOTTOMRIGHT", 20, -5)
    
    btn:SetText("Prepare Batch")
    
    btn:SetScript("OnClick", function()
        PrepareNextBatch()
    end)
end


-- =============================================================
--  EVENT HANDLERS
-- =============================================================
BR:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == AddonName then
        if not BankRouterDB then BankRouterDB = {} end
        if not BankRouterDB.routes then BankRouterDB.routes = {} end
        if not BankRouterDB.minimapPos then BankRouterDB.minimapPos = 45 end
        if not BankRouterDB.autoSend then BankRouterDB.autoSend = true end
        if not BankRouterDB.debug then BankRouterDB.debug = false end
        
        CreateConfigFrame()
        CreateMinimapButton()
        CreateMailboxButton()
        InitHooks() -- Activate the Shift+Click hook
        Print("Loaded.")
    end
end)