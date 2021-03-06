local LibCustomGlow = LibStub("LibCustomGlow-1.0");

function LootReserve.Server:UpdateReserveListRolls(lockdown)
    if not self.Window:IsShown() then return; end

    lockdown = lockdown or InCombatLockdown() or not self.Settings.UseUnitFrames;

    local list = (lockdown and self.Window.PanelReservesLockdown or self.Window.PanelReserves).Scroll.Container;
    list.Frames = list.Frames or { };

    for _, frame in ipairs(list.Frames) do
        if frame:IsShown() and frame.ReservesFrame then
            frame.Roll = self:IsRolling(frame.Item) and not self.RequestedRoll.Custom and self.RequestedRoll or nil;

            frame.ReservesFrame.HeaderRoll:SetShown(frame.Roll);
            frame.ReservesFrame.ReportRolls:SetShown(frame.Roll);
            frame.RequestRollButton.CancelIcon:SetShown(frame.Roll and not frame.Historical and self:IsRolling(frame.Item));

            local highest = LootReserve.Constants.RollType.NotRolled;
            if frame.Roll then
                for player, rolls in pairs(frame.Roll.Players) do
                    for _, roll in ipairs(rolls) do
                        if highest < roll and (frame.Historical or LootReserve:IsPlayerOnline(player)) then
                            highest = roll;
                        end
                    end
                end
            end

            for _, button in ipairs(frame.ReservesFrame.Players) do
                if button:IsShown() then
                    if frame.Roll and frame.Roll.Players[button.Player] and frame.Roll.Players[button.Player][button.RollNumber] then
                        local roll = frame.Roll.Players[button.Player][button.RollNumber];
                        local rolled = roll > LootReserve.Constants.RollType.NotRolled;
                        local passed = roll == LootReserve.Constants.RollType.Passed;
                        local deleted = roll == LootReserve.Constants.RollType.Deleted;
                        local winner;
                        if frame.Roll.Winners then
                            winner = LootReserve:Contains(frame.Roll.Winners, button.Player);
                        else
                            winner = rolled and highest > LootReserve.Constants.RollType.NotRolled and roll == highest; -- Backwards compatibility
                        end

                        local color = not LootReserve:IsPlayerOnline(button.Player) and GRAY_FONT_COLOR or winner and GREEN_FONT_COLOR or passed and GRAY_FONT_COLOR or deleted and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR;
                        button.Roll:Show();
                        button.Roll:SetText(rolled and tostring(roll) or passed and "PASS" or deleted and "DEL" or "...");
                        button.Roll:SetTextColor(color.r, color.g, color.b);
                        if LootReserve.Server.Settings.HighlightSameItemWinners and not frame.Historical then
                            button.AlreadyWonHighlight:SetShown(LootReserve.Server:HasAlreadyWon(button.Player, frame.Item));
                            button.WinnerHighlight:Hide();
                        else
                            button.AlreadyWonHighlight:Hide();
                            button.WinnerHighlight:SetShown(winner);
                        end
                    else
                        button.Roll:Hide();
                        button.AlreadyWonHighlight:Hide();
                        button.WinnerHighlight:Hide();
                    end
                end
            end
        end
    end

    self:UpdateReserveListButtons(lockdown);
end

function LootReserve.Server:UpdateReserveListButtons(lockdown)
    if not self.Window:IsShown() then return; end

    lockdown = lockdown or InCombatLockdown() or not self.Settings.UseUnitFrames;

    local list = (lockdown and self.Window.PanelReservesLockdown or self.Window.PanelReserves).Scroll.Container;
    list.Frames = list.Frames or { };

    for _, frame in ipairs(list.Frames) do
        if frame:IsShown() and frame.ReservesFrame then
            frame.Roll = self:IsRolling(frame.Item) and not self.RequestedRoll.Custom and self.RequestedRoll or nil;

            for _, button in ipairs(frame.ReservesFrame.Players) do
                if button:IsShown() then
                    button.Name.WonRolls:SetShown(self.CurrentSession and self.CurrentSession.Members[button.Player] and self.CurrentSession.Members[button.Player].WonRolls);
                    button.Name.RecentChat:SetShown(frame.Roll and self:HasRelevantRecentChat(frame.Roll.Chat, button.Player));
                end
            end
        end
    end
end

