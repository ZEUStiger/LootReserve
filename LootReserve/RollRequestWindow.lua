local LibCustomGlow = LibStub("LibCustomGlow-1.0");

function LootReserve.Client:RollRequested(sender, item, players, custom, duration, maxDuration, phase)
    local frame = LootReserveRollRequestWindow;

    if LibCustomGlow then
        LibCustomGlow.ButtonGlow_Stop(frame.ItemFrame.IconGlow);
    end
    frame:Hide();

    if not LootReserve:Contains(players, Ambiguate(UnitName("player"), "short")) then
        self.RollRequest = nil;
        return;
    end

    self.RollRequest =
    {
        Sender = sender,
        Item = item,
        Custom = custom or nil,
        Duration = duration and duration > 0 and duration or nil,
        MaxDuration = maxDuration and maxDuration > 0 and maxDuration or nil,
        Phase = phase,
    };

    local name, link, _, _, _, type, subtype, _, _, texture = GetItemInfo(item);
    if subtype and type ~= subtype then
        type = type .. ", " .. subtype;
    end
    frame.Link = link;

    frame.Sender = sender;
    frame.Item = item;
    frame.LabelSender:SetText(format(custom and "%s offers you to roll%s on this item:" or "%s asks you to roll%s on the item you reserved:", LootReserve:ColoredPlayer(sender), phase and format(" for |cFF00FF00%s|r", phase) or ""));
    frame.ItemFrame.Icon:SetTexture(texture);
    frame.ItemFrame.Name:SetText((link or name or "|cFFFF4000Loading...|r"):gsub("[%[%]]", ""));
    frame.ItemFrame.Misc:SetText(type);
    frame.ButtonRoll:Disable();
    frame.ButtonRoll:SetAlpha(0.25);
    frame.ButtonPass:Disable();
    frame.ButtonPass:SetAlpha(0.25);

    frame.DurationFrame:SetShown(self.RollRequest.MaxDuration);
    local durationHeight = frame.DurationFrame:IsShown() and 20 or 0;
    frame.DurationFrame:SetHeight(math.max(durationHeight, 0.00001));

    frame:SetHeight(90 + durationHeight);
    frame:SetMinResize(300, 90 + durationHeight);
    frame:SetMaxResize(1000, 90 + durationHeight);

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
            self:RollRequested(sender, item, players, custom, duration, maxDuration, phase);
        end);
    end
end

function LootReserve.Client:RespondToRollRequest(response)
    if LibCustomGlow then
        LibCustomGlow.ButtonGlow_Stop(LootReserveRollRequestWindow.ItemFrame.IconGlow);
    end
    LootReserveRollRequestWindow:Hide();

    if not self.RollRequest then return; end

    if response then
        RandomRoll(1, 100);
    else
        LootReserve.Comm:SendPassRoll(self.RollRequest.Item);
    end
    self.RollRequest = nil;
end