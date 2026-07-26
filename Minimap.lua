local _, addon = ...

local state = addon.state

local function atan2Compat(y, x)
    return type(math.atan2) == "function" and math.atan2(y, x) or math.atan(y, x)
end

local function saveMinimapPosition(button)
    local mx, my = Minimap:GetCenter()
    local bx, by = button:GetCenter()
    if not mx or not my or not bx or not by then
        return
    end
    local scale = Minimap:GetEffectiveScale()
    ElysiumFearWardDB.minimap.position = math.deg(atan2Compat((by - my) * scale, (bx - mx) * scale)) % 360
    ElysiumFearWardDB.minimap.distance = 1
end

function addon.UpdateMinimapButtonPosition()
    if not state.minimapButton then
        return
    end
    local minimap = ElysiumFearWardDB.minimap
    local angle = math.rad(minimap.position or 225)
    local radius = (Minimap:GetWidth() / 2) + 5
    local distance = minimap.distance or 1
    state.minimapButton:ClearAllPoints()
    state.minimapButton:SetPoint(
        "CENTER",
        Minimap,
        "CENTER",
        math.cos(angle) * radius * distance,
        math.sin(angle) * radius * distance
    )
    if minimap.visible == false or not state.enabled then
        state.minimapButton:Hide()
    else
        state.minimapButton:Show()
    end
end

function addon.EnsureMinimapButton()
    if state.minimapButton then
        return state.minimapButton
    end

    local button = CreateFrame("Button", addon.name .. "MinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture("Interface\\Icons\\Spell_Holy_Excorcism")
    icon:SetPoint("TOPLEFT", 7, -6)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Elysium Fear Ward")
        GameTooltip:AddLine("Left-click: toggle window", 1, 1, 1)
        GameTooltip:AddLine("Right-click: open settings", 1, 1, 1)
        GameTooltip:AddLine("Shift-drag: move button", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            addon.OpenSettingsFrame()
        elseif not IsShiftKeyDown() then
            addon.ToggleMainFrame()
        end
    end)
    button:SetScript("OnDragStart", function(self)
        if not IsShiftKeyDown() then
            return
        end
        self:LockHighlight()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ElysiumFearWardDB.minimap.position = math.deg(atan2Compat(py / scale - my, px / scale - mx)) % 360
            addon.UpdateMinimapButtonPosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
        saveMinimapPosition(self)
        addon.UpdateMinimapButtonPosition()
    end)

    state.minimapButton = button
    addon.UpdateMinimapButtonPosition()
    return button
end
