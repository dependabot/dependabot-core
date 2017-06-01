<?php

require __DIR__ . '/../vendor/autoload.php';

use \Composer\Installer\InstallationManager;
use \Composer\Repository\RepositoryInterface;
use \Composer\DependencyResolver\Operation\InstallOperation;
use \Composer\DependencyResolver\Operation\UpdateOperation;
use \Composer\DependencyResolver\Operation\UninstallOperation;

class BumpInstallationManager extends InstallationManager
{
    private $installed = array();
    private $updated = array();
    private $uninstalled = array();

    public function install(RepositoryInterface $repo, InstallOperation $operation)
    {
        parent::install($repo, $operation);
        $this->installed[] = $operation->getPackage();
    }

    public function update(RepositoryInterface $repo, UpdateOperation $operation)
    {
        parent::update($repo, $operation);
        $this->updated[] = array($operation->getInitialPackage(), $operation->getTargetPackage());
    }

    public function uninstall(RepositoryInterface $repo, UninstallOperation $operation)
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

class UpdateChecker
{
  public static function get_latest_resolvable_version($args)
  {
    list($workingDirectory, $dependencyName) = $args;

    // Relax the version on the dependency we're bumping
    // TODO: Explain why we do this.
    $composerJson = json_decode(file_get_contents($workingDirectory . "/composer.json"), true);
    $composerJson["require"][$dependencyName] = "*";
    file_put_contents($workingDirectory . "/composer.json", json_encode($composerJson));

    date_default_timezone_set("Europe/London");
    $io = new \Composer\IO\NullIO();
    $composer = \Composer\Factory::create($io, $workingDirectory . '/composer.json');

    $installationManager = new BumpInstallationManager();
    $install = new \Composer\Installer(
      $io,
      $composer->getConfig(),
      $composer->getPackage(),
      $composer->getDownloadManager(),
      $composer->getRepositoryManager(),
      $composer->getLocker(),
      $installationManager,
      $composer->getEventDispatcher(),
      $composer->getAutoloadGenerator()
    );

    // For all potential options, see UpdateCommand in composer
    $install
      ->setDryRun(true)
      ->setUpdate(true)
      ->setUpdateWhitelist([$dependencyName])
      ->setPreferStable(true)
      ;

    $install->run();

    $installedPackages = $installationManager->getInstalledPackages();
    $updatedPackages = $installationManager->getUpdatedPackages();
    $uninstalledPackages = $installationManager->getUninstalledPackages();

    $updatedPackage = current(array_filter($installedPackages, function($package) use($dependencyName) {
      return $package->getName() == $dependencyName;
    }));

    if ($updatedPackage->getRepository()->getRepoConfig()["type"] == "vcs") {
      return NULL;
    } else {
      return preg_replace('/^([v])/', '', $updatedPackage->getPrettyVersion());
    }
  }
}
