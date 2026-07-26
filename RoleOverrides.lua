local _, addon = ...

local state = addon.state

function addon.SetRoleOverride(guid, roleKey)
    local entry = guid and state.roster[guid]
    if not entry or (roleKey ~= nil and not addon.IsRoleOverrideAllowed(entry.classToken, roleKey)) then
        return
    end
    ElysiumFearWardDB.roleOverrides[guid] = roleKey
    addon.RefreshRows()
end

function addon.ShowRoleOverrideMenu(row)
    if not row or not row.guid then
        return
    end

    local entry = state.roster[row.guid]
    if not entry then
        return
    end

    local allowedRoles = addon.ROLE_OVERRIDE_OPTIONS[entry.classToken]
    if not allowedRoles or #allowedRoles == 0 then
        return
    end

    local guid = row.guid
    local current = ElysiumFearWardDB.roleOverrides[guid]
    if current and not addon.IsRoleOverrideAllowed(entry.classToken, current) then
        ElysiumFearWardDB.roleOverrides[guid] = nil
        current = nil
    end

    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(row.clickTarget or row, function(_, rootDescription)
            rootDescription:CreateTitle(addon.GetPlayerDisplayName(entry))
            rootDescription:CreateRadio(
                "Automatic (WoW role)",
                function()
                    return current == nil
                end,
                function()
                    addon.SetRoleOverride(guid, nil)
                end
            )
            for _, roleKey in ipairs(allowedRoles) do
                local overrideRole = roleKey
                rootDescription:CreateRadio(
                    addon.ROLE_OVERRIDE_LABELS[overrideRole],
                    function()
                        return current == overrideRole
                    end,
                    function()
                        addon.SetRoleOverride(guid, overrideRole)
                    end
                )
            end
        end)
        return
    end

    if not EasyMenu then
        return
    end
    if not state.roleMenuFrame then
        state.roleMenuFrame = CreateFrame(
            "Frame",
            addon.name .. "RoleOverrideMenu",
            UIParent,
            "UIDropDownMenuTemplate"
        )
    end

    local menu = {
        {
            text = addon.GetPlayerDisplayName(entry),
            isTitle = true,
            notCheckable = true,
        },
        {
            text = "Automatic (WoW role)",
            checked = current == nil,
            func = function()
                addon.SetRoleOverride(guid, nil)
            end,
        },
    }
    for _, roleKey in ipairs(allowedRoles) do
        local overrideRole = roleKey
        menu[#menu + 1] = {
            text = addon.ROLE_OVERRIDE_LABELS[overrideRole],
            checked = current == overrideRole,
            func = function()
                addon.SetRoleOverride(guid, overrideRole)
            end,
        }
    end
    EasyMenu(menu, state.roleMenuFrame, "cursor", 0, 0, "MENU")
end
