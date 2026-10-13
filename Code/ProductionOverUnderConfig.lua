local DEFAULT_SETTINGS = {
    EnableArrows = true,
    EnableThresholdNotifications = true,
}

local CONFIG_RESOURCES = {
    "Metals",
    "Concrete",
    "Food",
    "Polymers",
    "MachineParts",
    "Electronics",
    "RareMetals",
    "Fuel",
}

local settings = {}
local settings_loaded = false
local settings_saved = false


local function LoadSettings()
    if settings_loaded then
        return
    end

    settings_loaded = true
    for name, value in pairs(DEFAULT_SETTINGS) do
        settings[name] = value
    end
    settings.Resources = {}
    for _, resource in ipairs(CONFIG_RESOURCES) do
        settings.Resources[resource] = {
            enabled = false,
            direction = "over",
            threshold = 100,
        }
    end

    local err, data = ReadModPersistentData()
    if err or not data then
        return
    end

    local arrows, notifications, rules = string.match(
        data, "^(%d),(%d)|?(.*)$"
    )
    if arrows and notifications then
        settings.EnableArrows = arrows == "1"
        settings.EnableThresholdNotifications = notifications == "1"
        local index = 0
        for rule in string.gmatch(rules or "", "[^|]+") do
            index = index + 1
            local enabled, direction, threshold = string.match(
                rule, "^(%d),([ou]),(%d+)$"
            )
            local resource = CONFIG_RESOURCES[index]
            if resource and enabled and threshold then
                settings.Resources[resource] = {
                    enabled = enabled == "1",
                    direction = direction == "u" and "under" or "over",
                    threshold = math.max(1, math.min(10000, tonumber(threshold))),
                }
            end
        end
        settings_saved = index == #CONFIG_RESOURCES
        if not settings_saved and tonumber(rules) then
            local threshold = math.max(1, math.min(10000, tonumber(rules)))
            for _, resource in ipairs(CONFIG_RESOURCES) do
                settings.Resources[resource] = {
                    enabled = settings.EnableThresholdNotifications,
                    direction = "over",
                    threshold = threshold,
                }
            end
        end
    end
end


local function SaveSettings()
    local rules = {}
    for _, resource in ipairs(CONFIG_RESOURCES) do
        local rule = settings.Resources[resource]
        rules[#rules + 1] = string.format(
            "%d,%s,%d",
            rule.enabled and 1 or 0,
            rule.direction == "under" and "u" or "o",
            rule.threshold
        )
    end
    WriteModPersistentData(string.format(
        "%d,%d|%s",
        settings.EnableArrows and 1 or 0,
        settings.EnableThresholdNotifications and 1 or 0,
        table.concat(rules, "|")
    ))
    settings_saved = true
end


function GetProductionOverUnderSetting(name, default)
    if not CurrentModOptions or not CurrentModOptions.GetProperty then
        return default
    end

    local value = CurrentModOptions:GetProperty(name)
    if value == nil then
        return default
    end
    return value
end


function GetProductionOverUnderNotificationRule(resource)
    local enabled = GetProductionOverUnderSetting(
        "Enable" .. resource .. "Notification",
        false
    )
    local under = GetProductionOverUnderSetting(
        "Under" .. resource .. "Threshold",
        false
    )
    local threshold = GetProductionOverUnderSetting(
        resource .. "Threshold",
        100
    )

    return {
        enabled = enabled,
        direction = under and "under" or "over",
        threshold = math.max(
            1,
            math.min(10000, math.floor(tonumber(threshold) or 100))
        ),
    }
end


local function CloseConfigDialog(dialog)
    SaveSettings()
    dialog:Close()
end


DefineClass.ProductionOverUnderConfigDlg = {
    __parents = {"XDialog"},
    ZOrder = 1000,
}


local function GetConfigControl(dialog, id)
    local content = dialog:ResolveId("idContent")
    local control = content and content:ResolveId(id) or dialog:ResolveId(id)
    if control then
        return control
    end

    local function FindControl(parent)
        if not parent then
            return
        end
        if parent.Id == id then
            return parent
        end
        for _, child in ipairs(parent) do
            local found = FindControl(child)
            if found then
                return found
            end
        end
    end

    return FindControl(dialog)
