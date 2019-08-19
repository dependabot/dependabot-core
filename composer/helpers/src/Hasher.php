<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\Package\Locker;

class Hasher
{
    public static function getContentHash(array $args): string
    {
        [$workingDirectory] = $args;

        $config = $workingDirectory . '/composer.json';

        return Locker::getContentHash(file_get_contents($config));
    }
}
