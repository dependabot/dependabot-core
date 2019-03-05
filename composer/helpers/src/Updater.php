<?php

declare(strict_types=1);

namespace Dependabot\PHP;

use Composer\Factory;
use Composer\Installer;

class Updater
{
    public static function update(array $args): array
    {
        [$workingDirectory, $dependencyName, $dependencyVersion, $gitCredentials, $registryCredentials] = $args;

        // Change working directory to the one provided, this ensures that we
        // install dependencies into the working dir, rather than a vendor folder
        // in the root of the project
        $originalDir = getcwd();
        chdir($workingDirectory);

        $io = new ExceptionIO();
        $composer = Factory::create($io);
        $config = $composer->getConfig();
        $httpBasicCredentials = [];

        $pm = new DependabotPluginManager($io, $composer, null, false);
        $composer->setPluginManager($pm);
        $pm->loadInstalledPlugins();

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

        $result = [
            'composer.lock' => file_get_contents('composer.lock'),
        ];

        chdir($originalDir);

        return $result;
    }
}
