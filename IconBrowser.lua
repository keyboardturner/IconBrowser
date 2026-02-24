--[[
	all hail Meorawr AKA moowoo aka Miku Enjoyer 2 aka Meowaww aka Meorawr Malvaceaa aka idk what else to put here
	
	anyway here's the original trp3 copyright because it's relevant to the code i "borrowed" / adapted from:

	-- Copyright The Total RP 3 Authors
	-- SPDX-License-Identifier: Apache-2.0

--]]

local addonName, LRPMIB = ...;

local L = LRPMIB.L;

local LRPM12 = LibStub:GetLibrary("LibRPMedia-1.2");

local IconBrowserConstants = LRPMIB.IconBrowserConstants;

local IconBrowserSearchTask = CreateFromMixins(CallbackRegistryMixin);

function IconBrowserSearchTask:Init(predicate, model)
	self:GenerateCallbackEvents({"OnStateChanged", "OnProgressChanged", "OnResultsChanged"})
	self:OnLoad()
	
	self.state = "pending"
	self.predicate = predicate
	self.found = 0
	self.searched = 0
	self.iterator = model:EnumerateIcons({ reuseTable = {} })
	self.total = model:GetIconCount()
	self.step = math.min(500, math.ceil(model:GetIconCount() / 20))
	self.results = {}
end

function IconBrowserSearchTask:Start()
	self.ticker = C_Timer.NewTicker(0, function() self:OnUpdate(); end)
	self.state = "running"
	self:TriggerEvent("OnStateChanged", self.state)
end

function IconBrowserSearchTask:Finish()
	if self.state == "finished" then return; end
	if self.ticker then self.ticker:Cancel() end
	self.ticker = nil
	self.state = "finished"
	self:TriggerEvent("OnStateChanged", self.state)
end

function IconBrowserSearchTask:OnUpdate()
	local found, visited = self.found, self.searched
	local limit = math.min(self.searched + self.step, self.total)

	for iconIndex, iconInfo in self.iterator do
		if self.predicate(iconIndex, iconInfo) then
			found = found + 1;
			self.results[found] = iconIndex;
		end
		visited = visited + 1
		if visited > limit then break; end
	end

	if self.searched == 0 or self.found ~= found then
		self.found = found;
		self:TriggerEvent("OnResultsChanged", self.results);
	end

	self.searched = limit
	self:TriggerEvent("OnProgressChanged", { found = self.found, searched = self.searched, total = self.total })

	if self.searched >= self.total then
		self:Finish();
	end
end


------------------------------------------------------------------------------------------------------

local IconBrowserModel = CreateFromMixins(CallbackRegistryMixin)

function IconBrowserModel:Init()
	self:GenerateCallbackEvents({"OnModelUpdated"})
	self:OnLoad()
end

function IconBrowserModel:GetIconCount() return LRPM12:GetNumIcons() end
function IconBrowserModel:GetIconInfo(index) return LRPM12:GetIconInfoByIndex(index) end
function IconBrowserModel:EnumerateIcons(options) return LRPM12:EnumerateIcons(options) end


------------------------------------------------------------------------------------------------------

local IconBrowserSelectionModel = CreateFromMixins(CallbackRegistryMixin)

function IconBrowserSelectionModel:Init(source)
	self:GenerateCallbackEvents({"OnModelUpdated"})
	self:OnLoad()
	self.source = source
	self.selectedFileID = nil
	self.selectedIndex = nil
	self.source:RegisterCallback("OnModelUpdated", function() self:RebuildModel(); end, self)
end

function IconBrowserSelectionModel:GetIconCount()
	return self.source:GetIconCount();
end

function IconBrowserSelectionModel:GetSourceIndex(proxyIndex)
	if not self.selectedIndex then return proxyIndex end
	if proxyIndex == 1 then return self.selectedIndex end
	if proxyIndex <= self.selectedIndex then return proxyIndex - 1 end
	return proxyIndex
end

function IconBrowserSelectionModel:GetProxyIndex(sourceIndex)
	if not self.selectedIndex then return sourceIndex end
	if sourceIndex == self.selectedIndex then return 1 end
	if sourceIndex < self.selectedIndex then return sourceIndex + 1 end
	return sourceIndex
end

function IconBrowserSelectionModel:GetIconInfo(index)
	local sourceIndex = self:GetSourceIndex(index)
	return self.source:GetIconInfo(sourceIndex)
end