function LootReserve.Server:UpdateReserveList(lockdown)
    if not self.Window:IsShown() then return; end

    lockdown = lockdown or InCombatLockdown() or not self.Settings.UseUnitFrames;

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
            if member.ReservesLeft == 0 then
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
        frame.Historical = false;
        frame.Roll = self:IsRolling(frame.Item) and not self.RequestedRoll.Custom and self.RequestedRoll or nil;

        frame.ItemFrame.Icon:SetTexture(texture);
        frame.ItemFrame.Name:SetText((link or name or "|cFFFF4000Loading...|r"):gsub("[%[%]]", ""));
        local tracking = self.CurrentSession.LootTracking[item];
        local fade = false;
        if LootReserve:IsLootingItem(item) then
            frame.ItemFrame.Misc:SetText("In loot");
            fade = false;
            if LibCustomGlow then
                LibCustomGlow.ButtonGlow_Start(frame.ItemFrame.IconGlow);
            end
        elseif tracking then
            local players = "";
            for player, count in pairs(tracking.Players) do
                players = players .. (#players > 0 and ", " or "") .. LootReserve:ColoredPlayer(player) .. (count > 1 and format(" (%d)", count) or "");
            end
            frame.ItemFrame.Misc:SetText("Looted by " .. players);
            fade = false;
            if LibCustomGlow then
                LibCustomGlow.ButtonGlow_Stop(frame.ItemFrame.IconGlow);
            end
        else
            frame.ItemFrame.Misc:SetText("Not looted");
            fade = self.Settings.ReservesSorting == LootReserve.Constants.ReservesSorting.ByLooter and next(self.CurrentSession.LootTracking) ~= nil;
            if LibCustomGlow then
                LibCustomGlow.ButtonGlow_Stop(frame.ItemFrame.IconGlow);
            end
        end
        frame:SetAlpha(fade and 0.25 or 1);

        frame.DurationFrame:SetShown(self:IsRolling(frame.Item) and self.RequestedRoll.MaxDuration and not self.RequestedRoll.Custom);
        local durationHeight = frame.DurationFrame:IsShown() and 12 or 0;
        frame.DurationFrame:SetHeight(math.max(durationHeight, 0.00001));

        local reservesHeight = 5 + 12 + 2;
        local last = 0;
        local playerNames = { };
        frame.ReservesFrame.Players = frame.ReservesFrame.Players or { };
        for i, player in ipairs(reserve.Players) do
            if i > #frame.ReservesFrame.Players then
                local button = CreateFrame("Button", nil, frame.ReservesFrame, lockdown and "LootReserveReserveListPlayerTemplate" or "LootReserveReserveListPlayerSecureTemplate");
                table.insert(frame.ReservesFrame.Players, button);
            end
            local unit = LootReserve:GetRaidUnitID(player) or LootReserve:GetPartyUnitID(player);
            local button = frame.ReservesFrame.Players[i];
            if button.init then button:init(); end
            button:Show();
            button.Player = player;

            playerNames[player] = playerNames[player] and playerNames[player] + 1 or 1;
            button.RollNumber = playerNames[player];

            button.Unit = unit;
            if not lockdown then
                button:SetAttribute("unit", unit);
            end
            button.Name:SetText(format("%s%s", LootReserve:ColoredPlayer(player), LootReserve:IsPlayerOnline(player) == nil and "|cFF808080 (not in raid)|r" or LootReserve:IsPlayerOnline(player) == false and "|cFF808080 (offline)|r" or ""));
            button.Roll:SetText("");
            button.AlreadyWonHighlight:Hide();
            button.WinnerHighlight:Hide();
            button:SetPoint("TOPLEFT", frame.ReservesFrame, "TOPLEFT", 0, 5 - reservesHeight);
            button:SetPoint("TOPRIGHT", frame.ReservesFrame, "TOPRIGHT", 0, 5 - reservesHeight);
            reservesHeight = reservesHeight + button:GetHeight();
            last = i;
        end
        for i = last + 1, #frame.ReservesFrame.Players do
            local button = frame.ReservesFrame.Players[i];
            button:Hide();
            if not lockdown then
                button:SetAttribute("unit", nil);
            end
        end

        frame:SetHeight(44 + durationHeight + reservesHeight);
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
        local customIndex = 0;
        for item, conditions in pairs(self.CurrentSession.ItemConditions) do
            if conditions.Custom then
                customIndex = customIndex + 1;
                if item == reserve.Item then
                    return customIndex;
                end
            end
        end
        for id, category in LootReserve:Ordered(LootReserve.Data.Categories, LootReserve.Data.CategorySorter) do
            if category.Children and (not self.CurrentSession or id == self.CurrentSession.Settings.LootCategory) and LootReserve.Data:IsCategoryVisible(category) then
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
        if LootReserve:IsLootingItem(reserve.Item) then
            return "";
        end
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
        local frame = list.Frames[i];
        frame:Hide();
        if not lockdown then
            for _, button in ipairs(frame.ReservesFrame.Players) do
                button:SetAttribute("unit", nil);
            end
        end
    end

    list:GetParent():UpdateScrollChildRect();

    self:UpdateReserveListRolls(lockdown);

    if missingName then
        C_Timer.After(0.25, function() self:UpdateReserveList(); end);
    end
end

function LootReserve.Server:UpdateRollListRolls(lockdown)
    if not self.Window:IsShown() then return; end

    lockdown = lockdown or InCombatLockdown() or not self.Settings.UseUnitFrames;

    local list = (lockdown and self.Window.PanelRollsLockdown or self.Window.PanelRolls).Scroll.Container;
    list.Frames = list.Frames or { };

    for i, frame in ipairs(list.Frames) do
        if frame:IsShown() and frame.ReservesFrame then
            frame.ReservesFrame.HeaderRoll:SetShown(frame.Roll);
            frame.ReservesFrame.ReportRolls:SetShown(frame.Roll);
            frame.RequestRollButton.CancelIcon:SetShown(frame.Roll and not frame.Historical and self:IsRolling(frame.Item));

            local highest = LootReserve.Constants.RollType.NotRolled;
            if frame.Roll then
                for player, rolls in pairs(frame.Roll.Players) do
                    for _, roll in ipairs(rolls) do
                        if highest < roll and (frame.Historical or LootReserve:IsPlayerOnline(player)) then
                            highest = roll;
                        end
                    end
                end
            end

            for _, button in ipairs(frame.ReservesFrame.Players) do
                if button:IsShown() then
                    if frame.Roll and frame.Roll.Players[button.Player] and frame.Roll.Players[button.Player][button.RollNumber] then
                        local roll = frame.Roll.Players[button.Player][button.RollNumber];
                        local rolled = roll > LootReserve.Constants.RollType.NotRolled;
                        local passed = roll == LootReserve.Constants.RollType.Passed;
                        local deleted = roll == LootReserve.Constants.RollType.Deleted;
                        local winner;
                        if frame.Roll.Winners then
                            winner = LootReserve:Contains(frame.Roll.Winners, button.Player);
                        else
                            winner = rolled and highest > LootReserve.Constants.RollType.NotRolled and roll == highest; -- Backwards compatibility
                        end

                        local color = winner and GREEN_FONT_COLOR or passed and GRAY_FONT_COLOR or deleted and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR;
                        button.Roll:Show();
                        button.Roll:SetText(rolled and tostring(roll) or passed and "PASS" or deleted and "DEL" or "...");
                        button.Roll:SetTextColor(color.r, color.g, color.b);
                        if LootReserve.Server.Settings.HighlightSameItemWinners and not frame.Historical then
                            button.AlreadyWonHighlight:SetShown(LootReserve.Server:HasAlreadyWon(button.Player, frame.Item));
                            button.WinnerHighlight:Hide();
                        else
                            button.AlreadyWonHighlight:Hide();
                            button.WinnerHighlight:SetShown(winner);
                        end
                    else
                        button.Roll:Hide();
                        button.AlreadyWonHighlight:Hide();
                        button.WinnerHighlight:Hide();
                    end
                end
            end
        end
    end

    self:UpdateRollListButtons(lockdown);
end

function LootReserve.Server:UpdateRollListButtons(lockdown)
    if not self.Window:IsShown() then return; end

    lockdown = lockdown or InCombatLockdown() or not self.Settings.UseUnitFrames;

    local list = (lockdown and self.Window.PanelRollsLockdown or self.Window.PanelRolls).Scroll.Container;
    list.Frames = list.Frames or { };

    for _, frame in ipairs(list.Frames) do
        if frame:IsShown() and frame.ReservesFrame then
            for _, button in ipairs(frame.ReservesFrame.Players) do
                if button:IsShown() then
                    button.Name.WonRolls:SetShown(self.CurrentSession and self.CurrentSession.Members[button.Player] and self.CurrentSession.Members[button.Player].WonRolls);
                    button.Name.RecentChat:SetShown(frame.Roll and self:HasRelevantRecentChat(frame.Roll.Chat, button.Player));
                end
            end
        end
    end
end

function LootReserve.Server:UpdateRollList(lockdown)
    if not self.Window:IsShown() then return; end

    lockdown = lockdown or InCombatLockdown() or not self.Settings.UseUnitFrames;

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
    if not list.HistoryHeader then
        list.HistoryHeader = CreateFrame("Frame", nil, list, "LootReserveRollHistoryHeader");
    end
    list.HistoryHeader:Hide();
    local historicalDisplayed = 0;
    local firstHistoricalHidden = true;
    if not list.HistoryShowMore then
        list.HistoryShowMore = CreateFrame("Frame", nil, list, "LootReserveRollHistoryShowMore");
    end
    list.HistoryShowMore:Hide();

    local function createFrame(item, roll, historical)
        if historical then
            historicalDisplayed = historicalDisplayed + 1;
            if historicalDisplayed > self.RollHistoryDisplayLimit then
                if firstHistoricalHidden then
                    firstHistoricalHidden = false;
                    list.HistoryShowMore.Button:SetText(format("Show %d more", self.Settings.RollHistoryDisplayLimit));
                    list.HistoryShowMore:Show();
                    list.HistoryShowMore:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -list.ContentHeight);
                    list.HistoryShowMore:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -list.ContentHeight);
                    list.ContentHeight = list.ContentHeight + list.HistoryShowMore:GetHeight();
                end
                return;
            end
        end

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

            frame.DurationFrame:SetShown(not historical and self:IsRolling(frame.Item) and self.RequestedRoll.MaxDuration);
            local durationHeight = frame.DurationFrame:IsShown() and 12 or 0;
            frame.DurationFrame:SetHeight(math.max(durationHeight, 0.00001));

            local reservesHeight = 5 + 12 + 2;
            local last = 0;
            frame.ReservesFrame.Players = frame.ReservesFrame.Players or { };

            for player, roll, rollNumber in LootReserve.Server:GetOrderedPlayerRolls(roll.Players) do
                last = last + 1;
                if last > #frame.ReservesFrame.Players then
                    local button = CreateFrame("Button", nil, frame.ReservesFrame, lockdown and "LootReserveReserveListPlayerTemplate" or "LootReserveReserveListPlayerSecureTemplate");
                    table.insert(frame.ReservesFrame.Players, button);
                end
                local unit = LootReserve:GetRaidUnitID(player) or LootReserve:GetPartyUnitID(player);
                local button = frame.ReservesFrame.Players[last];
                if button.init then button:init(); end
                button:Show();
                button.Player = player;
                button.RollNumber = rollNumber;
                button.Unit = unit;
                if not lockdown then
                    button:SetAttribute("unit", unit);
                end
                button.Name:SetText(format("%s%s", LootReserve:ColoredPlayer(player), historical and "" or LootReserve:IsPlayerOnline(player) == nil and "|cFF808080 (not in raid)|r" or LootReserve:IsPlayerOnline(player) == false and "|cFF808080 (offline)|r" or ""));
                button.Roll:SetText("");
                button.AlreadyWonHighlight:Hide();
                button.WinnerHighlight:Hide();
                button:SetPoint("TOPLEFT", frame.ReservesFrame, "TOPLEFT", 0, 5 - reservesHeight);
                button:SetPoint("TOPRIGHT", frame.ReservesFrame, "TOPRIGHT", 0, 5 - reservesHeight);
                reservesHeight = reservesHeight + button:GetHeight();
            end
            for i = last + 1, #frame.ReservesFrame.Players do
                local button = frame.ReservesFrame.Players[i];
                button:Hide();
                if not lockdown then
                    button:SetAttribute("unit", nil);
                end
            end

            frame.ReservesFrame.HeaderPlayer:SetText(roll.RaidRoll and "Raid-rolled to" or roll.Custom and format("Rolled%s by", roll.Phases and format(" for |cFF00FF00%s|r", roll.Phases[1] or "") or "") or "Reserved by");
            frame.ReservesFrame.NoRollsPlaceholder:SetShown(last == 0);
            if frame.ReservesFrame.NoRollsPlaceholder:IsShown() then
                reservesHeight = reservesHeight + 16;
            end

            frame:SetHeight(44 + durationHeight + reservesHeight);
        else
            frame:SetShown(not self.RequestedRoll);
            frame:SetHeight(frame:IsShown() and 44 or 0.00001);
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
    if IsInRaid() or IsInGroup() or LootReserve.Comm.SoloDebug then
        if self.RequestedRoll then
            --if not filter or matchesFilter(self.RequestedRoll.Item, self.RequestedRoll, filter) then
                createFrame(self.RequestedRoll.Item, self.RequestedRoll, false);
            --end
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
        local frame = list.Frames[i];
        frame:Hide();
        if not lockdown then
            for _, button in ipairs(frame.ReservesFrame.Players) do
                button:SetAttribute("unit", nil);
            end
        end
    end

    list:GetParent():UpdateScrollChildRect();

    self:UpdateRollListRolls(lockdown);
