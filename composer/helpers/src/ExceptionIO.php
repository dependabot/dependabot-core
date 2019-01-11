<?php

declare(strict_types=1);

namespace Dependabot\PHP;

use Composer\IO\NullIO;

class ExceptionIO extends NullIO
{
    private $raise_next_error = false;

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