function IconBrowserSelectionModel:EnumerateIcons(options)
	local iterator = self.source:EnumerateIcons(options)
	local hasEnumeratedSelection = (self.selectedIndex == nil)

	local function GetNextIcon()
		if not hasEnumeratedSelection then
			hasEnumeratedSelection = true;
			return 1, self:GetIconInfo(1);
		end

		local sourceIndex, iconInfo = iterator()
		if sourceIndex == self.selectedIndex then
			sourceIndex, iconInfo = iterator();
		end

		if sourceIndex ~= nil then
			return self:GetProxyIndex(sourceIndex), iconInfo;
		end
	end

	return GetNextIcon
end

function IconBrowserSelectionModel:SetSelectedFileID(fileId)
	if self.selectedFileID ~= fileId then
		self.selectedFileID = fileId;
		self:RebuildModel();
	end
end

function IconBrowserSelectionModel:RebuildModel()
	self.selectedIndex = nil
	if self.selectedFileID then
		for index, info in self.source:EnumerateIcons() do
			if info.file == self.selectedFileID then
				self.selectedIndex = index;
				break;
			end
		end
	end
	self:TriggerEvent("OnModelUpdated")
end


------------------------------------------------------------------------------------------------------

local IconBrowserPinnedModel = CreateFromMixins(CallbackRegistryMixin)

function IconBrowserPinnedModel:Init(source)
	self:GenerateCallbackEvents({"OnModelUpdated"})
	self:OnLoad()
	self.source = source
	self.pinnedFileIDs = {}
	self.proxyToSource = nil
	self.pinnedSourceSet = {}
	self.pinnedCount = 0
	self.source:RegisterCallback("OnModelUpdated", function() self:RebuildModel() end, self)
end

function IconBrowserPinnedModel:SetPinnedFileIDs(fileIDs)
	local seen = {}
	local deduped = {}
	for _, fid in ipairs(fileIDs or {}) do
		if fid and fid ~= 0 and not seen[fid] then
			seen[fid] = true
			table.insert(deduped, fid);
		end
	end
	self.pinnedFileIDs = deduped
	self:RebuildModel()
end

function IconBrowserPinnedModel:RebuildModel()
	if #self.pinnedFileIDs == 0 then
		self.proxyToSource = nil;
		self.pinnedSourceSet = {};
		self.pinnedCount = 0;
		self:TriggerEvent("OnModelUpdated");
		return;
	end

	local wantedSet = {}
	for _, fid in ipairs(self.pinnedFileIDs) do
		wantedSet[fid] = true;
	end

	local fileIDToSourceIndex = {}
	local remaining = #self.pinnedFileIDs
	for index, info in self.source:EnumerateIcons() do
		if wantedSet[info.file] and not fileIDToSourceIndex[info.file] then
			fileIDToSourceIndex[info.file] = index;
			remaining = remaining - 1;
			if remaining == 0 then break; end
		end
	end

	local pinnedSourceIndices = {}
	local pinnedSourceSet = {}
	for _, fid in ipairs(self.pinnedFileIDs) do
		local si = fileIDToSourceIndex[fid];
		if si then
			table.insert(pinnedSourceIndices, si);
			pinnedSourceSet[si] = true;
		end
	end

	if #pinnedSourceIndices == 0 then
		self.proxyToSource = nil;
		self.pinnedSourceSet = {};
		self.pinnedCount = 0;
		self:TriggerEvent("OnModelUpdated");
		return;
	end

	local proxyToSource = {}
	for i, si in ipairs(pinnedSourceIndices) do
		proxyToSource[i] = si;
	end
	local pi = #pinnedSourceIndices + 1
	for si = 1, self.source:GetIconCount() do
		if not pinnedSourceSet[si] then
			proxyToSource[pi] = si;
			pi = pi + 1;
		end
	end

	self.proxyToSource = proxyToSource
	self.pinnedSourceSet = pinnedSourceSet
	self.pinnedCount = #pinnedSourceIndices
	self:TriggerEvent("OnModelUpdated")
end

function IconBrowserPinnedModel:GetIconCount()
	return self.source:GetIconCount();
end

function IconBrowserPinnedModel:GetIconInfo(proxyIndex)
	if not self.proxyToSource then
		return self.source:GetIconInfo(proxyIndex);
	end
	local si = self.proxyToSource[proxyIndex]
	return si and self.source:GetIconInfo(si) or nil
end

function IconBrowserPinnedModel:EnumerateIcons(options)
	if not self.proxyToSource then
		return self.source:EnumerateIcons(options);
	end

	local pinnedCount = self.pinnedCount
	local proxyToSource = self.proxyToSource
	local pinnedSourceSet = self.pinnedSourceSet
	local source = self.source
	local phase = 1
	local pinnedIdx = 0
	local sourceIterator = nil
	local nonPinnedProxy = pinnedCount

	return function()
		if phase == 1 then
			pinnedIdx = pinnedIdx + 1;
			if pinnedIdx <= pinnedCount then
				return pinnedIdx, source:GetIconInfo(proxyToSource[pinnedIdx]);
			end
			phase = 2;
			sourceIterator = source:EnumerateIcons(options);
		end

		local si, info = sourceIterator()
		while si ~= nil and pinnedSourceSet[si] do
			si, info = sourceIterator();
		end
		if si ~= nil then
			nonPinnedProxy = nonPinnedProxy + 1;
			return nonPinnedProxy, info;
		end
	end
