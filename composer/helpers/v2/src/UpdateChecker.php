<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\DependencyResolver\Request;
use Composer\Factory;
use Composer\Filter\PlatformRequirementFilter\PlatformRequirementFilterFactory;
use Composer\Installer;
use Composer\Package\Link;
use Composer\Package\PackageInterface;
use Composer\Package\Version\VersionParser;

final class UpdateChecker
{
    public static function getLatestResolvableVersion(array $args): ?string
    {
        [$workingDirectory, $dependencyName, $gitCredentials, $registryCredentials, $latestAllowableVersion] = $args;

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

        $package = $composer->getPackage();
        $versionParser = new VersionParser();
        // constraint from dependabot
        $dependabotConstraint = '==' . $latestAllowableVersion;
        // combine new dependabot constraints with the existing composer constraints (if exists)
        if (isset($package->getRequires()[$dependencyName])) {
            // Root Composer Constraint
            $composerConstraint = $package->getRequires()[$dependencyName]->getPrettyConstraint();
            $combinedConstraint = $dependabotConstraint . ' ' . $composerConstraint;
            $constraint = $versionParser->parseConstraints($combinedConstraint);
            $link = new Link($package->getName(), $dependencyName, $constraint);
            $package->setRequires([$dependencyName => $link]);
        } elseif (isset($package->getDevRequires()[$dependencyName])) {
            // Dev Composer Constraint
            $composerConstraint = $package->getDevRequires()[$dependencyName]->getPrettyConstraint();
            $combinedConstraint = $dependabotConstraint . ' ' . $composerConstraint;
            $constraint = $versionParser->parseConstraints($combinedConstraint);
            $link = new Link($package->getName(), $dependencyName, $constraint);
            $package->setDevRequires([$dependencyName => $link]);
        } else {
            // No Composer Constraint
            $constraint = $versionParser->parseConstraints($dependabotConstraint);
            $link = new Link($package->getName(), $dependencyName, $constraint);
            $package->setRequires([$dependencyName => $link]);
        }

        $install = new Installer(
            $io,
            $config,
            $package,  // @phpstan-ignore-line
            $composer->getDownloadManager(),
            $composer->getRepositoryManager(),
            $composer->getLocker(),
            $composer->getInstallationManager(),
            $composer->getEventDispatcher(),
            $composer->getAutoloadGenerator()
        );

        $composer->getEventDispatcher()->setRunScripts(false);

        // For all potential options, see UpdateCommand in composer
        $install
            ->setUpdate(true)
            ->setInstall(false)
            ->setDevMode(true)
            ->setUpdateAllowTransitiveDependencies(Request::UPDATE_LISTED_WITH_TRANSITIVE_DEPS)
            ->setDumpAutoloader(false)
            ->setPlatformRequirementFilter(PlatformRequirementFilterFactory::fromBoolOrList(false))
            ->setAudit(false);

        // if no lock is present, we do not do a partial update as
        // this is not supported by the Installer
        if ($composer->getLocker()->isLocked()) {
            $install->setUpdateAllowList([$dependencyName]);
        }

        $install->run();

        $installedPackages = $composer->getLocker()->getLockedRepository(true)->getPackages();

        $updatedPackage = current(array_filter($installedPackages, static function (PackageInterface $package) use ($dependencyName): bool {
            return $package->getName() === $dependencyName;
        }));

        // We found the package in the list of updated packages. Return its version.
        if ($updatedPackage instanceof PackageInterface) {
            return ltrim($updatedPackage->getPrettyVersion(), 'v');
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
                return ltrim($link->getPrettyConstraint(), 'v');
            }
        }

        foreach ($installedPackages as $package) {
            foreach ($package->getProvides() as $link) {
                if ($link->getTarget() === $dependencyName) {
                    return ltrim($link->getPrettyConstraint(), 'v');
                }
            }
        }

        throw new \RuntimeException('Package not found in updated packages!');
    }
}
