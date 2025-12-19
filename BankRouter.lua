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
    ["Recipe"] = 1,  
    ["Miscellaneous"] = 1
}

local validSubs = {
    -- Trade Goods (Custom Categories)
    ["Cloth"] = 1,
    ["Metal"] = 1,
    ["Elemental"] = 1,
    ["Leather"] = 1,
    ["Herb"] = 1,
    ["Gem"] = 1,
    ["Stone"] = 1,
    ["Enchanting Material"] = 1,
    ["Cooking Ingredient"] = 1,
    ["Engineering Parts"] = 1,
    ["Misc Trade Goods"] = 1,

    -- Consumables (Custom Categories)
    ["Fish"] = 1,
    ["Food"] = 1,
    ["Drink"] = 1,
    ["Potion"] = 1,
    ["Scroll"] = 1,
    ["Bandage"] = 1,
    ["Item Enhancement"] = 1,
    ["Misc Consumable"] = 1,

    -- Armor (Custom & Passthrough)
    ["Cloth Armor"] = 1,
    ["Leather Armor"] = 1,
    ["Mail Armor"] = 1,
    ["Plate Armor"] = 1,
    ["Misc Armor"] = 1,
    ["Shields"] = 1,
    ["Idols"] = 1,
    ["Librams"] = 1,
    ["Totems"] = 1,

    -- Recipes (concatenated)
    ["Alchemy Recipe"] = 1,
    ["Blacksmithing Recipe"] = 1,
    ["Cooking Recipe"] = 1,
    ["Enchanting Recipe"] = 1,
    ["Engineering Recipe"] = 1,
    ["First Aid Recipe"] = 1,
    ["Leatherworking Recipe"] = 1,
    ["Tailoring Recipe"] = 1,

    -- Weapons (Passthrough)
    ["Bows"] = 1,
    ["Crossbows"] = 1,
    ["Daggers"] = 1,
    ["Guns"] = 1,
    ["Fishing Pole"] = 1,
    ["Fist Weapons"] = 1,
    ["One-Handed Axes"] = 1,
    ["One-Handed Maces"] = 1,
    ["One-Handed Swords"] = 1,
    ["Polearms"] = 1,
    ["Staves"] = 1,
    ["Thrown"] = 1,
    ["Two-Handed Axes"] = 1,
    ["Two-Handed Maces"] = 1,
    ["Two-Handed Swords"] = 1,
    ["Wands"] = 1,

    -- Other Passthroughs
    ["Bag"] = 1,
    ["Key"] = 1,
    ["Reagent"] = 1,
    ["Arrow"] = 1,
    ["Bullet"] = 1,
    ["Book"] = 1,
    ["Quest"] = 1,
    ["Devices"] = 1,
    ["Explosives"] = 1,
    ["Parts"] = 1,
    ["Miscellaneous"] = 1,
    
    -- Global Fallback
    ["Misc"] = 1
}


-- =============================================================
--  HELPER FUNCTIONS
-- =============================================================

local function RGBToHex(r, g, b)
    r = r or 1.0; g = g or 1.0; b = b or 1.0;
    return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

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

function FindItemId(name)
    -- 1. Attempt to resolve the name to an ID using the new database
    local id = nil
    if BankRouterItemDB then
        id = BankRouterItemDB[name]
    end
    if (not id) then
        for bag = 0, 4 do
            for slot = 1, GetContainerNumSlots(bag) do

                local texture = GetContainerItemInfo(bag, slot)
                
                if texture then
                    local link = GetContainerItemLink(bag, slot)
                    if link and GetItemNameFromLink(link) == name then
                        local _, _, idStr = string.find(link, "item:(%d+)")
                        id=tonumber(idStr)
                    end
                end
            end
        end
    end

    return id
end

local function GetLinkFromID(id)
    if not id then return nil end
    
    -- Get name and quality from the API
    local name, _, rarity = GetItemInfo(id)
    
    if name then
        -- Get the hex color code for the quality (e.g., Blue = 0070dd)
        local r, g, b = GetItemQualityColor(rarity)
        local hex=RGBToHex(r, g, b)
        
        -- Construct the full clickable Hyperlink
        -- Format: |c<Color>|H<ItemString>|h[<Name>]|h|r
        return string.format("%s|Hitem:%d:0:0:0|h[%s]|h|r", hex, id, name)
    else
        -- Fallback if item is not in cache (return just the raw string or nil)
        return "item:"..id..":0:0:0"
    end
end

local function stringContains(target, ...)
    for i = 1, arg.n do
        if string.find(target, arg[i]) then
            return true
        end
    end
    return false
end

