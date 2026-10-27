fx_version 'cerulean'
game 'gta5'

author 'otonashi'
description '潜水用酸素ボンベ'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/playerdata.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'qbx_core',
    'ox_lib',
    'ox_inventory'
}

lua54 'yes'
