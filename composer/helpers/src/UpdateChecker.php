<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\Factory;
use Composer\Installer;
use Composer\Package\PackageInterface;

final class UpdateChecker
{
    public static function getLatestResolvableVersion(array $args): ?string
    {
        [$workingDirectory, $dependencyName, $gitCredentials, $registryCredentials] = $args;

        $httpBasicCredentials = [];

        foreach ($gitCredentials as $credentials) {
            $httpBasicCredentials[$credentials['host']] = [
                'username' => $credentials['username'],
                'password' => $credentials['password'],
            ];
        }

        foreach ($registryCredentials as $credentials) {
            $httpBasicCredentials[$credentials['registry']] = [
                'username' => $credentials['username'],
                'password' => $credentials['password'],
            ];
        }

        $io = new ExceptionIO();

        $composer = Factory::create($io, $workingDirectory . '/composer.json');

        $config = $composer->getConfig();

        if (0 < count($httpBasicCredentials)) {
            $config->merge([
                'config' => [
                    'http-basic' => $httpBasicCredentials,
                ],
            ]);

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
            ->setUpdateAllowList([$dependencyName])
            ->setAllowListTransitiveDependencies(true)
            ->setExecuteOperations(false)
            ->setDumpAutoloader(false)
            ->setRunScripts(false)
            ->setIgnorePlatformRequirements(false);

        $install->run();

        $installedPackages = $installationManager->getInstalledPackages();

        $updatedPackage = current(array_filter($installedPackages, static function (PackageInterface $package) use ($dependencyName): bool {
            return $package->getName() === $dependencyName;
        }));

        // We found the package in the list of updated packages. Return its version.
        if ($updatedPackage instanceof PackageInterface) {
            return preg_replace('/^([v])/', '', $updatedPackage->getPrettyVersion());
        }

        // We didn't find the package in the list of updated packages. Check if
        // it was replaced by another package (in which case we can ignore).
        foreach ($composer->getPackage()->getReplaces() as $link) {
            if ($link->getTarget() === $dependencyName) {
                return null;
            }
        }

        foreach ($installedPackages as $package) {
            foreach ($package->getReplaces() as $link) {
                if ($link->getTarget() === $dependencyName) {
                    return null;
                }
            }
        }

        // Similarly, check if the package was provided by any other package.
        foreach ($composer->getPackage()->getProvides() as $link) {
            if ($link->getTarget() === $dependencyName) {
                return preg_replace('/^([v])/', '', $link->getPrettyConstraint());
            }
        }

        foreach ($installedPackages as $package) {
            foreach ($package->getProvides() as $link) {
                if ($link->getTarget() === $dependencyName) {
                    return preg_replace('/^([v])/', '', $link->getPrettyConstraint());
                }
            }
        }

        throw new \RuntimeException('Package not found in updated packages!');
    }
}
