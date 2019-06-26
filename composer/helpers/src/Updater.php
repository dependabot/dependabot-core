<?php

declare(strict_types=1);

namespace Dependabot\PHP;

use Composer\Factory;
use Composer\Installer;

class Updater
{
    public static function update(array $args): array
    {
        [$workingDirectory, $dependencyName, $dependencyVersionAndExtentions, $gitCredentials, $registryCredentials] = $args;
        [$dependencyVersion, $extensionsString] = explode(';', $dependencyVersionAndExtentions);
        $extensions = [];
        if ($extensionsString !== null && strlen($extensionsString) > 0) {
            $extensions = explode(',', $extensionsString);
        }

        // Change working directory to the one provided, this ensures that we
        // install dependencies into the working dir, rather than a vendor folder
        // in the root of the project
        $originalDir = getcwd();
        chdir($workingDirectory);

        $io = new ExceptionIO();
        $composer = Factory::create($io);
        $config = $composer->getConfig();
        $originalConfig = clone $config;
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

        if (count($extensions) > 0) {
            $platform = [];
            foreach ($extensions as $extension) {
                [$extension, $version] = explode('|', $extension);
                $platform[$extension] = $version;
            }

            $config->merge(
                [
                    'config' => [
                        'platform' => $platform + $config->get('platform'),
                    ],
                ]
            );
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
            ->setDevMode(true)
            ->setUpdateWhitelist([$dependencyName])
            ->setWhitelistTransitiveDependencies(true)
            ->setExecuteOperations(false)
            ->setDumpAutoloader(false)
            ->setRunScripts(false)
            ->setIgnorePlatformRequirements(false);

        $install->run();

        $install
            ->setConfig($originalConfig)
            ->setUpdateWhitelist(['lock'])
            ->setIgnorePlatformRequirements(true);
        $install->run();

        $result = [
            'composer.lock' => file_get_contents('composer.lock'),
        ];

        chdir($originalDir);

        return $result;
    }
}
