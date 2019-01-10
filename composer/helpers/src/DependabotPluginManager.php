<?php

declare(strict_types=1);

namespace Dependabot\PHP;

use Composer\Package\PackageInterface;
use Composer\Plugin\PluginManager;

class DependabotPluginManager extends PluginManager
{
    public function registerPackage(PackageInterface $package, $failOnMissingClasses = false): void
    {
        // This package does some setup for PHP_CodeSniffer, but errors out the
        // install if Symfony isn't installed (which it won't be for a lockfile
        // only install run). Safe to ignore
        if (strpos($package->getName(), 'phpcodesniffer') !== false) {
            return;
        }

        parent::registerPackage($package, $failOnMissingClasses);
    }
}
