LootReserve = LootReserve or { };
LootReserve.Comm =
{
    Prefix = "LootReserve",
    Handlers = { },
    Listening = false,
    Debug = false,
    SoloDebug = false,
};

local Opcodes =
{
    Version = 1,
    ReportIncompatibleVersion = 2,
    Hello = 3,
    SessionInfo = 4,
    SessionStop = 5,
    SessionReset = 6,
    ReserveItem = 7,
    ReserveResult = 8,
    ReserveInfo = 9,
    CancelReserve = 10,
    CancelReserveResult = 11,
    RequestRoll = 12,
    PassRoll = 13,
    DeletedRoll = 14,
};

function LootReserve.Comm:StartListening()
    if not self.Listening then
        self.Listening = true;
        LootReserve:RegisterComm(self.Prefix, function(prefix, text, channel, sender)
            if LootReserve.Enabled and prefix == self.Prefix then
                local opcode, message = strsplit("|", text, 2);
                local handler = self.Handlers[tonumber(opcode)];
                if handler then
                    if self.Debug then
                        print("[DEBUG] Received: " .. text:gsub("|", "||"));
                    end

                    sender = Ambiguate(sender, "short");
                    LootReserve.Server:SetAddonUser(sender, true);
                    handler(sender, strsplit("|", message));
                end
            end
        end);
    end
end

function LootReserve.Comm:CanBroadcast(opcode)
    return LootReserve.Enabled and (self.SoloDebug
        or IsInRaid()
        or IsInGroup() and opcode == Opcodes.RequestRoll
    );
end
function LootReserve.Comm:CanWhisper(target, opcode)
    return LootReserve.Enabled and (self.SoloDebug
        or IsInRaid() and UnitInRaid(target)
        or IsInGroup() and UnitInParty(target) and (opcode == Opcodes.PassRoll and LootReserve.Client.RollRequest and target == LootReserve.Client.RollRequest.Sender
                                                 or opcode == Opcodes.DeletedRoll)
    );
end

function LootReserve.Comm:Broadcast(opcode, ...)
    if not self:CanBroadcast(opcode) then return; end

    local message = format("%d|", opcode);
    for _, part in ipairs({ ... }) do
        if type(part) == "boolean" then
            message = message .. tostring(part and 1 or 0) .. "|";
        else
            message = message .. tostring(part) .. "|";
        end
    end

    if self.Debug then
        print("[DEBUG] Raid Broadcast: " .. message:gsub("|", "||"));
    end

    if self.SoloDebug then
        LootReserve:SendCommMessage(self.Prefix, message, "WHISPER", UnitName("player"));
    else
        LootReserve:SendCommMessage(self.Prefix, message, IsInRaid() and "RAID" or "PARTY");
    end
end
function LootReserve.Comm:Whisper(target, opcode, ...)
    if not self:CanWhisper(target, opcode) then return; end

    local message = format("%d|", opcode);
    for _, part in ipairs({ ... }) do
        if type(part) == "boolean" then
            message = message .. tostring(part and 1 or 0) .. "|";
        else
            message = message .. tostring(part) .. "|";
        end
    end

    if self.Debug then
        print("[DEBUG] Sent to " .. target .. ": " .. message:gsub("|", "||"));
    end

    LootReserve:SendCommMessage(self.Prefix, message, "WHISPER", target);
end
function LootReserve.Comm:Send(target, opcode, ...)
    if target then
        self:Whisper(target, opcode, ...);
    else
        self:Broadcast(opcode, ...);
    end
end
function LootReserve.Comm:WhisperServer(opcode, ...)
    if LootReserve.Client.SessionServer then
        self:Whisper(LootReserve.Client.SessionServer, opcode, ...);
    else
        LootReserve:ShowError("Loot reserves aren't active in your raid");
    end
end

-- Version
function LootReserve.Comm:BroadcastVersion()
    LootReserve.Comm:SendVersion();
end
function LootReserve.Comm:SendVersion(target)
    LootReserve.Comm:Send(target, Opcodes.Version,
        LootReserve.Version,
        LootReserve.MinAllowedVersion);
