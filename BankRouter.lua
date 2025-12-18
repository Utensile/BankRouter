-- Namespace and Event Handling
local AddonName = "BankRouter"
local BR = CreateFrame("Frame")
BR:RegisterEvent("ADDON_LOADED")

--Hidden tooltip for SoulBound detection
local BR_Scanner = CreateFrame("GameTooltip", "BankRouterScanner", nil, "GameTooltipTemplate")
BR_Scanner:SetOwner(WorldFrame, "ANCHOR_NONE")

local validCats = {
    -- Standard Types
    ["Trade Goods"] = 1,
    ["Consumable"] = 1,
    ["Reagent"] = 1,
    ["Armor"] = 1,
    ["Weapon"] = 1,
    ["Container"] = 1,
    ["Quiver"] = 1,
    ["Projectile"] = 1,
    ["Quest"] = 1,
    ["Key"] = 1,
    ["Miscellaneous"] = 1,
    ["Recipe"] = 1,      -- Sometimes returned as the type itself
    
    -- Profession Types (Recipes often use these as the Main Type)
    ["Alchemy"] = 1,
    ["Blacksmithing"] = 1,
    ["Cooking"] = 1,
    ["Enchanting"] = 1,
    ["Engineering"] = 1,
    ["First Aid"] = 1,
    ["Leatherworking"] = 1,
    ["Mining"] = 1,
    ["Tailoring"] = 1,
    -- ["Jewelcrafting"] = 1, -- Only include if playing TBC/TurtleWoW custom
}

local validSubs = {
    ["Cloth"] = 1,
    ["Stone"] = 1,
    ["Metal"] = 1,
    ["Meat"] = 1,
    ["Leather"] = 1,
    ["Herb"] = 1,
    ["Gem"] = 1,
    ["Enchanting"] = 1,
    ["Potion"] = 1,
    ["Recipe"] = 1,
    ["Misc"] = 1
}


-- =============================================================
--  HELPER FUNCTIONS
-- =============================================================

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[BankRouter]|r " .. msg)
end

local function Debug(msg)
    if(BankRouterDB.debug) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Debug]|r " .. msg)
    end
end

local function Wait(seconds, callback)
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

local function GetItemNameFromLink(link)
    if not link then return nil end
    local _, _, name = string.find(link, "%[(.+)%]")
    return name
end

local function FindItemLink(targetName)
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            -- GetTexture is return value #1 from GetContainerItemInfo
            local texture, _, _ = GetContainerItemInfo(bag, slot)
            
            if texture then
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local name = GetItemNameFromLink(link)
                    if name == targetName then
                        -- Return BOTH the link and the texture we found
                        return link, texture, bag, slot
                    end
                end
            end
        end
    end
    return nil, nil, nil ,nil
end

local function DetectSmartSubCategory(name, texture, type)
    if not name or not texture then return nil end
    
    local n = string.lower(name)
    local tex = string.lower(texture)
    
    if string.find(tex, "fabric") or string.find(tex, "cloth") or string.find(n, "cloth") then
        return "Cloth"
        
    elseif (string.find(tex, "stone") or string.find(n, "stone")) and (( not (string.find(tex, "gem"))) or (not (string.find(n, "moon")))) then
        return "Stone"

    elseif string.find(n, "ore") or string.find(tex, "ore") or string.find(tex, "bar") or string.find(n, "bar") then
        return "Metal"
    
    elseif string.find(n, "meat") or string.find(tex, "meat") then
        return "Meat"
        
    elseif string.find(tex, "leather") or string.find(n, "leather") or string.find(n, "hide") or string.find(n, "scale") then
        return "Leather"
        
    elseif string.find(tex, "herb") or string.find(tex, "flower") then
        return "Herb"
        
    elseif type=="Trade Goods" and (string.find(tex, "gem") or string.find(tex, "moonstone") or string.find(tex, "crystal") or string.find(n, "gem") or string.find(n, "moonstone") or string.find(n, "crystal")) then
        return "Gem"
        
    elseif string.find(tex, "dust") or string.find(tex, "essence") or string.find(tex, "shard") then
        return "Enchanting"
        
    elseif string.find(tex, "potion") or string.find(tex, "elixir") or string.find(tex, "flask") or string.find(n, "potion") or string.find(n, "elixir") or string.find(n, "flask") then
        return "Potion"
    
    elseif type~="Consumable" and (string.find(tex, "scroll") or string.find(tex, "note")) then
        return "Recipe"
    end
    
    return "Misc"
end


