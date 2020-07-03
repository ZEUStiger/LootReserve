function LootReserve.Server:UpdateReserveListRolls(lockdown)
    lockdown = lockdown or InCombatLockdown();

    local list = (lockdown and self.Window.PanelReservesLockdown or self.Window.PanelReserves).Scroll.Container;
    list.Frames = list.Frames or { };

    for _, frame in ipairs(list.Frames) do
        if frame:IsShown() then
            local rollingThisItem = self:IsRolling(frame.Item);

            frame.ReservesFrame.HeaderRoll:SetShown(rollingThisItem);
            frame.RequestRollButton.CancelIcon:SetShown(rollingThisItem);

            local highest = 0;
            if self.RequestedRoll then
                for player, roll in pairs(self.RequestedRoll.Players) do
                    if highest < roll and LootReserve:IsPlayerOnline(player) then
                        highest = roll;
                    end
                end
            end

            for _, button in ipairs(frame.ReservesFrame.Players) do
                if button:IsShown() then
                    if rollingThisItem and self.RequestedRoll.Players[button.Player] then
                        local roll = self.RequestedRoll.Players[button.Player];
                        local winner = roll > 0 and highest > 0 and roll == highest;
                        local pass = roll == -1;
                        local deleted = roll == -2;
                        local color = not LootReserve:IsPlayerOnline(button.Player) and GRAY_FONT_COLOR or winner and GREEN_FONT_COLOR or pass and GRAY_FONT_COLOR or deleted and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR;
                        button.Roll:Show();
                        button.Roll:SetText(roll > 0 and tostring(roll) or pass and "PASS" or deleted and "DEL" or "...");
                        button.Roll:SetTextColor(color.r, color.g, color.b);
                        button.WinnerHighlight:SetShown(winner);
                    else
                        button.Roll:Hide();
                        button.WinnerHighlight:Hide();
                    end
                end
            end
        end
    end
end

