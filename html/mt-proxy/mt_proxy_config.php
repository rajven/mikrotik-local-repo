<?php
/**
 * mt_proxy_config.php - general proxy configuration and fallbacks.
 */
$routeros_dir = rtrim($_SERVER['DOCUMENT_ROOT'], '/') . '/routeros';

return [
    'upstream_base'   => 'https://upgrade.mikrotik.com/routeros/',
    'connect_timeout' => 2,
    'total_timeout'   => 3,
    'routeros_dir'    => $routeros_dir,

    // ============================================================================= 
    // Security: checking the secret token 
    // ============================================================================= 
    'WARMUP_TOKEN' => 'CHANGE_ME', // Replace with your secret token

    // ----- Hardcoded fallback of allowed versions ----- 
    // Use force_update.php as the LAST stand: 
    // if global_versions in the database are empty AND mt_proxy_rules.php is missing/empty.
    'allowed_versions_hardcoded' => [
        '6.49.23',
        '7.24.5',
        '7.23.8',
    ],

    // ----- fallback -----
    'fallbacks' => [
        // v6
        'NEWEST6.stable'     => "6.49.23 1791389116\n",
        'NEWESTa6.stable'    => "6.49.23 1791389116\n",
        'NEWEST6.long-term'  => "6.49.23 1791389116\n",
        'NEWESTa6.long-term' => "6.49.23 1791389116\n",
        'NEWEST6.upgrade'    => "7.12.1 1700221125\n",
        'NEWESTa6.upgrade'   => "7.23.8 1791452776\n",
        // v7
        'NEWEST7.stable'     => "7.12.1 1700221125\n",
        'NEWEST7.long-term'  => "7.12.1 1700221125\n",
        'NEWESTa7.stable'    => "7.24.5 1790691687\n",
        'NEWESTa7.long-term' => "7.23.8 1791452776\n",
    ],

    // ----- ROS v6 -----
    'v6' => [
        'log_prefix'      => '[mt-upgrade-proxy-v6]',
        'cache_file'      => $routeros_dir . '/ros6.version.cache',
        'default_version' => '6.49.23',
        'user_agent'      => 'RouterOS ',
        'local_stable'    => $routeros_dir . '/LATEST.6',
        'local_longterm'  => $routeros_dir . '/LATEST.6fix',
    ],

    // ----- ROS v7 -----
    'v7' => [
        'log_prefix'           => '[mt-upgrade-proxy-v7]',
        'cache_file'           => $routeros_dir . '/ros7.version.cache',
        'default_version'      => '7.23.8',
        'user_agent'           => 'RouterOS ',
        'local_stable'         => $routeros_dir . '/NEWEST7.stable',
        'local_longterm'       => $routeros_dir . '/NEWEST7.stable',
        'local_stable_afile'   => $routeros_dir . '/NEWESTa7.stable',
        'local_longterm_afile' => $routeros_dir . '/NEWESTa7.long-term',
    ],
];
