--[[
    Created by Lama Development
    For support - https://discord.gg/etkAKTw3M7
    Updated: 
      • Only based off trash cans, no fake “new location” jobs  
      • Adds a permanent blip at the shift start  
      • Uses lib.notify for all messages  
      • Prevents double-picking the same can  
]]--

-- Job state
local isInJob      = false
local garbageTruck = nil
local garbagePay   = 0
local pickedTrash  = {}

-- Shift start location & heading
local shiftPoint   = vector3(2388.18, 3098.06, 48.15)
local shiftHeading = 302.46

-- Create a map blip for the shift start
Citizen.CreateThread(function()
    local blip = AddBlipForCoord(shiftPoint)
    SetBlipSprite(blip, 498)             -- garbage icon
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, 2)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Trash Collector Start")
    EndTextCommandSetBlipName(blip)
end)

-- Garbage can models
local garbageCanModels = {
    "prop_rub_binbag_sd_01","prop_cs_bin_03","prop_cs_bin_01_skinned",
    "prop_cs_bin_02","prop_cs_bin_01","prop_ld_rub_binbag_01",
    "prop_rub_binbag_sd_02","prop_ld_binbag_01","prop_cs_rub_binbag_01",
    "prop_bin_07b","prop_bin_01a","prop_recyclebin_05_a","prop_recyclebin_02_c",
    "prop_recyclebin_03_a","zprop_bin_01a_old","prop_bin_07c","prop_bin_14a",
    "prop_bin_02a","prop_bin_08a","prop_bin_08open","prop_bin_14b",
    "prop_cs_dumpster_01a","p_dumpster_t","prop_dumpster_3a","prop_dumpster_4b",
    "prop_dumpster_4a","prop_dumpster_01a","prop_dumpster_02b","prop_dumpster_02a"
}

-- ox_target options for each can
local garbageCanOptions = {
    label    = "Pick up trash",
    distance = 5.0,
    onSelect = function(data)
        if not isInJob then
            lib.notify({
                id          = 'not_in_job',
                title       = 'Trash Collector',
                description = 'You must start your shift at the truck first.',
                type        = 'error',
                icon        = 'times-circle',
                iconColor   = '#E74C3C'
            })
            return
        end

        local obj = data.entity
        if pickedTrash[obj] then
            lib.notify({
                id          = 'already_picked',
                title       = 'Trash Collector',
                description = "You've already emptied this can.",
                type        = 'warning',
                icon        = 'exclamation-triangle',
                iconColor   = '#F1C40F'
            })
            return
        end

        pickedTrash[obj] = true
        PayForTrash()
    end
}

-- Register all models
for _, model in ipairs(garbageCanModels) do
    exports.ox_target:addModel(model, garbageCanOptions)
end

-- Payment handler
function PayForTrash()
    local pay = math.random(Config.MinRandomPayment, Config.MaxRandomPayment)
    garbagePay = garbagePay + pay

    lib.notify({
        id          = 'got_money_' .. tostring(pay),
        title       = 'Trash Collector',
        description = ("You earned $%d!"):format(pay),
        type        = 'success',
        icon        = 'trash',
        iconColor   = '#2ECC71'
    })

    TriggerServerEvent("TrashCollector:GiveReward", pay)
end

-- Start your shift (spawn truck & instructions)
function StartGarbageJob()
    if isInJob then return end
    isInJob     = true
    garbagePay  = 0
    pickedTrash = {}

    -- Spawn garbage truck
    RequestModel(Config.GarbageTruck)
    while not HasModelLoaded(Config.GarbageTruck) do
        Wait(100)
    end
    garbageTruck = CreateVehicle(
        Config.GarbageTruck,
        shiftPoint.x, shiftPoint.y, shiftPoint.z,
        shiftHeading, true, false
    )
    SetVehicleEngineOn(garbageTruck, true, true, false)
    TriggerServerEvent("TruckDriver:started", NetworkGetNetworkIdFromEntity(garbageTruck))

-- Instructions
lib.notify({
    id          = 'job_started',
    title       = 'Trash Collector',
    description = 'Shift started! Walk up to any trash bin and use your 3rd eye (ALT) to collect.',
    type        = 'inform',
    icon        = 'play-circle',
    iconColor   = '#3498DB',
    duration    = 10000,      -- 10 seconds
    showDuration = true,      -- optional, defaults to true
    position    = 'top-right' -- or wherever you like
})

    lib.notify({
        id          = 'end_shift',
        title       = 'Trash Collector',
        description = 'Return to the truck and press E to end your shift.',
        type        = 'inform',
        icon        = 'truck',
        duration    = 10000,      -- 10 seconds
        showDuration = true,      -- optional, defaults to true
        iconColor   = '#3498DB'
    })
end

-- End shift & delete truck when back at the start
function TryEndShift()
    if not isInJob then return end

    local pos   = GetEntityCoords(garbageTruck)
    local dist  = #(pos - shiftPoint)
    if dist <= 5.0 then
        lib.notify({
            id          = 'return_truck',
            title       = 'Trash Collector',
            description = 'Press E to end shift and retrieve earnings.',
            type        = 'warning',
            icon        = 'hand-holding-usd',
            iconColor   = '#F39C12'
        })
        if IsControlJustReleased(1, 38) then -- E
            DeleteEntity(garbageTruck)
            isInJob = false
            lib.notify({
                id          = 'shift_ended',
                title       = 'Trash Collector',
                description = ("Shift ended! You earned $%d total."):format(garbagePay),
                type        = 'success',
                icon        = 'money-bill-wave',
                iconColor   = '#2ECC71'
            })
        end
    end
end

-- Draw start marker & listen for shift start/end
Citizen.CreateThread(function()
    AddTextEntry("press_start_job", "Press ~INPUT_CONTEXT~ to start/end your shift")

    while true do
        Wait(1)
        local ped    = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local dist   = #(coords - shiftPoint)

        -- start/end marker
        DrawMarker(
            1,
            shiftPoint.x, shiftPoint.y, shiftPoint.z - 2.0,
            0,0,0, 0,0,0,
            2.0,2.0,1.5,
            50,205,50,75,
            false, true, 2, false
        )

        if dist <= 2.0 then
            DisplayHelpTextThisFrame("press_start_job")
            if IsControlJustReleased(1, 38) then
                if isInJob then
                    TryEndShift()
                else
                    StartGarbageJob()
                end
            end
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if isInJob and garbageTruck then
            local ped = PlayerPedId()
            -- Are we seated in our job's truck?
            if IsPedInVehicle(ped, garbageTruck, false) then
                -- CTRL group 0, control 21 is LEFT SHIFT, control 73 is X
                if IsControlPressed(0, 21) and IsControlJustReleased(0, 73) then
                    -- End the shift
                    DeleteEntity(garbageTruck)
                    isInJob = false
                    -- Notify player
                    lib.notify({
                        id          = 'shift_aborted',
                        title       = 'Trash Collector',
                        description = 'Shift aborted. Truck removed.',
                        type        = 'warning',
                        icon        = 'trash-alt',
                        iconColor   = '#E74C3C'
                    })
                end
            end
        end
    end
end)


-- Helper for on-screen help
function DisplayHelpTextThisFrame(msg)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(msg)
    EndTextCommandDisplayHelp(0, false, true, -1)
end
