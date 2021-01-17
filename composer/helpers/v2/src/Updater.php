<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\DependencyResolver\Request;
use Composer\Factory;
use Composer\Installer;
use Composer\Util\Filesystem;

final class Updater
{
    /**
     * @throws \RuntimeException
     */
    public static function update(array $args): array
    {
        [$workingDirectory, $dependencyName, $dependencyVersion, $gitCredentials, $registryCredentials] = $args;

        // Change working directory to the one provided, this ensures that we
        // install dependencies into the working dir, rather than a vendor folder
        // in the root of the project
        $originalDir = getcwd();

        if (!is_string($originalDir)) {
            throw new \RuntimeException('Failed determining the current working directory.');
        }

        chdir($workingDirectory);

        $io = new ExceptionIO();
        $composer = Factory::create($io);
        $config = $composer->getConfig();
        $httpBasicCredentials = [];

        $pm = new DependabotPluginManager($io, $composer, null, false);
        $composer->setPluginManager($pm);
        $pm->loadInstalledPlugins();

        foreach ($gitCredentials as &$cred) {
            $httpBasicCredentials[$cred['host']] = [
                'username' => $cred['username'],
                'password' => $cred['password'],
            ];
        }

        foreach ($registryCredentials as &$cred) {
            $httpBasicCredentials[$cred['registry']] = [
                'username' => $cred['username'],
                'password' => $cred['password'],
            ];
        }

        if ($httpBasicCredentials) {
            $config->merge(
                [
                    'config' => [
                        'http-basic' => $httpBasicCredentials,
                    ],
                ]
            );
            $io->loadConfiguration($config);
        }

        $installationManager = new DependabotInstallationManager($composer->getLoop(), $io);

        $fs = new Filesystem(null);
        $binaryInstaller = new Installer\BinaryInstaller($io, rtrim($composer->getConfig()->get('bin-dir'), '/'), $composer->getConfig()->get('bin-compat'), $fs);

        $installationManager->addInstaller(new LibraryInstaller());
        $installationManager->addInstaller(new Installer\PluginInstaller($io, $composer, $fs, $binaryInstaller));
        $installationManager->addInstaller(new Installer\MetapackageInstaller($io));

        $install = new Installer(
            $io,
            $config,
            $composer->getPackage(), // @phpstan-ignore-line
            $composer->getDownloadManager(),
            $composer->getRepositoryManager(),
            $composer->getLocker(),
            $installationManager,
            $composer->getEventDispatcher(),
            $composer->getAutoloadGenerator()
        );

        // For all potential options, see UpdateCommand in composer
        $install
            ->setWriteLock(true)
            ->setUpdate(true)
            ->setDevMode(true)
            ->setUpdateAllowList([$dependencyName])
            ->setUpdateAllowTransitiveDependencies(Request::UPDATE_LISTED_WITH_TRANSITIVE_DEPS)
            ->setExecuteOperations(true)
            ->setDumpAutoloader(false)
            ->setRunScripts(false)
            ->setIgnorePlatformRequirements(false);

        $install->run();

        $result = [
            'composer.lock' => file_get_contents('composer.lock'),
        ];

        chdir($originalDir);

        return $result;
    }
}
