# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/azure_pipelines/package/azure_devops_http"

RSpec.describe Dependabot::AzurePipelines::Package::AzureDevOpsHttp do
  let(:url) { "https://dev.azure.com/example/_apis/distributedtask/tasks" }

  describe ".get" do
    it "retries throttling and outages, then returns the eventual answer" do
      stub_request(:get, url).to_return(
        { status: 429, body: "" },
        { status: 503, body: "<html>Our services aren't available right now</html>" },
        { status: 200, body: "{}" }
      )

      expect(described_class.get(url: url).status).to eq(200)
      expect(described_class).to have_received(:wait).twice
    end

    it "retries an outage page served with a 200" do
      stub_request(:get, url).to_return(
        { status: 200, body: "<html>Sorry! Our services aren't available right now.</html>" },
        { status: 200, body: "{}" }
      )

      expect(described_class.get(url: url).body).to eq("{}")
    end

    it "retries a connection that fails, and gives up with its error" do
      stub_request(:get, url).to_raise(Excon::Error::Socket.new(StandardError.new("reset")))

      expect { described_class.get(url: url) }.to raise_error(Excon::Error::Socket)
      expect(WebMock).to have_requested(:get, url).times(described_class::MAX_ATTEMPTS)
    end

    it "waits as long as Retry-After asks, within the cap" do
      stub_request(:get, url).to_return(
        { status: 429, headers: { "Retry-After" => "7" }, body: "" },
        { status: 429, headers: { "Retry-After" => "3600" }, body: "" },
        { status: 200, body: "{}" }
      )

      described_class.get(url: url)

      expect(described_class).to have_received(:wait).with(7.0).ordered
      expect(described_class).to have_received(:wait).with(described_class::MAX_DELAY_SECONDS).ordered
    end

    it "backs off exponentially when the service gives no delay" do
      stub_request(:get, url).to_return(status: 502, body: "")
      delays = []
      allow(described_class).to receive(:wait) { |seconds| delays << seconds }

      described_class.get(url: url)

      expect(delays.size).to eq(described_class::MAX_ATTEMPTS - 1)
      expect(delays.zip([1, 2, 4]).all? { |delay, base| delay >= base && delay < base + 1 }).to be(true)
    end

    it "does not retry an authentication failure" do
      stub_request(:get, url).to_return(status: 401, body: "")

      expect(described_class.get(url: url).status).to eq(401)
      expect(WebMock).to have_requested(:get, url).once
    end

    it "suppresses the sign-in redirect while keeping the caller's headers" do
      stub_request(:get, url).to_return(status: 200, body: "{}")

      described_class.get(url: url, headers: { "Accept" => "application/json;api-version=7.1" })

      expect(WebMock).to have_requested(:get, url).with(
        headers: { "X-TFS-FedAuthRedirect" => "Suppress", "Accept" => "application/json;api-version=7.1" }
      )
    end
  end

  describe ".describe_failure" do
    def response(status, body)
      Excon::Response.new(status: status, body: body)
    end

    it "uses the message from an Azure DevOps error body" do
      body = "\uFEFF#{JSON.dump('message' => 'TF400813: Not authorized.', 'typeKey' => 'UnauthorizedRequestException')}"

      expect(described_class.describe_failure(response(401, body))).to eq("HTTP 401: TF400813: Not authorized.")
    end

    it "falls back to the type when the error body has no message" do
      body = JSON.dump("typeKey" => "ExtensionDoesNotExistException")

      expect(described_class.describe_failure(response(404, body))).to eq("HTTP 404: ExtensionDoesNotExistException")
    end

    it "finds a TF error in a non-JSON body" do
      expect(described_class.describe_failure(response(400, "<p>TF14045: The identity could not be found.</p>")))
        .to eq("HTTP 400: TF14045: The identity could not be found.")
    end

    it "reports only the status when the body explains nothing" do
      expect(described_class.describe_failure(response(500, JSON.dump("message" => "boom")))).to eq("HTTP 500")
    end
  end
end
