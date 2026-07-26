local addonName, addon = ...

addon.name = addonName

addon.constants = {
    FEAR_WARD_ID = 6346,
    FEAR_WARD_NAME = GetSpellInfo(6346) or "Fear Ward",
    FEAR_WARD_DURATION = 180,
    DEFAULT_FONT_PATH = "Fonts\\FRIZQT__.TTF",
    DEFAULT_FONT_KEY = "Friz Quadrata TT",
    DEFAULT_FONT_SIZE = 12,
    MIN_FONT_SIZE = 8,
    MAX_FONT_SIZE = 24,
    DEFAULT_NAME_LENGTH = 12,
    MIN_NAME_LENGTH = 3,
    MAX_NAME_LENGTH = 12,
    WINDOW_WIDTH = 250,
    WINDOW_HEIGHT = 250,
    MIN_WINDOW_WIDTH = 220,
    MIN_WINDOW_HEIGHT = 150,
    MAX_WINDOW_WIDTH = 600,
    MAX_WINDOW_HEIGHT = 700,
    ROW_HEIGHT = 15,
    HEADER_HEIGHT = 14,
    FRAME_PADDING = 8,
    TOP_CONTENT_OFFSET = 54,
    FOOTER_HEIGHT = 28,
    FILTER_ICON_SIZE = 19,
    FILTER_ICON_SPACING = 24,
    RANGE_UPDATE_INTERVAL = 0.25,
    COOLDOWN_UPDATE_INTERVAL = 0.1,
}

addon.ROLE_ORDER = {
    "maintank",
    "melee",
    "warriors",
    "healers",
    "ranged",
}

addon.ROLE_LABELS = {
    maintank = "Maintanks",
    melee = "Melee",
    warriors = "Warriors",
    healers = "Healers",
    ranged = "Ranged",
}

addon.ROLE_OVERRIDE_LABELS = {
    maintank = "Tank",
    melee = "Melee",
    warriors = "Warrior",
    healers = "Healer",
    ranged = "Ranged",
}

addon.ROLE_OVERRIDE_OPTIONS = {
    WARRIOR = { "maintank", "warriors" },
    DRUID = { "maintank", "melee", "healers" },
    PALADIN = { "healers", "melee" },
    PRIEST = { "healers", "ranged" },
}

addon.ROLE_ICONS = {
    maintank = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    melee = "Interface\\Icons\\Ability_MeleeDamage",
    warriors = "Interface\\Icons\\Ability_Racial_Avatar",
    healers = "Interface\\Icons\\Spell_Holy_Heal",
    ranged = "Interface\\Icons\\Spell_Fire_FireBolt02",
}

addon.CLASS_PRIORITY = {
    DRUID = 1,
    ROGUE = 2,
    WARRIOR = 3,
    PALADIN = 4,
    PRIEST = 5,
    HUNTER = 6,
    MAGE = 7,
    WARLOCK = 8,
}

