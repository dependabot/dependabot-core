<?php

declare(strict_types=1);

namespace Dependabot\PHP;

use Composer\Factory;
use Composer\Installer;

class Updater
{
    public static function update(array $args): array
    {
        [$workingDirectory, $dependencyName, $dependencyVersion, $githubToken, $registry_credentials] = $args;

        // Change working directory to the one provided, this ensures that we
        // install dependencies into the working dir, rather than a vendor folder
        // in the root of the project
        $originalDir = getcwd();
        chdir($workingDirectory);

        $io = new ExceptionIO();
        $composer = Factory::create($io);
        $config = $composer->getConfig();
        $httpBasicCredentials = [];

        if($githubToken) {
            $httpBasicCredentials['github.com'] = [
                'username' => 'x-access-token',
                'password' => $githubToken,
            ];
        }

        foreach($registry_credentials as &$cred) {
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
                    ]
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
            ->setExecuteOperations(false)
            ->setDumpAutoloader(false)
            ->setRunScripts(false)
            ->setIgnorePlatformRequirements(true);

        $install->run();

        $result = [
            'composer.lock' => file_get_contents('composer.lock'),
        ];

        chdir($originalDir);

        return $result;
    }
}
