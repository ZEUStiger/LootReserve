LootReserve = LootReserve or { };
LootReserve.Server =
{
    CurrentSession = nil,
    NewSessionSettings =
    {
        LootCategory = 100,
        MaxReservesPerPlayer = 1,
        Duration = 300,
        ChatFallback = true,
    },
    RequestedRoll = nil,
    AddonUsers = { },

    ReservableItems = { },
    DurationUpdateRegistered = false,
    RollMatcherRegistered = false,
    ChatFallbackRegistered = false,
    SessionEventsRegistered = false,
    AllItemNamesCached = false,
};

StaticPopupDialogs["LOOTRESERVE_CONFIRM_FORCED_CANCEL_RESERVE"] =
{
    text = "Are you sure you want to remove %s's reserve for item %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        LootReserve.Server:CancelReserve(self.data.Player, self.data.Item, false, true);
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

function LootReserve.Server:CanBeServer()
    return IsInRaid() and (UnitIsGroupLeader("player") or IsMasterLooter()) or LootReserve.Comm.SoloDebug;
end

function LootReserve.Server:IsAddonUser(player)
    return player == UnitName("player") or self.AddonUsers[player] or false;
end

function LootReserve.Server:SetAddonUser(player, isUser)
    if self.AddonUsers[player] ~= isUser then
        self.AddonUsers[player] = isUser;
        self:UpdateAddonUsers();
    end
end

function LootReserve.Server:Load()
    -- Copy data from saved variables into runtime tables
    -- Don't outright replace tables, as new versions of the addon could've added more fields that would be missing in the saved data
    local function loadInto(to, from, field)
        if from and to and field then
            if from[field] then
                for k, v in pairs(from[field]) do
                    to[field] = to[field] or { };
                    to[field][k] = v;
                    empty = false;
                end
            end
            from[field] = to[field];
        end
    end
    loadInto(self, LootReserveCharacterSave.Server, "CurrentSession");
    loadInto(self, LootReserveCharacterSave.Server, "RequestedRoll");
    loadInto(self, LootReserveGlobalSave.Server, "NewSessionSettings");
    
    -- Verify that all the required fields are present in the session
    if self.CurrentSession then
        local function verifySessionField(field)
            if self.CurrentSession and self.CurrentSession[field] == nil then
                self.CurrentSession = nil;
            end
        end

        local fields = { "AcceptingReserves", "Settings", "Duration", "DurationEndTimestamp", "Members", "ItemReserves" };
        for _, field in ipairs(fields) do
            verifySessionField(field);
        end
    end

    -- Rearm the duration timer, to make it expire at about the same time (second precision) as it would've otherwise if the server didn't log out/reload UI
    -- Unless the timer would've expired during that time, in which case set it to a dummy 1 second to allow the code to finish reserves properly upon expiration
    if self.CurrentSession and self.CurrentSession.AcceptingReserves and self.CurrentSession.Duration ~= 0 then
        self.CurrentSession.Duration = math.max(1, self.CurrentSession.DurationEndTimestamp - time());
    end

    -- Update the UI according to loaded settings
    self:LoadNewSessionSessings();
end

function LootReserve.Server:Startup()
    if self.CurrentSession and self:CanBeServer() then
        -- Hook handlers
        self:PrepareSession();
        -- Inform other players about ongoing session
        self:BroadcastSessionInfo();
        -- Update UI
        if self.CurrentSession.AcceptingReserves then
            self:SessionStarted();
        else
            self:SessionStopped();
        end
        self:UpdateReserveList();

        -- Hook roll handlers if needed
        if self.RequestedRoll then
            self:PrepareRequestRoll();
        end

        self.Window:Show();

        -- Immediately after logging in retrieving raid member names might not work (names not yet cached?)
        -- so update the UI a little bit later, otherwise reserving players will show up as "(not in raid)"
        -- until the next group roster change
        C_Timer.After(5, function()
            self:UpdateReserveList();
        end);
    end

    -- Show reserves even if no longer the server, just a failsafe
    self:UpdateReserveList();
end

function LootReserve.Server:PrepareSession()
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

        -- For the future. But it needs proper periodic time sync broadcasts to work correctly anyway
        --[[
        LootReserve:RegisterEvent("LOADING_SCREEN_DISABLED", function()
            if self.CurrentSession and self.CurrentSession.AcceptingReserves and self.CurrentSession.Duration ~= 0 then
                self.CurrentSession.Duration = math.max(1, self.CurrentSession.DurationEndTimestamp - time());
            end
        end);
        ]]

        LootReserve:RegisterEvent("GROUP_LEFT", function()
            if self.CurrentSession then
                self:StopSession();
                self:ResetSession();
            end
            table.wipe(self.AddonUsers);
            self:UpdateAddonUsers();
        end);

        local function UpdateGroupMembers()
            if self.CurrentSession then
                -- Remove member info for players who left (?)
                --[[
                local leavers = { };
                for player, member in pairs(self.CurrentSession.Members) do
                    if not UnitInRaid(player) then
                        table.insert(leavers, player);

                        for i = #member.ReservedItems, 1, -1 do
                            self:CancelReserve(player, member.ReservedItems[i], false, true);
                        end
                    end
                end

                for _, player in ipairs(leavers) do
                    self.CurrentSession.Members[player] = nil;
                end
                ]]

                -- Add member info for players who joined
                for i = 1, MAX_RAID_MEMBERS do
                    local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(i);
                    if name then
                        name = Ambiguate(name, "short");
                        if not self.CurrentSession.Members[name] then
                            self.CurrentSession.Members[name] =
                            {
                                ReservesLeft = self.CurrentSession.Settings.MaxReservesPerPlayer,
                                ReservedItems = { },
                            };
                        end
                    end
                end
            end
            self:UpdateReserveList();
            self:UpdateAddonUsers();
        end
        
        LootReserve:RegisterEvent("GROUP_ROSTER_UPDATE", UpdateGroupMembers);
        LootReserve:RegisterEvent("UNIT_NAME_UPDATE", function(unit)
            if unit and (stringStartsWith(unit, "raid") or stringStartsWith(unit, "party")) then
                UpdateGroupMembers();
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
                        players = players .. (#players > 0 and ", " or "") .. LootReserve:ColoredPlayer(player);
                    end
                    tooltip:AddLine("|TInterface\\BUTTONS\\UI-GroupLoot-Dice-Up:32:32:0:-4|t Reserved by " .. players, 1, 1, 1);
                end
            end
        end);
    end

    self.AllItemNamesCached = false; -- If category is changed - other item names might need to be cached

    if self.CurrentSession.Settings.ChatFallback and not self.ChatFallbackRegistered then
        self.ChatFallbackRegistered = true;

        -- Precache item names
        local function updateItemNameCache()
            if self.AllItemNamesCached then return self.AllItemNamesCached; end

            self.AllItemNamesCached = true;
            for id, category in pairs(LootReserve.Data.Categories) do
                if category.Children then
                    for _, child in ipairs(category.Children) do
                        if child.Loot then
                            for _, item in ipairs(child.Loot) do
                                if item ~= 0 and self.ReservableItems[item] then
                                    if not GetItemInfo(item) then
                                        self.AllItemNamesCached = false;
                                    end
                                end
                            end
                        end
                    end
                end
            end
            return self.AllItemNamesCached;
        end

        local prefixA = "!reserve";
        local prefixB = "!res";

        local function ProcessChat(text, sender)
            sender = Ambiguate(sender, "short");
            if not self.CurrentSession then return; end;

            local member = self.CurrentSession.Members[sender];
            if not member or not LootReserve:IsPlayerOnline(sender) then return; end

            text = text:lower();
            text = LootReserve:StringTrim(text);
            if stringStartsWith(text, prefixA) then
                text = text:sub(1 + #prefixA);
            elseif stringStartsWith(text, prefixB) then
                text = text:sub(1 + #prefixB);
            else
                return;
            end

            if not self.CurrentSession.AcceptingReserves then
                LootReserve:SendChatMessage("Loot reserves are no longer being accepted.", "WHISPER", sender);
                return;
            end

            text = LootReserve:StringTrim(text);
            local command = "reserve";
            if stringStartsWith(text, "cancel") then
                text = text:sub(1 + #("cancel"));
                command = "cancel";
            end

            text = LootReserve:StringTrim(text);
            if #text == 0 and command == "cancel" then
                if #member.ReservedItems > 0 then
                    self:CancelReserve(sender, member.ReservedItems[#member.ReservedItems], true);
                end
                return;
            end

            local function handleItemCommand(item, command)
                if self.ReservableItems[item] then
                    if command == "reserve" then
                        self:Reserve(sender, item, true);
                    elseif command == "cancel" then
                        self:CancelReserve(sender, item, true);
                    end
                else
                    LootReserve:SendChatMessage("That item is not reservable in this raid.", "WHISPER", sender);
                end
            end

            local item = tonumber(text:match("item:(%d+)"));
            if item then
                handleItemCommand(item, command);
            else
                text = LootReserve:TransformSearchText(text);
                local function handleItemCommandByName()
                    if updateItemNameCache() then
                        local match = nil;
                        local matches = { };
                        for id, category in pairs(LootReserve.Data.Categories) do
                            if category.Children then
                                for _, child in ipairs(category.Children) do
                                    if child.Loot then
                                        for _, item in ipairs(child.Loot) do
                                            if item ~= 0 and self.ReservableItems[item] then
                                                if string.find(GetItemInfo(item):upper(), text) then
                                                    match = match and 0 or item;
                                                    table.insert(matches, item);
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        if not match then
                            LootReserve:SendChatMessage("Cannot find an item with that name.", "WHISPER", sender);
                        elseif match > 0 then
                            handleItemCommand(match, command);
                        elseif match == 0 then
                            local names = { };
                            for i = 1, math.min(5, #matches) do
                                names[i] = GetItemInfo(matches[i]);
                            end
                            LootReserve:SendChatMessage(format("Try being more specific, %d items match that name: %s%s",
                                #matches,
                                strjoin(", ", unpack(names)),
                                #matches > #names and format(" and %d more...", #matches - #names) or ""
                            ), "WHISPER", sender);
                        end
                    else
                        C_Timer.After(0.25, handleItemCommandByName);
                    end
                end

                if #text >= 3 then
                    handleItemCommandByName();
                else
                    LootReserve:SendChatMessage("That name is too short, 3 or more letters required.", "WHISPER", sender);
                end
            end
        end

        local chatTypes =
        {
            "CHAT_MSG_WHISPER",
            -- Just in case some people can't follow instructions
            "CHAT_MSG_SAY",
            "CHAT_MSG_YELL",
            "CHAT_MSG_PARTY",
            "CHAT_MSG_PARTY_LEADER",
            "CHAT_MSG_RAID",
            "CHAT_MSG_RAID_LEADER",
            "CHAT_MSG_RAID_WARNING",
        };
        for _, type in ipairs(chatTypes) do
            LootReserve:RegisterEvent(type, ProcessChat);
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
        DurationEndTimestamp = time() + self.NewSessionSettings.Duration, -- Used to resume the session after relog or UI reload
        Members = { },
        --[[
        {
            [PlayerName] =
            {
                ReservesLeft = self.CurrentSession.Settings.MaxReservesPerPlayer,
                ReservedItems = { ItemID, ItemID, ... },
            },
            ...
        },
        ]]
        ItemReserves = { },
        --[[
        {
            [ItemID] =
            {
                Item = ItemID,
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
    LootReserveCharacterSave.Server.CurrentSession = self.CurrentSession;

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

    self:PrepareSession();

    LootReserve.Comm:BroadcastVersion();
    self:BroadcastSessionInfo(true);
    if self.CurrentSession.Settings.ChatFallback then
        local category = LootReserve.Data.Categories[self.CurrentSession.Settings.LootCategory];
        local duration = self.CurrentSession.Settings.Duration
        local count = self.CurrentSession.Settings.MaxReservesPerPlayer;
        LootReserve:SendChatMessage(format("Loot reserves are now started%s%s. %d reserved %s per character. Whisper !reserve ItemLinkOrName",
            category and format(" for %s", category.Name) or "",
            duration ~= 0 and format(" and will last for %d:%02d minutes", math.floor(duration / 60), duration % 60) or "",
            count,
            count == 1 and "item" or "items"
        ), "RAID");
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
    self.CurrentSession.DurationEndTimestamp = time() + math.floor(self.CurrentSession.Duration);
    self:BroadcastSessionInfo();

    if self.CurrentSession.Settings.ChatFallback then
        LootReserve:SendChatMessage("Accepting loot reserves again. Whisper !reserve ItemLinkOrName", "RAID");
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
        LootReserve:SendChatMessage("No longer accepting loot reserves.", "RAID");
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

    if self.RequestedRoll then
        self:CancelRollRequest(self.RequestedRoll.Item);
    end

    LootReserve.Comm:SendSessionReset();

    self.CurrentSession = nil;
    LootReserveCharacterSave.Server.CurrentSession = self.CurrentSession;

    self:UpdateReserveList();

    self:SessionReset();
    return true;
end

function LootReserve.Server:Reserve(player, item, chat)
    if not LootReserve:IsPlayerOnline(player) then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.NotInRaid, 0);
        if chat then LootReserve:SendChatMessage("You are not in the raid", "WHISPER", player); end
        return;
    end

    if not self.CurrentSession or not self.CurrentSession.AcceptingReserves then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.NoSession, 0);
        if chat then LootReserve:SendChatMessage("Loot reserves aren't active in your raid", "WHISPER", player); end
        return;
    end

    local member = self.CurrentSession.Members[player];
    if not member then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.NotMember, 0);
        if chat then LootReserve:SendChatMessage("You are not participating in loot reserves", "WHISPER", player); end
        return;
    end

    if not self.ReservableItems[item] then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.ItemNotReservable, member.ReservesLeft);
        if chat then LootReserve:SendChatMessage("That item cannot be reserved in this raid", "WHISPER", player); end
        return;
    end

    if LootReserve:Contains(member.ReservedItems, item) then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.AlreadyReserved, member.ReservesLeft);
        if chat then LootReserve:SendChatMessage("You are already reserving that item", "WHISPER", player); end
        return;
    end

    if member.ReservesLeft <= 0 then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.NoReservesLeft, member.ReservesLeft);
        if chat then LootReserve:SendChatMessage("You already reserved too many items", "WHISPER", player); end
        return;
    end

    member.ReservesLeft = member.ReservesLeft - 1;
    table.insert(member.ReservedItems, item);
    LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.ReserveResult.OK, member.ReservesLeft);

    local reserve = self.CurrentSession.ItemReserves[item] or
    {
        Item = item,
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

            LootReserve:SendChatMessage(format("You reserved %s.%s %s more %s available. You can cancel with !reserve cancel [ItemLinkOrName]",
                link,
                post,
                member.ReservesLeft == 0 and "No" or tostring(member.ReservesLeft),
                member.ReservesLeft == 1 and "reserve" or "reserves"
            ), "WHISPER", player);
        end
        if chat or not self:IsAddonUser(player) then
            WhisperPlayer();
        end

        local function WhisperOthers()
            if #reserve.Players <= 1 then return; end

            local name, link = GetItemInfo(item);
            if not name or not link then
                C_Timer.After(0.25, WhisperOthers);
                return;
            end

            for _, other in ipairs(reserve.Players) do
                if other ~= player and LootReserve:IsPlayerOnline(other) and not self:IsAddonUser(other) then
                    local others = deepcopy(reserve.Players);
                    removeFromTable(others, other);

                    LootReserve:SendChatMessage(format("There %s now %d %s for %s you reserved: %s.",
                        #others == 1 and "is" or "are",
                        #others,
                        #others == 1 and "contender" or "contenders",
                        link,
                        strjoin(", ", unpack(others))
                    ), "WHISPER", other);
                end
            end
        end
        WhisperOthers();
    end

    self:UpdateReserveList();
end

function LootReserve.Server:CancelReserve(player, item, chat, forced)
    if not LootReserve:IsPlayerOnline(player) then
        LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.NotInRaid, 0);
        if chat then LootReserve:SendChatMessage("You are not in the raid", "WHISPER", player); end
        return;
    end

    if not self.CurrentSession or not self.CurrentSession.AcceptingReserves then
        LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.NoSession, 0);
        if chat then LootReserve:SendChatMessage("Loot reserves aren't active in your raid", "WHISPER", player); end
        return;
    end

    local member = self.CurrentSession.Members[player];
    if not member then
        LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.NotMember, 0);
        if chat then LootReserve:SendChatMessage("You are not participating in loot reserves", "WHISPER", player); end
        return;
    end

    if not self.ReservableItems[item] then
        LootReserve.Comm:SendReserveResult(player, item, LootReserve.Constants.CancelReserveResult.ItemNotReservable, member.ReservesLeft);
        if chat then LootReserve:SendChatMessage("That item cannot be reserved in this raid", "WHISPER", player); end
        return;
    end

    if not LootReserve:Contains(member.ReservedItems, item) then
        LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.NotReserved, member.ReservesLeft);
        if chat then LootReserve:SendChatMessage("You did not reserve that item", "WHISPER", player); end
        return;
    end

    member.ReservesLeft = math.min(member.ReservesLeft + 1, self.CurrentSession.Settings.MaxReservesPerPlayer);
    removeFromTable(member.ReservedItems, item);
    LootReserve.Comm:SendCancelReserveResult(player, item, forced and LootReserve.Constants.CancelReserveResult.Forced or LootReserve.Constants.CancelReserveResult.OK, member.ReservesLeft);

    if self:IsRolling(item) then
        self.RequestedRoll.Players[player] = nil;
    end

    local reserve = self.CurrentSession.ItemReserves[item];
    if reserve then
        removeFromTable(reserve.Players, player);
        LootReserve.Comm:BroadcastReserveInfo(item, reserve.Players);
        -- Remove the item entirely if all reserves were cancelled
        if #reserve.Players == 0 then
            self:CancelRollRequest(item);
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

            LootReserve:SendChatMessage(format(forced and "Your reserve for %s has been forcibly removed. %d more %s available." or "You cancelled your reserve for %s. %d more %s available.",
                link,
                member.ReservesLeft,
                member.ReservesLeft == 1 and "reserve" or "reserves"
            ), "WHISPER", player);
        end
        if chat or not self:IsAddonUser(player) then
            WhisperPlayer();
        end

        local function WhisperOthers()
            if #reserve.Players == 0 then return; end

            local name, link = GetItemInfo(item);
            if not name or not link then
                C_Timer.After(0.25, WhisperOthers);
                return;
            end

            for _, other in ipairs(reserve.Players) do
                if LootReserve:IsPlayerOnline(other) and not self:IsAddonUser(other) then
                    local others = deepcopy(reserve.Players);
                    removeFromTable(others, other);

                    if #others == 0 then
                        LootReserve:SendChatMessage(format("You are now the only contender for %s.", link), "WHISPER", other);
                    else
                        LootReserve:SendChatMessage(format("There %s now %d %s for %s you reserved: %s.",
                            #others == 1 and "is" or "are",
                            #others,
                            #others == 1 and "contender" or "contenders",
                            link,
                            strjoin(", ", unpack(others))
                        ), "WHISPER", other);
                    end
                end
            end
        end
        WhisperOthers();
    end

    self:UpdateReserveList();
    self:UpdateReserveListRolls();
end

function LootReserve.Server:IsRolling(item)
    return self.RequestedRoll and self.RequestedRoll.Item == item;
end

function LootReserve.Server:CancelRollRequest(item)
    if self:IsRolling(item) then
        self.RequestedRoll = nil;
        LootReserveCharacterSave.Server.RequestedRoll = self.RequestedRoll;
        LootReserve.Comm:BroadcastRequestRoll(0, { });
        self:UpdateReserveListRolls();
        return;
    end
end

function LootReserve.Server:PrepareRequestRoll()
    if not self.RollMatcherRegistered then
        self.RollMatcherRegistered = true;

        local rollMatcher = formatToRegexp(RANDOM_ROLL_RESULT);
        LootReserve:RegisterEvent("CHAT_MSG_SYSTEM", function(text)
            if self.RequestedRoll then
                local player, roll, min, max = text:match(rollMatcher);
                if player and roll and min == "1" and max == "100" and self.RequestedRoll.Players[player] == 0 and tonumber(roll) and LootReserve:IsPlayerOnline(player) then
                    self.RequestedRoll.Players[player] = tonumber(roll);
                    self:UpdateReserveListRolls();
                end
            end
        end);
    end
end

function LootReserve.Server:RequestRoll(item)
    local reserve = self.CurrentSession.ItemReserves[item];
    if not reserve then
        LootReserve:ShowError("That item is not reserved by anyone");
        return;
    end

    self.RequestedRoll =
    {
        Item = item,
        Players = { },
    };
    LootReserveCharacterSave.Server.RequestedRoll = self.RequestedRoll;

    for _, player in ipairs(reserve.Players) do
        self.RequestedRoll.Players[player] = 0;
    end

    self:PrepareRequestRoll();

    LootReserve.Comm:BroadcastRequestRoll(item, reserve.Players);

    if self.CurrentSession.Settings.ChatFallback then
        local function WhisperPlayer()
            local name, link = GetItemInfo(item);
            if not name or not link then
                C_Timer.After(0.25, WhisperPlayer);
                return;
            end

            for player, roll in pairs(self.RequestedRoll.Players) do
                if roll == 0 and LootReserve:IsPlayerOnline(player) and not self:IsAddonUser(player) then
                    LootReserve:SendChatMessage(format("Please /roll on %s you reserved.", link), "WHISPER", player);
                end
            end
        end
        WhisperPlayer();
    end

    self:UpdateReserveListRolls();
end

function LootReserve.Server:PassRoll(player, item)
    if not self:IsRolling(item) or not self.RequestedRoll.Players[player] then
        return;
    end

    self.RequestedRoll.Players[player] = -1;

    self:UpdateReserveListRolls();
end

function LootReserve.Server:WhisperAllWithoutReserves()
    if not self.CurrentSession then return; end

    for player, member in pairs(self.CurrentSession.Members) do
        if #member.ReservedItems == 0 and member.ReservesLeft > 0 and LootReserve:IsPlayerOnline(player) then
            LootReserve:SendChatMessage(format("Don't forget to reserve your items. You have %d %s left.",
                member.ReservesLeft,
                member.ReservesLeft == 1 and "reserve" or "reserves"
            ), "WHISPER", player);
        end
    end
end
