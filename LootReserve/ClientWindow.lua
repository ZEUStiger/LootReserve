function LootReserve.Client:UpdateReserveStatus()
    if not self.SessionServer then
        self.Window.RemainingText:SetText("|cFF808080Loot reserves are not started in your raid|r");
        self.Window.RemainingTextGlow:SetVertexColor(1, 1, 1, 0.15);
    elseif not self.AcceptingReserves then
        self.Window.RemainingText:SetText("|cFF808080Loot reserves are no longer being accepted|r");
        --self.Window.RemainingTextGlow:SetVertexColor(1, 0, 0, 0.15);
        -- animated in LootReserve.Client:OnWindowLoad instead
    else
        local reserves = LootReserve.Client:GetRemainingReserves();
        self.Window.RemainingText:SetText(format("You can reserve|cFF%s %d |rmore |4item:items;", reserves > 0 and "00FF00" or "FF0000", reserves));
        --self.Window.RemainingTextGlow:SetVertexColor(reserves > 0 and 0 or 1, reserves > 0 and 1 or 0, 0);
        --local r, g, b = self.Window.Duration:GetStatusBarColor();
        --self.Window.RemainingTextGlow:SetVertexColor(r, g, b, 0.15);
        -- animated in LootReserve.Client:OnWindowLoad instead
    end

    local list = self.Window.Loot.Scroll.Container;
    list.Frames = list.Frames or { };

    for i, frame in ipairs(list.Frames) do
        local item = frame.Item;
        if item ~= 0 then
            frame.ReserveFrame.ReserveButton:SetShown(self.SessionServer and not self:IsItemReservedByMe(item) and self:HasRemainingReserves());
            frame.ReserveFrame.CancelReserveButton:SetShown(self.SessionServer and self:IsItemReservedByMe(item) and self.AcceptingReserves);
            frame.ReserveFrame.ReserveIcon.One:Hide();
            frame.ReserveFrame.ReserveIcon.Many:Hide();
            frame.ReserveFrame.ReserveIcon.Number:Hide();
            frame.ReserveFrame.ReserveIcon.NumberMany:Hide();

            local pending = self:IsItemPending(item);
            frame.ReserveFrame.ReserveButton:SetEnabled(not pending);
            frame.ReserveFrame.CancelReserveButton:SetEnabled(not pending);

            if self.SessionServer then
                local reservers = self:GetItemReservers(item);
                if self:IsItemReservedByMe(item) then
                    if #reservers == 1 then
                        frame.ReserveFrame.ReserveIcon.One:Show();
                    else
                        frame.ReserveFrame.ReserveIcon.Many:Show();
                        frame.ReserveFrame.ReserveIcon.NumberMany:SetText(tostring(#reservers));
                        frame.ReserveFrame.ReserveIcon.NumberMany:Show();
                    end
                else
                    if #reservers > 0 then
                        frame.ReserveFrame.ReserveIcon.Number:SetText(tostring(#reservers));
                        frame.ReserveFrame.ReserveIcon.Number:Show();
                    end
                end
            end
        end
    end
end

function LootReserve.Client:UpdateLootList()
    local filter = self.Window.Search:GetText():gsub("^%s*(.-)%s*$", "%1"):upper();
    if #filter < 3 then
        filter = nil;
    end

    local list = self.Window.Loot.Scroll.Container;
    list.Frames = list.Frames or { };
    list.LastIndex = 0;
    list.ContentHeight = 0;
    
    local function createFrame(item, source)
        list.LastIndex = list.LastIndex + 1;
        local frame = list.Frames[list.LastIndex];
        while not frame do
            frame = CreateFrame("Frame", nil, list, "LootReserveLootListTemplate");

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

        frame.Item = item;

        if item == 0 then
            frame:SetHeight(16);
            frame:Hide();
        else
            frame:SetHeight(44);
            frame:Show();

            local name, link, _, _, _, type, subtype, _, _, texture = GetItemInfo(item);
            if subtype and type ~= subtype then
                type = type .. ", " .. subtype;
            end
            frame.Link = link;

            frame.ItemFrame.Icon:SetTexture(texture);
            frame.ItemFrame.Name:SetText((link or name or "|cFFFF4000Loading...|r"):gsub("[%[%]]", ""));
            frame.ItemFrame.Misc:SetText(source or type);
        end

        list.ContentHeight = list.ContentHeight + frame:GetHeight();
    end

    local function matchesFilter(item, filter)
        filter = (filter or ""):gsub("^%s*(.-)%s*$", "%1"):upper();
        if #filter == 0 then
            return true;
        end

        local name, link = GetItemInfo(item);
        if name then
            if string.find(name:upper(), filter) then
                return true;
            end
        else
            return nil;
        end

        return false;
    end

    if self.SelectedCategory and self.SelectedCategory.Reserves and self.SessionServer then
        for item in pairs(self.ItemReserves) do
            if self.SelectedCategory.Reserves == "my" and self:IsItemReservedByMe(item) then
                createFrame(item);
            elseif self.SelectedCategory.Reserves == "all" and self:IsItemReserved(item) then
                createFrame(item);
            end
        end
    elseif self.SelectedCategory and self.SelectedCategory.Search and filter then
        local missing = false;
        local uniqueItems = { };
        for id, category in LootReserve:Ordered(LootReserve.Data.Categories) do
            if category.Children and (not self.LootCategory or id == self.LootCategory) then
                for _, child in ipairs(category.Children) do
                    if child.Loot then
                        for _, item in ipairs(child.Loot) do
                            if item ~= 0 and not uniqueItems[item] then
                                uniqueItems[item] = true;
                                local match = matchesFilter(item, filter);
                                if match then
                                    createFrame(item, format("%s > %s", category.Name, child.Name));
                                elseif match == nil then
                                    missing = true;
                                end
                            end
                        end
                    end
                end
            end
        end
        if missing then
            C_Timer.After(0.25, function()
                self:UpdateLootList();
            end);
        end
    elseif self.SelectedCategory and self.SelectedCategory.Loot then
        for _, item in ipairs(self.SelectedCategory.Loot) do
            createFrame(item);
        end
    end
    for i = list.LastIndex + 1, #list.Frames do
        list.Frames[i]:Hide();
    end

    list:SetSize(list:GetParent():GetWidth(), math.max(list.ContentHeight, list:GetParent():GetHeight()));

    self:UpdateReserveStatus();
end

function LootReserve.Client:UpdateCategories()
    local list = self.Window.Categories.Scroll.Container;
    list.Frames = list.Frames or { };
    list.LastIndex = 0;
    list.ContentHeight = 0;
    
    local function createButton(id, category)
        list.LastIndex = list.LastIndex + 1;
        local frame = list.Frames[list.LastIndex];
        while not frame do
            frame = CreateFrame("CheckButton", nil, list,
                category.Separator and "LootReserveCategoryListSeparatorTemplate" or
                category.Children and "LootReserveCategoryListHeaderTemplate" or
                "LootReserveCategoryListButtonTemplate");

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

        frame.CategoryID = id;
        frame.Category = category;
        frame.DefaultHeight = frame.DefaultHeight or frame:GetHeight();

        if category.Separator then
            frame:EnableMouse(false);
        else
            frame.Text:SetText(category.Name);
            if category.Children then
                frame:EnableMouse(false);
            else
                frame:RegisterForClicks("LeftButtonDown");
                frame:SetScript("OnClick", function(frame) self:OnCategoryClick(frame); end);
            end
        end

        list.ContentHeight = list.ContentHeight + frame:GetHeight();
    end
    
    local function createCategoryButtonsRecursively(id, category)
        if category.Name or category.Separator then
            createButton(id, category);
        end
        if category.Children then
            for i, child in ipairs(category.Children) do
                createCategoryButtonsRecursively(id, child);
            end
        end
    end
    
    for id, category in LootReserve:Ordered(LootReserve.Data.Categories) do
        createCategoryButtonsRecursively(id, category);
    end

    local needsSelect = not self.SelectedCategory or self.SelectedCategory.Reserves;
    list.ContentHeight = 0;
    for i, frame in ipairs(list.Frames) do
        if i <= list.LastIndex and (frame.CategoryID < 0 or not self.LootCategory or frame.CategoryID == self.LootCategory) then
            frame:SetHeight(frame.DefaultHeight);
            frame:Show();
            list.ContentHeight = list.ContentHeight + frame.DefaultHeight;

            if needsSelect and selected == nil then
                if frame.CategoryID > 0 and self.LootCategory and frame.CategoryID == self.LootCategory then
                    selected = false;
                end
            elseif selected == false then
                selected = true;
                frame:Click();
            end
        else
            frame:Hide();
            frame:SetHeight(0.00001);
            if frame.Category == self.SelectedCategory then
                needsSelect = true;
            end
        end
    end

    if needsSelect then
        local selected = nil;
        for i, frame in ipairs(list.Frames) do
            if i <= list.LastIndex and (frame.CategoryID < 0 or not self.LootCategory or frame.CategoryID == self.LootCategory) then
                if needsSelect and selected == nil then
                    if frame.CategoryID > 0 and self.LootCategory and frame.CategoryID == self.LootCategory then
                        selected = false;
                    end
                elseif selected == false then
                    selected = true;
                    frame:Click();
                end
            end
        end
    end

    list:SetPoint("TOPLEFT");
    list:SetSize(list:GetParent():GetWidth(), math.max(list.ContentHeight, list:GetParent():GetHeight()));
end

function LootReserve.Client:OnCategoryClick(button)
    if not button.Category.Search then
        self.Window.Search:ClearFocus();
    end

    -- Don't allow deselecting the current selected category
    if not button:GetChecked() then
        button:SetChecked(true);
        return;
    end;

    -- Toggle off all the other checkbuttons
    for _, b in pairs(self.Window.Categories.Scroll.Container.Frames) do
        if b ~= button then
            b:SetChecked(false);
        end
    end

    self.SelectedCategory = button.Category;
    self.Window.Loot.Scroll:SetVerticalScroll(0);
    self:UpdateLootList();
end

function LootReserve.Client:OnWindowLoad(window)
    self.Window = window;
    self.Window.TopLeftCorner:SetSize(32, 32); -- Blizzard UI bug?
    self.Window.TitleText:SetText("Loot Reserve");
    self.Window:SetMinResize(550, 250);
    self:UpdateCategories();
    self:UpdateReserveStatus();
    LootReserve:RegisterUpdate(function(elapsed)
        if not self.SessionServer then
        elseif not self.AcceptingReserves then
            local r, g, b, a = self.Window.RemainingTextGlow:GetVertexColor();
            elapsed = math.min(elapsed, 1);
            r = r + (1 - r) * elapsed / 0.5;
            g = g + (0 - g) * elapsed / 0.5;
            b = b + (0 - b) * elapsed / 0.5;
            a = a + (0.15 - a) * elapsed / 0.5;
            self.Window.RemainingTextGlow:SetVertexColor(r, g, b, a);
        elseif self.Duration == 0 then
            self.Window.RemainingTextGlow:SetVertexColor(0, 1, 0);
        else
            local r, g, b = self.Window.Duration:GetStatusBarColor();
            self.Window.RemainingTextGlow:SetVertexColor(r, g, b, 0.15 + r * 0.25);
        end
    end);
    LootReserve:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(item, success)
        if not item or not self.SelectedCategory then return; end

        if self.SelectedCategory.Loot then
            for _, loot in ipairs(self.SelectedCategory.Loot) do
                if item == loot then
                    self:UpdateLootList();
                end
            end
        elseif self.SelectedCategory.Search or self.SelectedCategory.Reserves then
            self:UpdateLootList();
        end
    end);

    LootReserve.Comm:StartListening();
end