local function IsItemSoulbound(name)
    local _, _, bag, slot = FindItemLink(name)
    BR_Scanner:ClearLines()
    BR_Scanner:SetBagItem(bag, slot)
    
    -- Scan the first 5 lines (Soulbound status is always at the top)
    for i = 1, 5 do
        local textLeft = _G["BankRouterScannerTextLeft"..i]
        if textLeft then
            local text = textLeft:GetText()
            -- Check for the global string (Localized) or the hardcoded English word
            if text and (text == ITEM_BIND_ON_PICKUP or text == "Soulbound" or text == "Quest Item") then
                return true
            end
        end
    end
    return false
end

--returns link, type, subType, soulbound, id, rarity, level, minlevel, stackCount, equipLoc, texture, sellPrice
local function GetItemDetails(name)
    -- 1. Scan bags to get Link AND Texture
    local link, bagTexture = FindItemLink(name)
    if not link then return nil, nil, nil end

    -- 2. Extract ID
    local _, _, id = string.find(link, "item:(%d+)")
    if not id then return nil, nil, nil end

    -- 3. Get Info
    local _, _, rarity, level, type, realSubType, stackSize, equipLoc, texture = GetItemInfo(id)
    local soulbound = IsItemSoulbound(name)
    -- 4. === HEURISTIC REFINEMENT ===
    -- Only run heuristics if it's a generic "Trade Good" to avoid misclassifying Armor/Weapons
    local subType = "undefined"
    if type and bagTexture then
        local detected = DetectSmartSubCategory(name, bagTexture, type)
        if detected then
            subType = detected
        end
    end
    -- ============================
    return link, type, subType, soulbound, id, rarity, level, realSubType, stackSize, equipLoc, texture end

local function DebugItemInfo(name)
    if not name then 
        Debug("DebugItemInfo: Input is nil") 
        return 
    end

    local link, type, subType, soulbound, id, rarity, level, realSubType, stackSize, equipLoc, texture = GetItemDetails(name)
    -- 5. Print EVERYTHING
    
    Debug("-------------------------------------------")
    Debug("FULL REPORT FOR: " .. (link or "nil"))
    Debug("ID: " .. (id or "nil"))
    Debug("Name: " .. (name or "nil"))
    Debug("-------------------------------------------")
    Debug("ITEM DETAILS:")
    Debug("• Rarity: " .. (rarity or "nil"))
    Debug("• Level: " .. (level or "nil"))
    Debug("• Stack Size: " .. (stackSize or "nil"))
    Debug("• Equipment Location: " .. (equipLoc or "nil"))
    Debug("• Texture: " .. (texture or "nil"))
    Debug("• Soulbound: " .. (tostring(soulbound) or "nil"))
    Debug("-------------------------------------------")
    Debug("CATEGORIZATION:")
    Debug("   Category: " .. "|cff00ff00" .. (type or "nil") .. "|r")
    Debug("   SubCategory: " .. "|cff66ccff" .. (subType or "nil") .."["..(realSubType or "nil").."]".. "|r")
    Debug("-------------------------------------------")
end

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

local function ColorText(text, colorType)
    if colorType == "cat" then return "|cff00ff00" .. text .. "|r" end       -- Green
    if colorType == "sub" then return "|cff66ccff" .. text .. "|r" end       -- Light Blue
    if colorType == "item" then return "|cffffd100" .. text .. "|r" end      -- Yellow
    return text
end

-- =============================================================
--  LOGIC
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
        if(IsShiftKeyDown() and button == "LeftButton") then
            if(BankRouterDB.debug) then
                local bag = this:GetParent():GetID()
                local slot = this:GetID()
                local link = GetContainerItemLink(bag, slot)
                local name = GetItemNameFromLink(link)
                if name then
                    DebugItemInfo(name)
                end
            end
            if BankRouterFrame and BankRouterFrame:IsVisible() then
                -- Get the item info from the button that was clicked
                local bag = this:GetParent():GetID()
                local slot = this:GetID()
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local name = GetItemNameFromLink(link)
                    if name then
                        -- Update the Input Field
                        BankRouterItemInput:SetText(name)
                        -- Move focus to Recipient field for faster entry
                        BankRouterRecInput:SetFocus()
                        Debug("Auto-filled: " .. name)
                        
                        -- CRITICAL: Return here to BLOCK the item from being picked up
                        return 
                    end
                end
            end
        end
        -- 3. If the window wasn't open (or it wasn't a left click), run the original code
        if BR_Orig_ContainerFrameItemButton_OnClick then
            BR_Orig_ContainerFrameItemButton_OnClick(button, ignoreShift)
        end
    end
