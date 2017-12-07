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

    $composerJson = self::updateComposerJsonSection(
      $composerJson,
      "require",
      $dependencyName,
      $dependencyVersion
    );

    $composerJson = self::updateComposerJsonSection(
      $composerJson,
      "require-dev",
      $dependencyName,
      $dependencyVersion
    );

    // When encoding JSON in PHP, it'll escape forward slashes by default.
    // We're not expecting this transform from the original data, which means
    // by default we mutate the JSON that arrives back in the ruby portion of
    // Dependabot.
    //
    // The JSON_UNESCAPED_SLASHES option prevents escaping for forward
    // slashes, mitigating this issue.
    //
    // https://stackoverflow.com/questions/1580647/json-why-are-forward-slashes-escaped
    $jsonFile = new \Composer\Json\JsonFile('composer.json');
    $jsonFile->write($composerJson);

    date_default_timezone_set("Europe/London");
    $io = new \Composer\IO\NullIO();
    $composer = \Composer\Factory::create($io);

    $installationManager = new DependabotInstallationManager();

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


  // Make PHP rules match the rest of bump's libraries, keeping the
  // unconstrained version if they're defined and can be maintained. For
  // example:
  //
  //     Applying 3.1.5 -> 3.1.* => 3.1.*
  //     Applying 3.1.* -> 3.2.3 => 3.2.*
  //     Applying 3.1.* -> 4.0.0 => 4.0.*
  //     Applying 1.2.3-pre -> 4.1.2 => 4.1.2
  //
  // See more examples at https://github.com/composer/semver/blob/master/tests/VersionParserTest.php#L52
  public static function relaxVersionToUserPreference($existingDependencyVersion, $suggestedDependencyVersion) {
    $version_regex = '/[0-9]+(?:\.[a-zA-Z0-9]+)*/';
    preg_match($version_regex, $existingDependencyVersion, $matches);
    $precision = count(explode(".", $matches[0]));

    $suggestedVersionSegments = array_slice(explode(".", $suggestedDependencyVersion), 0, $precision);
    $newDependencyVersion = str_replace($matches[0], implode(".", $suggestedVersionSegments), $existingDependencyVersion);

    return $newDependencyVersion;
  }

  // Given a nested array representing a composer.json file, look for the given
  // dependency in the provided section (i.e., require, require-dev) and update
  // the composer data with the new version, before returning a composer
  // representation with the updated version.
  //
  // If the dependency doesn't exist in the section, will return the provided
  // composer JSON unaltered
  //
  // Note: Arrays are passed by value/copy, so this will leave the original composerJson untouched
  public static function updateComposerJsonSection($composerJson, $section, $dependencyName, $dependencyVersion) {
    if(isset($composerJson[$section][$dependencyName])) {
      $existingDependencyVersion = $composerJson[$section][$dependencyName];
      $newDependencyVersion = self::relaxVersionToUserPreference($existingDependencyVersion, $dependencyVersion);
      $composerJson[$section][$dependencyName] = $newDependencyVersion;
    }

    return $composerJson;
  }
}
