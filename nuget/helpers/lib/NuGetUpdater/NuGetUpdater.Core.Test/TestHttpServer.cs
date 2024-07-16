using System.Net;
using System.Net.Sockets;

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