function LootReserve.Server:UpdateReserveList(lockdown)
    lockdown = lockdown or InCombatLockdown();

    local filter = LootReserve:TransformSearchText(self.Window.Search:GetText());
    if #filter == 0 then
        filter = nil;
    end

    local list = (lockdown and self.Window.PanelReservesLockdown or self.Window.PanelReserves).Scroll.Container;
    list.Frames = list.Frames or { };
    list.LastIndex = 0;
    list.ContentHeight = 0;

    -- Clear everything
    for _, frame in ipairs(list.Frames) do
        frame:Hide();
    end

    local totalPlayers = 0;
    if self.CurrentSession then
        for _, member in pairs(self.CurrentSession.Members) do
            if #member.ReservedItems > 0 then
                totalPlayers = totalPlayers + 1;
            end
        end
    end
    self.Window.ButtonMenu:SetText(format("|cFF00FF00%d|r/%d", totalPlayers, GetNumGroupMembers()));
    if GameTooltip:IsOwned(self.Window.ButtonMenu) then
        self.Window.ButtonMenu:UpdateTooltip();
    end

    if not self.CurrentSession then
        return;
    end
    
    local function createFrame(item, reserve)
        list.LastIndex = list.LastIndex + 1;
        local frame = list.Frames[list.LastIndex];
        while not frame do
            frame = CreateFrame("Frame", nil, list, "LootReserveReserveListTemplate");
            table.insert(list.Frames, frame);
            frame = list.Frames[list.LastIndex];
        end

        frame:Show();

        frame.Item = item;

        local name, link, _, _, _, _, _, _, _, texture = GetItemInfo(item);
        frame.Link = link;

        frame.ItemFrame.Icon:SetTexture(texture);
        frame.ItemFrame.Name:SetText((link or name or "|cFFFF4000Loading...|r"):gsub("[%[%]]", ""));
        local tracking = self.CurrentSession.LootTracking[item];
        local fade = false;
        if tracking then
            local players = "";
            for player, count in pairs(tracking.Players) do
                players = players .. (#players > 0 and ", " or "") .. LootReserve:ColoredPlayer(player) .. (count > 1 and format(" (%d)", count) or "");
            end
            frame.ItemFrame.Misc:SetText("Looted by " .. players);
            fade = false;
        else
            frame.ItemFrame.Misc:SetText("Not looted");
            fade = self.Settings.ReservesSorting == LootReserve.Constants.ReservesSorting.ByLooter and next(self.CurrentSession.LootTracking) ~= nil;
        end
        frame:SetAlpha(fade and 0.25 or 1);

        local reservesHeight = 5 + 12 + 2;
        local last = 0;
        frame.ReservesFrame.Players = frame.ReservesFrame.Players or { };
        for i, player in ipairs(reserve.Players) do
            if i > #frame.ReservesFrame.Players then
                local button = CreateFrame("Button", nil, frame.ReservesFrame, lockdown and "LootReserveReserveListPlayerTemplate" or "LootReserveReserveListPlayerSecureTemplate");
                table.insert(frame.ReservesFrame.Players, button);
            end
            local unit = LootReserve:GetRaidUnitID(player);
            local button = frame.ReservesFrame.Players[i];
            button:Show();
            button.Player = player;
            button.Unit = unit;
            if not lockdown then
                button:SetAttribute("unit", unit);
            end
            button.Name:SetText(format("%s%s", LootReserve:ColoredPlayer(player), LootReserve:IsPlayerOnline(player) == nil and "|cFF808080 (not in raid)|r" or ""));
            button.Roll:SetText("");
            button.WinnerHighlight:Hide();
            button:SetPoint("TOPLEFT", frame.ReservesFrame, "TOPLEFT", 0, 5 - reservesHeight);
            button:SetPoint("TOPRIGHT", frame.ReservesFrame, "TOPRIGHT", 0, 5 - reservesHeight);
            reservesHeight = reservesHeight + button:GetHeight();
            last = i;
        end
        for i = last + 1, #frame.ReservesFrame.Players do
            frame.ReservesFrame.Players[i]:Hide();
        end

        frame:SetHeight(44 + reservesHeight);
        frame:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -list.ContentHeight);
        frame:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -list.ContentHeight);
        list.ContentHeight = list.ContentHeight + frame:GetHeight();
    end

    local function matchesFilter(item, reserve, filter)
        filter = LootReserve:TransformSearchText(filter or "");
        if #filter == 0 then
            return true;
        end

        local name, link = GetItemInfo(item);
        if name then
            if string.find(name:upper(), filter) then
                return true;
            end
        end

        for _, player in ipairs(reserve.Players) do
            if string.find(player:upper(), filter) then
                return true;
            end
        end

        return false;
    end

    local missingName = false;
    local function getSortingTime(reserve)
        return reserve.StartTime;
    end
    local function getSortingName(reserve)
        local name = GetItemInfo(reserve.Item);
        if not name then
            missingName = true;
        end
        return (name or ""):upper();
    end
    local function getSortingSource(reserve)
        for id, category in LootReserve:Ordered(LootReserve.Data.Categories) do
            if category.Children and (not self.CurrentSession or id == self.CurrentSession.Settings.LootCategory) then
                for childIndex, child in ipairs(category.Children) do
                    if child.Loot then
                        for lootIndex, loot in ipairs(child.Loot) do
                            if loot == reserve.Item then
                                return id * 10000 + childIndex * 100 + lootIndex;
                            end
                        end
                    end
                end
            end
        end
        return 100000000;
    end
    local function getSortingLooter(reserve)
        local tracking = self.CurrentSession.LootTracking[reserve.Item];
        if tracking then
            for player, _ in LootReserve:Ordered(tracking.Players) do
                return player:upper();
            end
        else
            return "ZZZZZZZZZZZZ";
        end
    end

    local sorting = self.Settings.ReservesSorting;
        if sorting == LootReserve.Constants.ReservesSorting.ByTime   then sorting = getSortingTime;
    elseif sorting == LootReserve.Constants.ReservesSorting.ByName   then sorting = getSortingName;
    elseif sorting == LootReserve.Constants.ReservesSorting.BySource then sorting = getSortingSource;
    elseif sorting == LootReserve.Constants.ReservesSorting.ByLooter then sorting = getSortingLooter;
    else sorting = nil; end

    local function sorter(a, b)
        if sorting then
            local aOrder, bOrder = sorting(a), sorting(b);
            if aOrder ~= bOrder then
                return aOrder < bOrder;
            end
        end

        return a.Item < b.Item;
    end
    
    for item, reserve in LootReserve:Ordered(self.CurrentSession.ItemReserves, sorter) do
        if not filter or matchesFilter(item, reserve, filter) then
            createFrame(item, reserve);
        end
    end
    for i = list.LastIndex + 1, #list.Frames do
        list.Frames[i]:Hide();
    end

    list:SetSize(list:GetParent():GetWidth(), math.max(list.ContentHeight or 0, list:GetParent():GetHeight() - 1));

    self:UpdateReserveListRolls(lockdown);
