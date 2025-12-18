-- =============================================================
-- BANKROUTER
-- Automated Item Mailing for Turtle WoW (Vanilla 1.12.1)
-- Logic adapted from TurtleMail (Event-driven instead of Timer)
-- =============================================================

-- CONFIGURATION
-- -------------------------------------------------------------
local config = {
    ["Runecloth"]    = "ClothBankToon",
    ["Thorium Ore"]  = "OreBankToon",
    ["Light Leather"]= "LeatherToon",
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
        
        -- Switch to Send tab
        MailFrameTab2:Click()
        
        -- Pickup and attach
        PickupContainerItem(work.bag, work.slot)
        ClickSendMailItemButton()
        
        -- Send
        SendMail(work.recipient, work.name, "BankRouter Auto-Send")
        Print("Sent " .. work.name .. " to " .. work.recipient)
        
        -- We remain in 'processing' state, but wait for the event to trigger the next one
    else
        -- Queue is empty
        processing = false
        pendingSend = false
        Print("All items sent!")
    end
end

-- 2. The Scanner (Starts the loop)
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
        ProcessNextItem() -- Send the first one immediately to start the chain
    else
        Print("No configured items found.")
    end
end

-- EVENT HANDLING
-- -------------------------------------------------------------
eventFrame:RegisterEvent("MAIL_SEND_SUCCESS")
eventFrame:RegisterEvent("UI_ERROR_MESSAGE")

eventFrame:SetScript("OnEvent", function()
    if not processing then return end

    if event == "MAIL_SEND_SUCCESS" then
        -- Success! Flag the OnUpdate loop to send the next one.
        -- We use a flag instead of calling directly to avoid stack overflow or script limits.
        pendingSend = true
        
    elseif event == "UI_ERROR_MESSAGE" then
        -- If we get an error (bag full, target not found), stop immediately.
        -- Common errors: ERR_MAIL_TARGET_NOT_FOUND, ERR_MAIL_MAILBOX_FULL
        if arg1 == ERR_MAIL_TARGET_NOT_FOUND or arg1 == ERR_MAIL_MAILBOX_FULL then
            processing = false
            pendingSend = false
            Print("Error encountered: " .. arg1 .. ". Stopping.")
        end
    end
end)

-- LOGIC LOOP
-- -------------------------------------------------------------
-- This mimics TurtleMail's 'on_update' check
eventFrame:SetScript("OnUpdate", function()
    if processing and pendingSend then
        pendingSend = false
        ProcessNextItem()
    end
end)

-- UI BUTTON
-- -------------------------------------------------------------
local btn = CreateFrame("Button", "BankRouterBtn", MailFrame, "UIPanelButtonTemplate")
btn:SetWidth(120)
btn:SetHeight(25)
btn:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -50, -40)
btn:SetText("Auto Route")

btn:SetScript("OnClick", function()
    if processing then
        processing = false
        pendingSend = false
        Print("Stopped.")
    else
        ScanBagsAndQueue()
    end
end)

Print("BankRouter (Event Mode) Loaded.")