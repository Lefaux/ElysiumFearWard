local addonName = ...

ElysiumFearWardDB = ElysiumFearWardDB or {}

local FEAR_WARD_NAME = GetSpellInfo(6346) or "Fear Ward"
local DEFAULT_FONT_PATH = "Fonts\\FRIZQT__.TTF"
local DEFAULT_FONT_KEY = "Friz Quadrata TT"
local DEFAULT_FONT_SIZE = 12
local MIN_FONT_SIZE = 8
local MAX_FONT_SIZE = 24
local DEFAULT_NAME_LENGTH = 12
local MIN_NAME_LENGTH = 3
local MAX_NAME_LENGTH = 12
local WINDOW_WIDTH = 250
local WINDOW_HEIGHT = 250
local MIN_WINDOW_WIDTH = 220
local MIN_WINDOW_HEIGHT = 150
local MAX_WINDOW_WIDTH = 600
local MAX_WINDOW_HEIGHT = 700
local ROW_HEIGHT = 15
local HEADER_HEIGHT = 14
local FRAME_PADDING = 8
local TOP_CONTENT_OFFSET = 54
local FOOTER_HEIGHT = 28
local FILTER_ICON_SIZE = 19
local FILTER_ICON_SPACING = 24
local RANGE_UPDATE_INTERVAL = 0.25
local COOLDOWN_UPDATE_INTERVAL = 0.1
local FEAR_WARD_DURATION = 180

local ROLE_ORDER = {
    "maintank",
    "melee",
    "warriors",
    "healers",
    "ranged",
}

local ROLE_LABELS = {
    maintank = "Maintanks",
    melee = "Melee",
    warriors = "Warriors",
    healers = "Healers",
    ranged = "Ranged",
}

local ROLE_ICONS = {
    maintank = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    melee = "Interface\\Icons\\Ability_MeleeDamage",
    warriors = "Interface\\Icons\\Ability_Racial_Avatar",
    healers = "Interface\\Icons\\Spell_Holy_Heal",
    ranged = "Interface\\Icons\\Spell_Fire_FireBolt02",
}

local CLASS_PRIORITY = {
    DRUID = 1,
    ROGUE = 2,
    WARRIOR = 3,
    PALADIN = 4,
    PRIEST = 5,
    HUNTER = 6,
    MAGE = 7,
    WARLOCK = 8,
}