end

local function UpdateRouteList(scrollChild)
    -- 1. Clear existing
    local kids = {scrollChild:GetChildren()}
    for _, child in ipairs(kids) do child:Hide(); child:SetParent(nil) end

    -- 2. Sort Logic
    local sorted = {}
    for key, recipient in pairs(BankRouterDB.routes) do
        local display, sortKey, colorType
        
        -- Detect Rule Type based on prefix
        if string.sub(key, 1, 2) == "c:" then
            display = string.sub(key, 3)
            sortKey = "3_" .. display -- Cats last in sort
            colorType = "cat"
        elseif string.sub(key, 1, 2) == "s:" then
            display = string.sub(key, 3)
            sortKey = "2_" .. display -- Subs middle
            colorType = "sub"
        else
            display = key
            sortKey = "1_" .. display -- Items first (Specifics)
            colorType = "item"
        end
        
        table.insert(sorted, {
            rawKey = key, 
            display = display, 
            recipient = recipient, 
            sort = sortKey,
            cType = colorType
        })
    end

    -- Sort: Recipient -> Priority (Item > Sub > Cat)
    table.sort(sorted, function(a, b)
        if a.recipient == b.recipient then
            return a.sort < b.sort
        else
            return a.recipient < b.recipient
        end
    end)

    -- 3. Render
    local yOffset = 0
    for _, route in ipairs(sorted) do
        local row = CreateFrame("Button", nil, scrollChild)
        row:SetWidth(280)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)

        -- Delete Button
        local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        delBtn:SetWidth(20); delBtn:SetHeight(20)
        delBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        delBtn:SetText("X")
        
        -- CRITICAL FIX: Store the key on the button itself
        delBtn.sortKey = route.rawKey 
        
        delBtn:SetScript("OnClick", function()
            -- Retrieve the key from 'this' (the button clicked)
            local keyToDelete = this.sortKey
            if keyToDelete then
                BankRouterDB.routes[keyToDelete] = nil
                UpdateRouteList(scrollChild)
            end
        end)

        -- Rule Text (Left)
        local ruleText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ruleText:SetPoint("LEFT", row, "LEFT", 0, 0)
        ruleText:SetWidth(160)
        ruleText:SetJustifyH("LEFT")
        
        -- Apply Color
        ruleText:SetText(ColorText(route.display, route.cType))
        
        -- Tooltip for Items only
        if route.cType == "item" then
            -- Find the full link in bags
            local fullLink, _ = FindItemLink(route.display)
            
            if fullLink then
                -- FIX: Extract ONLY the 'item:1234:...' part
                -- The pattern captures everything between |H and |h
                local _, _, cleanLink = string.find(fullLink, "|H(.+)|h")
                
                -- Use the clean link if found, otherwise fallback (safer)
                row.tipLink = cleanLink or fullLink 

                row:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
                    -- This now passes "item:1234:..." which makes AtlasLoot happy
                    GameTooltip:SetHyperlink(this.tipLink) 
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        end

        -- Recipient (Right)
        local recText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        recText:SetPoint("RIGHT", delBtn, "LEFT", -5, 0)
        recText:SetWidth(80)
        recText:SetJustifyH("RIGHT")
        local colorHex = GetRecipientColor(route.recipient)
        recText:SetText(colorHex .. route.recipient .. "|r")

        yOffset = yOffset - 22
    end
end

