local QBX = exports.qbx_core

-- ✅ JOBチェック関数
local function checkJobPermission(source, itemName)
    local deviceConfig = Config.OxygenDevices[itemName]
    if not deviceConfig then return false end
    
    -- allowedJobsが設定されていない、または空の場合は誰でも使用可能
    if not deviceConfig.allowedJobs or #deviceConfig.allowedJobs == 0 then
        return true
    end
    
    local Player = QBX:GetPlayer(source)
    if not Player then return false end
    
    local playerJob = Player.PlayerData.job.name
    
    -- 許可されたJOBリストをチェック
    for _, allowedJob in ipairs(deviceConfig.allowedJobs) do
        if playerJob == allowedJob then
            if Config.Debug then
                print(string.format('[JOB許可] %s: %s (JOB: %s)', GetPlayerName(source), itemName, playerJob))
            end
            return true
        end
    end
    
    if Config.Debug then
        print(string.format('[JOB拒否] %s: %s (JOB: %s)', GetPlayerName(source), itemName, playerJob))
    end
    
    return false
end

-- 各酸素機器を使用可能アイテムとして登録（JOB制限対応版）
for itemName, deviceConfig in pairs(Config.OxygenDevices) do
    exports.qbx_core:CreateUseableItem(itemName, function(source, item)
        
        -- ✅ JOB制限チェック
        if not checkJobPermission(source, itemName) then
            -- クライアントにエラー通知を送信
            TriggerClientEvent('qbx_oxygentank:client:jobRestricted', source, itemName)
            return
        end
        
        -- JOB制限をクリア、通常処理を実行
        TriggerClientEvent('qbx_oxygentank:client:useDevice', source, {
            name = item.name,
            slot = item.slot,
            metadata = item.metadata or {}
        })
    end)
end

-- メタデータ初期化関数
local function initializeMetadata(source, itemName, slot)
    local deviceConfig = Config.OxygenDevices[itemName]
    if not deviceConfig then return false end
    
    local metadata = {
        oxygen = deviceConfig.maxOxygen,
        maxOxygen = deviceConfig.maxOxygen,
        deviceType = deviceConfig.type,
        durability = 100                -- ox_inventoryの耐久バー用
    }
    
    exports.ox_inventory:SetMetadata(source, slot, metadata)
    return metadata
end

-- アイテムデータ取得コールバック
lib.callback.register('qbx_oxygentank:server:getDeviceData', function(source, itemName, slot)
    local Player = QBX:GetPlayer(source)
    if not Player then return false, 0, 0 end
    
    -- 指定スロットのアイテム取得
    local item = exports.ox_inventory:GetSlot(source, slot)
    if not item or item.name ~= itemName then
        return false, 0, 0
    end
    
    local deviceConfig = Config.OxygenDevices[itemName]
    if not deviceConfig then return false, 0, 0 end
    
    -- メタデータの初期化チェック
    local metadata = item.metadata
    if not metadata or not metadata.oxygen then
        metadata = initializeMetadata(source, itemName, slot)
    end
    
    return true, metadata.oxygen, metadata.maxOxygen
end)

-- 酸素残量の更新（厳格な安全チェック版）
RegisterNetEvent('qbx_oxygentank:server:updateOxygen', function(itemName, slot, oxygenLevel)
    local src = source
    local Player = QBX:GetPlayer(src)
    if not Player then return end
    
    -- ✅ 【安全装置】指定スロットのアイテムが本当に目的のものか確認
    local item = exports.ox_inventory:GetSlot(src, slot)
    if not item or item.name ~= itemName then 
        if Config.Debug then
            print(string.format('⚠️ [安全ブロック] プレイヤー%d: スロット%d のアイテムが %s ではないため、メタデータ上書きをブロックしました', 
                src, slot, itemName))
        end
        return -- 別のアイテムを上書きしないよう即座に終了
    end
    
    local deviceConfig = Config.OxygenDevices[itemName]
    if not deviceConfig then return end
    
    -- 残量を適切な範囲に制限
    oxygenLevel = math.max(0, math.min(oxygenLevel, deviceConfig.maxOxygen))
    local durabilityPercent = math.floor((oxygenLevel / deviceConfig.maxOxygen) * 100)
    
    -- メタデータ更新（安全確認後）
    local metadata = item.metadata or {}
    metadata.oxygen = oxygenLevel
    metadata.maxOxygen = deviceConfig.maxOxygen
    metadata.deviceType = deviceConfig.type
    metadata.durability = durabilityPercent
    
    exports.ox_inventory:SetMetadata(src, slot, metadata)
    
    if Config.Debug then
        print(string.format('[安全更新] プレイヤー%d: %s スロット%d 残量%.1f秒', src, itemName, slot, oxygenLevel))
    end
end)

