<?php

declare(strict_types=1);

namespace Dependabot\Composer;

use Composer\DependencyResolver\Request;
use Composer\Factory;
use Composer\Filter\PlatformRequirementFilter\PlatformRequirementFilterFactory;
use Composer\Installer;

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
        $bearerCredentials = [];
        $githubOauthCredentials = [];
        $gitlabOauthCredentials = [];
        $gitlabTokenCredentials = [];
        $bitbucketOauthCredentials = [];

        $pm = new DependabotPluginManager($io, $composer, null, false);
        $composer->setPluginManager($pm);
        $pm->loadInstalledPlugins();

        foreach ($gitCredentials as &$cred) {
            if (isset($cred['host']) && isset($cred['username']) && isset($cred['password'])) {
                $httpBasicCredentials[$cred['host']] = [
                    'username' => $cred['username'],
                    'password' => $cred['password'],
                ];
            }
        }

        foreach ($registryCredentials as &$cred) {
            $host = $cred['registry'] ?? null;
            if (!$host) {
                continue;
            }

            if (isset($cred['username']) && isset($cred['password'])) {
                $httpBasicCredentials[$host] = [
                    'username' => $cred['username'],
                    'password' => $cred['password'],
                ];
            }

            $authType = $cred['auth_type'] ?? null;
            if ($authType === 'bearer' && isset($cred['token'])) {
                $bearerCredentials[$host] = $cred['token'];
            }
            if ($authType === 'github-oauth' && isset($cred['token'])) {
                $githubOauthCredentials[$host] = $cred['token'];
            }
            if ($authType === 'gitlab-oauth' && isset($cred['token'])) {
                $gitlabOauthCredentials[$host] = $cred['token'];
            }
            if ($authType === 'gitlab-token' && isset($cred['token'])) {
                $gitlabTokenCredentials[$host] = $cred['token'];
            }
            if ($authType === 'bitbucket-oauth' && (isset($cred['key']) || isset($cred['consumer-key']) || isset($cred['username'])) && (isset($cred['secret']) || isset($cred['consumer-secret']) || isset($cred['password']))) {
                $bitbucketOauthCredentials[$host] = [
                    'consumer-key' => $cred['key'] ?? $cred['consumer-key'] ?? $cred['username'] ?? '',
                    'consumer-secret' => $cred['secret'] ?? $cred['consumer-secret'] ?? $cred['password'] ?? '',
                ];
            }
        }

        $mergeConfig = ['config' => []];
        if (!empty($httpBasicCredentials)) {
            $mergeConfig['config']['http-basic'] = $httpBasicCredentials;
        }
        if (!empty($bearerCredentials)) {
            $mergeConfig['config']['bearer'] = $bearerCredentials;
        }
        if (!empty($githubOauthCredentials)) {
            $mergeConfig['config']['github-oauth'] = $githubOauthCredentials;
        }
        if (!empty($gitlabOauthCredentials)) {
            $mergeConfig['config']['gitlab-oauth'] = $gitlabOauthCredentials;
        }
        if (!empty($gitlabTokenCredentials)) {
            $mergeConfig['config']['gitlab-token'] = $gitlabTokenCredentials;
        }
        if (!empty($bitbucketOauthCredentials)) {
            $mergeConfig['config']['bitbucket-oauth'] = $bitbucketOauthCredentials;
        }

        if (!empty($mergeConfig['config'])) {
            $config->merge($mergeConfig);
            $io->loadConfiguration($config);
        }

        $install = new Installer(
            $io,
            $config,
            $composer->getPackage(), // @phpstan-ignore-line
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
            ->setWriteLock(true)
            ->setUpdate(true)
            ->setInstall(false)
            ->setDevMode(true)
            ->setUpdateAllowList([$dependencyName])
            ->setUpdateAllowTransitiveDependencies(Request::UPDATE_LISTED_WITH_TRANSITIVE_DEPS)
            ->setExecuteOperations(true)
            ->setDumpAutoloader(false)
            ->setPlatformRequirementFilter(PlatformRequirementFilterFactory::fromBoolOrList(false))
            ->setAudit(false);

        $install->run();

        $result = [
            'composer.lock' => file_get_contents('composer.lock'),
        ];

        chdir($originalDir);

        return $result;
    }
}
