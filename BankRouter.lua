-- =============================================================
-- BANKROUTER v1.7 (FIXED TIMING)
-- Fix: Added explicit 0.3s delay after tab switch to ensure 
-- the mail slot is ready to receive items.
-- =============================================================

-- CONFIGURATION & STATE
-- -------------------------------------------------------------
local mailQueue = {}
local processing = false
local currentState = "IDLE" 
local currentWork = nil
local eventFrame = CreateFrame("Frame")
local delayTimer = 0 -- Timer for our pause state
local configFrame, scrollChild

-- UTILITIES
-- -------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[BankRouter]|r " .. msg)
end

local function Debug(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[DEBUGV2]|r " .. msg)
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

local function RunStateMachine(elapsed)
    
    -- SAFETY CHECK
    if not MailFrame:IsVisible() then
        processing = false
        currentState = "IDLE"
        Print("Mailbox closed. Stopping.")
        return
    end

    -- STATE: WAIT_DELAY
    -- This acts as a 'Sleep' function to let the UI catch up
    if currentState == "WAIT_DELAY" then
        delayTimer = delayTimer - elapsed
        if delayTimer <= 0 then
            currentState = "ATTACH_ITEM" -- Resume work
        end
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
        
        Debug("Processing: " .. currentWork.name)
        currentState = "PREPARE_UI"
        return
    end

    -- STATE 2: PREPARE UI
    if currentState == "PREPARE_UI" then
        -- 1. Switch Tab if needed
        if not SendMailFrame:IsVisible() then
            Debug("Switching to Send Mail Tab...")
            MailFrameTab2:Click()
        end
        
        -- 2. Clean up UI
        SendMailNameEditBox:SetText("")
        SendMailSubjectEditBox:SetText("")
        SendMailBodyEditBox:SetText("")
        
        -- 3. Scrub Cursor/Slot
        ClearCursor()
        ClickSendMailItemButton()
        ClearCursor()
        
        -- 4. PAUSE! 
        -- We wait 0.3 seconds here to let the slot initialize.
        delayTimer = 0.3
        currentState = "WAIT_DELAY"
        return
    end

    -- STATE 3: ATTACH ITEM
    if currentState == "ATTACH_ITEM" then
        -- Pickup
        PickupContainerItem(currentWork.bag, currentWork.slot)
        
        -- Verify pickup
        if not CursorHasItem() then
            Debug("FAILED: Cursor empty. Retrying...")
            ClearCursor()
            currentState = "PREPARE_UI" -- Reset UI and try again
            return
        end
        
        -- Drop
        ClickSendMailItemButton()
        
        -- Verify Attachment
        if GetSendMailItem() then
            Debug("Success! Attached.")
            currentState = "SEND_MAIL"
        else
            Debug("FAILED: Item dropped but didn't stick.")
            ClearCursor() 
            currentState = "NEXT_ITEM" -- Skip this item to avoid infinite loop
        end
        return
    end

    -- STATE 4: SEND MAIL
    if currentState == "SEND_MAIL" then
        Debug("Sending to " .. currentWork.recipient)
        SendMail(currentWork.recipient, "", "")
        
        -- Wait for Server Event
        currentState = "WAITING_FOR_SERVER"
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
        Debug("Mail Sent!")
        currentState = "NEXT_ITEM"
        
    elseif event == "UI_ERROR_MESSAGE" then
        Debug("UI Error: " .. arg1)
        if arg1 == ERR_MAIL_TARGET_NOT_FOUND or arg1 == ERR_MAIL_MAILBOX_FULL then
            processing = false
            Print("Critical Error. Stopping.")
        else
            currentState = "NEXT_ITEM"
        end
    end
end)

eventFrame:SetScript("OnUpdate", function()
    if processing then
        RunStateMachine(arg1) -- arg1 is 'elapsed' time since last frame
    end
end)

-- =============================================================
-- UI SETUP
-- =============================================================

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
-- mmBtn Movement code omitted for brevity but logic is standard

local btn = CreateFrame("Button", "BankRouterBtn", MailFrame, "UIPanelButtonTemplate")
btn:SetWidth(120); btn:SetHeight(25); btn:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -50, -40); btn:SetText("Auto Route")
btn:SetScript("OnClick", function() if processing then processing = false; Print("Stopped.") else ScanBagsAndQueue() end end)

local original_MailFrameTab_OnClick = MailFrameTab_OnClick
function MailFrameTab_OnClick(tab)
    original_MailFrameTab_OnClick(tab)
    if not tab then tab = this:GetID() end
    if tab == 1 then BankRouterBtn:Show() else BankRouterBtn:Hide() end
end