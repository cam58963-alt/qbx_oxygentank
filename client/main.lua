local QBX = exports.qbx_core

-- 状態管理変数
local currentDevice = nil
local currentSlot = nil
local deviceConfig = nil
local currentOxygen = 0
local maxOxygen = 0
local isActive = false
local oxygenThread = nil

-- プロップ管理変数（配列で統一管理）
local attachedProps = {}

-- 警告管理変数
local warningShown = false
local criticalWarningShown = false
local lastServerUpdate = 0

--------------------------------------------------
-- プロップ管理関数（修正版）
--------------------------------------------------

-- ✅ 1. 先に DetachDeviceProps を定義
local function DetachDeviceProps()
    for i, propData in ipairs(attachedProps) do
        if propData.entity and DoesEntityExist(propData.entity) then
            DeleteEntity(propData.entity)
            
            if Config.Debug then
                print(string.format('[プロップ削除] %d. %s', propData.index, propData.config.label))
            end
        end
    end
    
    -- 配列をクリア
    attachedProps = {}
end

-- ✅ 2. その後に AttachDeviceProps を定義
local function AttachDeviceProps()
    if not deviceConfig or not deviceConfig.props or #deviceConfig.props == 0 then 
        return 
    end
    
    local ped = PlayerPedId()
    
    -- 既存プロップをクリア（上で定義済みなので正常に動作）
    DetachDeviceProps()
    
    -- 各プロップを順番に装着
    for i, propConfig in ipairs(deviceConfig.props) do
        lib.requestModel(propConfig.model)
        
        local prop = CreateObject(propConfig.model, 0, 0, 0, true, true, true)
        SetEntityCollision(prop, false, false)
        
        AttachEntityToEntity(
            prop,
            ped,
            GetPedBoneIndex(ped, propConfig.bone),
            propConfig.offset.x,
            propConfig.offset.y,
            propConfig.offset.z,
            propConfig.rotation.x,
            propConfig.rotation.y,
            propConfig.rotation.z,
            true, true, false, true, 1, true
        )
        
        -- 配列に保存
        table.insert(attachedProps, {
            entity = prop,
            config = propConfig,
            index = i
        })
        
        if Config.Debug then
            print(string.format('[プロップ装着] %d. %s', i, propConfig.label))
        end
    end
end

--------------------------------------------------
-- UI管理関数
--------------------------------------------------

-- 酸素UI表示の更新
local function UpdateOxygenUI()
    if not deviceConfig or not deviceConfig.showUI then return end
    
    local oxygenPercent = (currentOxygen / maxOxygen) * 100
    
    -- 色の決定
    local color = '#00ff00'  -- 緑
    if oxygenPercent <= 20 then
        color = '#ff0000'    -- 赤
    elseif oxygenPercent <= 40 then
        color = '#ffaa00'    -- オレンジ
    elseif oxygenPercent <= 60 then
        color = '#ffff00'    -- 黄色
    end
    
    -- 状態判定
    local ped = PlayerPedId()
    local isSwimmingUnderwater = IsPedSwimmingUnderWater(ped)
    local isInWater = IsEntityInWater(ped)
    
    local statusIcon = "🏖️"
    local statusText = "地上"
    local actionText = ""
    
    if isInWater then
        if isSwimmingUnderwater then
            statusIcon = "🤿"
            statusText = "潜水中"
            actionText = " (酸素消費中)"
        else
            statusIcon = "🏊"
            statusText = "水面"
            actionText = deviceConfig.autoRefillOnSurface and " (回復中)" or ""
        end
    else
        actionText = deviceConfig.autoRefillOnSurface and " (回復中)" or ""
    end
    
    local displayText = string.format("%s %s: %.1f%% (%.0f秒) | %s%s", 
        statusIcon,
        deviceConfig.label, 
        oxygenPercent, 
        currentOxygen,
        statusText,
        actionText
    )
    
    lib.showTextUI(displayText, {
        position = Config.UI.position,
        icon = deviceConfig.type == 'refillable' and 'wind' or 'mask-face',
        iconColor = color
    })