local FALLBACK_FONTS = {
    { key = "Friz Quadrata TT", label = "Friz Quadrata TT", path = "Fonts\\FRIZQT__.TTF" },
    { key = "Arial Narrow", label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { key = "Morpheus", label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { key = "Skurri", label = "Skurri", path = "Fonts\\skurri.ttf" },
}

local state = {
    enabled = false,
    frame = nil,
    titleText = nil,
    countText = nil,
    rows = {},
    headerRows = {},
    settingsFrame = nil,
    settingsRows = {},
    fontRows = {},
    fontScrollFrame = nil,
    fontScrollChild = nil,
    fontSizeSlider = nil,
    showRealmCheckbox = nil,
    nameLengthSlider = nil,
    minimapButton = nil,
    settingsCategory = nil,
    cooldownBar = nil,
    cooldownText = nil,
    scrollFrame = nil,
    scrollChild = nil,
    filterButtons = {},
    roleMenuFrame = nil,
    roster = {},
    rosterOrder = {},
    missingGuids = {},
    displayList = {},
    rangeTicker = 0,
    cooldownTicker = 0,
    fearWardSpellSlot = nil,
    visibleRows = 0,
    pendingSecureRefresh = false,
    pendingLayoutRefresh = false,
}

local openSettingsFrame
local refreshFontRows
local findUnitByGuid
local showRoleOverrideMenu

local function isEligiblePlayer()
    local _, classToken = UnitClass("player")
    local _, raceToken = UnitRace("player")
    return classToken == "PRIEST" and raceToken == "Dwarf"
end

local function ensureDB()
    ElysiumFearWardDB.frame = ElysiumFearWardDB.frame or {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }
    ElysiumFearWardDB.minimap = ElysiumFearWardDB.minimap or {
        position = 225,
        distance = 1,
        visible = true,
    }
    ElysiumFearWardDB.settings = ElysiumFearWardDB.settings or {}
    ElysiumFearWardDB.roleOverrides = ElysiumFearWardDB.roleOverrides or {}

    local settings = ElysiumFearWardDB.settings
    settings.fontKey = settings.fontKey or DEFAULT_FONT_KEY
    settings.fontSize = tonumber(settings.fontSize) or DEFAULT_FONT_SIZE
    settings.fontSize = math.max(MIN_FONT_SIZE, math.min(MAX_FONT_SIZE, math.floor(settings.fontSize + 0.5)))
    if settings.showPlayerRealm == nil then
        settings.showPlayerRealm = true
    else
        settings.showPlayerRealm = not not settings.showPlayerRealm
    end
    settings.nameLength = tonumber(settings.nameLength) or DEFAULT_NAME_LENGTH
    settings.nameLength = math.max(MIN_NAME_LENGTH, math.min(MAX_NAME_LENGTH, math.floor(settings.nameLength + 0.5)))
    settings.groups = settings.groups or {}

    for _, key in ipairs(ROLE_ORDER) do
        if settings.groups[key] == nil then
            settings.groups[key] = true
        else
            settings.groups[key] = not not settings.groups[key]
        end
    end

    local savedFrame = ElysiumFearWardDB.frame
    savedFrame.width = math.max(MIN_WINDOW_WIDTH, math.min(MAX_WINDOW_WIDTH, tonumber(savedFrame.width) or WINDOW_WIDTH))
    savedFrame.height = math.max(MIN_WINDOW_HEIGHT, math.min(MAX_WINDOW_HEIGHT, tonumber(savedFrame.height) or WINDOW_HEIGHT))
end

local function getSharedMedia()
    if not LibStub then
        return nil
    end

    local ok, media = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok then
        return media
    end

    return nil
end

local function getAvailableFonts()
    local fonts = {}
    local seen = {}

    for _, entry in ipairs(FALLBACK_FONTS) do
        fonts[#fonts + 1] = entry
        seen[entry.key] = true
    end

    local media = getSharedMedia()
    if media and media.HashTable then
        local hash = media:HashTable("font") or {}
        for key, path in pairs(hash) do
            if not seen[key] then
                fonts[#fonts + 1] = {
                    key = key,
                    label = key,
                    path = path,
                }
                seen[key] = true
            end
        end
    end

    table.sort(fonts, function(a, b)
        return a.label < b.label
    end)

    return fonts
end

local function getFontPath(fontKey)
    local media = getSharedMedia()
    if media and media.IsValid and media:IsValid("font", fontKey) then
        local fetched = media:Fetch("font", fontKey, true)
        if fetched then
            return fetched
        end
    end

    for _, entry in ipairs(FALLBACK_FONTS) do
        if entry.key == fontKey then
            return entry.path
        end
    end

    return DEFAULT_FONT_PATH
end

local function applyFont(fontString, sizeAdjust, forceColor)
    if not fontString then
        return
    end

    local settings = ElysiumFearWardDB.settings
    local fontPath = getFontPath(settings.fontKey)
    local fontSize = settings.fontSize + (sizeAdjust or 0)
    fontString:SetFont(fontPath, fontSize, "")
    if forceColor then
        fontString:SetTextColor(forceColor.r, forceColor.g, forceColor.b, forceColor.a or 1)
    end
end

local function saveFramePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not point then
        return
    end

    local saved = ElysiumFearWardDB.frame
    saved.point = point
    saved.relativePoint = relativePoint
    saved.x = math.floor(x + 0.5)
    saved.y = math.floor(y + 0.5)
end

local function saveFrameSize(frame)
    local saved = ElysiumFearWardDB.frame
    saved.width = math.floor(frame:GetWidth() + 0.5)
    saved.height = math.floor(frame:GetHeight() + 0.5)
end

local function atan2Compat(y, x)
    if type(math.atan2) == "function" then
        return math.atan2(y, x)
    end

    return math.atan(y, x)
end

local function saveMinimapPosition(button)
    local mx, my = Minimap:GetCenter()
    local bx, by = button:GetCenter()
    if not mx or not my or not bx or not by then
        return
    end

    local scale = Minimap:GetEffectiveScale()
    local dx = (bx * scale) - (mx * scale)
    local dy = (by * scale) - (my * scale)

    ElysiumFearWardDB.minimap.position = math.deg(atan2Compat(dy, dx)) % 360
    ElysiumFearWardDB.minimap.distance = 1
end

local function updateMinimapButtonPosition()
    if not state.minimapButton then
        return
    end

    local minimap = ElysiumFearWardDB.minimap
    local angle = math.rad(minimap.position or 225)
    local distance = minimap.distance or 1
    local radius = (Minimap:GetWidth() / 2) + 5
    local x = math.cos(angle) * radius * distance
    local y = math.sin(angle) * radius * distance

    state.minimapButton:ClearAllPoints()
    state.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)

    if minimap.visible == false or not state.enabled then
        state.minimapButton:Hide()
    else
        state.minimapButton:Show()
    end
end

local function getPlayerNameParts(unit)
    local currentRealm = ""
    if GetNormalizedRealmName then
        currentRealm = GetNormalizedRealmName() or ""
    elseif GetRealmName then
        currentRealm = string.gsub(GetRealmName() or "", "%s+", "")
    end

    if UnitFullName then
        local name, realm = UnitFullName(unit)
        if name and name ~= "" then
            return name, (realm and realm ~= "") and realm or currentRealm
        end
    end

    local fullName = GetUnitName(unit, true) or UnitName(unit) or "?"
    local separator = string.find(fullName, "-", 1, true)
    if separator then
        return string.sub(fullName, 1, separator - 1), string.sub(fullName, separator + 1)
    end

    return fullName, currentRealm
end

local function shortenCharacterName(name, maxLetters)
    name = name or "?"
    if utf8sub then
        return utf8sub(name, 1, maxLetters)
    end
    return string.sub(name, 1, maxLetters)
end

local function getPlayerDisplayName(entry)
    if not entry then
        return "?"
    end

    local settings = ElysiumFearWardDB.settings
    local name = shortenCharacterName(entry.name, settings.nameLength or DEFAULT_NAME_LENGTH)
    if settings.showPlayerRealm and entry.realm and entry.realm ~= "" then
        return name .. "-" .. entry.realm
    end

    return name
end

local function shouldSkipUnit(unit)
    return not UnitExists(unit)
        or UnitIsUnit(unit, "pet")
        or UnitIsDeadOrGhost(unit)
        or not UnitIsConnected(unit)
end

local function findFearWardSpellSlot()
    if not FEAR_WARD_NAME or not GetNumSpellTabs or not GetSpellTabInfo or not GetSpellBookItemName then
        return nil
    end

    local numTabs = GetNumSpellTabs() or 0
    for tabIndex = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tabIndex)
        offset = tonumber(offset) or 0
        numSpells = tonumber(numSpells) or 0

        for spellOffset = 1, numSpells do
            local slot = offset + spellOffset
            local spellName = GetSpellBookItemName(slot, BOOKTYPE_SPELL)
            if spellName == FEAR_WARD_NAME then
                return slot
            end
        end
    end

    return nil
end

local function getFearWardInfo(unit)
    local index = 1
    while true do
        local name, _, _, _, duration, expirationTime = UnitBuff(unit, index)
        if not name then
            return false, nil
        end
        if name == FEAR_WARD_NAME then
            duration = tonumber(duration) or 0
            expirationTime = tonumber(expirationTime) or 0
            if duration > 0 and expirationTime > 0 then
                return true, expirationTime
            end
            return true, nil
        end
        index = index + 1
    end
end

local function getAssignedGroupRole(unit)
    if not UnitGroupRolesAssigned then
        return "NONE"
    end

    local role = UnitGroupRolesAssigned(unit)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        return role
    end

    return "NONE"
end

local function classifyUnit(entry)
    if not entry then
        return nil
    end

    local roleOverride = ElysiumFearWardDB.roleOverrides and ElysiumFearWardDB.roleOverrides[entry.guid]
    if roleOverride and ROLE_LABELS[roleOverride] then
        return roleOverride
    end

    if entry.assignedRole == "TANK" or entry.isMaintank then
        return "maintank"
    end

    if entry.assignedRole == "HEALER" then
        return "healers"
    end

    if entry.classToken == "ROGUE" then
        return "melee"
    end

    if entry.classToken == "WARRIOR" then
        return "warriors"
    end

    return "ranged"
end

local function sortEntries(a, b)
    local classA = CLASS_PRIORITY[a.classToken] or 99
    local classB = CLASS_PRIORITY[b.classToken] or 99
    if classA ~= classB then
        return classA < classB
    end

    return (a.name or "") < (b.name or "")
end

local function isUnitOutOfFearWardRange(unit)
    if not unit or not UnitExists(unit) then
        return false
    end

    if not state.fearWardSpellSlot then
        state.fearWardSpellSlot = findFearWardSpellSlot()
    end

    if not state.fearWardSpellSlot then
        return false
    end

    local inRange = IsSpellInRange(state.fearWardSpellSlot, BOOKTYPE_SPELL, unit)
    if inRange == 0 then
        return true
    end

    if inRange == nil and CheckInteractDistance then
        local followRange = CheckInteractDistance(unit, 4)
        if followRange == false then
            return true
        end
    end

    return false
end

local function setFearWardClickTarget(button, unit, enabled)
    if not button then
        return
    end

    -- Macro text on secure buttons is no longer a reliable way for addons to
    -- cast spells. Use the secure spell action directly instead.
    button:SetAttribute("macrotext1", nil)
    if enabled and unit and UnitExists(unit) then
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", FEAR_WARD_NAME)
        button:SetAttribute("unit", unit)
        button:SetAttribute("checkselfcast", false)
    else
        button:SetAttribute("type1", nil)
        button:SetAttribute("spell1", nil)
        button:SetAttribute("unit", nil)
    end
end

local function getPlayerStatusColor(entry, isOutOfRange)
    if entry and entry.hasFearWard then
        local remaining = math.max(0, (entry.fearWardExpiresAt or 0) - GetTime())
        if remaining > 120 then
            return 0.15, 1, 0.15
        end
        return 1, 0.85, 0.1
    end

    if isOutOfRange then
        return 0.55, 0.55, 0.55
    end

    return 1, 0.15, 0.15
end

local function updateRangeIndicators()
    for _, row in ipairs(state.rows) do
        if row and row.dot and row:IsShown() and row.unit and UnitExists(row.unit) then
            local entry = row.guid and state.roster[row.guid]
            local isOutOfRange = isUnitOutOfFearWardRange(row.unit)
            local r, g, b = getPlayerStatusColor(entry, isOutOfRange)
            row.text:SetTextColor(r, g, b, 1)
            row.dot:Hide()

            if row.clickTarget and not InCombatLockdown() then
                setFearWardClickTarget(row.clickTarget, row.unit, not isOutOfRange)
            elseif row.clickTarget then
                state.pendingSecureRefresh = true
            end
        elseif row and row.dot then
            if row.text then
                row.text:SetTextColor(0.55, 0.55, 0.55, 1)
            end
            row.dot:Hide()
        end
    end
end

local function getFearWardCooldownInfo()
    local startTime, duration, enabled

    if state.fearWardSpellSlot then
        startTime, duration, enabled = GetSpellCooldown(state.fearWardSpellSlot, BOOKTYPE_SPELL)
        startTime = tonumber(startTime) or 0
        duration = tonumber(duration) or 0
        if startTime > 0 or duration > 0 then
            return startTime, duration, enabled
        end
    end

    startTime, duration, enabled = GetSpellCooldown(FEAR_WARD_NAME)
    startTime = tonumber(startTime) or 0
    duration = tonumber(duration) or 0
    return startTime, duration, enabled
end

local function updateCooldownBar()
    if not state.cooldownBar or not state.cooldownText then
        return false
    end

    if not state.fearWardSpellSlot then
        state.fearWardSpellSlot = findFearWardSpellSlot()
    end

    local startTime, duration, enabled = getFearWardCooldownInfo()

    if enabled == 0 or duration <= 1.5 or startTime <= 0 then
        state.cooldownBar:Hide()
        return false
    end

    local remaining = math.max(0, (startTime + duration) - GetTime())
    if remaining <= 0 then
        state.cooldownBar:Hide()
        return false
    end

    state.cooldownBar:SetMinMaxValues(0, duration)
    state.cooldownBar:SetValue(remaining)
    state.cooldownText:SetText(string.format("Fear Ward CD: %.0fs", remaining))
    applyFont(state.cooldownText, -1)
    state.cooldownBar:Show()
    return true
end

local function adjustFrameHeight()
    if not state.frame then
        return
    end

    updateCooldownBar()
end

local function updateDisplayList()
    local display = {}
    local count = 0
    local settings = ElysiumFearWardDB.settings

    for _, key in ipairs(ROLE_ORDER) do
        display[key] = {}
    end

    for _, guid in ipairs(state.rosterOrder) do
        local entry = state.roster[guid]
        if entry and entry.online and not entry.dead then
            local role = classifyUnit(entry)
            if role and settings.groups[role] ~= false then
                display[role][#display[role] + 1] = entry
                if not entry.hasFearWard then
                    count = count + 1
                end
            end
        end
    end

    for _, key in ipairs(ROLE_ORDER) do
        table.sort(display[key], sortEntries)
    end

    state.displayList = display
    state.displayCount = count
end

local function refreshRows()
    if not state.frame then
        return
    end

    updateDisplayList()

    if InCombatLockdown() then
        state.pendingLayoutRefresh = true
        state.countText:SetText(string.format("%d players not fearwarded", state.displayCount or 0))

        applyFont(state.titleText, 1)
        applyFont(state.countText, 1)
        updateCooldownBar()
        return
    end

    local y = 0
    local headerIndex = 1
    local rowIndex = 1
    local visibleRows = 0
    local contentWidth = math.max(1, state.scrollChild and state.scrollChild:GetWidth() or (state.frame:GetWidth() - 36))

    state.countText:SetText(string.format("%d players not fearwarded", state.displayCount or 0))

    applyFont(state.titleText, 1)
    applyFont(state.countText, 1)

    for _, key in ipairs(ROLE_ORDER) do
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
            headerRow:SetSize(contentWidth - 4, HEADER_HEIGHT)
            headerRow.text:SetText(ROLE_LABELS[key])
            applyFont(headerRow.text, -1, HIGHLIGHT_FONT_COLOR)
            headerRow:Show()
            headerIndex = headerIndex + 1
            y = y - HEADER_HEIGHT
            visibleRows = visibleRows + 1

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
                        if mouseButton == "RightButton" and showRoleOverrideMenu then
                            showRoleOverrideMenu(self.ownerRow)
                        end
                    end)
                    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    row.dot = row:CreateTexture(nil, "OVERLAY")
                    row.dot:SetSize(5, 5)
                    row.dot:SetPoint("LEFT", -8, 0)
                    row.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
                    row.dot:SetVertexColor(1, 0.15, 0.15, 1)
                    row.dot:Hide()
                    row.text:SetPoint("LEFT", 0, 0)
                    local highlight = row.clickTarget:CreateTexture(nil, "HIGHLIGHT")
                    highlight:SetAllPoints(row.clickTarget)
                    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
                    highlight:SetVertexColor(1, 1, 1, 0.08)
                    state.rows[rowIndex] = row
                end

                local unit = findUnitByGuid(entry.guid)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", state.scrollChild, "TOPLEFT", 10, y)
                row:SetSize(contentWidth - 12, ROW_HEIGHT)
                row.unit = unit
                row.guid = entry.guid
                row.text:SetText(getPlayerDisplayName(entry))
                row.text:Show()
                applyFont(row.text, 0)

                if row.clickTarget and not InCombatLockdown() then
                    if unit and UnitExists(unit) then
                        setFearWardClickTarget(row.clickTarget, unit, not isUnitOutOfFearWardRange(unit))
                    else
                        setFearWardClickTarget(row.clickTarget, nil, false)
                    end
                elseif row.clickTarget then
                    state.pendingSecureRefresh = true
                end

                row:Show()
                rowIndex = rowIndex + 1
                y = y - ROW_HEIGHT
                visibleRows = visibleRows + 1
            end
        end
    end

    for index = headerIndex, #state.headerRows do
        state.headerRows[index]:Hide()
    end

    for index = rowIndex, #state.rows do
        state.rows[index].guid = nil
        state.rows[index].unit = nil
        state.rows[index].text:Show()
        state.rows[index]:Hide()
    end

    state.visibleRows = visibleRows
    if state.scrollChild then
        state.scrollChild:SetHeight(math.max(1, -y))
    end
    if state.scrollFrame and state.scrollFrame.UpdateScrollChildRect then
        state.scrollFrame:UpdateScrollChildRect()
    end
    adjustFrameHeight()
    updateRangeIndicators()
end

local function setRoleOverride(guid, roleKey)
    if not guid then
        return
    end

    if roleKey ~= nil and not ROLE_LABELS[roleKey] then
        return
    end

    ElysiumFearWardDB.roleOverrides[guid] = roleKey
    refreshRows()
end

showRoleOverrideMenu = function(row)
    if not row or not row.guid then
        return
    end

    local entry = state.roster[row.guid]
    if not entry or not EasyMenu then
        return
    end

    if not state.roleMenuFrame then
        state.roleMenuFrame = CreateFrame(
            "Frame",
            addonName .. "RoleOverrideMenu",
            UIParent,
            "UIDropDownMenuTemplate"
        )
    end

    local guid = row.guid
    local current = ElysiumFearWardDB.roleOverrides[guid]
    local menu = {
        {
            text = getPlayerDisplayName(entry),
            isTitle = true,
            notCheckable = true,
        },
        {
            text = "Automatic (WoW role)",
            checked = current == nil,
            func = function()
                setRoleOverride(guid, nil)
            end,
        },
    }

    for _, roleKey in ipairs(ROLE_ORDER) do
        local overrideRole = roleKey
        menu[#menu + 1] = {
            text = ROLE_LABELS[overrideRole],
            checked = current == overrideRole,
            func = function()
                setRoleOverride(guid, overrideRole)
            end,
        }
    end

    EasyMenu(menu, state.roleMenuFrame, "cursor", 0, 0, "MENU")
end

local function enumerateUnits()
    if IsInRaid() then
        local size = GetNumGroupMembers() or 0
        local index = 0
        return function()
            index = index + 1
            if index <= size then
                return "raid" .. index
            end
        end
    end

    if IsInGroup() then
        local yieldedPlayer = false
        local size = GetNumSubgroupMembers() or 0
        local index = 0
        return function()
            if not yieldedPlayer then
                yieldedPlayer = true
                return "player"
            end

            index = index + 1
            if index <= size then
                return "party" .. index
            end
        end
    end

    local yieldedSolo = false
    return function()
        if not yieldedSolo then
            yieldedSolo = true
            return "player"
        end
    end
end

local function rebuildRoster()
    wipe(state.roster)
    wipe(state.rosterOrder)
    wipe(state.missingGuids)

    local inRaid = IsInRaid()
    for unit in enumerateUnits() do
        if unit and UnitExists(unit) then
            local guid = UnitGUID(unit)
            local _, classToken = UnitClass(unit)
            if guid and classToken and not shouldSkipUnit(unit) then
                local hasWard, fearWardExpiresAt = getFearWardInfo(unit)
                local playerName, playerRealm = getPlayerNameParts(unit)
                local entry = {
                    guid = guid,
                    unit = unit,
                    name = playerName,
                    realm = playerRealm,
                    classToken = classToken,
                    online = UnitIsConnected(unit),
                    dead = UnitIsDeadOrGhost(unit),
                    assignedRole = getAssignedGroupRole(unit),
                    isMaintank = inRaid and GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) or false,
                    hasFearWard = hasWard,
                    fearWardExpiresAt = hasWard and (fearWardExpiresAt or (GetTime() + FEAR_WARD_DURATION)) or nil,
                }

                state.roster[guid] = entry
                state.rosterOrder[#state.rosterOrder + 1] = guid
            end
        end
    end

    refreshRows()
end

findUnitByGuid = function(guid)
    local entry = guid and state.roster[guid]
    if entry and entry.unit and UnitExists(entry.unit) and UnitGUID(entry.unit) == guid then
        return entry.unit
    end

    for unit in enumerateUnits() do
        if unit and UnitExists(unit) and UnitGUID(unit) == guid then
            if entry then
                entry.unit = unit
            end
            return unit
        end
    end

    return nil
end

local function updateRosterUnitStatuses()
    for _, guid in ipairs(state.rosterOrder) do
        local entry = state.roster[guid]
        if entry then
            local unit = findUnitByGuid(guid)
            if unit and UnitExists(unit) then
                entry.unit = unit
                entry.online = UnitIsConnected(unit)
                entry.dead = UnitIsDeadOrGhost(unit)
                entry.assignedRole = getAssignedGroupRole(unit)
                entry.isMaintank = IsInRaid() and GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) or false
            else
                entry.online = false
                entry.dead = true
                entry.assignedRole = "NONE"
                entry.isMaintank = false
            end
        end
    end