end
LootReserve.Comm.Handlers[Opcodes.Version] = function(sender, version, minAllowedVersion)
    if LootReserve.LatestKnownVersion >= version then return; end
    LootReserve.LatestKnownVersion = version;

    if LootReserve.Version < minAllowedVersion then
        LootReserve:PrintError("You're using an incompatible outdated version of LootReserve. Please update to version |cFFFFD200%s|r or newer to continue using the addon.", version);
        LootReserve:ShowError("You're using an incompatible outdated version of LootReserve. Please update to version |cFFFFD200%s|r or newer to continue using the addon.", version);
        LootReserve.Comm:BroadcastReportIncompatibleVersion();
        LootReserve.Enabled = false;
    elseif LootReserve.Version < version then
        LootReserve:PrintError("You're using an outdated version of LootReserve. It will continue to work, but please update to version |cFFFFD200%s|r or newer.", version);
    end
end

-- ReportIncompatibleVersion
function LootReserve.Comm:BroadcastReportIncompatibleVersion()
    LootReserve.Comm:Broadcast(Opcodes.ReportIncompatibleVersion);
end
LootReserve.Comm.Handlers[Opcodes.ReportIncompatibleVersion] = function(sender)
    LootReserve.Server:SetAddonUser(sender, false);
end

-- Hello
function LootReserve.Comm:BroadcastHello()
    LootReserve.Comm:Broadcast(Opcodes.Hello);
end
LootReserve.Comm.Handlers[Opcodes.Hello] = function(sender)
    LootReserve.Comm:SendVersion(sender);

    if LootReserve.Server.CurrentSession and LootReserve.Server:CanBeServer() then
        LootReserve.Comm:SendSessionInfo(sender);
    end
    if LootReserve.Server.RequestedRoll and not LootReserve.Server.RequestedRoll.RaidRoll and LootReserve.Server:CanRoll(sender) then
        LootReserve.Comm:SendRequestRoll(sender, LootReserve.Server.RequestedRoll.Item, { sender }, LootReserve.Server.RequestedRoll.Custom, LootReserve.Server.RequestedRoll.Duration, LootReserve.Server.RequestedRoll.MaxDuration);
    end
end

-- SessionInfo
function LootReserve.Comm:BroadcastSessionInfo(starting)
    local session = LootReserve.Server.CurrentSession;
    if session.Settings.Blind then
        for player in pairs(session.Members) do
            if LootReserve:IsPlayerOnline(player) then
                LootReserve.Comm:SendSessionInfo(player, starting);
            end
        end
    else
        LootReserve.Comm:SendSessionInfo(nil, starting);
    end