local function PrepareNextBatch()
    -- Safety Check
    if SendMailSubjectEditBox:GetText() ~= "" then
        Print("Mailbox is busy.")
        return
    end

    local myName = UnitName("player")
    local targetRecipient = nil
    local targetSubject = nil
    local itemsToAttach = {}
    
    -- Scan Bags
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local texture, count, locked = GetContainerItemInfo(bag, slot)
            
            if texture and not locked then
                local link = GetContainerItemLink(bag, slot)
                local name = GetItemNameFromLink(link)
                
                -- === PRIORITY LOOKUP ===
                local recipient = nil
                if(not IsItemSoulbound(name)) then
                    -- 1. Check Specific Item Rule (Highest Priority)
                    if BankRouterDB.routes[name] then
                        recipient = BankRouterDB.routes[name]
                        Debug("Match Item: " .. name .. " to " .. recipient)
                    else
                        local _, type, subType = GetItemDetails(name)
                        
                        -- 2. Check Subcategory Rule (Medium Priority)
                        if subType and BankRouterDB.routes["s:" .. subType] then
                            recipient = BankRouterDB.routes["s:" .. subType]
                            Debug("Match SubCat: " .. name .." - ".. subType .. " to " .. recipient)
                            
                        -- 3. Check Category Rule (Lowest Priority)
                        elseif type and BankRouterDB.routes["c:" .. type] then
                            recipient = BankRouterDB.routes["c:" .. type]
                            Debug("Match Cat: " .. name .." - ".. type .. " to " .. recipient)
                        end
                    end
                end
                -- === BATCHING LOGIC ===
                if recipient and recipient ~= myName then
                    -- If we haven't picked a target yet, lock it in
                    if not targetRecipient then
                        targetRecipient = recipient
                        targetSubject = name -- Subject is just the first item found
                    end
                    
                    -- If this item matches our current target batch, add it
                    if recipient == targetRecipient then
                        if table.getn(itemsToAttach) < 12 then
                            table.insert(itemsToAttach, {bag=bag, slot=slot})
                        end
                    end
                end
            end
        end
    end

    if not targetRecipient then
        Print("No routable items found.")
        return
    end

    -- Send Logic (Same as before)
    if MailFrameTab2 then MailFrameTab2:Click() end
    SendMailNameEditBox:SetText(targetRecipient)
    SendMailSubjectEditBox:SetText("BankRouter: " .. targetSubject)
    
    local count = 0
    for _, item in ipairs(itemsToAttach) do
        UseContainerItem(item.bag, item.slot)
        count = count + 1
    end
    
    Print("Prepared batch for " .. targetRecipient .. " (" .. count .. " items).")
    
    if BankRouterDB.autoSend and TurtleMail and TurtleMail.send_mail_button_onclick then
        Wait(0.2, function ()
            TurtleMail.send_mail_button_onclick()
            Wait(1, function () PrepareNextBatch() end)
        end)
    end
end

-- =============================================================
--  GUI
-- =============================================================

