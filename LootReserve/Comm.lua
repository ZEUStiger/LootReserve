LootReserve = LootReserve or { };
LootReserve.Comm =
{
    Prefix = "LootReserve",
    Handlers = { },
    Listening = false,
    Debug = true,
    SoloDebug = true,
};

local Opcodes =
{
    Version = 1,
    Hello = 2,
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
};

function LootReserve.Comm:StartListening()
    if not self.Listening then
        self.Listening = true;
        C_ChatInfo.RegisterAddonMessagePrefix(self.Prefix);
        LootReserve:RegisterEvent("CHAT_MSG_ADDON", function(prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID)
            if LootReserve.Enabled and prefix == self.Prefix then
                local opcode, message = strsplit("|", text, 2);
                local handler = self.Handlers[tonumber(opcode)];
                if handler then
                    if self.Debug then
                        LootReserve:Print("[DEBUG] Received: " .. text:gsub("|", "||"));
                    end

                    handler(Ambiguate(sender, "short"), strsplit("|", message));
                end
            end
        end);
    end
end

function LootReserve.Comm:CanBroadcast()
    return LootReserve.Enabled and (IsInRaid() or self.Debug);
end
function LootReserve.Comm:CanWhisper(target)
    return LootReserve.Enabled and ((IsInRaid() and UnitInRaid(target)) or self.Debug);
end

function LootReserve.Comm:Broadcast(opcode, ...)
    if not self:CanBroadcast() then return; end

    local message = format("%d|", opcode);
    for _, part in ipairs({ ... }) do
        if type(part) == "boolean" then
            message = message .. tostring(part and 1 or 0) .. "|";
        else
            message = message .. tostring(part) .. "|";
        end
    end

    if self.Debug then
        LootReserve:Print("[DEBUG] Raid Broadcast: " .. message:gsub("|", "||"));
    end

    if self.SoloDebug then
        C_ChatInfo.SendAddonMessage(self.Prefix, message, "WHISPER", UnitName("player"));
    else
        C_ChatInfo.SendAddonMessage(self.Prefix, message, "RAID");
    end
end
function LootReserve.Comm:Whisper(target, opcode, ...)
    if not self:CanWhisper(target) then return; end

    local message = format("%d|", opcode);
    for _, part in ipairs({ ... }) do
        if type(part) == "boolean" then
            message = message .. tostring(part and 1 or 0) .. "|";
        else
            message = message .. tostring(part) .. "|";
        end
    end

    if self.Debug then
        LootReserve:Print("[DEBUG] Sent to " .. target .. ": " .. message:gsub("|", "||"));
    end

    C_ChatInfo.SendAddonMessage(self.Prefix, message, "WHISPER", target);
end
function LootReserve.Comm:WhisperServer(opcode, ...)
    if LootReserve.Client.SessionServer then
        self:Whisper(LootReserve.Client.SessionServer, opcode, ...);
    else
        print("No Active Session");
    end
end
function LootReserve.Comm:BroadcastOrWhisper(target, opcode, ...)
    if target then
        self:Whisper(target, opcode, ...);
    else
        self:Broadcast(opcode, ...);
    end
end

-- Version
function LootReserve.Comm:SendVersion(target)
    LootReserve.Comm:BroadcastOrWhisper(target, Opcodes.Version,
        LootReserve.Version,
        LootReserve.MinAllowedVersion);
end
function LootReserve.Comm:BroadcastVersion()
    self:SendVersion();
end
LootReserve.Comm.Handlers[Opcodes.Version] = function(sender, version, minAllowedVersion)
    if LootReserve.Version < minAllowedVersion then
        LootReserve:PrintError("You're using an incompatible outdated version of LootReserve. Please update to version %s or newer to continue using the addon.", version);
        LootReserve:ShowError("You're using an incompatible outdated version of LootReserve. Please update to version %s or newer to continue using the addon.", version);
        LootReserve.Enabled = false;
    elseif LootReserve.Version < version then
        LootReserve:PrintError("You're using an outdated version of LootReserve. Please update to version %s or newer.", version);
    end
end

-- Hello
function LootReserve.Comm:BroadcastHello()
    LootReserve.Comm:Broadcast(Opcodes.Hello);
end
LootReserve.Comm.Handlers[Opcodes.Hello] = function(sender)
    LootReserve.Comm:SendVersion(sender);

    if LootReserve.Server.CurrentSession then
        LootReserve.Comm:SendSessionInfo(sender, LootReserve.Server.CurrentSession);
    end
end

