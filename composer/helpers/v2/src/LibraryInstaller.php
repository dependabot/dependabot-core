<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\Installer\BinaryPresenceInterface;
use Composer\Installer\NoopInstaller;
use Composer\Package\PackageInterface;

class LibraryInstaller extends NoopInstaller implements BinaryPresenceInterface
{
    /**
     * {@inheritDoc}
     */
    public function supports($packageType)
    {
        return $packageType === 'library';
    }

    /**
     * {@inheritDoc}
     */
    public function ensureBinariesPresence(PackageInterface $package): void
    {
    }
}
