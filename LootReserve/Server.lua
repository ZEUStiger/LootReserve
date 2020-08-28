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
    Settings =
    {
        ChatAsRaidWarning = { },
        ChatUpdates = true,
        ChatThrottle = false,
        ReservesSorting = LootReserve.Constants.ReservesSorting.ByTime,
        UseGlobalProfile = false,
        RollUsePhases = false,
        RollPhases = { },
        RollAdvanceOnExpire = true,
        RollLimitDuration = false,
        RollDuration = 60,
        RollFinishOnExpire = true,
    },
    RequestedRoll = nil,
    RollHistory = { },
    RecentLoot = { },
    AddonUsers = { },

    ReservableItems = { },
    LootTrackingRegistered = false,
    DurationUpdateRegistered = false,
    RollDurationUpdateRegistered = false,
    RollMatcherRegistered = false,
    ChatTrackingRegistered = false,
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

StaticPopupDialogs["LOOTRESERVE_CONFIRM_FORCED_CANCEL_ROLL"] =
{
    text = "Are you sure you want to delete %s's roll for item %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        LootReserve.Server:DeleteRoll(self.data.Player, self.data.Item);
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

StaticPopupDialogs["LOOTRESERVE_CONFIRM_GLOBAL_PROFILE_ENABLE"] =
{
    text = "By enabling global profile you acknowledge that all the mess you can create by e.g. swapping between characters who are in different raid groups will be on your conscience.|n|nDo you want to enable global profile?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        LootReserveGlobalSave.Server.GlobalProfile = LootReserveCharacterSave.Server;
        LootReserve.Server.Settings.UseGlobalProfile = true;
        LootReserve.Server:Load();
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
};

StaticPopupDialogs["LOOTRESERVE_CONFIRM_GLOBAL_PROFILE_DISABLE"] =
{
    text = "Disabling global profile will revert you back to using sessions stored on your other characters before you turned global profile on. Your current character will adopt the current session.|n|nDo you want to disable global profile?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self)
        LootReserveCharacterSave.Server = LootReserveGlobalSave.Server.GlobalProfile;
        LootReserveGlobalSave.Server.GlobalProfile = nil;
        LootReserve.Server.Settings.UseGlobalProfile = false;
        LootReserve.Server:Load();
        LootReserve.Server:Startup();
        LootReserve.Server:UpdateReserveList();
        LootReserve.Server:UpdateRollList();
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
};

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

function LootReserve.Server:GetChatChannel(announcement)
    if IsInRaid() then
        return self.Settings.ChatAsRaidWarning[announcement] and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) and "RAID_WARNING" or "RAID";
    elseif IsInGroup() then
        return "PARTY";
    elseif LootReserve.Comm.SoloDebug then
        return "WHISPER", UnitName("player");
    else
        return "PARTY";
    end
end

function LootReserve.Server:HasRelevantRecentChat(chat, player)
    if not chat or not chat[player] then return false; end
    if #chat[player] > 1 then return true; end
    local time, type, text = strsplit("|", chat[player][1], 3);
    return type ~= "SYSTEM";
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
    LootReserveCharacterSave.Server = LootReserveCharacterSave.Server or { };
    LootReserveGlobalSave.Server = LootReserveGlobalSave.Server or { };

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

    loadInto(self, LootReserveGlobalSave.Server, "NewSessionSettings");
    loadInto(self, LootReserveGlobalSave.Server, "Settings");

    if self.Settings.UseGlobalProfile then
        LootReserveGlobalSave.Server.GlobalProfile = LootReserveGlobalSave.Server.GlobalProfile or { };
        self.SaveProfile = LootReserveGlobalSave.Server.GlobalProfile;
    else
        self.SaveProfile = LootReserveCharacterSave.Server;
    end
    loadInto(self, self.SaveProfile, "CurrentSession");
    loadInto(self, self.SaveProfile, "RequestedRoll");
    loadInto(self, self.SaveProfile, "RollHistory");
    loadInto(self, self.SaveProfile, "RecentLoot");

    for name, key in pairs(LootReserve.Constants.ChatAnnouncement) do
        if self.Settings.ChatAsRaidWarning[key] == nil then
            self.Settings.ChatAsRaidWarning[key] = true;
        end
    end

    -- Expire session if more than 1 hour has passed since the player was last online
    if self.CurrentSession and self.CurrentSession.LogoutTime and time() > self.CurrentSession.LogoutTime + 3600 then
        self.CurrentSession = nil;
    end
    
    -- Verify that all the required fields are present in the session
    if self.CurrentSession then
        local function verifySessionField(field)
            if self.CurrentSession and self.CurrentSession[field] == nil then
                self.CurrentSession = nil;
            end
        end

        local fields = { "AcceptingReserves", "Settings", "StartTime", "Duration", "DurationEndTimestamp", "Members", "ItemReserves" };
        for _, field in ipairs(fields) do
            verifySessionField(field);
        end
    end

    -- Rearm the duration timer, to make it expire at about the same time (second precision) as it would've otherwise if the server didn't log out/reload UI
    -- Unless the timer would've expired during that time, in which case set it to a dummy 1 second to allow the code to finish reserves properly upon expiration
    if self.CurrentSession and self.CurrentSession.AcceptingReserves and self.CurrentSession.Duration ~= 0 then
        self.CurrentSession.Duration = math.max(1, self.CurrentSession.DurationEndTimestamp - time());
    end

    -- Same for current roll
    if self.RequestedRoll and self.RequestedRoll.MaxDuration and self.RequestedRoll.Duration ~= 0 then
        self.RequestedRoll.Duration = math.max(1, self.RequestedRoll.StartTime + self.RequestedRoll.MaxDuration - time());
    end

    -- Update the UI according to loaded settings
    self:LoadNewSessionSessings();