end

function LootReserve.Server:UpdateRollListRolls(lockdown)
    lockdown = lockdown or InCombatLockdown();

    local list = (lockdown and self.Window.PanelRollsLockdown or self.Window.PanelRolls).Scroll.Container;
    list.Frames = list.Frames or { };

    for i, frame in ipairs(list.Frames) do
        if frame:IsShown() and frame.Roll then
            local rollingThisItem = self:IsRolling(frame.Item);

            frame.ReservesFrame.HeaderRoll:Show();
            frame.RequestRollButton.CancelIcon:SetShown(not frame.Historical and rollingThisItem);

            local highest = 0;
            for player, roll in pairs(frame.Roll.Players) do
                if highest < roll and (frame.Historical or LootReserve:IsPlayerOnline(player)) then
                    highest = roll;
                end
            end

            for _, button in ipairs(frame.ReservesFrame.Players) do
                if button:IsShown() then
                    if frame.Roll.Players[button.Player] then
                        local roll = frame.Roll.Players[button.Player];
                        local winner = roll > 0 and highest > 0 and roll == highest;
                        local pass = roll == -1;
                        local deleted = roll == -2;
                        local color = winner and GREEN_FONT_COLOR or pass and GRAY_FONT_COLOR or deleted and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR;
                        button.Roll:Show();
                        button.Roll:SetText(roll > 0 and tostring(roll) or pass and "PASS" or deleted and "DEL" or "...");
                        button.Roll:SetTextColor(color.r, color.g, color.b);
                        button.WinnerHighlight:SetShown(winner);
                    else
                        button.Roll:Hide();
                        button.WinnerHighlight:Hide();
                    end
                end
            end
        end
    end
end

