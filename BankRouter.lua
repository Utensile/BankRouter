-- Namespace and Event Handling
local AddonName = "BankRouter"
local BR = CreateFrame("Frame")
BR:RegisterEvent("ADDON_LOADED")

--Hidden tooltip for SoulBound detection
local BR_Scanner = CreateFrame("GameTooltip", "BankRouterScanner", nil, "GameTooltipTemplate")
BR_Scanner:SetOwner(WorldFrame, "ANCHOR_NONE")

local validCats = {}
local validSubs = {}

for _, catEntry in ipairs(BankRouterData) do
    validCats[catEntry.name] = 1

    if catEntry.subs then
        for _, subName in ipairs(catEntry.subs) do
            validSubs[subName] = 1
        end
    end
end

local BankRouterMenuState = {}


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

local function FormattedText(text)
    if not text or text == "" then return text end

    text = string.lower(text)

    local result = string.gsub(text, "(%a)([%w_']*)", function(firstLetter, restOfWord)
        return string.upper(firstLetter) .. restOfWord
    end)

    return result
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
    return "Miscellaneous"
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
    for i = 2, math.min(3, BR_Scanner:NumLines()) do
        local line = _G["BankRouterScannerTextLeft"..i]
        if line then
            local text = line:GetText()
            -- ITEM_BIND_ON_PICKUP is a global localized string ("Binds when picked up")
            if text and (text == ITEM_BIND_ON_PICKUP or text == ITEM_BIND_QUEST or text == ITEM_SOULBOUND) then
                return true
            end
        end
    end

    return false
end

