-- 補充型：プロフェッショナル用酸素ボンベ
['oxygen_tank'] = {
    label = '酸素ボンベ',
    weight = 5000,
    stack = false,
    close = true,
    description = '高性能な補充型酸素供給装置。残量はインベントリのゲージで確認できます。主にEMSや専門ダイバーが使用。',
    client = {
        image = 'oxygen_tank.png'
    }
},

-- 使い捨て型：一般向けリブリーザー
['rebreather'] = {
    label = 'リブリーザー',
    weight = 2000,
    stack = false,
    close = true,
    description = '使い捨ての携帯型呼吸装置。約2.5分間の潜水が可能。酸素が尽きると自動的に廃棄される。',
    client = {
        image = 'rebreather.png'
    }
},

-- 使い捨て型：エントリーモデル
['oxygen_mask'] = {
    label = '簡易酸素マスク',
    weight = 800,
    stack = false,
    close = true,
    description = '使い捨ての簡易酸素マスク。約1.2分間の短時間潜水用。軽量で安価だが持続時間が短い。',
    client = {
        image = 'oxygen_mask.png'
    }
}