end

--------------------------------------------------
-- 酸素制御関数
--------------------------------------------------

-- 酸素制御のメインループ（アイテム監視対応版）
local function StartOxygenControl()
    if oxygenThread then return end
    
    CreateThread(function()
        oxygenThread = true
        
        while isActive and deviceConfig do
            local ped = PlayerPedId()
            
            -- ✅ 【重要】アイテム移動・消失検知システム
            local hasItemInSlot = false
            local items = exports.ox_inventory:Search('slots', currentDevice)
            
            if items then
                for _, item in pairs(items) do
                    if item.slot == currentSlot then
                        hasItemInSlot = true
                        break
                    end
                end
            end
            
            -- アイテムが移動・削除された場合の安全装置
            if not hasItemInSlot then
                lib.notify({
                    title = '⚠️ 安全装置作動',
                    description = string.format('%s が移動されたため、装備を自動解除しました', deviceConfig.label),
                    type = 'warning',
                    icon = 'triangle-exclamation',
                    duration = 6000
                })
                
                -- 強制的に装備を外す（データ保存はスキップして安全確保）
                isActive = false
                SetPedMaxTimeUnderwater(ped, Config.DefaultUnderwaterTime)
                DetachDeviceProps()
                lib.hideTextUI()
                
                -- 変数リセット
                currentDevice = nil
                currentSlot = nil
                deviceConfig = nil
                currentOxygen = 0
                maxOxygen = 0
                
                if Config.Debug then
                    print("[安全装置] アイテム移動を検知し、強制解除しました")
                end
                
                break -- ループを抜けて終了
            end
            
            -- 以下、既存の酸素制御ロジック
            local isSwimmingUnderwater = IsPedSwimmingUnderWater(ped)
            
            if isSwimmingUnderwater then
                currentOxygen = math.max(0, currentOxygen - deviceConfig.consumeRate)
                
                if currentOxygen <= 0 then
                    HandleEmptyDevice()
                    break
                else
                    HandleOxygenWarnings()
                end
            else
                if deviceConfig.autoRefillOnSurface and currentOxygen < maxOxygen then
                    if not IsEntityInWater(ped) or not isSwimmingUnderwater then
                        currentOxygen = math.min(currentOxygen + deviceConfig.refillRate, maxOxygen)
                        
                        if currentOxygen >= deviceConfig.warningLevel then
                            warningShown = false
                            criticalWarningShown = false
                        end
                    end
                end
            end
            
            -- サーバー同期
            local currentTime = GetGameTimer()
            if currentTime - lastServerUpdate >= 5000 then
                TriggerServerEvent('qbx_oxygentank:server:updateOxygen', currentDevice, currentSlot, currentOxygen)
                lastServerUpdate = currentTime
            end
            
            UpdateOxygenUI()
            Wait(Config.UI.updateInterval)
        end
        
        oxygenThread = nil
    end)
end


-- 酸素切れ時の処理
function HandleEmptyDevice()
    if deviceConfig.type == 'disposable' then
        lib.notify({
            title = '緊急警告',
            description = string.format(Config.Notifications.consumed, deviceConfig.label),
            type = 'error',
            duration = 5000
        })
        
        TriggerServerEvent('qbx_oxygentank:server:consumeDevice', currentDevice, currentSlot)
    else
        lib.notify({
            title = '緊急警告',
            description = string.format(Config.Notifications.empty, deviceConfig.label),
            type = 'error',
            duration = 5000
        })
    end
    
    StopUsingDevice(true)
    
    local ped = PlayerPedId()
    SetPedDiesInWater(ped, true)
end

-- 酸素警告の処理
function HandleOxygenWarnings()
    if currentOxygen <= deviceConfig.criticalLevel and not criticalWarningShown then
        lib.notify({
            title = '危険警告',
            description = string.format(Config.Notifications.critical, currentOxygen),
            type = 'error',
            duration = 4000
        })
        criticalWarningShown = true
        warningShown = true
    elseif currentOxygen <= deviceConfig.warningLevel and not warningShown then
        lib.notify({
            title = '警告',
            description = string.format(Config.Notifications.warning, currentOxygen),
            type = 'warning',
            duration = 3000
        })
        warningShown = true
    end
