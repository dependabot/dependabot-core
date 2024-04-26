// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

using NuGet.Common;
using NuGet.Frameworks;
using NuGet.Packaging.Core;
using NuGet.Packaging.Signing;

namespace NuGet.Packaging
{
    /// <summary>
    /// Reads an unzipped nupkg folder.
    /// </summary>
    public class PackageFolderReader : PackageReaderBase
    {
        private readonly DirectoryInfo _root;

        /// <summary>
        /// Package folder reader
        /// </summary>
        public PackageFolderReader(string folderPath)
            : this(folderPath, DefaultFrameworkNameProvider.Instance, DefaultCompatibilityProvider.Instance)
        {
        }

        /// <summary>
        /// Package folder reader
        /// </summary>
        /// <param name="folder">root directory of an extracted nupkg</param>
        public PackageFolderReader(DirectoryInfo folder)
            : this(folder, DefaultFrameworkNameProvider.Instance, DefaultCompatibilityProvider.Instance)
        {
        }

        /// <summary>
        /// Package folder reader
        /// </summary>
        /// <param name="folderPath">root directory of an extracted nupkg</param>
        /// <param name="frameworkProvider">framework mappings</param>
        /// <param name="compatibilityProvider">framework compatibility provider</param>
        public PackageFolderReader(string folderPath, IFrameworkNameProvider frameworkProvider, IFrameworkCompatibilityProvider compatibilityProvider)
            : this(new DirectoryInfo(folderPath), frameworkProvider, compatibilityProvider)
        {
        }

        /// <summary>
        /// Package folder reader
        /// </summary>
        /// <param name="folder">root directory of an extracted nupkg</param>
        /// <param name="frameworkProvider">framework mappings</param>
        /// <param name="compatibilityProvider">framework compatibility provider</param>
        public PackageFolderReader(DirectoryInfo folder, IFrameworkNameProvider frameworkProvider, IFrameworkCompatibilityProvider compatibilityProvider)
            : base(frameworkProvider, compatibilityProvider)
        {
            _root = folder;
        }

        public override string GetNuspecFile()
        {
            // This needs to be explicitly case insensitive in order to work on XPlat, since GetFiles is normally case sensitive on non-Windows
            var nuspecFiles = _root.GetFiles("*.*", SearchOption.TopDirectoryOnly).Where(f => f.Name.EndsWith(".nuspec", StringComparison.OrdinalIgnoreCase)).ToArray();

            if (nuspecFiles.Length == 0)
            {
                var message = new StringBuilder();
                message.Append(Strings.Error_MissingNuspecFile);
                message.AppendFormat(CultureInfo.CurrentCulture, Strings.Message_Path, _root.FullName);
                throw new PackagingException(NuGetLogCode.NU5037, message.ToString());
            }
            else if (nuspecFiles.Length > 1)
            {
                throw new PackagingException(Strings.MultipleNuspecFiles);
            }

            return nuspecFiles[0].FullName;
        }

        /// <summary>
        /// Opens a local file in read only mode.
        /// </summary>
        public override Stream GetStream(string path)
        {
            return GetFile(path).OpenRead();
        }

        private FileInfo GetFile(string path)
        {
            var file = new FileInfo(Path.Combine(_root.FullName, path));

            if (!file.FullName.StartsWith(_root.FullName, StringComparison.OrdinalIgnoreCase))
            {
                // the given path does not appear under the folder root
                throw new FileNotFoundException(path);
            }

            return file;
        }

        public override IEnumerable<string> GetFiles()
        {
            // Read all files starting at the root.
            return GetFiles(folder: null);
        }

