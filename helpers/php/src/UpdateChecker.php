<?php

declare(strict_types=1);

namespace Dependabot\PHP;

use Composer\Factory;
use Composer\Installer;
use Composer\Package\PackageInterface;

class UpdateChecker
{
    public static function getLatestResolvableVersion(array $args): ?string
    {
        [$workingDirectory, $dependencyName, $githubToken] = $args;

        $io = new ExceptionIO();
        $composer = Factory::create($io, $workingDirectory . '/composer.json');
        $config = $composer->getConfig();

        if ($githubToken) {
            $config->merge(
                [
                    'config' => [
                        'http-basic' => [
                            'github.com' => [
                                'username' => 'x-access-token',
                                'password' => $githubToken,
                            ],
                        ],
                    ],
                ]
            );
            $io->loadConfiguration($config);
        }

        $installationManager = new DependabotInstallationManager();
        $install = new Installer(
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
            ->setDevMode(true)
            ->setUpdateWhitelist([$dependencyName])
            ->setExecuteOperations(false)
            ->setDumpAutoloader(false)
            ->setRunScripts(false)
            ->setIgnorePlatformRequirements(true);

        $install->run();

        $installedPackages = $installationManager->getInstalledPackages();

        $updatedPackage = current(array_filter($installedPackages, function (PackageInterface $package) use ($dependencyName) {
            return $package->getName() == $dependencyName;
        }));

        return preg_replace('/^([v])/', '', $updatedPackage->getPrettyVersion());
    }
}
