<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\DependencyResolver\Operation\InstallOperation;
use Composer\DependencyResolver\Operation\UninstallOperation;
use Composer\DependencyResolver\Operation\UpdateOperation;
use Composer\Installer\InstallationManager;
use Composer\Package\PackageInterface;
use Composer\Repository\InstalledRepositoryInterface;
use React\Promise\PromiseInterface;

final class DependabotInstallationManager extends InstallationManager
{
    private array $installed = [];
    private array $updated = [];
    private array $uninstalled = [];

    public function execute(InstalledRepositoryInterface $repo, array $operations, $devMode = true, $runScripts = true): void
    {
        foreach ($operations as $operation) {
            $method = $operation->getOperationType();
            // NOTE: skipping download() step
            $this->$method($repo, $operation);
        }
    }

    public function install(InstalledRepositoryInterface $repo, InstallOperation $operation): ?PromiseInterface
    {
        $this->installed[] = $operation->getPackage();

        return null;
    }

    public function update(InstalledRepositoryInterface $repo, UpdateOperation $operation): ?PromiseInterface
    {
        $this->updated[] = [$operation->getInitialPackage(), $operation->getTargetPackage()];

        return null;
    }

    public function uninstall(InstalledRepositoryInterface $repo, UninstallOperation $operation): ?PromiseInterface
    {
        $this->uninstalled[] = $operation->getPackage();

        return null;
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