        public override IEnumerable<string> GetFiles(string folder)
        {
            // Default to retrieve files and throwing if the root
            // directory is not found.
            var getFiles = true;
            var searchFolder = new DirectoryInfo(_root.FullName);

            if (!string.IsNullOrEmpty(folder))
            {
                // Search in the sub folder if one was specified
                searchFolder = new DirectoryInfo(Path.Combine(_root.FullName, folder));

                // For sub folders verify it exists
                // The root is expected to exist and should throw if it does not
                getFiles = searchFolder.Exists;

                // try a case-insensitive search
                if (!getFiles)
                {
                    searchFolder = _root.GetDirectories().FirstOrDefault(d => d.Name.Equals(folder, StringComparison.OrdinalIgnoreCase));
                    getFiles = searchFolder?.Exists == true;
                }
            }

            if (getFiles)
            {
                // Enumerate root folder filtering out nupkg files
                foreach (var file in searchFolder.GetFiles("*", SearchOption.AllDirectories))
                {
                    var path = GetRelativePath(_root, file);

                    // disallow nupkgs in the root
                    if (!IsFileInRoot(path) || !IsNupkg(path))
                    {
                        yield return path;
                    }
                }
            }

            yield break;
        }

        /// <summary>
        /// True if the path does not contain /
        /// </summary>
        private static bool IsFileInRoot(string path)
        {
#if NETCOREAPP
            return path.IndexOf('/', StringComparison.Ordinal) == -1;
#else
            return path.IndexOf('/') == -1;
#endif
        }

        /// <summary>
        /// True if the path ends with .nupkg
        /// </summary>
        private static bool IsNupkg(string path)
        {
            return path.EndsWith(PackagingCoreConstants.NupkgExtension, StringComparison.OrdinalIgnoreCase) == true;
        }

        /// <summary>
        /// Build the relative path in the same format that ZipArchive uses
        /// </summary>
        private static string GetRelativePath(DirectoryInfo root, FileInfo file)
        {
            var parents = new Stack<DirectoryInfo>();

            var parent = file.Directory;

            while (parent != null
                   && !StringComparer.OrdinalIgnoreCase.Equals(parent.FullName, root.FullName))
            {
                parents.Push(parent);
                parent = parent.Parent;
            }

            if (parent == null)
            {
                // the given file path does not appear under root
                throw new FileNotFoundException(file.FullName);
            }

            var parts = parents.Select(d => d.Name).Concat(new string[] { file.Name });

            return string.Join("/", parts);
        }

        public override IEnumerable<string> CopyFiles(
            string destination,
            IEnumerable<string> packageFiles,
            ExtractPackageFileDelegate extractFile,
            ILogger logger,
            CancellationToken token)
        {
            var filesCopied = new List<string>();

            foreach (var packageFile in packageFiles)
            {
                token.ThrowIfCancellationRequested();

                var sourceFile = GetFile(packageFile);

                var targetPath = Path.Combine(destination, packageFile);
                Directory.CreateDirectory(Path.GetDirectoryName(targetPath));

                using (var fileStream = sourceFile.OpenRead())
                {
                    targetPath = extractFile(sourceFile.FullName, targetPath, fileStream);
                    if (targetPath != null)
                    {
                        ZipArchiveExtensions.UpdateFileTime(targetPath, sourceFile.LastWriteTimeUtc);
                        filesCopied.Add(targetPath);
                    }
                }
            }

            return filesCopied;
        }

        protected override void Dispose(bool disposing)
        {
            // do nothing here
        }

        public override Task<PrimarySignature> GetPrimarySignatureAsync(CancellationToken token)
        {
            return TaskResult.Null<PrimarySignature>();
        }

        public override Task<bool> IsSignedAsync(CancellationToken token)
        {
            return TaskResult.False;
        }

        public override Task ValidateIntegrityAsync(SignatureContent signatureContent, CancellationToken token)
        {
            throw new NotImplementedException();
        }

        public override Task<byte[]> GetArchiveHashAsync(HashAlgorithmName hashAlgorithm, CancellationToken token)
        {
            throw new NotImplementedException();
        }

        public override bool CanVerifySignedPackages(SignedPackageVerifierSettings verifierSettings)
        {
            return false;
        }

        public override string GetContentHash(CancellationToken token, Func<string> GetUnsignedPackageHash = null)
        {
            throw new NotImplementedException();
        }
    }
}