end

function LootReserve.Server:OnWindowTabClick(tab)
    PanelTemplates_Tab_OnClick(tab, self.Window);
    PanelTemplates_SetTab(self.Window, tab:GetID());
    self:SetWindowTab(tab:GetID());
    CloseMenus();
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB);
end

function LootReserve.Server:SetWindowTab(tab, lockdown)
    lockdown = lockdown or InCombatLockdown() or not self.Settings.UseUnitFrames;

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
            (lockdown and self.Window.PanelReservesLockdown or self.Window.PanelReserves):SetPoint("TOPLEFT", self.Window, "TOPLEFT", 7, -61);
        else
            self.Window.Search:SetPoint("TOPLEFT", self.Window, "TOPLEFT", 10, -25);
            self.Window.Search:SetPoint("TOPRIGHT", self.Window, "TOPRIGHT", -7 - 80, -25);
            (lockdown and self.Window.PanelReservesLockdown or self.Window.PanelReserves):SetPoint("TOPLEFT", self.Window, "TOPLEFT", 7, -48);
        end
    elseif tab == 3 then
        self.Window.InsetBg:SetPoint("TOPLEFT", self.Window.Search, "BOTTOMLEFT", -6, 0);
        self.Window.Duration:Hide();
        self.Window.Search:Show();
        self.Window.ButtonMenu:Hide();
        self.Window.Search:SetPoint("TOPLEFT", self.Window, "TOPLEFT", 10, -25);
        self.Window.Search:SetPoint("TOPRIGHT", self.Window, "TOPRIGHT", -7, -25);
        (lockdown and self.Window.PanelRollsLockdown or self.Window.PanelRolls):SetPoint("TOPLEFT", self.Window, "TOPLEFT", 7, -48);
        self.RollHistoryDisplayLimit = self.Settings.RollHistoryDisplayLimit;
    end

    for i, panel in ipairs(self.Window.Panels) do
        if panel.Lockdown then
            if lockdown then
                if panel:IsShown() then
                    panel:Hide();
                end
                panel = panel.Lockdown;
            else
                panel.Lockdown:Hide();
            end
        end
        panel:SetShown(i == tab);
    end
    self:UpdateServerAuthority();
