-- =============================================================
-- BANKROUTER v1.6 (DEBUG & STATE MACHINE)
-- =============================================================

-- CONFIGURATION & STATE
-- -------------------------------------------------------------
local mailQueue = {}
local processing = false
local currentState = "IDLE" -- IDLE, PREPARING, SENDING, WAITING
local currentWork = nil
local eventFrame = CreateFrame("Frame")
local configFrame, scrollChild

-- UTILITIES
-- -------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[BankRouter]|r " .. msg)
end

local function Debug(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[DEBUG]|r " .. msg)
end

-- DATABASE INIT
-- -------------------------------------------------------------
function BankRouter_InitDB()
    if not BankRouterDB then BankRouterDB = {} end
    if BankRouterDB.routes == nil then
        BankRouterDB.routes = {
            ["Runecloth"]     = "ClothBankToon",
            ["Thorium Ore"]   = "OreBankToon",
            ["Light Leather"] = "LeatherToon",
        }
        Print("Default routes loaded.")
    end
    if not BankRouterDB.minimapPos then BankRouterDB.minimapPos = 45 end
end

-- =============================================================
-- CORE LOGIC (STATE MACHINE)
-- =============================================================

-- This function runs every single frame when 'processing' is true
local function RunStateMachine()
    
    -- SAFETY CHECK
    if not MailFrame:IsVisible() then
        processing = false
        currentState = "IDLE"
        Print("Mailbox closed. Stopping.")
        return
    end

    -- STATE 1: GET NEXT ITEM
    if currentState == "NEXT_ITEM" then
        currentWork = table.remove(mailQueue, 1)
        if not currentWork then
            processing = false
            currentState = "IDLE"
            Print("Queue empty. All done!")
            return
        end
        
        Debug("Processing: " .. currentWork.name .. " (Bag " .. currentWork.bag .. ", Slot " .. currentWork.slot .. ")")
        currentState = "PREPARE_UI"
        return
    end

    -- STATE 2: PREPARE UI (Switch Tab & Clear)
    if currentState == "PREPARE_UI" then
        if not SendMailFrame:IsVisible() then
            Debug("Switching to Send Mail Tab...")
            MailFrameTab2:Click()
        end
        
        -- Clear fields
        SendMailNameEditBox:SetText("")
        SendMailSubjectEditBox:SetText("")
        SendMailBodyEditBox:SetText("")
        
        -- Scrub cursor/slot clean
        ClearCursor()
        ClickSendMailItemButton()
        ClearCursor()
        
        -- Wait one frame for UI to update
        currentState = "ATTACH_ITEM"
        return
    end

    -- STATE 3: ATTACH ITEM
    if currentState == "ATTACH_ITEM" then
        -- Try to pick it up
        PickupContainerItem(currentWork.bag, currentWork.slot)
        
        -- Check if cursor actually has it
        if not CursorHasItem() then
            Debug("FAILED: Cursor did not pick up item. Retrying...")
            -- If this happens, we just stay in this state to try again next frame
            -- or we could abort to prevent infinite loops. 
            -- For now, let's abort this item.
            Debug("Skipping " .. currentWork.name .. " due to pickup failure.")
            currentState = "NEXT_ITEM"
            return
        end
        
        -- Drop into slot
        ClickSendMailItemButton()
        
        -- Verify it is attached
        local attachedName = GetSendMailItem()
        if attachedName then
            Debug("Success! Attached: " .. attachedName)
            currentState = "SEND_MAIL"
        else
            Debug("FAILED: Item dropped but not attached to mail slot.")
            ClearCursor() -- Clean up mess
            currentState = "NEXT_ITEM" -- Skip it
        end
        return
    end

    -- STATE 4: SEND MAIL
    if currentState == "SEND_MAIL" then
        Debug("Sending mail to " .. currentWork.recipient)
        SendMail(currentWork.recipient, "", "")
        
        -- Now we MUST wait for the server event
        currentState = "WAITING_FOR_SERVER"
    end
    
    -- STATE 5: WAITING (Handled by OnEvent)
    if currentState == "WAITING_FOR_SERVER" then
        -- Do nothing here. We wait for MAIL_SEND_SUCCESS or TIMEOUT.
    end
end

local function ScanBagsAndQueue()
    BankRouter_InitDB()
    mailQueue = {} 
    
    Debug("Scanning bags...")
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
        Print("Found " .. count .. " items.")
        processing = true
        currentState = "NEXT_ITEM"
    else
        Print("No configured items found.")
    end
end

-- =============================================================
-- EVENTS
-- =============================================================
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("MAIL_SEND_SUCCESS")
eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
eventFrame:RegisterEvent("MAIL_SHOW")

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "BankRouter" then
        BankRouter_InitDB()
    end
    
    if event == "MAIL_SHOW" and BankRouterBtn then 
        BankRouterBtn:Show() 
    end

    if not processing then return end

    if event == "MAIL_SEND_SUCCESS" then
        Debug("Server confirmed: Mail Sent.")
        currentState = "NEXT_ITEM"
        
    elseif event == "UI_ERROR_MESSAGE" then
        Debug("UI Error: " .. arg1)
        if arg1 == ERR_MAIL_TARGET_NOT_FOUND or arg1 == ERR_MAIL_MAILBOX_FULL then
            processing = false
            Print("Critical Error. Stopping.")
        else
            -- Recoverable error? Try next item.
            currentState = "NEXT_ITEM"
        end
    end
end)

