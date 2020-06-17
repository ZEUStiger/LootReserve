LootReserve = LootReserve or { };
LootReserve.Server =
{
    CurrentSession = nil,
    NewSessionSettings =
    {
        LootCategory = 100,
        MaxReservesPerPlayer = 5,
        Duration = 600,
        ChatFallback = true,
    },
    RequestedRoll = nil,

    ReservableItems = { },
    DurationUpdateRegistered = false,
    RollMatcherRegistered = false,
    ChatFallbackRegistered = false,
    SessionEventsRegistered = false,
};

StaticPopupDialogs["LOOTRESERVE_CONFIRM_FORCED_CANCEL_RESERVE"] =
{
    text = "Are you sure you want to remove %s's reserve for item %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        LootReserve.Server:CancelReserve(self.data.Player, self.data.Item, true);
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
};

local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end
local function removeFromTable(tbl, item)
    for index, i in ipairs(tbl) do
        if i == item then
            table.remove(tbl, index);
            return true;
        end
    end
    return false;
end
local function formatToRegexp(fmt)
    return fmt:gsub("%(", "%%("):gsub("%)", "%%)"):gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)");
end
local function stringStartsWith(str, start)
    return str:sub(1, #start) == start;
end
local function stringTrim(str, chars)
    chars = chars or "%s"
    return (str:match("^" .. chars .. "*(.-)" .. chars .. "*$"));
end

function LootReserve.Server:CanBeServer()
    return IsInRaid() and (UnitIsGroupLeader("player") or IsMasterLooter()) or LootReserve.Comm.SoloDebug;
end

function LootReserve.Server:StartSession()
    if not self:CanBeServer() then
        LootReserve:ShowError("You must be the raid leader or the master looter to start loot reserves");
        return;
    end

    if self.CurrentSession then
        LootReserve:ShowError("Loot reserves are already started");
        return;
    end

    if LootReserve.Client.SessionServer then
        LootReserve:ShowError("Loot reserves are already started in this raid");
        return;
    end

    self.CurrentSession =
    {
        AcceptingReserves = true,
        Settings = deepcopy(self.NewSessionSettings),
        Duration = self.NewSessionSettings.Duration,
        Members = { },
        ItemReserves = { },
        --[[
        {
            [ItemID] =
            {
                StartTime = time(),
                Players = { PlayerName, PlayerName, ... },
            },
            ...
        },
        ]]
        LootTracking = { },
        --[[
        {
            [ItemID] =
            {
                TotalCount = 0,
                Players = { [PlayerName] = Count, ... },
            },
            ...
        },
        ]]
    };

    for i = 1, MAX_RAID_MEMBERS do
        local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(i);
        if LootReserve.Comm.SoloDebug and i == 1 then
            name = UnitName("player");
        end
        if name then
            name = Ambiguate(name, "short");
            self.CurrentSession.Members[name] =
            {
                ReservesLeft = self.CurrentSession.Settings.MaxReservesPerPlayer,
                ReservedItems = { },
            };
        end
    end

self.CurrentSession.ItemReserves[16800] = { StartTime = time(), Players = { "Tagar", "Mandula" } };
self.CurrentSession.ItemReserves[16805] = { StartTime = time(), Players = { "Tagar" } };
self.CurrentSession.Members["Tagar"] = { ReservesLeft = self.CurrentSession.Settings.MaxReservesPerPlayer, ReservedItems = { 16805, 16800 }, };
self.CurrentSession.Members["Mandula"] = { ReservesLeft = self.CurrentSession.Settings.MaxReservesPerPlayer, ReservedItems = { 16800 }, };

    if self.CurrentSession.Settings.Duration ~= 0 and not self.DurationUpdateRegistered then
        self.DurationUpdateRegistered = true;
        LootReserve:RegisterUpdate(function(elapsed)
            if self.CurrentSession and self.CurrentSession.AcceptingReserves and self.CurrentSession.Duration ~= 0 then
                if self.CurrentSession.Duration > elapsed then
                    self.CurrentSession.Duration = self.CurrentSession.Duration - elapsed;
                else
                    self.CurrentSession.Duration = 0;
                    self:StopSession();
                end
            end
        end);
    end

    if not self.SessionEventsRegistered then
        self.SessionEventsRegistered = true;

        LootReserve:RegisterEvent("GROUP_LEFT", function()
            if self.CurrentSession then
                self:StopSession();
                self:ResetSession();
            end
        end);

        LootReserve:RegisterEvent("GROUP_ROSTER_UPDATE", function()
            if self.CurrentSession then
                local leavers = { };
                for player, member in pairs(self.CurrentSession.Members) do
                    if not UnitInRaid(player) then
                        table.insert(leavers, player);

                        for i = #member.ReservedItems, 1, -1 do
                            self:CancelReserve(player, member.ReservedItems[i]);
                        end
                    end
                end

                for _, player in ipairs(leavers) do
                    self.CurrentSession.Members[player] = nil;
                end
            end
        end);

        local loot = formatToRegexp(LOOT_ITEM);
        local lootMultiple = formatToRegexp(LOOT_ITEM_MULTIPLE);
        local lootSelf = formatToRegexp(LOOT_ITEM_SELF);
        local lootSelfMultiple = formatToRegexp(LOOT_ITEM_SELF_MULTIPLE);
        LootReserve:RegisterEvent("CHAT_MSG_LOOT", function(text)
            if not self.CurrentSession then return; end

            local looter, item, count;
            item, count = text:match(lootSelfMultiple);
            if item and count then
                looter = UnitName("player");
            else
                item = text:match(lootSelf);
                if item then
                    looter = UnitName("player");
                    count = 1;
                else
                    looter, item, count = text:match(lootMultiple);
                    if looter and item and count then
                        -- ok
                    else
                        looter, item = text:match(loot);
                        if looter and item then
                            -- ok
                        else
                            return;
                        end
                    end
                end
            end

            looter = Ambiguate(looter, "short");
            item = tonumber(item:match("item:(%d+)"));
            count = tonumber(count);
            if looter and item and count and self.ReservableItems[item] then
                local tracking = self.CurrentSession.LootTracking[item] or
                {
                    TotalCount = 0,
                    Players = { },
                };
                self.CurrentSession.LootTracking[item] = tracking;
                tracking.TotalCount = tracking.TotalCount + count;
                tracking.Players[looter] = (tracking.Players[looter] or 0) + count;

                self:UpdateReserveList();
            end
        end);

        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            if self.CurrentSession then
                local name, link = tooltip:GetItem();
                if not link then return; end

                local item = tonumber(link:match("item:(%d+)"));
                if item and self.CurrentSession.ItemReserves[item] then
                    local players = "";
                    for _, player in ipairs(self.CurrentSession.ItemReserves[item].Players) do
                        players = players .. format(#players > 0 and ", |c%s%s|r" or "|c%s%s|r", LootReserve:GetPlayerClassColor(player), player);
                    end
                    tooltip:AddLine("|TInterface\\BUTTONS\\UI-GroupLoot-Dice-Up:32:32:0:-4|t Reserved by " .. players, 1, 1, 1);
                end
            end
        end);
    end

    LootReserve.Comm:BroadcastVersion();
    self:BroadcastSessionInfo(true);
    if self.CurrentSession.Settings.ChatFallback then
        local category = LootReserve.Data.Categories[self.CurrentSession.Settings.LootCategory];
        local duration = self.CurrentSession.Settings.Duration
        local count = self.CurrentSession.Settings.MaxReservesPerPlayer;
        SendChatMessage(format("Loot reserves are now started%s%s. %d reserved %s per character. Whisper !reserve ItemLinkOrName",
            category and format(" for %s", category.Name) or "",
            duration ~= 0 and format(" and will last for %d:%02d minutes", math.floor(duration / 60), duration % 60) or "",
            count,
            count == 1 and "item" or "items"
        ), "RAID");

        if not self.ChatFallbackRegistered then
            self.ChatFallbackRegistered = true;

            local prefixA = "!reserve";
            local prefixB = "!res";

            local function ProcessChat(text, sender)
                sender = Ambiguate(sender, "short");
                if not self.CurrentSession then return; end;

                local member = self.CurrentSession.Members[sender];
                if not member then return; end

                text = stringTrim(text);
                if stringStartsWith(text, prefixA) then
                    text = text:sub(1 + #prefixA);
                elseif stringStartsWith(text, prefixB) then
                    text = text:sub(1 + #prefixB);
                else
                    return;
                end

                if not self.CurrentSession.AcceptingReserves then
                    SendChatMessage("Loot reserves are no longer being accepted.", "WHISPER", nil, sender);
                    return;
                end

                text = stringTrim(text);
                local command = "reserve";
                if stringStartsWith(text, "cancel") then
                    text = text:sub(1 + #("cancel"));
                    command = "cancel";
                end

                text = stringTrim(text);
                if #text == 0 and command == "cancel" then
                    if #member.ReservedItems > 0 then
                        self:CancelReserve(sender, member.ReservedItems[#member.ReservedItems]);
                    end
                    return;
                end

                local item = tonumber(text:match("item:(%d+)"));
                if item then
                    if self.ReservableItems[item] then
                        if command == "reserve" then
                            self:Reserve(sender, item);
                        elseif command == "cancel" then
                            self:CancelReserve(sender, item);
                        end
                    else
                        SendChatMessage("That item is not reservable in this raid.", "WHISPER", nil, sender);
                    end
                else
                    text = stringTrim(text, "[%s%[%]]");
                    -- TODO: Name search
                end
            end

            LootReserve:RegisterEvent("CHAT_MSG_WHISPER", ProcessChat);
            LootReserve:RegisterEvent("CHAT_MSG_RAID", ProcessChat); -- Just in case some people can't follow instructions
            LootReserve:RegisterEvent("CHAT_MSG_RAID_LEADER", ProcessChat); -- Just in case some people can't follow instructions
            LootReserve:RegisterEvent("CHAT_MSG_RAID_WARNING", ProcessChat); -- Just in case some people can't follow instructions
        end
    end

    -- Cache the list of items players can reserve
    table.wipe(self.ReservableItems);
    for id, category in pairs(LootReserve.Data.Categories) do
        if category.Children and (not self.CurrentSession.Settings.LootCategory or id == self.CurrentSession.Settings.LootCategory) then
            for _, child in ipairs(category.Children) do
                if child.Loot then
                    for _, item in ipairs(child.Loot) do
                        if item ~= 0 then
                            self.ReservableItems[item] = true;
                        end
                    end
                end
            end
        end
    end

    self:UpdateReserveList();

    self:SessionStarted();
    return true;
end

function LootReserve.Server:BroadcastSessionInfo(starting)
    for player in pairs(self.CurrentSession.Members) do
        if LootReserve:IsPlayerOnline(player) then
            LootReserve.Comm:SendSessionInfo(player, starting);
        end
    end
end

function LootReserve.Server:ResumeSession()
    if not self.CurrentSession then
        LootReserve:ShowError("Loot reserves haven't been started");
        return;
    end

    self.CurrentSession.AcceptingReserves = true;
    self:BroadcastSessionInfo();

    if self.CurrentSession.Settings.ChatFallback then
        SendChatMessage("Accepting loot reserves again.", "RAID");
    end

    self:UpdateReserveList();

    self:SessionStarted();
    return true;
end

function LootReserve.Server:StopSession()
    if not self.CurrentSession then
        LootReserve:ShowError("Loot reserves haven't been started");
        return;
    end

    self.CurrentSession.AcceptingReserves = false;
    self:BroadcastSessionInfo();
    LootReserve.Comm:SendSessionStop();

    if self.CurrentSession.Settings.ChatFallback then
        SendChatMessage("No longer accepting loot reserves.", "RAID");
    end

    self:UpdateReserveList();

    self:SessionStopped();
    return true;
end

function LootReserve.Server:ResetSession()
    if not self.CurrentSession then
        return true;
    end

    if self.CurrentSession.AcceptingReserves then
        LootReserve:ShowError("You need to stop loot reserves first");
        return;
    end

    LootReserve.Comm:SendSessionReset();

    self.CurrentSession = nil;

    self:UpdateReserveList();

    self:SessionReset();
    return true;
end

function LootReserve.Server:Reserve(player, item)
    if not self.CurrentSession then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.NoSession, 0);
        return;
    end

    local member = self.CurrentSession.Members[player];
    if not member then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.NotMember, 0);
        return;
    end

    if not self.ReservableItems[item] then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.ItemNotReservable, member.ReservesLeft);
        return;
    end

    if LootReserve:Contains(member.ReservedItems, item) then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.AlreadyReserved, member.ReservesLeft);
        return;
    end

    if member.ReservesLeft <= 0 then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.NoReservesLeft, member.ReservesLeft);
        return;
    end

    member.ReservesLeft = member.ReservesLeft - 1;
    table.insert(member.ReservedItems, item);
    LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.OK, member.ReservesLeft);

    local reserve = self.CurrentSession.ItemReserves[item] or
    {
        StartTime = time(),
        Players = { },
    };
    self.CurrentSession.ItemReserves[item] = reserve;
    table.insert(reserve.Players, player);
    LootReserve.Comm:BroadcastReserveInfo(item, reserve.Players);

    if self.CurrentSession.Settings.ChatFallback then
        local function WhisperPlayer()
            if #reserve.Players == 0 then return; end

            local name, link = GetItemInfo(item);
            if not name or not link then
                C_Timer.After(0.25, WhisperPlayer);
                return;
            end

            local post;
            if #reserve.Players == 1 and reserve.Players[1] == player then
                post = " You are the only player reserving this item thus far.";
            else
                local others = deepcopy(reserve.Players);
                removeFromTable(others, player);
                post = format(" It's also reserved by %d other %s: %s.",
                    #others,
                    #others == 1 and "player" or "players",
                    strjoin(", ", unpack(others)));
            end

            SendChatMessage(format("You reserved %s.%s %s more %s available. You can cancel with !reserve cancel [ItemLinkOrName]",
                link,
                post,
                member.ReservesLeft == 0 and "No" or tostring(member.ReservesLeft),
                member.ReservesLeft == 1 and "reserve" or "reserves"
            ), "WHISPER", nil, player);
        end
        WhisperPlayer();

        local function WhisperOthers()
            if #reserve.Players <= 1 then return; end

            local name, link = GetItemInfo(item);
            if not name or not link then
                C_Timer.After(0.25, WhisperOthers);
                return;
            end

            for _, other in ipairs(reserve.Players) do
                if other ~= player then
                    local others = deepcopy(reserve.Players);
                    removeFromTable(others, other);

                    SendChatMessage(format("There %s now %d %s for %s you reserved: %s.",
                        #others == 1 and "is" or "are",
                        #others,
                        #others == 1 and "contender" or "contenders",
                        link,
                        strjoin(", ", unpack(others))
                    ), "WHISPER", nil, other);
                end
            end
        end
        WhisperOthers();
    end

    self:UpdateReserveList();
