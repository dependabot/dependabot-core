# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/docker/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Docker::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end
  let(:ignored_versions) { [] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: [{
        requirement: nil,
        groups: [],
        file: "Dockerfile",
        source: source
      }],
      package_manager: "docker"
    )
  end
  let(:dependency_name) { "ubuntu" }
  let(:version) { "17.04" }
  let(:source) { { tag: version } }
  let(:repo_url) { "https://registry.hub.docker.com/v2/library/ubuntu/" }
  let(:registry_tags) do
    fixture("docker", "registry_tags", "ubuntu_no_latest.json")
  end

  before do
    auth_url = "https://auth.docker.io/token?service=registry.docker.io"
    stub_request(:get, auth_url).
      and_return(status: 200, body: { token: "token" }.to_json)

    stub_request(:get, repo_url + "tags/list").
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

      context "and a digest" do
        let(:source) { { digest: "old_digest" } }
        let(:headers_response) do
          fixture("docker", "registry_manifest_headers", "ubuntu_17.10.json")
        end

        before do
          stub_request(:head, repo_url + "manifests/artful").
            and_return(status: 200, headers: JSON.parse(headers_response))
        end

        context "that is out-of-date" do
          let(:source) { { digest: "old_digest" } }
          it { is_expected.to be_truthy }
        end

        context "that is up-to-date" do
          let(:source) do
            {
              digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86ca97"\
                      "eba880ebf600d68608"
            }
          end

          it { is_expected.to be_falsey }
        end
      end
    end

    context "when the 'latest' version is just a more precise one" do
      let(:dependency_name) { "python" }
      let(:version) { "3.6" }
      let(:registry_tags) { fixture("docker", "registry_tags", "python.json") }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "ubuntu_17.10.json")
      end
      let(:repo_url) { "https://registry.hub.docker.com/v2/library/python/" }

      before do
        stub_request(:get, repo_url + "tags/list").
          and_return(status: 200, body: registry_tags)
        stub_request(:head, repo_url + "manifests/3.6").
          and_return(status: 200, headers: JSON.parse(headers_response))
        stub_request(:head, repo_url + "manifests/3.6.3").
          and_return(status: 200, headers: JSON.parse(headers_response))
      end

      it { is_expected.to be_falsey }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    it { is_expected.to eq("17.10") }

    context "when the dependency has a non-numeric version" do
      let(:version) { "artful" }
      it { is_expected.to eq("artful") }

      context "that starts with a number" do
        let(:version) { "309403913c7f0848e6616446edec909b55d53571" }
        it { is_expected.to eq("309403913c7f0848e6616446edec909b55d53571") }
      end
    end

    context "when the latest version is being ignored" do
      let(:ignored_versions) { [">= 17.10"] }
      it { is_expected.to eq("17.04") }
    end

    context "when there is a latest tag" do
      let(:registry_tags) { fixture("docker", "registry_tags", "ubuntu.json") }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "ubuntu_17.10.json")
      end
      let(:version) { "12.10" }
      let(:latest_version) { "17.04" }

      before do
        versions =
          %w(10.04 12.04.5 12.04 12.10 13.04 13.10 14.04.1 14.04.2 14.04.3
             14.04.4 14.04.5 14.04 14.10 15.04 15.10 16.04 16.10 17.04 17.10) -
          [latest_version]

        versions.each do |version|
          stub_request(:head, repo_url + "manifests/#{version}").
            and_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response)
            )
        end

        # Stub the latest version to return a different digest
        [latest_version, "latest"].each do |version|
          stub_request(:head, repo_url + "manifests/#{version}").
            and_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2"))
            )
        end
      end

      it { is_expected.to eq("17.04") }
    end

    context "when the dependency's version has a prefix" do
      let(:version) { "artful-20170826" }
      it { is_expected.to eq("artful-20170916") }
    end

    context "when the dependency has SHA suffices that should be ignored" do
      let(:registry_tags) do
        fixture("docker", "registry_tags", "sha_suffices.json")
      end
      let(:version) { "7.2-0.1" }
      it { is_expected.to eq("7.2-0.3.1") }

      context "for an older version of the prefix" do
        let(:version) { "7.1-0.1" }
        it { is_expected.to eq("7.1-0.3.1") }
      end
    end

    context "when the docker registry times out" do
      before do
        stub_request(:get, repo_url + "tags/list").
          to_raise(RestClient::Exceptions::OpenTimeout).then.
          to_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("17.10") }

      context "every time" do
        before do
          stub_request(:get, repo_url + "tags/list").
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
        tags_url = "https://registry.hub.docker.com/v2/moj/ruby/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("2.4.2") }

      context "and dockerhub 401s" do
        before do
          tags_url = "https://registry.hub.docker.com/v2/moj/ruby/tags/list"
          stub_request(:get, tags_url).
            and_return(
              status: 401,
              body: "",
              headers: { "www_authenticate" => "basic 123" }
            )
        end

        it "raises a to PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { checker.latest_version }.
            to raise_error(error_class) do |error|
              expect(error.source).to eq("registry.hub.docker.com")
            end
        end
      end
    end

    context "when the latest version is a pre-release" do
      let(:dependency_name) { "python" }
      let(:version) { "3.5" }
      let(:registry_tags) { fixture("docker", "registry_tags", "python.json") }
      before do
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

    context "when the latest tag points to an older version" do
      let(:registry_tags) { fixture("docker", "registry_tags", "dotnet.json") }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "ubuntu_17.10.json")
      end
      let(:version) { "2.0-sdk" }
      let(:latest_versions) { %w(2-sdk 2.1-sdk 2.1.401-sdk) }

      before do
        versions =
          %w(1-sdk 1.0-sdk 1.0.4-sdk 1.0.5-sdk 1.0.7-sdk 1.1-sdk 1.1.1-sdk
             1.1.2-sdk 1.1.4-sdk 1.1.5-sdk 2-sdk 2.0-sdk 2.0.0-sdk 2.0.3-sdk
             2.1-sdk 2.1.300-sdk 2.1.301-sdk 2.1.302-sdk 2.1.400-sdk 2.1.401-sdk
             2.2-sdk) -
          latest_versions

        versions.each do |version|
          stub_request(:head, repo_url + "manifests/#{version}").
            and_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response)
            )
        end

        # Stub the latest version to return a different digest
        [*latest_versions, "latest"].each do |version|
          stub_request(:head, repo_url + "manifests/#{version}").
            and_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2"))
            )
        end
      end

      it { is_expected.to eq("2.1.401-sdk") }

      context "and a suffix" do
        let(:version) { "2.0-runtime" }
        it { is_expected.to eq("2.1.3-runtime") }
      end

      context "when the latest tag 404s" do
        before do
          stub_request(:head, repo_url + "manifests/latest").
            to_return(status: 404).then.
            to_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2"))
            )
        end

        it { is_expected.to eq("2.1.401-sdk") }

        context "every time" do
          before do
            stub_request(:head, repo_url + "manifests/latest").
              to_return(status: 404)
          end

          it { is_expected.to eq("2.2-sdk") }
        end
      end
    end

    context "when the dependency's version has a suffix with periods" do
      let(:dependency_name) { "python" }
      let(:version) { "3.6.2-alpine3.6" }
      let(:registry_tags) { fixture("docker", "registry_tags", "python.json") }
      before do
        tags_url = "https://registry.hub.docker.com/v2/library/python/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("3.6.3-alpine3.6") }
    end

    context "when the dependency has a private registry" do
      let(:dependency_name) { "ubuntu" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: version,
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { registry: "registry-host.io:5000" }
          }],
          package_manager: "docker"
        )
      end
      let(:registry_tags) do
        fixture("docker", "registry_tags", "ubuntu_no_latest.json")
      end

      context "without authentication credentials" do
        before do
          tags_url = "https://registry-host.io:5000/v2/ubuntu/tags/list"
          stub_request(:get, tags_url).
            and_return(
              status: 401,
              body: "",
              headers: { "www_authenticate" => "basic 123" }
            )
        end

        it "raises a to PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { checker.latest_version }.
            to raise_error(error_class) do |error|
              expect(error.source).to eq("registry-host.io:5000")
            end
        end
      end

      context "with authentication credentials" do
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "type" => "docker_registry",
              "registry" => "registry-host.io:5000",
              "username" => "grey",
              "password" => "pa55word"
            }
          ]
        end

        before do
          tags_url = "https://registry-host.io:5000/v2/ubuntu/tags/list"
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

    context "when specified with a tag" do
      let(:source) { { tag: version } }

      it "updates the tag" do
        expect(checker.updated_requirements).
          to eq(
            [{
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "17.10" }
            }]
          )
      end
    end

    context "when specified with a digest" do
      let(:source) { { digest: "old_digest" } }

      before do
        new_headers =
          fixture("docker", "registry_manifest_headers", "ubuntu_17.10.json")
        stub_request(:head, repo_url + "manifests/17.10").
          and_return(status: 200, body: "", headers: JSON.parse(new_headers))
      end

      it "updates the digest" do
        expect(checker.updated_requirements).
          to eq(
            [{
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: {
                digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86"\
                        "ca97eba880ebf600d68608"
              }
            }]
          )
      end
    end

    context "when specified with a digest and a tag" do
      let(:source) { { digest: "old_digest", tag: "17.04" } }

      before do
        new_headers =
          fixture("docker", "registry_manifest_headers", "ubuntu_17.10.json")
        stub_request(:head, repo_url + "manifests/17.10").
          and_return(status: 200, body: "", headers: JSON.parse(new_headers))
      end

      it "updates the tag and the digest" do
        expect(checker.updated_requirements).
          to eq(
            [{
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: {
                digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86"\
                        "ca97eba880ebf600d68608",
                tag: "17.10"
              }
            }]
          )
      end
    end
  end
end