end

function LootReserve.Server:Startup()
    -- Hook roll handlers if needed
    if self.RequestedRoll then
        self:PrepareRequestRoll();
    end

    if self.CurrentSession and self:CanBeServer() then
        -- Hook handlers
        self:PrepareSession();
        -- Inform other players about ongoing session
        LootReserve.Comm:BroadcastSessionInfo();
        -- Update UI
        if self.CurrentSession.AcceptingReserves then
            self:SessionStarted();
        else
            self:SessionStopped();
        end
        self:UpdateReserveList();

        self.Window:Show();

        -- Immediately after logging in retrieving raid member names might not work (names not yet cached?)
        -- so update the UI a little bit later, otherwise reserving players will show up as "(not in raid)"
        -- until the next group roster change
        C_Timer.After(5, function()
            self:UpdateReserveList();
            self:UpdateRollList();
        end);
    end

    -- Show reserves even if no longer the server, just a failsafe
    self:UpdateReserveList();

    -- Hook events to record recent loot and track looters
    self:PrepareLootTracking();
end

function LootReserve.Server:PrepareLootTracking()
    if self.LootTrackingRegistered then return; end
    self.LootTrackingRegistered = true;

    local loot = formatToRegexp(LOOT_ITEM);
    local lootMultiple = formatToRegexp(LOOT_ITEM_MULTIPLE);
    local lootSelf = formatToRegexp(LOOT_ITEM_SELF);
    local lootSelfMultiple = formatToRegexp(LOOT_ITEM_SELF_MULTIPLE);
    LootReserve:RegisterEvent("CHAT_MSG_LOOT", function(text)
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
        if looter and item and count then
            removeFromTable(self.RecentLoot, item);
            table.insert(self.RecentLoot, item);
            while #self.RecentLoot > 10 do
                table.remove(self.RecentLoot, 1);
            end

            if self.CurrentSession and self.ReservableItems[item] then
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
        end
    end);
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

        LootReserve:RegisterEvent("PLAYER_LOGOUT", function()
            if self.CurrentSession then
                self.CurrentSession.LogoutTime = time();
            end
        end);

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
            self:UpdateRollList();
            self:UpdateAddonUsers();
        end
        
        LootReserve:RegisterEvent("GROUP_ROSTER_UPDATE", UpdateGroupMembers);
        LootReserve:RegisterEvent("UNIT_NAME_UPDATE", function(unit)
            if unit and (stringStartsWith(unit, "raid") or stringStartsWith(unit, "party")) then
                UpdateGroupMembers();
            end
        end);
        LootReserve:RegisterEvent("UNIT_CONNECTION", function(unit)
            if unit and (stringStartsWith(unit, "raid") or stringStartsWith(unit, "party")) then
                UpdateGroupMembers();
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
                                                if string.find(GetItemInfo(item):upper(), text) and not LootReserve:Contains(matches, item) then
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
        StartTime = time(),
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
    self.SaveProfile.CurrentSession = self.CurrentSession;

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
    LootReserve.Comm:BroadcastSessionInfo(true);
    if self.CurrentSession.Settings.ChatFallback then
        local category = LootReserve.Data.Categories[self.CurrentSession.Settings.LootCategory];
        local duration = self.CurrentSession.Settings.Duration
        local count = self.CurrentSession.Settings.MaxReservesPerPlayer;
        LootReserve:SendChatMessage(format("Loot reserves are now started%s%s. %d reserved %s per character. Whisper !reserve ItemLinkOrName",
            category and format(" for %s", category.Name) or "",
            duration ~= 0 and format(" and will last for %d:%02d minutes", math.floor(duration / 60), duration % 60) or "",
            count,
            count == 1 and "item" or "items"
        ), self:GetChatChannel(LootReserve.Constants.ChatAnnouncement.SessionStart));
    end

    self:UpdateReserveList();

    self:SessionStarted();
    return true;
end

function LootReserve.Server:ResumeSession()
    if not self.CurrentSession then
        LootReserve:ShowError("Loot reserves haven't been started");
        return;
    end

    self.CurrentSession.AcceptingReserves = true;
    self.CurrentSession.DurationEndTimestamp = time() + math.floor(self.CurrentSession.Duration);
    LootReserve.Comm:BroadcastSessionInfo();

    if self.CurrentSession.Settings.ChatFallback then
        LootReserve:SendChatMessage("Accepting loot reserves again. Whisper !reserve ItemLinkOrName", self:GetChatChannel(LootReserve.Constants.ChatAnnouncement.SessionResume));
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
    LootReserve.Comm:BroadcastSessionInfo();
    LootReserve.Comm:SendSessionStop();

    if self.CurrentSession.Settings.ChatFallback then
        LootReserve:SendChatMessage("No longer accepting loot reserves", self:GetChatChannel(LootReserve.Constants.ChatAnnouncement.SessionStop));
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

    if self.RequestedRoll and not self.RequestedRoll.Custom then
        self:CancelRollRequest(self.RequestedRoll.Item);
    end

    LootReserve.Comm:SendSessionReset();

    self.CurrentSession = nil;
    self.SaveProfile.CurrentSession = self.CurrentSession;

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
        if self.Settings.ChatUpdates then
            WhisperOthers();
        end
    end

    self:UpdateReserveList();
end

function LootReserve.Server:CancelReserve(player, item, chat, forced)
    if not LootReserve:IsPlayerOnline(player) and not forced then
        LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.NotInRaid, 0);
        if chat then LootReserve:SendChatMessage("You are not in the raid", "WHISPER", player); end
        return;
    end

    if not self.CurrentSession or (not self.CurrentSession.AcceptingReserves and not forced) then
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

    if self:IsRolling(item) and not self.RequestedRoll.Custom then
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
        if self.Settings.ChatUpdates then
            WhisperOthers();
        end
    end

    self:UpdateReserveList();
    self:UpdateReserveListRolls();