end

function LootReserve.Server:CancelReserve(player, item, forced)
    if not self.CurrentSession then
        LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.NoSession, 0);
        return;
    end

    local member = self.CurrentSession.Members[player];
    if not member then
        LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.NotMember, 0);
        return;
    end

    if not self.ReservableItems[item] then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.CancelReserveResult.ItemNotReservable, member.ReservesLeft);
        return;
    end

    if not LootReserve:Contains(member.ReservedItems, item) then
        LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.NotReserved, member.ReservesLeft);
        return;
    end

    member.ReservesLeft = math.min(member.ReservesLeft + 1, self.CurrentSession.Settings.MaxReservesPerPlayer);
    removeFromTable(member.ReservedItems, item);
    LootReserve.Comm:SendCancelReserveResult(player, item, forced and LootReserve.Constants.CancelReserveResult.Forced or LootReserve.Constants.CancelReserveResult.OK, member.ReservesLeft);

    if self.RequestedRoll and self.RequestedRoll.Item == item then
        self.RequestedRoll.Players[player] = nil;
    end

    local reserve = self.CurrentSession.ItemReserves[item];
    if reserve then
        removeFromTable(reserve.Players, player);
        LootReserve.Comm:BroadcastReserveInfo(item, reserve.Players);
        -- Remove the item entirely if all reserves were cancelled
        if #reserve.Players == 0 then
            self.CurrentSession.ItemReserves[item] = nil;
        end
    end

    if self.CurrentSession.Settings.ChatFallback then
        local function WhisperPlayer()
            local name, link = GetItemInfo(item);
            if not name or not link then
                C_Timer.After(0.25, WhisperPlayer);
                return;
            end

            SendChatMessage(format(forced and "Your reserve for %s has been forcibly removed. %d more %s available." or "You cancelled your reserve for %s. %d more %s available.",
                link,
                member.ReservesLeft,
                member.ReservesLeft == 1 and "reserve" or "reserves"
            ), "WHISPER", nil, player);
        end
        WhisperPlayer();

        local function WhisperOthers()
            if #reserve.Players == 0 then return; end

            local name, link = GetItemInfo(item);
            if not name or not link then
                C_Timer.After(0.25, WhisperOthers);
                return;
            end

            for _, other in ipairs(reserve.Players) do
                local others = deepcopy(reserve.Players);
                removeFromTable(others, other);

                if #others == 0 then
                    SendChatMessage(format("You are again the only contender for %s.", link), "WHISPER", nil, other);
                else
                    SendChatMessage(format("There %s now %d %s for %s you reserved: %s.",
                        #others == 1 and "is" or "are",
                        #others,
                        #others == 1 and "contender" or "contenders",
                        link,
                        strjoin(", ", unpack(others))
                    ), "WHISPER", nil, other);
                end
            end
        end
        WhisperOthers();
    end

    self:UpdateReserveList();
    self:UpdateReserveListRolls();
