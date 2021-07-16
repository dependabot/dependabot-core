<?php

namespace Dependabot\Composer;

use Composer\Package\PackageInterface;
use Composer\Installer\MetapackageInstaller;
use Composer\Installer\BinaryPresenceInterface;

class LibraryInstaller extends MetapackageInstaller implements BinaryPresenceInterface {
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
    public function ensureBinariesPresence(PackageInterface $package) {
        return;
    }
}
