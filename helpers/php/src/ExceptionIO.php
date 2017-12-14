<?php

declare(strict_types=1);

namespace Dependabot\PHP;

use Composer\IO\NullIO;

class ExceptionIO extends NullIO
{
    public function writeError($messages, $newline = true, $verbosity = self::NORMAL): void
    {
        if (strpos($messages, 'Your requirements could not be resolved') !== false) {
            throw new \RuntimeException('Requirements could not be resolved');
        } elseif (strpos($messages, 'bytes exhausted') !== false) {
            throw new \RuntimeException('Out of memory!');
        }
    }
}