local function CreateConfigFrame()
    -- 1. Main Frame
    local f = CreateFrame("Frame", "BankRouterFrame", UIParent)
    f:SetWidth(380) -- Widened for new checkboxes
    f:SetHeight(500)
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
    subtitle:SetText("(Shift+Click an item to use as template)")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    -- 2. Input Fields
    local itemInput = CreateFrame("EditBox", "BankRouterItemInput", f, "InputBoxTemplate")
    itemInput:SetWidth(150)
    itemInput:SetHeight(20)
    itemInput:SetPoint("TOPLEFT", f, "TOPLEFT", 25, -60)
    itemInput:SetAutoFocus(false)
    
    local itemLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemLabel:SetPoint("BOTTOMLEFT", itemInput, "TOPLEFT", -5, 4)
    itemLabel:SetText("Item Name")

    local recInput = CreateFrame("EditBox", "BankRouterRecInput", f, "InputBoxTemplate")
    recInput:SetWidth(120)
    recInput:SetHeight(20)
    recInput:SetPoint("LEFT", itemInput, "RIGHT", 20, 0)
    recInput:SetAutoFocus(false)

    local recLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recLabel:SetPoint("BOTTOMLEFT", recInput, "TOPLEFT", -5, 4)
    recLabel:SetText("Recipient Name")

    -- 3. NEW CHECKBOXES (Categories)
    local catCB = CreateFrame("CheckButton", "BankRouterCatCheck", f, "UICheckButtonTemplate")
    catCB:SetPoint("TOPLEFT", itemInput, "BOTTOMLEFT", -5, -10)
    _G[catCB:GetName().."Text"]:SetText("Set Category")
    _G[catCB:GetName().."Text"]:SetTextColor(0, 1, 0) -- Green Text

    local subCatCB = CreateFrame("CheckButton", "BankRouterSubCatCheck", f, "UICheckButtonTemplate")
    subCatCB:SetPoint("LEFT", catCB, "RIGHT", 160, 0)
    _G[subCatCB:GetName().."Text"]:SetText("Set Subcategory")
    _G[subCatCB:GetName().."Text"]:SetTextColor(0.4, 0.8, 1) -- Light Blue Text
    

    
    -- Init state
    _G[BankRouterSubCatCheck:GetName().."Text"]:SetTextColor(0.4, 0.8, 1)


    -- 4. Global Settings (Auto Send / Debug)
    local autoSendCB = CreateFrame("CheckButton", "BankRouterAutoSendCheck", f, "UICheckButtonTemplate")
    autoSendCB:SetPoint("TOPLEFT", catCB, "BOTTOMLEFT", 0, -10)
    _G[autoSendCB:GetName().."Text"]:SetText("Auto Send")
    autoSendCB:SetChecked(BankRouterDB.autoSend)
    autoSendCB:SetScript("OnClick", function() BankRouterDB.autoSend = this:GetChecked() end)

    local debugCB = CreateFrame("CheckButton", "BankRouterDebugCheck", f, "UICheckButtonTemplate")
    debugCB:SetPoint("LEFT", autoSendCB, "RIGHT", 100, 0)
    _G[debugCB:GetName().."Text"]:SetText("Debug Mode")
    debugCB:SetChecked(BankRouterDB.debug)
    debugCB:SetScript("OnClick", function() BankRouterDB.debug = this:GetChecked() end)


    -- 5. Add/Update Button
    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetWidth(250)
    addBtn:SetHeight(25)
    addBtn:SetPoint("TOP", f, "TOP", 0, -160)
    addBtn:SetText("Add / Update Rule")

    -- 6. Scroll List
    local scrollFrame = CreateFrame("ScrollFrame", "BankRouterConfigScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -200)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -35, 15)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(300)
    scrollChild:SetHeight(300)
    scrollFrame:SetScrollChild(scrollChild)

    -- === ADD BUTTON LOGIC ===
    addBtn:SetScript("OnClick", function()
        local added = false
        local inputName = itemInput:GetText()
        local recipient = recInput:GetText()
        local useCat = BankRouterCatCheck:GetChecked()
        local useSub = BankRouterSubCatCheck:GetChecked()

        if inputName == "" or recipient == "" then
            Print("Error: Need Item Name and Recipient.")
            return
        end

        local _, type, subType, soulbound = GetItemDetails(inputName)

        if soulbound then
            Print("Error: Item is Soulbound.")
            return
        end

        if useCat or useSub then

            if(useCat and validCats[inputName]) then
                type=inputName
            end
            if(useSub and validSubs[inputName]) then
                subType=inputName
            end

            Debug("type: ".. (type or "nil") .. " and subType: "..(subType or "nil"))
            Debug(tostring(((not type) and useCat) and ((not subType) and useSub)))
            if ((not type) and useCat) or ((not subType) and useSub) then
                Print("Error: Could not determine category/subcategory. Is '"..inputName.."' a valid category or in your bag?")
                return
            end

            -- 2. Add Category Rule (Green)
            if useCat and type then
                BankRouterDB.routes["c:" .. type] = recipient
                added=true
                Print("Added Category Rule: " .. ColorText(type, "cat") .. " -> " .. recipient)
            end

            -- 3. Add Subcategory Rule (Blue)
            if useSub and subType then
                if subType and subType ~= "" then
                    BankRouterDB.routes["s:" .. subType] = recipient
                    added=true
                    Print("Added Subcat Rule: " .. ColorText(subType, "sub") .. " -> " .. recipient)
                else
                    Print("Warning: Item has no subcategory.")
                end
            end
        else
            -- 4. Default: Specific Item Rule (Yellow)
            BankRouterDB.routes[inputName] = recipient
            added=true
            Print("Added Item Rule: " .. ColorText(inputName, "item") .. " -> " .. recipient)
        end

        -- Reset & Refresh
        if(added) then
            itemInput:SetText("")
        end
        UpdateRouteList(scrollChild)
    end)

    f:SetScript("OnShow", function() UpdateRouteList(scrollChild) end)
end

local function CreateMailboxButton()
    -- 1. Stop if button already exists
    if _G["BankRouterPrepareButton"] then return end
    
    -- 2. Define parent
    local parent = MailFrame
    if not parent then return end

    local btn = CreateFrame("Button", "BankRouterPrepareButton", parent, "UIPanelButtonTemplate")
    btn:SetWidth(100)
    btn:SetHeight(25)
    btn:SetText("Prepare Batch")

    -- 3. SAFER ANCHORING
    -- We use the OBJECT directly (no quotes) because your debug confirmed it exists.
    -- We wrap it in pcall() to ignore any possible errors.
    local anchorTarget = SendMailMailButton 
    
    local success = pcall(function()
        if anchorTarget then
             -- PASS THE WIDGET TABLE, NOT THE STRING NAME
            btn:SetPoint("TOP", anchorTarget, "BOTTOMRIGHT", 20, -5)
        else
            error("Target is nil") -- Trigger fallback
        end
    end)

    -- 4. Fallback if the preferred anchor failed
    if not success then
        Debug("Preferred anchor failed. Using safe fallback position.")
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -35, 50)
    end
    
    btn:SetScript("OnClick", function()
        PrepareNextBatch()
    end)
end

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
--  LOAD EVENT
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