end

function LootReserve.Server:IsRolling(item)
    return self.RequestedRoll and self.RequestedRoll.Item == item;
end

function LootReserve.Server:ExpireRollRequest()
    if self.RequestedRoll then
        if self:GetWinningRollAndPlayers() then
            -- If someone rolled on this phase - end the roll
            if self.Settings.RollFinishOnExpire then
                self:FinishRollRequest(self.RequestedRoll.Item);
            end
        else
            -- If nobody rolled on this phase - advance to the next
            if self.Settings.RollAdvanceOnExpire then
                if not self:AdvanceRollPhase(self.RequestedRoll.Item) then
                    -- If the phase cannot advance (i.e. because we ran out of phases) - end the roll
                    if self.Settings.RollFinishOnExpire then
                        self:FinishRollRequest(self.RequestedRoll.Item);
                    end
                end
            elseif not self.RequestedRoll.Phases or #self.RequestedRoll.Phases <= 1 then
                -- If no more phases remaining - end the roll
                if self.Settings.RollFinishOnExpire then
                    self:FinishRollRequest(self.RequestedRoll.Item);
                end
            end
        end

        self:RollExpired();
    end
end

function LootReserve.Server:GetWinningRollAndPlayers()
    if self.RequestedRoll then
        local highestRoll = 0;
        local highestPlayers = { };
        for player, roll in pairs(self.RequestedRoll.Players) do
            if highestRoll <= roll and LootReserve:IsPlayerOnline(player) then
                if highestRoll ~= roll then
                    table.wipe(highestPlayers);
                end
                table.insert(highestPlayers, player);
                highestRoll = roll;
            end
        end
        if highestRoll > 0 then
            return highestRoll, highestPlayers;
        end
    end
