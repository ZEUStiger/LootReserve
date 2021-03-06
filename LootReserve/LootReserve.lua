local addon, ns = ...;

LootReserve = LibStub("AceAddon-3.0"):NewAddon("LootReserve", "AceComm-3.0");
LootReserve.Version = GetAddOnMetadata(addon, "Version");
LootReserve.MinAllowedVersion = GetAddOnMetadata(addon, "X-Min-Allowed-Version");
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
        RequestedRoll  = nil,
        RollHistory    = nil,
        RecentLoot     = nil,
    },
};
LootReserveGlobalSave =
{
    Client =
    {
        Settings        = nil,
        GlobalFavorites = nil,
    },
    Server =
    {
        NewSessionSettings = nil,
        Settings           = nil,
        GlobalProfile      = nil,
    },
};

StaticPopupDialogs["LOOTRESERVE_GENERIC_ERROR"] =
{
    text         = "%s",
    button1      = CLOSE,
    timeout      = 0,
    whileDead    = 1,
    hideOnEscape = 1,
};

LOOTRESERVE_BACKDROP_BLACK_4 =
{
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
};

SLASH_LOOTRESERVE1 = "/lootreserve";
SLASH_LOOTRESERVE2 = "/reserve";
SLASH_LOOTRESERVE3 = "/res";
function SlashCmdList.LOOTRESERVE(command)
    command = command:lower();

    if command == "" then
        LootReserve.Client.Window:SetShown(not LootReserve.Client.Window:IsShown());
    elseif command == "server" then
        LootReserve:ToggleServerWindow(not LootReserve.Server.Window:IsShown());
    elseif command == "roll" or command == "rolls" then
        LootReserve:ToggleServerWindow(not LootReserve.Server.Window:IsShown(), true);
    end
end

local pendingToggleServerWindow = nil;
local pendingLockdownHooked = nil;
function LootReserve:ToggleServerWindow(state, rolls)
    if InCombatLockdown() and LootReserve.Server.Window:IsProtected() then
        pendingToggleServerWindow = { state, rolls };
        if not pendingLockdownHooked then
            pendingLockdownHooked = true;
            self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
                if pendingToggleServerWindow then
                    local params = pendingToggleServerWindow;
                    pendingToggleServerWindow = nil;
                    self:ToggleServerWindow(unpack(params));
                end
            end);
        end
        self:PrintMessage("Server window will %s once you're out of combat", state and "open" or "close");
        return;
    end

    if rolls then
        self.Server.Window:Show();
        self.Server:OnWindowTabClick(self.Server.Window.TabRolls);
    else
        self.Server.Window:SetShown(state);
    end
end

function LootReserve:OnInitialize()
    LootReserve.Client:Load();
    LootReserve.Server:Load();
end

function LootReserve:OnEnable()
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

    if LootReserve.Comm.Debug then
        SlashCmdList.LOOTRESERVE("server");
    end
end

function LootReserve:OnDisable()
end

function LootReserve:ShowError(fmt, ...)
    StaticPopup_Show("LOOTRESERVE_GENERIC_ERROR", "|cFFFFD200LootReserve|r|n|n" .. format(fmt, ...) .. "|n ");
end