end


------------------------------------------------------------------------------------------------------

local IconBrowserFilterModel = CreateFromMixins(CallbackRegistryMixin)

function IconBrowserFilterModel:Init(source)
	self:GenerateCallbackEvents({"OnModelUpdated", "OnSearchStateChanged", "OnSearchProgressChanged"})
	self:OnLoad()
	self.source = source
	self.sourceIndices = {}
	self.searchQuery = ""
	self.searchCategories = {}
	
	self.source:RegisterCallback("OnModelUpdated", function() self:RebuildModel() end, self)
end

function IconBrowserFilterModel:IsApplyingAnyFilter()
	return self.searchQuery ~= "" or self:IsFilteringAnyCategory()
end

function IconBrowserFilterModel:GetIconCount()
	return self:IsApplyingAnyFilter() and #self.sourceIndices or self.source:GetIconCount()
end

function IconBrowserFilterModel:GetIconInfo(proxyIndex)
	local sourceIndex = self:IsApplyingAnyFilter() and self.sourceIndices[proxyIndex] or proxyIndex
	return self.source:GetIconInfo(sourceIndex)
end

function IconBrowserFilterModel:SetSearchQuery(query)
	query = string.lower(query)
	if self.searchQuery ~= query then
		self.searchQuery = query;
		self:RebuildModel();
	end
end

function IconBrowserFilterModel:ClearAllFilters()
	self.searchQuery = ""
	self.searchCategories = {}
	self:RebuildModel()
end

function IconBrowserFilterModel:IsFilteringAnyCategory()
	return next(self.searchCategories) ~= nil
end

function IconBrowserFilterModel:IsFilteringCategory(category)
	return self.searchCategories[category] == true
end

function IconBrowserFilterModel:ToggleCategory(category)
	if self.searchCategories[category] then
		self.searchCategories[category] = nil;
	else
		self.searchCategories[category] = true;
	end
	self:RebuildModel()
end

function IconBrowserFilterModel:RebuildModel()
	if self.searchTask then
		self.searchTask:Finish();
		self.searchTask = nil;
	end

	if not self:IsApplyingAnyFilter() then
		self:TriggerEvent("OnModelUpdated");
		return;
	end

	local query = self.searchQuery
	local activeCategories = {}
	
	for category, isActive in pairs(self.searchCategories) do
		if isActive then table.insert(activeCategories, category); end
	end
	
	local categoryPredicate = #activeCategories > 0 and LRPM12:GenerateIconCategoryPredicate(activeCategories) or nil

	local function DoesIconMatchFilters(_, iconInfo)
		if categoryPredicate and not categoryPredicate(iconInfo.index) then
			return false;
		end

		if query ~= "" then
			local iconName = iconInfo.name and string.lower(iconInfo.name) or ""
			if not string.find(iconName, query, 1, true) then
				return false;
			end
		end

		return true
	end

	self.searchTask = CreateAndInitFromMixin(IconBrowserSearchTask, DoesIconMatchFilters, self.source)
	self.searchTask:RegisterCallback("OnStateChanged", function(_, state)
		if state == "finished" then self.searchTask = nil; end
		self:TriggerEvent("OnSearchStateChanged", state)
	end, self)
	
	self.searchTask:RegisterCallback("OnProgressChanged", function(_, progress)
		self:TriggerEvent("OnSearchProgressChanged", progress)
	end, self)

	self.searchTask:RegisterCallback("OnResultsChanged", function(_, results)
		self.sourceIndices = results
		self:TriggerEvent("OnModelUpdated")
	end, self)

	self.searchTask:Start()
end


------------------------------------------------------------------------------------------------------

LRPMIB_IconBrowserButtonMixin = {}

function LRPMIB_IconBrowserButtonMixin:OnLoad()
	self:RegisterForClicks("LeftButtonUp")
end

function LRPMIB_IconBrowserButtonMixin:Init(iconInfo)
	self.Icon:SetTexture(iconInfo and iconInfo.file or 134400)
	local isSelected = self.browser and (self.browser.selectedFile == iconInfo.file)
	self.SelectedTexture:SetShown(isSelected and true or false)
end

function LRPMIB_IconBrowserButtonMixin:OnClick()
	local iconInfo = self:GetElementData()
	if not iconInfo then return; end

	local browser = self.browser
	if browser and browser.OnIconSelected then
		browser:OnIconSelected(iconInfo);
	end