end

--------------------------------------------------
-- 装着・脱着関数
--------------------------------------------------

-- 酸素機器の使用開始
function StartUsingDevice(itemData)
    lib.callback('qbx_oxygentank:server:getDeviceData', false, function(hasDevice, oxygenLevel, maxOxygenLevel)
        if hasDevice then
            currentDevice = itemData.name
            currentSlot = itemData.slot
            deviceConfig = Config.OxygenDevices[itemData.name]
            currentOxygen = oxygenLevel
            maxOxygen = maxOxygenLevel
            isActive = true
            warningShown = false
            criticalWarningShown = false
            lastServerUpdate = GetGameTimer()
            
            -- 使い捨てアイテムで残量0の場合
            if currentOxygen <= 0 and deviceConfig.type == 'disposable' then
                lib.notify({
                    title = 'エラー',
                    description = 'このアイテムは既に使い切られています',
                    type = 'error'
                })
                StopUsingDevice(true)
                return
            end
            
            -- 潜水時間を延長
            local ped = PlayerPedId()
            SetPedMaxTimeUnderwater(ped, deviceConfig.underwaterTime)
            
            -- プロップの装着
            AttachDeviceProps()
            
            lib.notify({
                title = 'ダイビングギア',
                description = string.format(Config.Notifications.equipped, deviceConfig.label),
                type = 'success'
            })
            
            if Config.Debug then
                print(string.format("[装着] %s スロット%d 残量:%.1f/%.1f", 
                    itemData.name, currentSlot, oxygenLevel, maxOxygenLevel))
            end
            
            StartOxygenControl()
        else
            lib.notify({
                title = 'エラー',
                description = Config.Notifications.noDevice,
                type = 'error'
            })
        end
    end, itemData.name, itemData.slot)
end

-- 酸素機器の使用停止
function StopUsingDevice(skipNotification)
    if not isActive then return end
    
    local wasActive = isActive
    local savedDevice = currentDevice
    local savedSlot = currentSlot
    local savedConfig = deviceConfig
    local savedOxygen = currentOxygen
    
    isActive = false
    
    -- 潜水時間をデフォルトに戻す
    local ped = PlayerPedId()
    SetPedMaxTimeUnderwater(ped, Config.DefaultUnderwaterTime)
    
    -- プロップの取り外し
    DetachDeviceProps()
    lib.hideTextUI()
    
    -- 最終残量をメタデータに保存
    if savedDevice and savedSlot then
        TriggerServerEvent('qbx_oxygentank:server:updateOxygen', savedDevice, savedSlot, savedOxygen)
        
        if Config.Debug then
            print(string.format("[取外] %s スロット%d 残量:%.1f", savedDevice, savedSlot, savedOxygen))
        end
    end
    
    if not skipNotification and wasActive and savedConfig then
        lib.notify({
            title = 'ダイビングギア',
            description = string.format(Config.Notifications.removed, savedConfig.label),
            type = 'inform'
        })
    end
    
    -- 変数リセット
    currentDevice = nil
    currentSlot = nil
    deviceConfig = nil
    currentOxygen = 0
    maxOxygen = 0
    
    if oxygenThread then
        oxygenThread = nil
    end
end

--------------------------------------------------
-- イベントハンドラー（JOB制限対応版）
--------------------------------------------------

-- ✅ JOB制限エラー通知（新規追加）
RegisterNetEvent('qbx_oxygentank:client:jobRestricted', function(itemName)
    local deviceConfig = Config.OxygenDevices[itemName]
    if not deviceConfig then return end
    
    -- 基本通知
    lib.notify({
        title = '使用制限',
        description = Config.Notifications.jobRestricted,
        type = 'error',
        duration = 5000,
        icon = 'ban'
    })
    
    -- 詳細ダイアログ（ox_libの美しいUI）
    lib.alertDialog({
        header = '⛔ 専門装備使用制限',
        content = string.format([[
**%s は使用できません**

この装備は専門的な訓練を受けた職員のみが使用できます。

**許可された職業:**
%s

**代替手段:**
一般向けの「リブリーザー」をご利用ください。これらのアイテムは誰でも使用可能で、短時間の潜水には十分です。
        ]],
            deviceConfig.label,
            deviceConfig.allowedJobs and #deviceConfig.allowedJobs > 0 
                and '• ' .. table.concat(deviceConfig.allowedJobs, '\n• ') 
                or '• 設定されていません'
        ),
        centered = true
    })
end)

