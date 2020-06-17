function LootReserve.Server:UpdateReserveListUnits(lockdown)
    lockdown = lockdown or InCombatLockdown();

    local list = (lockdown and self.Window.PanelReservesLockdown or self.Window.PanelReserves).Scroll.Container;
    list.Frames = list.Frames or { };

    for _, frame in ipairs(list.Frames) do
        if frame:IsShown() then
            for _, button in ipairs(frame.ReservesFrame.Players) do
                if button:IsShown() then
                    local unit = LootReserve:GetRaidUnitID(button.Player);
                    button.Unit = unit;
                    if not lockdown then
                        button:SetAttribute("unit", unit);
                    end
                end
            end
        end
    end
end

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
                    if highest < roll then
                        highest = roll;
                    end
                end
            end

            for _, button in ipairs(frame.ReservesFrame.Players) do
                if button:IsShown() then
                    if rollingThisItem and self.RequestedRoll.Players[button.Player] then
                        local roll = self.RequestedRoll.Players[button.Player];
                        local winner = roll > 0 and highest > 0 and roll == highest;
                        local pass = roll < 0;
                        local color = winner and GREEN_FONT_COLOR or pass and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR;
                        button.Roll:Show();
                        button.Roll:SetText(roll > 0 and tostring(roll) or pass and "PASS" or "...");
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

    local filter = self.Window.Search:GetText():gsub("^%s*(.-)%s*$", "%1"):upper();
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

    if not self.CurrentSession then
        return;
    end
    
    local function createFrame(i, item, reserve)
        list.LastIndex = list.LastIndex + 1;
        local frame = list.Frames[list.LastIndex];
        while not frame do
            frame = CreateFrame("Frame", nil, list, "LootReserveReserveListTemplate");

            if #list.Frames == 0 then
                frame:SetPoint("TOPLEFT", list, "TOPLEFT");
                frame:SetPoint("TOPRIGHT", list, "TOPRIGHT");
            else
                frame:SetPoint("TOPLEFT", list.Frames[#list.Frames], "BOTTOMLEFT", 0, 0);
                frame:SetPoint("TOPRIGHT", list.Frames[#list.Frames], "BOTTOMRIGHT", 0, 0);
            end
            table.insert(list.Frames, frame);
            frame = list.Frames[list.LastIndex];
        end

        frame:Show();

        frame.Item = item;

        local name, link, _, _, _, type, subtype, _, _, texture = GetItemInfo(item);
        if subtype and type ~= subtype then
            type = type .. ", " .. subtype;
        end
        frame.Link = link;

        frame.ItemFrame.Icon:SetTexture(texture);
        frame.ItemFrame.Name:SetText((link or name or "|cFFFF4000Loading...|r"):gsub("[%[%]]", ""));
        local tracking = self.CurrentSession.LootTracking[item];
        if tracking then
            local players = "";
            for player, count in pairs(tracking.Players) do
                players = players .. (#players > 0 and ", " or "") .. format("|c%s%s|r", LootReserve:GetPlayerClassColor(player), player) .. (count > 1 and format(" (%d)", count) or "");
            end
            frame.ItemFrame.Misc:SetText("Looted by " .. players);
        else
            frame.ItemFrame.Misc:SetText("Not looted");
        end

        local reservesHeight = 5 + 12 + 2;
        local last = 0;
        frame.ReservesFrame.Players = frame.ReservesFrame.Players or { };
        for i, player in ipairs(reserve.Players) do
            if i > #frame.ReservesFrame.Players then
                local button = CreateFrame("Button", nil, frame.ReservesFrame, lockdown and "LootReserveReserveListPlayerTemplate" or "LootReserveReserveListPlayerSecureTemplate");
                if #frame.ReservesFrame.Players == 0 then
                    button:SetPoint("TOPLEFT", frame.ReservesFrame, "TOPLEFT", 0, -14);
                    button:SetPoint("TOPRIGHT", frame.ReservesFrame, "TOPRIGHT", 0, 0);
                else
                    button:SetPoint("TOPLEFT", frame.ReservesFrame.Players[i - 1], "BOTTOMLEFT");
                    button:SetPoint("TOPRIGHT", frame.ReservesFrame.Players[i - 1], "BOTTOMRIGHT");
                end
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
            button.Name:SetText(format("|c%s%s|r", LootReserve:GetPlayerClassColor(player), player));
            button.Roll:SetText("");
            button.WinnerHighlight:Hide();
            reservesHeight = reservesHeight + button:GetHeight();
            last = i;
        end
        for i = last + 1, #frame.ReservesFrame.Players do
            frame.ReservesFrame.Players[i]:Hide();
        end

        frame:SetHeight(44 + reservesHeight);
        list.ContentHeight = list.ContentHeight + frame:GetHeight();
    end

    local function matchesFilter(item, reserve, filter)
        filter = (filter or ""):gsub("^%s*(.-)%s*$", "%1"):upper();
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
    
    for item, reserve in LootReserve:Ordered(self.CurrentSession.ItemReserves, function(a, b) return a.StartTime < b.StartTime; end) do
        if not filter or matchesFilter(item, reserve, filter) then
            createFrame(last, item, reserve);
        end
    end
    for i = list.LastIndex + 1, #list.Frames do
        list.Frames[i]:Hide();
    end

    list:SetSize(list:GetParent():GetWidth(), math.max(list.ContentHeight or 0, list:GetParent():GetHeight() - 1));

    self:UpdateReserveListRolls(lockdown);
end

function LootReserve.Server:OnWindowTabClick(tab)
    PanelTemplates_Tab_OnClick(tab, self.Window);
    PanelTemplates_SetTab(self.Window, tab:GetID());
    self:SetWindowTab(tab:GetID());
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB);
end

function LootReserve.Server:SetWindowTab(tab)
    if tab == 1 then
        self.Window.InsetBg:SetPoint("TOPLEFT", self.Window, "TOPLEFT", 4, -24);
    elseif tab == 2 then
        self.Window.InsetBg:SetPoint("TOPLEFT", self.Window.Search, "BOTTOMLEFT", -6, 0);
    end
    self.Window.Duration:SetShown(tab == 2 and self.CurrentSession and self.CurrentSession.AcceptingReserves and self.CurrentSession.Duration ~= 0 and self.CurrentSession.Settings.Duration ~= 0);
    self.Window.Search:SetShown(tab == 2 and not self.Window.Duration:IsShown());

    for i, panel in ipairs(self.Window.Panels) do
        if panel == self.Window.PanelReserves and InCombatLockdown() then
            panel = self.Window.PanelReservesLockdown;
        end
        panel:SetShown(i == tab);
    end
end

function LootReserve.Server:OnWindowLoad(window)
    self.Window = window;
    self.Window.TopLeftCorner:SetSize(32, 32); -- Blizzard UI bug?
    self.Window.TitleText:SetText("Loot Reserve Server");
    self.Window:SetMinResize(230, 360);
    PanelTemplates_SetNumTabs(self.Window, 2);
    PanelTemplates_SetTab(self.Window, 1);
    self:SetWindowTab(1);

    local function updateAuthority() self:UpdateServerAuthority(); end
    LootReserve:RegisterEvent("GROUP_JOINED", updateAuthority);
    LootReserve:RegisterEvent("GROUP_LEFT", updateAuthority);
    LootReserve:RegisterEvent("PARTY_LEADER_CHANGED", updateAuthority);
    LootReserve:RegisterEvent("PARTY_LOOT_METHOD_CHANGED", updateAuthority);
    LootReserve:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(item, success)
        if item and self.CurrentSession and self.CurrentSession.ItemReserves[item] then
            self:UpdateReserveList();
        end
    end);
    LootReserve:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        -- Swap out the real (tained) reserves panel for a slightly less functional one, but one that doesn't have taint
        if self.Window.PanelReserves:IsShown() then
            self.Window.PanelReserves:Hide();
            self.Window.PanelReservesLockdown:Show();
        end
        -- Sync changes between real and lockdown panels
        self:UpdateReserveList(true);
        self.Window.PanelReservesLockdown.Scroll:UpdateScrollChildRect();
        self.Window.PanelReservesLockdown.Scroll:SetVerticalScroll(self.Window.PanelReserves.Scroll:GetVerticalScroll());
    end);
    LootReserve:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        -- Restore original reserves panel
        if self.Window.PanelReservesLockdown:IsShown() then
            self.Window.PanelReservesLockdown:Hide();
            self.Window.PanelReserves:Show();
        end
        -- Sync changes between real and lockdown panels
        self:UpdateReserveList();
        self.Window.PanelReserves.Scroll:UpdateScrollChildRect();
        self.Window.PanelReserves.Scroll:SetVerticalScroll(self.Window.PanelReservesLockdown.Scroll:GetVerticalScroll());
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
end

function LootReserve.Server:SessionStopped()
    activeSessionChanges:Apply(self.Window.PanelSession, true);
    self.Window.PanelSession.Duration:SetShown(self.CurrentSession.Settings.Duration ~= 0);
    self.Window.PanelSession.ButtonStartSession:Show();
    self.Window.PanelSession.ButtonStopSession:Hide();
    self.Window.PanelSession.ButtonResetSession:Show();
    if self.Window.Duration:IsShown() then
        self.Window.Duration:Hide();
        self.Window.Search:Show();
    end
    self:UpdateServerAuthority();
end

function LootReserve.Server:SessionReset()
    activeSessionChanges:Apply(self.Window.PanelSession, false);
    self.Window.PanelSession.Duration:Hide();
    self.Window.PanelSession.ButtonStartSession:Show();
    self.Window.PanelSession.ButtonStopSession:Hide();
    self.Window.PanelSession.ButtonResetSession:Hide();
    self:UpdateServerAuthority();
end

function LootReserve.Server:UpdateServerAuthority()
    local hasAuthority = self:CanBeServer();
    self.Window.PanelSession.ButtonStartSession:SetEnabled(hasAuthority);
    self.Window.PanelSession.NoAuthority:SetShown(not hasAuthority and not self.CurrentSession);
    --self.Window.PanelSession.ButtonStopSession:SetEnabled(hasAuthority);
    --self.Window.PanelSession.ButtonResetSession:SetEnabled(hasAuthority);
end
