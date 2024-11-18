-- State variables
local lastViewMode = 1  -- Default to third-person view
local isWeaponOut = false  -- To track if the player has a weapon out
local isAiming = false
local isShooting = false
local forceFirstPerson = false  -- Flag to force the player to stay in first-person
local isCrouching = false  -- Flag to track crouch state
local isMoving = false  -- Flag to check if player is moving

-- Fine-tuned settings
local recoilMultiplier = 0.02  -- Reduced recoil multiplier for smoother recoil
local shakeIntensity = 0.08
local muzzleFlashScale = 0.3
local muzzleFlashColor = {r = 255, g = 255, b = 200}

-- Weapon-specific recoil patterns (further reduced recoil ranges)
local weaponRecoil = {
    [`WEAPON_CARBINERIFLE`] = {
        vertical = {min = 0, max = 2},  -- Reduced the vertical recoil range even more
        horizontal = {min = -0.5, max = 0.5},  -- Reduced horizontal recoil range
        multiplier = 0.02  -- Further lowered multiplier for smoother recoil
    },
    [`WEAPON_ADVANCEDRIFLE`] = {
        vertical = {min = 0, max = 2},  -- Reduced the vertical recoil range even more
        horizontal = {min = -0.5, max = 0.5},  -- Reduced horizontal recoil range
        multiplier = 0.015  -- Lower multiplier for even smoother recoil
    },
    [`WEAPON_SPECIALCARBINE`] = {
        vertical = {min = 1, max = 3},  -- Reduced the vertical recoil range
        horizontal = {min = -1, max = 1},  -- Reduced horizontal recoil range
        multiplier = 0.03  -- Lower multiplier for smoother recoil
    }
}

-- Default recoil for other weapons (further reduced values)
local defaultRecoil = {
    vertical = {min = 5, max = 12},  -- Reduced vertical recoil range
    horizontal = {min = -2, max = 2},  -- Reduced horizontal recoil range
    multiplier = 0.05  -- Lower multiplier for smoother recoil
}

-- Force first-person when aiming or shooting, and switch back to third-person when done
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        local ped = PlayerPedId()
        local _, hasWeapon = GetCurrentPedWeapon(ped)
        
        -- Check if the player has a weapon out
        if hasWeapon then
            isWeaponOut = true
            isShooting = IsPedShooting(ped)
            isAiming = IsPlayerFreeAiming(PlayerId())
            
            -- Force first-person view when aiming or shooting
            if isAiming or isShooting then
                if GetFollowPedCamViewMode() ~= 4 then
                    SetFollowPedCamViewMode(4)  -- Switch to first-person view mode
                end
                forceFirstPerson = true
            else
                -- If we stop aiming and shooting, return to third-person view
                if forceFirstPerson then
                    SetFollowPedCamViewMode(1)  -- Switch back to third-person mode
                    forceFirstPerson = false  -- Reset the flag
                end
            end
        else
            -- If the player doesn't have a weapon out, allow toggling view mode with V key
            if not isWeaponOut then
                SetFollowPedCamViewMode(lastViewMode)
            end
        end
    end
end)

-- View toggle thread for the V key (only when the player doesn't have a weapon out)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        local ped = PlayerPedId()
        local _, hasWeapon = GetCurrentPedWeapon(ped)
        
        -- Allow switching camera views when the player doesn't have a weapon out
        if not hasWeapon then
            if IsControlJustPressed(0, 86) then -- V key
                local currentView = GetFollowPedCamViewMode()
                if currentView == 1 then
                    lastViewMode = currentView
                    SetFollowPedCamViewMode(4)  -- Switch to first-person mode
                else
                    SetFollowPedCamViewMode(1)  -- Switch back to third-person mode
                end
            end
        end
    end
end)

-- Movement and crouch-aim handling thread
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local ped = PlayerPedId()

        -- Handle crouch + aim state transitions
        if IsPedCrouching(ped) then
            isCrouching = true
            -- Check if the player is moving while crouching and aiming
            if isAiming then
                -- If moving, apply crouch-aim animation
                if IsControlPressed(0, 32) or IsControlPressed(0, 33) or IsControlPressed(0, 34) or IsControlPressed(0, 35) then
                    isMoving = true
                    SetPedMovementClipset(ped, "move_ped_crouched", 0.25)
                else
                    -- If not moving, apply standing-aim animation while crouching
                    isMoving = false
                    SetPedMovementClipset(ped, "move_ped_crouched", 0.0)
                end
            else
                -- If not aiming, reset crouch movement
                ResetPedMovementClipset(ped, 0.0)
            end
        else
            isCrouching = false
            -- If standing and aiming, apply standing animation
            if isAiming then
                SetPedMovementClipset(ped, "move_ped_standing", 0.25)
            else
                -- Reset to default movement if not aiming or crouching
                ResetPedMovementClipset(ped, 0.25)
            end
        end
    end
end)

-- Main weapon handling thread for recoil, shake, and muzzle flash effects
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local ped = PlayerPedId()
        local isShooting = IsPedShooting(ped)

        if isShooting then
            -- Screen shake
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', shakeIntensity)

            -- Muzzle flash effects
            local coords = GetEntityCoords(ped)
            UseParticleFxAssetNextCall("core")
            StartParticleFxNonLoopedOnEntity(
                "weapon_muzzle_flash", -- Built-in muzzle flash particle effect
                ped,  -- The player ped
                0.0, 0.6, 0.0,  -- Position offset (x, y, z)
                0.0, 0.0, 0.0,  -- Rotation offsets (pitch, yaw, roll)
                muzzleFlashScale,  -- Scale of the effect (can tweak this for size)
                false, false, false  -- Flags (whether to stop, persist, etc.)
            )

            -- Recoil
            local _, weapon = GetCurrentPedWeapon(ped)
            local recoilPattern = weaponRecoil[weapon] or defaultRecoil

            -- Apply recoil adjustments
            local recoilUp = math.random(recoilPattern.vertical.min, recoilPattern.vertical.max) * recoilPattern.multiplier
            local recoilSide = math.random(recoilPattern.horizontal.min, recoilPattern.horizontal.max) * recoilPattern.multiplier

            -- Get current camera pitch and heading
            local camPitch = GetGameplayCamRelativePitch()
            local camHeading = GetGameplayCamRelativeHeading()

            -- Apply recoil adjustments to camera pitch and heading
            SetGameplayCamRelativePitch(camPitch + recoilUp, 1.0)
            SetGameplayCamRelativeHeading(camHeading + recoilSide)
        end
    end
end)

-- Prevent crouch-walking while aiming down sights (to avoid getting stuck)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local ped = PlayerPedId()

        -- If player is aiming and crouch-walking, stop crouch-walking
        if isAiming and IsPedCrouching(ped) then
            -- If player releases movement keys, stop crouch-walking
            if not (IsControlPressed(0, 32) or IsControlPressed(0, 33) or IsControlPressed(0, 34) or IsControlPressed(0, 35)) then
                ResetPedMovementClipset(ped, 0.0)
                SetPedMovementClipset(ped, "move_ped_crouched", 0.25)  -- Keep crouch movement but without walking
            end
        end
    end
end)