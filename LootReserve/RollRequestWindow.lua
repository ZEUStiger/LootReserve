local LibCustomGlow = LibStub("LibCustomGlow-1.0");

function LootReserve.Client:RollRequested(sender, item, players)
    local frame = LootReserveRollRequestWindow;

    if LibCustomGlow then
        LibCustomGlow.ButtonGlow_Stop(frame.ItemFrame.IconGlow);
    end
    frame:Hide();

    if not LootReserve:Contains(players, Ambiguate(UnitName("player"), "short")) then
        return;
    end

    local name, link, _, _, _, type, subtype, _, _, texture = GetItemInfo(item);
    if subtype and type ~= subtype then
        type = type .. ", " .. subtype;
    end
    frame.Link = link;

    frame.Sender = sender;
    frame.Item = item;
    frame.LabelSender:SetText(format("%s asks you to roll on the item you reserved:", LootReserve:ColoredPlayer(sender)));
    frame.ItemFrame.Icon:SetTexture(texture);
    frame.ItemFrame.Name:SetText((link or name or "|cFFFF4000Loading...|r"):gsub("[%[%]]", ""));
    frame.ItemFrame.Misc:SetText(type);
    frame.ButtonRoll:Disable();
    frame.ButtonRoll:SetAlpha(0.25);
    frame.ButtonPass:Disable();
    frame.ButtonPass:SetAlpha(0.25);
    frame:Show();

    C_Timer.After(1, function()
        if frame.Item == item then
            frame.ButtonRoll:Enable();
            frame.ButtonRoll:SetAlpha(1);
            frame.ButtonPass:Enable();
            frame.ButtonPass:SetAlpha(1);
            if LibCustomGlow then
                LibCustomGlow.ButtonGlow_Start(frame.ItemFrame.IconGlow);
            end
        end
    end);

    if not name or not link then
        C_Timer.After(0.25, function()
            self:RollRequested(sender, item, players);
        end);
    end
end

function LootReserve.Client:RespondToRollRequest(response)
    if LibCustomGlow then
        LibCustomGlow.ButtonGlow_Stop(LootReserveRollRequestWindow.ItemFrame.IconGlow);
    end
    if response then
        RandomRoll(1, 100);
    else
        LootReserve.Comm:SendPassRoll(LootReserveRollRequestWindow.Item);
    end
    LootReserveRollRequestWindow:Hide();
end