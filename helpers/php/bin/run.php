<?php

require dirname(__FILE__) . '/../src/UpdateChecker.php';
require dirname(__FILE__) . '/../src/Updater.php';

// Get details of the process to run from STDIN. It will have a `function`
// and an `args` method, as passed in by UpdateCheckers::Php
$request = json_decode(file_get_contents("php://stdin"));

// Increase the default memory limit. Calling `composer update` is otherwise
// vulnerable to scenarios where there are unconstrained versions, resulting in
// it checking huge numbers of dependency combinations and causing OOM issues.
ini_set('memory_limit','256M');

switch ($request->function) {
    case "update":
        $updatedFiles = Updater::update($request->args);
        fwrite(STDOUT, json_encode(["result" => $updatedFiles]));
        break;
    case "get_latest_resolvable_version":
        $latestVersion = UpdateChecker::get_latest_resolvable_version($request->args);
        fwrite(STDOUT, json_encode(["result" => $latestVersion]));
        break;
    default:
        fwrite(STDOUT, "{\"error\": \"Invalid function ".$request->{'function'}."\" }");
        exit(1);
}
