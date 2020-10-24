local addon, ns = ...;

LootReserve = LibStub("AceAddon-3.0"):NewAddon("LootReserve", "AceComm-3.0");
LootReserve.Version = GetAddOnMetadata(addon, "Version");
LootReserve.MinAllowedVersion = "2020-09-04";
LootReserve.LatestKnownVersion = LootReserve.Version;
LootReserve.Enabled = true;

LootReserve.EventFrame = CreateFrame("Frame", nil, UIParent);
LootReserve.EventFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0);
LootReserve.EventFrame:SetSize(0, 0);
LootReserve.EventFrame:Show();

LootReserveCharacterSave =
{
    Client =
    {
        CharacterFavorites = nil,
    },
    Server =
    {
        CurrentSession = nil,
        RequestedRoll = nil,
        RollHistory = nil,
        RecentLoot = nil,
    },
};
LootReserveGlobalSave =
{
    Client =
    {
        Settings = nil,
        GlobalFavorites = nil,
    },
    Server =
    {
        NewSessionSettings = nil,
        Settings = nil,
        GlobalProfile = nil,
    },
};

StaticPopupDialogs["LOOTRESERVE_GENERIC_ERROR"] =
{
    text = "%s",
    button1 = CLOSE,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
};

SLASH_LOOTRESERVE1 = "/lootreserve";
SLASH_LOOTRESERVE2 = "/reserve";
SLASH_LOOTRESERVE3 = "/res";
function SlashCmdList.LOOTRESERVE(command)
    command = command:lower();

    if command == "" then
        LootReserve.Client.Window:SetShown(not LootReserve.Client.Window:IsShown());
    elseif command == "server" then
        LootReserve:OpenServerWindow();
    elseif command == "roll" or command == "rolls" then
        LootReserve:OpenServerWindow(true);
    end
end

local pendingOpenServerWindow = nil;
local pendingLockdownHooked = nil;
function LootReserve:OpenServerWindow(rolls)
    if InCombatLockdown() and LootReserve.Server.Window:IsProtected() then
        pendingOpenServerWindow = { rolls };
        if not pendingLockdownHooked then
            pendingLockdownHooked = true;
            LootReserve:RegisterEvent("PLAYER_REGEN_ENABLED", function()
                if pendingOpenServerWindow then
                    local params = pendingOpenServerWindow;
                    pendingOpenServerWindow = nil;
                    LootReserve:OpenServerWindow(unpack(params));
                end
            end);
        end
        DEFAULT_CHAT_FRAME:AddMessage("Loot Reserve Server window will open once you're out of combat", 1, 1, 1);
        return;
    end

    if rolls then
        LootReserve.Server.Window:Show();
        LootReserve.Server:OnWindowTabClick(LootReserve.Server.Window.TabRolls);
    else
        LootReserve.Server.Window:SetShown(not LootReserve.Server.Window:IsShown());
    end
end

function LootReserve:OnInitialize()
    LootReserve.Client:Load();
    LootReserve.Server:Load();

    LootReserve.Comm:StartListening();

    local function Startup()
        LootReserve.Server:Startup();
        if IsInRaid() or LootReserve.Comm.SoloDebug then
            -- Query other group members about their addon versions and request server session info if any
            LootReserve.Client:SearchForServer(true);
        end
    end

    LootReserve:RegisterEvent("GROUP_JOINED", function()
        -- Load client and server after WoW client restart
        -- Server session should not normally exist when the player is outside of any raid groups, so restarting it upon regular group join shouldn't break anything
        -- With a delay, due to possible name cache issues
        C_Timer.After(1, Startup);
    end);

    -- Load client and server after UI reload
    -- This should be the only case when a player is already detected to be in a group at the time of addon loading
    Startup();
end

function LootReserve:OnEnable()
end

function LootReserve:OnDisable()
end

function LootReserve:ShowError(fmt, ...)
    StaticPopup_Show("LOOTRESERVE_GENERIC_ERROR", "|cFFFFD200LootReserve|r|n|n" .. format(fmt, ...) .. "|n ");
end