addon.FALLBACK_FONTS = {
    { key = "Friz Quadrata TT", label = "Friz Quadrata TT", path = "Fonts\\FRIZQT__.TTF" },
    { key = "Arial Narrow", label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { key = "Morpheus", label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { key = "Skurri", label = "Skurri", path = "Fonts\\skurri.ttf" },
}

addon.state = {
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
    displayList = {},
    rangeTicker = 0,
    cooldownTicker = 0,
    fearWardSpellSlot = nil,
    visibleRows = 0,
    pendingSecureRefresh = false,
    pendingLayoutRefresh = false,
}

function addon.IsEligiblePlayer()
    local _, classToken = UnitClass("player")
    local _, raceToken = UnitRace("player")
    return classToken == "PRIEST" and raceToken == "Dwarf"
end

function addon.IsRoleOverrideAllowed(classToken, roleKey)
    for _, allowedRole in ipairs(addon.ROLE_OVERRIDE_OPTIONS[classToken] or {}) do
        if allowedRole == roleKey then
            return true
        end
    end
    return false
end

function addon.EnsureDB()
    local c = addon.constants
    ElysiumFearWardDB = ElysiumFearWardDB or {}
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
    settings.fontKey = settings.fontKey or c.DEFAULT_FONT_KEY
    settings.fontSize = tonumber(settings.fontSize) or c.DEFAULT_FONT_SIZE
    settings.fontSize = math.max(c.MIN_FONT_SIZE, math.min(c.MAX_FONT_SIZE, math.floor(settings.fontSize + 0.5)))
    settings.showPlayerRealm = settings.showPlayerRealm == nil and true or not not settings.showPlayerRealm
    settings.nameLength = tonumber(settings.nameLength) or c.DEFAULT_NAME_LENGTH
    settings.nameLength = math.max(c.MIN_NAME_LENGTH, math.min(c.MAX_NAME_LENGTH, math.floor(settings.nameLength + 0.5)))
    settings.groups = settings.groups or {}

    for _, key in ipairs(addon.ROLE_ORDER) do
        settings.groups[key] = settings.groups[key] == nil and true or not not settings.groups[key]
    end

    local savedFrame = ElysiumFearWardDB.frame
    savedFrame.width = math.max(c.MIN_WINDOW_WIDTH, math.min(c.MAX_WINDOW_WIDTH, tonumber(savedFrame.width) or c.WINDOW_WIDTH))
    savedFrame.height = math.max(c.MIN_WINDOW_HEIGHT, math.min(c.MAX_WINDOW_HEIGHT, tonumber(savedFrame.height) or c.WINDOW_HEIGHT))
end

local function getSharedMedia()
    if not LibStub then
        return nil
    end
    local ok, media = pcall(LibStub, "LibSharedMedia-3.0", true)
    return ok and media or nil
end

function addon.GetAvailableFonts()
    local fonts, seen = {}, {}
    for _, entry in ipairs(addon.FALLBACK_FONTS) do
        fonts[#fonts + 1] = entry
        seen[entry.key] = true
    end

    local media = getSharedMedia()
    if media and media.HashTable then
        for key, path in pairs(media:HashTable("font") or {}) do
            if not seen[key] then
                fonts[#fonts + 1] = { key = key, label = key, path = path }
                seen[key] = true
            end
        end
    end

    table.sort(fonts, function(a, b)
        return a.label < b.label
    end)
    return fonts
end

function addon.GetFontPath(fontKey)
    local media = getSharedMedia()
    if media and media.IsValid and media:IsValid("font", fontKey) then
        local fetched = media:Fetch("font", fontKey, true)
        if fetched then
            return fetched
        end
    end

    for _, entry in ipairs(addon.FALLBACK_FONTS) do
        if entry.key == fontKey then
            return entry.path
        end
    end
    return addon.constants.DEFAULT_FONT_PATH
end

function addon.ApplyFont(fontString, sizeAdjust, forceColor)
    if not fontString then
        return
    end
    local settings = ElysiumFearWardDB.settings
    fontString:SetFont(addon.GetFontPath(settings.fontKey), settings.fontSize + (sizeAdjust or 0), "")
    if forceColor then
        fontString:SetTextColor(forceColor.r, forceColor.g, forceColor.b, forceColor.a or 1)
    end
end

function addon.SaveFramePosition(frame)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point then
        local saved = ElysiumFearWardDB.frame
        saved.point, saved.relativePoint = point, relativePoint
        saved.x, saved.y = math.floor(x + 0.5), math.floor(y + 0.5)
    end
end

function addon.SaveFrameSize(frame)
    ElysiumFearWardDB.frame.width = math.floor(frame:GetWidth() + 0.5)
    ElysiumFearWardDB.frame.height = math.floor(frame:GetHeight() + 0.5)
end

function addon.GetPlayerNameParts(unit)
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

function addon.GetPlayerDisplayName(entry)
    if not entry then
        return "?"
    end
    local settings = ElysiumFearWardDB.settings
    local maxLetters = settings.nameLength or addon.constants.DEFAULT_NAME_LENGTH
    local name = utf8sub and utf8sub(entry.name or "?", 1, maxLetters) or string.sub(entry.name or "?", 1, maxLetters)
    if settings.showPlayerRealm and entry.realm and entry.realm ~= "" then
        return name .. "-" .. entry.realm
    end
    return name
end
