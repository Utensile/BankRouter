-- =============================================================
-- BANKROUTER v1.3
-- Fixed Minimap Toggle & Safer Item Attachment
-- =============================================================

-- DEFAULT SETTINGS
-- -------------------------------------------------------------
local defaultRoutes = {
    ["Silk Cloth"]     = "Knabe",
    ["Mageweave Cloth"]   = "Knabe",
    ["Light Leather"] = "LeatherToon",
}

-- STATE VARIABLES
-- -------------------------------------------------------------
local mailQueue = {}
local processing = false
local pendingSend = false
local eventFrame = CreateFrame("Frame")
local configFrame = nil 
local scrollChild = nil 

-- UTILITIES
-- -------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[BankRouter]|r " .. msg)
end

-- DATABASE INIT
-- -------------------------------------------------------------
function BankRouter_InitDB()
    if not BankRouterDB then BankRouterDB = {} end
    if not BankRouterDB.routes then BankRouterDB.routes = defaultRoutes end
    if not BankRouterDB.minimapPos then BankRouterDB.minimapPos = 45 end
end

-- =============================================================
-- LOGIC: MAILING (Event-Driven)
-- =============================================================

local function ProcessNextItem()
    -- Safety Check
    if not MailFrame:IsVisible() then
        processing = false
        pendingSend = false
        Print("Mailbox closed. Stopping.")
        return
    end

    local work = table.remove(mailQueue, 1)

    if work then
        -- 1. Ensure we are on the Send Mail tab
        if not SendMailFrame:IsVisible() then
            MailFrameTab2:Click()
        end

        -- 2. Clear fields
        SendMailNameEditBox:SetText("")
        SendMailSubjectEditBox:SetText("")
        SendMailBodyEditBox:SetText("")
        
        -- 3. Attach Item
        PickupContainerItem(work.bag, work.slot)
        ClickSendMailItemButton()
        
        -- 4. VERIFY ATTACHMENT (The Fix)
        -- We check if an item is actually in the mail slot. 
        -- If GetSendMailItem() returns nil, the pickup failed.
        local attachedName = GetSendMailItem()
        
        if attachedName then
            -- Item is there, safe to send.
            -- Using "" for subject as requested. The game might auto-fill it, 
            -- or send it blank.
            SendMail(work.recipient, "", "")
            Print("Sent " .. work.name .. " to " .. work.recipient)
        else
            -- Attachment failed (Item locked or missing). Skip this item.
            Print("Error: Could not attach " .. work.name .. ". Skipping.")
            pendingSend = true -- Immediately trigger next cycle to keep going
        end
    else
        -- Queue Empty
        processing = false
        pendingSend = false
        Print("All items sent!")
    end
end

local function ScanBagsAndQueue()
    BankRouter_InitDB()
    mailQueue = {} 
    
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local itemName = string.match(link, "%[(.*)%]")
                if BankRouterDB.routes[itemName] then
                    table.insert(mailQueue, {
                        bag = bag,
                        slot = slot,
                        name = itemName,
                        recipient = BankRouterDB.routes[itemName]
                    })
                end
            end
        end
    end

    local count = table.getn(mailQueue)
    if count > 0 then
        Print("Found " .. count .. " items. Sending...")
        processing = true
        ProcessNextItem() 
    else
        Print("No configured items found in bags.")
    end
end

-- =============================================================
-- UI: CONFIGURATION WINDOW
-- =============================================================

local function RefreshConfigList()
    -- Clear current list
    local children = { scrollChild:GetChildren() }
    for _, child in ipairs(children) do 
        child:Hide() 
        child:SetParent(nil)
    end

    -- Rebuild list
    local yOffset = 0
    for item, recipient in pairs(BankRouterDB.routes) do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetWidth(260); row:SetHeight(20)
        row:SetPoint("TOPLEFT", 5, yOffset)

        local btnDelete = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        btnDelete:SetWidth(20); btnDelete:SetHeight(20)
        btnDelete:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        btnDelete:SetScript("OnClick", function()
            BankRouterDB.routes[item] = nil
            RefreshConfigList()
        end)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", 5, 0)
        text:SetText("|cffffffff" .. item .. "|r  -->  |cff00ccff" .. recipient .. "|r")

        yOffset = yOffset - 20
    end
    scrollChild:SetHeight(math.abs(yOffset))
end

