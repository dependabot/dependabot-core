<?php

declare(strict_types=1);

namespace Dependabot\PHP;

require __DIR__ . '/../vendor/autoload.php';

// Get details of the process to run from STDIN. It will have a `function`
// and an `args` method, as passed in by UpdateCheckers::Php
$request = json_decode(file_get_contents('php://stdin'), true);

// Increase the default memory limit. Calling `composer update` is otherwise
// vulnerable to scenarios where there are unconstrained versions, resulting in
// it checking huge numbers of dependency combinations and causing OOM issues.
ini_set('memory_limit', '1900M');

date_default_timezone_set('Europe/London');

// This storage is freed on error (case of allowed memory exhausted)
$memory = str_repeat('*', 1024 * 1024);

register_shutdown_function(function (): void {
    $memory = null;
    $error = error_get_last();
    if (null !== $error && strpos($error['message'], 'Allowed memory size') === 0) {
        fwrite(STDOUT, json_encode(['error' => $error['message']]));
    }
});

try {
    switch ($request['function']) {
        case 'update':
            $updatedFiles = Updater::update($request['args']);
            fwrite(STDOUT, json_encode(['result' => $updatedFiles]));
            break;
        case 'get_latest_resolvable_version':
            $latestVersion = UpdateChecker::getLatestResolvableVersion($request['args']);
            fwrite(STDOUT, json_encode(['result' => $latestVersion]));
            break;
        case 'get_content_hash':
            $content_hash = Hasher::getContentHash($request['args']);
            fwrite(STDOUT, json_encode(['result' => $content_hash]));
            break;
        default:
            fwrite(STDOUT, '{"error": "Invalid function ' . $request['function'] . '" }');
            exit(1);
    }
} catch (\Exception $e) {
    fwrite(STDOUT, json_encode(['error' => $e->getMessage()]));
    exit(1);
}