--returns link, type, subType, soulbound, id, rarity, level, realSubType, stackSize, equipLoc, texture
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

    -- 1. Hook ContainerFrameItemButton_OnClick (Your existing Click Hook)
    if not BR_Orig_ContainerFrameItemButton_OnClick then
        BR_Orig_ContainerFrameItemButton_OnClick = ContainerFrameItemButton_OnClick
    end

    ContainerFrameItemButton_OnClick = function(button, ignoreShift)
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
                local bag = this:GetParent():GetID()
                local slot = this:GetID()
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local name = GetItemNameFromLink(link)
                    if name then
                        BankRouterItemInput:SetText(name)
                        BankRouterRecInput:SetFocus()
                        Debug("Auto-filled: " .. name)
                        return 
                    end
                end
            end
        end
        if BR_Orig_ContainerFrameItemButton_OnClick then
            BR_Orig_ContainerFrameItemButton_OnClick(button, ignoreShift)
        end
    end

    -- 2. NEW: Hook GameTooltip.SetBagItem (Specific for Vanilla 1.12)
    -- We hook the method directly on the object table
    if not BR_Orig_SetBagItem then
        BR_Orig_SetBagItem = GameTooltip.SetBagItem
    end

    GameTooltip.SetBagItem = function(self, bag, slot)
        -- 1. Run the original function first so the item appears
        if BR_Orig_SetBagItem then
            BR_Orig_SetBagItem(self, bag, slot)
        end

        -- 2. Run our custom logic using the Bag/Slot arguments
        local link = GetContainerItemLink(bag, slot)
        if link then
            local name = GetItemNameFromLink(link)
            if name then
                local _, type, subType, _, _, _, _, _, stackSize= GetItemDetails(name)
                
                if type or subType then
                    self:AddLine(" ") -- Spacing
                    if type and subType then
                        self:AddLine(ColorText(type, "cat") .. ": " .. ColorText(subType, "sub"))
                    end
                    -- Force update
                    self:Show()
                end
            end
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
            local id = FindItemId(route.display)
            local fullLink, _ = GetLinkFromID(id)
            
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
    -- 1. Main Frame (Widened to 600 to accommodate side menu)
    local f = CreateFrame("Frame", "BankRouterFrame", UIParent)
    f:SetWidth(600) 
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

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -15)
    title:SetText("BankRouter Config")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)

    -- =============================================================
    --  LEFT SIDE: CATEGORY MENU
    -- =============================================================
    
    -- Menu Background container
    local menuBg = CreateFrame("Frame", nil, f)
    menuBg:SetWidth(190)
    menuBg:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -40)
    menuBg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 15, 15)
    menuBg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    menuBg:SetBackdropColor(0, 0, 0, 0.5)

    -- Menu Scroll Frame
    local menuScroll = CreateFrame("ScrollFrame", "BankRouterMenuScroll", menuBg, "UIPanelScrollFrameTemplate")
    menuScroll:SetPoint("TOPLEFT", menuBg, "TOPLEFT", 5, -5)
    menuScroll:SetPoint("BOTTOMRIGHT", menuBg, "BOTTOMRIGHT", -26, 5)

    local menuContent = CreateFrame("Frame", nil, menuScroll)
    menuContent:SetWidth(160)
    menuContent:SetHeight(400) -- Will update dynamically
    menuScroll:SetScrollChild(menuContent)

    -- Function to Draw the Tree View
    local function UpdateMenu()
        -- Clear existing children
        local kids = {menuContent:GetChildren()}
        for _, child in ipairs(kids) do child:Hide() end

        local yOffset = 0
        
        -- === ITERATE THE MASTER DATA STRUCTURE ===
        for _, cat in ipairs(BankRouterData) do
            if cat.subs then
                -- 1. Parent Button
                local btn = CreateFrame("Button", nil, menuContent)
                btn:SetWidth(160)
                btn:SetHeight(20)
                btn:SetPoint("TOPLEFT", menuContent, "TOPLEFT", 0, yOffset)
                
                local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                text:SetPoint("LEFT", btn, "LEFT", 5, 0)
                
                local hasSubs = (table.getn(cat.subs) > 0)
                local prefix = ""
                if hasSubs then
                    prefix = BankRouterMenuState[cat.name] and "[-] " or "[+] "
                else
                    prefix = "    " -- Indent if no children
                end

                text:SetText(prefix .. cat.name)
                btn:SetScript("OnEnter", function() text:SetTextColor(0.33, 1, 0.33) end)
                btn:SetScript("OnLeave", function() text:SetTextColor(1, 0.82, 0) end)

                -- === FIX: STORE DATA ON THE ELEMENT ===
                btn.catName = cat.name
                btn.hasSubs = hasSubs

                btn:SetScript("OnClick", function()
                    -- Retrieve data from 'this' (the button clicked)
                    local cName = this.catName
                    
                    -- Update Input Fields
                    if(IsShiftKeyDown()) then
                        BankRouterItemInput:SetText(cName)
                        BankRouterCatCheck:SetChecked(true)
                        BankRouterSubCatCheck:SetChecked(false)
                    elseif this.hasSubs then
                        BankRouterMenuState[cName] = not BankRouterMenuState[cName]
                        UpdateMenu()
                    end
                end)
                
                yOffset = yOffset - 20

                -- 2. Children (if expanded)
                if hasSubs and BankRouterMenuState[cat.name] then
                    for _, sub in ipairs(cat.subs) do
                        local subBtn = CreateFrame("Button", nil, menuContent)
                        subBtn:SetWidth(160)
                        subBtn:SetHeight(16)
                        subBtn:SetPoint("TOPLEFT", menuContent, "TOPLEFT", 15, yOffset)
                        
                        local subText = subBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        subText:SetPoint("LEFT", subBtn, "LEFT", 0, 0)
                        subText:SetText(sub)
                        
                        -- === FIX: STORE DATA ON THE ELEMENT ===
                        subBtn.subName = sub

                        subBtn:SetScript("OnClick", function()
                            BankRouterItemInput:SetText(this.subName)
                            BankRouterCatCheck:SetChecked(false)
                            BankRouterSubCatCheck:SetChecked(true)
                        end)
                        
                        subBtn:SetScript("OnEnter", function() subText:SetTextColor(0.33, 1, 0.33) end)
                        subBtn:SetScript("OnLeave", function() subText:SetTextColor(1, 1, 1) end)

                        yOffset = yOffset - 16
                    end
                end
            end
        end
        menuContent:SetHeight(math.abs(yOffset) + 20)
    end

    -- =============================================================
    --  RIGHT SIDE: CONFIGURATION
    -- =============================================================

    local rightStart = 220 -- X offset where the right pane starts

   -- 1. Inputs
    local itemInput = CreateFrame("EditBox", "BankRouterItemInput", f, "InputBoxTemplate")
    itemInput:SetWidth(200)
    itemInput:SetHeight(20)
    itemInput:SetPoint("TOPLEFT", f, "TOPLEFT", rightStart, -60)
    itemInput:SetAutoFocus(false)
    
    local itemLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    itemLabel:SetPoint("BOTTOMLEFT", itemInput, "TOPLEFT", -5, 4)
    itemLabel:SetText("Item / Category Name")

    local recInput = CreateFrame("EditBox", "BankRouterRecInput", f, "InputBoxTemplate")
    recInput:SetWidth(140)
    recInput:SetHeight(20)
    recInput:SetPoint("LEFT", itemInput, "RIGHT", 15, 0)
    recInput:SetAutoFocus(false)

    local recLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recLabel:SetPoint("BOTTOMLEFT", recInput, "TOPLEFT", -5, 4)
    recLabel:SetText("Recipient Name")

    -- 2. Checkboxes (Categories)
    local catCB = CreateFrame("CheckButton", "BankRouterCatCheck", f, "UICheckButtonTemplate")
    -- Anchor directly below ItemInput
    catCB:SetPoint("TOPLEFT", itemInput, "BOTTOMLEFT", -5, -10)
    _G[catCB:GetName().."Text"]:SetText("Set Category")
    _G[catCB:GetName().."Text"]:SetTextColor(0, 1, 0) 

    local subCatCB = CreateFrame("CheckButton", "BankRouterSubCatCheck", f, "UICheckButtonTemplate")
    subCatCB:SetPoint("LEFT", catCB, "RIGHT", 150, 0)
    _G[subCatCB:GetName().."Text"]:SetText("Set Subcategory")
    _G[subCatCB:GetName().."Text"]:SetTextColor(0.4, 0.8, 1) 

    -- 3. Add Button (In the Middle)
    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetWidth(150) 
    addBtn:SetHeight(25)
    -- Anchored below the Cat Checkbox
    addBtn:SetPoint("TOPLEFT", catCB, "BOTTOMLEFT", 5, -5)
    addBtn:SetText("Add / Update Rule")

    -- 4. Global Settings (Below the Add Button)
    local autoSendCB = CreateFrame("CheckButton", "BankRouterAutoSendCheck", f, "UICheckButtonTemplate")
    -- Anchored below the Add Button
    autoSendCB:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", -5, -10)
    _G[autoSendCB:GetName().."Text"]:SetText("Auto Send")
    autoSendCB:SetChecked(BankRouterDB.autoSend)
    autoSendCB:SetScript("OnClick", function() BankRouterDB.autoSend = this:GetChecked() end)

    local debugCB = CreateFrame("CheckButton", "BankRouterDebugCheck", f, "UICheckButtonTemplate")
    debugCB:SetPoint("LEFT", autoSendCB, "RIGHT", 150, 0)
    _G[debugCB:GetName().."Text"]:SetText("Debug Mode")
    debugCB:SetChecked(BankRouterDB.debug)
    debugCB:SetScript("OnClick", function() BankRouterDB.debug = this:GetChecked() end)

    -- 5. Scroll List (Below everything)
    local scrollFrame = CreateFrame("ScrollFrame", "BankRouterConfigScrollFrame", f, "UIPanelScrollFrameTemplate")
    -- Anchor below the AutoSend Checkbox to ensure no overlap
    scrollFrame:SetPoint("TOPLEFT", autoSendCB, "BOTTOMLEFT", 0, -20)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -35, 15)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(330)
    scrollChild:SetHeight(300)
    scrollFrame:SetScrollChild(scrollChild)

    local listHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("BOTTOMLEFT", scrollFrame, "TOPLEFT", 0, 5)
    listHeader:SetText("Current Routes")

    -- === ADD BUTTON LOGIC ===
    addBtn:SetScript("OnClick", function()
        local added = false

        local inputName = FormattedText(itemInput:GetText())
        local recipient = FormattedText(recInput:GetText())
        itemInput:SetText(inputName)
        recInput:SetText(recipient)

        local useCat = BankRouterCatCheck:GetChecked()
        local useSub = BankRouterSubCatCheck:GetChecked()

        if inputName == "" or recipient == "" then
            Print("Error: Need Item Name and Recipient.")
            return
        end
        local link, type, subType, soulbound = GetItemDetails(inputName)
        -- Check soulbound only if it's NOT a category/subcategory rule
        if not useCat and not useSub then
            if not link then
                Print("Error: Item not Found.")
                return
            end
             if soulbound then
                Print("Error: Item is Soulbound.")
                return
            end
             
        end

        if useCat or useSub then
            if(!type and !subType) then
                if(useCat and validCats[inputName]) then type=inputName end
                if(useSub and validSubs[inputName]) then subType=inputName end
            end

            if ((not type) and useCat) or ((not subType) and useSub) then
                Print("Error: '"..inputName.." type: ".. type .."subType: "..subType.."' is not a valid Category/Subcategory.")
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
                BankRouterDB.routes["s:" .. subType] = recipient
                added=true
                Print("Added Subcat Rule: " .. ColorText(subType, "sub") .. " -> " .. recipient)
            end
        else
            -- 4. Default: Specific Item Rule (Yellow)
            BankRouterDB.routes[inputName] = recipient
            added=true
            Print("Added Item Rule: " .. ColorText(inputName, "item") .. " -> " .. recipient)
        end

        -- Reset & Refresh
        if(added) then
            -- Optional: Clear item input or leave it for rapid entry
            -- itemInput:SetText("") 
        end
        UpdateRouteList(scrollChild)
    end)

    f:SetScript("OnShow", function() 
        UpdateRouteList(scrollChild)
        UpdateMenu() -- Initialize the menu
    end)
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