end

function LRPMIB_IconBrowserButtonMixin:OnEnter()
	local iconInfo = self:GetElementData()
	if not iconInfo then return; end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(iconInfo.name or L["UnknownIcon"], 1, 1, 1)
	GameTooltip:AddLine(string.format(L["FileID"], iconInfo.file), 0.44, 0.83, 1)
	GameTooltip:Show()
end

function LRPMIB_IconBrowserButtonMixin:OnLeave()
	GameTooltip:Hide()
end

LRPMIB_IconBrowserMixin = {}

function LRPMIB_IconBrowserMixin:OnLoad()
	self.baseModel = CreateAndInitFromMixin(IconBrowserModel)
	self.pinnedModel = CreateAndInitFromMixin(IconBrowserPinnedModel, self.baseModel)
	self.selectionModel = CreateAndInitFromMixin(IconBrowserSelectionModel, self.pinnedModel)
	self.filterModel = CreateAndInitFromMixin(IconBrowserFilterModel, self.selectionModel)
	self.selectedFile = nil

	local GRID_STRIDE = 9
	local GRID_PADDING = 4

	local initialStride = self.strideOverride or GRID_STRIDE

	self.Content.ScrollView = CreateScrollBoxListGridView(initialStride, GRID_PADDING, GRID_PADDING, GRID_PADDING, GRID_PADDING)
	self.Content.ScrollView:SetElementInitializer("LRPMIB_IconBrowserButtonTemplate", function(button, iconInfo)
		button.browser = self;
		button:Init(iconInfo);
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(self.Content.ScrollBox, self.Content.ScrollBar, self.Content.ScrollView)

	local scrollBoxAnchorsWithBar = {
		AnchorUtil.CreateAnchor("TOPLEFT", self.Content, "TOPLEFT", 0, 0),
		AnchorUtil.CreateAnchor("BOTTOMRIGHT", self.Content.ScrollBar, "BOTTOMLEFT", -4, 0),
	};
	local scrollBoxAnchorsWithoutBar = {
		AnchorUtil.CreateAnchor("TOPLEFT", self.Content, "TOPLEFT", 0, 0),
		AnchorUtil.CreateAnchor("BOTTOMRIGHT", self.Content, "BOTTOMRIGHT", 0, 0),
	};
	ScrollUtil.AddManagedScrollBarVisibilityBehavior(self.Content.ScrollBox, self.Content.ScrollBar, scrollBoxAnchorsWithBar, scrollBoxAnchorsWithoutBar)

	local provider = CreateFromMixins(CallbackRegistryMixin)
	provider:GenerateCallbackEvents({"OnSizeChanged"})
	provider:OnLoad()

	function provider:Enumerate(i, j)
		i = i and (i - 1) or 0
		j = j or self.model:GetIconCount()
		return function(_, k)
			k = k + 1;
			if k <= j then return k, self.model:GetIconInfo(k); end
		end, nil, i
	end
	function provider:Find(i) return self.model:GetIconInfo(i) end
	function provider:GetSize() return self.model:GetIconCount() end
	function provider:IsVirtual() return true end

	provider.model = self.filterModel
	self.filterModel:RegisterCallback("OnModelUpdated", function() provider:TriggerEvent("OnSizeChanged") end)
	self.Content.ScrollBox:SetDataProvider(provider)
	self.provider = provider

	self.Content.ScrollBox:HookScript("OnSizeChanged", function(scrollBox)
		local newStride = self.strideOverride or GRID_STRIDE;
		if self.Content.ScrollView.stride ~= newStride then
			self.Content.ScrollView.stride = newStride;
			if self.provider then
				self.provider:TriggerEvent("OnSizeChanged");
			end
		end
	end)

	local timer
	self.SearchBox:HookScript("OnTextChanged", function(box)
		if timer then timer:Cancel(); end
		timer = C_Timer.NewTimer(0.25, function() self.filterModel:SetSearchQuery(box:GetText()) end);
	end)

	self.filterModel:RegisterCallback("OnSearchStateChanged", function(_, state)
		self.Content.ProgressOverlay:SetShown(state == "running");
	end)
	self.filterModel:RegisterCallback("OnSearchProgressChanged", function(_, progress)
		self.Content.ProgressOverlay.ProgressBar:SetSmoothedValue(progress.searched / progress.total);
	end)

	self.FilterDropdown:SetIsDefaultCallback(function()
		return not self.filterModel:IsApplyingAnyFilter();
	end)
	self.FilterDropdown:SetDefaultCallback(function()
		self:OnFilterDropdownResetClicked();
	end)
	self.FilterDropdown:SetupMenu(function(dropdown, rootDescription)
		self:SetupFilterDropdown(rootDescription);
	end)

	self:RegisterEvent("UPDATE_MACROS")
end

function LRPMIB_IconBrowserMixin:OnEvent(event, ...)
	if event == "UPDATE_MACROS" and self:IsVisible() then
		RunNextFrame(function()
			self:UpdateSelection();
		end)
	end
end

function LRPMIB_IconBrowserMixin:UpdateSelection()
	local popup = self:GetParent():GetParent()
	if popup and popup.BorderBox and popup.BorderBox.SelectedIconArea then
		local currentIcon = popup.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture()
		if currentIcon then
			self.selectedFile = currentIcon;
			self.selectionModel:SetSelectedFileID(currentIcon);
			
			if self.provider then
				self.provider:TriggerEvent("OnSizeChanged");
			end
		end
	end
end

function LRPMIB_IconBrowserMixin:SetupFilterDropdown(rootDescription)
	local constants = IconBrowserConstants

	local function IsSelected(category) return self.filterModel.searchCategories[category] end
	local function ToggleCategory(category) self.filterModel:ToggleCategory(category) end
	local function CreateCategoryCheckbox(parent, name, category)
		parent:CreateCheckbox(name, function() return IsSelected(category) end, function() ToggleCategory(category) end);
	end

	if constants then
		local function BuildSubMenu(parent, title, categoryTable)
			if not categoryTable then return end
			local menu = parent:CreateButton(title)
			for _, catInfo in ipairs(categoryTable) do
				local name = catInfo.name
				if catInfo.color then
					name = catInfo.color:WrapTextInColorCode(name);
				end
				CreateCategoryCheckbox(menu, name, catInfo.category);
			end
			return menu;
		end

		CreateCategoryCheckbox(rootDescription, L["ICON_CATEGORY_SPELLSABILITIES"], LRPM12.IconCategory.Ability)
		CreateCategoryCheckbox(rootDescription, L["ICON_CATEGORY_ACHIEVEMENTS"], LRPM12.IconCategory.Achievement)
		CreateCategoryCheckbox(rootDescription, L["ICON_CATEGORY_HOUSING"], LRPM12.IconCategory.Housing)
		rootDescription:CreateDivider()

		BuildSubMenu(rootDescription, L["ICON_CATEGORY_CLASSES"], constants.ClassCategories)
		BuildSubMenu(rootDescription, L["ICON_CATEGORY_CULTURE"], constants.CultureCategories)

		do
			local menu = rootDescription:CreateButton(L["ICON_CATEGORY_WEAPON"]);
			CreateCategoryCheckbox(menu, L["ICON_CATEGORY_ALLWEAPONS"], LRPM12.IconCategory.Weapon);
			menu:CreateDivider();
			menu:CreateTitle(L["ICON_CATEGORY_MELEEWEAPONS"]);
			for _, catInfo in ipairs(constants.MeleeWeaponCategories) do
				CreateCategoryCheckbox(menu, catInfo.name, catInfo.category);
			end
			menu:CreateDivider();
			menu:CreateTitle(L["ICON_CATEGORY_RANGEDWEAPONS"]);
			for _, catInfo in ipairs(constants.RangedWeaponCategories) do
				CreateCategoryCheckbox(menu, catInfo.name, catInfo.category);
			end
		end

		do
			local menu = rootDescription:CreateButton(L["ICON_CATEGORY_ARMOR"]);
			for _, catInfo in ipairs(constants.ArmorTypeCategories) do
				CreateCategoryCheckbox(menu, catInfo.name, catInfo.category);
			end
			menu:CreateDivider();
			menu:CreateTitle(L["ICON_CATEGORY_INVENTORYSLOTS"]);
			for _, catInfo in ipairs(constants.InventorySlotCategories) do
				CreateCategoryCheckbox(menu, catInfo.name, catInfo.category);
			end
		end

		BuildSubMenu(rootDescription, L["ICON_CATEGORY_MAGIC"], constants.MagicCategories)
		BuildSubMenu(rootDescription, L["ICON_CATEGORY_FACTIONS"], constants.FactionCategories)

		do
			local menu = rootDescription:CreateButton(L["ICON_CATEGORY_PROFESSION"]);
			CreateCategoryCheckbox(menu, L["ICON_CATEGORY_ALLPROFESSIONS"], LRPM12.IconCategory.Professions);
			menu:CreateDivider();
			for _, catInfo in ipairs(constants.ProfessionCategories) do
				CreateCategoryCheckbox(menu, catInfo.name, catInfo.category);
			end
		end

		do
			local menu = rootDescription:CreateButton(L["ICON_CATEGORY_ITEMS"]);
			CreateCategoryCheckbox(menu, L["ICON_CATEGORY_ALLITEMS"], LRPM12.IconCategory.Item);
			menu:CreateDivider();
			for _, catInfo in ipairs(constants.ItemCategories) do
				CreateCategoryCheckbox(menu, catInfo.name, catInfo.category);
			end
		end
	else
		CreateCategoryCheckbox(rootDescription, L["ICON_CATEGORY_SPELLSABILITIES"], LRPM12.IconCategory.Ability);
		CreateCategoryCheckbox(rootDescription, L["ICON_CATEGORY_ITEMS"], LRPM12.IconCategory.Item);
		CreateCategoryCheckbox(rootDescription, L["ICON_CATEGORY_WEAPON"], LRPM12.IconCategory.Weapon);
		CreateCategoryCheckbox(rootDescription, L["ICON_CATEGORY_ARMOR"], LRPM12.IconCategory.ArmorType);
		CreateCategoryCheckbox(rootDescription, L["ICON_CATEGORY_PROFESSION"], LRPM12.IconCategory.Professions);
		CreateCategoryCheckbox(rootDescription, L["ICON_CATEGORY_ACHIEVEMENTS"], LRPM12.IconCategory.Achievement);
	end
end

function LRPMIB_IconBrowserMixin:SetPinnedFileIDs(fileIDs)
	self.pinnedModel:SetPinnedFileIDs(fileIDs);
end

function LRPMIB_IconBrowserMixin:OnShow()
	self.SearchBox:SetFocus()
	
	RunNextFrame(function()
		self:UpdateSelection();
	end)
end

function LRPMIB_IconBrowserMixin:OnFilterDropdownResetClicked()
	self.filterModel:ClearAllFilters()
	self.SearchBox:SetText("")
end

function LRPMIB_IconBrowserMixin:OnIconSelected(iconInfo)
	if not iconInfo or not iconInfo.file then return end
	
	-- if custom callback is defined from addons to use
	if self.customSelectCallback then
		self.customSelectCallback(iconInfo.file, iconInfo)
	end

	local popup = self:GetParent():GetParent()

	if popup and popup.BorderBox then
		popup.BorderBox.SelectedIconArea.SelectedIconButton:SetIconTexture(iconInfo.file);

		popup.selectedIconTexture = iconInfo.file;
		popup.selectedIconIndex = nil;

		if popup.SetSelectedIconText then
			popup:SetSelectedIconText();
		end

		popup.BorderBox.OkayButton:Enable();
	end

	self.selectedFile = iconInfo.file
	self.provider:TriggerEvent("OnSizeChanged")
end


------------------------------------------------------------------------------------------------------

local events = {
	"WORLD_CURSOR_TOOLTIP_UPDATE",
	"CURSOR_CHANGED",
	"ACTIONBAR_UPDATE_COOLDOWN",
	"GLOBAL_MOUSE_DOWN",
	"GLOBAL_MOUSE_UP",
};

--[[
	it's not pretty, but it works for this use case
	i'd like to replace this with something a bit nicer
	
	i actually tried to OnUpdate and hide it while the browser was shown
	but it still resulted in "flickering" when the game set it shown
	so that's why i set the alpha to 0
--]]
local LRPMIB_InjectedPopups = {};

local function HideTheseDangFrames()
	for _, popup in ipairs(LRPMIB_InjectedPopups) do
		if popup.IconSelector then
			popup.IconSelector:Hide();
			popup.IconSelector:SetAlpha(0);
		end
		if popup.BorderBox and popup.BorderBox.IconTypeDropdown then
			popup.BorderBox.IconTypeDropdown:Hide();
			popup.BorderBox.IconTypeDropdown:SetAlpha(0);
		end
	end
end

local function InjectBrowser(popup, browserName)
	if not popup or popup.LRPMIB_Browser then return end

	local browser = CreateFrame("Frame", browserName, popup.BorderBox, "LRPMIB_IconBrowserFrameTemplate")
	popup.LRPMIB_Browser = browser
	
	local topAnchorFrame = popup.BorderBox.IconSelectorEditBox
	local yOffset = -10
	local xOffset = -5

	-- bank frame is a little different because of extra settings
	if popup.DepositSettingsMenu then
		topAnchorFrame = popup.DepositSettingsMenu;
		xOffset = 7.5;
		yOffset = -5;
	end

	browser:SetPoint("TOPLEFT", topAnchorFrame, "BOTTOMLEFT", xOffset, yOffset)
	browser:SetPoint("BOTTOMRIGHT", popup.BorderBox, "BOTTOMRIGHT", -5, 40)
	
	popup:HookScript("OnShow", function()
		HideTheseDangFrames();
		browser:Show();
	end)

	-- the will be overlapped by the search bar othewise
	if popup.BorderBox.IconSelectionText then
		local point, relativeTo, relativePoint, x, y = popup.BorderBox.IconSelectionText:GetPoint(1)
		if point then
			popup.BorderBox.IconSelectionText:ClearAllPoints();
			popup.BorderBox.IconSelectionText:SetPoint(point, relativeTo, relativePoint, x, (y or 0) - 10);
		end
	end

	table.insert(LRPMIB_InjectedPopups, popup);
end

for k, v in pairs(events) do
	EventRegistry:RegisterFrameEventAndCallback(v, function() RunNextFrame(HideTheseDangFrames) end)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_MacroUI", function()
	InjectBrowser(MacroPopupFrame, "LRPMIB_MacroIconBrowser");
end)