function LootReserve.Server:UpdateRollList(lockdown)
    lockdown = lockdown or InCombatLockdown();

    local filter = LootReserve:TransformSearchText(self.Window.Search:GetText());
    if #filter == 0 then
        filter = nil;
    end

    local list = (lockdown and self.Window.PanelRollsLockdown or self.Window.PanelRolls).Scroll.Container;
    list.Frames = list.Frames or { };
    list.LastIndex = 0;
    list.ContentHeight = 0;

    -- Clear everything
    for _, frame in ipairs(list.Frames) do
        frame:Hide();
    end

    local firstHistorical = true;
    if list.HistoryHeader then
        list.HistoryHeader:Hide();
    else
        list.HistoryHeader = CreateFrame("Frame", nil, list, "LootReserveRollHistoryHeader");
    end

    local function createFrame(item, roll, historical)
        list.LastIndex = list.LastIndex + 1;
        local frame = list.Frames[list.LastIndex];
        while not frame do
            frame = CreateFrame("Frame", nil, list, item and "LootReserveReserveListTemplate" or "LootReserveRollPlaceholderTemplate");
            table.insert(list.Frames, frame);
            frame = list.Frames[list.LastIndex];
        end

        frame:Show();

        if item and roll then
            frame.Item = item;

            local name, link, _, _, _, type, subtype, _, _, texture = GetItemInfo(item);
            if subtype and type ~= subtype then
                type = type .. ", " .. subtype;
            end
            frame.Link = link;
            frame.Historical = historical;
            frame.Roll = roll;

            frame:SetBackdropBorderColor(historical and 0.25 or 1, historical and 0.25 or 1, historical and 0.25 or 1);
            frame.RequestRollButton:SetShown(not historical);
            frame.RequestRollButton:SetWidth(frame.RequestRollButton:IsShown() and 32 or 0.00001);
            frame.ItemFrame.Icon:SetTexture(texture);
            frame.ItemFrame.Name:SetText((link or name or "|cFFFF4000Loading...|r"):gsub("[%[%]]", ""));

            if historical then
                frame.ItemFrame.Misc:SetText(roll.StartTime and date(format("%%B%s%%e  %%H:%%M", date("*t", roll.StartTime).day < 10 and "" or " "), roll.StartTime) or "");
            else
                local reservers = 0;
                if LootReserve.Server.CurrentSession then
                    local reserve = LootReserve.Server.CurrentSession.ItemReserves[item];
                    reservers = reserve and #reserve.Players or 0;
                end
                frame.ItemFrame.Misc:SetText(reservers > 0 and format("Reserved by %d |4player:players;", reservers) or "Not reserved");
            end

            local reservesHeight = 5 + 12 + 2;
            local last = 0;
            frame.ReservesFrame.Players = frame.ReservesFrame.Players or { };
            for player, roll in LootReserve:Ordered(roll.Players, function(aRoll, bRoll, aPlayer, bPlayer)
                if aRoll ~= bRoll then
                    return aRoll > bRoll;
                else
                    return aPlayer < bPlayer;
                end
            end) do
                last = last + 1;
                if last > #frame.ReservesFrame.Players then
                    local button = CreateFrame("Button", nil, frame.ReservesFrame, lockdown and "LootReserveReserveListPlayerTemplate" or "LootReserveReserveListPlayerSecureTemplate");
                    table.insert(frame.ReservesFrame.Players, button);
                end
                local unit = LootReserve:GetRaidUnitID(player);
                local button = frame.ReservesFrame.Players[last];
                button:Show();
                button.Player = player;
                button.Unit = unit;
                if not lockdown then
                    button:SetAttribute("unit", unit);
                end
                button.Name:SetText(format("%s%s", LootReserve:ColoredPlayer(player), not historical and LootReserve:IsPlayerOnline(player) == nil and "|cFF808080 (not in raid)|r" or ""));
                button.Roll:SetText("");
                button.WinnerHighlight:Hide();
                button:SetPoint("TOPLEFT", frame.ReservesFrame, "TOPLEFT", 0, 5 - reservesHeight);
                button:SetPoint("TOPRIGHT", frame.ReservesFrame, "TOPRIGHT", 0, 5 - reservesHeight);
                reservesHeight = reservesHeight + button:GetHeight();
            end
            for i = last + 1, #frame.ReservesFrame.Players do
                frame.ReservesFrame.Players[i]:Hide();
            end

            frame.ReservesFrame.HeaderPlayer:SetText(roll.Custom and "Rolled by" or "Reserved by");
            frame.ReservesFrame.NoRollsPlaceholder:SetShown(last == 0);
            if frame.ReservesFrame.NoRollsPlaceholder:IsShown() then
                reservesHeight = reservesHeight + 16;
            end

            frame:SetHeight(44 + reservesHeight);
        else
            frame:SetShown(not self.RequestedRoll);
            frame:SetHeight(frame:IsShown() and 45 or 0.00001);
        end

        if historical and firstHistorical then
            firstHistorical = false;
            list.HistoryHeader:Show();
            list.HistoryHeader:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -list.ContentHeight);
            list.HistoryHeader:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -list.ContentHeight);
            list.ContentHeight = list.ContentHeight + list.HistoryHeader:GetHeight();
        end

        frame:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -list.ContentHeight);
        frame:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -list.ContentHeight);
        list.ContentHeight = list.ContentHeight + frame:GetHeight();
    end

    local function matchesFilter(item, roll, filter)
        filter = LootReserve:TransformSearchText(filter or "");
        if #filter == 0 then
            return true;
        end

        local name, link = GetItemInfo(item);
        if name then
            if string.find(name:upper(), filter) then
                return true;
            end
        end

        for player, _ in pairs(roll.Players) do
            if string.find(player:upper(), filter) then
                return true;
            end
        end

        return false;
    end

    createFrame();
    if self.CurrentSession then
        if self.RequestedRoll then
            if not filter or matchesFilter(self.RequestedRoll.Item, self.RequestedRoll, filter) then
                createFrame(self.RequestedRoll.Item, self.RequestedRoll, false);
            end
        end
    else
        list.Frames[1]:Hide();
        list.ContentHeight = 0;
    end
    for i = #self.RollHistory, 1, -1 do
        local roll = self.RollHistory[i];
        if not filter or matchesFilter(roll.Item, roll, filter) then
            createFrame(roll.Item, roll, true);
        end
    end
    for i = list.LastIndex + 1, #list.Frames do
        list.Frames[i]:Hide();
    end

    list:SetSize(list:GetParent():GetWidth(), math.max(list.ContentHeight or 0, list:GetParent():GetHeight() - 1));

    self:UpdateRollListRolls(lockdown);