end

function LootReserve.Server:RefreshWindowTab(lockdown)
    for i, panel in ipairs(self.Window.Panels) do
        if panel:IsShown() or panel.Lockdown and panel.Lockdown:IsShown() then
            self:SetWindowTab(i, lockdown or InCombatLockdown() or not self.Settings.UseUnitFrames);
            return;
        end
    end
end

function LootReserve.Server:OnWindowLoad(window)
    self.Window = window;
    self.Window.TopLeftCorner:SetSize(32, 32); -- Blizzard UI bug?
    self.Window.TitleText:SetPoint("TOP", self.Window, "TOP", 0, -4);
    self.Window.TitleText:SetText("Loot Reserve Server");
    self.Window:SetMinResize(230, 365);
    self.Window.PanelSession.LabelDuration:SetPoint("RIGHT", self.Window.PanelSession.DropDownDuration.Text, "LEFT", -16, 0);
    self.Window.PanelSession.DropDownDuration:SetPoint("CENTER", self.Window.PanelSession.Duration, "CENTER", (6 + self.Window.PanelSession.LabelDuration:GetStringWidth()) / 2, 0);
    PanelTemplates_SetNumTabs(self.Window, 3);
    PanelTemplates_SetTab(self.Window, 1);
    self:SetWindowTab(1);
    self:UpdateServerAuthority();
    self:LoadNewSessionSettings();

    LootReserve:RegisterEvent("GROUP_JOINED", "GROUP_LEFT", "PARTY_LEADER_CHANGED", "PARTY_LOOT_METHOD_CHANGED", "GROUP_ROSTER_UPDATE", function()
        self:UpdateServerAuthority();
    end);
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
    function self.OnEnterCombat()
        -- Swap out the real (tainted) reserves and rolls panels for slightly less functional ones, but ones that don't have taint
        self:RefreshWindowTab(true);
        -- Sync changes between real and lockdown panels
        self:UpdateReserveList(true);
        self.Window.PanelReservesLockdown.Scroll:UpdateScrollChildRect();
        self.Window.PanelReservesLockdown.Scroll:SetVerticalScroll(self.Window.PanelReserves.Scroll:GetVerticalScroll());
        self:UpdateRollList(true);
        self.Window.PanelRollsLockdown.Scroll:UpdateScrollChildRect();
        self.Window.PanelRollsLockdown.Scroll:SetVerticalScroll(self.Window.PanelRolls.Scroll:GetVerticalScroll());
        local list = self.Window.PanelRolls.Scroll.Container;
        local listLockdown = self.Window.PanelRollsLockdown.Scroll.Container;
        if list and list.Frames and list.Frames[1] and listLockdown and listLockdown.Frames and listLockdown.Frames[1] then
            listLockdown.Frames[1]:SetItem(list.Frames[1].Item);
        end
    end
    function self.OnExitCombat()
        -- Restore original panels
        self:RefreshWindowTab();
        -- Sync changes between real and lockdown panels
        self:UpdateReserveList();
        self.Window.PanelReserves.Scroll:UpdateScrollChildRect();
        self.Window.PanelReserves.Scroll:SetVerticalScroll(self.Window.PanelReservesLockdown.Scroll:GetVerticalScroll());
        self:UpdateRollList();
        self.Window.PanelRolls.Scroll:UpdateScrollChildRect();
        self.Window.PanelRolls.Scroll:SetVerticalScroll(self.Window.PanelRollsLockdown.Scroll:GetVerticalScroll());
        local list = self.Window.PanelRolls.Scroll.Container;
        local listLockdown = self.Window.PanelRollsLockdown.Scroll.Container;
        if list and list.Frames and list.Frames[1] and listLockdown and listLockdown.Frames and listLockdown.Frames[1] then
            list.Frames[1]:SetItem(listLockdown.Frames[1].Item);
        end
    end
    LootReserve:RegisterEvent("PLAYER_REGEN_DISABLED", self.OnEnterCombat);
    LootReserve:RegisterEvent("PLAYER_REGEN_ENABLED", self.OnExitCombat);
    LootReserve:RegisterEvent("LOOT_READY", "LOOT_CLOSED", "LOOT_SLOT_CHANGED", "LOOT_SLOT_CLEARED", function()
        self:UpdateReserveList();
    end);
