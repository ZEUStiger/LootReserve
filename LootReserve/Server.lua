LootReserve = LootReserve or { };
LootReserve.Server =
{
    CurrentSession = nil,
    NewSessionSettings =
    {
        LootCategory = 1,
        MaxReservesPerPlayer = 1,
    },
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
local function contains(table, item)
    for _, i in ipairs(table) do
        if i == item then
            return true;
        end
    end
    return false;
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

function LootReserve.Server:CanBeServer()
    return IsInRaid() and (UnitIsGroupLeader("player") or IsMasterLooter());
end

function LootReserve.Server:StartSession()
    if not self:CanBeServer() then
        LootReserve:Print("|cFFFF4000You don't have enough authority to start a loot reserve session|r");
        return;
    end

    if self.CurrentSession then
        LootReserve:Print("|cFFFF4000Session already in progress|r");
        return;
    end

    self.CurrentSession =
    {
        Settings = deepcopy(self.NewSessionSettings),
        Members = { },
        ItemReserves = { }, -- { [ItemID] = { PlayerName, PlayerName, ... }, ... }
    };

    for i = 1, MAX_RAID_MEMBERS do
        local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(i);
        if name then
            name = Ambiguate(name, "short");
            self.CurrentSession.Members[name] =
            {
                ReservesLeft = self.CurrentSession.Settings.MaxReservesPerPlayer,
                ReservedItems = { },
            };
        end
    end

    -- TOOD: Redo as Members iteration
    for i = 1, MAX_RAID_MEMBERS do
        local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(i);
        if name and online then
            name = Ambiguate(name, "short");
            LootReserve.Comm:SendSessionInfo(name, self.CurrentSession);
        end
    end
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

    if contains(member.ReservedItems, item) then
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

    self.CurrentSession.ItemReserves[item] = self.CurrentSession.ItemReserves[item] or { };
    table.insert(self.CurrentSession.ItemReserves[item], player);
    LootReserve.Comm:SendReserveInfo(nil, item, self.CurrentSession.ItemReserves[item]);
end

function LootReserve.Server:CancelReserve(player, item)
    if not self.CurrentSession then
        LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.NoSession, 0);
        return;
    end

    local member = self.CurrentSession.Members[player];
    if not member then
        LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.NotMember, 0);
        return;
    end

    if not contains(member.ReservedItems, item) then
        LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.NotReserved, member.ReservesLeft);
        return;
    end

    member.ReservesLeft = math.min(member.ReservesLeft + 1, self.CurrentSession.Settings.MaxReservesPerPlayer);
    removeFromTable(member.ReservedItems, item);
    LootReserve.Comm:SendCancelReserveResult(player, item, LootReserve.Constants.CancelReserveResult.OK, member.ReservesLeft);

    self.CurrentSession.ItemReserves[item] = self.CurrentSession.ItemReserves[item] or { };
    removeFromTable(self.CurrentSession.ItemReserves[item], player);
    LootReserve.Comm:SendReserveInfo(nil, item, self.CurrentSession.ItemReserves[item]);
end