end

local function fullRefresh()
    updateRosterUnitStatuses()
    refreshRows()
end

local function setFearWardStateByGuid(guid, hasBuff, expiresAt)
    if not guid then
        return
    end

    local entry = state.roster[guid]
    if not entry then
        return
    end

    hasBuff = hasBuff and true or false
    local stateChanged = entry.hasFearWard ~= hasBuff
    entry.hasFearWard = hasBuff
    if hasBuff then
        entry.fearWardExpiresAt = tonumber(expiresAt) or entry.fearWardExpiresAt or (GetTime() + FEAR_WARD_DURATION)
    else
        entry.fearWardExpiresAt = nil
    end

    updateRangeIndicators()
    if stateChanged then
        refreshRows()
    end
end

local function handleUnitAura(unit)
    if not unit or not UnitExists(unit) then
        return
    end

    local guid = UnitGUID(unit)
    if guid and state.roster[guid] then
        local hasBuff, expiresAt = getFearWardInfo(unit)
        setFearWardStateByGuid(guid, hasBuff, expiresAt)
    end
end

local function handleCombatLog()
    local _, eventType, _, _, _, _, _, destGUID, _, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
    if spellName ~= FEAR_WARD_NAME and spellId ~= 6346 then
        return
    end

    if eventType == "SPELL_AURA_APPLIED" or eventType == "SPELL_AURA_REFRESH" then
        setFearWardStateByGuid(destGUID, true, GetTime() + FEAR_WARD_DURATION)
        return
    end

    if eventType == "SPELL_AURA_REMOVED"
        or eventType == "SPELL_AURA_BROKEN"
        or eventType == "SPELL_AURA_BROKEN_SPELL" then
        setFearWardStateByGuid(destGUID, false)
    end
