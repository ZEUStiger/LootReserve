-- TODO: Ability for server to forcibly remove reserves
-- TODO: Stop client session when the server or the client leaves the group
-- TODO: Chat command support and announcements in raid chat
-- TODO: Scroll up on category change

LootReserve = LibStub("AceAddon-3.0"):NewAddon("LootReserve", "AceConsole-3.0", "AceEvent-3.0");

LootReserve.Version = "2020-06-10";
LootReserve.MinAllowedVersion = "2020-06-10";
LootReserve.Enabled = true;
LootReserve.EventFrame = CreateFrame("Frame");
LootReserve.EventFrame:Hide();

function LootReserve:RegisterEvent(event, handler)
    LootReserve.EventFrame:RegisterEvent(event);
    if not LootReserve.EventFrame.RegisteredEvents then
        LootReserve.EventFrame.RegisteredEvents = { };
        LootReserve.EventFrame:SetScript("OnEvent", function(self, event, ...)
            local handlers = self.RegisteredEvents[event];
            if handlers then
                for _, handler in ipairs(handlers) do
                    handler(...);
                end
            end
        end);
    end

    LootReserve.EventFrame.RegisteredEvents[event] = LootReserve.EventFrame.RegisteredEvents[event] or { };
    table.insert(LootReserve.EventFrame.RegisteredEvents[event], handler);
end

function LootReserve:GetPlayerClassColor(player)
    local className, classFilename, classId = UnitClass(player);
    if classFilename then
        local colors = RAID_CLASS_COLORS[classFilename];
        if colors then
            return colors.colorStr;
        else
            return "ff808080";
        end
    end
end

function LootReserve:Ordered(tbl)
    local function __genOrderedIndex(t)
        local orderedIndex = { };
        for key in pairs(t) do
            table.insert(orderedIndex, key);
        end
        table.sort(orderedIndex);
        return orderedIndex;
    end

    local function orderedNext(t, state)
        local key;
        if state == nil then
            t.__orderedIndex = __genOrderedIndex(t)
            key = t.__orderedIndex[1];
        else
            for i = 1,table.getn(t.__orderedIndex) do
                if t.__orderedIndex[i] == state then
                    key = t.__orderedIndex[i + 1];
                end
            end
        end

        if key then
            return key, t[key];
        end

        t.__orderedIndex = nil;
        return
    end

    return orderedNext, tbl, nil;
end

function LootReserve:OnInitialize()
    -- Called when the addon is loaded

    -- Print a message to the chat frame
    self:Print("OnInitialize Event Fired: Hello")
end

function LootReserve:OnEnable()
    -- Called when the addon is enabled

    -- Print a message to the chat frame
    self:Print("OnEnable Event Fired: Hello, again ;)")
end

function LootReserve:OnDisable()
    -- Called when the addon is disabled
end
