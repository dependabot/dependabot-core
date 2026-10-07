// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System;
using System.Linq;
using System.Net;
using System.Threading;
using System.Threading.Tasks;
using NuGet.Configuration;
using NuGet.Credentials;

namespace NuGet.CommandLine
{
    public class SettingsCredentialProvider : ICredentialProvider
    {
        private readonly IPackageSourceProvider _packageSourceProvider;
        private readonly Common.ILogger _logger;

        public SettingsCredentialProvider(IPackageSourceProvider packageSourceProvider)
            : this(packageSourceProvider, Common.NullLogger.Instance)
        {
        }

        public SettingsCredentialProvider(IPackageSourceProvider packageSourceProvider, Common.ILogger logger)
        {
            _packageSourceProvider = packageSourceProvider ?? throw new ArgumentNullException(nameof(packageSourceProvider));
            _logger = logger;
            Id = $"{nameof(SettingsCredentialProvider)}_{Guid.NewGuid()}";
        }

        public string Id { get; }

        public Task<CredentialResponse> GetAsync(
            Uri uri,
            IWebProxy proxy,
            CredentialRequestType type,
            string message,
            bool isRetry,
            bool nonInteractive,
            CancellationToken cancellationToken)
        {
            if (uri == null)
            {
                throw new ArgumentNullException(nameof(uri));
            }

            cancellationToken.ThrowIfCancellationRequested();

            // If we are retrying, the stored credentials must be invalid.
            if (!isRetry && type == CredentialRequestType.Unauthorized && TryGetCredentials(uri, out var credentials, out var username))
            {
                _logger.LogMinimal(string.Format(
                    System.Globalization.CultureInfo.CurrentCulture,
                    NuGetResources.SettingsCredentials_UsingSavedCredentials,
                    username,
                    uri.OriginalString));

                return Task.FromResult(new CredentialResponse(credentials));
            }

            return Task.FromResult(new CredentialResponse(CredentialStatus.ProviderNotApplicable));
        }

        private bool TryGetCredentials(Uri uri, out ICredentials? credentials, out string? username)
        {
            credentials = null;
            username = null;

            var source = _packageSourceProvider.LoadPackageSources()
                .FirstOrDefault(p =>
                {
                    Uri sourceUri;
                    return p.Credentials != null
                        && p.Credentials.IsValid()
                        && Uri.TryCreate(p.Source, UriKind.Absolute, out sourceUri)
                        && UriEquals(IsHttpSource(sourceUri) ? sourceUri : new Uri(p.Source), uri);
                });

            if (source == null)
            {
                return false;
            }

            credentials = new NetworkCredential(source.Credentials.Username, source.Credentials.Password);
            username = source.Credentials.Username;
            return true;
        }

        private static bool IsHttpSource(Uri uri)
        {
            return uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps;
        }

        private static bool UriEquals(Uri uri1, Uri uri2)
        {
            // Compare the scheme, host, port, and path (case-insensitive for host)
            return uri1.Scheme == uri2.Scheme
                && string.Equals(uri1.Host, uri2.Host, StringComparison.OrdinalIgnoreCase)
                && uri1.Port == uri2.Port
                && string.Equals(uri1.AbsolutePath.TrimEnd('/'), uri2.AbsolutePath.TrimEnd('/'), StringComparison.OrdinalIgnoreCase);
        }
    }
}