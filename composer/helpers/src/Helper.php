<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\Factory;
use Composer\Package\Locker;
use Composer\Package\PackageInterface;

final class Helper
{
    private function __construct()
    {
        // This class is not intended to be instanced
    }

    /**
     * Returns the md5 hash of the sorted content of the composer file.
     *
     * @param string $workingDirectory The directory of the composer file.
     *
     * @return string
     *
     * @throws \RuntimeException
     */
    public static function getContentHash(string $workingDirectory): string
    {
        $config = $workingDirectory . '/composer.json';

        $contents = file_get_contents($config);

        if (!is_string($contents)) {
            throw new \RuntimeException(sprintf(
                'Failed to load contents of "%s".',
                $config
            ));
        }

        return Locker::getContentHash($contents);
    }

    /**
     * Update the dependency within packages constraints and return the new lock file.
     *
     * @param string $workingDirectory The directory of the composer file.
     * @param string $dependencyName The name of the dependency.
     * @param array $gitCredentials
     * @param array $registryCredentials
     *
     * @return array
     *
     * @throws \Exception
     */
    public static function update(
        string $workingDirectory,
        string $dependencyName,
        array $gitCredentials,
        array $registryCredentials
    ): array {
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

        $pm = new PluginManager($io, $composer, null, false);
        $composer->setPluginManager($pm);
        $pm->loadInstalledPlugins();

        $install = new Installer($io, $composer, $dependencyName, $gitCredentials, $registryCredentials);

        $install
            ->setWriteLock(true)
            ->run();

        $result = [
            'composer.lock' => file_get_contents('composer.lock'),
        ];

        chdir($originalDir);

        return $result;
    }

    /**
     * Search and return the latest resolvable version of the dependency.
     *
     * @param string $workingDirectory The directory of the composer file.
     * @param string $dependencyName The name of the dependency.
     * @param array $gitCredentials
     * @param array $registryCredentials
     *
     * @return string|null
     *
     * @throws \Exception
     */
    public static function getLatestResolvableVersion(
        string $workingDirectory,
        string $dependencyName,
        array $gitCredentials,
        array $registryCredentials
    ): ?string {
        $io = new ExceptionIO();

        $composer = Factory::create($io, $workingDirectory . '/composer.json');

        $installationManager = new InstallationManager();

        $install = new Installer(
            $io,
            $composer,
            $dependencyName,
            $gitCredentials,
            $registryCredentials,
            $installationManager
        );

        $install
            ->setDryRun(true)
            ->run();

        $installedPackages = $installationManager->getInstalledPackages();

        $updatedPackage = current(array_filter(
            $installedPackages,
            static function (PackageInterface $package) use ($dependencyName): bool {
                return $package->getName() === $dependencyName;
            }
        ));

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
