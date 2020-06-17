LootReserve = LootReserve or { };
LootReserve.Server =
{
    CurrentSession = nil,
    NewSessionSettings =
    {
        LootCategory = 100,
        MaxReservesPerPlayer = 5,
        Duration = 600,
    },
    RequestedRoll = nil,

    ReservableItems = { },
    DurationUpdateRegistered = false,
    RollMatcherRegistered = false,
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
    self:BroadcastSessionInfo();

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

function LootReserve.Server:BroadcastSessionInfo()
    for player in pairs(self.CurrentSession.Members) do
        if LootReserve:IsPlayerOnline(player) then
            LootReserve.Comm:SendSessionInfo(player, true);
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

    self:UpdateReserveListRolls();
end

function LootReserve.Server:PassRoll(player, item)
    if not self.RequestedRoll or self.RequestedRoll.Item ~= item or not self.RequestedRoll.Players[player] then
        return;
    end

    self.RequestedRoll.Players[player] = -1;

    self:UpdateReserveListRolls();
end
