function LootReserve.Client:UpdateReserveStatus()
    if not self.SessionServer then
        self.Window.RemainingText:SetText("|cFF808080Loot reserves are not started in your raid|r");
        self.Window.RemainingTextGlow:SetVertexColor(1, 1, 1, 0.15);
    elseif not self.AcceptingReserves then
        self.Window.RemainingText:SetText("|cFF808080Loot reserves are no longer being accepted|r");
        --self.Window.RemainingTextGlow:SetVertexColor(1, 0, 0, 0.15);
        -- animated in LootReserve.Client:OnWindowLoad instead
    elseif self.Locked then
        self.Window.RemainingText:SetText("|cFF808080You are locked-in and cannot change your reserves|r");
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
            local _, myReserves, uniquePlayers, totalReserves = LootReserve:GetReservesData(self:GetItemReservers(item), LootReserve:Me());
            local canReserve = self.SessionServer and self:HasRemainingReserves() and LootReserve.ItemConditions:IsItemReservableOnClient(item) and (not self.Multireserve or myReserves < self.Multireserve);
            frame.ReserveFrame.ReserveButton:SetShown(canReserve and myReserves == 0);
            frame.ReserveFrame.MultiReserveButton:SetShown(canReserve and myReserves > 0 and self.Multireserve);
            frame.ReserveFrame.MultiReserveButton:SetText(format("x%d", myReserves + 1));
            frame.ReserveFrame.CancelReserveButton:SetShown(self.SessionServer and self:IsItemReservedByMe(item) and self.AcceptingReserves);
            frame.ReserveFrame.CancelReserveButton:SetWidth(frame.ReserveFrame.ReserveButton:GetWidth() - (frame.ReserveFrame.MultiReserveButton:IsShown() and frame.ReserveFrame.MultiReserveButton:GetWidth() - select(4, frame.ReserveFrame.MultiReserveButton:GetPoint(1)) or 0));
            frame.ReserveFrame.ReserveIcon.One:Hide();
            frame.ReserveFrame.ReserveIcon.Many:Hide();
            frame.ReserveFrame.ReserveIcon.Number:Hide();
            frame.ReserveFrame.ReserveIcon.NumberLimit:Hide();
            frame.ReserveFrame.ReserveIcon.NumberMany:Hide();
            frame.ReserveFrame.ReserveIcon.NumberMulti:Hide();

            local pending = self:IsItemPending(item);
            frame.ReserveFrame.ReserveButton:SetEnabled(not pending and not self.Locked);
            frame.ReserveFrame.MultiReserveButton:SetEnabled(not pending and not self.Locked);
            frame.ReserveFrame.CancelReserveButton:SetEnabled(not pending and not self.Locked);

            if self.SessionServer then
                local conditions = self.ItemConditions[item];
                local numberString;
                if conditions and conditions.Limit and conditions.Limit ~= 0 then
                    numberString = format(totalReserves >= conditions.Limit and "|cFFFF0000%d/%d|r" or "%d/%d", totalReserves, conditions.Limit);
                else
                    numberString = tostring(totalReserves);
                end

                if myReserves > 0 then
                    if uniquePlayers == 1 and not self.Blind then
                        frame.ReserveFrame.ReserveIcon.One:Show();
                    else
                        frame.ReserveFrame.ReserveIcon.Many:Show();
                        if not self.Blind then
                            frame.ReserveFrame.ReserveIcon.NumberMany:SetText(numberString);
                            frame.ReserveFrame.ReserveIcon.NumberMany:Show();
                        end
                    end
                    if myReserves > 1 then
                        frame.ReserveFrame.ReserveIcon.NumberMulti:SetText(format("x%d", myReserves));
                        frame.ReserveFrame.ReserveIcon.NumberMulti:Show();
                    end
                else
                    if conditions and conditions.Limit and conditions.Limit ~= 0 then
                        frame.ReserveFrame.ReserveIcon.NumberLimit:SetText(numberString);
                        frame.ReserveFrame.ReserveIcon.NumberLimit:Show();
                    elseif totalReserves > 0 then
                        frame.ReserveFrame.ReserveIcon.Number:SetText(numberString);
                        frame.ReserveFrame.ReserveIcon.Number:Show();
                    end
                end
            end
        end
    end
