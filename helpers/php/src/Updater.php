<?php

class Updater
{
  public static function update($args)
  {
    list($workingDirectory, $dependencyName, $dependencyVersion) = $args;

    // Change working directory to the one provided, this ensures that we
    // install dependencies into the working dir, rather than a vendor folder
    // in the root of the project
    $originalDir = getcwd();
    chdir($workingDirectory);

    $composerJson = json_decode(file_get_contents('composer.json'), true);

    // When encoding JSON in PHP, it'll escape forward slashes by default.
    // We're not expecting this transform from the original data, which means
    // by default we mutate the JSON that arrives back in the ruby portion of
    // Bump.
    //
    // The JSON_UNESCAPED_SLASHES option prevents escaping for forward
    // slashes, mitigating this issue.
    //
    // https://stackoverflow.com/questions/1580647/json-why-are-forward-slashes-escaped
    $composerJsonEncoded = json_encode($composerJson, JSON_UNESCAPED_SLASHES);

    file_put_contents('composer.json', $composerJsonEncoded);

    date_default_timezone_set("Europe/London");
    $io = new \Composer\IO\NullIO();
    $composer = \Composer\Factory::create($io);

    $installationManager = new BumpInstallationManager();

    $install = new \Composer\Installer(
      $io,
      $composer->getConfig(),
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
      ->setUpdate(true)
      ->setUpdateWhitelist([$dependencyName])
      ->setPreferStable(true)
      ->setWriteLock(true)
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