function LootReserve:PrintError(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD200LootReserve: |r" .. format(fmt, ...), 1, 0, 0);
end

function LootReserve:RegisterUpdate(handler)
    LootReserve.EventFrame:HookScript("OnUpdate", function(self, elapsed)
        handler(elapsed);
    end);
end

function LootReserve:RegisterEvent(...)
    if not LootReserve.EventFrame.RegisteredEvents then
        LootReserve.EventFrame.RegisteredEvents = { };
        LootReserve.EventFrame:SetScript("OnEvent", function(self, event, ...)
            local handlers = self.RegisteredEvents[event];
            if handlers then
                for _, handler in ipairs(handlers) do
                    handler(...);
                end
            end
        end);
    end

    local params = select("#", ...);

    local handler = select(params, ...);
    if type(handler) ~= "function" then
        error("LootReserve:RegisterEvent: The last passed parameter must be the handler function");
        return;
    end

    for i = 1, params - 1 do
        local event = select(i, ...);
        if type(event) == "string" then
            LootReserve.EventFrame:RegisterEvent(event);
            LootReserve.EventFrame.RegisteredEvents[event] = LootReserve.EventFrame.RegisteredEvents[event] or { };
            table.insert(LootReserve.EventFrame.RegisteredEvents[event], handler);
        else
            error("LootReserve:RegisterEvent: All but the last passed parameters must be event names");
        end
    end
end

function LootReserve:OpenMenu(menu, menuContainer, anchor)
    if UIDROPDOWNMENU_OPEN_MENU == menuContainer then
        CloseMenus();
        return;
    end

    local function FixMenu(menu)
        for _, item in ipairs(menu) do
            if item.notCheckable == nil then
                item.notCheckable = true;
            end
            if item.menuList then
                FixMenu(item.menuList);
            end
        end
    end
    FixMenu(menu);
    EasyMenu(menu, menuContainer, anchor, 0, 0, "MENU");
end

function LootReserve:OpenSubMenu(arg1)
    for i = 1, UIDROPDOWNMENU_MAXBUTTONS do
        local button = _G["DropDownList1Button"..i];
        if button and button.arg1 == arg1 then
            local arrow = _G[button:GetName().."ExpandArrow"];
            if arrow then
                arrow:Click();
            end
        end
    end
end

-- Used to prevent LootReserve:SendChatMessage from breaking a hyperlink into multiple segments if the message is too long
-- Use it if a text of undetermined length preceeds the hyperlink
-- GOOD: format("%s win %s", strjoin(", ", players), LootReserve:FixLink(link)) - players might contain so many names that the message overflows 255 chars limit
--  BAD: format("%s won by %s", LootReserve:FixLink(link), strjoin(", ", players)) - link is always early in the message and will never overflow the 255 chars limit
function LootReserve:FixLink(link)
    return link:gsub(" ", "\1");
end

function LootReserve:SendChatMessage(text, channel, target)
    local function Send(text)
        if #text > 0 then
            if ChatThrottleLib and LootReserve.Server.Settings.ChatThrottle then
                ChatThrottleLib:SendChatMessage("NORMAL", self.Comm.Prefix, text:gsub("\1", " "), channel, nil, target);
            else
                SendChatMessage(text:gsub("\1", " "), channel, nil, target);
            end
        end
    end

    if #text <= 250 then
        Send(text);
    else
        text = text .. " ";
        local accumulator = "";
        for word in text:gmatch("[^ ]- ") do
            if #accumulator + #word > 250 then
                Send(self:StringTrim(accumulator));
                accumulator = "";
            end
            accumulator = accumulator .. word;
        end
        Send(self:StringTrim(accumulator));
    end
end

function LootReserve:GetNumClasses()
    return 11;
end

function LootReserve:GetClassInfo(classID)
    local info = C_CreatureInfo.GetClassInfo(classID);
    if info then
        return info.className, info.classFile, info.classID;
    end
end

function LootReserve:IsPlayerOnline(player)
    for i = 1, MAX_RAID_MEMBERS do
        local name, _, _, _, _, _, _, online = GetRaidRosterInfo(i);

        if LootReserve.Comm.SoloDebug and i == 1 then
            name = UnitName("player");
            online = true;
        end

        if name and Ambiguate(name, "short") == player then
            return online or false;
        end
    end
end

function LootReserve:GetPlayerClassColor(player)
    local className, classFilename, classId = UnitClass(player);
    if classFilename then
        local colors = RAID_CLASS_COLORS[classFilename];
        if colors then
            return colors.colorStr;
        end
    end
    return "FF808080";
end

function LootReserve:GetRaidUnitID(player)
    for i = 1, MAX_RAID_MEMBERS do
        local unit = UnitName("raid" .. i);
        if unit and Ambiguate(unit, "short") == player then
            return "raid" .. i;
        end
    end

    if self.Comm.SoloDebug and Ambiguate(UnitName("player"), "short") == player then
        return "player";
    end
end

function LootReserve:GetPartyUnitID(player)
    for i = 1, MAX_PARTY_MEMBERS do
        local unit = UnitName("party" .. i);
        if unit and Ambiguate(unit, "short") == player then
            return "party" .. i;
        end
    end

    if Ambiguate(UnitName("player"), "short") == player then
        return "player";
    end
end

function LootReserve:ColoredPlayer(player)
    return format("|c%s%s|r", self:GetPlayerClassColor(player), player);
end

function LootReserve:IsItemSoulboundTradeable(bag, slot)
    if not self.TooltipScanner then
        self.TooltipScanner = CreateFrame("GameTooltip", "LootReserveTooltipScanner", UIParent, "GameTooltipTemplate");
        self.TooltipScanner:Hide();
    end

    if not self.TooltipScanner.SoulboundTradeable then
        self.TooltipScanner.SoulboundTradeable = BIND_TRADE_TIME_REMAINING:gsub("%.", "%%."):gsub("%%s", "(.+)");
    end

    self.TooltipScanner:SetOwner(UIParent, "ANCHOR_NONE");
    self.TooltipScanner:SetBagItem(bag, slot);
    for i = 50, 1, -1 do
        local line = _G[self.TooltipScanner:GetName() .. "TextLeft" .. i];
        if line and line:GetText() and line:GetText():match(self.TooltipScanner.SoulboundTradeable) then
            self.TooltipScanner:Hide();
            return true;
        end
    end
    self.TooltipScanner:Hide();
    return false;
end

function LootReserve:IsItemUsable(item)
    local name, _, _, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(item);
    if not name or not bindType then return; end

    -- Non BoP items are considered usable by everyone
    if bindType ~= 1 then
        return true;
    end

    if not self.TooltipScanner then
        self.TooltipScanner = CreateFrame("GameTooltip", "LootReserveTooltipScanner", UIParent, "GameTooltipTemplate");
        self.TooltipScanner:Hide();
    end

    self.TooltipScanner:SetOwner(UIParent, "ANCHOR_NONE");
    self.TooltipScanner:SetHyperlink("item:" .. item);
    local columns = { "Left", "Right" };
    for i = 1, 50 do
        for _, column in ipairs(columns) do
            local line = _G[self.TooltipScanner:GetName() .. "Text" .. column .. i];
            if line and line:GetText() and line:IsShown() then
                local r, g, b, a = line:GetTextColor();
                if r >= 0.95 and g <= 0.15 and b <= 0.15 and a >= 0.5 then
                    self.TooltipScanner:Hide();
                    return false;
                end
            end
        end
    end
    self.TooltipScanner:Hide();
    return true;
end

function LootReserve:IsLootingItem(item)
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i);
        if link then
            local id = tonumber(link:match("item:(%d+)"));
            if id and id == item then
                return i;
            end
        end
    end