EventUtil.ContinueOnAddOnLoaded("Blizzard_GuildBankUI", function()
	if GuildBankPopupFrame then
		InjectBrowser(GuildBankPopupFrame, "LRPMIB_GuildBankIconBrowser");
	end
end)

EventUtil.ContinueOnAddOnLoaded("Blizzard_Transmog", function()
	local popup = (TransmogFrame and TransmogFrame.OutfitPopup) or WardrobeOutfitEditFrame
	if not popup then return; end

	local browserName = "LRPMIB_TransmogIconBrowser"
	InjectBrowser(popup, browserName)

	local browser = popup.LRPMIB_Browser
	if not browser then return; end

	local function RefreshOutfitPins()
		local pinnedFileIDs = {};
		if TransmogFrame and TransmogFrame.GetViewedOutfitIcons then
			local icons = TransmogFrame:GetViewedOutfitIcons();
			if icons then
				for _, fileID in ipairs(icons) do
					if fileID and fileID ~= 0 then
						table.insert(pinnedFileIDs, fileID);
					end
				end
			end
		end
		browser:SetPinnedFileIDs(pinnedFileIDs);
	end

	popup:HookScript("OnShow", RefreshOutfitPins);
end)

local function InjectBaseFrames()
	if GearManagerPopupFrame then
		InjectBrowser(GearManagerPopupFrame, "LRPMIB_GearManagerIconBrowser");
	end
	if BankFrame and BankFrame.BankPanel and BankFrame.BankPanel.TabSettingsMenu then
		InjectBrowser(BankFrame.BankPanel.TabSettingsMenu, "LRPMIB_BankTabIconBrowser");
	end
