# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/codeql/registry_client"

RSpec.describe Dependabot::Codeql::RegistryClient do
  subject(:registry_client) { described_class.new(credentials: credentials) }

  let(:credentials) { [] }
  let(:pack_name) { "codeql/java-all" }
  let(:tags_url) { "https://ghcr.io/v2/#{pack_name}/tags/list" }

  describe "#tags" do
    before do
      stub_request(:get, tags_url)
        .to_return(
          status: 401,
          headers: {
            "www-authenticate" =>
              'Bearer realm="https://ghcr.io/token",service="ghcr.io",' \
              "scope=\"repository:#{pack_name}:pull\""
          }
        )

      stub_request(:get, %r{ghcr\.io/token})
        .to_return(status: 200, body: { token: "anon-token" }.to_json)

      stub_request(:get, tags_url)
        .with(headers: { "Authorization" => "Bearer anon-token" })
        .to_return(
          status: 200,
          body: { name: pack_name, tags: %w(0.9.0 0.9.1 0.10.0) }.to_json
        )
    end

    it "returns the published tags for the pack" do
      expect(registry_client.tags(pack_name)).to contain_exactly("0.9.0", "0.9.1", "0.10.0")
    end

    context "when the registry returns no tags key" do
      before do
        stub_request(:get, tags_url)
          .with(headers: { "Authorization" => "Bearer anon-token" })
          .to_return(status: 200, body: { name: pack_name }.to_json)
      end

      it "returns an empty array" do
        expect(registry_client.tags(pack_name)).to eq([])
      end
    end

    context "with GHCR credentials" do
      let(:credentials) do
        [Dependabot::Credential.new(
          "type" => "docker_registry",
          "registry" => "ghcr.io",
          "username" => "x",
          "password" => "secret-token"
        )]
      end

      it "still lists tags" do
        expect(registry_client.tags(pack_name)).to contain_exactly("0.9.0", "0.9.1", "0.10.0")
      end
    end

    context "when configured GHCR credentials fail for a public pack" do
      let(:credentials) do
        [Dependabot::Credential.new(
          "type" => "docker_registry",
          "registry" => "ghcr.io",
          "username" => "x-access-token",
          "password" => "expired-token"
        )]
      end

      before do
        stub_request(:get, %r{ghcr\.io/token})
          .with(headers: { "Authorization" => /Basic/ })
          .to_return(status: 403, body: "")

        allow(DockerRegistry2::Registry).to receive(:new).and_call_original
      end

      it "falls back to anonymous access" do
        expect(registry_client.tags(pack_name)).to contain_exactly("0.9.0", "0.9.1", "0.10.0")
      end

      it "does not proxy the anonymous retry through Dependabot's credential proxy" do
        registry_client.tags(pack_name)

        expect(DockerRegistry2::Registry).to have_received(:new).with(
          "https://ghcr.io"
        )
      end
    end

    context "when a GHCR credential is configured without a usable token" do
      let(:credentials) do
        [Dependabot::Credential.new(
          "type" => "docker_registry",
          "registry" => "ghcr.io",
          "username" => "x-access-token",
          "password" => ""
        )]
      end

      it "uses anonymous access" do
        expect(registry_client.tags(pack_name)).to contain_exactly("0.9.0", "0.9.1", "0.10.0")
      end
    end
  end

  describe "#tags error handling" do
    let(:raising_client) { instance_double(DockerRegistry2::Registry) }

    before do
      allow(DockerRegistry2::Registry).to receive(:new).and_return(raising_client)
      allow(raising_client).to receive(:tags).and_raise(error)
    end

    context "when authentication fails" do
      let(:error) { DockerRegistry2::RegistryAuthenticationException.new("nope") }

      it "raises PrivateSourceAuthenticationFailure" do
        expect { registry_client.tags(pack_name) }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "when the registry is unreachable" do
      let(:error) { DockerRegistry2::RegistryUnknownException.new("down") }

      it "raises PrivateSourceTimedOut" do
        expect { registry_client.tags(pack_name) }
          .to raise_error(Dependabot::PrivateSourceTimedOut)
      end
    end

    context "when the registry returns an HTTP error" do
      let(:error) { DockerRegistry2::RegistryHTTPException.new("500 error") }

      it "raises PrivateSourceBadResponse" do
        expect { registry_client.tags(pack_name) }
          .to raise_error(Dependabot::PrivateSourceBadResponse)
      end
    end
  end

  describe "#release_dates" do
    let(:versions_url) do
      "https://api.github.com/orgs/codeql/packages/container/java-all/versions?per_page=100"
    end
    let(:versions_body) do
      [
        { created_at: "2026-01-01T00:00:00Z", metadata: { container: { tags: ["0.10.0"] } } },
        { created_at: "2025-06-01T00:00:00Z", metadata: { container: { tags: ["0.9.1"] } } }
      ].to_json
    end

    before do
      stub_request(:get, versions_url).to_return(status: 200, body: versions_body)
    end

    it "maps each tag to its publish time" do
      dates = registry_client.release_dates(pack_name)

      expect(dates["0.10.0"]).to eq(Time.parse("2026-01-01T00:00:00Z"))
      expect(dates["0.9.1"]).to eq(Time.parse("2025-06-01T00:00:00Z"))
    end

    context "when a GitHub credential is configured" do
      let(:credentials) do
        [Dependabot::Credential.new(
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "secret-github-token"
        )]
      end

      it "authenticates the request with the real token" do
        registry_client.release_dates(pack_name)

        expect(WebMock).to have_requested(:get, versions_url)
          .with(headers: { "Authorization" => "Bearer secret-github-token" })
      end
    end

    context "when the API returns an error" do
      before do
        stub_request(:get, versions_url).to_return(status: 404, body: "")
      end

      it "returns an empty hash" do
        expect(registry_client.release_dates(pack_name)).to eq({})
      end
    end

    context "when the request raises an unexpected error" do
      before do
        allow(Excon).to receive(:get).and_raise(StandardError, "boom")
      end

      it "logs a warning and returns an empty hash" do
        expect(Dependabot.logger).to receive(:warn).with(/boom/)
        expect(registry_client.release_dates(pack_name)).to eq({})
      end
    end
  end
end
