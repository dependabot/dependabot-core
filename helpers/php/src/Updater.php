<?php

declare(strict_types=1);

namespace Dependabot\PHP;

use Composer\Factory;
use Composer\Installer;
use Composer\IO\NullIO;

class Updater
{
    public static function update($args)
    {
        [$workingDirectory, $dependencyName, $dependencyVersion, $githubToken] = $args;

        // Change working directory to the one provided, this ensures that we
        // install dependencies into the working dir, rather than a vendor folder
        // in the root of the project
        $originalDir = getcwd();
        chdir($workingDirectory);
        $io = new NullIO();
        $composer = Factory::create($io);

        $config = $composer->getConfig();

        if ($githubToken) {
            $config->merge(['config' => ['github-oauth' => ['github.com' => $githubToken]]]);
            $io->loadConfiguration($config);
        }

        $install = new Installer(
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
            ->setIgnorePlatformRequirements(true);

        $install->run();

        $result = [
            'composer.json' => file_get_contents('composer.json'),
            'composer.lock' => file_get_contents('composer.lock'),
        ];

        chdir($originalDir);

        return $result;
    }
}
