<?php

declare(strict_types=1);

namespace Dependabot\PHP;

use Composer\DependencyResolver\Operation\InstallOperation;
use Composer\DependencyResolver\Operation\UninstallOperation;
use Composer\DependencyResolver\Operation\UpdateOperation;
use Composer\Installer\InstallationManager;
use Composer\Repository\RepositoryInterface;

class DependabotInstallationManager extends InstallationManager
{
    private $installed = [];
    private $updated = [];
    private $uninstalled = [];

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

    public function getInstalledPackages()
    {
        return $this->installed;
    }

    public function getUpdatedPackages()
    {
        return $this->updated;
    }

    public function getUninstalledPackages()
    {
        return $this->uninstalled;
    }
}
