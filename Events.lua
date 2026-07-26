local _, addon = ...

local c = addon.constants
local state = addon.state

local function handleSlashCommand(msg)
    local command = string.lower(strtrim(msg or ""))
    if command == "" or command == "show" then
        if state.frame then
            state.frame:Show()
            addon.RefreshRows()
        end
    elseif command == "hide" then
        if state.frame then
            state.frame:Hide()
        end
    elseif command == "update" or command == "refresh" then
        addon.RebuildRoster()
    elseif command == "options" or command == "config" then
        addon.OpenOptionsPanel()
    else
        print("|cff66ccffElysiumFearWard|r commands: /fearward, /fearward refresh, /fearward options")
    end
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
    if state.rangeTicker >= c.RANGE_UPDATE_INTERVAL then
        state.rangeTicker = 0
        if state.frame and state.frame:IsShown() then
            addon.UpdateRangeIndicators()
        end
    end
    if state.cooldownTicker >= c.COOLDOWN_UPDATE_INTERVAL then
        state.cooldownTicker = 0
        if state.frame and state.frame:IsShown() then
            addon.UpdateCooldownBar()
        end
    end
end)

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addon.name then
            return
        end
        addon.EnsureDB()
        state.enabled = addon.IsEligiblePlayer()
        if state.enabled then
            addon.EnsureFrame()
            addon.EnsureSettingsFrame()
            addon.RefreshRows()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        SLASH_ELYSIUMFEARWARD1 = "/fearward"
        SlashCmdList["ELYSIUMFEARWARD"] = handleSlashCommand
        if state.enabled then
            addon.RebuildRoster()
            addon.UpdateMinimapButtonPosition()
        end
        return
    end

    if not state.enabled then
        return
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        addon.RebuildRoster()
    elseif event == "PLAYER_ROLES_ASSIGNED" then
        addon.FullRefresh()
    elseif event == "UNIT_AURA" then
        addon.HandleUnitAura(arg1)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if state.pendingSecureRefresh or state.pendingLayoutRefresh then
            state.pendingSecureRefresh, state.pendingLayoutRefresh = false, false
            addon.RefreshRows()
        end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        addon.HandleCombatLog()
    end
end)