end

function LootReserve.Server:ResolveRollTie(item)
    if self:IsRolling(item) then
        local roll, players = self:GetWinningRollAndPlayers();
        if roll and players and #players > 1 then
            local function Announce()
                local name, link = GetItemInfo(item);
                if not name or not link then
                    C_Timer.After(0.25, Announce);
                    return;
                end

                LootReserve:SendChatMessage(format("Tie for %s between players %s. All rolled %d. Please /roll again", link, strjoin(", ", unpack(players)), roll), self:GetChatChannel(LootReserve.Constants.ChatAnnouncement.RollTie));
            end
            Announce();

            if self.RequestedRoll.Custom then
                self:CancelRollRequest(item);
                self:RequestCustomRoll(item, self.Settings.RollLimitDuration and self.Settings.RollDuration or nil, nil, players);
            else
                self:CancelRollRequest(item);
                self:RequestRoll(item, nil, nil, players);
            end
        end
    end
end

function LootReserve.Server:FinishRollRequest(item)
    if self:IsRolling(item) then
        local roll, players = self:GetWinningRollAndPlayers();
        if roll and players then
            local function Announce()
                local name, link = GetItemInfo(item);
                if not name or not link then
                    C_Timer.After(0.25, Announce);
                    return;
                end

                LootReserve:SendChatMessage(format(self.RequestedRoll.RaidRoll and "%s won %s%s via raid-roll" or "%s won %s%s with a roll of %d", strjoin(", ", unpack(players)), LootReserve:FixLink(link), self.RequestedRoll.Phases and format(" for %s", self.RequestedRoll.Phases[1] or "") or "", roll), self:GetChatChannel(LootReserve.Constants.ChatAnnouncement.RollWinner));
            end
            Announce();
        end

        self:CancelRollRequest(item);
    end
end

function LootReserve.Server:AdvanceRollPhase(item)
    if self:IsRolling(item) then
        if self:GetWinningRollAndPlayers() then return; end
        if not self.RequestedRoll.Custom then return; end

        local phases = deepcopy(self.RequestedRoll.Phases);
        if not phases or #phases <= 1 then return; end
        table.remove(phases, 1);

        self:CancelRollRequest(item);
        self:RequestCustomRoll(item, self.Settings.RollLimitDuration and self.Settings.RollDuration or nil, phases);
        return true;
    end
end

function LootReserve.Server:CancelRollRequest(item)
    if self:IsRolling(item) then
        -- Cleanup chat from players who didn't roll to reduce memory and storage space usage
        if self.RequestedRoll.Chat then
            local toRemove = { };
            for player in pairs(self.RequestedRoll.Chat) do
                if not self.RequestedRoll.Players[player] then
                    table.insert(toRemove, player);
                end
            end
            for _, player in ipairs(toRemove) do
                self.RequestedRoll.Chat[player] = nil;
            end
        end

        table.insert(self.RollHistory, self.RequestedRoll);

        LootReserve.Comm:BroadcastRequestRoll(0, { }, self.RequestedRoll.Custom or self.RequestedRoll.RaidRoll);
        self.RequestedRoll = nil;
        self.SaveProfile.RequestedRoll = self.RequestedRoll;
        self:UpdateReserveListRolls();
        self:UpdateRollList();
    end
end

