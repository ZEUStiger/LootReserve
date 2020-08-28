-- TODO: Disable all loot edit actions if session is active

function LootReserve.Server.LootEdit:UpdateLootList()
    local filter = LootReserve:TransformSearchText(self.Window.Search:GetText());
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
            frame = CreateFrame("Frame", nil, list, "LootReserveLootEditListTemplate");

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
            if list.LastIndex > 1 and not list.Frames[list.LastIndex - 1]:IsShown() then
                frame:SetHeight(0.00001);
                frame:Hide();
            else
                frame:SetHeight(16);
                frame:Hide();
            end
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

    if self.SelectedCategory and self.SelectedCategory.Search and filter then
        local missing = false;
        local uniqueItems = { };
        for id, category in LootReserve:Ordered(LootReserve.Data.Categories) do
            if category.Children and (not LootReserve.Server.NewSessionSettings.LootCategory or id == LootReserve.Server.NewSessionSettings.LootCategory) then
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
end

function LootReserve.Server.LootEdit:UpdateCategories()
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
                if not child.Reserves then
                    createCategoryButtonsRecursively(id, child);
                end
            end
        end
    end
    
    for id, category in LootReserve:Ordered(LootReserve.Data.Categories) do
        createCategoryButtonsRecursively(id, category);
    end

    local needsSelect = not self.SelectedCategory;
    list.ContentHeight = 0;
    for i, frame in ipairs(list.Frames) do
        if i <= list.LastIndex and (frame.CategoryID < 0 or not LootReserve.Server.NewSessionSettings.LootCategory or frame.CategoryID == LootReserve.Server.NewSessionSettings.LootCategory) then
            frame:SetHeight(frame.DefaultHeight);
            frame:Show();
            list.ContentHeight = list.ContentHeight + frame.DefaultHeight;
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
            if i <= list.LastIndex then
                if selected == nil then
                    if frame.CategoryID > 0 and LootReserve.Server.NewSessionSettings.LootCategory and frame.CategoryID == LootReserve.Server.NewSessionSettings.LootCategory then
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

function LootReserve.Server.LootEdit:OnCategoryClick(button)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
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

function LootReserve.Server.LootEdit:OnWindowLoad(window)
    self.Window = window;
    self.Window.TopLeftCorner:SetSize(32, 32); -- Blizzard UI bug?
    self.Window.TitleText:SetPoint("TOP", self.Window, "TOP", 0, -4);
    self.Window.TitleText:SetText("Loot Reserve Server - Loot Edit");
    self.Window:SetMinResize(550, 250);
    self:UpdateCategories();
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
end