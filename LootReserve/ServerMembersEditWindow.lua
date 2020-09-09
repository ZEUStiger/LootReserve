function LootReserve.Server.MembersEdit:UpdateMembersList()
    LootReserveServerButtonMembersEdit:SetGlow(not LootReserve.Server.CurrentSession and next(LootReserve.Server.NewSessionSettings.ImportedMembers));

    if not self.Window:IsShown() then return; end

    local list = self.Window.Scroll.Container;
    list.Frames = list.Frames or { };
    list.LastIndex = 0;

    -- Clear everything
    for _, frame in ipairs(list.Frames) do
        frame:Hide();
    end

    self.Window.NoSession:SetShown(not LootReserve.Server.CurrentSession and not next(LootReserve.Server.NewSessionSettings.ImportedMembers));
    self.Window.Header.LockedIcon:SetShown(LootReserve.Server.CurrentSession);
    self.Window.ImportExportButton:SetText(LootReserve.Server.CurrentSession and "Export" or "Import/Export");
    self.Window.ImportExportButton:SetWidth(LootReserve.Server.CurrentSession and 60 or 90);
    
    local function createFrame(player, member)
        list.LastIndex = list.LastIndex + 1;
        local frame = list.Frames[list.LastIndex];
        while not frame do
            frame = CreateFrame("Frame", nil, list, "LootReserveServerMembersEditMemberTemplate");

            if #list.Frames == 0 then
                frame:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -4);
                frame:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -4);
            else
                frame:SetPoint("TOPLEFT", list.Frames[#list.Frames], "BOTTOMLEFT", 0, 0);
                frame:SetPoint("TOPRIGHT", list.Frames[#list.Frames], "BOTTOMRIGHT", 0, 0);
            end
            table.insert(list.Frames, frame);
            frame = list.Frames[list.LastIndex];
        end

        frame.Player = player;
        frame.Member = member;
        frame:Show();

        local maxCount = LootReserve.Server.CurrentSession and LootReserve.Server.CurrentSession.Settings.MaxReservesPerPlayer or LootReserve.Server.NewSessionSettings.MaxReservesPerPlayer;
        local count = member.ReservesLeft and (maxCount - member.ReservesLeft) or #member.ReservedItems;

        frame.Alt:SetShown(list.LastIndex % 2 == 0);
        frame.Name:SetText(format("%s%s%s", LootReserve:ColoredPlayer(player), not LootReserve.Server.CurrentSession and "|cFF808080 (imported)|r" or "", LootReserve:IsPlayerOnline(player) == nil and "|cFF808080 (not in raid)|r" or LootReserve:IsPlayerOnline(player) == false and "|cFF808080 (offline)|r" or ""));
        frame.ButtonWhisper:SetPoint("LEFT", frame.Name, "LEFT", math.min(frame.Name:GetWidth(), frame.Name:GetStringWidth()), 0);
        if LootReserve.Server.CurrentSession then
            frame.CheckButtonLocked:Show();
            frame.CheckButtonLocked:SetChecked(member.Locked);
            frame.CheckButtonLocked:SetEnabled(LootReserve.Server.CurrentSession.Settings.Lock);
            frame.CheckButtonLocked:SetAlpha(LootReserve.Server.CurrentSession.Settings.Lock and 1 or 0.25);
        else
            frame.CheckButtonLocked:Hide();
        end
        frame.Count:SetText(format("|c%s%d", count >= maxCount and "FF00FF00" or count > 0 and "FFFFD200" or "FFFF0000", count));

        local last = 0;
        frame.ReservesFrame.Items = frame.ReservesFrame.Items or { };
        for _, item in ipairs(member.ReservedItems) do
            last = last + 1;
            local button = frame.ReservesFrame.Items[last];
            while not button do
                button = CreateFrame("Button", nil, frame.ReservesFrame, "LootReserveServerMembersEditItemTemplate");
                if last == 1 then
                    button:SetPoint("LEFT", frame.ReservesFrame, "LEFT");
                else
                    button:SetPoint("LEFT", frame.ReservesFrame.Items[last - 1], "RIGHT", 4, 0);
                end
                table.insert(frame.ReservesFrame.Items, button);
                button = frame.ReservesFrame.Items[last];
            end
            button:Show();
            button.Item = item;

            local name, link, _, _, _, _, _, _, _, texture = GetItemInfo(item);
            button.Link = link;
            button.Icon.Texture:SetTexture(texture);
            if #member.ReservedItems == 1 and item ~= 0 then
                button.Icon.Name:SetText((link or "|cFFFF0000Loading...|r"):gsub("[%[%]]", ""));
                button.Icon.Name:Show();
            else
                button.Icon.Name:Hide();
            end
        end
        for i = last + 1, #frame.ReservesFrame.Items do
            frame.ReservesFrame.Items[i]:Hide();
        end
    end

    for player, member in LootReserve:Ordered(LootReserve.Server.CurrentSession and LootReserve.Server.CurrentSession.Members or LootReserve.Server.NewSessionSettings.ImportedMembers, function(aMember, bMember, aPlayer, bPlayer) return aPlayer < bPlayer; end) do
        createFrame(player, member);
    end

    for i = list.LastIndex + 1, #list.Frames do
        list.Frames[i]:Hide();
    end

    list:GetParent():UpdateScrollChildRect();
end

function LootReserve.Server.MembersEdit:ClearImported()
    if LootReserve.Server.CurrentSession then return; end

    table.wipe(LootReserve.Server.NewSessionSettings.ImportedMembers);
    self:UpdateMembersList();
end

function LootReserve.Server.MembersEdit:OnWindowLoad(window)
    self.Window = window;
    self.Window.TopLeftCorner:SetSize(32, 32); -- Blizzard UI bug?
    self.Window.TitleText:SetText("Loot Reserve Server - Players");
    self.Window:SetMinResize(450, 150);
    self:UpdateMembersList();
    LootReserve:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(item, success)
        if success then
            for player, member in pairs(LootReserve.Server.CurrentSession and LootReserve.Server.CurrentSession.Members or LootReserve.Server.NewSessionSettings.ImportedMembers) do
                if LootReserve:Contains(member.ReservedItems, item) then
                    self:UpdateMembersList();
                    return;
                end
            end
        end
    end);
end
