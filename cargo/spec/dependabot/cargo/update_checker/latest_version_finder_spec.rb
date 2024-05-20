# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/cargo/update_checker/latest_version_finder"

RSpec.describe Dependabot::Cargo::UpdateChecker::LatestVersionFinder do
  let(:crates_url) { "https://crates.io/api/v1/crates/#{dependency_name}" }
  let(:crates_response) { fixture("crates_io_responses", crates_fixture_name) }
  let(:crates_fixture_name) { "#{dependency_name}.json" }
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }
  let(:finder) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "Cargo.toml",
        content: fixture("manifests", manifest_fixture_name)
      ),
      Dependabot::DependencyFile.new(
        name: "Cargo.lock",
        content: fixture("lockfiles", lockfile_fixture_name)
      )
    ]
  end
  let(:manifest_fixture_name) { "bare_version_specified" }
  let(:lockfile_fixture_name) { "bare_version_specified" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: requirements,
      package_manager: "cargo"
    )
  end
  let(:requirements) do
    [{ file: "Cargo.toml", requirement: "0.1.12", groups: [], source: nil }]
  end
  let(:dependency_name) { "time" }
  let(:dependency_version) { "0.1.38" }

  describe "#latest_version" do
    subject { finder.latest_version }
    before do
      stub_request(:get, crates_url).to_return(status: 200, body: crates_response)
    end

    it { is_expected.to eq(Gem::Version.new("0.1.40")) }

    context "when the latest version is being ignored" do
      let(:ignored_versions) { [">= 0.1.40, < 2.0"] }
      it { is_expected.to eq(Gem::Version.new("0.1.39")) }
    end

    context "when the crates.io link resolves to a redirect" do
      let(:redirect_url) { "https://crates.io/api/v1/crates/Time" }

      before do
        stub_request(:get, crates_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(status: 200, body: crates_response)
      end

      it { is_expected.to eq(Gem::Version.new("0.1.40")) }
    end

    context "when the crates.io link fails at first" do
      before do
        stub_request(:get, crates_url)
          .to_raise(Excon::Error::Timeout).then
          .to_return(status: 200, body: crates_response)
      end

      it { is_expected.to eq(Gem::Version.new("0.1.40")) }
    end

    context "when the crates link resolves to a 'Not Found' page" do
      before do
        stub_request(:get, crates_url)
          .to_return(status: 404, body: crates_response)
      end
      let(:crates_fixture_name) { "not_found.json" }

      it { is_expected.to be_nil }
    end

    context "when the latest version is a pre-release" do
      let(:dependency_name) { "xdg" }
      let(:dependency_version) { "2.0.0" }
      it { is_expected.to eq(Gem::Version.new("2.1.0")) }

      context "when the user wants a pre-release" do
        context "when their current version is a pre-release" do
          let(:dependency_version) { "2.0.0-pre4" }
          it { is_expected.to eq(Gem::Version.new("3.0.0-pre1")) }
        end

        context "when their requirements indicate a preference for pre-releases" do
          let(:requirements) do
            [{
              file: "Cargo.toml",
              requirement: "~2.0.0-pre1",
              groups: ["dependencies"],
              source: nil
            }]
          end
          it { is_expected.to eq(Gem::Version.new("3.0.0-pre1")) }
        end
      end
    end

    context "when raise_on_ignored is set and later versions are allowed" do
      let(:raise_on_ignored) { true }
      it "doesn't raise an error" do
        expect { subject }.to_not raise_error
      end
    end

    context "when already on the latest version" do
      let(:dependency_version) { "0.1.40" }
      it { is_expected.to eq(Gem::Version.new("0.1.40")) }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }
        it "doesn't raise an error" do
          expect { subject }.to_not raise_error
        end
      end
    end

    context "when all later versions are being ignored" do
      let(:ignored_versions) { ["> 0.1.38"] }
      it { is_expected.to eq(Gem::Version.new("0.1.38")) }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }
        it "raises an error" do
          expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "when the dependency version isn't known" do
      let(:dependency_version) { nil }

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }
        it "doesn't raise an error" do
          expect { subject }.to_not raise_error
        end
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject { finder.lowest_security_fix_version }

    before do
      stub_request(:get, crates_url).to_return(status: 200, body: crates_response)
    end

    let(:dependency_name) { "time" }
    let(:dependency_version) { "0.1.12" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "cargo",
          vulnerable_versions: ["<= 0.1.18"]
        )
      ]
    end
    it { is_expected.to eq(Gem::Version.new("0.1.19")) }

    context "when the lowest version is being ignored" do
      let(:ignored_versions) { [">= 0.1.18, < 0.1.20"] }
      it { is_expected.to eq(Gem::Version.new("0.1.20")) }
    end

    context "when all versions are being ignored" do
      let(:ignored_versions) { [">= 0"] }
      it "returns nil" do
        expect(subject).to be_nil
      end

      context "when raise_on_ignored is enabled" do
        let(:raise_on_ignored) { true }
        it "raises an error" do
          expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "when the lowest fixed version is a pre-release" do
      let(:dependency_name) { "xdg" }
      let(:dependency_version) { "1.0.0" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "cargo",
            vulnerable_versions: ["<= 2.0.0-pre2"]
          )
        ]
      end
      it { is_expected.to eq(Gem::Version.new("2.0.0")) }

      context "when the user wants a pre-release" do
        context "when their current version is a pre-release" do
          let(:dependency_version) { "2.0.0-pre1" }
          it { is_expected.to eq(Gem::Version.new("2.0.0-pre3")) }
        end

        context "when their requirements indicate a preference for pre-releases" do
          let(:requirements) do
            [{
              file: "Cargo.toml",
              requirement: "~2.0.0-pre1",
              groups: ["dependencies"],
              source: nil
            }]
          end
          it { is_expected.to eq(Gem::Version.new("2.0.0-pre3")) }
        end
      end
    end
  end

  # Tests for sparse registry responses
  describe "Sparse registry response handling" do
    let(:sparse_registry_url) { "https://cargo.cloudsmith.io/honeyankit/test/he/ll/hello-world" }
    let(:sparse_registry_response) { fixture("private_registry_responses", crates_fixture_name) }
    let(:crates_fixture_name) { "#{dependency_name}.json" }

    let(:credentials) do
      [{
        "type" => "cargo_registry",
        "cargo_registry" => "honeyankit-test",
        "url" => "https://cargo.cloudsmith.io/honeyankit/test/",
        "token" => "token"
      }]
    end
    let(:dependency_name) { "hello-world" }
    let(:dependency_version) { "1.0.0" }
    let(:requirements) do
      [{
        file: "Cargo.toml",
        requirement: "1.0.0",
        groups: ["dependencies"],
        source: {
          type: "registry",
          name: "honeyankit-test",
          index: "sparse+https://cargo.cloudsmith.io/honeyankit/test/",
          dl: "https://dl.cloudsmith.io/basic/honeyankit/test/cargo/{crate}-{version}.crate",
          api: "https://cargo.cloudsmith.io/honeyankit/test"
        }
      }]
    end

    describe "#latest_version" do
      subject { finder.latest_version }
      before do
        stub_request(:get, sparse_registry_url).to_return(status: 200, body: sparse_registry_response)
      end

      it { is_expected.to eq(Gem::Version.new("1.0.1")) }

      context "when the latest version is being ignored" do
        let(:ignored_versions) { [">= 1.0.1, < 2.0"] }
        it { is_expected.to eq(Gem::Version.new("1.0.0")) }
      end

      context "when the sparse registry link resolves to a 'Not Found' page" do
        before do
          stub_request(:get, sparse_registry_url)
            .to_return(status: 404, body: sparse_registry_response)
        end
        let(:crates_fixture_name) { "not_found.json" }

        it { is_expected.to be_nil }
      end

      context "when the latest version is a pre-release" do
        let(:sparse_registry_response) do
          <<~BODY
            {"name": "hello-world", "vers": "1.0.0", "deps": [], "cksum": "b2c263921f1114820f4acc6b542d72bbc859ce7023c5b235346b157074dcccc7", "features": {}, "yanked": false, "links": null}
            {"name": "hello-world", "vers": "2.0.0-pre1", "deps": [], "cksum": "8a55b58def1ecc7aa8590c7078f379ec9a85328363ffb81d4354314b132b95c4", "features": {}, "yanked": false, "links": null}
          BODY
        end
        it { is_expected.to eq(Gem::Version.new("1.0.0")) }

        context "and the user wants a pre-release" do
          let(:requirements) do
            [{
              file: "Cargo.toml",
              requirement: "~2.0.0-pre1",
              groups: ["dependencies"],
              source: {
                type: "registry",
                name: "honeyankit-test",
                index: "sparse+https://cargo.cloudsmith.io/honeyankit/test/",
                dl: "https://dl.cloudsmith.io/basic/honeyankit/test/cargo/{crate}-{version}.crate",
                api: "https://cargo.cloudsmith.io/honeyankit/test"
              }
            }]
          end
          it { is_expected.to eq(Gem::Version.new("2.0.0-pre1")) }
        end
      end

      context "when already on the latest version" do
        let(:dependency_version) { "1.0.1" }
        it { is_expected.to eq(Gem::Version.new("1.0.1")) }
      end

      context "when all later versions are being ignored" do
        let(:ignored_versions) { ["> 1.0.0"] }
        it { is_expected.to eq(Gem::Version.new("1.0.0")) }

        context "raise_on_ignored" do
          let(:raise_on_ignored) { true }
          it "raises an error" do
            expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
          end
        end
      end
    end

    describe "#lowest_security_fix_version" do
      subject { finder.lowest_security_fix_version }

      before do
        stub_request(:get, sparse_registry_url).to_return(status: 200, body: sparse_registry_response)
      end

      let(:dependency_name) { "hello-world" }
      let(:dependency_version) { "1.0.0" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "cargo",
            vulnerable_versions: ["<= 1.0.0"]
          )
        ]
      end
      it { is_expected.to eq(Gem::Version.new("1.0.1")) }

      context "when the lowest version is being ignored" do
        let(:ignored_versions) { [">= 1.0.0, < 1.0.1"] }
        it { is_expected.to eq(Gem::Version.new("1.0.1")) }
      end

      context "when all versions are being ignored" do
        let(:ignored_versions) { [">= 0"] }
        it "returns nil" do
          expect(subject).to be_nil
        end

        context "raise_on_ignored" do
          let(:raise_on_ignored) { true }
          it "raises an error" do
            expect { subject }.to raise_error(Dependabot::AllVersionsIgnored)
          end
        end
      end

      context "when the lowest fixed version is a pre-release" do
        let(:sparse_registry_response) do
          <<~BODY
            {"name": "hello-world", "vers": "1.0.0", "deps": [], "cksum": "b2c263921f1114820f4acc6b542d72bbc859ce7023c5b235346b157074dcccc7", "features": {}, "yanked": false, "links": null}
            {"name": "hello-world", "vers": "2.0.0", "deps": [], "cksum": "b2c263921f1114820f4acc6b542d72bbc859ce7023c5b235346b157074dcccc8", "features": {}, "yanked": false, "links": null}
            {"name": "hello-world", "vers": "2.0.0-pre1", "deps": [], "cksum": "8a55b58def1ecc7aa8590c7078f379ec9a85328363ffb81d4354314b132b95c4", "features": {}, "yanked": false, "links": null}
            {"name": "hello-world", "vers": "2.0.0-pre2", "deps": [], "cksum": "8a55b58def1ecc7aa8590c7078f379ec9a85328363ffb81d4354314b132b95f6", "features": {}, "yanked": false, "links": null}
            {"name": "hello-world", "vers": "2.0.0-pre3", "deps": [], "cksum": "8a55b58def1ecc7aa8590c7078f379ec9a85328363ffb81d4354314b132b95d6", "features": {}, "yanked": false, "links": null}
          BODY
        end
        let(:security_advisories) do
          [
            Dependabot::SecurityAdvisory.new(
              dependency_name: dependency_name,
              package_manager: "cargo",
              vulnerable_versions: ["<= 2.0.0-pre2"]
            )
          ]
        end
        it { is_expected.to eq(Gem::Version.new("2.0.0")) }

        context "and the user wants a pre-release" do
          context "because their current version is a pre-release" do
            let(:dependency_version) { "2.0.0-pre1" }
            it { is_expected.to eq(Gem::Version.new("2.0.0-pre3")) }
          end

          context "because their requirements say they want pre-releases" do
            let(:requirements) do
              [{
                file: "Cargo.toml",
                requirement: "~2.0.0-pre1",
                groups: ["dependencies"],
                source: {
                  type: "registry",
                  name: "honeyankit-test",
                  index: "sparse+https://cargo.cloudsmith.io/honeyankit/test/",
                  dl: "https://dl.cloudsmith.io/basic/honeyankit/test/cargo/{crate}-{version}.crate",
                  api: "https://cargo.cloudsmith.io/honeyankit/test"
                }
              }]
            end
            it { is_expected.to eq(Gem::Version.new("2.0.0-pre3")) }
          end
        end
      end
    end
  end
end