-- 酸素機器の使用イベント
RegisterNetEvent('qbx_oxygentank:client:useDevice', function(itemData)
    if isActive then
        if currentSlot == itemData.slot then
            StopUsingDevice()  -- 同じアイテムなら外す
        else
            lib.notify({
                title = 'エラー',
                description = Config.Notifications.alreadyEquipped,
                type = 'error'
            })
        end
    else
        StartUsingDevice(itemData)
    end
end)

-- 補充完了イベント
RegisterNetEvent('qbx_oxygentank:client:oxygenRefilled', function(itemName, slot)
    if currentDevice == itemName and currentSlot == slot then
        currentOxygen = maxOxygen
        warningShown = false
        criticalWarningShown = false
        
        lib.notify({
            title = '完了',
            description = Config.Notifications.refilled,
            type = 'success'
        })
    end
end)

-- 機器消費完了イベント
RegisterNetEvent('qbx_oxygentank:client:deviceConsumed', function(itemName)
    -- 消費処理は既に完了しているため、特別な処理は不要
end)

--------------------------------------------------
-- 補充ステーション（エラーハンドリング強化版）
--------------------------------------------------

local stationProps = {}

CreateThread(function()
    -- リソース初期化完了を待機
    Wait(1000)
    
    for i, station in pairs(Config.RefillStations) do
        
        -- ✅ プロップ配置（堅牢なエラーハンドリング付き）
        if station.prop and station.prop.enabled then
            
            -- モデルハッシュの取得
            local modelHash = type(station.prop.model) == 'number' and station.prop.model or GetHashKey(station.prop.model)
            
            -- モデルの有効性チェック
            if not IsModelValid(modelHash) then
                if Config.Debug then
                    print(string.format('[補充ステーション警告] 無効なモデル: %s (ステーション%d)', tostring(station.prop.model), i))
                end
                goto continue_station  -- 次のステーションに進む
            end
            
            -- モデルのリクエスト（タイムアウト付き）
            RequestModel(modelHash)
            local timeout = 0
            while not HasModelLoaded(modelHash) and timeout < 50 do
                Wait(100)
                timeout = timeout + 1
            end
            
            if not HasModelLoaded(modelHash) then
                if Config.Debug then
                    print(string.format('[補充ステーション警告] モデルロードタイムアウト: %s', tostring(station.prop.model)))
                end
                goto continue_station
            end
            
            -- 座標計算（安全な方法）
            local propX = station.coords.x + station.prop.offset.x
            local propY = station.coords.y + station.prop.offset.y  
            local propZ = station.coords.z + station.prop.offset.z
            
            -- プロップ生成
            local prop = CreateObject(modelHash, propX, propY, propZ, false, false, false)
            
            if not DoesEntityExist(prop) then
                if Config.Debug then
                    print(string.format('[補充ステーション警告] プロップ生成失敗 (ステーション%d)', i))
                end
                SetModelAsNoLongerNeeded(modelHash)
                goto continue_station
            end
            
            -- プロップ設定
            SetEntityHeading(prop, station.heading or 0.0)
            if station.prop.rotation then
                SetEntityRotation(prop, station.prop.rotation.x, station.prop.rotation.y, station.prop.rotation.z, 2, true)
            end
            FreezeEntityPosition(prop, true)
            SetEntityAsMissionEntity(prop, true, true)
            
            -- 管理配列に追加
            table.insert(stationProps, prop)
            
            -- メモリクリーンアップ
            SetModelAsNoLongerNeeded(modelHash)
            
            if Config.Debug then
                print(string.format('[補充ステーション] 配置成功: %s (ID: %d)', station.label, prop))
            end
            
            -- ox_targetをプロップに設定
            exports.ox_target:addLocalEntity(prop, {
                {
                    name = 'oxygen_refill_' .. i,
                    event = 'qbx_oxygentank:client:refillOxygen',
                    icon = 'fas fa-wind',
                    label = '酸素ボンベを補充',
                    canInteract = function()
                        return isActive and deviceConfig and deviceConfig.canRefillAtStation
                    end
                }
            })
            
        else
            -- プロップなしの場合は座標ベースのターゲット
            if station.targetZone then
                exports.ox_target:addBoxZone({
                    coords = station.coords,
                    size = station.targetZone.size or vec3(3, 3, 3),
                    rotation = station.targetZone.rotation or 0,
                    debug = Config.Debug,
                    options = {
                        {
                            name = 'oxygen_refill_' .. i,
                            event = 'qbx_oxygentank:client:refillOxygen',
                            icon = 'fas fa-wind',
                            label = '酸素ボンベを補充',
                            canInteract = function()
                                return isActive and deviceConfig and deviceConfig.canRefillAtStation
                            end
                        }
                    }
                })
            end
        end
        
        -- ブリップ作成
        if station.blip and station.blip.enabled then
            local blip = AddBlipForCoord(station.coords.x, station.coords.y, station.coords.z)
            SetBlipSprite(blip, station.blip.sprite or 780)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, station.blip.scale or 0.8)
            SetBlipColour(blip, station.blip.color or 3)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(station.blip.name or 'Oxygen Station')
            EndTextCommandSetBlipName(blip)
        end
        
        ::continue_station::  -- エラー時はここにジャンプして次のステーションに進む
    end
    
    if Config.Debug then
        print(string.format('[補充ステーション] 初期化完了: %d個のプロップを配置', #stationProps))
    end
end)

-- ✅ リソース停止時のクリーンアップ（既存の処理を拡張）
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- 配置したステーションプロップを削除
        for _, prop in ipairs(stationProps) do
            if DoesEntityExist(prop) then
                DeleteEntity(prop)
            end
        end
        stationProps = {}
        
        -- 装着中の機器も削除
        if isActive then
            StopUsingDevice(true)
        end
    end
end)

