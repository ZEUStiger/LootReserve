LootReserve = LootReserve or { };
LootReserve.Client =
{
    SessionServer = nil,

    RemainingReserves = 0,

    ItemReserves = { }, -- { [ItemID] = { "Playername", "Playername", ... }, ... }
    PendingItems = { },

    SelectedCategory = nil,
};

function LootReserve.Client:StartSession(server)
print("Start Session" .. (server or "nil"));
    self.SessionServer = server;
    self.RemainingReserves = 0;
    self.ItemReserves = { };
    self.PendingItems = { };
end

function LootReserve.Client:GetRemainingReserves()
    return self.SessionServer and self.RemainingReserves or 0;
end
function LootReserve.Client:HasRemainingReserves()
    return self:GetRemainingReserves() > 0;
end

function LootReserve.Client:IsItemReserved(item)
    return self:GetItemReservers(item) > 0;
end
function LootReserve.Client:IsItemReservedByMe(item)
    for _, player in ipairs(self:GetItemReservers(item)) do
        if player == UnitName("player") then
            return true;
        end
    end
    return false;
end
function LootReserve.Client:GetItemReservers(item)
    if not self.SessionServer then return { }; end
    return self.ItemReserves[item] or { };
end

function LootReserve.Client:IsItemPending(item)
    return self.PendingItems[item];
end
function LootReserve.Client:SetItemPending(item, pending)
    self.PendingItems[item] = pending or nil;
end

function LootReserve.Client:Reserve(item)
    if not self.SessionServer then return; end
    LootReserve.Client:SetItemPending(item, true);
    LootReserve.Client:UpdateReserveStatus();
    LootReserve.Comm:SendReserveItem(item);
end

function LootReserve.Client:CancelReserve(item)
    if not self.SessionServer then return; end
    LootReserve.Client:SetItemPending(item, true);
    LootReserve.Client:UpdateReserveStatus();
    LootReserve.Comm:SendCancelReserve(item);
end