-- 使い捨て機器の消費処理（厳格な安全チェック版）
RegisterNetEvent('qbx_oxygentank:server:consumeDevice', function(itemName, slot)
    local src = source
    local Player = QBX:GetPlayer(src)
    if not Player then return end
    
    local deviceConfig = Config.OxygenDevices[itemName]
    if not deviceConfig or deviceConfig.type ~= 'disposable' then return end
    
    -- ✅ 【安全装置】指定スロットのアイテムが本当に目的のものか確認
    local item = exports.ox_inventory:GetSlot(src, slot)
    local success = false
    
    if item and item.name == itemName then
        -- スロットが一致：安全にそのスロットから削除
        success = exports.ox_inventory:RemoveItem(src, itemName, 1, nil, slot)
        if Config.Debug then
            print(string.format('[安全削除] プレイヤー%d: %s をスロット%d から消費', src, itemName, slot))
        end
    else
        -- スロット不一致：インベントリ全体から該当アイテムを検索して削除
        success = exports.ox_inventory:RemoveItem(src, itemName, 1)
        if Config.Debug then
            print(string.format('⚠️ [フォールバック] プレイヤー%d: スロット%d に %s がないため、インベントリ全体から検索して消費', 
                src, slot, itemName))
        end
    end
    
    if success then
        TriggerClientEvent('ox_inventory:client:ItemBox', src, QBX.Shared.Items[itemName], 'remove')
        TriggerClientEvent('qbx_oxygentank:client:deviceConsumed', src, itemName)
    end
end)

-- 酸素補充処理
RegisterNetEvent('qbx_oxygentank:server:refillOxygen', function(itemName, slot)
    local src = source
    local Player = QBX:GetPlayer(src)
    if not Player then return end
    
    local deviceConfig = Config.OxygenDevices[itemName]
    if not deviceConfig or not deviceConfig.canRefillAtStation then return end
    
    -- アイテム存在確認
    local item = exports.ox_inventory:GetSlot(src, slot)
    if not item or item.name ~= itemName then return end
    
    -- メタデータを満タンに更新
    local metadata = item.metadata or {}
    metadata.oxygen = deviceConfig.maxOxygen
    metadata.maxOxygen = deviceConfig.maxOxygen
    metadata.deviceType = deviceConfig.type
    metadata.durability = 100
    
    exports.ox_inventory:SetMetadata(src, slot, metadata)
    
    TriggerClientEvent('qbx_oxygentank:client:oxygenRefilled', src, itemName, slot)
    
    if Config.Debug then
        print(string.format('[補充完了] スロット%d %s が満タンになりました', slot, itemName))
    end
end)

-- デバッグ用コールバック
if Config.Debug then
    lib.callback.register('qbx_oxygentank:debug:getSlotInfo', function(source, slot)
        local item = exports.ox_inventory:GetSlot(source, slot)
        
        if item then
            return true, {
                name = item.name,
                count = item.count,
                metadata = item.metadata
            }
        else
            return false, {}
        end
    end)
end

-- サーバー起動時のログ
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        print('^2[QBX Oxygen System]^7 サーバー側が正常に開始されました')
        print('^3[QBX Oxygen System]^7 メタデータ管理システムで起動')
        
        local deviceCount = 0
        for _ in pairs(Config.OxygenDevices) do
            deviceCount = deviceCount + 1
        end
        print('^3[QBX Oxygen System]^7 登録された機器数: ' .. deviceCount)
    end
end)

