local addon, ns = ...;

LootReserve = LibStub("AceAddon-3.0"):NewAddon("LootReserve", "AceComm-3.0");
LootReserve.Version = GetAddOnMetadata(addon, "Version");
LootReserve.MinAllowedVersion = "2020-06-25";
LootReserve.LatestKnownVersion = LootReserve.Version;
LootReserve.Enabled = true;

LootReserve.EventFrame = CreateFrame("Frame", nil, UIParent);
LootReserve.EventFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0);
LootReserve.EventFrame:SetSize(0, 0);
LootReserve.EventFrame:Show();

LootReserveCharacterSave =
{
    Server =
    {
        CurrentSession = nil,
        RequestedRoll = nil,
    },
};
LootReserveGlobalSave =
{
    Server =
    {
        NewSessionSettings = nil,
        Settings = nil,
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

SLASH_RESERVE1 = "/reserve";
SLASH_RESERVE2 = "/res";
SLASH_RESERVE3 = "/lootreserve";
function SlashCmdList.RESERVE(command)
    command = command:lower();

    if command == "" then
        LootReserve.Client.Window:SetShown(not LootReserve.Client.Window:IsShown());
    elseif command == "server" then
        LootReserve.Server.Window:SetShown(not LootReserve.Server.Window:IsShown());
    end
end

function LootReserve:OnInitialize()
    LootReserve.Server:Load();

    LootReserve.Comm:StartListening();

    local function Startup()
        if IsInRaid() or LootReserve.Comm.SoloDebug then
            LootReserve.Server:Startup();
            -- Query other group members about their addon versions and request server session info if any
            LootReserve.Comm:BroadcastHello();
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

function LootReserve:RegisterEvent(event, handler)
    LootReserve.EventFrame:RegisterEvent(event);
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

    LootReserve.EventFrame.RegisteredEvents[event] = LootReserve.EventFrame.RegisteredEvents[event] or { };
    table.insert(LootReserve.EventFrame.RegisteredEvents[event], handler);
end

function LootReserve:SendChatMessage(text, channel, target)
    local function Send(text)
        if #text > 0 then
            if ChatThrottleLib and LootReserve.Server.Settings.ChatThrottle then
                ChatThrottleLib:SendChatMessage("NORMAL", self.Comm.Prefix, text, channel, nil, target);
            else
                SendChatMessage(text, channel, nil, target);
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
    return "ff808080";
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

function LootReserve:ColoredPlayer(player)
    return format("|c%s%s|r", self:GetPlayerClassColor(player), player);
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

function LootReserve:Contains(table, item)
    for _, i in ipairs(table) do
        if i == item then
            return true;
        end
    end
    return false;
end

function LootReserve:Ordered(tbl, sorter)
    local function __genOrderedIndex(t)
        local orderedIndex = { };
        for key in pairs(t) do
            table.insert(orderedIndex, key);
        end
        if sorter then
            table.sort(orderedIndex, function(a, b)
                return sorter(t[a], t[b]);
            end);
        else
            table.sort(orderedIndex);
        end
        return orderedIndex;
    end

    local function orderedNext(t, state)
        local key;
        if state == nil then
            t.__orderedIndex = __genOrderedIndex(t)
            key = t.__orderedIndex[1];
        else
            for i = 1, table.getn(t.__orderedIndex) do
                if t.__orderedIndex[i] == state then
                    key = t.__orderedIndex[i + 1];
                end
            end
        end

        if key then
            return key, t[key];
        end

        t.__orderedIndex = nil;
        return
    end

    return orderedNext, tbl, nil;
end