end

function LootReserve:TransformSearchText(text)
    text = self:StringTrim(text, "[%s%[%]]");
    text = text:upper();
    text = text:gsub("`", "'"):gsub("´", "'"); -- For whatever reason [`´] doesn't work
    return text;
end

function LootReserve:StringTrim(str, chars)
    chars = chars or "%s"
    return (str:match("^" .. chars .. "*(.-)" .. chars .. "*$"));
end

function LootReserve:Deepcopy(orig)
    if type(orig) == 'table' then
        local copy = { };
        for orig_key, orig_value in next, orig, nil do
            copy[self:Deepcopy(orig_key)] = self:Deepcopy(orig_value)
        end
        setmetatable(copy, self:Deepcopy(getmetatable(orig)))
        return copy;
    else
        return orig;
    end
end

function LootReserve:TableRemove(tbl, item)
    for index, i in ipairs(tbl) do
        if i == item then
            table.remove(tbl, index);
            return true;
        end
    end
    return false;
end

function LootReserve:Contains(table, item)
    for _, i in ipairs(table) do
        if i == item then
            return true;
        end
    end
    return false;
end

local __orderedIndex = { };
function LootReserve:Ordered(tbl, sorter)
    local function __genOrderedIndex(t)
        local orderedIndex = { };
        for key in pairs(t) do
            table.insert(orderedIndex, key);
        end
        if sorter then
            table.sort(orderedIndex, function(a, b)
                return sorter(t[a], t[b], a, b);
            end);
        else
            table.sort(orderedIndex);
        end
        return orderedIndex;
    end

    local function orderedNext(t, state)
        local key;
        if state == nil then
            __orderedIndex[t] = __genOrderedIndex(t)
            key = __orderedIndex[t][1];
        else
            for i = 1, table.getn(__orderedIndex[t]) do
                if __orderedIndex[t][i] == state then
                    key = __orderedIndex[t][i + 1];
                end
            end
        end

        if key then
            return key, t[key];
        end

        __orderedIndex[t] = nil;
        return
    end

    return orderedNext, tbl, nil;
end

function LootReserve:MakeMenuSeparator()
    return
    {
        text = "",
        hasArrow = false,
        dist = 0,
        isTitle = true,
        isUninteractable = true,
        notCheckable = true,
        iconOnly = true,
        icon = "Interface\\Common\\UI-TooltipDivider-Transparent",
        tCoordLeft = 0,
        tCoordRight = 1,
        tCoordTop = 0,
        tCoordBottom = 1,
        tSizeX = 0,
        tSizeY = 8,
        tFitDropDownSizeX = true,
        iconInfo =
        {
            tCoordLeft = 0,
            tCoordRight = 1,
            tCoordTop = 0,
            tCoordBottom = 1,
            tSizeX = 0,
            tSizeY = 8,
            tFitDropDownSizeX = true
        },
    };
end
