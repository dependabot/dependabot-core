# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/update_checkers/docker/docker"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Docker::Docker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: credentials
    )
  end
  let(:credentials) do
    [
      {
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    ]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: [
        {
          requirement: nil,
          groups: [],
          file: "Dockerfile",
          source: { type: "tag" }
        }
      ],
      package_manager: "docker"
    )
  end
  let(:dependency_name) { "ubuntu" }
  let(:version) { "17.04" }
  let(:registry_tags) { fixture("docker", "registry_tags", "ubuntu.json") }

  before do
    auth_url = "https://auth.docker.io/token?service=registry.docker.io"
    stub_request(:get, auth_url).
      and_return(status: 200, body: { token: "token" }.to_json)

    tags_url = "https://registry.hub.docker.com/v2/library/ubuntu/tags/list"
    stub_request(:get, tags_url).
      and_return(status: 200, body: registry_tags)
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "given an outdated dependency" do
      let(:version) { "17.04" }
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
      let(:version) { "17.10" }
      it { is_expected.to be_falsey }
    end

    context "given a non-numeric version" do
      let(:version) { "artful" }
      it { is_expected.to be_falsey }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    it { is_expected.to eq("17.10") }

    context "when the dependency has a non-numeric version" do
      let(:version) { "artful" }
      it { is_expected.to be_nil }

      context "that starts with a number" do
        let(:version) { "309403913c7f0848e6616446edec909b55d53571" }
        it { is_expected.to be_nil }
      end
    end

    context "when the dependency has a non-numeric version" do
      let(:version) { "artful-20170619" }
      it { is_expected.to eq("artful-20170916") }
    end

    context "when the docker registry times out" do
      before do
        tags_url = "https://registry.hub.docker.com/v2/library/ubuntu/tags/list"
        stub_request(:get, tags_url).
          to_raise(RestClient::Exceptions::OpenTimeout).then.
          to_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("17.10") }

      context "every time" do
        before do
          tags_url =
            "https://registry.hub.docker.com/v2/library/ubuntu/tags/list"
          stub_request(:get, tags_url).
            to_raise(RestClient::Exceptions::OpenTimeout)
        end

        it "raises" do
          expect { checker.latest_version }.
            to raise_error(RestClient::Exceptions::OpenTimeout)
        end
      end
    end

    context "when the dependency's version has a suffix" do
      let(:dependency_name) { "ruby" }
      let(:version) { "2.4.0-slim" }
      let(:registry_tags) { fixture("docker", "registry_tags", "ruby.json") }
      before do
        auth_url = "https://auth.docker.io/token?service=registry.docker.io"
        stub_request(:get, auth_url).
          and_return(status: 200, body: { token: "token" }.to_json)

        tags_url = "https://registry.hub.docker.com/v2/library/ruby/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("2.4.2-slim") }
    end

    context "when the dependency has a namespace" do
      let(:dependency_name) { "moj/ruby" }
      let(:registry_tags) { fixture("docker", "registry_tags", "ruby.json") }
      before do
        auth_url = "https://auth.docker.io/token?service=registry.docker.io"
        stub_request(:get, auth_url).
          and_return(status: 200, body: { token: "token" }.to_json)

        tags_url = "https://registry.hub.docker.com/v2/moj/ruby/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("2.4.2") }
    end

    context "when the latest version is a pre-release" do
      let(:dependency_name) { "python" }
      let(:version) { "3.5" }
      let(:registry_tags) { fixture("docker", "registry_tags", "python.json") }
      before do
        auth_url = "https://auth.docker.io/token?service=registry.docker.io"
        stub_request(:get, auth_url).
          and_return(status: 200, body: { token: "token" }.to_json)

        tags_url = "https://registry.hub.docker.com/v2/library/python/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("3.6.3") }

      context "and the current version is a pre-release" do
        let(:version) { "3.7.0a1" }
        it { is_expected.to eq("3.7.0a2") }
      end
    end

    context "when the dependency's version has a suffix with periods" do
      let(:dependency_name) { "python" }
      let(:version) { "3.6.2-alpine3.6" }
      let(:registry_tags) { fixture("docker", "registry_tags", "python.json") }
      before do
        auth_url = "https://auth.docker.io/token?service=registry.docker.io"
        stub_request(:get, auth_url).
          and_return(status: 200, body: { token: "token" }.to_json)

        tags_url = "https://registry.hub.docker.com/v2/library/python/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("3.6.3-alpine3.6") }
    end

    context "when the dependency has a private registry" do
      let(:dependency_name) { "myreg/ubuntu" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: version,
          requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { type: "tag", registry: "registry-host.io:5000" }
            }
          ],
          package_manager: "docker"
        )
      end
      let(:registry_tags) { fixture("docker", "registry_tags", "ubuntu.json") }

      context "without authentication credentials" do
        it "raises a to Dependabot::PrivateSourceNotReachable error" do
          expect { checker.latest_version }.
            to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
              expect(error.source).to eq("registry-host.io:5000")
            end
        end
      end

      context "with authentication credentials" do
        let(:credentials) do
          [
            {
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "registry" => "registry-host.io:5000",
              "username" => "grey",
              "password" => "pa55word"
            }
          ]
        end

        before do
          tags_url = "https://registry-host.io:5000/v2/myreg/ubuntu/tags/list"
          stub_request(:get, tags_url).
            and_return(status: 200, body: registry_tags)
        end

        it { is_expected.to eq("17.10") }
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    before { allow(checker).to receive(:latest_version).and_return("delegate") }
    it { is_expected.to eq("delegate") }
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements }
    it { is_expected.to eq(dependency.requirements) }
  end
end