local function CreateConfigFrame()
    if configFrame then return end -- If it exists, do nothing

    -- Main Frame
    configFrame = CreateFrame("Frame", "BankRouterConfig", UIParent)
    configFrame:SetWidth(300); configFrame:SetHeight(350)
    configFrame:SetPoint("CENTER", UIParent, "CENTER")
    configFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32, 
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    configFrame:EnableMouse(true)
    configFrame:SetMovable(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    configFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    configFrame:Hide() -- Start hidden

    -- Header
    local header = configFrame:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetWidth(256); header:SetHeight(64)
    header:SetPoint("TOP", 0, 12)
    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", header, "TOP", 0, -14)
    title:SetText("BankRouter Config")

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() configFrame:Hide() end)

    -- ADD NEW SECTION
    local inputItem = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
    inputItem:SetWidth(110); inputItem:SetHeight(20)
    inputItem:SetPoint("TOPLEFT", 20, -40)
    inputItem:SetAutoFocus(false)
    inputItem:SetText("Item Name")

    local inputTo = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
    inputTo:SetWidth(100); inputTo:SetHeight(20)
    inputTo:SetPoint("LEFT", inputItem, "RIGHT", 10, 0)
    inputTo:SetAutoFocus(false)
    inputTo:SetText("Recipient")

    local btnAdd = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    btnAdd:SetWidth(40); btnAdd:SetHeight(20)
    btnAdd:SetPoint("LEFT", inputTo, "RIGHT", 5, 0)
    btnAdd:SetText("Add")
    btnAdd:SetScript("OnClick", function()
        local item = inputItem:GetText()
        local to = inputTo:GetText()
        if item and to and item ~= "" and to ~= "" then
            BankRouterDB.routes[item] = to
            inputItem:SetText("")
            RefreshConfigList()
        end
    end)

    -- LIST SCROLL FRAME
    local scrollFrame = CreateFrame("ScrollFrame", "BankRouterScroll", configFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -75)
    scrollFrame:SetWidth(240); scrollFrame:SetHeight(240)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(240); scrollChild:SetHeight(10)
    scrollFrame:SetScrollChild(scrollChild)

    local listBg = configFrame:CreateTexture(nil, "BACKGROUND")
    listBg:SetPoint("TOPLEFT", scrollFrame, -5, 5)
    listBg:SetPoint("BOTTOMRIGHT", scrollFrame, 25, -5)
    listBg:SetTexture(0, 0, 0, 0.3)

    RefreshConfigList()
end

-- =============================================================
-- UI: MINIMAP BUTTON
-- =============================================================
local mmBtn = CreateFrame("Button", "BankRouterMinimapBtn", Minimap)
mmBtn:SetFrameStrata("LOW")
mmBtn:SetWidth(32); mmBtn:SetHeight(32)
mmBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mmBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = mmBtn:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\INV_Letter_15") 
icon:SetWidth(20); icon:SetHeight(20)
icon:SetPoint("CENTER", 0, 0)

local border = mmBtn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetWidth(52); border:SetHeight(52)
border:SetPoint("TOPLEFT", 0, 0)

-- Minimap Movement
local function UpdateMinimapPosition()
    local angle = math.rad(BankRouterDB.minimapPos or 45)
    local x, y = math.cos(angle), math.sin(angle)
    mmBtn:SetPoint("CENTER", Minimap, "CENTER", x * 80, y * 80)
end

mmBtn:SetMovable(true)
mmBtn:RegisterForDrag("LeftButton")
mmBtn:SetScript("OnDragStart", function() this:LockHighlight(); this.isDragging = true end)
mmBtn:SetScript("OnDragStop", function() this:UnlockHighlight(); this.isDragging = false end)
mmBtn:SetScript("OnUpdate", function()
    if this.isDragging then
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = UIParent:GetScale()
        px, py = px / scale, py / scale
        local angle = math.deg(math.atan2(py - my, px - mx))
        BankRouterDB.minimapPos = angle
        UpdateMinimapPosition()
    end
end)

-- MINIMAP CLICK (FIXED)
mmBtn:SetScript("OnClick", function() 
    BankRouter_InitDB()
    CreateConfigFrame() -- Create if missing
    
    if configFrame:IsVisible() then 
        configFrame:Hide() 
    else 
        configFrame:Show() 
    end
end)

mmBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("BankRouter")
    GameTooltip:AddLine("Click to configure.", 1,1,1)
    GameTooltip:Show()
end)
mmBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)


-- =============================================================
-- MAIN EVENT LOOP
-- =============================================================
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("MAIL_SEND_SUCCESS")
eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
eventFrame:RegisterEvent("MAIL_SHOW")

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "BankRouter" then
        BankRouter_InitDB()
        UpdateMinimapPosition()
    end

    if event == "MAIL_SHOW" then
        if BankRouterBtn then BankRouterBtn:Show() end
    end

    if not processing then return end

    if event == "MAIL_SEND_SUCCESS" then
        pendingSend = true
    elseif event == "UI_ERROR_MESSAGE" then
        if arg1 == ERR_MAIL_TARGET_NOT_FOUND or arg1 == ERR_MAIL_MAILBOX_FULL then
            processing = false
            Print("Error: " .. arg1 .. ". Stopping.")
        end
    end
end)

eventFrame:SetScript("OnUpdate", function()
    if processing and pendingSend then
        pendingSend = false
        ProcessNextItem()
    end
end)

-- MAILBOX BUTTON
local btn = CreateFrame("Button", "BankRouterBtn", MailFrame, "UIPanelButtonTemplate")
btn:SetWidth(120); btn:SetHeight(25)
btn:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -50, -40)
btn:SetText("Auto Route")
btn:SetScript("OnClick", function()
    if processing then
        processing = false; Print("Stopped.")
    else
        ScanBagsAndQueue()
    end
end)

-- Hook Tab click (Visibility Logic)
local original_MailFrameTab_OnClick = MailFrameTab_OnClick
function MailFrameTab_OnClick(tab)
    original_MailFrameTab_OnClick(tab)
    if not tab then tab = this:GetID() end
    if tab == 1 then BankRouterBtn:Show() else BankRouterBtn:Hide() end
end