function LootReserve.Server.MembersEdit:UpdateMembersList()
    if not self.Window:IsShown() then return; end

    local list = self.Window.Scroll.Container;
    list.Frames = list.Frames or { };
    list.LastIndex = 0;

    -- Clear everything
    for _, frame in ipairs(list.Frames) do
        frame:Hide();
    end

    local session = LootReserve.Server.CurrentSession;
    self.Window.NoSession:SetShown(not session);
    if not session then
        return;
    end
    
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

        local count = session.Settings.MaxReservesPerPlayer - member.ReservesLeft;

        frame.Alt:SetShown(list.LastIndex % 2 == 0);
        frame.Name:SetText(format("%s%s", LootReserve:ColoredPlayer(player), LootReserve:IsPlayerOnline(player) == nil and "|cFF808080 (not in raid)|r" or LootReserve:IsPlayerOnline(player) == false and "|cFF808080 (offline)|r" or ""));
        frame.ButtonWhisper:SetPoint("LEFT", frame.Name, "LEFT", frame.Name:GetStringWidth(), 0);
        frame.CheckButtonLocked:SetChecked(member.Locked);
        frame.CheckButtonLocked:SetEnabled(session.Settings.Lock);
        frame.CheckButtonLocked:SetAlpha(session.Settings.Lock and 1 or 0.25);
        frame.Count:SetText(format("|c%s%d", count >= session.Settings.MaxReservesPerPlayer and "FF00FF00" or count > 0 and "FFFFD200" or "FFFF0000", count));

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
        end
        for i = last + 1, #frame.ReservesFrame.Items do
            frame.ReservesFrame.Items[i]:Hide();
        end
    end

    for player, member in LootReserve:Ordered(session.Members, function(aMember, bMember, aPlayer, bPlayer) return aPlayer < bPlayer; end) do
        createFrame(player, member);
    end

    for i = list.LastIndex + 1, #list.Frames do
        list.Frames[i]:Hide();
    end

    list:GetParent():UpdateScrollChildRect();
end

function LootReserve.Server.MembersEdit:OnWindowLoad(window)
    self.Window = window;
    self.Window.TopLeftCorner:SetSize(32, 32); -- Blizzard UI bug?
    self.Window.TitleText:SetText("Loot Reserve Server - Players");
    self.Window:SetMinResize(360, 150);
    self:UpdateMembersList();
    LootReserve:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(item, success)
        if success and LootReserve.Server.CurrentSession then
            for player, member in pairs(LootReserve.Server.CurrentSession.Members) do
                if LootReserve:Contains(member.ReservedItems, item) then
                    self:UpdateMembersList();
                    return;
                end
            end
        end
    end);
end