end

function LootReserve.Server:OnWindowTabClick(tab)
    PanelTemplates_Tab_OnClick(tab, self.Window);
    PanelTemplates_SetTab(self.Window, tab:GetID());
    self:SetWindowTab(tab:GetID());
    CloseMenus();
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB);
end

function LootReserve.Server:SetWindowTab(tab)
    if tab == 1 then
        self.Window.InsetBg:SetPoint("TOPLEFT", self.Window, "TOPLEFT", 4, -24);
        self.Window.Duration:Hide();
        self.Window.Search:Hide();
        self.Window.ButtonMenu:Hide();
    elseif tab == 2 then
        self.Window.InsetBg:SetPoint("TOPLEFT", self.Window.Search, "BOTTOMLEFT", -6, 0);
        self.Window.Duration:SetShown(self.CurrentSession and self.CurrentSession.AcceptingReserves and self.CurrentSession.Duration ~= 0 and self.CurrentSession.Settings.Duration ~= 0);
        self.Window.Search:Show();
        self.Window.ButtonMenu:Show();
        if self.Window.Duration:IsShown() then
            self.Window.Search:SetPoint("TOPLEFT", self.Window.Duration, "BOTTOMLEFT", 3, -3);
            self.Window.Search:SetPoint("TOPRIGHT", self.Window.Duration, "BOTTOMRIGHT", 3 - 80, -3);
            if not InCombatLockdown() then
                self.Window.PanelReserves:SetPoint("TOPLEFT", self.Window, "TOPLEFT", 7, -61);
            end
        else
            self.Window.Search:SetPoint("TOPLEFT", self.Window, "TOPLEFT", 10, -25);
            self.Window.Search:SetPoint("TOPRIGHT", self.Window, "TOPRIGHT", -7 - 80, -25);
            if not InCombatLockdown() then
                self.Window.PanelReserves:SetPoint("TOPLEFT", self.Window, "TOPLEFT", 7, -48);
            end
        end
    elseif tab == 3 then
        self.Window.InsetBg:SetPoint("TOPLEFT", self.Window.Search, "BOTTOMLEFT", -6, 0);
        self.Window.Duration:Hide();
        self.Window.Search:Show();
        self.Window.ButtonMenu:Hide();
        self.Window.Search:SetPoint("TOPLEFT", self.Window, "TOPLEFT", 10, -25);
        self.Window.Search:SetPoint("TOPRIGHT", self.Window, "TOPRIGHT", -7, -25);
        if not InCombatLockdown() then
            self.Window.PanelRolls:SetPoint("TOPLEFT", self.Window, "TOPLEFT", 7, -48);
        end
    end

    for i, panel in ipairs(self.Window.Panels) do
        if panel == self.Window.PanelReserves and InCombatLockdown() then
            panel = self.Window.PanelReservesLockdown;
        end
        if panel == self.Window.PanelRolls and InCombatLockdown() then
            panel = self.Window.PanelRollsLockdown;
        end
        panel:SetShown(i == tab);
    end
    self:UpdateServerAuthority();
end

