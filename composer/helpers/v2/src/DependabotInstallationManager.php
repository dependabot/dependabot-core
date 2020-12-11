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

    public function execute(RepositoryInterface $repo, array $operations, $devMode = true, $runScripts = true): void
    {
        foreach ($operations as $operation) {
            $method = $operation->getOperationType();
            // skipping download() step here for tests
            $this->$method($repo, $operation);
        }
    }

    public function install(RepositoryInterface $repo, InstallOperation $operation): void
    {
        $this->installed[] = $operation->getPackage();
    }

    public function update(RepositoryInterface $repo, UpdateOperation $operation): void
    {
        $this->updated[] = [$operation->getInitialPackage(), $operation->getTargetPackage()];
    }

    public function uninstall(RepositoryInterface $repo, UninstallOperation $operation): void
    {
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
