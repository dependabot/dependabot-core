<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\DependencyResolver\Request;
use Composer\Factory;
use Composer\Installer;
use Composer\Package\PackageInterface;
use Composer\Util\Filesystem;

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

        $installationManager = new DependabotInstallationManager($composer->getLoop(), $io);

        $fs = new Filesystem(null);
        $binaryInstaller = new Installer\BinaryInstaller($io, rtrim($composer->getConfig()->get('bin-dir'), '/'), $composer->getConfig()->get('bin-compat'), $fs);

        $installationManager->addInstaller(new Installer\LibraryInstaller($io, $composer, null, $fs, $binaryInstaller));
        $installationManager->addInstaller(new Installer\PluginInstaller($io, $composer, $fs, $binaryInstaller));
        $installationManager->addInstaller(new Installer\MetapackageInstaller($io));

        $install = new Installer(
            $io,
            $config,
            $composer->getPackage(),  // @phpstan-ignore-line
            $composer->getDownloadManager(),
            $composer->getRepositoryManager(),
            $composer->getLocker(),
            $installationManager,
            $composer->getEventDispatcher(),
            $composer->getAutoloadGenerator()
        );

        // For all potential options, see UpdateCommand in composer
        $install
            ->setUpdate(true)
            ->setDevMode(true)
            ->setUpdateAllowTransitiveDependencies(Request::UPDATE_LISTED_WITH_TRANSITIVE_DEPS)
            ->setDumpAutoloader(false)
            ->setRunScripts(false)
            ->setIgnorePlatformRequirements(false);

        // if no lock is present, we do not do a partial update as
        // this is not supported by the Installer
        if ($composer->getLocker()->isLocked()) {
            $install->setUpdateAllowList([$dependencyName]);
        }

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
