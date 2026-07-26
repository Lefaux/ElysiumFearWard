local _, addon = ...

local state = addon.state

local function shouldSkipUnit(unit)
    return not UnitExists(unit)
        or UnitIsUnit(unit, "pet")
        or UnitIsDeadOrGhost(unit)
        or not UnitIsConnected(unit)
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

function addon.ClassifyUnit(entry)
    if not entry then
        return nil
    end

    local override = ElysiumFearWardDB.roleOverrides and ElysiumFearWardDB.roleOverrides[entry.guid]
    if override and addon.IsRoleOverrideAllowed(entry.classToken, override) then
        return override
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

function addon.SortEntries(a, b)
    local classA = addon.CLASS_PRIORITY[a.classToken] or 99
    local classB = addon.CLASS_PRIORITY[b.classToken] or 99
    if classA ~= classB then
        return classA < classB
    end
    return (a.name or "") < (b.name or "")
end

function addon.EnumerateUnits()
    if IsInRaid() then
        local size, index = GetNumGroupMembers() or 0, 0
        return function()
            index = index + 1
            if index <= size then
                return "raid" .. index
            end
        end
    end

    if IsInGroup() then
        local yieldedPlayer, size, index = false, GetNumSubgroupMembers() or 0, 0
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

function addon.FindUnitByGuid(guid)
    local entry = guid and state.roster[guid]
    if entry and entry.unit and UnitExists(entry.unit) and UnitGUID(entry.unit) == guid then
        return entry.unit
    end

    for unit in addon.EnumerateUnits() do
        if unit and UnitExists(unit) and UnitGUID(unit) == guid then
            if entry then
                entry.unit = unit
            end
            return unit
        end
    end
    return nil
end

function addon.RebuildRoster()
    wipe(state.roster)
    wipe(state.rosterOrder)

    local inRaid = IsInRaid()
    for unit in addon.EnumerateUnits() do
        if unit and UnitExists(unit) then
            local guid = UnitGUID(unit)
            local _, classToken = UnitClass(unit)
            if guid and classToken and not shouldSkipUnit(unit) then
                local hasWard, expiresAt = addon.GetFearWardInfo(unit)
                local playerName, playerRealm = addon.GetPlayerNameParts(unit)
                state.roster[guid] = {
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
                    fearWardExpiresAt = hasWard and (expiresAt or (GetTime() + addon.constants.FEAR_WARD_DURATION)) or nil,
                }
                state.rosterOrder[#state.rosterOrder + 1] = guid
            end
        end
    end

    if addon.RefreshRows then
        addon.RefreshRows()
    end
end

function addon.UpdateRosterUnitStatuses()
    for _, guid in ipairs(state.rosterOrder) do
        local entry = state.roster[guid]
        if entry then
            local unit = addon.FindUnitByGuid(guid)
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

function addon.FullRefresh()
    addon.UpdateRosterUnitStatuses()
    addon.RefreshRows()
end