-- 補充イベント（ox_lib最適化版）
RegisterNetEvent('qbx_oxygentank:client:refillOxygen', function()
    if not isActive or not deviceConfig then
        lib.notify({
            title = 'エラー',
            description = '先に酸素機器を装着してください',
            type = 'error'
        })
        return
    end
    
    if not deviceConfig.canRefillAtStation then
        lib.notify({
            title = 'エラー',
            description = Config.Notifications.cannotRefill,
            type = 'error'
        })
        return
    end
    
    if currentOxygen >= maxOxygen then
        lib.notify({
            title = '情報',
            description = Config.Notifications.alreadyFull,
            type = 'inform'
        })
        return
    end
    
    -- ✅ ox_libの統合アニメーション機能を使用
    if lib.progressBar({
        duration = 6000,
        label = string.format('スロット%d の%sを補充中...', currentSlot, deviceConfig.label),
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
            mouse = false
        },
        -- 🚀 アニメーションをox_libが自動管理
        anim = {
            dict = 'mini@repair',
            clip = 'fixing_a_ped',
            flag = 1
        }
    }) then
        TriggerServerEvent('qbx_oxygentank:server:refillOxygen', currentDevice, currentSlot)
    else
        lib.notify({
            title = '情報',
            description = '補充をキャンセルしました',
            type = 'error'
        })
    end
end)

--------------------------------------------------
-- クリーンアップ処理
--------------------------------------------------

-- プレイヤーリセット処理
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    if isActive then
        StopUsingDevice(true)
    end
end)

-- 死亡時の処理
AddEventHandler('gameEventTriggered', function(event, data)
    if event == "CEventNetworkEntityDamage" then
        local victim = data[1]
        local isDead = data[4] == 1
        if victim == PlayerPedId() and isDead and isActive then
            StopUsingDevice(true)
        end
    end
end)

