LootReserve = LootReserve or { };
LootReserve.Comm =
{
    Prefix = "LootReserve",
    Handlers = { },
    Listening = false,
    Debug = true,
};

local Opcodes =
{
    Version = 1,
    Hello = 2,
    SessionInfo = 4,
    ReserveItem = 5,
    ReserveResult = 6,
    ReserveInfo = 7,
    CancelReserve = 8,
    CancelReserveResult = 9,
};

function LootReserve.Comm:StartListening()
    if not self.Listening then
        self.Listening = true;
        C_ChatInfo.RegisterAddonMessagePrefix(self.Prefix);
        LootReserve:RegisterEvent("CHAT_MSG_ADDON", function(prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID)
            sender = Ambiguate(sender, "short");

            if prefix == self.Prefix then
                local opcode, message = strsplit("|", text, 2);
                local handler = self.Handlers[tonumber(opcode)];
                if handler then
                    if self.Debug then
                        LootReserve:Print("[DEBUG] Received: " .. text:gsub("|", "||"));
                    end

                    handler(sender, strsplit("|", message));
                end
            end
        end);
    end
end

function LootReserve.Comm:CanBroadcast()
    return IsInRaid() or self.Debug;
end
function LootReserve.Comm:CanWhisper(target)
    return (IsInRaid() and UnitInRaid(target)) or self.Debug;
end

function LootReserve.Comm:Broadcast(opcode, ...)
    if not self:CanBroadcast() then return; end

    local message = format("%d|", opcode);
    for _, part in ipairs({ ... }) do
        message = message .. tostring(part) .. "|";
    end

    if self.Debug then
        LootReserve:Print("[DEBUG] Raid Broadcast: " .. message:gsub("|", "||"));
    end

    C_ChatInfo.SendAddonMessage(self.Prefix, message, "RAID");
end
function LootReserve.Comm:Whisper(target, opcode, ...)
    if not self:CanWhisper(target) then return; end

    local message = format("%d|", opcode);
    for _, part in ipairs({ ... }) do
        message = message .. tostring(part) .. "|";
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
        self:Whisper(target, ...);
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
LootReserve.Comm.Handlers[Opcodes.Version] = function(sender, version, minAllowedVersion)
    if LootReserve.Version < minAllowedVersion then
        LootReserve:Print("|cFFFF4000You're using an incompatible outdated version of LootReserve. Please update to version %s or newer to continue using the addon.|r", version);
        LootReserve.Enabled = false;
    elseif LootReserve.Version < version then
        LootReserve:Print("|cFFFF4000You're using an outdated version of LootReserve. Please update to version %s or newer.|r", version);
    end
end

-- Hello
function LootReserve.Comm:SendHello(target)
    LootReserve.Comm:BroadcastOrWhisper(target, Opcodes.Hello);
end
LootReserve.Comm.Handlers[Opcodes.Hello] = function(sender)
    LootReserve.Comm:SendVersion(sender);

    if LootReserve.Server.CurrentSession then
        LootReserve.Comm:SendSessionInfo(target, LootReserve.Server.CurrentSession);
    end
end

-- SessionInfo
function LootReserve.Comm:SendSessionInfo(target, session)
    local itemReserves = "";
    for item, players in pairs(session.ItemReserves) do
        itemReserves = itemReserves .. (#itemReserves > 0 and ";" or "") .. format("%d=%s", item, strjoin(",", unpack(players)));
    end

    LootReserve.Comm:Whisper(target, Opcodes.SessionInfo,
        session.Members[target].ReservesLeft,
        itemReserves);
end
LootReserve.Comm.Handlers[Opcodes.SessionInfo] = function(sender, remainingReserves, itemReserves)
    remainingReserves = tonumber(remainingReserves);

    LootReserve.Client:StartSession(sender);
    LootReserve.Client.RemainingReserves = tonumber(remainingReserves);
    LootReserve.Client.ItemReserves = { };
    if #itemReserves > 0 then
        itemReserves = { strsplit(";", itemReserves) };
        for _, reserves in ipairs(itemReserves) do
            local item, players = strsplit("=", reserves, 2);
            LootReserve.Client.ItemReserves[tonumber(item)] = { strsplit(",", players) };
        end
    end

    LootReserve.Client:UpdateReserveStatus();
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
        end

        LootReserve.Client:SetItemPending(item, false);
        LootReserve.Client:UpdateReserveStatus();
    end
end

-- ReserveInfo
function LootReserve.Comm:SendReserveInfo(target, item, players)
    LootReserve.Comm:BroadcastOrWhisper(target, Opcodes.ReserveInfo,
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
        end

        LootReserve.Client:SetItemPending(item, false);
        LootReserve.Client:UpdateReserveStatus();
    end
end