end

function LootReserve.Server:RequestRoll(item)
    local reserve = self.CurrentSession.ItemReserves[item];
    if not reserve then
        LootReserve:ShowError("That item is not reserved by anyone");
        return;
    end

    if self.RequestedRoll and self.RequestedRoll.Item == item then
        -- Cancel roll
        self.RequestedRoll = nil;
        LootReserve.Comm:BroadcastRequestRoll(0, { });
        self:UpdateReserveListRolls();
        return;
    end

    if not self.RollMatcherRegistered then
        self.RollMatcherRegistered = true;
        local rollMatcher = formatToRegexp(RANDOM_ROLL_RESULT);
        LootReserve:RegisterEvent("CHAT_MSG_SYSTEM", function(text)
            if self.RequestedRoll then
                local player, roll, min, max = text:match(rollMatcher);
                if player and roll and min == "1" and max == "100" and self.RequestedRoll.Players[player] == 0 and tonumber(roll) then
                    self.RequestedRoll.Players[player] = tonumber(roll);
                    self:UpdateReserveListRolls();
                end
            end
        end);
    end

    self.RequestedRoll =
    {
        Item = item,
        Players = { },
    };

    for _, player in ipairs(reserve.Players) do
        self.RequestedRoll.Players[player] = 0;
    end
    LootReserve.Comm:BroadcastRequestRoll(item, reserve.Players);

    if self.CurrentSession.Settings.ChatFallback then
        local function WhisperPlayer()
            local name, link = GetItemInfo(item);
            if not name or not link then
                C_Timer.After(0.25, WhisperPlayer);
                return;
            end

            for player, roll in pairs(self.RequestedRoll.Players) do
                if roll == 0 then
                    SendChatMessage(format("Please /roll on %s you reserved.", link), "WHISPER", nil, player);
                end
            end
        end
        WhisperPlayer();
    end

    self:UpdateReserveListRolls();
end

function LootReserve.Server:PassRoll(player, item)
    if not self.RequestedRoll or self.RequestedRoll.Item ~= item or not self.RequestedRoll.Players[player] then
        return;
    end

    self.RequestedRoll.Players[player] = -1;

    self:UpdateReserveListRolls();
end
