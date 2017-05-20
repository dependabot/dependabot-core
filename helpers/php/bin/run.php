<?php

require dirname(__FILE__) . '/../src/UpdateChecker.php';
require dirname(__FILE__) . '/../src/Updater.php';

// Get details of the process to run from STDIN. It will have a `function` and
// an `args` method, as passed in by UpdateCheckers::Php
$request = json_decode(file_get_contents("php://stdin"));

switch ($request->function) {
    case "update":
        Updater::update($request->args);
        break;
    case "get_latest_resolvable_version":
        UpdaterChecker::get_latest_resolvable_version($request->args);
        break;
    default:
        fwrite(STDOUT, "{\"error\": \"Invalid function ".$request->{'function'}."\" }");
        exit(1);
}

?>