end

function LootReserve.Client:UpdateLootList()
    local filter = LootReserve:TransformSearchText(self.Window.Search:GetText());
    if #filter < 3 then
        filter = nil;
    end

    local list = self.Window.Loot.Scroll.Container;
    list.Frames = list.Frames or { };
    list.LastIndex = 0;
    list.ContentHeight = 0;

    if list.CharacterFavoritesHeader then
        list.CharacterFavoritesHeader:Hide();
    end
    if list.GlobalFavoritesHeader then
        list.GlobalFavoritesHeader:Hide();
    end

    local function createFrame(item, source)
        list.LastIndex = list.LastIndex + 1;
        local frame = list.Frames[list.LastIndex];
        while not frame do
            frame = CreateFrame("Frame", nil, list, "LootReserveLootListTemplate");
            table.insert(list.Frames, frame);
            frame = list.Frames[list.LastIndex];
        end

        frame.Item = item;

        if item == 0 then
            if list.LastIndex <= 1 or not list.Frames[list.LastIndex - 1]:IsShown() then
                frame:SetHeight(0.00001);
                frame:Hide();
            else
                frame:SetHeight(16);
                frame:Hide();
            end
            frame.Favorite:Hide();
        else
            frame:SetHeight(44);
            frame:Show();

            local name, link, _, _, _, type, subtype, _, _, texture = GetItemInfo(item);
            if subtype and type ~= subtype then
                type = type .. ", " .. subtype;
            end
            frame.Link = link;

            local conditions = self.ItemConditions[item];
            if conditions and conditions.Limit and conditions.Limit ~= 0 then
                source = format("|cFFFF0000(Max %d |4reserve:reserves;) |r%s", conditions.Limit, source or type or "");
            end

            frame.ItemFrame.Icon:SetTexture(texture);
            frame.ItemFrame.Name:SetText((link or name or "|cFFFF4000Loading...|r"):gsub("[%[%]]", ""));
            frame.ItemFrame.Misc:SetText(source or type);
            frame.Favorite:SetPoint("LEFT", frame.ItemFrame.Name, "LEFT", math.min(frame.ItemFrame:GetWidth() - 57, frame.ItemFrame.Name:GetStringWidth()), 0);
            frame.Favorite.Set:SetShown(not self:IsFavorite(item));
            frame.Favorite.Unset:SetShown(not frame.Favorite.Set:IsShown());
            frame.Favorite:SetShown(frame.hovered or frame.Favorite.Unset:IsShown());
            frame.ItemFrame.Name:SetPoint("TOPRIGHT", frame.ItemFrame, "TOPRIGHT", frame.Favorite:IsShown() and -20 or 0, 0);
        end

        frame:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -list.ContentHeight);
        frame:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -list.ContentHeight);
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

    local function sortByItemName(_, _, aItem, bItem)
        local aName = GetItemInfo(aItem);
        local bName = GetItemInfo(bItem);
        if not aName then return false; end
        if not bName then return true; end
        return aName < bName;
    end

    if self.SelectedCategory and self.SelectedCategory.Reserves and self.SessionServer then
        for item in LootReserve:Ordered(self.ItemReserves, sortByItemName) do
            if self.SelectedCategory.Reserves == "my" and self:IsItemReservedByMe(item) then
                createFrame(item);
            elseif self.SelectedCategory.Reserves == "all" and self:IsItemReserved(item) and not self.Blind then
                createFrame(item);
            end
        end
    elseif self.SelectedCategory and self.SelectedCategory.Favorites then
        for _, favorites in ipairs({ self.CharacterFavorites, self.GlobalFavorites }) do
            local first = true;
            for item in LootReserve:Ordered(favorites, sortByItemName) do
                local conditions = self.ItemConditions[item];
                if item ~= 0 and (not self.LootCategory or LootReserve.Data:IsItemInCategory(item, self.LootCategory) or conditions and conditions.Custom) and LootReserve.ItemConditions:IsItemVisibleOnClient(item) then
                    if first then
                        first = false;
                        if favorites == self.CharacterFavorites then
                            if not list.CharacterFavoritesHeader then
                                list.CharacterFavoritesHeader = CreateFrame("Frame", nil, list, "LootReserveLootFavoritesHeader");
                                list.CharacterFavoritesHeader.Text:SetText(format("%s's Favorites", LootReserve:ColoredPlayer(LootReserve:Me())));
                            end
                            list.CharacterFavoritesHeader:Show();
                            list.CharacterFavoritesHeader:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -list.ContentHeight);
                            list.CharacterFavoritesHeader:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -list.ContentHeight);
                            list.ContentHeight = list.ContentHeight + list.CharacterFavoritesHeader:GetHeight();
                        elseif favorites == self.GlobalFavorites then
                            if not list.GlobalFavoritesHeader then
                                list.GlobalFavoritesHeader = CreateFrame("Frame", nil, list, "LootReserveLootFavoritesHeader");
                                list.GlobalFavoritesHeader.Text:SetText("Account Favorites");
                            end
                            list.GlobalFavoritesHeader:Show();
                            list.GlobalFavoritesHeader:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -list.ContentHeight);
                            list.GlobalFavoritesHeader:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -list.ContentHeight);
                            list.ContentHeight = list.ContentHeight + list.GlobalFavoritesHeader:GetHeight();
                        end
                    end
                    createFrame(item);
                end
            end
        end
    elseif self.SelectedCategory and self.SelectedCategory.Search and filter then
        local missing = false;
        local uniqueItems = { };
        for item, conditions in pairs(self.ItemConditions) do
            if item ~= 0 and conditions.Custom and not uniqueItems[item] and LootReserve.ItemConditions:IsItemVisibleOnClient(item) then
                uniqueItems[item] = true;
                local match = matchesFilter(item, filter);
                if match then
                    createFrame(item, "Custom Item");
                elseif match == nil then
                    missing = true;
                end
            end
        end
        for id, category in LootReserve:Ordered(LootReserve.Data.Categories, LootReserve.Data.CategorySorter) do
            if category.Children and (not self.LootCategory or id == self.LootCategory) and LootReserve.Data:IsCategoryVisible(category) then
                for _, child in ipairs(category.Children) do
                    if child.Loot then
                        for _, item in ipairs(child.Loot) do
                            if item ~= 0 and not uniqueItems[item] and LootReserve.ItemConditions:IsItemVisibleOnClient(item) then
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
    elseif self.SelectedCategory and self.SelectedCategory.Custom then
        for item, conditions in pairs(self.ItemConditions) do
            if item ~= 0 and conditions.Custom and LootReserve.ItemConditions:IsItemVisibleOnClient(item) then
                createFrame(item);
            end
        end
    elseif self.SelectedCategory and self.SelectedCategory.Loot then
        for _, item in ipairs(self.SelectedCategory.Loot) do
            if LootReserve.ItemConditions:IsItemVisibleOnClient(item) then
                createFrame(item);
            end
        end
    end
    for i = list.LastIndex + 1, #list.Frames do
        list.Frames[i]:Hide();
    end

    if self.Blind and not list.BlindHint then
        list.BlindHint = CreateFrame("Frame", nil, list, "LootReserveLootBlindHint");
    end
    if list.BlindHint then
        list.BlindHint:SetShown(self.Blind and self.SelectedCategory and self.SelectedCategory.Reserves == "all");
    end

    list:GetParent():UpdateScrollChildRect();

    self:UpdateReserveStatus();