end

local function toggleMainFrame()
    local frame = state.frame
    if not frame then
        return
    end

    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        refreshRows()
    end
end

local function selectFont(fontKey)
    ElysiumFearWardDB.settings.fontKey = fontKey
    refreshRows()

    if state.settingsFrame and state.settingsFrame:IsShown() then
        refreshFontRows()
    end
end

local function ensureMinimapButton()
    if state.minimapButton then
        return state.minimapButton
    end

    local button = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetClampedToScreen(true)
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
            openSettingsFrame()
            return
        end

        if IsShiftKeyDown() then
            return
        end

        toggleMainFrame()
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
            local dx = (px / scale) - mx
            local dy = (py / scale) - my
            ElysiumFearWardDB.minimap.position = math.deg(atan2Compat(dy, dx)) % 360
            ElysiumFearWardDB.minimap.distance = 1
            updateMinimapButtonPosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
        saveMinimapPosition(self)
        updateMinimapButtonPosition()
    end)

    state.minimapButton = button
    updateMinimapButtonPosition()
    return button
end

local function ensureFrame()
    if state.frame then
        return state.frame
    end

    local saved = ElysiumFearWardDB.frame
    local frame = CreateFrame("Frame", addonName .. "Frame", UIParent, "BackdropTemplate")
    frame:SetSize(saved.width or WINDOW_WIDTH, saved.height or WINDOW_HEIGHT)
    frame:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        edgeSize = 14,
    })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT, MAX_WINDOW_WIDTH, MAX_WINDOW_HEIGHT)
    else
        frame:SetMinResize(MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT)
        frame:SetMaxResize(MAX_WINDOW_WIDTH, MAX_WINDOW_HEIGHT)
    end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveFramePosition(self)
    end)
    frame:Hide()

    if EasyMenu and not state.roleMenuFrame then
        state.roleMenuFrame = CreateFrame(
            "Frame",
            addonName .. "RoleOverrideMenu",
            UIParent,
            "UIDropDownMenuTemplate"
        )
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", FRAME_PADDING, -FRAME_PADDING)
    title:SetText("Fear Ward")
    applyFont(title, 1)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    local updateButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    updateButton:SetSize(62, 18)
    updateButton:SetPoint("TOPRIGHT", closeButton, "BOTTOMRIGHT", -6, -3)
    updateButton:SetText("Refresh")
    updateButton:SetScript("OnClick", function()
        rebuildRoster()
    end)

    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    countText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    countText:SetJustifyH("LEFT")
    countText:SetText("0 players not fearwarded")

    local scrollFrame = CreateFrame("ScrollFrame", addonName .. "PlayerScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", FRAME_PADDING, -TOP_CONTENT_OFFSET)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, FOOTER_HEIGHT + 4)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local scrollBar = self.ScrollBar
        if not scrollBar then
            return
        end

        local minValue, maxValue = scrollBar:GetMinMaxValues()
        local newValue = scrollBar:GetValue() - (delta * (ROW_HEIGHT * 3))
        scrollBar:SetValue(math.max(minValue, math.min(maxValue, newValue)))
    end)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    scrollChild:SetSize(math.max(1, scrollFrame:GetWidth()), 1)
    scrollFrame:SetScrollChild(scrollChild)

    local cooldownBar = CreateFrame("StatusBar", nil, frame)
    cooldownBar:SetPoint(
        "BOTTOMLEFT",
        frame,
        "BOTTOMLEFT",
        FRAME_PADDING + (#ROLE_ORDER * FILTER_ICON_SPACING) + 4,
        8
    )
    cooldownBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -FRAME_PADDING, 8)
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
    cooldownText:SetPoint("CENTER", cooldownBar, "CENTER", 0, 0)
    cooldownText:SetJustifyH("CENTER")
    cooldownText:SetText("")

    for index, key in ipairs(ROLE_ORDER) do
        local roleKey = key
        local filter = CreateFrame("CheckButton", addonName .. "Main" .. roleKey .. "Filter", frame)
        filter:SetSize(FILTER_ICON_SIZE, FILTER_ICON_SIZE)
        filter:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", FRAME_PADDING + ((index - 1) * FILTER_ICON_SPACING), 5)
        filter:SetNormalTexture(ROLE_ICONS[roleKey])
        filter:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        filter:SetCheckedTexture(ROLE_ICONS[roleKey])
        filter:SetChecked(ElysiumFearWardDB.settings.groups[roleKey] ~= false)
        filter:SetAlpha(filter:GetChecked() and 1 or 0.35)
        filter.roleKey = roleKey

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
            refreshRows()
        end)
        filter:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(ROLE_LABELS[roleKey])
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
    resizeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeButton:SetScript("OnMouseDown", function()
        if InCombatLockdown() then
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage("Window size cannot change during combat", 1, 0.2, 0.2)
            end
            return
        end
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeButton:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        saveFrameSize(frame)
        refreshRows()
    end)

    frame:SetScript("OnSizeChanged", function(_, width)
        if state.scrollChild and not InCombatLockdown() then
            state.scrollChild:SetWidth(math.max(1, width - 36))
            refreshRows()
        elseif InCombatLockdown() then
            state.pendingLayoutRefresh = true
        end
    end)

    frame:SetScript("OnShow", refreshRows)

    state.frame = frame
    state.titleText = title
    state.countText = countText
    state.cooldownBar = cooldownBar
    state.cooldownText = cooldownText
    state.scrollFrame = scrollFrame
    state.scrollChild = scrollChild
    scrollChild:SetWidth(math.max(1, frame:GetWidth() - 36))

    ensureMinimapButton()
    return frame
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

    local selected = row:CreateTexture(nil, "BACKGROUND")
    selected:SetAllPoints()
    selected:SetTexture("Interface\\Buttons\\WHITE8X8")
    selected:SetVertexColor(1, 0.82, 0.2, 0.16)
    row.selected = selected

    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local highlight = row:GetHighlightTexture()
    highlight:SetVertexColor(1, 1, 1, 0.08)

    row:SetScript("OnClick", function(self)
        if self.fontKey then
            selectFont(self.fontKey)
        end
    end)

    state.fontRows[index] = row
    return row