local function DetectSmartSubCategory(name, texture, type, realSubType)
    if not name or not texture then return nil end
    
    local n = string.lower(name)
    local tex = string.lower(texture)
    local sub = realSubType and string.lower(realSubType) or ""

    if stringContains(sub, "bag", "key", "reagent", "arrow", "book", "bullet", "quest", 
        "devices", "explosives", "parts", "bows", "crossbows", "daggers", "guns", 
        "fishing pole", "fist weapons", "miscellaneous", "shields", "idols", "librams", "totems",
        "one-handed axes", "one-handed maces", "one-handed swords", 
        "polearms", "staves", "thrown", 
        "two-handed axes", "two-handed maces", "two-handed swords", "wands") then
        return realSubType
    
    elseif type == "Recipe" and stringContains(sub, "alchemy", "blacksmithing", "cooking", "enchanting", "engineering", "first aid", "leatherworking", "tailoring") then
        return realSubType .. " Recipe"

    elseif type == "Armor" then
        if stringContains(sub, "cloth", "leather", "mail", "plate") then
            return realSubType .. " Armor"
        end

        return "Misc Armor"

    elseif type == "Consumable" then
        if stringContains(n, "bandage") then
            return "Bandage"

        elseif stringContains(tex, "stone_sharpening") or stringContains(n, "weightstone", "sharpening", "weapon oil") then
            return "Item Enhancement"

        elseif stringContains(tex, "potion", "elixir", "flask") or stringContains(n, "potion", "elixir", "flask") then
            return "Potion"
            
        elseif stringContains(tex, "scroll") or stringContains(n, "scroll") then
            return "Scroll"

        elseif stringContains(tex, "fish") then 
            return "Fish"

        elseif stringContains(tex, "food", "meat", "fish", "bread", "cheese", "misc_bowl") then
            return "Food"
         
        elseif stringContains(tex, "drink", "water", "juice", "tea") then
            return "Drink"
        end

        return "Misc Consumable"
    elseif type == "Trade Goods" then
        
        -- A. Cloth (Prioritize specific fabrics)
        if stringContains(tex, "fabric", "cloth", "bolt") or stringContains(n, "cloth", "bolt", "weave", "linen", "wool", "silk", "mageweave", "runecloth", "felcloth") then
            return "Cloth"
        
        -- B. Enchanting (Check this BEFORE Gems to catch 'Nexus Crystal' or 'Large Brilliant Shard')
        elseif stringContains(tex, "dust", "essence", "shard") or stringContains(n, "dust", "essence", "shard", "nexus crystal") then
            return "Enchanting Material"

        -- C. Herbs
        elseif stringContains(tex, "herb", "flower") or stringContains(n, "lotus", "bloom", "weed", "root", "leaf", "grass", "kelp", "mushroom", "fungus") then
            return "Herb"

        -- D. Leather / Skins
        elseif stringContains(tex, "leather") or stringContains(n, "leather", "hide", "scale", "pelt") then
            return "Leather"

        -- E. Metals / Mining
        elseif stringContains(n, "ore", "bar", "bronze", "iron", "mithril", "thorium", "copper", "silver", "gold", "truesilver", "arcanite") or stringContains(tex, "ore", "bar") then
            return "Metal"

        -- F. Elementals (Volatiles, Essences, Hearts, Globes)
        elseif stringContains(tex, "fire", "nature", "frost", "shadow") or stringContains(n, "elemental", "volatile", "essence of", "heart of", "globe of", "core of", "breath of") then
            return "Elemental"

        -- G. Gems (Expanded list)
        elseif stringContains(tex, "gem") or stringContains(n, "gem", "moonstone", "crystal", "emerald", "ruby", "sapphire", "opal", "diamond", "pearl", "garnet", "jade", "agate", "citrine") then
            return "Gem"

        -- H. Stone (Strict filtering to avoid Hearthstones or Sharpening stones)
        elseif (stringContains(tex, "stone") or stringContains(n, "stone", "rock")) and not stringContains(tex, "gem") and not stringContains(n, "moon", "hearth", "sharpening", "weight") then
            return "Stone"

        -- I. Cooking Ingredients (Meat, Eggs, Spices)
        elseif stringContains(n, "meat", "egg", "flesh", "spider", "spice", "seasoning") or stringContains(tex, "meat", "egg", "fish") then
            return "Cooking Ingredient"
            
        -- J. Engineering Parts (Catch-all for tubes, blasting powder, etc.)
        elseif stringContains(n, "tube", "trigger", "powder", "dynamite", "bomb", "casing", "gear", "gyro", "plug", "converter", "battery") then
            return "Engineering Parts"
        end

        return "Misc Trade Goods"
    end

    -- 5. Fallback
    return "Misc"
end


local function IsItemSoulbound(id)
    if not id then return false end

    -- 1. Check if the item is in the local cache
    local name, _ = GetItemInfo(id)
    if not name then 
        -- If the item isn't cached, we can't determine its binding status yet
        return false 
    end

    -- 2. Clear and set the tooltip using the Item ID
    BR_Scanner:ClearLines()
    local _, _, cleanLink = string.find(GetLinkFromID(id), "|H(.+)|h")
    BR_Scanner:SetHyperlink(cleanLink)

    -- 3. Scan the tooltip lines for the BoP text
    for i = 1, BR_Scanner:NumLines() do
        local line = _G["BankRouterScannerTextLeft"..i]
        if line then
            local text = line:GetText()
            -- ITEM_BIND_ON_PICKUP is a global localized string ("Binds when picked up")
            if text and (text == ITEM_BIND_ON_PICKUP or text == "Soulbound" or text == "Quest Item") then
                return true
            end
        end
    end

    return false
end

--returns link, type, subType, soulbound, id, rarity, level, minlevel, stackCount, equipLoc, texture, sellPrice
local function GetItemDetails(name)

    local id = FindItemId(name)
    if not id then return nil, nil, nil end

    local _, _, rarity, level, type, realSubType, stackSize, equipLoc, texture = GetItemInfo(id)

    local link = GetLinkFromID(id)

    local soulbound = IsItemSoulbound(id)
    -- 4. === HEURISTIC REFINEMENT ===
    -- Only run heuristics if it's a generic "Trade Good" to avoid misclassifying Armor/Weapons
    local subType = "undefined"
    if type and texture then
        local detected = DetectSmartSubCategory(name, texture, type, realSubType)
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
        InitHooks()
        Print("Loaded.")
    end
end)