function LootReserve.Server:OnWindowLoad(window)
    self.Window = window;
    self.Window.TopLeftCorner:SetSize(32, 32); -- Blizzard UI bug?
    self.Window.TitleText:SetPoint("TOP", self.Window, "TOP", 0, -4);
    self.Window.TitleText:SetText("Loot Reserve Server");
    self.Window:SetMinResize(230, 360);
    PanelTemplates_SetNumTabs(self.Window, 3);
    PanelTemplates_SetTab(self.Window, 1);
    self:SetWindowTab(1);
    self:UpdateServerAuthority();
    self:LoadNewSessionSessings();

    local function updateAuthority() self:UpdateServerAuthority(); end
    LootReserve:RegisterEvent("GROUP_JOINED", updateAuthority);
    LootReserve:RegisterEvent("GROUP_LEFT", updateAuthority);
    LootReserve:RegisterEvent("PARTY_LEADER_CHANGED", updateAuthority);
    LootReserve:RegisterEvent("PARTY_LOOT_METHOD_CHANGED", updateAuthority);
    LootReserve:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(item, success)
        if item and self.CurrentSession and self.CurrentSession.ItemReserves[item] then
            self:UpdateReserveList();
        end
        if item and self.RequestedRoll and self.RequestedRoll.Item == item then
            self:UpdateRollList();
            return;
        end
        if item and self.RollHistory then
            for _, roll in ipairs(self.RollHistory) do
                if roll.Item == item then
                    self:UpdateRollList();
                    return;
                end
            end
        end
    end);
    LootReserve:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        -- Swap out the real (tained) reserves and rolls panels for slightly less functional ones, but ones that don't have taint
        if self.Window.PanelReserves:IsShown() then
            self.Window.PanelReserves:Hide();
            self.Window.PanelReservesLockdown:Show();
        end
        if self.Window.PanelRolls:IsShown() then
            self.Window.PanelRolls:Hide();
            self.Window.PanelRollsLockdown:Show();
        end
        -- Sync changes between real and lockdown panels
        self:UpdateReserveList(true);
        self.Window.PanelReservesLockdown.Scroll:UpdateScrollChildRect();
        self.Window.PanelReservesLockdown.Scroll:SetVerticalScroll(self.Window.PanelReserves.Scroll:GetVerticalScroll());
        self:UpdateRollList(true);
        self.Window.PanelRollsLockdown.Scroll:UpdateScrollChildRect();
        self.Window.PanelRollsLockdown.Scroll:SetVerticalScroll(self.Window.PanelRolls.Scroll:GetVerticalScroll());
    end);
    LootReserve:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        -- Restore original reserves panel
        if self.Window.PanelReservesLockdown:IsShown() then
            self.Window.PanelReservesLockdown:Hide();
            self.Window.PanelReserves:Show();
        end
        if self.Window.PanelRollsLockdown:IsShown() then
            self.Window.PanelRollsLockdown:Hide();
            self.Window.PanelRolls:Show();
        end
        -- Sync changes between real and lockdown panels
        self:UpdateReserveList();
        self.Window.PanelReserves.Scroll:UpdateScrollChildRect();
        self.Window.PanelReserves.Scroll:SetVerticalScroll(self.Window.PanelReservesLockdown.Scroll:GetVerticalScroll());
        self:UpdateRollList();
        self.Window.PanelRolls.Scroll:UpdateScrollChildRect();
        self.Window.PanelRolls.Scroll:SetVerticalScroll(self.Window.PanelRollsLockdown.Scroll:GetVerticalScroll());
    end);
end

local activeSessionChanges =
{
    ButtonStartSession = "Hide",
    ButtonStopSession = "Show",
    ButtonResetSession = "Hide",
    LabelRaid = "Label",
    DropDownRaid = "DropDown",
    LabelCount = "Label",
    EditBoxCount = "Disable",
    LabelDuration = "Label",
    DropDownDuration = "DropDown",

    Apply = function(self, panel, active)
        for k, action in pairs(self) do
            local region = panel[k];
            if action == "Hide" then
                region:SetShown(not active);
            elseif action == "Show" then
                region:SetShown(active);
            elseif action == "DropDown" then
                if active then
                    UIDropDownMenu_DisableDropDown(region);
                else
                    UIDropDownMenu_EnableDropDown(region);
                end
            elseif action == "Disable" then
                region:SetEnabled(not active);
            elseif action == "Label" then
                local color = active and GRAY_FONT_COLOR or NORMAL_FONT_COLOR;
                region:SetTextColor(color.r, color.g, color.b);
            end
        end
    end
};

