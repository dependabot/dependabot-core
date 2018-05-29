# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/elixir/hex"
require "dependabot/errors"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Elixir::Hex do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: files,
      credentials: credentials,
      ignored_versions: ignored_versions
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
  let(:ignored_versions) { [] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: dependency_requirements,
      package_manager: "hex"
    )
  end

  let(:dependency_name) { "plug" }
  let(:version) { "1.3.0" }
  let(:dependency_requirements) do
    [{ file: "mix.exs", requirement: "~> 1.3.0", groups: [], source: nil }]
  end

  let(:files) { [mixfile, lockfile] }

  let(:mixfile) do
    Dependabot::DependencyFile.new(content: mixfile_body, name: "mix.exs")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(content: lockfile_body, name: "mix.lock")
  end

  let(:mixfile_body) { fixture("elixir", "mixfiles", "minor_version") }
  let(:lockfile_body) { fixture("elixir", "lockfiles", "minor_version") }

  let(:hex_url) { "https://hex.pm/api/packages/#{dependency_name}" }
  let(:hex_response) do
    fixture("elixir", "registry_api", "#{dependency_name}_response.json")
  end

  before do
    stub_request(:get, hex_url).to_return(status: 200, body: hex_response)
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    before do
      allow(checker).to receive(:latest_resolvable_version).
        and_return(Gem::Version.new("1.3.5"))
    end

    it { is_expected.to eq(Gem::Version.new("1.4.3")) }

    context "when the user wants pre-releases" do
      let(:version) { "1.4.0-rc.0" }
      it { is_expected.to eq(Gem::Version.new("1.5.0-rc.0")) }
    end

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 1.3.0.a, < 2.0"] }
      it { is_expected.to eq(Gem::Version.new("1.2.5")) }
    end

    context "when the dependency doesn't have a requirement" do
      let(:version) { "1.4.0" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: nil, groups: [], source: nil }]
      end
      it { is_expected.to eq(Gem::Version.new("1.4.3")) }
    end

    context "when the registry 404s" do
      before { stub_request(:get, hex_url).to_return(status: 404) }
      it { is_expected.to eq(Gem::Version.new("1.3.5")) }
    end

    context "with a dependency with a git source" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "git_source") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "git_source") }

      let(:dependency_name) { "phoenix" }
      let(:version) { "178ce1a2344515e9145599970313fcc190d4b881" }
      let(:dependency_requirements) do
        [{
          file: "mix.exs",
          requirement: "~> 1.3.0",
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/phoenixframework/phoenix.git",
            branch: "master",
            ref: "v1.2.0"
          }
        }]
      end

      before do
        git_url = "https://github.com/phoenixframework/phoenix.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: ["x-access-token", "token"]).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "phoenix"),
            headers: git_header
          )
      end
      it { is_expected.to eq("81705318ff929b2bc3c9c1b637c3f801e7371551") }
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it { is_expected.to eq(Gem::Version.new("1.3.6")) }

    context "when the user is ignoring the latest version" do
      let(:ignored_versions) { [">= 1.3.5.a, < 2.0"] }
      it { is_expected.to eq(Gem::Version.new("1.3.4")) }
    end

    context "with a version conflict at the latest version" do
      let(:dependency_name) { "phoenix" }
      let(:version) { "1.2.1" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: "== 1.2.1", groups: [], source: nil }]
      end

      let(:mixfile_body) { fixture("elixir", "mixfiles", "exact_version") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "exact_version") }

      it { is_expected.to eq(Gem::Version.new("1.2.2")) }
    end

    context "when a subdependency needs updating" do
      let(:dependency_name) { "phoenix" }
      let(:version) { "1.2.5" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: "~> 1.2.1", groups: [], source: nil }]
      end

      let(:mixfile_body) { fixture("elixir", "mixfiles", "minor_version") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "minor_version") }

      it { is_expected.to be >= Gem::Version.new("1.3.0") }
    end

    context "with a dependency with a private source" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "private_package") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "private_package") }

      before { `mix hex.organization deauth dependabot` }

      let(:dependency_name) { "example_package_a" }
      let(:version) { "1.0.0" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: "~> 1.0.0", groups: [], source: nil }]
      end

      context "with good credentials" do
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "type" => "hex_organization",
              "organization" => "dependabot",
              "token" => "855f6cbeffc6e14c6a884f0111caff3e"
            }
          ]
        end

        it { is_expected.to eq(Gem::Version.new("1.1.0")) }
      end

      context "with bad credentials" do
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "type" => "hex_organization",
              "organization" => "dependabot",
              "token" => "111f6cbeffc6e14c6a884f0111caff3e"
            }
          ]
        end

        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
              expect(error.source).to eq("dependabot")
            end
        end
      end

      context "with no credentials" do
        let(:credentials) do
          [{
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }]
        end

        # The Elixir process hangs waiting for input in this case. This spec
        # passes as long as we're intelligently timing out.
        it "raises a helpful error" do
          expect { subject }.
            to raise_error(Dependabot::PrivateSourceNotReachable) do |error|
              expect(error.source).to eq("dependabot")
            end
        end
      end
    end

    context "with a dependency with a git source" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "git_source") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "git_source") }

      context "that is not the dependency we're checking" do
        let(:dependency_name) { "plug" }
        let(:version) { "1.2.0" }
        let(:dependency_requirements) do
          [{ file: "mix.exs", requirement: "1.2.0", groups: [], source: nil }]
        end
        it { is_expected.to be >= Gem::Version.new("1.4.3") }
      end

      context "that is the dependency we're checking" do
        let(:dependency_name) { "phoenix" }
        let(:version) { "178ce1a2344515e9145599970313fcc190d4b881" }
        let(:dependency_requirements) do
          [{
            file: "mix.exs",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/phoenixframework/phoenix.git",
              branch: "master",
              ref: ref
            }
          }]
        end

        context "and has a tag" do
          let(:ref) { "v1.2.0" }

          before do
            git_url = "https://github.com/phoenixframework/phoenix.git"
            git_header = {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
            stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
              with(basic_auth: ["x-access-token", "token"]).
              to_return(
                status: 200,
                body: fixture("git", "upload_packs", "phoenix"),
                headers: git_header
              )
          end

          context "that can update" do
            let(:mixfile_body) do
              fixture("elixir", "mixfiles", "git_source_tag_can_update")
            end
            let(:lockfile_body) do
              fixture("elixir", "lockfiles", "git_source_tag_can_update")
            end

            it { is_expected.to eq("81705318ff929b2bc3c9c1b637c3f801e7371551") }
          end

          context "that can't update (because of resolvability)" do
            let(:mixfile_body) do
              fixture("elixir", "mixfiles", "git_source")
            end
            let(:lockfile_body) do
              fixture("elixir", "lockfiles", "git_source")
            end

            it { is_expected.to eq("178ce1a2344515e9145599970313fcc190d4b881") }
          end
        end

        context "and has no tag" do
          let(:ref) { nil }
          context "and can update" do
            let(:mixfile_body) do
              fixture("elixir", "mixfiles", "git_source_no_tag")
            end
            let(:lockfile_body) do
              fixture("elixir", "lockfiles", "git_source_no_tag")
            end
            let(:ref) { nil }
            it "updates the dependency" do
              expect(latest_resolvable_version).to_not be_nil
              expect(latest_resolvable_version).
                to_not eq("178ce1a2344515e9145599970313fcc190d4b881")
              expect(latest_resolvable_version).to match(/^[0-9a-f]{40}$/)
            end
          end

          context "and is blocked from updating" do
            let(:mixfile_body) do
              fixture("elixir", "mixfiles", "git_source_no_tag_blocked")
            end
            let(:lockfile_body) do
              fixture("elixir", "lockfiles", "git_source_no_tag_blocked")
            end
            let(:ref) { nil }
            it { is_expected.to be_nil }
          end
        end
      end
    end

    context "with a mix.exs that opens another file" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "loads_file") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "exact_version") }

      let(:dependency_name) { "phoenix" }
      let(:version) { "1.2.1" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: "== 1.2.1", groups: [], source: nil }]
      end

      it { is_expected.to eq(Gem::Version.new("1.2.2")) }
    end

    context "with an umbrella application" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "umbrella") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "umbrella") }
      let(:files) { [mixfile, lockfile, sub_mixfile1, sub_mixfile2] }
      let(:sub_mixfile1) do
        Dependabot::DependencyFile.new(
          name: "apps/dependabot_business/mix.exs",
          content: fixture("elixir", "mixfiles", "dependabot_business")
        )
      end
      let(:sub_mixfile2) do
        Dependabot::DependencyFile.new(
          name: "apps/dependabot_web/mix.exs",
          content: fixture("elixir", "mixfiles", "dependabot_web")
        )
      end

      let(:dependency_name) { "plug" }
      let(:version) { "1.3.6" }
      let(:dependency_requirements) do
        [
          {
            requirement: "~> 1.3.0",
            file: "apps/dependabot_business/mix.exs",
            groups: [],
            source: nil
          },
          {
            requirement: "1.3.6",
            file: "apps/dependabot_web/mix.exs",
            groups: [],
            source: nil
          }
        ]
      end

      it { is_expected.to be >= Gem::Version.new("1.4.3") }
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject(:new_version) { checker.latest_resolvable_version_with_no_unlock }
    it { is_expected.to eq(Gem::Version.new("1.3.6")) }

    context "with a dependency with a git source" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "git_source") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "git_source") }

      context "that is the dependency we're checking" do
        let(:dependency_name) { "phoenix" }
        let(:version) { "178ce1a2344515e9145599970313fcc190d4b881" }
        let(:dependency_requirements) do
          [{
            file: "mix.exs",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/phoenixframework/phoenix.git",
              branch: "master",
              ref: ref
            }
          }]
        end

        context "and has a tag" do
          let(:ref) { "v1.2.0" }
          it { is_expected.to eq("178ce1a2344515e9145599970313fcc190d4b881") }
        end

        context "and has no tag and can update" do
          let(:mixfile_body) do
            fixture("elixir", "mixfiles", "git_source_no_tag")
          end
          let(:lockfile_body) do
            fixture("elixir", "lockfiles", "git_source_no_tag")
          end
          let(:ref) { nil }
          it "updates the dependency" do
            expect(new_version).to_not be_nil
            expect(new_version).
              to_not eq("178ce1a2344515e9145599970313fcc190d4b881")
            expect(new_version).to match(/^[0-9a-f]{40}$/)
          end
        end

        context "and is blocked from updating" do
          let(:mixfile_body) do
            fixture("elixir", "mixfiles", "git_source_no_tag_blocked")
          end
          let(:lockfile_body) do
            fixture("elixir", "lockfiles", "git_source_no_tag_blocked")
          end
          let(:ref) { nil }
          it { is_expected.to be_nil }
        end
      end
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }

    before do
      allow(checker).
        to receive(:latest_resolvable_version).
        and_return(Gem::Version.new("1.6.0"))
    end

    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater).
        to receive(:new).
        with(
          requirements: dependency_requirements,
          updated_source: nil,
          latest_resolvable_version: "1.6.0"
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [{
            file: "mix.exs",
            requirement: "~> 1.6.0",
            groups: [],
            source: nil
          }]
        )
    end

    context "updating a git source" do
      let(:mixfile_body) do
        fixture("elixir", "mixfiles", "git_source_tag_can_update")
      end
      let(:lockfile_body) do
        fixture("elixir", "lockfiles", "git_source_tag_can_update")
      end
      let(:dependency_name) { "phoenix" }
      let(:version) { "178ce1a2344515e9145599970313fcc190d4b881" }
      let(:dependency_requirements) do
        [{
          requirement: nil,
          file: "mix.exs",
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/phoenixframework/phoenix.git",
            branch: "master",
            ref: "v1.2.0"
          }
        }]
      end

      before do
        git_url = "https://github.com/phoenixframework/phoenix.git"
        git_header = {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack").
          with(basic_auth: ["x-access-token", "token"]).
          to_return(
            status: 200,
            body: fixture("git", "upload_packs", "phoenix"),
            headers: git_header
          )
      end

      it "delegates to the RequirementsUpdater" do
        expect(described_class::RequirementsUpdater).
          to receive(:new).
          with(
            requirements: dependency_requirements,
            updated_source: {
              type: "git",
              url: "https://github.com/phoenixframework/phoenix.git",
              branch: "master",
              ref: "v1.3.2"
            },
            latest_resolvable_version: "1.6.0"
          ).
          and_call_original
        expect(checker.updated_requirements).
          to eq(
            [{
              requirement: nil,
              file: "mix.exs",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/phoenixframework/phoenix.git",
                branch: "master",
                ref: "v1.3.2"
              }
            }]
          )
      end
    end
  end
end