end


local function ApplySettingsToConfigDialog(dialog)
    local arrows = GetConfigControl(dialog, "idArrows")
    local notifications = GetConfigControl(dialog, "idNotifications")
    if not arrows or not notifications then
        return false
    end

    arrows:SetToggled(settings.EnableArrows)
    notifications:SetToggled(settings.EnableThresholdNotifications)

    for index, resource in ipairs(CONFIG_RESOURCES) do
        local rule = settings.Resources[resource]
        local row = GetConfigControl(dialog, "idResource" .. index)
        if not row then
            return false
        end

        local enabled = row:ResolveId("idEnabled")
        local direction = row:ResolveId("idDirection")
        local threshold = row:ResolveId("idThreshold")
        if not enabled or not direction or not threshold then
            return false
        end

        enabled:SetToggled(rule.enabled)
        direction:SetText(rule.direction == "under" and "Under" or "Over")
        threshold:SetText(tostring(rule.threshold))
    end

    return true
end


function ProductionOverUnderConfigDlg:Open(...)
    LoadSettings()
    XDialog.Open(self, ...)
    CreateRealTimeThread(function()
        for _ = 1, 10 do
            if ApplySettingsToConfigDialog(self) then
                return
            end
            Sleep(0)
        end
    end)
end


function ProductionOverUnderConfigDlg:SaveAndClose()
    local arrows = GetConfigControl(self, "idArrows")
    local notifications = GetConfigControl(self, "idNotifications")
    if not arrows or not notifications then
        return
    end

    settings.EnableArrows = arrows:GetToggled()
    settings.EnableThresholdNotifications = notifications:GetToggled()
    for index, resource in ipairs(CONFIG_RESOURCES) do
        local row = GetConfigControl(self, "idResource" .. index)
        if not row then
            return
        end
        local enabled = row:ResolveId("idEnabled")
        local direction_control = row:ResolveId("idDirection")
        local threshold_control = row:ResolveId("idThreshold")
        if not enabled or not direction_control or not threshold_control then
            return
        end
        local direction = string.lower(direction_control:GetText()) == "under"
            and "under"
            or "over"
        local threshold = tonumber(threshold_control:GetText()) or 100
        settings.Resources[resource] = {
            enabled = enabled:GetToggled(),
            direction = direction,
            threshold = math.max(1, math.min(10000, math.floor(threshold))),
        }
    end
    CloseConfigDialog(self)
end


function OpenProductionOverUnderConfig()
    local dialog = GetDialog("ProductionOverUnderConfigDlg")
    if dialog then
        dialog:SetFocus(true)
        return dialog
    end

    local parent = rawget(_G, "GetInGameInterface")
    parent = parent and parent() or terminal.desktop
    return OpenDialog("ProductionOverUnderConfigDlg", parent)
end


function OpenProductionOverUnderConfigFromOptions()
    local options = GetDialog("OptionsDlg")
    if options then
        options:Close()
    end

    CreateRealTimeThread(function()
        Sleep(0)
        OpenProductionOverUnderConfig()
    end)
end


function RegisterProductionOverUnderOptions()
    local categories = rawget(_G, "OptionsCategories")
    if not categories then
        return false
    end

    for _, category in ipairs(categories) do
        if category.id == "ProductionOverUnder" then
            return true
        end
    end

    table.insert(categories, {
        id = "ProductionOverUnder",
        display_name = T(
            100002000010,
            "Resource Production Arrows"
        ),
        caps_name = T(
            100002000011,
            "RESOURCE PRODUCTION ARROWS"
        ),
        run = OpenProductionOverUnderConfigFromOptions,
    })
    return true
end


function RegisterProductionOverUnderOptionsWhenReady()
    CreateRealTimeThread(function()
        for _ = 1, 20 do
            if RegisterProductionOverUnderOptions() then
                return
            end
            Sleep(500)
        end
    end)
end


function ProductionOverUnderConfigOnCityStart()
    LoadSettings()
    if not settings_saved then
        CreateRealTimeThread(function()
            Sleep(1000)
            OpenProductionOverUnderConfig()
        end)
    end