end

InjectBaseFrames()
local baseUILoader = CreateFrame("Frame")
baseUILoader:RegisterEvent("PLAYER_LOGIN")
baseUILoader:SetScript("OnEvent", function()
	InjectBaseFrames()
end)

EventUtil.ContinueOnAddOnLoaded("Baganator", function()
	Baganator.API.Skins.RegisterListener(function(details)
		if details.regionType == "ButtonFrame" and details.tags and tIndexOf(details.tags, "bank") ~= nil then
			if details.region.Character and details.region.Character.TabSettingsMenu then
				InjectBrowser(details.region.Character.TabSettingsMenu, nil);
			end
			if details.region.Warband and details.region.Warband.TabSettingsMenu then
				InjectBrowser(details.region.Warband.TabSettingsMenu, nil);
			end
		end
	end)
end)

EventUtil.ContinueOnAddOnLoaded("MacroToolkit", function()
	local MT = _G.MacroToolkit
	if not MT then return end
	
	local function InjectMTBrowser()
		local popup = _G.MacroToolkitPopup;
		if not popup or popup.LRPMIB_Browser then return; end
		
		local origGetIcon = MT.GetSpellorMacroIconInfo;
		MT.GetSpellorMacroIconInfo = function(self, index)
			local texture = origGetIcon(self, index);
			if not texture and popup.selectedIcon == index then
				return index;
			end
			return texture;
		end

		popup:HookScript("OnShow", function()
			if _G.MacroToolkitPopupGoLarge then
				_G.MacroToolkitPopupGoLarge:Hide();
				_G.MacroToolkitPopupGoLarge:SetAlpha(0);
			end
			if _G.MacroToolkitPopupIcons then
				_G.MacroToolkitPopupIcons:Hide();
				_G.MacroToolkitPopupIcons:SetAlpha(0);
			end
			if _G.MacroToolkitSearchBox then
				_G.MacroToolkitSearchBox:Hide();
				_G.MacroToolkitSearchBox:SetAlpha(0);
			end
			if _G.MacroToolkitSpellCheck then
				_G.MacroToolkitSpellCheck:Hide();
				_G.MacroToolkitSpellCheck:SetAlpha(0);
			end
			MT.golarge();

			if popup.LRPMIB_Browser then
				popup.LRPMIB_Browser:Show();
				popup.LRPMIB_Browser:UpdateSelection();
			end

		end)
		
		local function OnIconSelected(fileID, iconInfo)
			_G.MacroToolkitSelMacroButton.Icon:SetTexture(fileID);
			popup.selectedIconTexture = fileID;
			popup.selectedIcon = fileID;
			MT:PopupOkayUpdate();
		end
		
		local browser = _G.LRPMediaIconBrowserAPI.CreateBrowser(popup, _G.MacroToolkitPopupEdit, 260, 270, OnIconSelected)
		browser.strideOverride = 8
		popup.LRPMIB_Browser = browser
		
		browser:ClearAllPoints()
		browser:SetPoint("TOPLEFT", _G.MacroToolkitPopupEdit, "BOTTOMLEFT", -15, -35)
		browser:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", 0, 45)

		browser.UpdateSelection = function(self)
			if popup.selectedIconTexture then
				self.selectedFile = popup.selectedIconTexture;
				self.selectionModel:SetSelectedFileID(popup.selectedIconTexture);
			end
		end
	end
	
	if _G.MacroToolkitPopup then
		InjectMTBrowser();
	else
		hooksecurefunc(MT, "CreateMTPopup", InjectMTBrowser);
	end
end)


