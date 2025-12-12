<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\DependencyResolver\Request;
use Composer\Factory;
use Composer\Filter\PlatformRequirementFilter\PlatformRequirementFilterFactory;
use Composer\Installer;
use Composer\Package\PackageInterface;

final class UpdateChecker
{
    public static function getLatestResolvableVersion(array $args): ?string
    {
        [$workingDirectory, $dependencyName, $gitCredentials, $registryCredentials] = $args;

        $httpBasicCredentials = [];
        $bearerCredentials = [];
        $githubOauthCredentials = [];
        $gitlabOauthCredentials = [];
        $gitlabTokenCredentials = [];
        $bitbucketOauthCredentials = [];

        foreach ($gitCredentials as $credentials) {
            if (isset($credentials['host']) && isset($credentials['username']) && isset($credentials['password'])) {
                $httpBasicCredentials[$credentials['host']] = [
                    'username' => $credentials['username'],
                    'password' => $credentials['password'],
                ];
            }
        }

        foreach ($registryCredentials as $credentials) {
            $host = $credentials['registry'] ?? null;
            if (!$host) {
                continue;
            }

            // http-basic
            if (isset($credentials['username']) && isset($credentials['password'])) {
                $httpBasicCredentials[$host] = [
                    'username' => $credentials['username'],
                    'password' => $credentials['password'],
                ];
            }

            $authType = $credentials['auth_type'] ?? null;
            // bearer
            if ($authType === 'bearer' && isset($credentials['token'])) {
                $bearerCredentials[$host] = $credentials['token'];
            }
            // github-oauth
            if ($authType === 'github-oauth' && isset($credentials['token'])) {
                $githubOauthCredentials[$host] = $credentials['token'];
            }
            // gitlab-oauth
            if ($authType === 'gitlab-oauth' && isset($credentials['token'])) {
                $gitlabOauthCredentials[$host] = $credentials['token'];
            }
            // gitlab-token
            if ($authType === 'gitlab-token' && isset($credentials['token'])) {
                $gitlabTokenCredentials[$host] = $credentials['token'];
            }
            // bitbucket-oauth
            if ($authType === 'bitbucket-oauth' && (isset($credentials['key']) || isset($credentials['consumer-key']) || isset($credentials['username'])) && (isset($credentials['secret']) || isset($credentials['consumer-secret']) || isset($credentials['password']))) {
                $bitbucketOauthCredentials[$host] = [
                    'consumer-key' => $credentials['key'] ?? $credentials['consumer-key'] ?? $credentials['username'] ?? '',
                    'consumer-secret' => $credentials['secret'] ?? $credentials['consumer-secret'] ?? $credentials['password'] ?? '',
                ];
            }
        }

        $io = new ExceptionIO();

        $composer = Factory::create($io, $workingDirectory . '/composer.json');

        $config = $composer->getConfig();

        $configToMerge = ['config' => []];
        if (!empty($httpBasicCredentials)) {
            $configToMerge['config']['http-basic'] = $httpBasicCredentials;
        }
        if (!empty($bearerCredentials)) {
            $configToMerge['config']['bearer'] = $bearerCredentials;
        }
        if (!empty($githubOauthCredentials)) {
            $configToMerge['config']['github-oauth'] = $githubOauthCredentials;
        }
        if (!empty($gitlabOauthCredentials)) {
            $configToMerge['config']['gitlab-oauth'] = $gitlabOauthCredentials;
        }
        if (!empty($gitlabTokenCredentials)) {
            $configToMerge['config']['gitlab-token'] = $gitlabTokenCredentials;
        }
        if (!empty($bitbucketOauthCredentials)) {
            $configToMerge['config']['bitbucket-oauth'] = $bitbucketOauthCredentials;
        }

        if (!empty($configToMerge['config'])) {
            $config->merge($configToMerge);
            $io->loadConfiguration($config);
        }

        $install = new Installer(
            $io,
            $config,
            $composer->getPackage(),  // @phpstan-ignore-line
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
