<?php
/**
 * Update rules for force_update.php.
 *
 * Located in the mt-proxy directory.
 *
 * Returns an array with three priority levels:
 *   - serials         — rules for specific serial numbers (highest priority)
 *   - models          — rules for specific device models
 *   - global_versions — global list of allowed versions (fallback)
 *
 * If an identifier (serial number or model) exists in the database,
 * the decision for that identifier is final — the global list
 * is not consulted.
 */

return [
    // Level 1: Specific serial numbers (highest priority)
    'serials' => [
        // 'SERIAL_NUMBER' => ['allowed_version_1', 'allowed_version_2'],
        // 'ABC123DEF456' => ['7.24.5'],
        // 'SN9876543210' => ['6.49.23'],
    ],

    // Level 2: Specific device models
    'models' => [
        // 'MODEL' => ['allowed_version_1', 'allowed_version_2'],
        // 'hEX lite'     => ['6.49.23'],
        // 'RB4011iGS+RM' => ['7.23.8'],
    ],

    // Level 3: Global list of allowed versions
    // (fallback for devices not found in the database)
    'global_versions' => [
        '6.49.23',
        '7.24.5',
        '7.23.8',
    ],
];
