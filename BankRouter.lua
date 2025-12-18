-- =============================================================
-- BANKROUTER
-- Automated Item Mailing for Turtle WoW (Vanilla 1.12.1)
-- Logic: Event-driven + UI Visibility Fix
-- =============================================================

-- CONFIGURATION
-- -------------------------------------------------------------
local config = {
    ["Red Wolf Meat"]    = "Knabe",
    ["Silk Cloth"]  = "Knabe",
    ["Mageweave Cloth"]= "Knabe",
    ["Strange Dust"] = "EnchantToon",
}

-- STATE VARIABLES
-- -------------------------------------------------------------
local mailQueue = {}       -- Holds the list of items to send
local processing = false   -- Are we currently in the middle of a batch?
local pendingSend = false  -- Trigger for the OnUpdate loop
local eventFrame = CreateFrame("Frame")

-- UTILITIES
-- -------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[BankRouter]|r " .. msg)
end

-- UI BUTTON CREATION
-- (We create it early so we can reference it in functions)
-- -------------------------------------------------------------
local btn = CreateFrame("Button", "BankRouterBtn", MailFrame, "UIPanelButtonTemplate")
btn:SetWidth(120)
btn:SetHeight(25)
btn:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -50, -40)
btn:SetText("Auto Route")

-- CORE FUNCTIONS
-- -------------------------------------------------------------

-- 1. The function that physically sends the mail
local function ProcessNextItem()
    -- Safety check: Stop if mailbox closed
    if not MailFrame:IsVisible() then
        processing = false
        pendingSend = false
        Print("Mailbox closed. Stopping.")
        return
    end

    -- Get next item
    local work = table.remove(mailQueue, 1)

    if work then
        -- Clear fields
        SendMailNameEditBox:SetText("")
        SendMailSubjectEditBox:SetText("")
        SendMailBodyEditBox:SetText("") -- Clear body text
        
        -- Switch to Send tab (This will trigger our hook and hide the button)
        MailFrameTab2:Click()
        
        -- Pickup and attach
        PickupContainerItem(work.bag, work.slot)
        ClickSendMailItemButton()
        
        -- Send with NO body text
        SendMail(work.recipient, work.name, "") 
        
        Print("Sent " .. work.name .. " to " .. work.recipient)
        
    else
        -- Queue is empty
        processing = false
        pendingSend = false
        Print("All items sent!")
        -- Optional: Switch back to Inbox when done? 
        -- Uncomment the next line if you want it to return to Inbox automatically
        -- MailFrameTab1:Click() 
    end
end

-- 2. The Scanner
local function ScanBagsAndQueue()
    mailQueue = {} 
    
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local itemName = string.match(link, "%[(.*)%]")
                if config[itemName] then
                    table.insert(mailQueue, {
                        bag = bag,
                        slot = slot,
                        name = itemName,
                        recipient = config[itemName]
                    })
                end
            end
        end
    end

    local count = table.getn(mailQueue)
    if count > 0 then
        Print("Found " .. count .. " items. Sending first item...")
        processing = true
        ProcessNextItem() 
    else
        Print("No configured items found.")
    end
end

-- EVENT HANDLING
-- -------------------------------------------------------------
eventFrame:RegisterEvent("MAIL_SEND_SUCCESS")
eventFrame:RegisterEvent("UI_ERROR_MESSAGE")
eventFrame:RegisterEvent("MAIL_SHOW") -- Listen for mailbox opening

eventFrame:SetScript("OnEvent", function()
    -- 1. Reset Visibility on Open
    if event == "MAIL_SHOW" then
        if BankRouterBtn then BankRouterBtn:Show() end
        return
    end

    -- 2. Automation Logic
    if not processing then return end

    if event == "MAIL_SEND_SUCCESS" then
        pendingSend = true
        
    elseif event == "UI_ERROR_MESSAGE" then
        if arg1 == ERR_MAIL_TARGET_NOT_FOUND or arg1 == ERR_MAIL_MAILBOX_FULL then
            processing = false
            pendingSend = false
            Print("Error: " .. arg1 .. ". Stopping.")
        end
    end
end)

-- LOGIC LOOP
-- -------------------------------------------------------------
eventFrame:SetScript("OnUpdate", function()
    if processing and pendingSend then
        pendingSend = false
        ProcessNextItem()
    end
end)

-- BUTTON CLICK HANDLER
-- -------------------------------------------------------------
btn:SetScript("OnClick", function()
    if processing then
        processing = false
        pendingSend = false
        Print("Stopped.")
    else
        ScanBagsAndQueue()
    end
end)

-- HOOKS (VISIBILITY FIX)
-- -------------------------------------------------------------
-- We overwrite the Tab Click function to toggle our button
local original_MailFrameTab_OnClick = MailFrameTab_OnClick

function MailFrameTab_OnClick(tab)
    -- Run the original blizzard code first
    original_MailFrameTab_OnClick(tab)

    -- Now apply our logic
    if not tab then tab = this:GetID() end -- Handle case where tab isn't passed directly
    
    if tab == 1 then
        -- Inbox Tab: Show Button
        BankRouterBtn:Show()
    else
        -- Send Tab: Hide Button
        BankRouterBtn:Hide()
    end
end

Print("BankRouter (Main Tab Only) Loaded.")