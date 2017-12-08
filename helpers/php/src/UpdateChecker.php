<?php

require __DIR__ . '/../vendor/autoload.php';

use \Composer\Installer\InstallationManager;
use \Composer\Repository\RepositoryInterface;
use \Composer\DependencyResolver\Operation\InstallOperation;
use \Composer\DependencyResolver\Operation\UpdateOperation;
use \Composer\DependencyResolver\Operation\UninstallOperation;

class DependabotInstallationManager extends InstallationManager
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
    list($workingDirectory, $dependencyName, $githubToken) = $args;

    date_default_timezone_set("Europe/London");
    $io = new \Composer\IO\NullIO();
    $composer = \Composer\Factory::create($io, $workingDirectory . '/composer.json');

    $config = $composer->getConfig();
    $config->merge(array('config' => array('github-oauth' => array('github.com' => $githubToken))));
    $io->loadConfiguration($config);

    $installationManager = new DependabotInstallationManager();
    $install = new \Composer\Installer(
      $io,
      $config,
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
      ->setExecuteOperations(false)
      ->setDumpAutoloader(false)
      ->setRunScripts(false)
      ->setIgnorePlatformRequirements(true)
      ;

    $install->run();

    $installedPackages = $installationManager->getInstalledPackages();

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
