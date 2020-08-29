LootReserve = LootReserve or { };
LootReserve.Client =
{
    -- Server Connection
    SessionServer = nil,

    -- Server Session Info
    StartTime = 0,
    AcceptingReserves = false,
    RemainingReserves = 0,
    LootCategory = nil,
    Duration = nil,
    MaxDuration = nil,
    ItemReserves = { }, -- { [ItemID] = { "Playername", "Playername", ... }, ... }
    ItemConditions = { },
    RollRequest = nil,
    Blind = false,

    Settings =
    {
        RollRequestShow = true,
        RollRequestShowUnusable = false,
        RollRequestGlowOnlyReserved = false,
    },

    PendingItems = { },
    ServerSearchTimeoutTime = nil,
    DurationUpdateRegistered = false,
    SessionEventsRegistered = false,

    SelectedCategory = nil,
};

function LootReserve.Client:Load()
    LootReserveGlobalSave.Client = LootReserveGlobalSave.Client or { };

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
    loadInto(self, LootReserveGlobalSave.Client, "Settings");
end

function LootReserve.Client:SearchForServer(startup)
    if not startup and self.ServerSearchTimeoutTime and time() < self.ServerSearchTimeoutTime then return; end
    self.ServerSearchTimeoutTime = time() + 10;

    LootReserve.Comm:BroadcastHello();
end

function LootReserve.Client:StartSession(server, starting, startTime, acceptingReserves, lootCategory, duration, maxDuration, blind)
    self:ResetSession();
    self.SessionServer = server;
    self.StartTime = startTime;
    self.AcceptingReserves = acceptingReserves;
    self.LootCategory = lootCategory;
    self.Duration = duration;
    self.MaxDuration = maxDuration;
    self.Blind = blind;

    if self.MaxDuration ~= 0 and not self.DurationUpdateRegistered then
        self.DurationUpdateRegistered = true;
        LootReserve:RegisterUpdate(function(elapsed)
            if self.SessionServer and self.AcceptingReserves and self.Duration ~= 0 then
                if self.Duration > elapsed then
                    self.Duration = self.Duration - elapsed;
                else
                    self.Duration = 0;
                    self:StopSession();
                end
            end
        end);
    end

    if not self.SessionEventsRegistered then
        self.SessionEventsRegistered = true;
        
        LootReserve:RegisterEvent("GROUP_LEFT", function()
            if self.SessionServer then
                self:StopSession();
                self:ResetSession();
                self:UpdateCategories();
                self:UpdateLootList();
                self:UpdateReserveStatus();
            end
        end);
        
        LootReserve:RegisterEvent("GROUP_ROSTER_UPDATE", function()
            if self.SessionServer and not UnitInRaid(self.SessionServer) then
                self:StopSession();
                self:ResetSession();
                self:UpdateCategories();
                self:UpdateLootList();
                self:UpdateReserveStatus();
            end
        end);
    end

    if starting then
        PlaySound(SOUNDKIT.GS_CHARACTER_SELECTION_ENTER_WORLD);
    end
end

function LootReserve.Client:StopSession()
    self.AcceptingReserves = false;
end

function LootReserve.Client:ResetSession()
    self.SessionServer = nil;
    self.RemainingReserves = 0;
    self.LootCategory = nil;
    self.ItemReserves = { };
    self.ItemConditions = { };
    self.PendingItems = { };
end

function LootReserve.Client:GetRemainingReserves()
    return self.SessionServer and self.AcceptingReserves and self.RemainingReserves or 0;
end
function LootReserve.Client:HasRemainingReserves()
    return self:GetRemainingReserves() > 0;
end

function LootReserve.Client:IsItemReserved(item)
    return #self:GetItemReservers(item) > 0;
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
    if not self.AcceptingReserves then return; end
    LootReserve.Client:SetItemPending(item, true);
    LootReserve.Client:UpdateReserveStatus();
    LootReserve.Comm:SendReserveItem(item);
end

function LootReserve.Client:CancelReserve(item)
    if not self.SessionServer then return; end
    if not self.AcceptingReserves then return; end
    LootReserve.Client:SetItemPending(item, true);
    LootReserve.Client:UpdateReserveStatus();
    LootReserve.Comm:SendCancelReserve(item);
end