end
function LootReserve.Comm:SendSessionInfo(target, starting)
    local session = LootReserve.Server.CurrentSession;
    if not session then return; end

    target = target and Ambiguate(target, "short");
    if target and not session.Members[target] then return; end

    local membersInfo = "";
    for player, member in pairs(session.Members) do
        if not target or player == target then
            membersInfo = membersInfo .. (#membersInfo > 0 and ";" or "") .. format("%s=%s", player, strjoin(",", session.Settings.Lock and member.Locked and "#" or member.ReservesLeft));
        end
    end

    local itemReserves = "";
    for item, reserve in pairs(session.ItemReserves) do
        if session.Settings.Blind and target then
            if LootReserve:Contains(reserve.Players, target) then
                itemReserves = itemReserves .. (#itemReserves > 0 and ";" or "") .. format("%d=%s", item, target);
            end
        else
            itemReserves = itemReserves .. (#itemReserves > 0 and ";" or "") .. format("%d=%s", item, strjoin(",", unpack(reserve.Players)));
        end
    end

    local itemConditions = "";
    for item, conditions in pairs(session.Settings.ItemConditions) do
        if LootReserve.Data:IsItemInCategory(item, session.Settings.LootCategory) or conditions.Custom == session.Settings.LootCategory then
            local packed = LootReserve.ItemConditions:Pack(conditions);
            itemConditions = itemConditions .. (#itemConditions > 0 and ";" or "") .. format("%d=%s", item, packed);
        end
    end

    LootReserve.Comm:Send(target, Opcodes.SessionInfo,
        starting == true,
        session.StartTime or 0,
        session.AcceptingReserves,
        membersInfo,
        session.Settings.LootCategory,
        format("%.2f", session.Duration),
        session.Settings.Duration,
        itemReserves,
        itemConditions,
        session.Settings.Blind);
end
LootReserve.Comm.Handlers[Opcodes.SessionInfo] = function(sender, starting, startTime, acceptingReserves, membersInfo, lootCategory, duration, maxDuration, itemReserves, itemConditions, blind)
    starting = tonumber(starting) == 1;
    startTime = tonumber(startTime);
    acceptingReserves = tonumber(acceptingReserves) == 1;
    lootCategory = tonumber(lootCategory);
    duration = tonumber(duration);
    maxDuration = tonumber(maxDuration);
    blind = tonumber(blind) == 1;

    if LootReserve.Client.SessionServer and LootReserve.Client.SessionServer ~= sender and LootReserve.Client.StartTime > startTime then
        LootReserve:ShowError("%s is attempting to broadcast their older loot reserve session, but you're already connected to %s.|n|nPlease tell %s that they need to reset their session.", LootReserve:ColoredPlayer(sender), LootReserve:ColoredPlayer(LootReserve.Client.SessionServer), LootReserve:ColoredPlayer(sender));
        return;
    end

    LootReserve.Client:StartSession(sender, starting, startTime, acceptingReserves, lootCategory, duration, maxDuration, blind);

    LootReserve.Client.RemainingReserves = 0;
    if #membersInfo > 0 then
        membersInfo = { strsplit(";", membersInfo) };
        for _, infoStr in ipairs(membersInfo) do
            local player, info = strsplit("=", infoStr, 2);
            if player == Ambiguate(UnitName("player"), "short") then
                local remainingReserves = strsplit(",", info);
                LootReserve.Client.RemainingReserves = tonumber(remainingReserves) or 0;
                LootReserve.Client.Locked = remainingReserves == "#";
            end
        end
    end

    LootReserve.Client.ItemReserves = { };
    if #itemReserves > 0 then
        itemReserves = { strsplit(";", itemReserves) };
        for _, reserves in ipairs(itemReserves) do
            local item, players = strsplit("=", reserves, 2);
            LootReserve.Client.ItemReserves[tonumber(item)] = #players > 0 and { strsplit(",", players) } or nil;
        end
    end

    LootReserve.Client.ItemConditions = { };
    if #itemConditions > 0 then
        itemConditions = { strsplit(";", itemConditions) };
        for _, conditions in ipairs(itemConditions) do
            local item, packed = strsplit("=", conditions, 2);
            LootReserve.Client.ItemConditions[tonumber(item)] = #packed > 0 and LootReserve.ItemConditions:Unpack(packed, lootCategory) or nil;
        end
    end

    LootReserve.Client:UpdateCategories();
    LootReserve.Client:UpdateLootList();
    if acceptingReserves then
        LootReserve.Client.Window:Show();
    end
end

-- SessionStop
function LootReserve.Comm:SendSessionStop()
    LootReserve.Comm:Broadcast(Opcodes.SessionStop);
end
LootReserve.Comm.Handlers[Opcodes.SessionStop] = function(sender)
    if LootReserve.Client.SessionServer == sender then
        LootReserve.Client:StopSession();
        LootReserve.Client:UpdateReserveStatus();
    end
end

-- SessionStop
function LootReserve.Comm:SendSessionReset()
    LootReserve.Comm:Broadcast(Opcodes.SessionReset);
end
LootReserve.Comm.Handlers[Opcodes.SessionReset] = function(sender)
    if LootReserve.Client.SessionServer == sender then
        LootReserve.Client:ResetSession(sender);
        LootReserve.Client:UpdateCategories();
        LootReserve.Client:UpdateLootList();
    end
end

-- ReserveItem
function LootReserve.Comm:SendReserveItem(item)
    LootReserve.Comm:WhisperServer(Opcodes.ReserveItem,
        item);
end
LootReserve.Comm.Handlers[Opcodes.ReserveItem] = function(sender, item)
    item = tonumber(item);

    if LootReserve.Server.CurrentSession then
        LootReserve.Server:Reserve(sender, item);
    end
end

-- ReserveResult
function LootReserve.Comm:SendReserveResult(target, item, result, remainingReserves)
    LootReserve.Comm:Whisper(target, Opcodes.ReserveResult,
        item,
        result,
        remainingReserves);
end
LootReserve.Comm.Handlers[Opcodes.ReserveResult] = function(sender, item, result, remainingReserves)
    item = tonumber(item);
    result = tonumber(result);
    local locked = remainingReserves == "#";
    remainingReserves = tonumber(remainingReserves) or 0;

    if LootReserve.Client.SessionServer == sender then
        LootReserve.Client.RemainingReserves = remainingReserves;
        LootReserve.Client.Locked = locked;
        local message = "Failed to reserve the item:|n%s"
        if result == LootReserve.Constants.ReserveResult.OK then
            -- OK
        elseif result == LootReserve.Constants.ReserveResult.NotInRaid then
            LootReserve:ShowError(message, "You are not in the raid");
        elseif result == LootReserve.Constants.ReserveResult.NoSession then
            LootReserve:ShowError(message, "Loot reserves aren't active in your raid");
        elseif result == LootReserve.Constants.ReserveResult.NotMember then
            LootReserve:ShowError(message, "You are not participating in loot reserves");
        elseif result == LootReserve.Constants.ReserveResult.ItemNotReservable then
            LootReserve:ShowError(message, "That item cannot be reserved in this raid");
        elseif result == LootReserve.Constants.ReserveResult.AlreadyReserved then
            LootReserve:ShowError(message, "You are already reserving that item");
        elseif result == LootReserve.Constants.ReserveResult.NoReservesLeft then
            LootReserve:ShowError(message, "You already reserved too many items");
        elseif result == LootReserve.Constants.ReserveResult.FailedConditions then
            LootReserve:ShowError(message, "You cannot reserve that item");
        elseif result == LootReserve.Constants.ReserveResult.Locked then
            LootReserve:ShowError(message, "Your reserves are locked-in and cannot be changed anymore");
            LootReserve.Client.Locked = true;
        end

        LootReserve.Client:SetItemPending(item, false);
        LootReserve.Client:UpdateReserveStatus();
    end
end

-- ReserveInfo
function LootReserve.Comm:BroadcastReserveInfo(item, players)
    LootReserve.Comm:SendReserveInfo(nil, item, players);
end
function LootReserve.Comm:SendReserveInfo(target, item, players)
    LootReserve.Comm:Send(target, Opcodes.ReserveInfo,
        item,
        strjoin(",", unpack(players)));
end
LootReserve.Comm.Handlers[Opcodes.ReserveInfo] = function(sender, item, players)
    item = tonumber(item);

    if LootReserve.Client.SessionServer == sender then
        if #players > 0 then
            players = { strsplit(",", players) };
        else
            players = { };
        end
        LootReserve.Client.ItemReserves[item] = players;

        if LootReserve.Client.SelectedCategory and LootReserve.Client.SelectedCategory.Reserves then
            LootReserve.Client:UpdateLootList();
        else
            LootReserve.Client:UpdateReserveStatus();
        end
    end
end

-- CancelReserve
function LootReserve.Comm:SendCancelReserve(item)
    LootReserve.Comm:WhisperServer(Opcodes.CancelReserve,
        item);
end
LootReserve.Comm.Handlers[Opcodes.CancelReserve] = function(sender, item)
    item = tonumber(item);

    if LootReserve.Server.CurrentSession then
        LootReserve.Server:CancelReserve(sender, item);
    end
end

-- CancelReserveResult
function LootReserve.Comm:SendCancelReserveResult(target, item, result, remainingReserves)
    LootReserve.Comm:Whisper(target, Opcodes.CancelReserveResult,
        item,
        result,
        remainingReserves);
end
LootReserve.Comm.Handlers[Opcodes.CancelReserveResult] = function(sender, item, result, remainingReserves)
    item = tonumber(item);
    result = tonumber(result);
    local locked = remainingReserves == "#";
    remainingReserves = tonumber(remainingReserves) or 0;

    if LootReserve.Client.SessionServer == sender then
        LootReserve.Client.RemainingReserves = remainingReserves;
        LootReserve.Client.Locked = locked;
        local message = "Failed to cancel reserve of the item:|n%s"
        if result == LootReserve.Constants.CancelReserveResult.OK then
            -- OK
        elseif result == LootReserve.Constants.CancelReserveResult.NotInRaid then
            LootReserve:ShowError(message, "You are not in the raid");
        elseif result == LootReserve.Constants.CancelReserveResult.NoSession then
            LootReserve:ShowError(message, "Loot reserves aren't active in your raid");
        elseif result == LootReserve.Constants.CancelReserveResult.NotMember then
            LootReserve:ShowError(message, "You are not participating in loot reserves");
        elseif result == LootReserve.Constants.CancelReserveResult.ItemNotReservable then
            LootReserve:ShowError(message, "That item cannot be reserved in this raid");
        elseif result == LootReserve.Constants.CancelReserveResult.NotReserved then
            LootReserve:ShowError(message, "You did not reserve that item");
        elseif result == LootReserve.Constants.CancelReserveResult.Forced then
            local function ShowForced()
                local name, link = GetItemInfo(item);
                if name and link then
                    LootReserve:ShowError("%s removed your reserve for item %s", LootReserve:ColoredPlayer(sender), link);
                    LootReserve:PrintError("%s removed your reserve for item %s", LootReserve:ColoredPlayer(sender), link);
                else
                    C_Timer.After(0.25, ShowForced);
                end
            end
            ShowForced();
        elseif result == LootReserve.Constants.CancelReserveResult.Locked then
            LootReserve:ShowError(message, "Your reserves are locked-in and cannot be changed anymore");
            LootReserve.Client.Locked = true;
        end

        LootReserve.Client:SetItemPending(item, false);
        if LootReserve.Client.SelectedCategory and LootReserve.Client.SelectedCategory.Reserves then
            LootReserve.Client:UpdateLootList();
        else
            LootReserve.Client:UpdateReserveStatus();
        end
    end
end

-- RequestRoll
function LootReserve.Comm:BroadcastRequestRoll(item, players, custom, duration, maxDuration, phase)
    LootReserve.Comm:SendRequestRoll(nil, item, players, custom, duration, maxDuration, phase);
end
function LootReserve.Comm:SendRequestRoll(target, item, players, custom, duration, maxDuration, phase)
    LootReserve.Comm:Send(target, Opcodes.RequestRoll,
        item,
        strjoin(",", unpack(players)),
        custom == true,
        format("%.2f", duration or 0),
        maxDuration or 0,
        phase or "");
end
LootReserve.Comm.Handlers[Opcodes.RequestRoll] = function(sender, item, players, custom, duration, maxDuration, phase)
    item = tonumber(item);
    custom = tonumber(custom) == 1;
    duration = tonumber(duration);
    maxDuration = tonumber(maxDuration);
    phase = phase and #phase > 0 and phase or nil;

    if LootReserve.Client.SessionServer == sender or custom then
        if #players > 0 then
            players = { strsplit(",", players) };
        else
            players = { };
        end
        LootReserve.Client:RollRequested(sender, item, players, custom, duration, maxDuration, phase);
    end
end

-- PassRoll
function LootReserve.Comm:SendPassRoll(item)
    LootReserve.Comm:Whisper(LootReserve.Client.RollRequest.Sender, Opcodes.PassRoll,
        item);
end
LootReserve.Comm.Handlers[Opcodes.PassRoll] = function(sender, item)
    item = tonumber(item);

    if true--[[LootReserve.Server.CurrentSession]] then
        LootReserve.Server:PassRoll(sender, item);
    end
end

-- DeletedRoll
function LootReserve.Comm:SendDeletedRoll(player, item)
    LootReserve.Comm:Whisper(player, Opcodes.DeletedRoll,
        item);
end
LootReserve.Comm.Handlers[Opcodes.DeletedRoll] = function(sender, item)
    item = tonumber(item);

    if true--[[LootReserve.Client.SessionServer == sender]] then
        local function ShowDeleted()
            local name, link = GetItemInfo(item);
            if name and link then
                LootReserve:ShowError("%s deleted your roll for item %s", LootReserve:ColoredPlayer(sender), link);
                LootReserve:PrintError("%s deleted your roll for item %s", LootReserve:ColoredPlayer(sender), link);
            else
                C_Timer.After(0.25, ShowDeleted);
            end
        end
        ShowDeleted();
    end
end