end


PlaceObj("XTemplate", {
        __is_kind_of = "XDialog",
        group = "PreGame",
        id = "ProductionOverUnderConfigDlg",
}, PlaceObj("XTemplateWindow", {
            "__class", "ProductionOverUnderConfigDlg",
            "Dock", "box",
        }, {
            PlaceObj("XTemplateWindow", {
                "__class", "XFrame",
                "Dock", "box",
                "Image", "UI/CommonNew/bg1.tga",
            }, {
                PlaceObj("XTemplateWindow", {
                "__class", "XContentTemplate",
                "Id", "idContent",
                "Dock", "box",
                "LayoutMethod", "VList",
                "Padding", box(40, 30, 40, 30),
            }, {
                PlaceObj("XTemplateWindow", {
                    "__class", "XText",
                    "Text", "ProductionOverUnder settings",
                    "TextStyle", "OnScreenNotificationTitle",
                    "Dock", "top",
                    "MinHeight", 50,
                }),
                PlaceObj("XTemplateWindow", {
                    "__class", "XCheckButton",
                    "Id", "idArrows",
                    "Text", "Show production arrows",
                    "Dock", "top",
                    "MinHeight", 45,
                }),
                PlaceObj("XTemplateWindow", {
                    "__class", "XCheckButton",
                    "Id", "idNotifications",
                    "Text", "Enable threshold notifications",
                    "Dock", "top",
                    "MinHeight", 45,
                }),
                PlaceObj("XTemplateWindow", {
                    "__class", "XScrollArea",
                    "Id", "idResourceList",
                    "Dock", "box",
                    "LayoutMethod", "VList",
                }, (function()
                    local rows = {}
                    for index, resource in ipairs(CONFIG_RESOURCES) do
                        rows[#rows + 1] = PlaceObj("XTemplateWindow", {
                            "__class", "XFrame",
                            "Id", "idResource" .. index,
                            "Dock", "top",
                            "MinHeight", 46,
                            "LayoutMethod", "HList",
                            "Padding", box(4, 4, 4, 4),
                        }, {
                            PlaceObj("XTemplateWindow", {
                                "__class", "XCheckButton",
                                "Id", "idEnabled",
                                "Text", resource,
                                "MinWidth", 180,
                            }),
                            PlaceObj("XTemplateWindow", {
                                "__class", "XButton",
                                "Id", "idDirection",
                                "Text", "Over",
                                "MinWidth", 90,
                                "OnPress", function(self)
                                    self:SetText(self:GetText() == "Over" and "Under" or "Over")
                                end,
                            }),
                            PlaceObj("XTemplateWindow", {
                                "__class", "XEdit",
                                "Id", "idThreshold",
                                "MinWidth", 100,
                            }),
                        })
                    end
                    return rows
                end)()),
                PlaceObj("XTemplateWindow", {
                    "__class", "XButton",
                    "Text", "Save",
                    "Dock", "top",
                    "MinHeight", 50,
                    "OnPress", function(self)
                        self:ResolveId("ProductionOverUnderConfigDlg"):SaveAndClose()
                    end,
                }),
            }),
        }),
    })
)


function RegisterProductionOverUnderShortcut()
    local target = rawget(_G, "XShortcutsTarget")
    if not target or not target.actions then
        return
    end

    for _, action in ipairs(target.actions) do
        if action.ActionId == "ProductionOverUnderConfig" then
            return
        end
    end

    table.insert(target.actions, {
        ActionId = "ProductionOverUnderConfig",
        ActionName = "Resource Production Arrows",
        ActionShortcut = "Ctrl-Shift-P",
        ActionToolbar = "mainmenu",
        OnAction = function()
            OpenProductionOverUnderConfig()
        end,
    })
end


function RegisterProductionOverUnderShortcutWhenReady()
    CreateRealTimeThread(function()
        for _ = 1, 20 do
            RegisterProductionOverUnderShortcut()
            if rawget(_G, "XShortcutsTarget") then
                return
            end
            Sleep(500)
        end
    end)
end
