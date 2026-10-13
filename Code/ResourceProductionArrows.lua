-- ============================================================
-- Resource Production / Consumption / Maintenance Arrows
-- Surviving Mars: Relaunched
--
-- Normal resources:
--   Production vs Consumption + Maintenance
--
-- Fuel:
--   Production vs Consumption + Maintenance + Rocket Refueling
--
-- Electricity / Water / Oxygen:
--   Not modified
-- ============================================================

local THRESHOLD_HIGH = 30
local THRESHOLD_MODERATE = 10
local NOTIFICATION_POLL_INTERVAL = 1000
local NOTIFICATION_IMAGE = "UI/Icons/Notifications/New/placeholder.tga"

local NOTIFICATION_RESOURCES = {
    "Metals",
    "Concrete",
    "Food",
    "Polymers",
    "MachineParts",
    "Electronics",
    "RareMetals",
    "Fuel",
}

local original_get_resource_text
local notification_was_shown = {}
local notification_thread_started = false


local function IsOptionEnabled(name, default)
    local get_setting = rawget(_G, "GetProductionOverUnderSetting")
    if get_setting then
        return get_setting(name, default)
    end

    if not CurrentModOptions or not CurrentModOptions.GetProperty then
        return default
    end

    local value = CurrentModOptions:GetProperty(name)
    if value == nil then
        return default
    end

    return value
end


local function GetNotificationRule(resource)
    local get_rule = rawget(_G, "GetProductionOverUnderNotificationRule")
    if get_rule then
        return get_rule(resource)
    end

    return {
        enabled = true,
        direction = "over",
        threshold = 100,
    }
end


local function GetStoredAmount(resource_overview, resource)
    local amount = resource_overview:GetAvailable(resource) / const.ResourceScale

    if resource == "Food" then
        amount =
            resource_overview:GetTotalFoodStored(resource)
            / const.ResourceScale
    end

    return amount
end


local function ShowThresholdNotification(resource, amount, threshold)
    local rule = GetNotificationRule(resource)
    local comparison = rule.direction == "under" and "is at or under" or "has reached"
    AddCustomOnScreenNotification(
        "ProductionOverUnder_" .. resource,
        T(100002000000, "Resource threshold reached"),
        T{
            100002000001,
            "<resource> <comparison> <amount> stored.",
            resource = resource,
            comparison = comparison,
            amount = math.floor(amount),
        },
        NOTIFICATION_IMAGE,
        nil,
        {
            expiration = 10000,
            close_on_read = true,
        }
    )
end


local function CheckResourceThresholds()
    if not IsOptionEnabled("EnableThresholdNotifications", false)
        or not UICity
    then
        return
    end

    local resource_overview = GetCityResourceOverview(UICity)
    if not resource_overview then
        return
    end

    for _, resource in ipairs(NOTIFICATION_RESOURCES) do
        local rule = GetNotificationRule(resource)
        local amount = GetStoredAmount(resource_overview, resource)
        local reached = rule
            and rule.enabled
            and (
                rule.direction == "under"
                and amount <= rule.threshold
                or rule.direction ~= "under"
                and amount >= rule.threshold
            )

        if reached then
            if not notification_was_shown[resource] then
                ShowThresholdNotification(resource, amount, rule.threshold)
                notification_was_shown[resource] = true
            end
        else
            notification_was_shown[resource] = false
        end
    end
end


local function StartThresholdNotificationThread()
    if notification_thread_started then
        return
    end

    notification_thread_started = true
    CreateRealTimeThread(function()
        while true do
            CheckResourceThresholds()
            Sleep(NOTIFICATION_POLL_INTERVAL)
        end
    end)
end


-- ============================================================
-- Creates the colored arrow
-- ============================================================

local function GetProductionTrendString(production, usage)
    local net = production - usage

    -- Production is lower than usage
    if net < 0 then

        -- How far below zero are we?
        local deficit = -net

        -- Increase the darkness as the deficit gets larger.
        -- 0 deficit = 255 red
        -- 50+ deficit = 100 red
        local red = math.max(
            100,
            math.floor(255 - (deficit * 3.1))
        )

        return string.format(
            "<color %d 0 0>v</color>",
            red
        )
    end

    -- Production is higher than usage
    if net > 0 then
        if net >= THRESHOLD_HIGH then
            return "<color 0 255 0>^</color>"
        elseif net >= THRESHOLD_MODERATE then
            return "<color 255 255 0>^</color>"
        else
            return "<color 255 0 0>^</color>"
        end
    end

    -- Production exactly matches usage
    return "-"
end


-- ============================================================
-- Custom resource text
-- ============================================================

local function CustomGetResourceText(self, res)

    if not IsOptionEnabled("EnableArrows", true) then
        return original_get_resource_text(self, res)
    end

    local resource_overview = GetCityResourceOverview(UICity)

    if not resource_overview then
        return T(0, "")
    end


    -- Current stored amount
    local amount =
        resource_overview:GetAvailable(res) / const.ResourceScale

    -- Food uses its special storage calculation
    if res == "Food" then
        amount =
            resource_overview:GetTotalFoodStored(res) / const.ResourceScale
    end


    -- Last Sol production
    local production =
        resource_overview:GetProducedYesterday(res)
        / const.ResourceScale


    -- Last Sol consumption
    local consumption =
        resource_overview:GetConsumedByConsumptionYesterday(res)
        / const.ResourceScale


    -- Estimated daily maintenance
    local maintenance =
        resource_overview:GetEstimatedDailyMaintenance(res)
        / const.ResourceScale


    -- Total usage
    local total_usage =
        consumption + maintenance


    -- Fuel also includes rocket refueling
    if res == "Fuel" then
        local rocket_refueling =
            resource_overview:GetRocketRefuelFuelYesterday()
            / const.ResourceScale

        total_usage =
            total_usage + rocket_refueling
    end


    -- Determine arrow
    local arrow =
        GetProductionTrendString(
            production,
            total_usage
        )


    -- Format resource amount
    local resource_text =
        self:FmtRes(amount)


    -- Keep everything inside a localized string
    return T{
        100001999999,
        "<resource_text> <arrow>",
        resource_text = resource_text,
        arrow = Untranslated(arrow),
    }
end


-- ============================================================
-- Install override
-- ============================================================

function OnMsg.ClassesBuilt()
    if not InfobarObj then
        print("ResourceTrend: InfobarObj does not exist!")
        return
    end

    original_get_resource_text = InfobarObj.GetResourceText

    rawset(
        InfobarObj,
        "GetResourceText",
        CustomGetResourceText
    )

    print("ResourceTrend: GetResourceText successfully replaced!")
end


function OnMsg.CityStart()
    notification_was_shown = {}
    StartThresholdNotificationThread()
end


function OnMsg.LoadGame()
    notification_was_shown = {}
    StartThresholdNotificationThread()
end