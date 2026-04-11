# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/docker/update_checker"
require "dependabot/config"
require "dependabot/config/update_config"
require "dependabot/package/release_cooldown_options"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Docker::UpdateChecker do
  let(:tags_fixture_name) { "ubuntu_no_latest.json" }
  let(:registry_tags) { fixture("docker", "registry_tags", tags_fixture_name) }
  let(:repo_url) { "https://registry.hub.docker.com/v2/library/ubuntu/" }
  let(:source) { { tag: version } }
  let(:version) { "17.04" }
  let(:dependency_name) { "ubuntu" }
  let(:update_cooldown) { nil }
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
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      update_cooldown: update_cooldown
    )
  end

  before do
    auth_url = "https://auth.docker.io/token?service=registry.docker.io"
    stub_request(:get, auth_url)
      .and_return(status: 200, body: { token: "token" }.to_json)

    stub_request(:get, repo_url + "tags/list")
      .and_return(status: 200, body: registry_tags)
  end

  it_behaves_like "an update checker"

  def stub_tag_with_no_digest(tag)
    stub_request(:head, repo_url + "manifests/#{tag}")
      .and_return(status: 200, headers: JSON.parse(headers_response).except("docker_content_digest"))
  end

  describe "#up_to_date?" do
    subject { checker.up_to_date? }

    context "when the digest is out of date and the tag is up to date" do
      let(:version) { "17.10" }
      let(:source) { { digest: "old_digest", tag: "17.10" } }

      before do
        new_headers =
          fixture("docker", "registry_manifest_headers", "generic.json")
        stub_request(:head, repo_url + "manifests/17.10")
          .and_return(status: 200, body: "", headers: JSON.parse(new_headers))
      end

      it { is_expected.to be_falsy }
    end
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "when the dependency is outdated" do
      let(:version) { "17.04" }

      it { is_expected.to be_truthy }
    end

    context "when the dependency is up-to-date" do
      let(:version) { "17.10" }

      it { is_expected.to be_falsey }
    end

    context "when the version is numeric" do
      let(:version) { "1234567890" }

      it { is_expected.to be_truthy }
    end

    context "when the version is non-numeric" do
      let(:version) { "artful" }

      it { is_expected.to be_falsey }

      context "when the digest is present" do
        let(:source) { { digest: "old_digest" } }
        let(:headers_response) do
          fixture("docker", "registry_manifest_headers", "generic.json")
        end

        before do
          stub_request(:head, repo_url + "manifests/artful")
            .and_return(status: 200, headers: JSON.parse(headers_response))
        end

        context "when the digest is out-of-date" do
          let(:source) { { digest: "old_digest" } }

          it { is_expected.to be_truthy }

          context "when the response doesn't include a new digest" do
            let(:headers_response) do
              fixture(
                "docker",
                "registry_manifest_headers",
                "generic.json"
              ).gsub(/^\s*"docker_content_digest.*?,/m, "")
            end

            it { is_expected.to be_falsey }
          end
        end

        context "when the digest is up-to-date" do
          let(:source) do
            {
              digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86ca97" \
                      "eba880ebf600d68608"
            }
          end

          it { is_expected.to be_falsey }
        end
      end
    end

    context "when only the digest is present" do
      let(:tags_fixture_name) { "ubuntu.json" }

      let(:version) { digest }
      let(:source) { { digest: digest } }

      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:head, repo_url + "manifests/latest")
          .and_return(status: 200, headers: JSON.parse(headers_response))
      end

      context "when the digest is out-to-date" do
        let(:digest) { "c5dcd377b75ca89f40a7b4284c05c58be4cd43d089f83af1333e56bde33d579f" }

        it { is_expected.to be_truthy }
      end

      context "when the digest is up-to-date" do
        let(:latest_digest) { "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86ca97eba880ebf600d68608" }
        let(:digest) { latest_digest }

        it { is_expected.to be_falsy }
      end
    end

    context "when the 'latest' version is just a more precise one" do
      let(:dependency_name) { "python" }
      let(:version) { "3.6" }
      let(:tags_fixture_name) { "python.json" }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end
      let(:repo_url) { "https://registry.hub.docker.com/v2/library/python/" }

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)
        stub_request(:head, repo_url + "manifests/3.6")
          .and_return(status: 200, headers: JSON.parse(headers_response))
        stub_request(:head, repo_url + "manifests/3.6.3")
          .and_return(status: 200, headers: JSON.parse(headers_response))
      end

      it { is_expected.to be_falsey }
    end

    context "when the 'latest' version is a newer version with more precision, and the API does not provide digests" do
      let(:dependency_name) { "ubi8/ubi-minimal" }
      let(:source) { { registry: "registry.access.redhat.com" } }
      let(:version) { "8.7-923.1669829893" }
      let(:tags_fixture_name) { "ubi-minimal.json" }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end
      let(:repo_url) { "https://registry.access.redhat.com/v2/ubi8/ubi-minimal/" }

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)
        stub_tag_with_no_digest("8.7-923.1669829893")
        stub_tag_with_no_digest("8.7-1049")
      end

      it { is_expected.to be true }
    end

    context "when the 'latest' version is newer, and API does not provide digests but there's a digest requirement" do
      let(:dependency_name) { "ubi8/ubi-minimal" }
      let(:source) do
        {
          registry: "registry.access.redhat.com",
          digest: "3f32ebba0cbf3849a48372d4fc3a4ce70816f248d39eb50da7ea5f15c7f9d120"
        }
      end
      let(:version) { "8.5" }
      let(:tags_fixture_name) { "ubi-minimal.json" }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end
      let(:repo_url) { "https://registry.access.redhat.com/v2/ubi8/ubi-minimal/" }

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)
        stub_tag_with_no_digest("8.7")
        stub_tag_with_no_digest("8.7-1049")
      end

      it { is_expected.to be false }
    end
  end

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    it { is_expected.to eq("17.10") }

    context "when the dependency has a non-numeric version" do
      let(:version) { "artful" }

      it { is_expected.to eq("artful") }

      context "when the version starts with a number" do
        let(:version) { "309403913c7f0848e6616446edec909b55d53571" }

        it { is_expected.to eq("309403913c7f0848e6616446edec909b55d53571") }
      end
    end

    context "when versions at different specificities look equal" do
      let(:dependency_name) { "ruby" }
      let(:version) { "2.4.0-slim" }
      let(:tags_fixture_name) { "ruby_25.json" }

      before do
        tags_url = "https://registry.hub.docker.com/v2/library/ruby/tags/list"
        stub_request(:get, tags_url)
          .and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("2.5.0-slim") }
    end

    context "when raise_on_ignored is enabled and later versions are allowed" do
      let(:raise_on_ignored) { true }

      it "doesn't raise an error" do
        expect { latest_version }.not_to raise_error
      end
    end

    context "when already on the latest version" do
      let(:version) { "17.10" }

      it { is_expected.to eq("17.10") }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it "doesn't raise an error" do
          expect { latest_version }.not_to raise_error
        end
      end
    end

    context "when all later versions are being ignored" do
      let(:ignored_versions) { [">= 17.10"] }

      it { is_expected.to eq("17.04") }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it "raises an error" do
          expect { latest_version }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "when all later versions are being ignored, but more tags available" do
      let(:ignored_versions) { [">= 17.10"] }
      let(:source) { { digest: "old_digest", tag: "17.04" } }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        before do
          new_headers =
            fixture("docker", "registry_manifest_headers", "generic.json")
          stub_request(:head, repo_url + "manifests/17.04")
            .and_return(status: 200, body: "", headers: JSON.parse(new_headers))
        end

        it "doesn't raise an error" do
          expect { latest_version }.not_to raise_error
        end
      end
    end

    context "when ignoring multiple versions" do
      let(:ignored_versions) { [">= 17.10, < 17.2"] }

      it { is_expected.to eq("17.10") }
    end

    context "when all versions are being ignored" do
      let(:ignored_versions) { [">= 0"] }

      it { is_expected.to eq("17.04") }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }

        it "raises an error" do
          expect { latest_version }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "with windows-servercore image" do
      let(:tags_fixture_name) { "windows-servercore.json" }
      let(:version) { "10.0.16299.1087" }

      it { is_expected.to eq("10.0.18362.175") }

      context "when using versions with cumulative updates (KB)" do
        let(:headers_response) do
          fixture("docker", "registry_manifest_headers", "generic.json")
        end

        before do
          stub_request(:head, repo_url + "manifests/1903")
            .and_return(status: 200, headers: JSON.parse(headers_response))

          # KB version is higher than KB-less version, so return a different digest
          stub_request(:head, repo_url + "manifests/1903-KB4505057")
            .and_return(status: 200, headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2")))
        end

        context "when using a version with no KB" do
          let(:version) { "1803" }

          it { is_expected.to eq("1903-KB4505057") }
        end

        context "when using a version with KB" do
          let(:version) { "1803-KB4487017" }

          it { is_expected.to eq("1903-KB4505057") }
        end
      end
    end

    context "when the version is the latest release candidate" do
      let(:dependency_name) { "php" }
      let(:tags_fixture_name) { "php.json" }
      let(:version) { "7.4.0RC6-fpm-buster" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/library/php/" }

      it { is_expected.to eq("7.4.0RC6-fpm-buster") }
    end

    context "when there is a latest tag" do
      let(:tags_fixture_name) { "ubuntu.json" }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end
      let(:version) { "12.10" }

      before do
        stub_request(:head, repo_url + "manifests/17.10")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )

        # Stub the latest version to return a different digest
        ["17.04", "latest"].each do |version|
          stub_request(:head, repo_url + "manifests/#{version}")
            .and_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2"))
            )
        end
      end

      it { is_expected.to eq("17.04") }
    end

    context "when fetching the latest tag results in a JSON parser error" do
      let(:tags_fixture_name) { "ubuntu.json" }
      let(:version) { "12.10" }

      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:head, repo_url + "manifests/17.10")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )

        stub_request(:head, repo_url + "manifests/latest").to_raise(JSON::ParserError)
      end

      it { is_expected.to eq("17.10") }
    end

    context "when the dependency's version has a prefix" do
      let(:version) { "artful-20170826" }

      it { is_expected.to eq("artful-20170916") }
    end

    context "when the dependency's version starts with a 'v'" do
      let(:version) { "v1.5.0" }
      let(:tags_fixture_name) { "kube_state_metrics.json" }

      it { is_expected.to eq("v1.6.0") }
    end

    context "when the dependency has SHA suffices that should be ignored" do
      let(:tags_fixture_name) { "sha_suffices.json" }
      let(:version) { "7.2-0.1" }

      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_same_sha_for("7.2-0.3", "7.2-0.3.1")
      end

      it { is_expected.to eq("7.2-0.3") }

      context "when using an older version of the prefix" do
        let(:version) { "7.1-0.1" }

        it { is_expected.to eq("7.2-0.3") }
      end
    end

    context "when the dependency version is generated with git describe --tags --long" do
      let(:tags_fixture_name) { "git_describe.json" }
      let(:version) { "v3.9.0-177-ged5bcde" }

      it { is_expected.to eq("v3.10.0-169-gfe040d3") }
    end

    context "when the docker registry times out" do
      before do
        stub_request(:get, repo_url + "tags/list")
          .to_raise(RestClient::Exceptions::OpenTimeout).then
          .to_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("17.10") }

      context "when it returns a bad response (TooManyRequests) error" do
        before do
          stub_request(:get, repo_url + "tags/list")
            .to_raise(RestClient::TooManyRequests)
        end

        it "raises" do
          expect { checker.latest_version }
            .to raise_error(Dependabot::PrivateSourceBadResponse)
        end

        context "when using a private registry" do
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
          let(:repo_url) { "https://registry-host.io:5000/v2/ubuntu/" }
          let(:tags_fixture_name) { "ubuntu_no_latest.json" }

          it "raises" do
            expect { checker.latest_version }
              .to raise_error(Dependabot::PrivateSourceBadResponse)
          end
        end
      end

      context "when the time out occurs every time" do
        before do
          stub_request(:get, repo_url + "tags/list")
            .to_raise(RestClient::Exceptions::OpenTimeout)
        end

        it "raises" do
          expect { checker.latest_version }
            .to raise_error(RestClient::Exceptions::OpenTimeout)
        end

        context "when using a private registry" do
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
          let(:repo_url) { "https://registry-host.io:5000/v2/ubuntu/" }
          let(:tags_fixture_name) { "ubuntu_no_latest.json" }

          it "raises" do
            expect { checker.latest_version }
              .to raise_error(Dependabot::PrivateSourceTimedOut)
          end
        end
      end

      context "when there is ServerBrokeConnection error response" do
        before do
          stub_request(:get, repo_url + "tags/list")
            .to_raise(RestClient::ServerBrokeConnection)
        end

        it "raises" do
          expect { checker.latest_version }
            .to raise_error(Dependabot::PrivateSourceBadResponse)
        end
      end

      context "when there is ParserError response from while accessing docker image tags" do
        before do
          stub_request(:get, repo_url + "tags/list")
            .to_raise(JSON::ParserError.new("unexpected token"))
        end

        it "raises" do
          expect { checker.latest_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end

      context "when TooManyRequests request error" do
        before do
          stub_request(:get, repo_url + "tags/list")
            .to_raise(RestClient::TooManyRequests)
        end

        it "raises" do
          expect { checker.latest_version }
            .to raise_error(Dependabot::PrivateSourceBadResponse)
        end
      end
    end

    context "when the dependency's version has a suffix" do
      let(:dependency_name) { "ruby" }
      let(:version) { "2.4.0-slim" }
      let(:tags_fixture_name) { "ruby.json" }

      before do
        tags_url = "https://registry.hub.docker.com/v2/library/ruby/tags/list"
        stub_request(:get, tags_url)
          .and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("2.4.2-slim") }
    end

    context "when the dependency's version has a prefix and a suffix" do
      let(:dependency_name) { "adoptopenjdk/openjdk11" }
      let(:version) { "jdk-11.0.2.7-alpine-slim" }
      let(:tags_fixture_name) { "openjdk11.json" }
      let(:repo_url) do
        "https://registry.hub.docker.com/v2/adoptopenjdk/openjdk11/"
      end
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )

        # Stub the latest version to return a different digest
        ["jdk-11.0.2.9", "latest"].each do |version|
          stub_request(:head, repo_url + "manifests/#{version}")
            .and_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2"))
            )
        end

        # Stub an oddly-formatted version to come back as a pre-release
        stub_request(:head, repo_url + "manifests/jdk-11.28")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response.gsub("3ea1ca1", "11171a2"))
          )
      end

      it { is_expected.to eq("jdk-11.0.2.9-alpine-slim") }
    end

    context "when the dependency's version has a <version>-<words>-<build_num> format" do
      let(:dependency_name) { "foo/bar" }
      let(:version) { "3.10-master-777" }
      let(:tags_fixture_name) { "bar.json" }
      let(:repo_url) do
        "https://registry.hub.docker.com/v2/foo/bar/"
      end
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )
      end

      it { is_expected.to eq("3.10-master-999") }
    end

    context "when the dependency's version has a <version>-<words>-<build_num> format prefixed with v" do
      let(:files) { [dockerfile] }
      let(:dockerfile_body) { "FROM foo/bar:v3.10-master-777" }
      let(:dockerfile) do
        Dependabot::DependencyFile.new(name: "Dockerfile", content: dockerfile_body)
      end
      let(:source) do
        Dependabot::Source.new(
          provider: "github",
          repo: "gocardless/bump",
          directory: "/"
        )
      end
      let(:parser) { Dependabot::Docker::FileParser.new(dependency_files: files, source: source) }
      let(:dependency) { parser.parse.first }
      let(:tags_fixture_name) { "bar_with_v.json" }
      let(:repo_url) do
        "https://registry.hub.docker.com/v2/foo/bar/"
      end
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )
      end

      it { is_expected.to eq("v3.10-master-999") }
    end

    context "when the dependency's version has a <version>-<words>-<build_num> format, and multiple hyphens" do
      let(:dependency_name) { "foo/baz" }
      let(:version) { "11-jdk-master-111" }
      let(:tags_fixture_name) { "baz.json" }
      let(:repo_url) do
        "https://registry.hub.docker.com/v2/foo/baz/"
      end
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )
      end

      it { is_expected.to eq("11-jdk-master-222") }
    end

    context "when the dependency's version has a <version>-<words>-<build> format, and different word formats" do
      let(:dependency_name) { "openjdk" }
      let(:version) { "21-ea-32" }
      let(:tags_fixture_name) { "openjdk.json" }
      let(:repo_url) do
        "https://registry.hub.docker.com/v2/library/openjdk/"
      end
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )
      end

      it { is_expected.to eq("22-ea-7") }
    end

    context "when the dependency's version has a <version>-<words>-<build> format, and multiple intermediate words" do
      let(:dependency_name) { "openjdk" }
      let(:tags_fixture_name) { "multiple-intermediate-words.json" }
      let(:repo_url) do
        "https://registry.hub.docker.com/v2/library/openjdk/"
      end
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )
      end

      context "when not the current version" do
        let(:version) { "21-ea-32" }

        it { is_expected.to eq("22-ea-7") }
      end

      context "when the current version" do
        let(:version) { "22-ea-7-windowsservercore-1809" }

        it { is_expected.to eq("22-ea-9-windowsservercore-1809") }
      end
    end

    context "when the dependency's version has a <prefix>_<year><month><day>.<version> format" do
      let(:dependency_name) { "dated_image" }
      let(:ignore_conditions) do
        [
          Dependabot::Config::IgnoreCondition.new(
            dependency_name: dependency_name,
            update_types: update_types
          )
        ]
      end
      let(:update_types) { ["version-update:semver-major"] }
      let(:ignored_versions) do
        Dependabot::Config::UpdateConfig.new(
          ignore_conditions: ignore_conditions
        ).ignored_versions_for(
          dependency,
          security_updates_only: false
        )
      end
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
      let(:tags_fixture_name) { "fulldate_in_tag.json" }
      let(:repo_url) do
        "https://registry-host.io:5000/v2/dated_image/"
      end
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )
      end

      context "when not the latest version, ignore updates" do
        let(:version) { "img_20230915.3" }

        it { is_expected.to eq("img_20230915.3") }
      end

      context "when the latest version, return latest version" do
        let(:version) { "img_20231011.1" }

        it { is_expected.to eq("img_20231011.1") }
      end
    end

    context "when the dependency's version has a <year><month><day>-<num>-<sha_suffix> format" do
      let(:dependency_name) { "foo/bar" }
      let(:version) { "20231101-230548-g159857a0b" }
      let(:tags_fixture_name) { "date_sha.json" }
      let(:repo_url) do
        "https://registry.hub.docker.com/v2/foo/bar/"
      end
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )
      end

      it { is_expected.to eq("20231203-230414-gd53f37589") }
    end

    context "when the dependencies have an underscore" do
      let(:dependency_name) { "eclipse-temurin" }
      let(:tags_fixture_name) { "eclipse-temurin.json" }
      let(:repo_url) do
        "https://registry.hub.docker.com/v2/library/eclipse-temurin/"
      end
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )

        # Stub the latest version to return a different digest
        ["17.0.2_8-jre-alpine", "latest"].each do |version|
          stub_request(:head, repo_url + "manifests/#{version}")
            .and_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2"))
            )
        end
      end

      context "when the underscore followed by numbers" do
        let(:version) { "17.0.1_12-jre-alpine" }

        it { is_expected.to eq("17.0.2_8-jre-alpine") }
      end

      context "when the underscore followed by numbers" do
        context "with less components than other version but higher underscore part" do
          before do
            stub_request(:head, repo_url + "manifests/#{latest_version}")
              .and_return(
                status: 200,
                body: "",
                headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2"))
              )
          end

          let(:latest_version) { "11.0.16.1_1-jdk" }
          let(:version) { "11.0.16_8-jdk" }

          it { is_expected.to eq(latest_version) }
        end
      end
    end

    context "when the dependencies have an underscore followed by sha-like strings" do
      let(:dependency_name) { "nixos/nix" }
      let(:version) { "2.1.3" }
      let(:tags_fixture_name) { "nixos-nix.json" }
      let(:repo_url) do
        "https://registry.hub.docker.com/v2/nixos/nix/"
      end
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )
      end

      it "ignores the sha-like part" do
        expect(latest_version).to eq("2.10.0")
      end
    end

    context "when the dependency has a namespace" do
      let(:dependency_name) { "moj/ruby" }
      let(:version) { "2.4.0" }
      let(:tags_fixture_name) { "ruby.json" }

      before do
        tags_url = "https://registry.hub.docker.com/v2/moj/ruby/tags/list"
        stub_request(:get, tags_url)
          .and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("2.4.2") }

      context "when dockerhub returns a 401 status" do
        before do
          tags_url = "https://registry.hub.docker.com/v2/moj/ruby/tags/list"
          stub_request(:get, tags_url)
            .and_return(
              status: 401,
              body: "",
              headers: { "www_authenticate" => "basic 123" }
            )
        end

        it "raises a to PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { checker.latest_version }
            .to raise_error(error_class) do |error|
              expect(error.source).to eq("registry.hub.docker.com")
            end
        end
      end
    end

    context "when the latest version is a pre-release" do
      let(:repo_url) { "https://registry.hub.docker.com/v2/library/python/" }
      let(:dependency_name) { "python" }
      let(:version) { "3.5" }
      let(:tags_fixture_name) { "python.json" }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        tags_url = "https://registry.hub.docker.com/v2/library/python/tags/list"
        stub_request(:get, tags_url)
          .and_return(status: 200, body: registry_tags)

        stub_same_sha_for("3.6", "3.6.3")
      end

      it { is_expected.to eq("3.6") }

      context "when the current version is a pre-release" do
        let(:version) { "3.7.0a1" }

        it { is_expected.to eq("3.7.0a2") }
      end
    end

    context "when the 'latest' version is a newer version with more precision, and the API does not provide digests" do
      let(:dependency_name) { "ubi8/ubi-minimal" }
      let(:source) { { registry: "registry.access.redhat.com" } }
      let(:version) { "8.7-923.1669829893" }
      let(:tags_fixture_name) { "ubi-minimal.json" }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end
      let(:repo_url) { "https://registry.access.redhat.com/v2/ubi8/ubi-minimal/" }

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)
        stub_tag_with_no_digest("8.7-923.1669829893")
        stub_tag_with_no_digest("8.7-1049")
      end

      it { is_expected.to eq("8.7-1049") }
    end

    context "when there are newer tags with the same and different precision, and the API does not provide digests" do
      let(:dependency_name) { "ubi8/ubi-minimal" }
      let(:source) { { registry: "registry.access.redhat.com" } }
      let(:version) { "8.5" }
      let(:tags_fixture_name) { "ubi-minimal.json" }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end
      let(:repo_url) { "https://registry.access.redhat.com/v2/ubi8/ubi-minimal/" }

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)
        stub_tag_with_no_digest("8.5")
        stub_tag_with_no_digest("8.7")
        stub_tag_with_no_digest("8.7-923.1669829893")
        stub_tag_with_no_digest("8.7-1049")
      end

      it { is_expected.to eq("8.7") }
    end

    context "when the latest tag points to an older version" do
      let(:tags_fixture_name) { "dotnet.json" }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end
      let(:version) { "2.0-sdk" }
      let(:latest_versions) { %w(2-sdk 2.1-sdk 2.1.401-sdk) }

      before do
        stub_request(:head, repo_url + "manifests/2.2-sdk")
          .and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )

        # Stub the latest version to return a different digest
        [*latest_versions, "latest"].each do |version|
          stub_request(:head, repo_url + "manifests/#{version}")
            .and_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2"))
            )
        end
      end

      it { is_expected.to eq("2.1-sdk") }

      context "when a suffix is present" do
        let(:version) { "2.0-runtime" }

        before do
          stub_same_sha_for("2.1.3-runtime", "2.1-runtime")
        end

        it { is_expected.to eq("2.1-runtime") }
      end

      context "with a paginated response" do
        let(:pagination_headers) do
          fixture("docker", "registry_pagination_headers", "next_link.json")
        end
        let(:end_pagination_headers) do
          fixture("docker", "registry_pagination_headers", "no_next_link.json")
        end

        before do
          stub_request(:get, repo_url + "tags/list")
            .and_return(
              status: 200,
              body: fixture("docker", "registry_tags", "dotnet_page_1.json"),
              headers: JSON.parse(pagination_headers)
            )
          last = "ukD72mdD/mC8b5xV3susmJzzaTgp3hKwR9nRUW1yZZ6dLc5kfZtKLT2ICo63" \
                 "WYvt2jq2VyIS3LWB%2Bo9HjGuiYQ6hARJz1jTFdW4jEMKPIg4kRwXypd7HXj" \
                 "/SnA9iMm3YvNsd4LmPQrO4fpYZgnZZ8rzIIYqex6%2B3A3/mKcTsNKkKDV9V" \
                 "R3ic6RJjYFCMOEk5/eqsfLaCDYEbtCNoxE2fBDwlzIl/W14f/F%2Bb%2BtQR" \
                 "Gh3eUKE9nBJpVvAfibAEs215m4ePJm%2BNuVktVjHOYlRG3U03ekr1T7CPD1" \
                 "Q%2B65wVYi0y2nCIl1/V40nkgG2WX5viYDxUuk3nEdnf55GUocnt38sDZzqB" \
                 "nyglM9jvbxBzlO8="
          stub_request(:get, repo_url + "tags/list?last=#{last}")
            .and_return(
              status: 200,
              body: fixture("docker", "registry_tags", "dotnet_page_2.json"),
              headers: JSON.parse(end_pagination_headers)
            )
        end

        it { is_expected.to eq("2.1-sdk") }
      end

      context "when the latest tag 404s" do
        before do
          stub_request(:head, repo_url + "manifests/latest")
            .to_return(status: 404).then
            .to_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2"))
            )
        end

        it { is_expected.to eq("2.1-sdk") }

        context "when it occurs every time" do
          before do
            stub_request(:head, repo_url + "manifests/latest")
              .to_return(status: 404)
          end

          it { is_expected.to eq("2.2-sdk") }
        end
      end
    end

    context "when the dependency's version has a suffix with periods" do
      let(:dependency_name) { "python" }
      let(:version) { "3.6.2-alpine3.6" }
      let(:tags_fixture_name) { "python.json" }

      before do
        tags_url = "https://registry.hub.docker.com/v2/library/python/tags/list"
        stub_request(:get, tags_url)
          .and_return(status: 200, body: registry_tags)
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
      let(:tags_fixture_name) { "ubuntu_no_latest.json" }

      context "without authentication credentials" do
        before do
          tags_url = "https://registry-host.io:5000/v2/ubuntu/tags/list"
          stub_request(:get, tags_url)
            .and_return(
              status: 401,
              body: "",
              headers: { "www_authenticate" => "basic 123" }
            )
        end

        it "raises a to PrivateSourceAuthenticationFailure error" do
          error_class = Dependabot::PrivateSourceAuthenticationFailure
          expect { checker.latest_version }
            .to raise_error(error_class) do |error|
              expect(error.source).to eq("registry-host.io:5000")
            end
        end
      end

      context "with authentication credentials" do
        let(:credentials) do
          [Dependabot::Credential.new(
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ), Dependabot::Credential.new(
            {
              "type" => "docker_registry",
              "registry" => "registry-host.io:5000",
              "username" => "grey",
              "password" => "pa55word"
            }
          )]
        end

        before do
          tags_url = "https://registry-host.io:5000/v2/ubuntu/tags/list"
          stub_request(:get, tags_url)
            .and_return(status: 200, body: registry_tags)
        end

        it { is_expected.to eq("17.10") }

        context "when there is no username or password" do
          let(:credentials) do
            [Dependabot::Credential.new(
              {
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }
            ), Dependabot::Credential.new(
              {
                "type" => "docker_registry",
                "registry" => "registry-host.io:5000"
              }
            )]
          end

          it { is_expected.to eq("17.10") }
        end
      end
    end

    context "when the dependency has a replaces-base" do
      let(:dependency_name) { "ubuntu" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: version,
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: { tag: "17.10" }
          }],
          package_manager: "docker"
        )
      end
      let(:tags_fixture_name) { "ubuntu_no_latest.json" }

      context "with replaces-base set to false" do
        let(:credentials) do
          [Dependabot::Credential.new(
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ), Dependabot::Credential.new(
            {
              "type" => "docker_registry",
              "registry" => "registry-host.io:5000",
              "username" => "grey",
              "password" => "pa55word",
              "replaces-base" => false
            }
          )]
        end

        before do
          tags_url = "https:/registry.hub.docker.com/v2/ubuntu/tags/list"
          stub_request(:get, tags_url)
            .and_return(status: 200, body: registry_tags)
        end

        it { is_expected.to eq("17.10") }
      end

      context "with replaces-base set to true and with authentication credentials" do
        let(:credentials) do
          [Dependabot::Credential.new(
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }
          ), Dependabot::Credential.new(
            {
              "type" => "docker_registry",
              "registry" => "registry-host.io:5000",
              "username" => "grey",
              "password" => "pa55word",
              "replaces-base" => true
            }
          )]
        end

        before do
          tags_url = "https://registry-host.io:5000/v2/ubuntu/tags/list"
          stub_request(:get, tags_url)
            .and_return(status: 200, body: registry_tags)
        end

        it { is_expected.to eq("17.10") }

        context "with replaces-base set to true and no username or password" do
          before do
            tags_url = "https://registry-host.io:5000/v2/ubuntu/tags/list"
            stub_request(:get, tags_url)
              .and_return(
                status: 401,
                body: "",
                headers: { "www_authenticate" => "basic 123" }
              )
          end

          let(:credentials) do
            [Dependabot::Credential.new(
              {
                "type" => "git_source",
                "host" => "github.com",
                "username" => "x-access-token",
                "password" => "token"
              }
            ), Dependabot::Credential.new(
              {
                "type" => "docker_registry",
                "registry" => "registry-host.io:5000",
                "replaces-base" => true
              }
            )]
          end

          it "raises a to PrivateSourceAuthenticationFailure error" do
            error_class = Dependabot::PrivateSourceAuthenticationFailure
            expect { checker.latest_version }
              .to raise_error(error_class) do |error|
                expect(error.source).to eq("registry-host.io:5000")
              end
          end
        end
      end
    end

    context "when the docker registry only knows about versions older than the current version" do
      let(:dependency_name) { "jetstack/cert-manager-controller" }
      let(:version) { "v1.7.2" }
      let(:digest) { "1815870847a48a9a6f177b90005d8df273e79d00830c21af9d43e1b5d8d208b4" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: version,
          requirements: [{
            requirement: nil,
            groups: [],
            file: "Dockerfile",
            source: {
              registry: "quay.io",
              tag: "v1.7.2",
              digest: "18305429afa14ea462f810146ba44d4363ae76e4c8dfc38288cf73aa07485005"
            }
          }],
          package_manager: "docker"
        )
      end
      let(:tags_fixture_name) { "truncated_tag_list.json" }

      before do
        tags_url = "https://quay.io/v2/jetstack/cert-manager-controller/tags/list"
        stub_request(:get, tags_url)
          .and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("v1.7.2") }
    end

    context "when versions have different components but similar structure" do
      let(:dependency_name) { "owasp/modsecurity-crs" }
      let(:version) { "3.3-apache-202209221209" }
      let(:tags_fixture_name) { "owasp.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/owasp/modsecurity-crs/" }

      let(:new_headers) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        tags_url = repo_url + "/tags/list"
        stub_request(:get, tags_url)
          .and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/4.11-apache-202502070602")
          .and_return(status: 200, body: "", headers: JSON.parse(new_headers))
        stub_request(:head, repo_url + "manifests/4-apache-202502070602")
          .and_return(status: 200, body: "", headers: JSON.parse(new_headers))
      end

      it { is_expected.to eq("4-apache-202502070602") }

      context "with multiple components to match" do
        let(:version) { "3.3-nginx-alpine-202209221209" }

        before do
          stub_request(:head, repo_url + "manifests/4.11-nginx-alpine-202502070602")
            .and_return(status: 200, body: "", headers: JSON.parse(new_headers))
          stub_request(:head, repo_url + "manifests/4-nginx-alpine-202502070602")
            .and_return(status: 200, body: "", headers: JSON.parse(new_headers))
        end

        it { is_expected.to eq("4-nginx-alpine-202502070602") }
      end

      context "when components are in a different order" do
        before do
          stub_request(:head, repo_url + "manifests/4-202502070602-apache")
            .and_return(status: 200, body: "", headers: JSON.parse(new_headers))
        end

        it { is_expected.to eq("4-apache-202502070602") }
      end
    end

    describe "with cooldown options" do
      subject(:latest_version) { checker.latest_version }

      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7)
      end
      let(:expected_cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 7,
          semver_major_days: 0,
          semver_minor_days: 0,
          semver_patch_days: 0,
          include: [],
          exclude: []
        )
      end

      before do
        new_headers =
          fixture("docker", "registry_manifest_headers", "generic.json")
        stub_request(:head, repo_url + "manifests/17.10")
          .and_return(status: 200, body: "", headers: JSON.parse(new_headers))
        stub_request(:get, repo_url + "manifests/17.10")
          .and_return(status: 200, body: fixture("docker", "registry_manifest_digests", "ubuntu_17.10.json"))

        blob_headers =
          fixture("docker", "image_blobs_headers", "ubuntu_17.10_38d6c1.json")

        stub_request(:head, repo_url + "blobs/sha256:9c4bf7dbb981591d4a1169138471afe4bf5ff5418841d00e30a7ba372e38d6c1")
          .and_return(status: 200, headers: JSON.parse(blob_headers))
      end

      it { is_expected.to eq("17.10") }
    end

    context "when the dependency has a compound suffix with alpine version" do
      let(:dependency_name) { "golang" }
      let(:version) { "1.26.0-alpine3.23" }
      let(:tags_fixture_name) { "golang.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/library/golang/" }

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)
      end

      it "updates to the latest version with the same exact suffix" do
        expect(checker.latest_version).to eq("1.27.0-alpine3.23")
      end
    end

    context "when node has alpine suffix with version" do
      let(:dependency_name) { "node" }
      let(:version) { "18.0.0-alpine3.18" }
      let(:tags_fixture_name) { "node_alpine.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/library/node/" }

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)
      end

      it "updates to the latest node version keeping the same alpine suffix" do
        expect(checker.latest_version).to eq("22.0.0-alpine3.18")
      end
    end

    context "when the dependency has an architecture-specific suffix" do
      let(:dependency_name) { "nginx" }
      let(:tags_fixture_name) { "architecture.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/library/nginx/" }

      before do
        stub_request(:get, repo_url + "tags/list")
          .and_return(status: 200, body: registry_tags)
      end

      context "when using arm64 architecture" do
        let(:version) { "1.25.3-alpine-arm64" }

        it "updates to the latest version with the same arm64 suffix" do
          expect(checker.latest_version).to eq("1.25.4-alpine-arm64")
        end
      end

      context "when using amd64 architecture" do
        let(:version) { "1.25.3-alpine-amd64" }

        it "updates to the latest version with the same amd64 suffix" do
          expect(checker.latest_version).to eq("1.25.4-alpine-amd64")
        end
      end

      context "when using the multi-arch tag (no architecture suffix)" do
        let(:version) { "1.25.3-alpine" }

        it "updates to the latest version without an architecture suffix" do
          expect(checker.latest_version).to eq("1.25.4-alpine")
        end
      end

      context "when docker_created_timestamp_validation is enabled" do
        before do
          Dependabot::Experiments.register(:docker_created_timestamp_validation, true)
          allow(checker).to receive(:fetch_manifest_platforms).and_return(nil)
        end

        after { Dependabot::Experiments.reset! }

        context "when using arm64 architecture with newer timestamps on other architectures" do
          let(:version) { "1.25.3-alpine-arm64" }

          before do
            allow(checker).to receive(:fetch_image_config_created) do |tag_name|
              case tag_name
              when "1.25.3-alpine-arm64"
                Time.parse("2024-01-01T10:00:00Z")
              when "1.25.4-alpine-arm64"
                Time.parse("2024-03-01T10:00:00Z")
              when "1.25.4-alpine-amd64"
                Time.parse("2024-04-01T10:00:00Z")
              when "1.25.4-alpine"
                Time.parse("2024-05-01T10:00:00Z")
              end
            end
          end

          it "updates to the latest arm64 tag, not a different architecture" do
            expect(checker.latest_version).to eq("1.25.4-alpine-arm64")
          end
        end

        context "when using amd64 architecture with newer timestamps on other architectures" do
          let(:version) { "1.25.3-alpine-amd64" }

          before do
            allow(checker).to receive(:fetch_image_config_created) do |tag_name|
              case tag_name
              when "1.25.3-alpine-amd64"
                Time.parse("2024-01-01T10:00:00Z")
              when "1.25.4-alpine-amd64"
                Time.parse("2024-03-01T10:00:00Z")
              when "1.25.4-alpine-arm64"
                Time.parse("2024-06-01T10:00:00Z")
              when "1.25.4-alpine"
                Time.parse("2024-05-01T10:00:00Z")
              end
            end
          end

          it "updates to the latest amd64 tag, not a different architecture" do
            expect(checker.latest_version).to eq("1.25.4-alpine-amd64")
          end
        end

        context "when using multi-arch tag with newer timestamps on arch-specific tags" do
          let(:version) { "1.25.3-alpine" }

          before do
            allow(checker).to receive(:fetch_image_config_created) do |tag_name|
              case tag_name
              when "1.25.3-alpine"
                Time.parse("2024-01-01T10:00:00Z")
              when "1.25.4-alpine"
                Time.parse("2024-03-01T10:00:00Z")
              when "1.25.4-alpine-arm64"
                Time.parse("2024-06-01T10:00:00Z")
              when "1.25.4-alpine-amd64"
                Time.parse("2024-06-01T10:00:00Z")
              end
            end
          end

          it "updates to the latest multi-arch tag, not an arch-specific tag" do
            expect(checker.latest_version).to eq("1.25.4-alpine")
          end
        end

        context "when timestamp fetch fails for architecture-specific tags" do
          let(:version) { "1.25.3-alpine-arm64" }

          before do
            allow(checker).to receive(:fetch_image_config_created).and_return(nil)
          end

          it "still updates to the correct architecture tag" do
            expect(checker.latest_version).to eq("1.25.4-alpine-arm64")
          end
        end
      end
    end

    context "when a date-embedded tag has a higher semver but is actually older (timestamp validation)" do
      let(:dependency_name) { "dotnet/framework/aspnet" }
      let(:version) { "4.8.1-windowsservercore-ltsc2022" }
      let(:tags_fixture_name) { "aspnet.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/dotnet/framework/aspnet/" }
      let(:source) { { tag: version } }

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, true)

        # Timestamps based on actual MCR values:
        # 4.8.1 and 4.8.1-20251014 are the same build (2026-02-10)
        # 4.8-20250909 and 4.8 are the same build (2025-09-09)
        created_timestamps = {
          "4.8-20250909-windowsservercore-ltsc2022" => Time.parse("2025-09-09T18:06:45Z"),
          "4.8.1-20251014-windowsservercore-ltsc2022" => Time.parse("2026-02-10T20:17:06Z"),
          "4.8.1-windowsservercore-ltsc2022" => Time.parse("2026-02-10T20:17:06Z"),
          "4.8-windowsservercore-ltsc2022" => Time.parse("2025-09-09T18:06:45Z"),
          "4.8.1-windowsservercore-ltsc2019" => Time.parse("2026-02-10T20:17:06Z"),
          "4.8-windowsservercore-ltsc2019" => Time.parse("2025-09-09T18:06:45Z")
        }

        allow(checker).to receive(:fetch_image_config_created) do |tag_name|
          created_timestamps[tag_name]
        end
      end

      after { Dependabot::Experiments.reset! }

      it "does not suggest upgrading to the older date-tagged version" do
        expect(checker.latest_version).to eq("4.8.1-windowsservercore-ltsc2022")
      end
    end

    context "when upgrading from a date-tagged version to another (both have dates in tag)" do
      let(:dependency_name) { "dotnet/framework/aspnet" }
      let(:version) { "4.8.1-20251014-windowsservercore-ltsc2022" }
      let(:tags_fixture_name) { "aspnet.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/dotnet/framework/aspnet/" }
      let(:source) { { tag: version } }

      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, true)

        # Stub manifest digest requests needed by precision comparison
        stub_request(:head, repo_url + "manifests/4.8.1-20251014-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response))
        stub_request(:head, repo_url + "manifests/4.8.1-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response.gsub("3ea1ca1", "6gc93c3")))
        stub_request(:head, repo_url + "manifests/4.8-20250909-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response.gsub("3ea1ca1", "5fb82b2")))
        stub_request(:head, repo_url + "manifests/4.8-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response.gsub("3ea1ca1", "4ea71a1")))

        # Timestamps based on actual MCR values
        created_timestamps = {
          "4.8-20250909-windowsservercore-ltsc2022" => Time.parse("2025-09-09T18:06:45Z"),
          "4.8.1-20251014-windowsservercore-ltsc2022" => Time.parse("2026-02-10T20:17:06Z"),
          "4.8.1-windowsservercore-ltsc2022" => Time.parse("2026-02-10T20:17:06Z")
        }

        allow(checker).to receive(:fetch_image_config_created) do |tag_name|
          created_timestamps[tag_name]
        end
      end

      after { Dependabot::Experiments.reset! }

      it "rejects the older dated tag despite higher semver" do
        # With the experiment flag enabled, numeric_version strips the date component
        # from dated tags. 4.8-20250909 therefore compares as "4.8", while
        # 4.8.1-20251014 compares as "4.8.1". remove_version_downgrades rejects
        # 4.8-20250909 as a downgrade from 4.8.1, so even though its raw tag looks
        # "higher" when the date is included, no upgrade is suggested.
        expect(checker.latest_version).to eq("4.8.1-20251014-windowsservercore-ltsc2022")
      end
    end

    context "when timestamp validation is disabled (flag off)" do
      let(:dependency_name) { "dotnet/framework/aspnet" }
      let(:version) { "4.8.1-windowsservercore-ltsc2022" }
      let(:tags_fixture_name) { "aspnet.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/dotnet/framework/aspnet/" }
      let(:source) { { tag: version } }

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, false)
      end

      after { Dependabot::Experiments.reset! }

      it "falls back to semver-based ordering (existing behavior with date inflation)" do
        # Without timestamp validation, dated/non-dated split is inactive and
        # dates inflate semver: Gem::Version("4.8.20250909") > Gem::Version("4.8.1")
        # This is the broken behavior that the experiment flag fixes.
        expect(checker.latest_version).to eq("4.8-20250909-windowsservercore-ltsc2022")
      end
    end

    context "when timestamp validation is enabled (flag on) for the same scenario" do
      let(:dependency_name) { "dotnet/framework/aspnet" }
      let(:version) { "4.8.1-windowsservercore-ltsc2022" }
      let(:tags_fixture_name) { "aspnet.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/dotnet/framework/aspnet/" }
      let(:source) { { tag: version } }

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, true)
      end

      after { Dependabot::Experiments.reset! }

      it "stays on current version because dated tags are excluded" do
        # With timestamp validation enabled, the dated/non-dated split is active:
        # 4.8-20250909 (dated) is not comparable to 4.8.1 (non-dated).
        # No false upgrade is suggested.
        expect(checker.latest_version).to eq("4.8.1-windowsservercore-ltsc2022")
      end
    end

    context "when timestamp validation cannot fetch config (graceful fallback)" do
      let(:dependency_name) { "dotnet/framework/aspnet" }
      let(:version) { "4.8.1-windowsservercore-ltsc2022" }
      let(:tags_fixture_name) { "aspnet.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/dotnet/framework/aspnet/" }
      let(:source) { { tag: version } }

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, true)

        allow(checker).to receive(:fetch_image_config_created).and_return(nil)
      end

      after { Dependabot::Experiments.reset! }

      it "stays on current version since dated tags are not comparable" do
        # Even when timestamp fetch fails, the dated/non-dated split prevents
        # 4.8-20250909 (dated) from being considered as an upgrade for 4.8.1 (non-dated)
        expect(checker.latest_version).to eq("4.8.1-windowsservercore-ltsc2022")
      end
    end

    context "when timestamp validation with a manifest list (multi-arch image)" do
      let(:dependency_name) { "dotnet/framework/aspnet" }
      let(:version) { "4.8.1-windowsservercore-ltsc2022" }
      let(:tags_fixture_name) { "aspnet.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/dotnet/framework/aspnet/" }
      let(:source) { { tag: version } }

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, true)

        # Stub at the fetch_image_config_created level to avoid interfering with tag listing
        # Timestamps based on actual MCR values
        created_timestamps = {
          "4.8-20250909-windowsservercore-ltsc2022" => Time.parse("2025-09-09T18:06:45Z"),
          "4.8.1-20251014-windowsservercore-ltsc2022" => Time.parse("2026-02-10T20:17:06Z"),
          "4.8.1-windowsservercore-ltsc2022" => Time.parse("2026-02-10T20:17:06Z")
        }

        allow(checker).to receive(:fetch_image_config_created) do |tag_name|
          created_timestamps[tag_name]
        end
      end

      after { Dependabot::Experiments.reset! }

      it "validates timestamps and rejects older candidates" do
        expect(checker.latest_version).to eq("4.8.1-windowsservercore-ltsc2022")
      end
    end

    context "when all non-dated candidate tags are genuinely newer by timestamp" do
      let(:dependency_name) { "dotnet/framework/aspnet" }
      let(:version) { "4.8-windowsservercore-ltsc2022" }
      let(:tags_fixture_name) { "aspnet.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/dotnet/framework/aspnet/" }
      let(:source) { { tag: version } }

      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, true)
        allow(checker).to receive(:fetch_manifest_platforms).and_return(nil)

        # Stub manifest digest requests needed by precision comparison
        stub_request(:head, repo_url + "manifests/4.8-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response))
        stub_request(:head, repo_url + "manifests/4.8.1-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response.gsub("3ea1ca1", "6gc93c3")))

        allow(checker).to receive(:fetch_image_config_created) do |tag_name|
          if tag_name == "4.8-windowsservercore-ltsc2022"
            Time.parse("2025-09-09T18:06:45Z")
          else
            Time.parse("2026-02-10T20:17:06Z")
          end
        end
      end

      after { Dependabot::Experiments.reset! }

      it "returns the highest non-dated tag since dated tags are excluded" do
        # 4.8-20250909 is excluded because it's a dated tag and 4.8 is non-dated.
        # The only comparable non-dated upgrade is 4.8.1.
        expect(checker.latest_version).to eq("4.8.1-windowsservercore-ltsc2022")
      end
    end

    context "when a dated tag has no newer dated tag available" do
      let(:dependency_name) { "dotnet/framework/aspnet" }
      let(:version) { "4.8.1-20251014-windowsservercore-ltsc2022" }
      let(:tags_fixture_name) { "aspnet.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/dotnet/framework/aspnet/" }
      let(:source) { { tag: version } }

      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, true)

        # Stub manifest digest requests
        stub_request(:head, repo_url + "manifests/4.8-20250909-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response))
        stub_request(:head, repo_url + "manifests/4.8.1-20251014-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response.gsub("3ea1ca1", "5fb82b2")))

        # Timestamps: non-dated tag has the newest timestamp, but should still
        # be excluded because the current tag is dated
        allow(checker).to receive(:fetch_image_config_created) do |tag_name|
          case tag_name
          when "4.8-20250909-windowsservercore-ltsc2022"
            Time.parse("2025-09-09T18:06:45Z")
          when "4.8.1-20251014-windowsservercore-ltsc2022"
            Time.parse("2026-02-10T20:17:06Z")
          when "4.8.1-windowsservercore-ltsc2022"
            # Non-dated tag has the newest timestamp — but it should NOT be picked
            Time.parse("2026-03-15T12:00:00Z")
          end
        end
      end

      after { Dependabot::Experiments.reset! }

      it "stays on current version, ignoring non-dated tags even with newer timestamps" do
        # 4.8.1-windowsservercore-ltsc2022 (non-dated, newest timestamp) is excluded.
        # 4.8.1-20251014-windowsservercore-ltsc2022 is already the highest semver among dated tags
        # No upgrade available.
        expect(checker.latest_version).to eq("4.8.1-20251014-windowsservercore-ltsc2022")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
        expect(checker.up_to_date?).to be(true)
      end
    end

    context "when a dated tag updates to a newer dated tag with the same base version" do
      let(:dependency_name) { "dotnet/framework/aspnet" }
      let(:version) { "4.8.1-20251014-windowsservercore-ltsc2022" }
      let(:tags_fixture_name) { "aspnet_with_future_dates.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/dotnet/framework/aspnet/" }
      let(:source) { { tag: version } }

      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, true)
        allow(checker).to receive(:fetch_manifest_platforms).and_return(nil)

        # Stub manifest digest requests needed by precision comparison
        stub_request(:head, repo_url + "manifests/4.8.1-20251014-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response))
        stub_request(:head, repo_url + "manifests/4.8.1-20990301-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response.gsub("3ea1ca1", "7hd04d4")))
        stub_request(:head, repo_url + "manifests/4.8-20250909-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response.gsub("3ea1ca1", "5fb82b2")))

        allow(checker).to receive(:fetch_image_config_created) do |tag_name|
          case tag_name
          when "4.8.1-20251014-windowsservercore-ltsc2022"
            Time.parse("2025-10-14T18:06:45Z")
          when "4.8.1-20990301-windowsservercore-ltsc2022"
            Time.parse("2099-03-01T20:17:06Z")
          when "4.8-20250909-windowsservercore-ltsc2022"
            Time.parse("2025-09-09T18:06:45Z")
          when "4.8.1-windowsservercore-ltsc2022"
            # Non-dated tag — should NOT be picked even though it exists
            Time.parse("2026-03-15T12:00:00Z")
          end
        end
      end

      after { Dependabot::Experiments.reset! }

      it "updates to the newer dated tag with the same base version" do
        # Both are dated, same base version, and timestamp confirms it's newer.
        # Non-dated 4.8.1-windowsservercore-ltsc2022 is excluded from comparison.
        expect(checker.latest_version).to eq("4.8.1-20990301-windowsservercore-ltsc2022")
        expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
        expect(checker.up_to_date?).to be(false)
      end
    end

    context "when a non-dated tag updates to a newer non-dated version, ignoring dated tags" do
      let(:dependency_name) { "dotnet/framework/aspnet" }
      let(:version) { "4.8.1-windowsservercore-ltsc2022" }
      let(:tags_fixture_name) { "aspnet_with_future_tags.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/dotnet/framework/aspnet/" }
      let(:source) { { tag: version } }

      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, true)
        allow(checker).to receive(:fetch_manifest_platforms).and_return(nil)

        stub_request(:head, repo_url + "manifests/4.8.1-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response))
        stub_request(:head, repo_url + "manifests/4.8.2-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response.gsub("3ea1ca1", "8ie15e5")))

        allow(checker).to receive(:fetch_image_config_created) do |tag_name|
          case tag_name
          when "4.8.1-windowsservercore-ltsc2022"
            Time.parse("2026-02-10T20:17:06Z")
          when "4.8.2-windowsservercore-ltsc2022"
            Time.parse("2026-03-01T10:00:00Z")
          when "4.8.2-20990301-windowsservercore-ltsc2022"
            # Dated tag has an even newer timestamp — but should NOT be picked
            Time.parse("2099-03-01T12:00:00Z")
          end
        end
      end

      after { Dependabot::Experiments.reset! }

      it "picks the non-dated 4.8.2, not the dated 4.8.2-20990301" do
        expect(checker.latest_version).to eq("4.8.2-windowsservercore-ltsc2022")
      end
    end

    context "when a dated tag updates to a newer dated version, ignoring non-dated tags" do
      let(:dependency_name) { "dotnet/framework/aspnet" }
      let(:version) { "4.8.1-20251014-windowsservercore-ltsc2022" }
      let(:tags_fixture_name) { "aspnet_with_future_tags.json" }
      let(:repo_url) { "https://registry.hub.docker.com/v2/dotnet/framework/aspnet/" }
      let(:source) { { tag: version } }

      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end

      before do
        Dependabot::Experiments.register(:docker_created_timestamp_validation, true)
        allow(checker).to receive(:fetch_manifest_platforms).and_return(nil)

        stub_request(:head, repo_url + "manifests/4.8.1-20251014-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response))
        stub_request(:head, repo_url + "manifests/4.8.2-20990301-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response.gsub("3ea1ca1", "9jf26f6")))
        stub_request(:head, repo_url + "manifests/4.8.1-20990301-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response.gsub("3ea1ca1", "7hd04d4")))
        stub_request(:head, repo_url + "manifests/4.8-20250909-windowsservercore-ltsc2022")
          .and_return(status: 200, body: "", headers: JSON.parse(headers_response.gsub("3ea1ca1", "5fb82b2")))

        allow(checker).to receive(:fetch_image_config_created) do |tag_name|
          case tag_name
          when "4.8.1-20251014-windowsservercore-ltsc2022"
            Time.parse("2025-10-14T18:06:45Z")
          when "4.8.1-20990301-windowsservercore-ltsc2022"
            Time.parse("2099-03-01T10:00:00Z")
          when "4.8.2-20990301-windowsservercore-ltsc2022"
            Time.parse("2099-03-01T10:00:00Z")
          when "4.8-20250909-windowsservercore-ltsc2022"
            Time.parse("2025-09-09T18:06:45Z")
          when "4.8.2-windowsservercore-ltsc2022"
            # Non-dated tag has an even newer timestamp — but should NOT be picked
            Time.parse("2099-03-15T12:00:00Z")
          end
        end
      end

      after { Dependabot::Experiments.reset! }

      it "picks the dated 4.8.2-20990301, not the non-dated 4.8.2" do
        expect(checker.latest_version).to eq("4.8.2-20990301-windowsservercore-ltsc2022")
      end
    end
  end

  describe "multi-platform validation" do
    let(:dependency_name) { "nginx" }
    let(:repo_url) { "https://registry.hub.docker.com/v2/library/nginx/" }
    let(:tags_fixture_name) { "multi_platform.json" }
    let(:source) { { tag: version } }

    before do
      Dependabot::Experiments.register(:docker_created_timestamp_validation, true)
    end

    after { Dependabot::Experiments.reset! }

    context "when candidate has all platforms with valid timestamps" do
      let(:version) { "1.25.3" }

      before do
        current_platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" }
        ]
        candidate_platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" }
        ]

        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.3").and_return(current_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.4").and_return(candidate_platforms)

        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.3").and_return(
          {
            "linux/amd64" => Time.parse("2024-01-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2024-01-01T10:30:00Z")
          }
        )
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.4").and_return(
          {
            "linux/amd64" => Time.parse("2024-03-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2024-03-01T10:30:00Z")
          }
        )
      end

      it "updates to the candidate tag" do
        expect(checker.latest_version).to eq("1.25.4")
      end
    end

    context "when candidate is missing a platform from current" do
      let(:version) { "1.25.3" }

      before do
        current_platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" },
          { "os" => "linux", "architecture" => "s390x" }
        ]
        # 1.25.4 missing s390x
        candidate_1254_platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" }
        ]
        # 1.25.2 has all platforms
        candidate_1252_platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" },
          { "os" => "linux", "architecture" => "s390x" }
        ]

        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.3").and_return(current_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.4").and_return(candidate_1254_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.2").and_return(candidate_1252_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.1").and_return(current_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.0").and_return(current_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.24.0").and_return(current_platforms)

        all_timestamps = {
          "linux/amd64" => Time.parse("2024-03-01T10:00:00Z"),
          "linux/arm64/v8" => Time.parse("2024-03-01T10:30:00Z"),
          "linux/s390x" => Time.parse("2024-03-01T11:00:00Z")
        }
        allow(checker).to receive(:fetch_all_platform_timestamps).and_return(all_timestamps)
      end

      it "skips the candidate missing a platform and falls back to current" do
        expect(checker.latest_version).to eq("1.25.3")
      end
    end

    context "when candidate platform was built before current (beyond 3h tolerance)" do
      let(:version) { "1.25.3" }

      before do
        platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" }
        ]

        allow(checker).to receive(:fetch_manifest_platforms).and_return(platforms)

        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.3").and_return(
          {
            "linux/amd64" => Time.parse("2024-03-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2024-03-01T10:30:00Z")
          }
        )
        # candidate arm64 is older than current arm64 by more than 3 hours
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.4").and_return(
          {
            "linux/amd64" => Time.parse("2024-03-02T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2024-03-01T05:00:00Z")
          }
        )
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.2").and_return(
          {
            "linux/amd64" => Time.parse("2024-03-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2024-03-01T10:30:00Z")
          }
        )
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.1").and_return(
          {
            "linux/amd64" => Time.parse("2024-02-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2024-02-01T10:30:00Z")
          }
        )
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.0").and_return(
          {
            "linux/amd64" => Time.parse("2024-01-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2024-01-01T10:30:00Z")
          }
        )
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.24.0").and_return(
          {
            "linux/amd64" => Time.parse("2023-12-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2023-12-01T10:30:00Z")
          }
        )
      end

      it "skips the stale candidate and falls back to current" do
        expect(checker.latest_version).to eq("1.25.3")
      end
    end

    context "when candidate platform timestamps are within 3h tolerance" do
      let(:version) { "1.25.3" }

      before do
        platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" }
        ]

        allow(checker).to receive(:fetch_manifest_platforms).and_return(platforms)

        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.3").and_return(
          {
            "linux/amd64" => Time.parse("2024-03-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2024-03-01T10:30:00Z")
          }
        )
        # candidate arm64 is 2h older than current arm64 — within 3h tolerance
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.4").and_return(
          {
            "linux/amd64" => Time.parse("2024-03-02T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2024-03-01T08:30:00Z")
          }
        )
      end

      it "accepts the candidate since timestamps are within tolerance" do
        expect(checker.latest_version).to eq("1.25.4")
      end
    end

    context "when current tag is single-platform (not a manifest list)" do
      let(:version) { "1.25.3" }

      before do
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.3").and_return(nil)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.4").and_return(nil)

        # Falls back to simple timestamp comparison
        allow(checker).to receive(:fetch_image_config_created).with("1.25.3")
                                                              .and_return(Time.parse("2024-01-01T10:00:00Z"))
        allow(checker).to receive(:fetch_image_config_created).with("1.25.4")
                                                              .and_return(Time.parse("2024-03-01T10:00:00Z"))
      end

      it "skips multi-platform validation and uses simple timestamp comparison" do
        expect(checker.latest_version).to eq("1.25.4")
      end
    end

    context "when candidate is single-platform but current is multi-platform" do
      let(:version) { "1.25.3" }

      before do
        current_platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" }
        ]

        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.3").and_return(current_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.4").and_return(nil)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.2").and_return(nil)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.1").and_return(nil)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.0").and_return(nil)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.24.0").and_return(nil)
      end

      it "rejects the single-platform candidate" do
        expect(checker.latest_version).to eq("1.25.3")
      end
    end

    context "when timestamps are unavailable for all platforms" do
      let(:version) { "1.25.3" }

      before do
        platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" }
        ]

        allow(checker).to receive_messages(
          fetch_manifest_platforms: platforms,
          fetch_all_platform_timestamps: {
            "linux/amd64" => nil,
            "linux/arm64/v8" => nil
          }
        )
      end

      it "trusts semver ordering (both timestamps nil)" do
        expect(checker.latest_version).to eq("1.25.4")
      end
    end

    context "when only candidate timestamp is unavailable for a platform" do
      let(:version) { "1.25.3" }

      before do
        platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" }
        ]

        allow(checker).to receive(:fetch_manifest_platforms).and_return(platforms)

        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.3").and_return(
          {
            "linux/amd64" => Time.parse("2024-01-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2024-01-01T10:30:00Z")
          }
        )
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.4").and_return(
          {
            "linux/amd64" => Time.parse("2024-03-01T10:00:00Z"),
            "linux/arm64/v8" => nil
          }
        )
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.2").and_return(
          {
            "linux/amd64" => Time.parse("2024-01-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2024-01-01T10:30:00Z")
          }
        )
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.1").and_return(
          {
            "linux/amd64" => Time.parse("2023-12-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2023-12-01T10:30:00Z")
          }
        )
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.25.0").and_return(
          {
            "linux/amd64" => Time.parse("2023-11-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2023-11-01T10:30:00Z")
          }
        )
        allow(checker).to receive(:fetch_all_platform_timestamps).with("1.24.0").and_return(
          {
            "linux/amd64" => Time.parse("2023-10-01T10:00:00Z"),
            "linux/arm64/v8" => Time.parse("2023-10-01T10:30:00Z")
          }
        )
      end

      it "conservatively rejects the candidate and falls back" do
        expect(checker.latest_version).to eq("1.25.3")
      end
    end

    context "when first candidate fails validation but second passes" do
      let(:version) { "1.25.2" }

      before do
        platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" }
        ]
        missing_platform = [
          { "os" => "linux", "architecture" => "amd64" }
        ]

        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.2").and_return(platforms)
        # 1.25.4 missing arm64
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.4").and_return(missing_platform)
        # 1.25.3 has all platforms
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.3").and_return(platforms)

        all_timestamps = {
          "linux/amd64" => Time.parse("2024-03-01T10:00:00Z"),
          "linux/arm64/v8" => Time.parse("2024-03-01T10:30:00Z")
        }
        allow(checker).to receive(:fetch_all_platform_timestamps).and_return(all_timestamps)
      end

      it "skips the first candidate and returns the second" do
        expect(checker.latest_version).to eq("1.25.3")
      end
    end

    context "when all candidates fail validation" do
      let(:version) { "1.25.2" }

      before do
        current_platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" },
          { "os" => "linux", "architecture" => "s390x" }
        ]
        # All candidates missing s390x
        candidate_platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" }
        ]

        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.2").and_return(current_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.4").and_return(candidate_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.3").and_return(candidate_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.1").and_return(candidate_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.25.0").and_return(candidate_platforms)
        allow(checker).to receive(:fetch_manifest_platforms).with("1.24.0").and_return(candidate_platforms)
      end

      it "returns the current tag" do
        expect(checker.latest_version).to eq("1.25.2")
      end
    end

    context "when more candidates fail than MAX_PLATFORM_VALIDATION_ATTEMPTS" do
      let(:tags_fixture_name) { "multi_platform_many_tags.json" }
      let(:version) { "1.24.0" }

      before do
        current_platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" },
          { "os" => "linux", "architecture" => "s390x" }
        ]
        # All candidates missing s390x — every validation will fail
        candidate_platforms = [
          { "os" => "linux", "architecture" => "amd64" },
          { "os" => "linux", "architecture" => "arm64", "variant" => "v8" }
        ]

        allow(checker).to receive(:fetch_manifest_platforms).with("1.24.0").and_return(current_platforms)
        # Stub all candidates to fail validation
        %w(1.25.7 1.25.6 1.25.5 1.25.4 1.25.3 1.25.2 1.25.1 1.25.0).each do |tag|
          allow(checker).to receive(:fetch_manifest_platforms).with(tag).and_return(candidate_platforms)
        end
      end

      it "stops validating after MAX_PLATFORM_VALIDATION_ATTEMPTS and accepts the next candidate" do
        # With 8 candidates above 1.24.0 and a cap of 5, the 6th candidate (1.25.2)
        # is accepted without timestamp validation
        expect(checker.latest_version).to eq("1.25.2")
      end

      it "does not call fetch_manifest_platforms more than MAX_PLATFORM_VALIDATION_ATTEMPTS times for candidates" do
        checker.latest_version

        # The cap should prevent validation of candidates beyond the limit.
        # 5 candidates validated (1.25.7..1.25.3) + 1 current tag fetch = at most 6 calls
        # for unique tags, but the 6th candidate (1.25.2) is accepted without validation.
        failed_candidate_tags = %w(1.25.7 1.25.6 1.25.5 1.25.4 1.25.3)
        failed_candidate_tags.each do |tag|
          expect(checker).to have_received(:fetch_manifest_platforms).with(tag)
        end
        # Tags beyond the cap should NOT have been validated
        expect(checker).not_to have_received(:fetch_manifest_platforms).with("1.25.1")
        expect(checker).not_to have_received(:fetch_manifest_platforms).with("1.25.0")
      end
    end
  end

  describe "#version_related_pattern?" do
    context "when docker_created_timestamp_validation is disabled (legacy patterns)" do
      it "filters mixed alphanumeric identifiers with digits via broad regex" do
        expect(checker.send(:version_related_pattern?, "alpine3")).to be true
        expect(checker.send(:version_related_pattern?, "ltsc2022")).to be true
        expect(checker.send(:version_related_pattern?, "ltsc2019")).to be true
        expect(checker.send(:version_related_pattern?, "nanoserver1809")).to be true
        expect(checker.send(:version_related_pattern?, "rc1")).to be true
        expect(checker.send(:version_related_pattern?, "beta2")).to be true
        expect(checker.send(:version_related_pattern?, "alpha3")).to be true
      end

      it "filters rc and jre as known versioning tokens" do
        expect(checker.send(:version_related_pattern?, "rc")).to be true
        expect(checker.send(:version_related_pattern?, "jre")).to be true
      end

      it "does not filter pure-letter identifiers without digits" do
        expect(checker.send(:version_related_pattern?, "alpha")).to be false
        expect(checker.send(:version_related_pattern?, "dev")).to be false
        expect(checker.send(:version_related_pattern?, "preview")).to be false
        expect(checker.send(:version_related_pattern?, "nightly")).to be false
        expect(checker.send(:version_related_pattern?, "snapshot")).to be false
        expect(checker.send(:version_related_pattern?, "canary")).to be false
        expect(checker.send(:version_related_pattern?, "ea")).to be false
      end

      it "filters purely numeric parts" do
        expect(checker.send(:version_related_pattern?, "123")).to be true
        expect(checker.send(:version_related_pattern?, "20250909")).to be true
      end

      it "filters structural version patterns" do
        expect(checker.send(:version_related_pattern?, "1.2")).to be true
        expect(checker.send(:version_related_pattern?, "v2")).to be true
        expect(checker.send(:version_related_pattern?, "KB4505057")).to be true
        expect(checker.send(:version_related_pattern?, "kb4487017")).to be true
        expect(checker.send(:version_related_pattern?, "0a1")).to be true
        expect(checker.send(:version_related_pattern?, "0b1")).to be true
        expect(checker.send(:version_related_pattern?, "0rc1")).to be true
      end

      it "does not filter pure-letter platform names" do
        expect(checker.send(:version_related_pattern?, "bookworm")).to be false
        expect(checker.send(:version_related_pattern?, "bullseye")).to be false
        expect(checker.send(:version_related_pattern?, "windowsservercore")).to be false
        expect(checker.send(:version_related_pattern?, "alpine")).to be false
        expect(checker.send(:version_related_pattern?, "slim")).to be false
        expect(checker.send(:version_related_pattern?, "nanoserver")).to be false
      end
    end

    context "when docker_created_timestamp_validation is enabled" do
      before { Dependabot::Experiments.register(:docker_created_timestamp_validation, true) }
      after { Dependabot::Experiments.reset! }

      it "does not filter platform identifiers that contain digits" do
        expect(checker.send(:version_related_pattern?, "alpine3")).to be false
        expect(checker.send(:version_related_pattern?, "ltsc2022")).to be false
        expect(checker.send(:version_related_pattern?, "ltsc2019")).to be false
        expect(checker.send(:version_related_pattern?, "nanoserver1809")).to be false
      end

      it "does not filter non-structural identifiers (handled by suffix matching instead)" do
        expect(checker.send(:version_related_pattern?, "rc1")).to be false
        expect(checker.send(:version_related_pattern?, "beta2")).to be false
        expect(checker.send(:version_related_pattern?, "alpha")).to be false
        expect(checker.send(:version_related_pattern?, "alpha3")).to be false
        expect(checker.send(:version_related_pattern?, "dev")).to be false
        expect(checker.send(:version_related_pattern?, "preview")).to be false
        expect(checker.send(:version_related_pattern?, "nightly")).to be false
        expect(checker.send(:version_related_pattern?, "snapshot")).to be false
        expect(checker.send(:version_related_pattern?, "canary")).to be false
        expect(checker.send(:version_related_pattern?, "ea")).to be false
        expect(checker.send(:version_related_pattern?, "rc")).to be false
        expect(checker.send(:version_related_pattern?, "jre")).to be false
      end

      it "filters purely numeric parts" do
        expect(checker.send(:version_related_pattern?, "123")).to be true
        expect(checker.send(:version_related_pattern?, "20250909")).to be true
      end

      it "filters structural version patterns" do
        expect(checker.send(:version_related_pattern?, "1.2")).to be true
        expect(checker.send(:version_related_pattern?, "v2")).to be true
        expect(checker.send(:version_related_pattern?, "KB4505057")).to be true
        expect(checker.send(:version_related_pattern?, "kb4487017")).to be true
        expect(checker.send(:version_related_pattern?, "0a1")).to be true
        expect(checker.send(:version_related_pattern?, "0b1")).to be true
        expect(checker.send(:version_related_pattern?, "0rc1")).to be true
      end

      it "does not filter pure-letter platform names" do
        expect(checker.send(:version_related_pattern?, "bookworm")).to be false
        expect(checker.send(:version_related_pattern?, "bullseye")).to be false
        expect(checker.send(:version_related_pattern?, "windowsservercore")).to be false
        expect(checker.send(:version_related_pattern?, "alpine")).to be false
        expect(checker.send(:version_related_pattern?, "slim")).to be false
        expect(checker.send(:version_related_pattern?, "nanoserver")).to be false
      end
    end
  end

  describe "#cooldown_period?" do
    let(:version) { "1.0.0" }
    let(:update_cooldown) do
      Dependabot::Package::ReleaseCooldownOptions.new(
        default_days: 5,
        semver_major_days: 14,
        semver_minor_days: 7,
        semver_patch_days: 2
      )
    end
    let(:release_date) { Time.now - (8 * 24 * 60 * 60) }

    it "uses semver_major_days for major updates" do
      candidate_tag = Dependabot::Docker::Tag.new("2.0.0")

      expect(checker.send(:cooldown_period?, release_date, candidate_tag)).to be true
    end

    it "uses semver_minor_days for minor updates" do
      candidate_tag = Dependabot::Docker::Tag.new("1.1.0")

      expect(checker.send(:cooldown_period?, release_date, candidate_tag)).to be false
    end

    it "uses semver_patch_days for patch updates" do
      candidate_tag = Dependabot::Docker::Tag.new("1.0.1")

      expect(checker.send(:cooldown_period?, release_date, candidate_tag)).to be false
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
        expect(checker.updated_requirements)
          .to eq(
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
          fixture("docker", "registry_manifest_headers", "generic.json")
        stub_request(:head, repo_url + "manifests/latest")
          .and_return(status: 200, body: "", headers: JSON.parse(new_headers))
      end

      it "updates the digest" do
        expect(checker.updated_requirements)
          .to eq(
            [{
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: {
                digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
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
          fixture("docker", "registry_manifest_headers", "generic.json")
        stub_request(:head, repo_url + "manifests/17.10")
          .and_return(status: 200, body: "", headers: JSON.parse(new_headers))
      end

      it "updates the tag and the digest" do
        expect(checker.updated_requirements)
          .to eq(
            [{
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: {
                digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                        "ca97eba880ebf600d68608",
                tag: "17.10"
              }
            }]
          )
      end
    end

    context "when specified with tags with different prefixes in separate files" do
      let(:version) { "trusty-20170728" }
      let(:source) { { tag: "trusty-20170728" } }

      before do
        dependency.requirements << {
          requirement: nil,
          groups: [],
          file: "Dockerfile.other",
          source: { tag: "xenial-20170802" }
        }
      end

      it "updates the tags" do
        expect(checker.updated_requirements)
          .to eq(
            [{
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "trusty-20170817" }
            },
             {
               requirement: nil,
               groups: [],
               file: "Dockerfile.other",
               source: { tag: "xenial-20170915" }
             }]
          )
      end
    end

    context "when docker_pin_digests experiment is enabled" do
      before do
        Dependabot::Experiments.register(:docker_pin_digests, true)
        new_headers =
          fixture("docker", "registry_manifest_headers", "generic.json")
        stub_request(:head, repo_url + "manifests/17.10")
          .and_return(status: 200, body: "", headers: JSON.parse(new_headers))
      end

      after do
        Dependabot::Experiments.reset!
      end

      context "when specified with a tag only (no digest)" do
        let(:source) { { tag: version } }

        it "adds a digest to the tag" do
          expect(checker.updated_requirements)
            .to eq(
              [{
                requirement: nil,
                groups: [],
                file: "Dockerfile",
                source: {
                  tag: "17.10",
                  digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                          "ca97eba880ebf600d68608"
                }
              }]
            )
        end
      end

      context "when specified with a tag and a digest" do
        let(:source) { { digest: "old_digest", tag: "17.04" } }

        it "updates both the tag and the digest" do
          expect(checker.updated_requirements)
            .to eq(
              [{
                requirement: nil,
                groups: [],
                file: "Dockerfile",
                source: {
                  digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
                          "ca97eba880ebf600d68608",
                  tag: "17.10"
                }
              }]
            )
        end
      end
    end

    context "when docker_pin_digests experiment is disabled" do
      before do
        Dependabot::Experiments.register(:docker_pin_digests, false)
      end

      after do
        Dependabot::Experiments.reset!
      end

      context "when specified with a tag only (no digest)" do
        let(:source) { { tag: version } }

        it "does not add a digest" do
          expect(checker.updated_requirements)
            .to eq(
              [{
                requirement: nil,
                groups: [],
                file: "Dockerfile",
                source: { tag: "17.10" }
              }]
            )
        end
      end
    end
  end

  describe ".docker_read_timeout_in_seconds" do
    context "when DEPENDABOT_DOCKER_READ_TIMEOUT_IN_SECONDS is set" do
      it "returns the provided value" do
        override_value = 10
        stub_const("ENV", ENV.to_hash.merge("DEPENDABOT_DOCKER_READ_TIMEOUT_IN_SECONDS" => override_value))
        expect(checker.send(:docker_read_timeout_in_seconds)).to eq(override_value)
      end
    end

    context "when ENV does not provide an override" do
      it "falls back to a default value" do
        expect(checker.send(:docker_read_timeout_in_seconds))
          .to eq(Dependabot::Docker::UpdateChecker::DEFAULT_DOCKER_READ_TIMEOUT_IN_SECONDS)
      end
    end
  end

  describe ".docker_open_timeout_in_seconds" do
    context "when DEPENDABOT_DOCKER_OPEN_TIMEOUT_IN_SECONDS is set" do
      it "returns the provided value" do
        override_value = 10
        stub_const("ENV", ENV.to_hash.merge("DEPENDABOT_DOCKER_OPEN_TIMEOUT_IN_SECONDS" => override_value))
        expect(checker.send(:docker_open_timeout_in_seconds)).to eq(override_value)
      end
    end

    context "when ENV does not provide an override" do
      it "falls back to a default value" do
        expect(checker.send(:docker_open_timeout_in_seconds))
          .to eq(Dependabot::Docker::UpdateChecker::DEFAULT_DOCKER_OPEN_TIMEOUT_IN_SECONDS)
      end
    end
  end

  describe "#get_tag_publication_details" do
    subject(:get_tag_publication_details) do
      checker.send(:get_tag_publication_details, tag)
    end

    let(:tag) { Dependabot::Docker::Tag.new("1.0.0") }
    let(:registry_url) { "https://registry.hub.docker.com" }
    let(:dependency_name) { "ubuntu" }
    let(:version) { "17.10" }
    let(:mock_client) { instance_double(DockerRegistry2::Registry) }
    let(:blob_headers) { { last_modified: "Mon, 15 Jan 2024 10:00:00 GMT" } }
    let(:mock_blob_response) { instance_double(RestClient::Response, headers: blob_headers) }

    before do
      allow(checker).to receive(:docker_registry_client).and_return(mock_client)
      allow(mock_client).to receive(:dohead).and_return(mock_blob_response)
    end

    context "when client.digest returns a String" do
      let(:digest_string) { "sha256:abc123" }

      before do
        allow(mock_client).to receive(:digest).and_return(digest_string)
      end

      it "handles the String case and returns publication details" do
        result = get_tag_publication_details
        expect(result).to be_a(Dependabot::Package::PackageRelease)
        expect(result.released_at).to eq(Time.parse("Mon, 15 Jan 2024 10:00:00 GMT"))
      end

      it "uses the blobs endpoint for a single-image digest" do
        get_tag_publication_details
        expect(mock_client).to have_received(:dohead).with("v2/ubuntu/blobs/sha256:abc123")
      end
    end

    context "when client.digest returns an Array" do
      let(:digest_array) { [{ "digest" => "sha256:def456" }] }

      before do
        allow(mock_client).to receive(:digest).and_return(digest_array)
      end

      it "handles the Array case and returns publication details" do
        result = get_tag_publication_details
        expect(result).to be_a(Dependabot::Package::PackageRelease)
        expect(result.released_at).to eq(Time.parse("Mon, 15 Jan 2024 10:00:00 GMT"))
      end

      it "uses the manifests endpoint for a manifest-list digest" do
        get_tag_publication_details
        expect(mock_client).to have_received(:dohead).with("v2/ubuntu/manifests/sha256:def456")
      end
    end

    context "when client.digest returns an empty Array" do
      let(:empty_array) { [] }

      before do
        allow(mock_client).to receive(:digest).and_return(empty_array)
        allow(Dependabot.logger).to receive(:warn)
      end

      it "returns nil and logs a warning" do
        expect(get_tag_publication_details).to be_nil
        expect(Dependabot.logger).to have_received(:warn).with(
          /Empty digest_info array/
        )
      end
    end

    context "when client.digest returns nil" do
      before do
        allow(mock_client).to receive(:digest).and_return(nil)
        allow(Dependabot.logger).to receive(:warn)
      end

      it "returns nil and logs a warning" do
        expect(get_tag_publication_details).to be_nil
        expect(Dependabot.logger).to have_received(:warn).with(
          /Unexpected digest_info type.*NilClass/
        )
      end
    end

    context "when tag has a 'v' prefix" do
      let(:tag) { Dependabot::Docker::Tag.new("v2.7.2") }
      let(:digest_string) { "sha256:abc123" }

      before do
        allow(mock_client).to receive(:digest).and_return(digest_string)
      end

      it "handles the version prefix correctly and returns publication details" do
        result = get_tag_publication_details
        expect(result).to be_a(Dependabot::Package::PackageRelease)
        expect(result.version).to be_a(Dependabot::Docker::Version)
        expect(result.released_at).to eq(Time.parse("Mon, 15 Jan 2024 10:00:00 GMT"))
      end

      it "creates a Docker::Version instead of base Dependabot::Version" do
        result = get_tag_publication_details
        expect(result.version).to be_a(Dependabot::Docker::Version)
        expect(result.version.class).to eq(Dependabot::Docker::Version)
      end
    end
  end

  describe "#digest_up_to_date?" do
    subject(:digest_up_to_date?) { checker.send(:digest_up_to_date?) }

    let(:headers_response) do
      fixture("docker", "registry_manifest_headers", "generic.json")
    end

    context "when a tag and digest are present and match the latest digest" do
      let(:version) { "17.10" }
      let(:source) do
        {
          tag: "17.10",
          digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86ca97eba880ebf600d68608"
        }
      end

      before do
        stub_request(:head, repo_url + "manifests/17.10")
          .and_return(status: 200, headers: JSON.parse(headers_response))
      end

      it "returns true" do
        expect(digest_up_to_date?).to be true
      end
    end

    context "when a tag and digest are present but do not match" do
      let(:version) { "17.10" }
      let(:source) do
        {
          tag: "17.10",
          digest: "old_digest"
        }
      end

      before do
        stub_request(:head, repo_url + "manifests/17.10")
          .and_return(status: 200, headers: JSON.parse(headers_response))
      end

      it "returns false" do
        expect(digest_up_to_date?).to be false
      end
    end

    context "when only a digest is present (no tag)" do
      let(:version) { "latest" }
      let(:source) do
        {
          digest: "old_digest"
        }
      end

      before do
        stub_request(:head, repo_url + "manifests/latest")
          .and_return(status: 200, headers: JSON.parse(headers_response))
      end

      it "compares against the updated digest and returns false if different" do
        expect(digest_up_to_date?).to be false
      end
    end

    context "when the registry does not return a digest" do
      let(:version) { "17.10" }
      let(:source) do
        {
          tag: "17.10",
          digest: "any_digest"
        }
      end

      before do
        stub_request(:head, repo_url + "manifests/17.10")
          .and_return(
            status: 200,
            headers: JSON.parse(headers_response).except("docker_content_digest")
          )
      end

      it "assumes the digest is up to date" do
        expect(digest_up_to_date?).to be true
      end
    end

    context "when multiple digest requirements are present" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: version,
          requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "17.10", digest: "old_digest" }
            },
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "17.04", digest: "old_digest" }
            }
          ],
          package_manager: "docker"
        )
      end

      before do
        stub_request(:head, repo_url + "manifests/17.10")
          .and_return(status: 200, headers: JSON.parse(headers_response))

        stub_request(:head, repo_url + "manifests/17.04")
          .and_return(status: 200, headers: JSON.parse(headers_response))
      end

      it "returns false if any digest is out of date" do
        expect(digest_up_to_date?).to be false
      end
    end

    context "when one requirement has no expected digest and others match" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: version,
          requirements: [
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "17.10", digest: "any_digest" }
            },
            {
              requirement: nil,
              groups: [],
              file: "Dockerfile",
              source: { tag: "17.04", digest: "3ea1ca1aa8483a38081750953ad75046e6cc9f6b86ca97eba880ebf600d68608" }
            }
          ],
          package_manager: "docker"
        )
      end

      before do
        stub_tag_with_no_digest("17.10")

        stub_request(:head, repo_url + "manifests/17.04")
          .and_return(status: 200, headers: JSON.parse(headers_response))
      end

      it "returns true" do
        expect(digest_up_to_date?).to be true
      end
    end
  end

  private

  def stub_same_sha_for(*tags)
    tags.each do |tag|
      stub_request(:head, repo_url + "manifests/#{tag}")
        .and_return(
          status: 200,
          body: "",
          headers: JSON.parse(headers_response.gsub(/"sha256:(.*)"/, "\"sha256:#{'a' * 40}\""))
        )
    end
  end
end