function LootReserve.Server:CanRoll(player)
    local roll = self.RequestedRoll;
    -- Roll must exist
    if not roll then return false; end
    -- Roll must not have expired yet
    if roll.MaxDuration and roll.Duration == 0 then return false; end
    -- Player must be online and in raid
    if not LootReserve:IsPlayerOnline(player) then return false; end
    -- Player must be allowed to roll if the roll is limited to specific players
    if roll.AllowedPlayers and not LootReserve:Contains(roll.AllowedPlayers, player) then return false; end
    -- Only raid roll creator is allowed to re-roll the raid-roll
    if roll.RaidRoll then return player == Ambiguate(UnitName("player"), "short"); end
    -- Player must have reserved the item if the roll is for a reserved item
    if not self.RequestedRoll.Custom and not self.RequestedRoll.Players[player] then return false; end
    -- Player cannot roll if they had rolled previously, but are allowed to roll if they passed on the item
    if self.RequestedRoll.Players[player] and self.RequestedRoll.Players[player] ~= 0 and self.RequestedRoll.Players[player] ~= -1 then return false; end
    -- Player cannot roll if their previous roll was deleted
    if self.RequestedRoll.Players[player] == -2 then return false; end

    return true;
end

function LootReserve.Server:PrepareRequestRoll()
    if self.RequestedRoll and self.RequestedRoll.Duration and not self.RollDurationUpdateRegistered then
        self.RollDurationUpdateRegistered = true;
        LootReserve:RegisterUpdate(function(elapsed)
            if self.RequestedRoll and self.RequestedRoll.Duration and self.RequestedRoll.Duration ~= 0 then
                if self.RequestedRoll.Duration > elapsed then
                    self.RequestedRoll.Duration = self.RequestedRoll.Duration - elapsed;
                else
                    self.RequestedRoll.Duration = 0;
                    self:ExpireRollRequest();
                end
            end
        end);
    end

    if not self.RollMatcherRegistered then
        self.RollMatcherRegistered = true;
        local rollMatcher = formatToRegexp(RANDOM_ROLL_RESULT);
        LootReserve:RegisterEvent("CHAT_MSG_SYSTEM", function(text)
            if self.RequestedRoll then
                local player, roll, min, max = text:match(rollMatcher);
                if player and roll and min == "1" and (max == "100" or self.RequestedRoll.RaidRoll and tonumber(max) == GetNumGroupMembers()) and tonumber(roll) and self:CanRoll(player) then
                    -- Re-roll the raid-roll
                    if self.RequestedRoll.RaidRoll then
                        table.wipe(self.RequestedRoll.Players);

                        local subgroups = { };
                        for i = 1, NUM_RAID_GROUPS do
                            subgroups[i] = { };
                        end
                        for i = 1, MAX_RAID_MEMBERS do
                            local name, _, subgroup, _, _, _, _, online = GetRaidRosterInfo(i);
                            if name and subgroup then
                                table.insert(subgroups[subgroup], Ambiguate(name, "short"));
                            end
                        end
                        local raid = { };
                        for _, subgroup in ipairs(subgroups) do
                            for _, player in ipairs(subgroup) do
                                table.insert(raid, player);
                            end
                        end

                        if tonumber(max) ~= #raid or #raid ~= GetNumGroupMembers() then return; end

                        player = raid[tonumber(roll)];
                    else
                        self.RequestedRoll.Chat = self.RequestedRoll.Chat or { };
                        self.RequestedRoll.Chat[player] = self.RequestedRoll.Chat[player] or { };
                        table.insert(self.RequestedRoll.Chat[player], format("%d|%s|%s", time(), "SYSTEM", text));
                    end

                    self.RequestedRoll.Players[player] = tonumber(roll);
                    self:UpdateReserveListRolls();
                    self:UpdateRollList();
                end
            end
        end);

        local chatTypes =
        {
            "CHAT_MSG_WHISPER",
            "CHAT_MSG_SAY",
            "CHAT_MSG_YELL",
            "CHAT_MSG_PARTY",
            "CHAT_MSG_PARTY_LEADER",
            "CHAT_MSG_RAID",
            "CHAT_MSG_RAID_LEADER",
            "CHAT_MSG_RAID_WARNING",
            "CHAT_MSG_EMOTE",
            "CHAT_MSG_GUILD",
            "CHAT_MSG_OFFICER",
        };
        for _, type in ipairs(chatTypes) do
            local savedType = type:gsub("CHAT_MSG_", "");
            LootReserve:RegisterEvent(type, function(text, sender)
                if self.RequestedRoll then
                    local player = Ambiguate(sender, "short");
                    self.RequestedRoll.Chat = self.RequestedRoll.Chat or { };
                    self.RequestedRoll.Chat[player] = self.RequestedRoll.Chat[player] or { };
                    table.insert(self.RequestedRoll.Chat[player], format("%d|%s|%s", time(), savedType, text));
                    self:UpdateReserveListChat();
                    self:UpdateRollListChat();
                end
            end);
        end
    end
