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
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "plug",
      version: "1.3.0",
      requirements: dependency_requirements,
      package_manager: "hex"
    )
  end

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

  describe "#latest_version" do
    subject { checker.latest_version }

    let(:hex_url) { "https://hex.pm/api/packages/plug" }
    let(:hex_response) do
      fixture("elixir", "registry_api", "plug_response.json")
    end

    before do
      stub_request(:get, hex_url).to_return(status: 200, body: hex_response)
      allow(checker).to receive(:latest_resolvable_version).
        and_return(Gem::Version.new("1.3.5"))
    end

    it { is_expected.to eq(Gem::Version.new("1.4.3")) }

    context "when the registry 404s" do
      before { stub_request(:get, hex_url).to_return(status: 404) }
      it { is_expected.to eq(Gem::Version.new("1.3.5")) }
    end

    context "with a dependency with a git source" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "git_source") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "git_source") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "178ce1a2344515e9145599970313fcc190d4b881",
          requirements: [
            {
              requirement: nil,
              file: "mix.exs",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/phoenixframework/phoenix.git",
                branch: "master",
                ref: "v1.2.0"
              }
            }
          ],
          package_manager: "hex"
        )
      end
      before do
        repo_url = "https://api.github.com/repos/phoenixframework/phoenix"
        stub_request(:get, repo_url + "/tags?per_page=100").
          to_return(
            status: 200,
            body: fixture("github", "phoenix_tags.json"),
            headers: { "Content-Type" => "application/json" }
          )
        stub_request(:get, repo_url + "/git/refs/tags/v1.3.0").
          to_return(
            status: 200,
            body: fixture("github", "ref.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end
      it { is_expected.to eq("aa218f56b14c9653891f9e74264a383fa43fefbd") }
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "returns a non-normalized version, following semver" do
      expect(subject.segments.count).to eq(3)
    end

    it "respects the resolvability of the mix.exs" do
      expect(latest_resolvable_version).
        to be > Gem::Version.new("1.3.5")
      expect(latest_resolvable_version).
        to be < Gem::Version.new("1.4.0")
    end

    context "with a version conflict at the latest version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "1.2.1",
          requirements: [
            {
              file: "mix.exs",
              requirement: "== 1.2.1",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      let(:mixfile_body) { fixture("elixir", "mixfiles", "exact_version") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "exact_version") }

      it { is_expected.to eq(Gem::Version.new("1.2.2")) }
    end

    context "when a subdependency needs updating" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "1.2.5",
          requirements: [
            {
              file: "mix.exs",
              requirement: "~> 1.2.1",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      let(:mixfile_body) { fixture("elixir", "mixfiles", "minor_version") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "minor_version") }

      it { is_expected.to be >= Gem::Version.new("1.3.0") }
    end

    context "with a dependency with a git source" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "git_source") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "git_source") }

      context "that is not the dependency we're checking" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "plug",
            version: "1.2.0",
            requirements: [
              {
                file: "mix.exs",
                requirement: "1.2.0",
                groups: [],
                source: nil
              }
            ],
            package_manager: "hex"
          )
        end
        it { is_expected.to be >= Gem::Version.new("1.4.3") }
      end

      context "that is the dependency we're checking" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "phoenix",
            version: "178ce1a2344515e9145599970313fcc190d4b881",
            requirements: [
              {
                requirement: nil,
                file: "mix.exs",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/phoenixframework/phoenix.git",
                  branch: "master",
                  ref: ref
                }
              }
            ],
            package_manager: "hex"
          )
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

    context "with a dependency with a bad specification" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "bad_spec") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "exact_version") }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { checker.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a mix.exs that opens another file" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "loads_file") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "exact_version") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "1.2.1",
          requirements: [
            {
              file: "mix.exs",
              requirement: "== 1.2.1",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
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

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "plug",
          version: "1.3.6",
          requirements: [
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
          ],
          package_manager: "hex"
        )
      end

      it { is_expected.to be >= Gem::Version.new("1.5.0") }
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject(:new_version) { checker.latest_resolvable_version_with_no_unlock }
    it { is_expected.to eq(Gem::Version.new("1.3.6")) }

    context "with a dependency with a git source" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "git_source") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "git_source") }

      context "that is the dependency we're checking" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "phoenix",
            version: "178ce1a2344515e9145599970313fcc190d4b881",
            requirements: [
              {
                requirement: nil,
                file: "mix.exs",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/phoenixframework/phoenix.git",
                  branch: "master",
                  ref: ref
                }
              }
            ],
            package_manager: "hex"
          )
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
          latest_resolvable_version: "1.6.0"
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [
            {
              file: "mix.exs",
              requirement: "~> 1.6.0",
              groups: [],
              source: nil
            }
          ]
        )
    end
  end
end
