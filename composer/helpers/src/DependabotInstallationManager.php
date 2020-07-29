<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\DependencyResolver\Operation\InstallOperation;
use Composer\DependencyResolver\Operation\UninstallOperation;
use Composer\DependencyResolver\Operation\UpdateOperation;
use Composer\Installer\InstallationManager;
use Composer\Package\PackageInterface;
use Composer\Repository\RepositoryInterface;

final class DependabotInstallationManager extends InstallationManager
{
    private array $installed = [];
    private array $updated = [];
    private array $uninstalled = [];

    public function install(RepositoryInterface $repo, InstallOperation $operation): void
    {
        parent::install($repo, $operation);
        $this->installed[] = $operation->getPackage();
    }

    public function update(RepositoryInterface $repo, UpdateOperation $operation): void
    {
        parent::update($repo, $operation);
        $this->updated[] = [$operation->getInitialPackage(), $operation->getTargetPackage()];
    }

    public function uninstall(RepositoryInterface $repo, UninstallOperation $operation): void
    {
        parent::uninstall($repo, $operation);
        $this->uninstalled[] = $operation->getPackage();
    }

    /**
     * @return PackageInterface[]
     */
    public function getInstalledPackages(): array
    {
        return $this->installed;
    }

    /**
     * @return PackageInterface[]
     */
    public function getUpdatedPackages(): array
    {
        return $this->updated;
    }

    /**
     * @return PackageInterface[]
     */
    public function getUninstalledPackages(): array
    {
        return $this->uninstalled;
    }
}
