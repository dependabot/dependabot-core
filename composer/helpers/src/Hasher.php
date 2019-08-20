<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\Package\Locker;

class Hasher
{
    /**
     * @param array $args
     *
     * @throws \RuntimeException
     *
     * @return string
     */
    public static function getContentHash(array $args): string
    {
        [$workingDirectory] = $args;

        $config = $workingDirectory . '/composer.json';

        $contents = file_get_contents($config);

        if (!is_string($contents)) {
            throw new \RuntimeException(sprintf(
                'Failed to load contents of "%s".',
                $config
            ));
        }

        return Locker::getContentHash($contents);
    }
}
