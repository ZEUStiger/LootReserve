-- TODO: Stop client session when the server or the client leaves the group
-- TODO: Chat command support and announcements in raid chat
-- TODO: Guild-only checkbox
-- TODO: Show server reserves in item tooltips
-- TODO: Client popup on roll request
-- TODO: Ask to clean up loot list
-- TODO: Vendorstrike easter egg
-- TODO: Disable server window buttons when not authority

LootReserve = LibStub("AceAddon-3.0"):NewAddon("LootReserve", "AceConsole-3.0", "AceEvent-3.0");

LootReserve.Version = "2020-06-10";
LootReserve.MinAllowedVersion = "2020-06-10";
LootReserve.Enabled = true;
LootReserve.EventFrame = CreateFrame("Frame", nil, UIParent);
LootReserve.EventFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0);
LootReserve.EventFrame:SetSize(0, 0);
LootReserve.EventFrame:Show();

StaticPopupDialogs["LOOTRESERVE_GENERIC_ERROR"] =
{
    text = "%s",
    button1 = OK,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
};

function LootReserve:OnInitialize()
end

function LootReserve:OnEnable()
end

function LootReserve:OnDisable()
end

function LootReserve:ShowError(fmt, ...)
    StaticPopup_Show("LOOTRESERVE_GENERIC_ERROR", "|cFFFFD200LootReserve|r|n" .. format(fmt, ...));
end

function LootReserve:PrintError(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD200LootReserve: |r|cFFFF4000" .. format(fmt, ...) .. "|r");
end

function LootReserve:RegisterUpdate(handler)
    LootReserve.EventFrame:HookScript("OnUpdate", function(self, elapsed)
        handler(elapsed);
    end);
end

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
        end
    end
    return "ff808080";
end

function LootReserve:GetRaidUnitID(player)
    for i = 1, MAX_RAID_MEMBERS do
        local unit = UnitName("raid" .. i);
        if unit and Ambiguate(unit, "short") == player then
            return "raid" .. i;
        end
    end

    if self.Comm.SoloDebug and Ambiguate(UnitName("player"), "short") == player then
        return "player";
    end
end

function LootReserve:Ordered(tbl, sorter)
    local function __genOrderedIndex(t)
        local orderedIndex = { };
        for key in pairs(t) do
            table.insert(orderedIndex, key);
        end
        if sorter then
            table.sort(orderedIndex, function(a, b)
                return sorter(t[a], t[b]);
            end);
        else
            table.sort(orderedIndex);
        end
        return orderedIndex;
    end

    local function orderedNext(t, state)
        local key;
        if state == nil then
            t.__orderedIndex = __genOrderedIndex(t)
            key = t.__orderedIndex[1];
        else
            for i = 1, table.getn(t.__orderedIndex) do
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
