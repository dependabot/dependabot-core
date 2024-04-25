// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using NuGet.Frameworks;

using static NuGet.Frameworks.FrameworkConstants;
using static NuGet.Frameworks.FrameworkConstants.CommonFrameworks;

namespace NuGetGallery.Frameworks
{
    /// <summary>
    /// This class contains documented supported frameworks.
    /// </summary>
    /// <remarks>
    /// All these frameworks were retrieved from the following sources:
    /// dotnet documentation: https://docs.microsoft.com/en-us/dotnet/standard/frameworks.
    /// nuget documentation: https://docs.microsoft.com/en-us/nuget/reference/target-frameworks.
    /// nuget client FrameworkConstants.CommonFrameworks: https://github.com/NuGet/NuGet.Client/blob/dev/src/NuGet.Core/NuGet.Frameworks/FrameworkConstants.cs.
    /// Deprecated frameworks are not included on the list https://docs.microsoft.com/en-us/dotnet/standard/frameworks#deprecated-target-frameworks.
    /// </remarks>
    public static class SupportedFrameworks
    {
        public static readonly Version Version8 = new Version(8, 0, 0, 0); // https://github.com/NuGet/Engineering/issues/5112

        public static readonly NuGetFramework MonoAndroid = new NuGetFramework(FrameworkIdentifiers.MonoAndroid, EmptyVersion);
        public static readonly NuGetFramework MonoTouch = new NuGetFramework(FrameworkIdentifiers.MonoTouch, EmptyVersion);
        public static readonly NuGetFramework MonoMac = new NuGetFramework(FrameworkIdentifiers.MonoMac, EmptyVersion);
        public static readonly NuGetFramework Net3 = new NuGetFramework(FrameworkIdentifiers.Net, new Version(3, 0, 0, 0));
        public static readonly NuGetFramework Net48 = new NuGetFramework(FrameworkIdentifiers.Net, new Version(4, 8, 0, 0));
        public static readonly NuGetFramework Net481 = new NuGetFramework(FrameworkIdentifiers.Net, new Version(4, 8, 1, 0));
        public static readonly NuGetFramework Net50Windows = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version5, "windows", EmptyVersion);
        public static readonly NuGetFramework Net60Android = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version6, "android", EmptyVersion);
        public static readonly NuGetFramework Net60Ios = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version6, "ios", EmptyVersion);
        public static readonly NuGetFramework Net60MacOs = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version6, "macos", EmptyVersion);
        public static readonly NuGetFramework Net60MacCatalyst = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version6, "maccatalyst", EmptyVersion);
        public static readonly NuGetFramework Net60TvOs = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version6, "tvos", EmptyVersion);
        public static readonly NuGetFramework Net60Windows = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version6, "windows", EmptyVersion);
        public static readonly NuGetFramework Net70Android = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version7, "android", EmptyVersion);
        public static readonly NuGetFramework Net70Ios = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version7, "ios", EmptyVersion);
        public static readonly NuGetFramework Net70MacOs = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version7, "macos", EmptyVersion);
        public static readonly NuGetFramework Net70MacCatalyst = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version7, "maccatalyst", EmptyVersion);
        public static readonly NuGetFramework Net70TvOs = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version7, "tvos", EmptyVersion);
        public static readonly NuGetFramework Net70Windows = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version7, "windows", EmptyVersion);

        public static readonly NuGetFramework Net80 = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version8); // https://github.com/NuGet/Engineering/issues/5112

        public static readonly NuGetFramework Net80Android = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version8, "android", EmptyVersion);
        public static readonly NuGetFramework Net80Ios = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version8, "ios", EmptyVersion);
        public static readonly NuGetFramework Net80MacOs = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version8, "macos", EmptyVersion);
        public static readonly NuGetFramework Net80MacCatalyst = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version8, "maccatalyst", EmptyVersion);
        public static readonly NuGetFramework Net80TvOs = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version8, "tvos", EmptyVersion);
        public static readonly NuGetFramework Net80Windows = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version8, "windows", EmptyVersion);
        public static readonly NuGetFramework NetCore = new NuGetFramework(FrameworkIdentifiers.NetCore, EmptyVersion);
        public static readonly NuGetFramework NetMf = new NuGetFramework(FrameworkIdentifiers.NetMicro, EmptyVersion);
        public static readonly NuGetFramework UAP = new NuGetFramework(FrameworkIdentifiers.UAP, EmptyVersion);
        public static readonly NuGetFramework WP = new NuGetFramework(FrameworkIdentifiers.WindowsPhone, EmptyVersion);
        public static readonly NuGetFramework XamarinIOs = new NuGetFramework(FrameworkIdentifiers.XamarinIOs, EmptyVersion);
        public static readonly NuGetFramework XamarinMac = new NuGetFramework(FrameworkIdentifiers.XamarinMac, EmptyVersion);
        public static readonly NuGetFramework XamarinTvOs = new NuGetFramework(FrameworkIdentifiers.XamarinTVOS, EmptyVersion);
        public static readonly NuGetFramework XamarinWatchOs = new NuGetFramework(FrameworkIdentifiers.XamarinWatchOS, EmptyVersion);

        public static readonly NuGetFramework Net60Windows7 = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version6, "windows", Version7);
        public static readonly NuGetFramework Net70Windows7 = new NuGetFramework(FrameworkIdentifiers.NetCoreApp, Version7, "windows", Version7);

        public static readonly IReadOnlyList<NuGetFramework> AllSupportedNuGetFrameworks;

        static SupportedFrameworks()
        {
            AllSupportedNuGetFrameworks = new List<NuGetFramework>
            {
                MonoAndroid, MonoMac, MonoTouch,
                Native,
                Net11, Net2, Net35, Net4, Net403, Net45, Net451, Net452, Net46, Net461, Net462, Net463, Net47, Net471, Net472, Net48, Net481,
                Net50, Net50Windows,
                Net60, Net60Android, Net60Ios, Net60MacCatalyst, Net60MacOs, Net60TvOs, Net60Windows,
                Net70, Net70Android, Net70Ios, Net70MacCatalyst, Net70MacOs, Net70TvOs, Net70Windows,
                Net80, Net80Android, Net80Ios, Net80MacCatalyst, Net80MacOs, Net80TvOs, Net80Windows,
                NetCore, NetCore45, NetCore451,
                NetCoreApp10, NetCoreApp11, NetCoreApp20, NetCoreApp21, NetCoreApp22, NetCoreApp30, NetCoreApp31,
                NetMf,
                NetStandard, NetStandard10, NetStandard11, NetStandard12, NetStandard13, NetStandard14, NetStandard15, NetStandard16, NetStandard20, NetStandard21,
                SL4, SL5,
                Tizen3, Tizen4, Tizen6,
                UAP, UAP10,
                WP, WP7, WP75, WP8, WP81, WPA81,
                XamarinIOs, XamarinMac, XamarinTvOs, XamarinWatchOs
            };
        }

        /// <summary>
        /// Lists of TFMs that users can filter packages by (for each Framework Generation) on NuGet.org search
        /// </summary>
        public static class TfmFilters
        {
            public static readonly List<NuGetFramework> NetTfms =
            [
                Net80,
                Net70,
                Net60,
                Net50
            ];

            public static readonly List<NuGetFramework> NetCoreAppTfms =
            [
                NetCoreApp31,
                NetCoreApp30,
                NetCoreApp22,
                NetCoreApp21,
                NetCoreApp20,
                NetCoreApp11,
                NetCoreApp10
            ];

            public static readonly List<NuGetFramework> NetStandardTfms =
            [
                NetStandard21,
                NetStandard20,
                NetStandard16,
                NetStandard15,
                NetStandard14,
                NetStandard13,
                NetStandard12,
                NetStandard11,
                NetStandard10
            ];

            public static readonly List<NuGetFramework> NetFrameworkTfms =
            [
                Net481,
                Net48,
                Net472,
                Net471,
                Net47,
                Net462,
                Net461,
                Net46,
                Net452,
                Net451,
                Net45,
                Net4,
                Net35,
                Net3,
                Net2
            ];
        }
    }
}
