LootReserve = LootReserve or { };
LootReserve.ItemSearch =
{
    LoadingState = nil,
    LoadingThread = nil,
    LoadingTicker = nil,
    Names = { },
    PendingNames = { };
    MaxID = 24283,
};

function LootReserve.ItemSearch:Load()
    if self.LoadingState ~= nil then return; end
    self.LoadingState = false;

    LootReserve:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(item, success)
        if item then
            self.PendingNames[item] = nil;
            if success then
                self.Names[item] = LootReserve:TransformSearchText(GetItemInfo(item) or "");
            end
        end
    end);

    self.LoadingThread = coroutine.create(function()
        for item = 1, self.MaxID do
            if C_Item.DoesItemExistByID(item) then
                local name = GetItemInfo(item);
                if name then
                    self.Names[item] = LootReserve:TransformSearchText(name);
                else
                    self.PendingNames[item] = true;
                end
            end
            if item % 250 == 0 then
                coroutine.yield();
            end
        end
        while next(self.PendingNames) do
            coroutine.yield();
        end
        self.LoadingState = true;
    end);

    self.LoadingTicker = C_Timer.NewTicker(0.05, function()
        coroutine.resume(self.LoadingThread);
        if coroutine.status(self.LoadingThread) == "dead" then
            self.LoadingTicker:Cancel();
        end
    end);
end

function LootReserve.ItemSearch:Search(query)
    self:Load();
    if not self.LoadingState then return; end

    query = LootReserve:TransformSearchText(query);

    local results = { };
    for item, name in pairs(self.Names) do
        if string.find(name, query) then
            table.insert(results, item);
        end
    end
    return results;
end
