local _, addon = ...

local c = addon.constants
local state = addon.state

local function updateDisplayList()
    local display, count = {}, 0
    local settings = ElysiumFearWardDB.settings
    for _, key in ipairs(addon.ROLE_ORDER) do
        display[key] = {}
    end

    for _, guid in ipairs(state.rosterOrder) do
        local entry = state.roster[guid]
        if entry and entry.online and not entry.dead then
            local role = addon.ClassifyUnit(entry)
            if role and settings.groups[role] ~= false then
                display[role][#display[role] + 1] = entry
                if not entry.hasFearWard then
                    count = count + 1
                end
            end
        end
    end

    for _, key in ipairs(addon.ROLE_ORDER) do
        table.sort(display[key], addon.SortEntries)
    end
    state.displayList, state.displayCount = display, count
end

function addon.RefreshRows()
    if not state.frame then
        return
    end

    updateDisplayList()
    state.countText:SetText(string.format("%d players not fearwarded", state.displayCount or 0))
    addon.ApplyFont(state.titleText, 1)
    addon.ApplyFont(state.countText, 1)

    if InCombatLockdown() then
        state.pendingLayoutRefresh = true
        addon.UpdateCooldownBar()
        return
    end

    local y, headerIndex, rowIndex, visibleRows = 0, 1, 1, 0
    local contentWidth = math.max(1, state.scrollChild:GetWidth())
    for _, key in ipairs(addon.ROLE_ORDER) do
        local list = state.displayList[key]
        if list and #list > 0 then
            local headerRow = state.headerRows[headerIndex]
            if not headerRow then
                headerRow = CreateFrame("Frame", nil, state.scrollChild)
                headerRow.text = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                headerRow.text:SetPoint("TOPLEFT", 0, 0)
                state.headerRows[headerIndex] = headerRow
            end
            headerRow:ClearAllPoints()
            headerRow:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", 2, y)
            headerRow:SetSize(contentWidth - 4, c.HEADER_HEIGHT)
            headerRow.text:SetText(addon.ROLE_LABELS[key])
            addon.ApplyFont(headerRow.text, -1, HIGHLIGHT_FONT_COLOR)
            headerRow:Show()
            headerIndex, y, visibleRows = headerIndex + 1, y - c.HEADER_HEIGHT, visibleRows + 1

            for _, entry in ipairs(list) do
                local row = state.rows[rowIndex]
                if not row then
                    row = CreateFrame("Frame", nil, state.scrollChild)
                    row.clickTarget = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
                    row.clickTarget:SetAllPoints(row)
                    row.clickTarget:RegisterForClicks(
                        "LeftButtonUp",
                        "LeftButtonDown",
                        "RightButtonUp",
                        "RightButtonDown"
                    )
                    row.clickTarget:SetAttribute("useOnKeyDown", false)
                    row.clickTarget.ownerRow = row
                    row.clickTarget:SetScript("PostClick", function(self, mouseButton)
                        if mouseButton == "RightButton" then
                            addon.ShowRoleOverrideMenu(self.ownerRow)
                        end
                    end)
                    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.text:SetPoint("LEFT", 0, 0)
                    row.dot = row:CreateTexture(nil, "OVERLAY")
                    row.dot:SetSize(5, 5)
                    row.dot:SetPoint("LEFT", -8, 0)
                    row.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
                    row.dot:Hide()
                    local highlight = row.clickTarget:CreateTexture(nil, "HIGHLIGHT")
                    highlight:SetAllPoints(row.clickTarget)
                    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
                    highlight:SetVertexColor(1, 1, 1, 0.08)
                    state.rows[rowIndex] = row
                end

                local unit = addon.FindUnitByGuid(entry.guid)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", 10, y)
                row:SetSize(contentWidth - 12, c.ROW_HEIGHT)
                row.unit, row.guid = unit, entry.guid
                row.text:SetText(addon.GetPlayerDisplayName(entry))
                row.text:Show()
                addon.ApplyFont(row.text, 0)

                if unit and UnitExists(unit) then
                    addon.SetFearWardClickTarget(row.clickTarget, unit, not addon.IsUnitOutOfFearWardRange(unit))
                else
                    addon.SetFearWardClickTarget(row.clickTarget, nil, false)
                end

                row:Show()
                rowIndex, y, visibleRows = rowIndex + 1, y - c.ROW_HEIGHT, visibleRows + 1
            end
        end
    end

    for index = headerIndex, #state.headerRows do
        state.headerRows[index]:Hide()
    end
    for index = rowIndex, #state.rows do
        local row = state.rows[index]
        row.guid, row.unit = nil, nil
        row.text:Show()
        row:Hide()
    end

    state.visibleRows = visibleRows
    state.scrollChild:SetHeight(math.max(1, -y))
    if state.scrollFrame.UpdateScrollChildRect then
        state.scrollFrame:UpdateScrollChildRect()
    end
    addon.UpdateCooldownBar()
    addon.UpdateRangeIndicators()
end

function addon.ToggleMainFrame()
    if not state.frame then
        return
    end
    if state.frame:IsShown() then
        state.frame:Hide()
    else
        state.frame:Show()
        addon.RefreshRows()
    end
end

function addon.EnsureFrame()
    if state.frame then
        return state.frame
    end

    local saved = ElysiumFearWardDB.frame
    local frame = CreateFrame("Frame", addon.name .. "Frame", UIParent, "BackdropTemplate")
    frame:SetSize(saved.width or c.WINDOW_WIDTH, saved.height or c.WINDOW_HEIGHT)
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(c.MIN_WINDOW_WIDTH, c.MIN_WINDOW_HEIGHT, c.MAX_WINDOW_WIDTH, c.MAX_WINDOW_HEIGHT)
    else
        frame:SetMinResize(c.MIN_WINDOW_WIDTH, c.MIN_WINDOW_HEIGHT)
        frame:SetMaxResize(c.MAX_WINDOW_WIDTH, c.MAX_WINDOW_HEIGHT)
    end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        addon.SaveFramePosition(self)
    end)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", c.FRAME_PADDING, -c.FRAME_PADDING)
    title:SetText("Fear Ward")
    addon.ApplyFont(title, 1)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    countText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    countText:SetJustifyH("LEFT")
    countText:SetText("0 players not fearwarded")

    local scrollFrame = CreateFrame("ScrollFrame", addon.name .. "PlayerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", c.FRAME_PADDING, -c.TOP_CONTENT_OFFSET)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, c.FOOTER_HEIGHT + 4)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local scrollBar = self.ScrollBar
        if scrollBar then
            local minValue, maxValue = scrollBar:GetMinMaxValues()
            scrollBar:SetValue(math.max(minValue, math.min(maxValue, scrollBar:GetValue() - delta * c.ROW_HEIGHT * 3)))
        end
    end)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    scrollChild:SetSize(math.max(1, frame:GetWidth() - 36), 1)
    scrollFrame:SetScrollChild(scrollChild)

    local cooldownBar = CreateFrame("StatusBar", nil, frame)
    cooldownBar:SetPoint(
        "BOTTOMLEFT",
        frame,
        "BOTTOMLEFT",
        c.FRAME_PADDING + (#addon.ROLE_ORDER * c.FILTER_ICON_SPACING) + 4,
        8
    )
    cooldownBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -c.FRAME_PADDING, 8)
    cooldownBar:SetHeight(12)
    cooldownBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    cooldownBar:SetStatusBarColor(0.85, 0.75, 0.2, 1)
    cooldownBar:SetMinMaxValues(0, 1)
    cooldownBar:SetValue(0)
    cooldownBar:Hide()

    local cooldownBackground = cooldownBar:CreateTexture(nil, "BACKGROUND")
    cooldownBackground:SetAllPoints()
    cooldownBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
    cooldownBackground:SetVertexColor(0.1, 0.1, 0.1, 0.9)

    local cooldownText = cooldownBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cooldownText:SetPoint("CENTER")
    cooldownText:SetText("")

    for index, key in ipairs(addon.ROLE_ORDER) do
        local roleKey = key
        local filter = CreateFrame("CheckButton", addon.name .. "Main" .. roleKey .. "Filter", frame)
        filter:SetSize(c.FILTER_ICON_SIZE, c.FILTER_ICON_SIZE)
        filter:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", c.FRAME_PADDING + (index - 1) * c.FILTER_ICON_SPACING, 5)
        filter:SetNormalTexture(addon.ROLE_ICONS[roleKey])
        filter:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        filter:SetCheckedTexture(addon.ROLE_ICONS[roleKey])
        filter:SetChecked(ElysiumFearWardDB.settings.groups[roleKey] ~= false)
        filter:SetAlpha(filter:GetChecked() and 1 or 0.35)
        filter:SetScript("OnClick", function(self)
            if InCombatLockdown() then
                self:SetChecked(ElysiumFearWardDB.settings.groups[roleKey] ~= false)
                self:SetAlpha(self:GetChecked() and 1 or 0.35)
                if UIErrorsFrame then
                    UIErrorsFrame:AddMessage("Lists cannot update during combat", 1, 0.2, 0.2)
                end
                return
            end
            local enabled = self:GetChecked() and true or false
            ElysiumFearWardDB.settings.groups[roleKey] = enabled
            self:SetAlpha(enabled and 1 or 0.35)
            if state.settingsRows[roleKey] then
                state.settingsRows[roleKey]:SetChecked(enabled)
            end
            addon.RefreshRows()
        end)
        filter:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(addon.ROLE_LABELS[roleKey])
            GameTooltip:AddLine("Lists cannot update during combat", 1, 0.82, 0)
            GameTooltip:Show()
        end)
        filter:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        state.filterButtons[roleKey] = filter
    end

    local resizeButton = CreateFrame("Button", nil, frame)
    resizeButton:SetSize(16, 16)
    resizeButton:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeButton:SetScript("OnMouseDown", function()
        if not InCombatLockdown() then
            frame:StartSizing("BOTTOMRIGHT")
        elseif UIErrorsFrame then
            UIErrorsFrame:AddMessage("Window size cannot change during combat", 1, 0.2, 0.2)
        end
    end)
    resizeButton:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        addon.SaveFrameSize(frame)
        addon.RefreshRows()
    end)

    frame:SetScript("OnSizeChanged", function(_, width)
        if state.scrollChild and not InCombatLockdown() then
            state.scrollChild:SetWidth(math.max(1, width - 36))
            addon.RefreshRows()
        elseif InCombatLockdown() then
            state.pendingLayoutRefresh = true
        end
    end)
    frame:SetScript("OnShow", addon.RefreshRows)

    state.frame, state.titleText, state.countText = frame, title, countText
    state.cooldownBar, state.cooldownText = cooldownBar, cooldownText
    state.scrollFrame, state.scrollChild = scrollFrame, scrollChild

    addon.EnsureMinimapButton()
    return frame
end
