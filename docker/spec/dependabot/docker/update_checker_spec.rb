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
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
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
  let(:registry_tags) { fixture("docker", "registry_tags", tags_fixture_name) }
  let(:tags_fixture_name) { "ubuntu_no_latest.json" }

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

    context "given an outdated requirement" do
      let(:version) { "17.10" }

      before do
        dependency.requirements << {
          requirement: nil,
          groups: [],
          file: "Dockerfile.other",
          source: { tag: "17.04" }
        }
      end

      it { is_expected.to be_truthy }
    end

    context "given a purely numeric version" do
      let(:version) { "1234567890" }
      it { is_expected.to be_truthy }
    end

    context "given a non-numeric version" do
      let(:version) { "artful" }
      it { is_expected.to be_falsey }

      context "and a digest" do
        let(:source) { { digest: "old_digest" } }
        let(:headers_response) do
          fixture("docker", "registry_manifest_headers", "generic.json")
        end

        before do
          stub_request(:head, repo_url + "manifests/artful").
            and_return(status: 200, headers: JSON.parse(headers_response))
        end

        context "that is out-of-date" do
          let(:source) { { digest: "old_digest" } }
          it { is_expected.to be_truthy }

          context "but the response doesn't include a new digest" do
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

        context "that is up-to-date" do
          let(:source) do
            {
              digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86ca97" \
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
      let(:tags_fixture_name) { "python.json" }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
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

    context "when versions at different specificities look equal" do
      let(:dependency_name) { "ruby" }
      let(:version) { "2.4.0-slim" }
      let(:tags_fixture_name) { "ruby_25.json" }
      before do
        tags_url = "https://registry.hub.docker.com/v2/library/ruby/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("2.5.0-slim") }
    end

    context "raise_on_ignored when later versions are allowed" do
      let(:raise_on_ignored) { true }
      it "doesn't raise an error" do
        expect { subject }.to_not raise_error
      end
    end

    context "when already on the latest version" do
      let(:version) { "17.10" }
      it { is_expected.to eq("17.10") }

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "doesn't raise an error" do
          expect { subject }.to_not raise_error
        end
      end
    end

    context "when all later versions are being ignored" do
      let(:ignored_versions) { [">= 17.10"] }
      it { is_expected.to eq("17.04") }

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "raises an error" do
          expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
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

      context "raise_on_ignored" do
        let(:raise_on_ignored) { true }
        it "raises an error" do
          expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "when there are also date-like versions" do
      let(:tags_fixture_name) { "windows-servercore.json" }
      let(:version) { "10.0.16299.1087" }

      it { is_expected.to eq("10.0.18362.175") }

      context "and we're using one" do
        let(:version) { "1803" }
        it { is_expected.to eq("1903") }
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
        stub_request(:head, repo_url + "manifests/17.10").
          and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )

        # Stub the latest version to return a different digest
        ["17.04", "latest"].each do |version|
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

      context "for an older version of the prefix" do
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

        context "for a private registry" do
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
            expect { checker.latest_version }.
              to raise_error(Dependabot::PrivateSourceTimedOut)
          end
        end
      end
    end

    context "when the dependency's version has a suffix" do
      let(:dependency_name) { "ruby" }
      let(:version) { "2.4.0-slim" }
      let(:tags_fixture_name) { "ruby.json" }
      before do
        tags_url = "https://registry.hub.docker.com/v2/library/ruby/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)
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
        stub_request(:get, repo_url + "tags/list").
          and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}").
          and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )

        # Stub the latest version to return a different digest
        ["jdk-11.0.2.9", "latest"].each do |version|
          stub_request(:head, repo_url + "manifests/#{version}").
            and_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2"))
            )
        end

        # Stub an oddly-formatted version to come back as a pre-release
        stub_request(:head, repo_url + "manifests/jdk-11.28").
          and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response.gsub("3ea1ca1", "11171a2"))
          )
      end

      it { is_expected.to eq("jdk-11.0.2.9-alpine-slim") }
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
        stub_request(:get, repo_url + "tags/list").
          and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}").
          and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )

        # Stub the latest version to return a different digest
        ["17.0.2_8-jre-alpine", "latest"].each do |version|
          stub_request(:head, repo_url + "manifests/#{version}").
            and_return(
              status: 200,
              body: "",
              headers: JSON.parse(headers_response.gsub("3ea1ca1", "4da71a2"))
            )
        end
      end

      context "followed by numbers" do
        let(:version) { "17.0.1_12-jre-alpine" }
        it { is_expected.to eq("17.0.2_8-jre-alpine") }
      end

      context "followed by numbers and with less components than other version but higher underscore part" do
        before do
          stub_request(:head, repo_url + "manifests/#{latest_version}").
            and_return(
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

    context "when the dependencies have an underscore followed by sha-like strings" do
      let(:dependency_name) { "nixos/nix" }
      let(:tags_fixture_name) { "nixos-nix.json" }
      let(:repo_url) do
        "https://registry.hub.docker.com/v2/nixos/nix/"
      end
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end
      before do
        stub_request(:get, repo_url + "tags/list").
          and_return(status: 200, body: registry_tags)

        stub_request(:head, repo_url + "manifests/#{version}").
          and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )
      end

      let(:version) { "2.1.3" }

      it "ignores the sha-like part" do
        expect(subject).to eq("2.10.0")
      end
    end

    context "when the dependency has a namespace" do
      let(:dependency_name) { "moj/ruby" }
      let(:version) { "2.4.0" }
      let(:tags_fixture_name) { "ruby.json" }
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
      let(:repo_url) { "https://registry.hub.docker.com/v2/library/python/" }
      let(:dependency_name) { "python" }
      let(:version) { "3.5" }
      let(:tags_fixture_name) { "python.json" }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end
      before do
        tags_url = "https://registry.hub.docker.com/v2/library/python/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)

        stub_same_sha_for("3.6", "3.6.3")
      end

      it { is_expected.to eq("3.6") }

      context "and the current version is a pre-release" do
        let(:version) { "3.7.0a1" }
        it { is_expected.to eq("3.7.0a2") }
      end
    end

    context "when the latest tag points to an older version" do
      let(:tags_fixture_name) { "dotnet.json" }
      let(:headers_response) do
        fixture("docker", "registry_manifest_headers", "generic.json")
      end
      let(:version) { "2.0-sdk" }
      let(:latest_versions) { %w(2-sdk 2.1-sdk 2.1.401-sdk) }

      before do
        stub_request(:head, repo_url + "manifests/2.2-sdk").
          and_return(
            status: 200,
            body: "",
            headers: JSON.parse(headers_response)
          )

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

      it { is_expected.to eq("2.1-sdk") }

      context "and a suffix" do
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
          stub_request(:get, repo_url + "tags/list").
            and_return(
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
          stub_request(:get, repo_url + "tags/list?last=#{last}").
            and_return(
              status: 200,
              body: fixture("docker", "registry_tags", "dotnet_page_2.json"),
              headers: JSON.parse(end_pagination_headers)
            )
        end

        it { is_expected.to eq("2.1-sdk") }
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

        it { is_expected.to eq("2.1-sdk") }

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
      let(:tags_fixture_name) { "python.json" }
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
      let(:tags_fixture_name) { "ubuntu_no_latest.json" }

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
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "docker_registry",
            "registry" => "registry-host.io:5000",
            "username" => "grey",
            "password" => "pa55word"
          }]
        end

        before do
          tags_url = "https://registry-host.io:5000/v2/ubuntu/tags/list"
          stub_request(:get, tags_url).
            and_return(status: 200, body: registry_tags)
        end

        it { is_expected.to eq("17.10") }

        context "that don't have a username or password" do
          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "docker_registry",
              "registry" => "registry-host.io:5000"
            }]
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
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "docker_registry",
            "registry" => "registry-host.io:5000",
            "username" => "grey",
            "password" => "pa55word",
            "replaces-base" => false
          }]
        end

        before do
          tags_url = "https:/registry.hub.docker.com/v2/ubuntu/tags/list"
          stub_request(:get, tags_url).
            and_return(status: 200, body: registry_tags)
        end

        it { is_expected.to eq("17.10") }
      end

      context "with replaces-base set to true and with authentication credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }, {
            "type" => "docker_registry",
            "registry" => "registry-host.io:5000",
            "username" => "grey",
            "password" => "pa55word",
            "replaces-base" => true
          }]
        end

        before do
          tags_url = "https://registry-host.io:5000/v2/ubuntu/tags/list"
          stub_request(:get, tags_url).
            and_return(status: 200, body: registry_tags)
        end

        it { is_expected.to eq("17.10") }

        context "with replaces-base set to true and no username or password" do
          before do
            tags_url = "https://registry-host.io:5000/v2/ubuntu/tags/list"
            stub_request(:get, tags_url).
              and_return(
                status: 401,
                body: "",
                headers: { "www_authenticate" => "basic 123" }
              )
          end

          let(:credentials) do
            [{
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            }, {
              "type" => "docker_registry",
              "registry" => "registry-host.io:5000",
              "replaces-base" => true
            }]
          end

          it "raises a to PrivateSourceAuthenticationFailure error" do
            error_class = Dependabot::PrivateSourceAuthenticationFailure
            expect { checker.latest_version }.
              to raise_error(error_class) do |error|
                expect(error.source).to eq("registry-host.io:5000")
              end
          end
        end
      end
    end

    context "when the docker registery only knows about versions older than the current version" do
      let(:dependency_name) { "jetstack/cert-manager-controller" }
      let(:version) { "v1.7.2" }
      let(:digest) { "sha256:1815870847a48a9a6f177b90005d8df273e79d00830c21af9d43e1b5d8d208b4" }
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
              digest: "sha256:18305429afa14ea462f810146ba44d4363ae76e4c8dfc38288cf73aa07485005"
            }
          }],
          package_manager: "docker"
        )
      end
      let(:tags_fixture_name) { "truncated_tag_list.json" }

      before do
        tags_url = "https://quay.io/v2/jetstack/cert-manager-controller/tags/list"
        stub_request(:get, tags_url).
          and_return(status: 200, body: registry_tags)
      end

      it { is_expected.to eq("v1.7.2") }
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
          fixture("docker", "registry_manifest_headers", "generic.json")
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
                digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
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
                digest: "sha256:3ea1ca1aa8483a38081750953ad75046e6cc9f6b86" \
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
        expect(checker.updated_requirements).
          to eq(
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
  end

  private

  def stub_same_sha_for(*tags)
    tags.each do |tag|
      stub_request(:head, repo_url + "manifests/#{tag}").
        and_return(
          status: 200,
          body: "",
          headers: JSON.parse(headers_response.gsub(/"sha256:(.*)"/, "\"sha256:#{'a' * 40}\""))
        )
    end
  end
end