function LootReserve.Server:SessionStarted()
    activeSessionChanges:Apply(self.Window.PanelSession, true);
    self.Window.PanelSession.Duration:SetShown(self.CurrentSession.Settings.Duration ~= 0);
    self.Window.PanelSession.ButtonStartSession:Hide();
    self.Window.PanelSession.ButtonStopSession:Show();
    self.Window.PanelSession.ButtonResetSession:Hide();
    self:OnWindowTabClick(self.Window.TabReserves);
    PlaySound(SOUNDKIT.GS_CHARACTER_SELECTION_ENTER_WORLD);
    self:UpdateServerAuthority();
    self:UpdateRollList();
end

function LootReserve.Server:SessionStopped()
    activeSessionChanges:Apply(self.Window.PanelSession, true);
    self.Window.PanelSession.Duration:SetShown(self.CurrentSession.Settings.Duration ~= 0);
    self.Window.PanelSession.ButtonStartSession:Show();
    self.Window.PanelSession.ButtonStopSession:Hide();
    self.Window.PanelSession.ButtonResetSession:Show();
    if self.Window.PanelReserves:IsShown() or self.Window.PanelReservesLockdown:IsShown() then
        LootReserve.Server:SetWindowTab(2);
    end
    if self.Window.PanelRolls:IsShown() or self.Window.PanelRollsLockdown:IsShown() then
        LootReserve.Server:SetWindowTab(3);
    end
    self:UpdateServerAuthority();
    self:UpdateRollList();
end

function LootReserve.Server:SessionReset()
    activeSessionChanges:Apply(self.Window.PanelSession, false);
    self.Window.PanelSession.Duration:Hide();
    self.Window.PanelSession.ButtonStartSession:Show();
    self.Window.PanelSession.ButtonStopSession:Hide();
    self.Window.PanelSession.ButtonResetSession:Hide();
    self:UpdateServerAuthority();
    self:UpdateRollList();
end

function LootReserve.Server:UpdateServerAuthority()
    local hasAuthority = self:CanBeServer();
    self.Window.PanelSession.ButtonStartSession:SetEnabled(hasAuthority);
    self.Window.PanelSession:SetAlpha((hasAuthority or self.CurrentSession) and 1 or 0.15);
    self.Window.NoAuthority:SetShown(not hasAuthority and not self.CurrentSession and self.Window.PanelSession:IsShown());
end

function LootReserve.Server:UpdateAddonUsers()
    if GameTooltip:IsOwned(self.Window.PanelSession.AddonUsers) then
        self.Window.PanelSession.AddonUsers:UpdateTooltip();
    end
    local count = 0;
    for player, compatible in pairs(self.AddonUsers) do
        if compatible then
            count = count + 1;
        end
    end
    self.Window.PanelSession.AddonUsers.Text:SetText(format("%d/%d", count, GetNumGroupMembers()));
    self.Window.PanelSession.AddonUsers:SetShown(#self.AddonUsers > 0 or GetNumGroupMembers() > 0);
end

function LootReserve.Server:LoadNewSessionSessings()
    local function setDropDownValue(dropDown, value)
        ToggleDropDownMenu(nil, nil, dropDown);
        UIDropDownMenu_SetSelectedValue(dropDown, value);
        CloseMenus();
    end

    setDropDownValue(self.Window.PanelSession.DropDownRaid, self.NewSessionSettings.LootCategory);
    self.Window.PanelSession.EditBoxCount:SetText(tostring(self.NewSessionSettings.MaxReservesPerPlayer));
    setDropDownValue(self.Window.PanelSession.DropDownDuration, self.NewSessionSettings.Duration);
end
