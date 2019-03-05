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
        [$workingDirectory, $dependencyName, $gitCredentials, $registryCredentials] = $args;

        $io = new ExceptionIO();
        $composer = Factory::create($io, $workingDirectory . '/composer.json');
        $config = $composer->getConfig();
        $httpBasicCredentials = [];

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
            ->setWhitelistTransitiveDependencies(true)
            ->setExecuteOperations(false)
            ->setDumpAutoloader(false)
            ->setRunScripts(false);

        /*
         * If a platform is set we assume people know what they are doing and we respect the setting.
         * If no platform is set we assume platform compatibility.
         */
        $platform = array_merge([
            'php' => '*',
            'ext-apcu' => '*',
            'ext-bcmath' => '*',
            'ext-bz2' => '*',
            'ext-curl' => '*',
            'ext-fileinfo' => '*',
            'ext-gd' => '*',
            'ext-gd2' => '*',
            'ext-gettext' => '*',
            'ext-gmp' => '*',
            'ext-intl' => '*',
            'ext-imagick' => '*',
            'ext-imap' => '*',
            'ext-interbase' => '*',
            'ext-json' => '*',
            'ext-ldap' => '*',
            'ext-mbstring' => '*',
            'ext-memcached' => '*',
            'ext-mongodb' => '*',
            'ext-exif' => '*',
            'ext-mysqli' => '*',
            'ext-oci8_12c' => '*',
            'ext-odbc' => '*',
            'ext-openssl' => '*',
            'ext-pdo_firebird' => '*',
            'ext-pdo_mysql' => '*',
            'ext-pdo_oci' => '*',
            'ext-pdo_odbc' => '*',
            'ext-pdo_pgsql' => '*',
            'ext-pdo_sqlite' => '*',
            'ext-pgsql' => '*',
            'ext-redis' => '*',
            'ext-shmop' => '*',
            'ext-snmp' => '*',
            'ext-soap' => '*',
            'ext-sockets' => '*',
            'ext-sodium' => '*',
            'ext-sqlite3' => '*',
            'ext-tidy' => '*',
            'ext-xdebug' => '*',
            'ext-xml' => '*',
            'ext-xmlrpc' => '*',
            'ext-xsl' => '*',
            'ext-zip' => '*',
            'ext-zmq' => '*',
        ], $config->get('platform'));

        $config->merge(
            [
                'config' => [
                    'platform' => $platform,
                ],
            ]
        );

        $install->run();

        $installedPackages = $installationManager->getInstalledPackages();

        $updatedPackage = current(array_filter($installedPackages, function (PackageInterface $package) use ($dependencyName) {
            return $package->getName() == $dependencyName;
        }));

        // We found the package in the list of updated packages. Return its version.
        if ($updatedPackage) {
            return preg_replace('/^([v])/', '', $updatedPackage->getPrettyVersion());
        }

        // We didn't find the package in the list of updated packages. Check if
        // it was replaced by another package (in which case we can ignore).
        foreach ($composer->getPackage()->getReplaces() as $link) {
            if ($link->getTarget() == $dependencyName) {
                return null;
            }
        }
        foreach ($installedPackages as $package) {
            foreach ($package->getReplaces() as $link) {
                if ($link->getTarget() == $dependencyName) {
                    return null;
                }
            }
        }

        // Similarly, check if the package was provided by any other package.
        foreach ($composer->getPackage()->getProvides() as $link) {
            if ($link->getTarget() == $dependencyName) {
                return preg_replace('/^([v])/', '', $link->getPrettyConstraint());
            }
        }
        foreach ($installedPackages as $package) {
            foreach ($package->getProvides() as $link) {
                if ($link->getTarget() == $dependencyName) {
                    return preg_replace('/^([v])/', '', $link->getPrettyConstraint());
                }
            }
        }

        throw new \RuntimeException('Package not found in updated packages!');
    }
}