end

refreshFontRows = function()
    if not state.fontScrollChild then
        return
    end

    local fonts = getAvailableFonts()
    local selectedKey = ElysiumFearWardDB.settings.fontKey

    for index, entry in ipairs(fonts) do
        local row = ensureFontRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", state.fontScrollChild, "TOPLEFT", 0, -((index - 1) * 18))
        row.fontKey = entry.key
        row.text:SetText(entry.label)
        row.text:SetFont(entry.path or DEFAULT_FONT_PATH, 12, "")

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

openSettingsFrame = function()
    if state.settingsFrame then
        state.settingsFrame:Show()
        state.settingsFrame:Raise()
    end
end

local function ensureSettingsFrame()
    if state.settingsFrame then
        return state.settingsFrame
    end

    local frame = CreateFrame("Frame", addonName .. "SettingsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(390, 600)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
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
    for _, key in ipairs(ROLE_ORDER) do
        local roleKey = key
        local checkbox = CreateFrame("CheckButton", addonName .. roleKey .. "Checkbox", frame, "UICheckButtonTemplate")
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
            refreshRows()
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
        label:SetText(ROLE_LABELS[roleKey])

        state.settingsRows[roleKey] = checkbox
        previousAnchor = checkbox
    end

    local sizeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", previousAnchor, "BOTTOMLEFT", 2, -18)
    sizeLabel:SetText("Font size")

    local sizeSlider = CreateFrame("Slider", addonName .. "FontSizeSlider", frame, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", -4, -14)
    sizeSlider:SetWidth(220)
    sizeSlider:SetMinMaxValues(MIN_FONT_SIZE, MAX_FONT_SIZE)
    sizeSlider:SetValueStep(1)
    sizeSlider:SetObeyStepOnDrag(true)
    _G[sizeSlider:GetName() .. "Low"]:SetText(tostring(MIN_FONT_SIZE))
    _G[sizeSlider:GetName() .. "High"]:SetText(tostring(MAX_FONT_SIZE))
    _G[sizeSlider:GetName() .. "Text"]:SetText("Font size")
    sizeSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        if ElysiumFearWardDB.settings.fontSize == value then
            return
        end
        ElysiumFearWardDB.settings.fontSize = value
        refreshRows()
    end)
    state.fontSizeSlider = sizeSlider

    local showRealmCheckbox = CreateFrame("CheckButton", addonName .. "ShowPlayerRealmCheckbox", frame, "UICheckButtonTemplate")
    showRealmCheckbox:SetSize(22, 22)
    showRealmCheckbox:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", 0, -18)
    showRealmCheckbox:SetScript("OnClick", function(self)
        ElysiumFearWardDB.settings.showPlayerRealm = self:GetChecked() and true or false
        refreshRows()
    end)

    local showRealmLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showRealmLabel:SetPoint("LEFT", showRealmCheckbox, "RIGHT", 4, 0)
    showRealmLabel:SetText("Show Player realm")
    state.showRealmCheckbox = showRealmCheckbox

    local nameLengthLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLengthLabel:SetPoint("TOPLEFT", showRealmCheckbox, "BOTTOMLEFT", 2, -16)
    nameLengthLabel:SetText("Character name length")

    local nameLengthSlider = CreateFrame("Slider", addonName .. "NameLengthSlider", frame, "OptionsSliderTemplate")
    nameLengthSlider:SetPoint("TOPLEFT", nameLengthLabel, "BOTTOMLEFT", -4, -14)
    nameLengthSlider:SetWidth(220)
    nameLengthSlider:SetMinMaxValues(MIN_NAME_LENGTH, MAX_NAME_LENGTH)
    nameLengthSlider:SetValueStep(1)
    nameLengthSlider:SetObeyStepOnDrag(true)
    _G[nameLengthSlider:GetName() .. "Low"]:SetText(tostring(MIN_NAME_LENGTH))
    _G[nameLengthSlider:GetName() .. "High"]:SetText(tostring(MAX_NAME_LENGTH))
    _G[nameLengthSlider:GetName() .. "Text"]:SetText(
        string.format("Shorten character name to %d letters", ElysiumFearWardDB.settings.nameLength)
    )
    nameLengthSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        _G[self:GetName() .. "Text"]:SetText(string.format("Shorten character name to %d letters", value))
        if ElysiumFearWardDB.settings.nameLength == value then
            return
        end
        ElysiumFearWardDB.settings.nameLength = value
        refreshRows()
    end)
    state.nameLengthSlider = nameLengthSlider

    local fontLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", nameLengthSlider, "BOTTOMLEFT", 4, -20)
    fontLabel:SetText("Font")

    local fontScrollFrame = CreateFrame("ScrollFrame", addonName .. "FontScrollFrame", frame, "UIPanelScrollFrameTemplate")
    fontScrollFrame:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -8)
    fontScrollFrame:SetSize(300, 120)
    fontScrollFrame:EnableMouseWheel(true)
    fontScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local scrollBar = self.ScrollBar
        if not scrollBar then
            return
        end

        local step = 18
        local minValue, maxValue = scrollBar:GetMinMaxValues()
        local newValue = scrollBar:GetValue() - (delta * step)
        if newValue < minValue then
            newValue = minValue
        elseif newValue > maxValue then
            newValue = maxValue
        end
        scrollBar:SetValue(newValue)
    end)

    local fontScrollChild = CreateFrame("Frame", nil, fontScrollFrame)
    fontScrollChild:SetPoint("TOPLEFT", fontScrollFrame, "TOPLEFT", 0, 0)
    fontScrollChild:SetWidth(280)
    fontScrollChild:SetHeight(1)
    fontScrollFrame:SetScrollChild(fontScrollChild)
    state.fontScrollFrame = fontScrollFrame
    state.fontScrollChild = fontScrollChild

    local updateButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    updateButton:SetSize(120, 22)
    updateButton:SetPoint("BOTTOMLEFT", 14, 14)
    updateButton:SetText("Refresh Roster")
    updateButton:SetScript("OnClick", function()
        rebuildRoster()
    end)

    frame:SetScript("OnShow", function()
        for key, checkbox in pairs(state.settingsRows) do
            checkbox:SetChecked(ElysiumFearWardDB.settings.groups[key] ~= false)
        end
        state.fontSizeSlider:SetValue(ElysiumFearWardDB.settings.fontSize)
        state.showRealmCheckbox:SetChecked(ElysiumFearWardDB.settings.showPlayerRealm)
        state.nameLengthSlider:SetValue(ElysiumFearWardDB.settings.nameLength)
        refreshFontRows()
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

local function openOptionsPanel()
    ensureSettingsFrame()

    if Settings and Settings.OpenToCategory and state.settingsCategory then
        Settings.OpenToCategory(state.settingsCategory.ID or state.settingsCategory.name)
        return
    end

    if InterfaceOptionsFrame_Show and InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_Show()
        InterfaceOptionsFrame_OpenToCategory(state.settingsFrame)
        return
    end

    openSettingsFrame()
end

local function handleSlashCommand(msg)
    local command = string.lower(strtrim(msg or ""))
    if command == "" or command == "show" then
        if state.frame then
            state.frame:Show()
            refreshRows()
        end
        return
    end

    if command == "hide" then
        if state.frame then
            state.frame:Hide()
        end
        return
    end

    if command == "update" or command == "refresh" then
        rebuildRoster()
        return
    end

    if command == "options" or command == "config" then
        openOptionsPanel()
        return
    end

    print("|cff66ccffElysiumFearWard|r commands: /fearward, /fearward update, /fearward options")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

eventFrame:SetScript("OnUpdate", function(_, elapsed)
    state.rangeTicker = state.rangeTicker + elapsed
    state.cooldownTicker = state.cooldownTicker + elapsed

    if state.rangeTicker >= RANGE_UPDATE_INTERVAL then
        state.rangeTicker = 0
        if state.frame and state.frame:IsShown() then
            updateRangeIndicators()
        end
    end

    if state.cooldownTicker >= COOLDOWN_UPDATE_INTERVAL then
        state.cooldownTicker = 0
        if state.frame and state.frame:IsShown() then
            adjustFrameHeight()
        end
    end
end)

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then
            return
        end

        ensureDB()
        state.enabled = isEligiblePlayer()
        if not state.enabled then
            return
        end

        ensureFrame()
        ensureSettingsFrame()
        refreshRows()
        return
    end

    if event == "PLAYER_LOGIN" then
        SLASH_ELYSIUMFEARWARD1 = "/fearward"
        SlashCmdList["ELYSIUMFEARWARD"] = handleSlashCommand

        if not state.enabled then
            return
        end

        rebuildRoster()
        updateMinimapButtonPosition()
        return
    end

    if not state.enabled then
        return
    end

    if event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        rebuildRoster()
        return
    end

    if event == "PLAYER_ROLES_ASSIGNED" then
        fullRefresh()
        return
    end

    if event == "UNIT_AURA" then
        handleUnitAura(arg1)
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if state.pendingSecureRefresh or state.pendingLayoutRefresh then
            state.pendingSecureRefresh = false
            state.pendingLayoutRefresh = false
            refreshRows()
        end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        handleCombatLog()
    end
end)