-- SessionInfo
function LootReserve.Comm:SendSessionInfo(target, session, starting)
    local member = session.Members[Ambiguate(target, "short")];
    if not member then return; end

    local itemReserves = "";
    for item, reserve in pairs(session.ItemReserves) do
        itemReserves = itemReserves .. (#itemReserves > 0 and ";" or "") .. format("%d=%s", item, strjoin(",", unpack(reserve.Players)));
    end

    LootReserve.Comm:Whisper(target, Opcodes.SessionInfo,
        starting and 1 or 0,
        session.AcceptingReserves,
        member.ReservesLeft,
        session.Settings.LootCategory,
        session.Duration,
        session.Settings.Duration,
        itemReserves);
end
LootReserve.Comm.Handlers[Opcodes.SessionInfo] = function(sender, starting, acceptingReserves, remainingReserves, lootCategory, duration, maxDuration, itemReserves)
    starting = tonumber(starting) == 1;
    acceptingReserves = tonumber(acceptingReserves) == 1;
    remainingReserves = tonumber(remainingReserves);
    lootCategory = tonumber(lootCategory);
    duration = tonumber(duration);
    maxDuration = tonumber(maxDuration);

    LootReserve.Client:StartSession(sender, starting, acceptingReserves, remainingReserves, lootCategory, duration, maxDuration);
    LootReserve.Client.ItemReserves = { };
    if #itemReserves > 0 then
        itemReserves = { strsplit(";", itemReserves) };
        for _, reserves in ipairs(itemReserves) do
            local item, players = strsplit("=", reserves, 2);
            LootReserve.Client.ItemReserves[tonumber(item)] = #players > 0 and { strsplit(",", players) } or nil;
        end
    end

    LootReserve.Client:UpdateCategories();
    LootReserve.Client:UpdateLootList();
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
    remainingReserves = tonumber(remainingReserves);

    if LootReserve.Client.SessionServer == sender then
        LootReserve.Client.RemainingReserves = remainingReserves;
        if result == LootReserve.Constants.ReserveResult.OK then
            print("ReserveResult: OK");
        elseif result == LootReserve.Constants.ReserveResult.NoSession then
            print("ReserveResult: NoSession");
        elseif result == LootReserve.Constants.ReserveResult.NotMember then
            print("ReserveResult: NotMember");
        elseif result == LootReserve.Constants.ReserveResult.AlreadyReserved then
            print("ReserveResult: AlreadyReserved");
        elseif result == LootReserve.Constants.ReserveResult.NoReservesLeft then
            print("ReserveResult: NoReservesLeft");
        elseif result == LootReserve.Constants.ReserveResult.ItemNotReservable then
            print("ReserveResult: ItemNotReservable");
        end

        LootReserve.Client:SetItemPending(item, false);
        LootReserve.Client:UpdateReserveStatus();
    end
end

-- ReserveInfo
function LootReserve.Comm:BroadcastReserveInfo(item, players)
    LootReserve.Comm:Broadcast(Opcodes.ReserveInfo,
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

        LootReserve.Client:UpdateReserveStatus();
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
    remainingReserves = tonumber(remainingReserves);

    if LootReserve.Client.SessionServer == sender then
        LootReserve.Client.RemainingReserves = remainingReserves;
        if result == LootReserve.Constants.CancelReserveResult.OK then
            print("CancelReserveResult: OK");
        elseif result == LootReserve.Constants.CancelReserveResult.NoSession then
            print("CancelReserveResult: NoSession");
        elseif result == LootReserve.Constants.CancelReserveResult.NotMember then
            print("CancelReserveResult: NotMember");
        elseif result == LootReserve.Constants.CancelReserveResult.NotReserved then
            print("CancelReserveResult: NotReserved");
        elseif result == LootReserve.Constants.CancelReserveResult.Forced then
            print("CancelReserveResult: Forced");
        elseif result == LootReserve.Constants.CancelReserveResult.ItemNotReservable then
            print("CancelReserveResult: ItemNotReservable");
        end

        LootReserve.Client:SetItemPending(item, false);
        LootReserve.Client:UpdateReserveStatus();
    end
end

-- RequestRoll
function LootReserve.Comm:BroadcastRequestRoll(item, players)
    LootReserve.Comm:Broadcast(Opcodes.RequestRoll,
        item,
        strjoin(",", unpack(players)));
end
LootReserve.Comm.Handlers[Opcodes.RequestRoll] = function(sender, item, players)
    item = tonumber(item);

    if LootReserve.Client.SessionServer == sender then
        if #players > 0 then
            players = { strsplit(",", players) };
        else
            players = { };
        end
        LootReserve.Client:RollRequested(sender, item, players);
    end
end

-- PassRoll
function LootReserve.Comm:SendPassRoll(item)
    LootReserve.Comm:WhisperServer(Opcodes.PassRoll,
        item);
end
LootReserve.Comm.Handlers[Opcodes.PassRoll] = function(sender, item)
    item = tonumber(item);

    if LootReserve.Server.CurrentSession then
        LootReserve.Server:PassRoll(sender, item);
    end
end