end

function LootReserve.Client:UpdateCategories()
    local list = self.Window.Categories.Scroll.Container;
    list.Frames = list.Frames or { };
    list.LastIndex = 0;

    local function createButton(id, category, expansion)
        list.LastIndex = list.LastIndex + 1;
        local frame = list.Frames[list.LastIndex];
        while not frame do
            frame = CreateFrame("CheckButton", nil, list,
                not category and "LootReserveCategoryListExpansionTemplate" or
                category.Separator and "LootReserveCategoryListSeparatorTemplate" or
                category.Children and "LootReserveCategoryListHeaderTemplate" or
                category.Header and "LootReserveCategoryListSubheaderTemplate" or
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
        frame.Expansion = expansion;
        frame.DefaultHeight = frame.DefaultHeight or frame:GetHeight();

        if not category then
            frame.Text:SetText(format(self.Settings.CollapsedExpansions[frame.Expansion] and "|cFF404040%s|r" or "|cFFFFD200%s|r", _G["EXPANSION_NAME"..expansion]));
            frame.GlowLeft:SetShown(not self.Settings.CollapsedExpansions[frame.Expansion]);
            frame.GlowRight:SetShown(not self.Settings.CollapsedExpansions[frame.Expansion]);
            frame:RegisterForClicks("LeftButtonDown");
            frame:SetScript("OnClick", function(frame) self:OnExpansionToggle(frame); end);
        elseif category.Separator then
            frame:EnableMouse(false);
        elseif category.Header then
            frame.Text:SetText(category.Name);
            frame:EnableMouse(false);
        elseif category.Children then
            local categoryCollapsed = self.Settings.CollapsedCategories[frame.CategoryID];
            if frame.CategoryID < 0 or self.LootCategory and frame.CategoryID == self.LootCategory then
                categoryCollapsed = false;
                frame:EnableMouse(false);
            else
                frame:EnableMouse(true);
                frame:RegisterForClicks("LeftButtonDown");
                frame:SetScript("OnClick", function(frame) self:OnCategoryToggle(frame); end);
            end
            frame.Text:SetText(format(categoryCollapsed and "|cFF806900%s|r" or "%s", category.Name));
        else
            frame.Text:SetText(category.Name);
            frame:RegisterForClicks("LeftButtonDown");
            frame:SetScript("OnClick", function(frame) self:OnCategoryClick(frame); end);
        end
    end

    local lastExpansion = nil;

    local function createCategoryButtonsRecursively(id, category)
        if category.Expansion and category.Expansion ~= lastExpansion then
            lastExpansion = category.Expansion;
            if LootReserve:GetCurrentExpansion() > 0 then
                createButton(nil, nil, lastExpansion);
            end
        end
        if category.Name or category.Separator then
            createButton(id, category, lastExpansion);
        end
        if category.Children then
            for i, child in ipairs(category.Children) do
                if not child.Edited then
                    createCategoryButtonsRecursively(id, child);
                end
            end
        end
    end

    for id, category in LootReserve:Ordered(LootReserve.Data.Categories, LootReserve.Data.CategorySorter) do
        if LootReserve.Data:IsCategoryVisible(category) then
            createCategoryButtonsRecursively(id, category);
        end
    end

    local needsSelect = not self.SelectedCategory;
    for i, frame in ipairs(list.Frames) do
        local expansionCollapsed = self.Settings.CollapsedExpansions[frame.Expansion];
        local categoryCollapsed = self.Settings.CollapsedCategories[frame.CategoryID];
        if self.LootCategory and frame.CategoryID == self.LootCategory then
            expansionCollapsed = false;
            categoryCollapsed = false;
        end

        if i <= list.LastIndex
            and (not self.LootCategory or not frame.CategoryID or frame.CategoryID < 0 or frame.CategoryID == self.LootCategory)
            and (not frame.Category or not frame.Category.Custom or LootReserve.ItemConditions:HasCustom(false))
            and (not categoryCollapsed or not frame.Category or frame.Category.Children)
            and (not expansionCollapsed or not frame.Category)
            and (not frame.Expansion or frame.Category or not self.LootCategory)
            then
            if categoryCollapsed and frame.Category and frame.Category.Children then
                frame:SetHeight(frame.DefaultHeight - 7);
            else
                frame:SetHeight(frame.DefaultHeight);
            end
            frame:Show();
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
                    if frame.CategoryID and frame.CategoryID > 0 and self.LootCategory and frame.CategoryID == self.LootCategory then
                        selected = false;
                    end
                elseif selected == false then
                    selected = true;
                    frame:Click();
                end
            end
        end
    end

    list:GetParent():UpdateScrollChildRect();
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

    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
    self:StopCategoryFlashing(button);

    self.SelectedCategory = button.Category;
    self.Window.Loot.Scroll:SetVerticalScroll(0);
    self:UpdateLootList();
end

function LootReserve.Client:OnCategoryToggle(button)
    button:SetChecked(false);
    self.Settings.CollapsedCategories[button.CategoryID] = not self.Settings.CollapsedCategories[button.CategoryID] or nil;
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
    self:UpdateCategories();
end

function LootReserve.Client:OnExpansionToggle(button)
    button:SetChecked(false);
    self.Settings.CollapsedExpansions[button.Expansion] = not self.Settings.CollapsedExpansions[button.Expansion] or nil;
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
    self:UpdateCategories();
end

function LootReserve.Client:FlashCategory(categoryField, value, continuously)
    for _, button in pairs(self.Window.Categories.Scroll.Container.Frames) do
        if button:IsShown() and button.Flash and not button.Expansion and button.Category and button.Category[categoryField] and (value == nil or button.Category[categoryField] == value) then
            button.Flash:SetAlpha(1);
            button.ContinuousFlashing = (button.ContinuousFlashing or continuously) and 0 or nil;
            self.CategoryFlashing = true;
        end
    end
end

function LootReserve.Client:StopCategoryFlashing(button)
    if button then
        button.Flash:SetAlpha(0);
        button.ContinuousFlashing = nil;
    else
        self.CategoryFlashing = false;
        for _, button in pairs(self.Window.Categories.Scroll.Container.Frames) do
            if button:IsShown() and button.Flash then
                button.Flash:SetAlpha(0);
                button.ContinuousFlashing = nil;
            end
        end
    end
end

function LootReserve.Client:OnWindowLoad(window)
    self.Window = window;
    self.Window.TopLeftCorner:SetSize(32, 32); -- Blizzard UI bug?
    self.Window.TitleText:SetPoint("TOP", self.Window, "TOP", 0, -4);
    self.Window.TitleText:SetText("Loot Reserve");
    self.Window:SetMinResize(550, 250);
    self:UpdateCategories();
    self:UpdateReserveStatus();
    LootReserve:RegisterUpdate(function(elapsed)
        if self.CategoryFlashing and self.Window:IsShown() then
            self.CategoryFlashing = false;
            for _, button in pairs(self.Window.Categories.Scroll.Container.Frames) do
                if button:IsShown() and button.Flash and (button.Flash:GetAlpha() > 0 or button.ContinuousFlashing) then
                    if button.ContinuousFlashing then
                        button.ContinuousFlashing = (button.ContinuousFlashing + elapsed) % 1;
                        button.Flash:SetAlpha(0.5 + 0.25 * (1 + math.cos(button.ContinuousFlashing * 2 * 3.14159265)));
                    else
                        button.Flash:SetAlpha(math.max(0, button.Flash:GetAlpha() - elapsed));
                    end
                    self.CategoryFlashing = true;
                end
            end
        end

        if not self.SessionServer then
        elseif not self.AcceptingReserves or self.Locked then
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

        if self.SelectedCategory.Custom then
            local conditions = LootReserve.ItemConditions:Get(item, false);
            if conditions and conditions.Custom then
                self:UpdateLootList();
            end
        elseif self.SelectedCategory.Loot then
            for _, loot in ipairs(self.SelectedCategory.Loot) do
                if item == loot then
                    self:UpdateLootList();
                end
            end
        elseif self.SelectedCategory.Favorites and self:IsFavorite(item) then
            self:UpdateLootList();
        elseif self.SelectedCategory.Search or self.SelectedCategory.Reserves then
            self:UpdateLootList();
        end
    end);
end