eventFrame:SetScript("OnUpdate", function()
    if processing then
        RunStateMachine()
    end
end)

-- =============================================================
-- UI SETUP (CONFIG & BUTTONS)
-- =============================================================

-- [Copy of previous UI Config code assumed here. 
--  To save space, I am including the essential Button/Hook logic only. 
--  The Config window code is identical to v1.5]

local function RefreshConfigList()
    local children = { scrollChild:GetChildren() }
    for _, child in ipairs(children) do child:Hide(); child:SetParent(nil) end
    local yOffset = 0
    for item, recipient in pairs(BankRouterDB.routes) do
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetWidth(260); row:SetHeight(20); row:SetPoint("TOPLEFT", 5, yOffset)
        local btnDelete = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        btnDelete:SetWidth(20); btnDelete:SetHeight(20); btnDelete:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        btnDelete:SetScript("OnClick", function() BankRouterDB.routes[item] = nil; RefreshConfigList() end)
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", 5, 0); text:SetText("|cffffffff" .. item .. "|r  -->  |cff00ccff" .. recipient .. "|r")
        yOffset = yOffset - 20
    end
    scrollChild:SetHeight(math.abs(yOffset))
end

local function CreateConfigFrame()
    if configFrame then return end
    configFrame = CreateFrame("Frame", "BankRouterConfig", UIParent)
    configFrame:SetWidth(300); configFrame:SetHeight(350); configFrame:SetPoint("CENTER", UIParent, "CENTER")
    configFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    configFrame:EnableMouse(true); configFrame:SetMovable(true); configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", function() this:StartMoving() end); configFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end); configFrame:Hide()
    
    local closeBtn = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton"); closeBtn:SetPoint("TOPRIGHT", -5, -5); closeBtn:SetScript("OnClick", function() configFrame:Hide() end)
    local inputItem = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate"); inputItem:SetWidth(110); inputItem:SetHeight(20); inputItem:SetPoint("TOPLEFT", 20, -40); inputItem:SetAutoFocus(false); inputItem:SetText("Item Name")
    local inputTo = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate"); inputTo:SetWidth(100); inputTo:SetHeight(20); inputTo:SetPoint("LEFT", inputItem, "RIGHT", 10, 0); inputTo:SetAutoFocus(false); inputTo:SetText("Recipient")
    local btnAdd = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate"); btnAdd:SetWidth(40); btnAdd:SetHeight(20); btnAdd:SetPoint("LEFT", inputTo, "RIGHT", 5, 0); btnAdd:SetText("Add")
    btnAdd:SetScript("OnClick", function() if inputItem:GetText() ~= "" then BankRouterDB.routes[inputItem:GetText()] = inputTo:GetText(); inputItem:SetText(""); RefreshConfigList() end end)
    
    local scrollFrame = CreateFrame("ScrollFrame", "BankRouterScroll", configFrame, "UIPanelScrollFrameTemplate"); scrollFrame:SetPoint("TOPLEFT", 20, -75); scrollFrame:SetWidth(240); scrollFrame:SetHeight(240)
    scrollChild = CreateFrame("Frame", nil, scrollFrame); scrollChild:SetWidth(240); scrollChild:SetHeight(10); scrollFrame:SetScrollChild(scrollChild)
    RefreshConfigList()
end

local mmBtn = CreateFrame("Button", "BankRouterMinimapBtn", Minimap)
mmBtn:SetFrameStrata("LOW"); mmBtn:SetWidth(32); mmBtn:SetHeight(32); mmBtn:SetPoint("CENTER", Minimap, "CENTER", -60, -60)
local icon = mmBtn:CreateTexture(nil, "BACKGROUND"); icon:SetTexture("Interface\\Icons\\INV_Letter_15"); icon:SetWidth(20); icon:SetHeight(20); icon:SetPoint("CENTER", 0, 0)
local border = mmBtn:CreateTexture(nil, "OVERLAY"); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetWidth(52); border:SetHeight(52); border:SetPoint("TOPLEFT", 0, 0)
mmBtn:SetScript("OnClick", function() BankRouter_InitDB(); CreateConfigFrame(); if configFrame:IsVisible() then configFrame:Hide() else configFrame:Show() end end)

local btn = CreateFrame("Button", "BankRouterBtn", MailFrame, "UIPanelButtonTemplate")
btn:SetWidth(120); btn:SetHeight(25); btn:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -50, -40); btn:SetText("Auto Route")
btn:SetScript("OnClick", function() if processing then processing = false; Print("Stopped.") else ScanBagsAndQueue() end end)

local original_MailFrameTab_OnClick = MailFrameTab_OnClick
function MailFrameTab_OnClick(tab)
    original_MailFrameTab_OnClick(tab)
    if not tab then tab = this:GetID() end
    if tab == 1 then BankRouterBtn:Show() else BankRouterBtn:Hide() end
end