-- some Global API stuff for other people to use the browser for their own addons
------------------------------------------------------------------------------------------------------

_G.LRPMediaIconBrowserAPI = {}

--[[
	creates and attaches the custom icon browser to a 3rd party addon's frame

	parentFrame - frame that will own the browser
	anchorFrame - frame the browser should anchor to (e.g., an editbox)
	width - the width of the browser window
	height - the height of the browser window
	onSelectCallback - fired when the clicking an icon, passes (fileID, iconInfo)
	browser.strideOverride - change the grid row icon count, default 9 (it's kind of the intended size)
--]]
function _G.LRPMediaIconBrowserAPI.CreateBrowser(parentFrame, anchorFrame, width, height, onSelectCallback)
	if not parentFrame then return nil end
	
	-- generate a unique name
	local browser = CreateFrame("Frame", nil, parentFrame, "LRPMIB_IconBrowserFrameTemplate")

	browser:SetSize(width or 250, height or 300)
	
	if anchorFrame then
		browser:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -10);
	else
		browser:SetPoint("CENTER", parentFrame, "CENTER");
	end
	
	-- attach a callback for OnIconSelected
	browser.customSelectCallback = onSelectCallback

	browser:Hide()
	
	return browser
end

--[[
-- complete example:

local MyCustomFrame = CreateFrame("Frame", "MyCustomIconBrowserTestFrame", UIParent, "BasicFrameTemplateWithInset")
MyCustomFrame:SetSize(500, 480)
MyCustomFrame:SetPoint("CENTER")
MyCustomFrame:Hide()

MyCustomFrame.TitleText:SetText("Icon Browser API Test")

MyCustomFrame:SetMovable(true)
MyCustomFrame:EnableMouse(true)
MyCustomFrame:RegisterForDrag("LeftButton")
MyCustomFrame:SetScript("OnDragStart", MyCustomFrame.StartMoving)
MyCustomFrame:SetScript("OnDragStop", MyCustomFrame.StopMovingOrSizing)

local PreviewIcon = MyCustomFrame:CreateTexture(nil, "ARTWORK")
PreviewIcon:SetSize(64, 64)
PreviewIcon:SetPoint("TOP", MyCustomFrame, "TOP", 0, -40)
PreviewIcon:SetTexture(134400)

MyCustomFrame:SetScript("OnShow", function(self)
	if not self.iconBrowser and _G.LRPMediaIconBrowserAPI then
		
		local function OnIconSelected(fileID, iconInfo)
			PreviewIcon:SetTexture(fileID);
			DevTools_Dump(iconInfo);
		end

		self.iconBrowser = _G.LRPMediaIconBrowserAPI.CreateBrowser(self, PreviewIcon, 480, 320, OnIconSelected)
		
		self.iconBrowser:ClearAllPoints()
		self.iconBrowser:SetPoint("TOP", PreviewIcon, "BOTTOM", 0, -20)
		self.iconBrowser:SetPoint("BOTTOM", self, "BOTTOM", 0, 10)
		
		self.iconBrowser:Show()
		
	elseif not _G.LRPMediaIconBrowserAPI then
		print("LRPMediaIconBrowserAPI is not loaded! Make sure the addon is enabled.");
	end
end)

SLASH_MYICONBROWSER1 = "/iconbrowser"

SlashCmdList["MYICONBROWSER"] = function(msg)
	if MyCustomFrame:IsShown() then
		MyCustomFrame:Hide();
	else
		MyCustomFrame:Show();
	end
end

]]