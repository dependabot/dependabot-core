<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\IO\NullIO;

final class ExceptionIO extends NullIO
{
    private bool $raise_next_error = false;

    public function writeError($messages, $newline = true, $verbosity = self::NORMAL): void
    {
        if (is_array($messages)) {
            return;
        }
        if ($this->raise_next_error) {
            throw new \RuntimeException('Your requirements could not be resolved to an installable set of packages.' . $messages);
        }
        if (strpos($messages, 'Your requirements could not be resolved') !== false) {
            $this->raise_next_error = true;
        }
    }
}
