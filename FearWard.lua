local _, addon = ...

local c = addon.constants
local state = addon.state

local function findFearWardSpellSlot()
    if not GetNumSpellTabs or not GetSpellTabInfo or not GetSpellBookItemName then
        return nil
    end
    for tabIndex = 1, GetNumSpellTabs() or 0 do
        local _, _, offset, numSpells = GetSpellTabInfo(tabIndex)
        offset, numSpells = tonumber(offset) or 0, tonumber(numSpells) or 0
        for spellOffset = 1, numSpells do
            local slot = offset + spellOffset
            if GetSpellBookItemName(slot, BOOKTYPE_SPELL) == c.FEAR_WARD_NAME then
                return slot
            end
        end
    end
    return nil
end

function addon.GetFearWardInfo(unit)
    local index = 1
    while true do
        local name, _, _, _, duration, expirationTime = UnitBuff(unit, index)
        if not name then
            return false, nil
        end
        if name == c.FEAR_WARD_NAME then
            duration, expirationTime = tonumber(duration) or 0, tonumber(expirationTime) or 0
            return true, duration > 0 and expirationTime > 0 and expirationTime or nil
        end
        index = index + 1
    end
end

function addon.IsUnitOutOfFearWardRange(unit)
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
    if inRange == nil and CheckInteractDistance and CheckInteractDistance(unit, 4) == false then
        return true
    end
    return false
end

function addon.SetFearWardClickTarget(button, unit, enabled)
    if not button then
        return
    end
    button:SetAttribute("macrotext1", nil)
    if enabled and unit and UnitExists(unit) then
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", c.FEAR_WARD_NAME)
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

function addon.UpdateRangeIndicators()
    for _, row in ipairs(state.rows) do
        if row and row.dot and row:IsShown() and row.unit and UnitExists(row.unit) then
            local entry = row.guid and state.roster[row.guid]
            local outOfRange = addon.IsUnitOutOfFearWardRange(row.unit)
            local r, g, b = getPlayerStatusColor(entry, outOfRange)
            row.text:SetTextColor(r, g, b, 1)
            row.dot:Hide()

            if row.clickTarget and not InCombatLockdown() then
                addon.SetFearWardClickTarget(row.clickTarget, row.unit, not outOfRange)
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
        startTime, duration = tonumber(startTime) or 0, tonumber(duration) or 0
        if startTime > 0 or duration > 0 then
            return startTime, duration, enabled
        end
    end
    startTime, duration, enabled = GetSpellCooldown(c.FEAR_WARD_NAME)
    return tonumber(startTime) or 0, tonumber(duration) or 0, enabled
end

function addon.UpdateCooldownBar()
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
    addon.ApplyFont(state.cooldownText, -1)
    state.cooldownBar:Show()
    return true
end

function addon.SetFearWardStateByGuid(guid, hasBuff, expiresAt)
    local entry = guid and state.roster[guid]
    if not entry then
        return
    end

    hasBuff = not not hasBuff
    local changed = entry.hasFearWard ~= hasBuff
    entry.hasFearWard = hasBuff
    entry.fearWardExpiresAt = hasBuff
        and (tonumber(expiresAt) or entry.fearWardExpiresAt or (GetTime() + c.FEAR_WARD_DURATION))
        or nil

    addon.UpdateRangeIndicators()
    if changed then
        addon.RefreshRows()
    end
end

function addon.HandleUnitAura(unit)
    if not unit or not UnitExists(unit) then
        return
    end
    local guid = UnitGUID(unit)
    if guid and state.roster[guid] then
        local hasBuff, expiresAt = addon.GetFearWardInfo(unit)
        addon.SetFearWardStateByGuid(guid, hasBuff, expiresAt)
    end
end

function addon.HandleCombatLog()
    local _, eventType, _, _, _, _, _, destGUID, _, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
    if spellName ~= c.FEAR_WARD_NAME and spellId ~= c.FEAR_WARD_ID then
        return
    end
    if eventType == "SPELL_AURA_APPLIED" or eventType == "SPELL_AURA_REFRESH" then
        addon.SetFearWardStateByGuid(destGUID, true, GetTime() + c.FEAR_WARD_DURATION)
    elseif eventType == "SPELL_AURA_REMOVED"
        or eventType == "SPELL_AURA_BROKEN"
        or eventType == "SPELL_AURA_BROKEN_SPELL" then
        addon.SetFearWardStateByGuid(destGUID, false)
    end
end
