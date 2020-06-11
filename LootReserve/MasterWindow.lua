function LootReserve.Client:UpdateReserveStatus()
    if self.SessionServer then
        self.Window.RemainingText:SetText(format("You can reserve|cFFFF0000 %d |rmore |4item:items;", LootReserve.Client:GetRemainingReserves()));
    else
        self.Window.RemainingText:SetText("|cFF808080Loot reserves are not being accepted at the moment|r");
    end

    local list = self.Window.Loot.Scroll.Container;
    list.Frames = list.Frames or { };

    for i, frame in ipairs(list.Frames) do
        local item = frame.Item;
        if item ~= 0 then
            frame.ReserveFrame.ReserveButton:Hide();
            frame.ReserveFrame.CancelReserveButton:Hide();
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
                    frame.ReserveFrame.CancelReserveButton:Show();
                    if #reservers == 1 then
                        frame.ReserveFrame.ReserveIcon.One:Show();
                    else
                        frame.ReserveFrame.ReserveIcon.Many:Show();
                        frame.ReserveFrame.ReserveIcon.NumberMany:SetText(tostring(#reservers));
                        frame.ReserveFrame.ReserveIcon.NumberMany:Show();
                    end
                else
                    if self:HasRemainingReserves() then
                        frame.ReserveFrame.ReserveButton:Show();
                    end
                    if #reservers > 0 then
                        frame.ReserveFrame.ReserveIcon.Number:SetText(tostring(#reservers));
                        frame.ReserveFrame.ReserveIcon.Number:Show();
                    end
                end
            end
        end
    end
end

function LootReserve.Client:OnCategoryClick(button)
    -- Don't allow deselecting the current selected category
    if not button:GetChecked() then
        button:SetChecked(true);
        return;
    end;

    -- Toggle off all the other checkbuttons
    for _, b in pairs(self.Window.Categories.Scroll.Container.Buttons) do
        if b ~= button then
            b:SetChecked(false);
        end
    end

    self:SelectCategory(button.Category);
end

function LootReserve.Client:SelectCategory(category)
    self.SelectedCategory = category;

    local list = self.Window.Loot.Scroll.Container;
    list.Frames = list.Frames or { };
    list.ContentHeight = 0;
    
    local function createFrame(i, item)
        while #list.Frames < i do
            local frame = CreateFrame("Frame", nil, list, "LootReserveLootListTemplate");

            if #list.Frames == 0 then
                frame:SetPoint("TOPLEFT", list, "TOPLEFT");
                frame:SetPoint("TOPRIGHT", list, "TOPRIGHT");
            else
                frame:SetPoint("TOPLEFT", list.Frames[#list.Frames], "BOTTOMLEFT", 0, 0);
                frame:SetPoint("TOPRIGHT", list.Frames[#list.Frames], "BOTTOMRIGHT", 0, 0);
            end
            table.insert(list.Frames, frame);
        end

        local frame = list.Frames[i];

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

            frame.ItemFrame.Icon:SetTexture(texture);
            frame.ItemFrame.Name:SetText((link or name or "|cFFFF4000Loading...|r"):gsub("[%[%]]", ""));
            frame.ItemFrame.Type:SetText(type);
        end

        list.ContentHeight = list.ContentHeight + frame:GetHeight();
    end
    
    local last = 0;
    if self.SelectedCategory.Loot then
        for i, item in ipairs(self.SelectedCategory.Loot) do
            createFrame(i, item);
            last = i;
        end
    end
    for i = last + 1, #list.Frames do
        list.Frames[i]:Hide();
    end

    list:SetPoint("TOPLEFT");
    list:SetWidth(list:GetParent():GetWidth());
    list:SetHeight(math.max(list.ContentHeight, list:GetParent():GetHeight()));

    self:UpdateReserveStatus();
end

function LootReserve.Client:OnWindowLoad(window)
    self.Window = window;
    self:LoadCategories();
    LootReserve:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(item, success)
        if item and self.SelectedCategory then
            for _, loot in ipairs(self.SelectedCategory.Loot) do
                if item == loot then
                    self:SelectCategory(self.SelectedCategory);
                end
            end
        end
    end);
end

function LootReserve.Client:LoadCategories()
    local list = self.Window.Categories.Scroll.Container;
    list.Buttons = list.Buttons or { };
    list.ContentHeight = 0;
    
    local function createButton(category)
        local button = CreateFrame("CheckButton", nil, list,
            category.Separator and "LootReserveCategoryListSeparatorTemplate" or
            category.Children and "LootReserveCategoryListHeaderTemplate" or
            "LootReserveCategoryListButtonTemplate");

        button.Category = category;

        if category.Separator then
            button:EnableMouse(false);
        else
            button.Text:SetText(category.Name);
            if category.Children then
                button:EnableMouse(false);
            else
                button:RegisterForClicks("LeftButtonDown");
                button:SetScript("OnClick", function(button) self:OnCategoryClick(button); end);
            end
        end
        
        if #list.Buttons == 0 then
            button:SetPoint("TOPLEFT", list, "TOPLEFT");
            button:SetPoint("TOPRIGHT", list, "TOPRIGHT");
        else
            button:SetPoint("TOPLEFT", list.Buttons[#list.Buttons], "BOTTOMLEFT", 0, 0);
            button:SetPoint("TOPRIGHT", list.Buttons[#list.Buttons], "BOTTOMRIGHT", 0, 0);
        end
        table.insert(list.Buttons, button);

        list.ContentHeight = list.ContentHeight + button:GetHeight();
    end
    
    local function createCategoryButtonsRecursively(category)
        if category.Name or category.Separator then
            createButton(category);
        end
        if category.Children then
            for i, child in ipairs(category.Children) do
                createCategoryButtonsRecursively(child);
            end
        end
    end
    
    for i, category in LootReserve:Ordered(LootReserve.Data.Categories) do
        createCategoryButtonsRecursively(category);
    end

    list:SetPoint("TOPLEFT");
    list:SetWidth(list:GetParent():GetWidth());
    list:SetHeight(list.ContentHeight);

    self:UpdateReserveStatus();
end