-- リソース停止時のクリーンアップ
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName and isActive then
        StopUsingDevice(true)
    end
end)

--------------------------------------------------
-- デバッグシステム
--------------------------------------------------

if Config.Debug then
    
    print('[QBX Oxygen] デバッグシステムが有効です')
    
    -- 装着中のプロップ数を取得
    local function getAttachedPropCount()
        return #attachedProps
    end
    
    -- 酸素システム詳細情報
    RegisterCommand('oxygeninfo', function()
        if isActive then
            local ped = PlayerPedId()
            local oxygenPercent = (currentOxygen / maxOxygen) * 100
            
            lib.alertDialog({
                header = '🫁 酸素システム詳細情報',
                content = string.format([[
**装着機器:** %s (スロット%d)
**機器タイプ:** %s
**酸素残量:** %.1f / %.1f秒
**残量率:** %.1f%%
**水中判定:** %s
**沈み具合:** %.1f%%
**装着プロップ:** %d個

**消費設定:**
• 消費速度: %.1f秒/秒
• 回復速度: %.1f秒/秒
• 警告レベル: %.0f秒
                ]],
                    currentDevice,
                    currentSlot or 0,
                    deviceConfig.type == 'refillable' and '補充型 🔄' or '使い捨て 🗑️',
                    currentOxygen,
                    maxOxygen,
                    oxygenPercent,
                    IsPedSwimmingUnderWater(ped) and '潜水中 🤿' or '水面/陸上 🏊',
                    GetEntitySubmergedLevel(ped) * 100,
                    getAttachedPropCount(),
                    deviceConfig.consumeRate,
                    deviceConfig.refillRate,
                    deviceConfig.warningLevel
                ),
                centered = true
            })
        else
            lib.notify({
                title = '酸素システム',
                description = '酸素機器は装着されていません',
                type = 'error'
            })
        end
    end, false)
    
    -- 水中判定確認
    RegisterCommand('oxygencheck', function()
        local ped = PlayerPedId()
        local isInWater = IsEntityInWater(ped)
        local isSwimming = IsPedSwimming(ped)
        local isUnderwater = IsPedSwimmingUnderWater(ped)
        local submerged = GetEntitySubmergedLevel(ped) * 100
        
        local statusIcon, statusText
        if isInWater then
            if isUnderwater then
                statusIcon, statusText = '🤿', '完全潜水'
            elseif isSwimming then
                statusIcon, statusText = '🏊', '水面泳ぎ'
            else
                statusIcon, statusText = '💦', '浅瀬'
            end
        else
            statusIcon, statusText = '🏖️', '陸上'
        end
        
        lib.alertDialog({
            header = string.format('%s 水中判定確認', statusIcon),
            content = string.format([[
**現在の状態:** %s

**詳細判定:**
• 水に触れている: %s
• 泳いでいる: %s
• 完全に潜水中: %s
• 沈み具合: %.1f%%

**酸素システム:**
%s
            ]],
                statusText,
                isInWater and '✅ はい' or '❌ いいえ',
                isSwimming and '✅ はい' or '❌ いいえ',
                isUnderwater and '🔴 はい（酸素消費中）' or '🟢 いいえ',
                submerged,
                isActive and string.format('装着中: %s\n酸素残量: %.1f秒', currentDevice, currentOxygen) or '❌ 未装着'
            ),
            centered = true
        })
    end, false)
    
    -- スロット確認
    RegisterCommand('checkslot', function(_, args)
        local slot = tonumber(args[1])
        
        if not slot then
            lib.alertDialog({
                header = '📦 スロット確認',
                content = [[
**使用方法:**
`/checkslot [スロット番号]`

**例:**
• `/checkslot 1` - スロット1を確認
• `/checkslot 5` - スロット5を確認

スロット番号を指定してアイテムの詳細情報を確認できます。
                ]],
                centered = true
            })
            return
        end
        
        lib.callback('qbx_oxygentank:debug:getSlotInfo', false, function(success, data)
            if success then
                local content = string.format('**アイテム:** %s\n**数量:** %d\n\n', 
                    data.name or 'なし', data.count or 0)
                
                if data.metadata then
                    local oxygenPercent = 0
                    if data.metadata.maxOxygen and data.metadata.maxOxygen > 0 then
                        oxygenPercent = (data.metadata.oxygen / data.metadata.maxOxygen) * 100
                    end
                    
                    content = content .. string.format([[
**メタデータ:**
• 酸素残量: %.1f秒
• 最大酸素: %.1f秒
• 残量率: %.1f%%
• 耐久値: %.1f%%
• タイプ: %s
                    ]],
                        data.metadata.oxygen or 0,
                        data.metadata.maxOxygen or 0,
                        oxygenPercent,
                        data.metadata.durability or 0,
                        data.metadata.deviceType == 'refillable' and '補充型' or '使い捨て'
                    )
                else
                    content = content .. '**メタデータ:** なし（新品アイテム）'
                end
                
                lib.alertDialog({
                    header = string.format('📦 スロット%d', slot),
                    content = content,
                    centered = true
                })
            else
                lib.notify({
                    title = 'スロット確認',
                    description = string.format('スロット%dは空です', slot),
                    type = 'error'
                })
            end
        end, slot)
    end, false)
    
    -- プロップ調整
    RegisterCommand('propfix', function(_, args)
        if #attachedProps == 0 or not deviceConfig or not deviceConfig.props then
            lib.notify({
                title = 'プロップ調整',
                description = 'プロップが装着されていません',
                type = 'error'
            })
            return
        end
        
        local propIndex = tonumber(args[1]) or 1
        local type = tonumber(args[1]) and args[2] or args[1]
        local axis = tonumber(args[1]) and args[3] or args[2]
        local value = tonumber(tonumber(args[1]) and args[4] or args[3]) or 0.01
        
        -- 設定表示とクリップボードコピー
        if type == 'show' then
            local configText = string.format("-- %s プロップ設定\nprops = {\n", currentDevice)
            
            for i, propConfig in ipairs(deviceConfig.props) do
                local o = propConfig.offset
                local r = propConfig.rotation
                
                configText = configText .. string.format([[    {
        model = %s,
        bone = %d,
        offset = vector3(%.3f, %.3f, %.3f),
        rotation = vector3(%.1f, %.1f, %.1f),
        label = "%s"
    }%s
]], 
                    propConfig.model, propConfig.bone,
                    o.x, o.y, o.z, r.x, r.y, r.z, propConfig.label,
                    i < #deviceConfig.props and ',' or ''
                )
            end
            
            configText = configText .. "}"
            
            lib.setClipboard(configText)
            
            lib.alertDialog({
                header = string.format('⚙️ %s プロップ設定', currentDevice),
                content = "**✅ 設定をクリップボードにコピーしました！**\n\n**💡 Ctrl+V で config.lua に貼り付けできます！**",
                centered = true
            })
            
            lib.notify({
                title = '設定コピー',
                description = 'クリップボードにコピーしました',
                type = 'success'
            })
            return
        end
        
        -- プロップ一覧
        if type == 'list' then
            local content = string.format('**装着中:** %d個\n\n', #attachedProps)
            for i, propData in ipairs(attachedProps) do
                content = content .. string.format('%d. %s\n', 
                    i, propData.config.label)
            end
            
            lib.alertDialog({
                header = '📋 プロップ一覧',
                content = content,
                centered = true
            })
            return
        end
        
        -- ヘルプ
        if not type or not axis then
            lib.alertDialog({
                header = '🛠️ プロップ調整ヘルプ',
                content = [[
**基本コマンド:**
• `/propfix [番号] pos [軸] [値]` - 位置調整
• `/propfix [番号] rot [軸] [値]` - 回転調整

**便利機能:**
• `/propfix show` - 設定表示＋クリップボードコピー
• `/propfix list` - プロップ一覧

**使用例:**
• `/propfix 1 pos x 0.02` - ボンベを右に移動
• `/propfix 2 rot y 90` - マスクをY軸回転
• `/propfix pos z 0.05` - 1番目を上に移動

**軸の説明:**
• X軸: 左右 (+ = 右, - = 左)
• Y軸: 前後 (+ = 前, - = 後)
• Z軸: 上下 (+ = 上, - = 下)
                ]],
                centered = true
            })
            return
        end
        
        -- 実際の調整処理
        if propIndex < 1 or propIndex > #deviceConfig.props then
            lib.notify({
                title = 'エラー',
                description = string.format('プロップ%dは存在しません（1-%d）', propIndex, #deviceConfig.props),
                type = 'error'
            })
            return
        end
        
        local targetConfig = deviceConfig.props[propIndex]
        local o = targetConfig.offset
        local r = targetConfig.rotation
        
        if type == 'pos' then
            if axis == 'x' then
                targetConfig.offset = vector3(o.x + value, o.y, o.z)
            elseif axis == 'y' then
                targetConfig.offset = vector3(o.x, o.y + value, o.z)
            elseif axis == 'z' then
                targetConfig.offset = vector3(o.x, o.y, o.z + value)
            else
                lib.notify({
                    title = 'エラー',
                    description = '軸は x, y, z のいずれかを指定してください',
                    type = 'error'
                })
                return
            end
            
            DetachDeviceProps()
            Wait(100)
            AttachDeviceProps()
            
            lib.notify({
                title = '位置調整',
                description = string.format('%s: %s軸 %+.3f', targetConfig.label, axis:upper(), value),
                type = 'success'
            })
        
        elseif type == 'rot' then
            if axis == 'x' then
                targetConfig.rotation = vector3(r.x + value, r.y, r.z)
            elseif axis == 'y' then
                targetConfig.rotation = vector3(r.x, r.y + value, r.z)
            elseif axis == 'z' then
                targetConfig.rotation = vector3(r.x, r.y, r.z + value)
            else
                lib.notify({
                    title = 'エラー',
                    description = '軸は x, y, z のいずれかを指定してください',
                    type = 'error'
                })
                return
            end
            
            DetachDeviceProps()
            Wait(100)
            AttachDeviceProps()
            
            lib.notify({
                title = '回転調整',
                description = string.format('%s: %s軸 %+.1f度', targetConfig.label, axis:upper(), value),
                type = 'success'
            })
        else
            lib.notify({
                title = 'エラー',
                description = 'タイプは pos または rot を指定してください',
                type = 'error'
            })
        end
    end, false)
    
    -- プロップ再装着
    RegisterCommand('reattach', function()
        if isActive and deviceConfig and deviceConfig.props and #deviceConfig.props > 0 then
            DetachDeviceProps()
            Wait(100)
            AttachDeviceProps()
            lib.notify({
                title = '再装着',
                description = string.format('%d個のプロップを再装着しました', #attachedProps),
                type = 'success'
            })
        else
            lib.notify({
                title = '再装着',
                description = '酸素機器が装着されていません',
                type = 'error'
            })
        end
    end, false)

    RegisterCommand('forcedetach', function()
        if isActive then
            StopUsingDevice()
            lib.notify({
                title = 'デバッグ',
                description = '酸素機器を強制解除しました',
                type = 'success'
            })
        end
    end, false)
    
    -- デバッグヘルプ
    RegisterCommand('oxygenhelp', function()
        lib.alertDialog({
            header = '🛠️ 酸素システム デバッグコマンド',
            content = [[
**情報確認:**
• `/oxygeninfo` - 酸素システム詳細
• `/oxygencheck` - 水中判定確認
• `/checkslot [番号]` - スロット詳細

**プロップ調整:**
• `/propfix show` - 設定表示＋コピー
• `/propfix list` - プロップ一覧
• `/propfix [番号] pos/rot [軸] [値]` - 調整
• `/reattach` - プロップ再装着

**その他:**
• `/oxygenhelp` - このヘルプ

すべてのコマンドでox_libの美しいUIを使用します。
            ]],
            centered = true
        })
    end, false)
    
end