end

local activeSessionChanges =
{
    ButtonStartSession  = "Hide",
    ButtonStopSession   = "Show",
    ButtonResetSession  = "Hide",
    LabelRaid           = "Label",
    DropDownRaid        = "DropDown",
    LabelCount          = "Label",
    EditBoxCount        = "Disable",
    LabelMultireserve   = "Label",
    EditBoxMultireserve = "Disable",
    LabelDuration       = "Hide",
    DropDownDuration    = "Hide",
    ButtonLootEdit      = "Disable",

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
    self:LoadNewSessionSettings();
    self.Window.PanelSession.CheckButtonBlind:SetChecked(self.CurrentSession.Settings.Blind);
    self.Window.PanelSession.CheckButtonLock:SetChecked(self.CurrentSession.Settings.Lock);
    self.Window.PanelSession.Duration:SetShown(self.CurrentSession.Settings.Duration ~= 0);
    self.Window.PanelSession.ButtonStartSession:Hide();
    self.Window.PanelSession.ButtonStopSession:Show();
    self.Window.PanelSession.ButtonResetSession:Hide();
    self:OnWindowTabClick(self.StartupAwaitingAuthority and self.Window.TabSession or self.Window.TabReserves);
    PlaySound(SOUNDKIT.GS_CHARACTER_SELECTION_ENTER_WORLD);
    self:UpdateServerAuthority();
    self:UpdateRollList();
    self.LootEdit.Window:Hide();
    self.Import.Window:Hide();
end

function LootReserve.Server:SessionStopped()
    activeSessionChanges:Apply(self.Window.PanelSession, true);
    self:LoadNewSessionSettings();
    self.Window.PanelSession.CheckButtonBlind:SetChecked(self.CurrentSession.Settings.Blind);
    self.Window.PanelSession.CheckButtonLock:SetChecked(self.CurrentSession.Settings.Lock);
    self.Window.PanelSession.Duration:SetShown(self.CurrentSession.Settings.Duration ~= 0);
    self.Window.PanelSession.ButtonStartSession:Show();
    self.Window.PanelSession.ButtonStopSession:Hide();
    self.Window.PanelSession.ButtonResetSession:Show();
    self:RefreshWindowTab();
    self:UpdateServerAuthority();
    self:UpdateRollList();
end

function LootReserve.Server:SessionReset()
    activeSessionChanges:Apply(self.Window.PanelSession, false);
    self:LoadNewSessionSettings();
    self.Window.PanelSession.CheckButtonBlind:SetChecked(self.NewSessionSettings.Blind);
    self.Window.PanelSession.CheckButtonLock:SetChecked(self.NewSessionSettings.Lock);
    self.Window.PanelSession.Duration:Hide();
    self.Window.PanelSession.ButtonStartSession:Show();
    self.Window.PanelSession.ButtonStopSession:Hide();
    self.Window.PanelSession.ButtonResetSession:Hide();
    self:UpdateServerAuthority();
    self:UpdateRollList();
end

function LootReserve.Server:RollEnded()
    if UIDROPDOWNMENU_OPEN_MENU then
        for _, panel in ipairs({ "PanelReserves", "PanelReservesLockdown", "PanelRolls", "PanelRollsLockdown" }) do
            local list = self.Window[panel].Scroll.Container;
            if list and list.Frames then
                for _, frame in ipairs(list.Frames) do
                    if UIDROPDOWNMENU_OPEN_MENU == frame.Menu then
                        CloseMenus();
                        return;
                    end
                end
            end
        end
    end
end

function LootReserve.Server:UpdateServerAuthority()
    local hasAuthority = self:CanBeServer();
    self.Window.PanelSession.ButtonStartSession:SetEnabled(hasAuthority);
    self.Window.PanelSession:SetAlpha((hasAuthority or self.CurrentSession and not self.StartupAwaitingAuthority) and 1 or 0.15);
    self.Window.NoAuthority:SetShown(not hasAuthority and not self.CurrentSession and self.Window.PanelSession:IsShown());
    self.Window.AwaitingAuthority:SetShown(not hasAuthority and self.CurrentSession and self.Window.PanelSession:IsShown() and self.StartupAwaitingAuthority);
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

function LootReserve.Server:LoadNewSessionSettings()
    if not self.Window:IsShown() then return; end

    local function setDropDownValue(dropDown, value)
        if dropDown.init then dropDown:init(); end
        ToggleDropDownMenu(nil, nil, dropDown);
        UIDropDownMenu_SetSelectedValue(dropDown, value);
        CloseMenus();
    end

    setDropDownValue(self.Window.PanelSession.DropDownRaid, self.NewSessionSettings.LootCategory);
    self.Window.PanelSession.EditBoxCount:SetText(tostring(self.NewSessionSettings.MaxReservesPerPlayer));
    self.Window.PanelSession.EditBoxMultireserve:SetEnabled(not self.CurrentSession and self.NewSessionSettings.MaxReservesPerPlayer > 1);
    self.Window.PanelSession.EditBoxMultireserve:SetText(self.NewSessionSettings.Multireserve and tostring(self.NewSessionSettings.Multireserve) or "Off");
    self.Window.PanelSession.EditBoxMultireserve:SetMinMaxValues(1, self.NewSessionSettings.MaxReservesPerPlayer);
    setDropDownValue(self.Window.PanelSession.DropDownDuration, self.NewSessionSettings.Duration);
    if self.CurrentSession then
        self.Window.PanelSession.CheckButtonBlind:SetChecked(self.CurrentSession.Settings.Blind);
        self.Window.PanelSession.CheckButtonLock:SetChecked(self.CurrentSession.Settings.Lock);
    else
        self.Window.PanelSession.CheckButtonBlind:SetChecked(self.NewSessionSettings.Blind);
        self.Window.PanelSession.CheckButtonLock:SetChecked(self.NewSessionSettings.Lock);
    end
end