end

function LootReserve.Server:RequestRoll(item, duration, phases, allowedPlayers)
    if not self.CurrentSession then
        LootReserve:ShowError("Loot reserves haven't been started");
        return;
    end

    local reserve = self.CurrentSession.ItemReserves[item];
    if not reserve then
        LootReserve:ShowError("That item is not reserved by anyone");
        return;
    end

    self.RequestedRoll =
    {
        Item = item,
        StartTime = time(),
        MaxDuration = duration and duration > 0 and duration or nil,
        Duration = duration and duration > 0 and duration or nil,
        Phases = phases and #phases > 0 and phases or nil,
        Custom = nil,
        Players = { },
        AllowedPlayers = allowedPlayers,
    };
    self.SaveProfile.RequestedRoll = self.RequestedRoll;

    for _, player in ipairs(allowedPlayers or reserve.Players) do
        self.RequestedRoll.Players[player] = 0;
    end

    self:PrepareRequestRoll();

    LootReserve.Comm:BroadcastRequestRoll(item, allowedPlayers or reserve.Players, self.RequestedRoll.Custom, self.RequestedRoll.Duration, self.RequestedRoll.MaxDuration, self.RequestedRoll.Phases and self.RequestedRoll.Phases[1] or "");

    if self.CurrentSession.Settings.ChatFallback then
        local durationStr = "";
        if self.RequestedRoll.MaxDuration then
            local time = self.RequestedRoll.MaxDuration;
            durationStr = time < 60      and format(" (%d %s)", time,      time ==  1 and "sec" or "secs")
                       or time % 60 == 0 and format(" (%d %s)", time / 60, time == 60 and "min" or "mins")
                       or                    format(" (%d:%02d mins)", math.floor(time / 60), time % 60);
        end

        local function BroadcastRoll()
            local name, link = GetItemInfo(item);
            if not name or not link then
                C_Timer.After(0.25, BroadcastRoll);
                return;
            end

            LootReserve:SendChatMessage(format("%s - roll on reserved %s%s", strjoin(", ", unpack(allowedPlayers or reserve.Players)), LootReserve:FixLink(link), durationStr), self:GetChatChannel(LootReserve.Constants.ChatAnnouncement.RollStartReserved));

            for player, roll in pairs(self.RequestedRoll.Players) do
                if roll == 0 and LootReserve:IsPlayerOnline(player) and not self:IsAddonUser(player) then
                    LootReserve:SendChatMessage(format("Please /roll on %s you reserved.%s", link, durationStr), "WHISPER", player);
                end
            end
        end
        BroadcastRoll();
    end

    self:UpdateReserveListRolls();
    self:UpdateRollList();
end

function LootReserve.Server:RequestCustomRoll(item, duration, phases, allowedPlayers)
    self.RequestedRoll =
    {
        Item = item,
        StartTime = time(),
        MaxDuration = duration and duration > 0 and duration or nil,
        Duration = duration and duration > 0 and duration or nil,
        Phases = phases and #phases > 0 and phases or nil,
        Custom = true,
        Players = { },
        AllowedPlayers = allowedPlayers,
    };
    self.SaveProfile.RequestedRoll = self.RequestedRoll;

    if allowedPlayers then
        for _, player in ipairs(allowedPlayers) do
            self.RequestedRoll.Players[player] = 0;
        end
    end

    self:PrepareRequestRoll();

    local players = allowedPlayers or { };
    if not allowedPlayers then
        for i = 1, MAX_RAID_MEMBERS do
            local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(i);
            if LootReserve.Comm.SoloDebug and i == 1 then
                name = UnitName("player");
                online = true;
            end
            if name and online then
                name = Ambiguate(name, "short");
                table.insert(players, name);
            end
        end
    end

    LootReserve.Comm:BroadcastRequestRoll(item, players, true, self.RequestedRoll.Duration, self.RequestedRoll.MaxDuration, self.RequestedRoll.Phases and self.RequestedRoll.Phases[1] or "");

    if not self.CurrentSession or self.CurrentSession.Settings.ChatFallback then
        local durationStr = "";
        if self.RequestedRoll.MaxDuration then
            local time = self.RequestedRoll.MaxDuration;
            durationStr = time < 60      and format(" (%d %s)", time,      time ==  1 and "sec" or "secs")
                       or time % 60 == 0 and format(" (%d %s)", time / 60, time == 60 and "min" or "mins")
                       or                    format(" (%d:%02d mins)", math.floor(time / 60), time % 60);
        end

        local function BroadcastRoll()
            local name, link = GetItemInfo(item);
            if not name or not link then
                C_Timer.After(0.25, BroadcastRoll);
                return;
            end

            if allowedPlayers then
                -- Should already be announced in LootReserve.Server:ResolveRollTie
                --LootReserve:SendChatMessage(format("%s - roll on %s%s", strjoin(", ", unpack(allowedPlayers)), LootReserve:FixLink(link), durationStr), self:GetChatChannel(LootReserve.Constants.ChatAnnouncement.RollStartCustom));

                for player, roll in pairs(self.RequestedRoll.Players) do
                    if roll == 0 and LootReserve:IsPlayerOnline(player) and not self:IsAddonUser(player) then
                        LootReserve:SendChatMessage(format("Please /roll on %s.%s", link, durationStr), "WHISPER", player);
                    end
                end
            else
                LootReserve:SendChatMessage(format("Roll%s on %s%s", self.RequestedRoll.Phases and format(" for %s", self.RequestedRoll.Phases[1] or "") or "", link, durationStr), self:GetChatChannel(LootReserve.Constants.ChatAnnouncement.RollStartCustom));
            end
        end
        BroadcastRoll();
    end

    self:UpdateRollList();
