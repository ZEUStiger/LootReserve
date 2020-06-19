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
        print("[DEBUG] Raid Broadcast: " .. message:gsub("|", "||"));
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
        print("[DEBUG] Sent to " .. target .. ": " .. message:gsub("|", "||"));
    end

    C_ChatInfo.SendAddonMessage(self.Prefix, message, "WHISPER", target);
end
function LootReserve.Comm:WhisperServer(opcode, ...)
    if LootReserve.Client.SessionServer then
        self:Whisper(LootReserve.Client.SessionServer, opcode, ...);
    else
        LootReserve:ShowError("Loot reserves aren't active in your raid");
    end
end

-- Version
function LootReserve.Comm:SendVersion(target)
    LootReserve.Comm:Whisper(target, Opcodes.Version,
        LootReserve.Version,
        LootReserve.MinAllowedVersion);
end
function LootReserve.Comm:BroadcastVersion()
    LootReserve.Comm:Broadcast(Opcodes.Version,
        LootReserve.Version,
        LootReserve.MinAllowedVersion);
end
LootReserve.Comm.Handlers[Opcodes.Version] = function(sender, version, minAllowedVersion)
    if LootReserve.Version < minAllowedVersion then
        LootReserve:PrintError("You're using an incompatible outdated version of LootReserve. Please update to version |cFFFFD200%s|r or newer to continue using the addon.", version);
        LootReserve:ShowError("You're using an incompatible outdated version of LootReserve. Please update to version |cFFFFD200%s|r or newer to continue using the addon.", version);
        LootReserve.Comm:BroadcastReportIncompatibleVersion();
        LootReserve.Enabled = false;
    elseif LootReserve.Version < version then
        LootReserve:PrintError("You're using an outdated version of LootReserve. Please update to version |cFFFFD200%s|r or newer.", version);
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

    if LootReserve.Server.CurrentSession then
        LootReserve.Comm:SendSessionInfo(sender);
    end
end

-- SessionInfo
function LootReserve.Comm:SendSessionInfo(target, starting)
    local session = LootReserve.Server.CurrentSession;
    if not session then return; end

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
        format("%.2f", session.Duration),
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
    remainingReserves = tonumber(remainingReserves);

    if LootReserve.Client.SessionServer == sender then
        LootReserve.Client.RemainingReserves = remainingReserves;
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
    remainingReserves = tonumber(remainingReserves);

    if LootReserve.Client.SessionServer == sender then
        LootReserve.Client.RemainingReserves = remainingReserves;
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
                    LootReserve:ShowError("|c%s%s|r removed your reserve for item %s", LootReserve:GetPlayerClassColor(sender), sender, link);
                    LootReserve:PrintError("|c%s%s|r removed your reserve for item %s", LootReserve:GetPlayerClassColor(sender), sender, link);
                else
                    C_Timer.After(0.25, ShowForced);
                end
            end
            ShowForced();
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
