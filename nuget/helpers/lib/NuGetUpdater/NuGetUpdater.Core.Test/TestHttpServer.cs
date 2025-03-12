using System.Net;
using System.Net.Sockets;
using System.Text;

using NuGet.Versioning;
using NuGet;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Test
{
    public class TestHttpServer : IDisposable
    {
        private readonly Func<string, (int, byte[])> _requestHandler;
        private readonly HttpListener _listener;
        private bool _runServer = true;

        public string BaseUrl { get; }

        private TestHttpServer(string baseurl, Func<string, (int, byte[])> requestHandler)
        {
            BaseUrl = baseurl;
            _requestHandler = requestHandler;
            _listener = new HttpListener();
            _listener.Prefixes.Add(baseurl);
        }

        private void Start()
        {
            _listener.Start();
            Task.Factory.StartNew(HandleResponses);
        }

        public void Dispose()
        {
            _runServer = false;
            _listener.Stop();
        }

        public string GetPackageFeedIndex() => BaseUrl.TrimEnd('/') + "/index.json";

        private async Task HandleResponses()
        {
            while (_runServer)
            {
                var context = await _listener.GetContextAsync();
                var (statusCode, response) = _requestHandler(context.Request.Url!.AbsoluteUri);
                context.Response.StatusCode = statusCode;
                await context.Response.OutputStream.WriteAsync(response);
                context.Response.Close();
            }
        }

        private static readonly object PortGate = new();

        public static TestHttpServer CreateTestServer(Func<string, (int, byte[])> requestHandler)
        {
            // static lock to ensure the port is not recycled after `FindFreePort()` and before we can start the real server
            lock (PortGate)
            {
                var port = FindFreePort();
                var baseUrl = $"http://localhost:{port}/";
                var server = new TestHttpServer(baseUrl, requestHandler);
                server.Start();
                return server;
            }
        }

        public static TestHttpServer CreateTestStringServer(Func<string, (int, string)> requestHandler)
        {
            Func<string, (int, byte[])> bytesRequestHandler = url =>
            {
                var (statusCode, response) = requestHandler(url);
                return (statusCode, Encoding.UTF8.GetBytes(response));
            };
            return CreateTestServer(bytesRequestHandler);
        }

        public static TestHttpServer CreateTestNuGetFeed(params MockNuGetPackage[] packages)
        {
            var packageVersions = new Dictionary<string, HashSet<NuGetVersion>>(StringComparer.OrdinalIgnoreCase);
            foreach (var package in packages)
            {
                var versions = packageVersions.GetOrAdd(package.Id, () => new HashSet<NuGetVersion>());
                var version = NuGetVersion.Parse(package.Version);
                versions.Add(version);
            }

            var responses = new Dictionary<string, byte[]>();
            foreach (var kvp in packageVersions)
            {
                var packageId = kvp.Key;
                var versions = kvp.Value.OrderBy(v => v).ToArray();

                // registration
                var registrationUrl = $"/registrations/{packageId.ToLowerInvariant()}/index.json";
                var registrationContent = $$"""
                {
                  "count": {{versions.Length}},
                  "items": [
                    {
                      "lower": "{{versions.First()}}",
                      "upper": "{{versions.Last()}}",
                      "items": [
                        {{string.Join(",\n", versions.Select(v => $$"""
                                                               {
                                                                 "catalogEntry": {
                                                                   "version": "{{v}}"
                                                                 }
                                                               }
                                                               """))}}
                      ]
                    }
                  ]
                }
                """;
                responses[registrationUrl] = Encoding.UTF8.GetBytes(registrationContent);

                // download
                var downloadUrl = $"/download/{packageId.ToLowerInvariant()}/index.json";
                var downloadContent = $$"""
                {
                  "versions": [{{string.Join(", ", versions.Select(v => $"\"{v}\""))}}]
                }
                """;
                responses[downloadUrl] = Encoding.UTF8.GetBytes(downloadContent);

                // nupkg
                foreach (var package in packages.Where(p => p.Id.Equals(packageId, StringComparison.OrdinalIgnoreCase)))
                {
                    var id = packageId.ToLowerInvariant();
                    var v = package.Version.ToLowerInvariant();
                    var nupkgUrl = $"/download/{id}/{v}/{id}.{v}.nupkg";
                    var nupkgContent = package.GetZipStream().ReadAllBytes();
                    responses[nupkgUrl] = nupkgContent;
                }
            }

            (int, byte[]) HttpHandler(string uriString)
            {
                var uri = new Uri(uriString, UriKind.Absolute);
                var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
                if (uri.PathAndQuery == "/index.json")
                {
                    return (200, Encoding.UTF8.GetBytes($$"""
                {
                    "version": "3.0.0",
                    "resources": [
                        {
                            "@id": "{{baseUrl}}/download",
                            "@type": "PackageBaseAddress/3.0.0"
                        },
                        {
                            "@id": "{{baseUrl}}/query",
                            "@type": "SearchQueryService"
                        },
                        {
                            "@id": "{{baseUrl}}/registrations",
                            "@type": "RegistrationsBaseUrl"
                        }
                    ]
                }
                """));
                }

                if (responses.TryGetValue(uri.PathAndQuery, out var response))
                {
                    return (200, response);
                }

                return (404, Encoding.UTF8.GetBytes("{}"));
            }

            var server = TestHttpServer.CreateTestServer(HttpHandler);
            return server;
        }

        private static int FindFreePort()
        {
            var tcpListener = new TcpListener(IPAddress.Loopback, 0);
            tcpListener.Start();
            var port = ((IPEndPoint)tcpListener.LocalEndpoint).Port;
            tcpListener.Stop();
            return port;
        }
    }
}
