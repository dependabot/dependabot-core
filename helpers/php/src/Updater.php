<?php

class Updater
{
  public static function update($args)
  {
    list($workingDirectory, $dependencyName, $dependencyVersion, $githubToken) = $args;

    // Change working directory to the one provided, this ensures that we
    // install dependencies into the working dir, rather than a vendor folder
    // in the root of the project
    $originalDir = getcwd();
    chdir($workingDirectory);
    date_default_timezone_set("Europe/London");
    $io = new \Composer\IO\NullIO();
    $composer = \Composer\Factory::create($io);

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
      $composer->getInstallationManager(),
      $composer->getEventDispatcher(),
      $composer->getAutoloadGenerator()
    );

    // For all potential options, see UpdateCommand in composer
    $install
      ->setWriteLock(true)
      ->setUpdate(true)
      ->setUpdateWhitelist([$dependencyName])
      ->setExecuteOperations(false)
      ->setDumpAutoloader(false)
      ->setRunScripts(false)
      ->setIgnorePlatformRequirements(true)
      ;

    $install->run();

    $result = [
      "composer.json" => file_get_contents('composer.json'),
      "composer.lock" => file_get_contents('composer.lock'),
    ];

    chdir($originalDir);

    return $result;
  }
}