end

function LootReserve.Server:RaidRoll(item)
    self.RequestedRoll =
    {
        Item = item,
        StartTime = time(),
        RaidRoll = true,
        Players = { },
        AllowedPlayers = { Ambiguate(UnitName("player"), "short") },
    };
    self.SaveProfile.RequestedRoll = self.RequestedRoll;

    self:PrepareRequestRoll();
    RandomRoll(1, GetNumGroupMembers());

    self:UpdateRollList();
end

function LootReserve.Server:PassRoll(player, item)
    if not self:IsRolling(item) or not self.RequestedRoll.Players[player] or self.RequestedRoll.Players[player] < 0 then
        return;
    end

    self.RequestedRoll.Players[player] = -1;

    self:UpdateReserveListRolls();
    self:UpdateRollListRolls();
end

function LootReserve.Server:DeleteRoll(player, item)
    if not self:IsRolling(item) or not self.RequestedRoll.Players[player] or self.RequestedRoll.Players[player] < 0 then
        return;
    end

    if self.RequestedRoll.RaidRoll then
        RandomRoll(1, GetNumGroupMembers());
        return;
    end

    self.RequestedRoll.Players[player] = -2;

    LootReserve.Comm:SendDeletedRoll(player, item);
    if not self.CurrentSession or self.CurrentSession.Settings.ChatFallback then
        local function WhisperPlayer()
            local name, link = GetItemInfo(item);
            if not name or not link then
                C_Timer.After(0.25, BroadcastRoll);
                return;
            end

            LootReserve:SendChatMessage(format("Your roll on item %s was deleted.", link), "WHISPER", player);
        end
        if not self:IsAddonUser(player) then
            WhisperPlayer();
        end
    end

    self:UpdateReserveListRolls();
    self:UpdateRollListRolls();
end

function LootReserve.Server:WhisperAllWithoutReserves()
    if not self.CurrentSession then return; end
    if not self.CurrentSession.AcceptingReserves then return; end

    for player, member in pairs(self.CurrentSession.Members) do
        if #member.ReservedItems == 0 and member.ReservesLeft > 0 and LootReserve:IsPlayerOnline(player) then
            LootReserve:SendChatMessage(format("Don't forget to reserve your items. You have %d %s left. Whisper !reserve ItemLinkOrName",
                member.ReservesLeft,
                member.ReservesLeft == 1 and "reserve" or "reserves"
            ), "WHISPER", player);
        end
    end
end

function LootReserve.Server:BroadcastInstructions()
    if not self.CurrentSession then return; end
    if not self.CurrentSession.AcceptingReserves then return; end

    LootReserve:SendChatMessage("Loot reserves are currently ongoing. Whisper !reserve ItemLinkOrName", self:GetChatChannel(LootReserve.Constants.ChatAnnouncement.SessionInstructions));
end
