<?php

declare(strict_types=1);

namespace Dependabot\PHP;

class UpdateChecker
{
    public static function get_latest_resolvable_version($args)
    {
        [$workingDirectory, $dependencyName, $githubToken] = $args;

        date_default_timezone_set('Europe/London');
        $io = new \Composer\IO\NullIO();
        $composer = \Composer\Factory::create($io, $workingDirectory . '/composer.json');

        $config = $composer->getConfig();

        if ($githubToken) {
            $config->merge(['config' => ['github-oauth' => ['github.com' => $githubToken]]]);
            $io->loadConfiguration($config);
        }

        $installationManager = new DependabotInstallationManager();
        $install = new \Composer\Installer(
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
            ->setUpdateWhitelist([$dependencyName])
            ->setExecuteOperations(false)
            ->setDumpAutoloader(false)
            ->setRunScripts(false)
            ->setIgnorePlatformRequirements(true);

        $install->run();

        $installedPackages = $installationManager->getInstalledPackages();

        $updatedPackage = current(array_filter($installedPackages, function ($package) use ($dependencyName) {
            return $package->getName() == $dependencyName;
        }));

        if ($updatedPackage->getRepository()->getRepoConfig()['type'] == 'vcs') {
            return null;
        }

        return preg_replace('/^([v])/', '', $updatedPackage->getPrettyVersion());
    }
}
