<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\Factory;
use Composer\Package\Locker;

class Hasher
{
    public static function getContentHash(array $args): ?string
    {
        [$workingDirectory] = $args;

        $config = $workingDirectory . '/composer.json';

        $io = new ExceptionIO();
        $composer = Factory::create($io, $config);
        $locker = $composer->getLocker();

        return Locker::getContentHash(file_get_contents($config));
    }
}
