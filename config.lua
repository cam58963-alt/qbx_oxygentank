Config = {}

-- デバッグモード（本番環境では false に変更）
Config.Debug = false

-- デフォルトの潜水時間
Config.DefaultUnderwaterTime = 10.0

-- 酸素機器の種類別設定
Config.OxygenDevices = {
    -- EMS/専門ダイバー向け（補充型・タンク＋マスク）
    ['oxygen_tank'] = {
        type = 'refillable',
        label = '酸素ボンベ',
        -- 🔒 使用を許可するJOBのリスト
        allowedJobs = {
            'ambulance',    -- EMS
            -- 'coastguard' -- 沿岸警備隊（カスタムJOBがあれば）
        },
        maxOxygen = 300,                -- 最大酸素量（秒）
        consumeRate = 0.8,              -- 消費速度（秒/秒）
        refillRate = 0,               -- 地上回復速度（秒/秒）
        warningLevel = 60,              -- 警告レベル（秒）
        criticalLevel = 30,             -- 危険レベル（秒）
        underwaterTime = 450.0,         -- ゲーム内潜水時間延長
        
        -- 複数プロップ設定
        props = {
            {   -- 背中の酸素タンク
                model = `p_s_scuba_tank_s`,
                bone = 24818,           -- SKEL_Spine_Root
                offset = vector3(-0.280, -0.240, 0.010),
                rotation = vector3(0.0, 90.0, 180.0),
                label = "酸素タンク"
            },
            {   -- 顔のダイビングマスク
                model = `p_d_scuba_mask_s`,
                bone = 12844,           -- SKEL_Head
                offset = vector3(0.010, -0.010, 0.000),
                rotation = vector3(180.0, 270.0, 0.0),
                label = "ダイビングマスク"
            }
        },
        
        canRefillAtStation = true,
        autoRefillOnSurface = false,
        showUI = true
    },
    
    -- 一般向け（使い捨て・マスクのみ）
    ['rebreather'] = {
        type = 'disposable',
        label = 'リブリーザー',
        -- 🔓 空配列 = 誰でも使用可能
        allowedJobs = {},
        maxOxygen = 150,
        consumeRate = 1.0,
        refillRate = 0,                 -- 使い捨てなので回復なし
        warningLevel = 45,
        criticalLevel = 20,
        underwaterTime = 200.0,
        
        props = {
            {
                model = `p_d_scuba_mask_s`,
                bone = 12844,
                offset = vector3(0.010, -0.010, 0.000),
                rotation = vector3(180.0, 270.0, 0.0),
                label = "リブリーザーマスク"
            }
        },
        
        canRefillAtStation = false,
        autoRefillOnSurface = false,
        showUI = true
    },
    
    -- 初心者/緊急用（使い捨て・プロップなし）
    ['oxygen_mask'] = {
        type = 'disposable',
        label = '簡易酸素マスク',
        -- 🔓 空配列 = 誰でも使用可能
        allowedJobs = {},
        maxOxygen = 75,
        consumeRate = 1.3,
        refillRate = 0,
        warningLevel = 25,
        criticalLevel = 10,
        underwaterTime = 120.0,
        
        props = {},                     -- プロップなし（軽量設計）
        
        canRefillAtStation = false,
        autoRefillOnSurface = false,
        showUI = true
    }
}

Config.RefillStations = {
    {
        coords = vector3(1127.56, -1581.16, 33.86),
        heading = 0.0,
        label = '酸素補充ステーション',
        
        prop = {
            enabled = true,
            model = `prop_compressor_01`,--`prop_gascyl_02a`,
            offset = vector3(0.0, 0.0, 0.0),
            rotation = vector3(0.0, 0.0, 270.0)
        },
        
        blip = {
            enabled = false,
            sprite = 780,
            color = 3,
            scale = 0.8,
            name = '酸素補充ステーション'
        },
        
        targetZone = {
            size = vec3(3, 3, 3),
            rotation = 0
        }
    },
}


-- UI設定
Config.UI = {
    position = 'right-center',
    updateInterval = 1000
}

-- 通知メッセージ
Config.Notifications = {
    equipped = '%s を装着しました',
    removed = '%s を外しました',
    empty = '%s の酸素が尽きました！',
    consumed = '%s を使い切りました',
    warning = '酸素残量が少なくなっています（残り %.0f秒）',
    critical = '酸素が危険なレベルです！（残り %.0f秒）',
    noDevice = '対応する酸素機器を持っていません',
    refilled = '酸素ボンベを満タンに補充しました',
    refillProgress = '酸素ボンベを補充中...',
    alreadyFull = '酸素ボンベは既に満タンです',
    cannotRefill = 'この機器は補充できません',
    alreadyEquipped = '既に酸素機器を装着しています'
}