function LootReserve:PrintError(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD200LootReserve: |r" .. format(fmt, ...), 1, 0, 0);
end

function LootReserve:PrintMessage(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD200LootReserve: |r" .. format(fmt, ...), 1, 1, 1);
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
                item.notCheckable = item.checked == nil;
            end
            if item.keepShownOnClick == nil and item.checked ~= nil then
                item.keepShownOnClick = true;
            end
            if item.tooltipText and item.tooltipTitle == nil then
                item.tooltipTitle = item.text;
            end
            if item.tooltipText and item.tooltipOnButton == nil then
                item.tooltipOnButton = true;
            end
            if item.hasArrow == nil and item.menuList then
                item.hasArrow = true;
            end
            if item.keepShownOnClick == nil and item.menuList then
                item.keepShownOnClick = true;
            end
            if item.menuList then
                FixMenu(item.menuList);
            end
        end
    end
    FixMenu(menu);
    EasyMenu(menu, menuContainer, anchor, 0, 0, "MENU");
end

function LootReserve:OpenSubMenu(...)
    for submenu = 1, select("#", ...) do
        local arg1 = select(submenu, ...);
        local opened = false;
        for i = 1, UIDROPDOWNMENU_MAXBUTTONS do
            local button = _G["DropDownList"..submenu.."Button"..i];
            if button and button.arg1 == arg1 then
                local arrow = _G[button:GetName().."ExpandArrow"];
                if arrow then
                    arrow:Click();
                    opened = true;
                end
            end
        end
        if not opened then
            return false;
        end
    end
    return true;
end

function LootReserve:ReopenMenu(button, ...)
    CloseMenus();
    button:Click();
    self:OpenSubMenu(...);
end

-- Used to prevent LootReserve:SendChatMessage from breaking a hyperlink into multiple segments if the message is too long
-- Use it if a text of undetermined length preceeds the hyperlink
-- GOOD: format("%s win %s", strjoin(", ", players), LootReserve:FixLink(link)) - players might contain so many names that the message overflows 255 chars limit
--  BAD: format("%s won by %s", LootReserve:FixLink(link), strjoin(", ", players)) - link is always early in the message and will never overflow the 255 chars limit
function LootReserve:FixLink(link)
    return link:gsub(" ", "\1");
end

function LootReserve:SendChatMessage(text, channel, target)
    if target and not LootReserve:IsPlayerOnline(target) then return; end
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

function LootReserve:GetCurrentExpansion()
    local version = GetBuildInfo();
    local expansion, major, minor = strsplit(".", version);
    return tonumber(expansion) - 1;
end

function LootReserve:IsCrossRealm()
    return self:GetCurrentExpansion() == 0;
    -- This doesn't really work, because even in non-connected realms UnitFullName ends up returning your realm name,
    -- and we can't use UnitName either, because that one NEVER returns a realm for "player". WTB good API, 5g.
    --[[
    if self.CachedIsCrossRealm == nil then
        local name, realm = UnitFullName("player");
        if name then
            self.CachedIsCrossRealm = realm ~= nil;
        end
    end
    return self.CachedIsCrossRealm;
    ]]
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

function LootReserve:Player(player)
    if not self:IsCrossRealm() then
        return Ambiguate(player, "short");
    end

    local name, realm = strsplit("-", player);
    if not realm then
        realm = GetNormalizedRealmName();
    end
    return name .. "-" .. realm;
end

function LootReserve:Me()
    return self:Player(UnitName("player"));
end

function LootReserve:IsMe(player)
    return self:IsSamePlayer(player, self:Me());
end

function LootReserve:IsSamePlayer(a, b)
    return self:Player(a) == self:Player(b);
end

function LootReserve:IsPlayerOnline(player)
    return self:ForEachRaider(function(name, _, _, _, _, _, _, online)
        if self:IsSamePlayer(name, player) then
            return online or false;
        end
    end);
end

function LootReserve:UnitInRaid(player)
    if not self:IsCrossRealm() then
        return UnitInRaid(player);
    end

    return IsInRaid() and self:ForEachRaider(function(name, _, _, _, className, classFilename, _, online)
        if self:IsSamePlayer(name, player) then
            return true;
        end
    end);
end

function LootReserve:UnitInParty(player)
    if not self:IsCrossRealm() then
        return UnitInParty(player);
    end

    return IsInGroup() and not IsInRaid() and self:ForEachRaider(function(name, _, _, _, className, classFilename, _, online)
        if self:IsSamePlayer(name, player) then
            return true;
        end
    end);
end

function LootReserve:UnitClass(player)
    if not self:IsCrossRealm() then
        return UnitClass(player);
    end

    return self:ForEachRaider(function(name, _, _, _, className, classFilename, _, online)
        if self:IsSamePlayer(name, player) then
            return className, classFilename, LootReserve.Constants.ClassFilenameToClassID[classFilename];
        end
    end);
end

function LootReserve:GetPlayerClassColor(player, dim)
    local className, classFilename, classId = self:UnitClass(player);
    if classFilename then
        local colors = RAID_CLASS_COLORS[classFilename];
        if colors then
            if dim then
                local r, g, b, a = colors:GetRGBA();
                return format("FF%02X%02X%02X", r * 128, g * 128, b * 128);
            else
                return colors.colorStr;
            end
        end
    end
    return dim and "FF404040" or "FF808080";
end

function LootReserve:GetRaidUnitID(player)
    for i = 1, MAX_RAID_MEMBERS do
        local unit = UnitName("raid" .. i);
        if unit and LootReserve:IsSamePlayer(LootReserve:Player(unit), player) then
            return "raid" .. i;
        end
    end

    if self:IsMe(player) then
        return "player";
    end
end

function LootReserve:GetPartyUnitID(player)
    for i = 1, MAX_PARTY_MEMBERS do
        local unit = UnitName("party" .. i);
        if unit and LootReserve:IsSamePlayer(LootReserve:Player(unit), player) then
            return "party" .. i;
        end
    end

    if self:IsMe(player) then
        return "player";
    end
end

function LootReserve:ColoredPlayer(player)
    local name, realm = strsplit("-", player);
    return realm and format("|c%s%s|r|c%s-%s|r", self:GetPlayerClassColor(player), name, self:GetPlayerClassColor(player, true), realm)
                  or format("|c%s%s|r",          self:GetPlayerClassColor(player), player);
end

function LootReserve:ForEachRaider(func)
    if not IsInGroup() then
        local className, classFilename = UnitClass("player");
        return func(self:Me(), 0, 1, UnitLevel("player"), className, classFilename, nil, true, UnitIsDead("player"));
    end

    for i = 1, MAX_RAID_MEMBERS do
        local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(i);
        if name then
            local result, a, b = func(self:Player(name), rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole);
            if result ~= nil then
                return result, a, b;
            end
        end
    end
end

function LootReserve:GetTradeableItemCount(item)
    local count = 0;
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag);
        if slots > 0 then
            for slot = 1, slots do
                local _, quantity, _, _, _, _, _, _, _, bagItem = GetContainerItemInfo(bag, slot);
                if bagItem and bagItem == item and (not C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot)) or LootReserve:IsItemSoulboundTradeable(bag, slot)) then
                    count = count + quantity;
                end
            end
        end
    end
    return count;
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

