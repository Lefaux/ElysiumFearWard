local _, addon = ...

local c = addon.constants
local state = addon.state

function addon.SelectFont(fontKey)
    ElysiumFearWardDB.settings.fontKey = fontKey
    addon.RefreshRows()
    if state.settingsFrame and state.settingsFrame:IsShown() then
        addon.RefreshFontRows()
    end
end

local function ensureFontRow(index)
    local row = state.fontRows[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, state.fontScrollChild)
    row:SetSize(260, 18)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetJustifyH("LEFT")
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.selected:SetVertexColor(1, 0.82, 0.2, 0.16)
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local highlight = row:GetHighlightTexture()
    if highlight then
        highlight:SetVertexColor(1, 1, 1, 0.08)
    end
    row:SetScript("OnClick", function(self)
        addon.SelectFont(self.fontKey)
    end)
    state.fontRows[index] = row
    return row
end

function addon.RefreshFontRows()
    if not state.fontScrollChild then
        return
    end
    local fonts = addon.GetAvailableFonts()
    local selectedKey = ElysiumFearWardDB.settings.fontKey
    for index, entry in ipairs(fonts) do
        local row = ensureFontRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", state.fontScrollChild, "TOPLEFT", 0, -(index - 1) * 18)
        row.fontKey = entry.key
        row.text:SetText(entry.label)
        row.text:SetFont(entry.path or c.DEFAULT_FONT_PATH, 12, "")
        if selectedKey == entry.key then
            row.selected:Show()
            row.text:SetTextColor(1, 0.82, 0.2, 1)
        else
            row.selected:Hide()
            row.text:SetTextColor(0.95, 0.95, 0.95, 1)
        end
        row:Show()
    end
    for index = #fonts + 1, #state.fontRows do
        state.fontRows[index]:Hide()
    end
    state.fontScrollChild:SetHeight(math.max(1, #fonts * 18))
    state.fontScrollFrame:SetVerticalScroll(0)
    if state.fontScrollFrame.UpdateScrollChildRect then
        state.fontScrollFrame:UpdateScrollChildRect()
    end
end

function addon.OpenSettingsFrame()
    if state.settingsFrame then
        state.settingsFrame:Show()
        state.settingsFrame:Raise()
    end
end

function addon.EnsureSettingsFrame()
    if state.settingsFrame then
        return state.settingsFrame
    end

    local frame = CreateFrame("Frame", addon.name .. "SettingsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(390, 600)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        edgeSize = 14,
    })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.96)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("Elysium Fear Ward Settings")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local groupsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    groupsLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    groupsLabel:SetText("Visible groups")

    local previousAnchor = groupsLabel
    for _, key in ipairs(addon.ROLE_ORDER) do
        local roleKey = key
        local checkbox = CreateFrame("CheckButton", addon.name .. roleKey .. "Checkbox", frame, "UICheckButtonTemplate")
        checkbox:SetSize(22, 22)
        checkbox:SetPoint("TOPLEFT", previousAnchor, "BOTTOMLEFT", -2, -8)
        checkbox:SetScript("OnClick", function(self)
            if InCombatLockdown() then
                self:SetChecked(ElysiumFearWardDB.settings.groups[roleKey] ~= false)
                return
            end
            local enabled = self:GetChecked() and true or false
            ElysiumFearWardDB.settings.groups[roleKey] = enabled
            if state.filterButtons[roleKey] then
                state.filterButtons[roleKey]:SetChecked(enabled)
                state.filterButtons[roleKey]:SetAlpha(enabled and 1 or 0.35)
            end
            addon.RefreshRows()
        end)
        checkbox:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Lists cannot update during combat", 1, 0.82, 0)
            GameTooltip:Show()
        end)
        checkbox:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        label:SetText(addon.ROLE_LABELS[roleKey])
        state.settingsRows[roleKey] = checkbox
        previousAnchor = checkbox
    end

    local sizeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", previousAnchor, "BOTTOMLEFT", 2, -18)
    sizeLabel:SetText("Font size")

    local sizeSlider = CreateFrame("Slider", addon.name .. "FontSizeSlider", frame, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", -4, -14)
    sizeSlider:SetWidth(220)
    sizeSlider:SetMinMaxValues(c.MIN_FONT_SIZE, c.MAX_FONT_SIZE)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    _G[sizeSlider:GetName() .. "Low"]:SetText(tostring(c.MIN_FONT_SIZE))
    _G[sizeSlider:GetName() .. "High"]:SetText(tostring(c.MAX_FONT_SIZE))
    _G[sizeSlider:GetName() .. "Text"]:SetText("Font size")
    sizeSlider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if ElysiumFearWardDB.settings.fontSize ~= value then
            ElysiumFearWardDB.settings.fontSize = value
            addon.RefreshRows()
        end
    end)
    state.fontSizeSlider = sizeSlider

    local realmCheckbox = CreateFrame("CheckButton", addon.name .. "ShowPlayerRealmCheckbox", frame, "UICheckButtonTemplate")
    realmCheckbox:SetSize(22, 22)
    realmCheckbox:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -18)
    realmCheckbox:SetScript("OnClick", function(self)
        ElysiumFearWardDB.settings.showPlayerRealm = self:GetChecked() and true or false
        addon.RefreshRows()
    end)
    local realmLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    realmLabel:SetPoint("LEFT", realmCheckbox, "RIGHT", 4, 0)
    realmLabel:SetText("Show Player realm")
    state.showRealmCheckbox = realmCheckbox

    local nameLengthLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLengthLabel:SetPoint("TOPLEFT", realmCheckbox, "BOTTOMLEFT", 2, -16)
    nameLengthLabel:SetText("Character name length")

    local nameSlider = CreateFrame("Slider", addon.name .. "NameLengthSlider", frame, "OptionsSliderTemplate")
    nameSlider:SetPoint("TOPLEFT", nameLengthLabel, "BOTTOMLEFT", -4, -14)
    nameSlider:SetWidth(220)
    nameSlider:SetMinMaxValues(c.MIN_NAME_LENGTH, c.MAX_NAME_LENGTH)
    nameSlider:SetValueStep(1)
    nameSlider:SetObeyStepOnDrag(true)
    _G[nameSlider:GetName() .. "Low"]:SetText(tostring(c.MIN_NAME_LENGTH))
    _G[nameSlider:GetName() .. "High"]:SetText(tostring(c.MAX_NAME_LENGTH))
    _G[nameSlider:GetName() .. "Text"]:SetText(
        string.format("Shorten character name to %d letters", ElysiumFearWardDB.settings.nameLength)
    )
    nameSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        _G[self:GetName() .. "Text"]:SetText(string.format("Shorten character name to %d letters", value))
        if ElysiumFearWardDB.settings.nameLength ~= value then
            ElysiumFearWardDB.settings.nameLength = value
            addon.RefreshRows()
        end
    end)
    state.nameLengthSlider = nameSlider

    local fontLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", nameSlider, "BOTTOMLEFT", 4, -20)
    fontLabel:SetText("Font")

    local fontScrollFrame = CreateFrame("ScrollFrame", addon.name .. "FontScrollFrame", frame, "UIPanelScrollFrameTemplate")
    fontScrollFrame:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -8)
    fontScrollFrame:SetSize(300, 120)
    fontScrollFrame:EnableMouseWheel(true)
    fontScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local scrollBar = self.ScrollBar
        if scrollBar then
            local minValue, maxValue = scrollBar:GetMinMaxValues()
            scrollBar:SetValue(math.max(minValue, math.min(maxValue, scrollBar:GetValue() - delta * 18)))
        end
    end)
    local fontScrollChild = CreateFrame("Frame", nil, fontScrollFrame)
    fontScrollChild:SetPoint("TOPLEFT", fontScrollFrame, "TOPLEFT", 0, 0)
    fontScrollChild:SetSize(280, 1)
    fontScrollFrame:SetScrollChild(fontScrollChild)
    state.fontScrollFrame, state.fontScrollChild = fontScrollFrame, fontScrollChild

    frame:SetScript("OnShow", function()
        for key, checkbox in pairs(state.settingsRows) do
            checkbox:SetChecked(ElysiumFearWardDB.settings.groups[key] ~= false)
        end
        sizeSlider:SetValue(ElysiumFearWardDB.settings.fontSize)
        realmCheckbox:SetChecked(ElysiumFearWardDB.settings.showPlayerRealm)
        nameSlider:SetValue(ElysiumFearWardDB.settings.nameLength)
        addon.RefreshFontRows()
    end)

    state.settingsFrame = frame
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(frame, "ElysiumFearWard")
        Settings.RegisterAddOnCategory(category)
        state.settingsCategory = category
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(frame)
    end
    return frame
end

function addon.OpenOptionsPanel()
    addon.EnsureSettingsFrame()
    if Settings and Settings.OpenToCategory and state.settingsCategory then
        Settings.OpenToCategory(state.settingsCategory.ID or state.settingsCategory.name)
    elseif InterfaceOptionsFrame_Show and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_Show()
        InterfaceOptionsFrame_OpenToCategory(state.settingsFrame)
    else
        addon.OpenSettingsFrame()
    end
end
