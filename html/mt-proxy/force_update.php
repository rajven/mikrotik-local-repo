<?php
// Set the content type so MikroTik receives plain text without any HTML
header('Content-Type: text/plain; charset=utf-8');

/**
 * Safely retrieve a GET parameter
 */
function getParam($key, $default = '') {
    if (isset($_GET[$key])) {
        $val = trim($_GET[$key]);
        // Explicitly check for an empty string instead of using empty()
        return ($val !== '') ? $val : $default;
    }
    return $default;
}

// Retrieve parameters from MikroTik
$requestedVersion = getParam('new_version', '');
$requestedSerial  = getParam('serial', '');
$requestedModel   = getParam('model', '');

// If no version is provided, deny the update immediately
if ($requestedVersion === '') {
    echo 'DISABLED';
    exit;
}

// ============================================================
// Update rules configuration (external file in the same directory)
// ============================================================

$rulesFile = __DIR__ . '/mt_proxy_rules.php';

if (!is_file($rulesFile) || !is_readable($rulesFile)) {
    // Configuration is unavailable — deny the update to avoid allowing updates for everyone
    echo 'DISABLED';
    exit;
}

$updateRules = require $rulesFile;

if (!is_array($updateRules)) {
    echo 'DISABLED';
    exit;
}

// Default values — protect against an incomplete configuration
$serialsRules = (isset($updateRules['serials'])         && is_array($updateRules['serials']))         ? $updateRules['serials']         : [];
$modelsRules  = (isset($updateRules['models'])          && is_array($updateRules['models']))          ? $updateRules['models']          : [];
$globalRules  = (isset($updateRules['global_versions']) && is_array($updateRules['global_versions'])) ? $updateRules['global_versions'] : [];

$isAllowed    = false;
$decisionMade = false; // Flag indicating whether a final decision has been made based on a known identifier

// Step 1: Check the serial number
if ($requestedSerial !== '' && array_key_exists($requestedSerial, $serialsRules)) {
    $decisionMade = true; // Serial number exists in the database; the decision is final
    $isAllowed    = in_array($requestedVersion, $serialsRules[$requestedSerial], true);
}

// Step 2: Check the model (ONLY if the serial number is not found in the database)
if ($decisionMade === false && $requestedModel !== '' && array_key_exists($requestedModel, $modelsRules)) {
    $decisionMade = true; // Model exists in the database; the decision is final
    $isAllowed    = in_array($requestedVersion, $modelsRules[$requestedModel], true);
}

// Step 3: Check the global list (ONLY if neither the serial number nor the model is found in the database)
if ($decisionMade === false) {
    $isAllowed = in_array($requestedVersion, $globalRules, true);
}

// ============================================================
// Final output
// ============================================================

echo $isAllowed ? 'ENABLED' : 'DISABLED';
