<?php

declare(strict_types=1);

namespace Dependabot\PHP;

use Composer\Factory;

class Hasher
{
    public static function getContentHash(array $args): ?string
    {
        [$workingDirectory] = $args;

        $io = new ExceptionIO();
        $composer = Factory::create($io, $workingDirectory . '/composer.json');
        $locker = $composer->getLocker();

        return $locker->getContentHash(file_get_contents(Factory::getComposerFile()));
    }
}
