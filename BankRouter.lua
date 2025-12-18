-- =============================================================
-- BANKROUTER
-- Automated Item Mailing for Turtle WoW (Vanilla 1.12.1)
-- =============================================================

-- CONFIGURATION
-- -------------------------------------------------------------
-- Define which items go to which character.
-- Format: ["Item Name"] = "CharacterName",
local config = {
    ["Runecloth"]    = "ClothBankToon",
    ["Thorium Ore"]  = "OreBankToon",
    ["Light Leather"]= "LeatherToon",
    ["Strange Dust"] = "EnchantToon",
}

-- Time in seconds between mails to avoid server disconnects.
-- 1.0 is safe. 0.5 is risky.
local MAIL_DELAY = 1.0 

-- STATE VARIABLES
-- -------------------------------------------------------------
local mailQueue = {}       -- Holds the list of items to send
local processing = false   -- Is the addon currently working?
local timerFrame = CreateFrame("Frame")
local timeSinceLast = 0

-- UTILITIES
-- -------------------------------------------------------------
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[BankRouter]|r " .. msg)
end

-- LOGIC: SCANNING
-- -------------------------------------------------------------
local function ScanBagsAndQueue()
    mailQueue = {} -- Clear previous queue
    
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                -- Extract item name from the link string
                local itemName = string.match(link, "%[(.*)%]")
                
                -- Check if this item is in our config list
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
        Print("Found " .. count .. " items to route. Starting...")
        processing = true
    else
        Print("No configured items found in bags.")
    end
end

-- LOGIC: PROCESSING LOOP
-- -------------------------------------------------------------
timerFrame:SetScript("OnUpdate", function()
    if not processing then return end

    -- Update timer
    timeSinceLast = timeSinceLast + arg1
    if timeSinceLast < MAIL_DELAY then return end
    
    -- Reset timer
    timeSinceLast = 0

    -- Safety Check: Is Mail Frame still open?
    if not MailFrame:IsVisible() then
        processing = false
        Print("Mailbox closed. Stopping.")
        return
    end

    -- Process next item
    local work = table.remove(mailQueue, 1)
    if work then
        -- 1. Clear fields
        SendMailNameEditBox:SetText("")
        SendMailSubjectEditBox:SetText("")
        
        -- 2. Ensure we are on the Send Mail tab
        MailFrameTab2:Click()
        
        -- 3. Pickup and attach item
        PickupContainerItem(work.bag, work.slot)
        ClickSendMailItemButton()
        
        -- 4. Send
        SendMail(work.recipient, work.name, "BankRouter Auto-Send")
        
        Print("Sent " .. work.name .. " to " .. work.recipient)
    else
        -- Queue empty
        processing = false
        Print("All items sent!")
    end
end)

-- UI: BUTTON CREATION
-- -------------------------------------------------------------
local btn = CreateFrame("Button", "BankRouterBtn", MailFrame, "UIPanelButtonTemplate")
btn:SetWidth(120)
btn:SetHeight(25)
btn:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -50, -40)
btn:SetText("Auto Route")

btn:SetScript("OnClick", function()
    if processing then
        processing = false
        Print("Stopped.")
    else
        ScanBagsAndQueue()
    end
end)

Print("Loaded. Open a mailbox to use.")