function LootReserve:FormatToRegexp(fmt)
    return fmt:gsub("%(", "%%("):gsub("%)", "%%)"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)");
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
        text              = "",
        hasArrow          = false,
        dist              = 0,
        isTitle           = true,
        isUninteractable  = true,
        notCheckable      = true,
        iconOnly          = true,
        icon              = "Interface\\Common\\UI-TooltipDivider-Transparent",
        tCoordLeft        = 0,
        tCoordRight       = 1,
        tCoordTop         = 0,
        tCoordBottom      = 1,
        tSizeX            = 0,
        tSizeY            = 8,
        tFitDropDownSizeX = true,
        iconInfo =
        {
            tCoordLeft        = 0,
            tCoordRight       = 1,
            tCoordTop         = 0,
            tCoordBottom      = 1,
            tSizeX            = 0,
            tSizeY            = 8,
            tFitDropDownSizeX = true
        },
    };
end

function LootReserve:RepeatedTable(element, count)
    local result = { };
    for i = 1, count do
        table.insert(result, element);
    end
    return result;
end

function LootReserve:FormatPlayersText(players, colorFunc)
    colorFunc = colorFunc or function(...) return ...; end

    local playersSorted = { };
    local playerNames = { };
    for _, player in ipairs(players) do
        if not playerNames[player] then
           table.insert(playersSorted, player);
           playerNames[player] = true;
        end
    end
    table.sort(playersSorted);

    local text = "";
    for _, player in ipairs(playersSorted) do
        text = text .. (#text > 0 and ", " or "") .. colorFunc(player);
    end
    return text;
end

local function FormatReservesText(players, excludePlayer, colorFunc)
    colorFunc = colorFunc or function(...) return ...; end

    local reservesCount = { };
    for _, player in ipairs(players) do
        if not excludePlayer or player ~= excludePlayer then
            reservesCount[player] = reservesCount[player] and reservesCount[player] + 1 or 1;
        end
    end

    local playersSorted = { };
    for player in pairs(reservesCount) do
        table.insert(playersSorted, player);
    end
    table.sort(playersSorted);

    local text = "";
    for _, player in ipairs(playersSorted) do
        text = text .. (#text > 0 and ", " or "") .. colorFunc(player) .. (reservesCount[player] > 1 and format(" x%d", reservesCount[player]) or "");
    end
    return text;
end

function LootReserve:FormatReservesText(players, excludePlayer)
    return FormatReservesText(players, excludePlayer);
end

function LootReserve:FormatReservesTextColored(players, excludePlayer)
    return FormatReservesText(players, excludePlayer, function(...) return self:ColoredPlayer(...); end);
end

local function GetReservesData(players, me, colorFunc)
    local reservesCount = { };
    for _, player in ipairs(players) do
        reservesCount[player] = reservesCount[player] and reservesCount[player] + 1 or 1;
    end

    local uniquePlayers = { };
    for player in pairs(reservesCount) do
        table.insert(uniquePlayers, player);
    end

    return FormatReservesText(players, me, colorFunc), me and reservesCount[me] or 0, #uniquePlayers, #players;
end

function LootReserve:GetReservesData(players, me)
    return GetReservesData(players, me);
end

function LootReserve:GetReservesDataColored(players, me)
    return GetReservesData(players, me, function(...) return self:ColoredPlayer(...); end);
end

local function GetReservesString(server, isUpdate, link, reservesText, myReserves, uniqueReservers, reserves)
    local blind, multireserve;
    if server then
        blind = LootReserve.Server.CurrentSession and LootReserve.Server.CurrentSession.Settings.Blind;
        multireserve = LootReserve.Server.CurrentSession and LootReserve.Server.CurrentSession.Settings.Multireserve;

        if blind then
            return "";
        end
    else
        blind = LootReserve.Client.Blind;
        multireserve = LootReserve.Client.Multireserve;
    end

    if uniqueReservers <= 1 then
        if myReserves > 0 then
            return format("You are%s%s reserving %s%s.%s",
                isUpdate and " now" or "",
                blind and "" or " the only player",
                link,
                (isUpdate or blind) and "" or " thus far",
                multireserve and format(" You have %d %s on this item.", myReserves, myReserves == 1 and "reserve" or "reserves") or "");
        else
           return "";
        end
    elseif myReserves > 0 then
        local otherReserves = reserves - myReserves;
        local otherReservers = uniqueReservers - 1;
        return format("There %s%s %d %s for %s: %s.",
            otherReserves == 1 and "is" or "are",
            isUpdate and " now" or "",
            otherReserves,
            multireserve and format("%s by %d %s", otherReserves == 1 and "other reserve" or "other reserves",
                                                   otherReservers,
                                                   otherReservers == 1 and "player" or "players")
                         or format("%s", otherReserves == 1 and "other contender" or "other contenders"),
            link,
            reservesText);
    else
        return "";
    end
end

function LootReserve:GetReservesString(server, players, player, isUpdate, link)
    return GetReservesString(self, isUpdate, link, self:GetReservesData(players, player));
end

function LootReserve:GetReservesStringColored(server, players, player, isUpdate, link)
    return GetReservesString(server, isUpdate, link, self:GetReservesDataColored(players, player));
end
