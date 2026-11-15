# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/mise/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Mise::UpdateChecker do
  let(:mise_toml) do
    Dependabot::DependencyFile.new(
      name: "mise.toml",
      content: <<~TOML
        [tools]
        erlang = "27.3.2"
      TOML
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "erlang",
      version: "27.3.2",
      package_manager: "mise",
      requirements: [{
        requirement: "27.3.2",
        file: "mise.toml",
        groups: [],
        source: nil
      }]
    )
  end

  let(:dependency_files) { [mise_toml] }
  let(:ignored_versions) { [] }
  let(:requirements_update_strategy) { nil }

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: ignored_versions,
      raise_on_ignored: false,
      requirements_update_strategy: requirements_update_strategy
    )
  end

  before do
    allow(Dependabot::SharedHelpers).to mise_ls_remote(dependency.name)
      .and_return(JSON.dump(
                    [
                      { "version" => "27.3.2", "created_at" => "2026-01-13T20:06:42.23Z", "rolling" => false },
                      { "version" => "28.4.1", "created_at" => "2026-03-12T19:32:23.78Z", "rolling" => false }
                    ]
                  ))
  end

  it_behaves_like "an update checker"

  describe "#latest_version" do
    it "returns the latest version from mise ls-remote" do
      expect(checker.latest_version).to eq("28.4.1")
    end
  end

  describe "#latest_resolvable_version" do
    it "returns the same as latest_version" do
      expect(checker.latest_resolvable_version).to eq(checker.latest_version)
    end
  end

  describe "#updated_requirements" do
    it "updates the requirement to the latest version" do
      expect(checker.updated_requirements.first[:requirement]).to eq("28.4.1")
    end
  end

  context "when a requirement's manifest was not provided" do
    let(:dependency_files) { [] }

    it "identifies the requirement and missing manifest" do
      expect { checker.latest_version }.to raise_error(
        Dependabot::DependencyFileNotFound, "Manifest mise.toml referenced by erlang was not provided"
      )
    end
  end

  context "with prerelease versions" do
    let(:tool_name) { "erlang" }
    let(:current_version) { "27.3.2" }
    let(:remote_versions) { %w(27.3.2 27.3.3 28.0-rc1 28.0-rc2) }
    let(:requirements) do
      [{ requirement: current_version, file: "mise.toml", groups: [], source: nil }]
    end
    let(:mise_toml) do
      Dependabot::DependencyFile.new(name: "mise.toml", content: "[tools]\n#{tool_name} = '#{current_version}'\n")
    end
    let(:dependency) do
      Dependabot::Dependency.new(
        name: tool_name, version: current_version, package_manager: "mise", requirements: requirements
      )
    end

    before do
      allow(Dependabot::SharedHelpers).to mise_ls_remote(tool_name)
        .and_return(JSON.dump(remote_versions.map { |version| { "version" => version } }))
    end

    it "keeps stable dependencies on stable releases" do
      expect(checker.latest_version).to eq("27.3.3")
    end

    context "when only prereleases are available" do
      let(:remote_versions) { %w(28.0-rc1 28.0-rc2) }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when the current version is a prerelease" do
      let(:current_version) { "28.0-rc1" }

      it "allows newer prereleases" do
        expect(checker.latest_version).to eq("28.0-rc2")
      end
    end

    context "when prereleases are ignored" do
      let(:current_version) { "27.3.2-rc1" }
      let(:ignored_versions) { ["*rc*"] }

      it "rejects newer prereleases even when the current pin is a prerelease" do
        expect(checker.latest_version).to eq("27.3.3")
      end
    end

    context "when another manifest explicitly requests a prerelease" do
      let(:dev_mise_toml) do
        Dependabot::DependencyFile.new(name: "mise.dev.toml", content: "[tools]\nerlang = '28.0-rc1'\n")
      end
      let(:dependency_files) { [mise_toml, dev_mise_toml] }
      let(:requirements) do
        super() + [{ requirement: "28.0-rc1", file: "mise.dev.toml", groups: [], source: nil }]
      end

      it "selects each manifest's target independently" do
        expect(checker.updated_requirements.to_h { |req| [req.file, req.requirement_string] }).to eq(
          "mise.toml" => "27.3.3", "mise.dev.toml" => "28.0-rc2"
        )
      end
    end

    context "with a partial pin resolved to a newer version" do
      let(:current_version) { "27.3.4" }
      let(:remote_versions) { %w(27.3.3) }
      let(:mise_toml) do
        Dependabot::DependencyFile.new(name: "mise.toml", content: "[tools]\nerlang = '27.3'\n")
      end
      let(:requirements) do
        [{
          requirement: "27.3", file: "mise.toml", groups: [], source: nil,
          metadata: { resolved_version: "27.3.4" }
        }]
      end

      it "does not pin an older release" do
        expect(checker.updated_requirements).to eq(dependency.requirements)
        expect(checker.updated_dependencies(requirements_to_unlock: :own)).to be_empty
      end
    end

    context "with a loose pin" do
      let(:pin) { "27" }
      let(:remote_versions) { %w(27.3.2 27.4.0 28.0.0 28.0.1) }
      let(:mise_resolves) { { "erlang@28" => "28.0.1", "erlang@28.0" => "28.0.1" } }
      let(:mise_toml) do
        Dependabot::DependencyFile.new(name: "mise.toml", content: "[tools]\nerlang = '#{pin}'\n")
      end
      let(:requirements) do
        [{
          requirement: pin, file: "mise.toml", groups: [], source: nil,
          metadata: { resolved_version: current_version }
        }]
      end
      let(:updated) do
        checker.updated_requirements.map { |req| [req.requirement_string, req.metadata_string("resolved_version")] }
      end

      before do
        mise_resolves.each do |query, version|
          allow(Dependabot::SharedHelpers).to mise_latest(query).and_return("#{version}\n")
        end
      end

      it "keeps the pin's precision" do
        expect(updated).to eq([%w(28 28.0.1)])
        expect(checker.updated_dependencies(requirements_to_unlock: :own).first.version).to eq("28.0.1")
      end

      context "when the pin includes the minor version" do
        let(:pin) { "27.3" }

        it "keeps both parts" do
          expect(updated).to eq([%w(28.0 28.0.1)])
        end
      end

      context "when the newest release still matches the pin" do
        let(:remote_versions) { %w(27.3.2 27.4.0) }

        it "reports the dependency as up to date" do
          expect(checker).to be_up_to_date
          expect(checker.updated_requirements).to eq(dependency.requirements)
        end
      end

      context "when an ignore rule holds back the newest release matching the new pin" do
        let(:ignored_versions) { [">= 28.0.1"] }

        it "pins the selected version exactly, so mise can't install the ignored one" do
          expect(updated).to eq([%w(28.0.0 28.0.0)])
        end
      end

      context "when the newest release still matches the pin and there's a lockfile" do
        let(:remote_versions) { %w(27.3.2 27.4.0) }
        let(:mise_resolves) { { "erlang@27" => "27.4.0" } }
        let(:dependency_files) { [mise_toml, Dependabot::DependencyFile.new(name: "mise.lock", content: "")] }

        it "updates the locked version and keeps the pin" do
          expect(updated).to eq([%w(27 27.4.0)])
        end
      end

      context "with a fuzzy pin" do
        let(:pin) { "latest" }
        let(:mise_resolves) { { "erlang@latest" => "28.0.1" } }
        let(:dependency_files) { [mise_toml, Dependabot::DependencyFile.new(name: "mise.lock", content: "")] }

        it "updates the locked version and keeps the pin" do
          expect(updated).to eq([%w(latest 28.0.1)])
          expect(checker.latest_version.to_s).to eq("28.0.1")
        end

        context "when mise selects a different build variant" do
          let(:current_version) { "27.3.2-linux-x64" }
          let(:remote_versions) { %w(27.3.2-linux-x64 28.0.1-linux-arm64) }
          let(:mise_resolves) { { "erlang@latest" => "28.0.1-linux-arm64" } }

          it "follows the fuzzy request" do
            expect(updated).to eq([%w(latest 28.0.1-linux-arm64)])
          end
        end

        context "when an ignore rule excludes the version mise resolves it to" do
          let(:ignored_versions) { [">= 28.0.1"] }

          it "reports the dependency as up to date" do
            expect(checker).to be_up_to_date
          end
        end

        context "without a lockfile" do
          let(:dependency_files) { [mise_toml] }

          it "reports the dependency as up to date" do
            expect(checker).to be_up_to_date
          end
        end
      end

      context "with the lockfile-only versioning strategy" do
        let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::LockfileOnly }
        let(:mise_resolves) { { "erlang@27" => "27.4.0" } }
        let(:dependency_files) { [mise_toml, Dependabot::DependencyFile.new(name: "mise.lock", content: "")] }

        it "moves only the locked version, even though 28.x exists" do
          expect(updated).to eq([%w(27 27.4.0)])
        end

        context "without a lockfile" do
          let(:dependency_files) { [mise_toml] }

          it "reports the dependency as up to date" do
            expect(checker).to be_up_to_date
          end
        end
      end

      context "with a fuzzy pin for the same tool in a manifest sharing the lockfile" do
        let(:requirements) do
          [
            { requirement: "27", file: "mise/conf.d/a.toml", groups: [], source: nil,
              metadata: { resolved_version: current_version } },
            { requirement: "latest", file: "mise/conf.d/b.toml", groups: [], source: nil,
              metadata: { resolved_version: current_version } }
          ]
        end
        let(:dependency_files) do
          [
            Dependabot::DependencyFile.new(name: "mise/conf.d/a.toml", content: "[tools]\nerlang = '27'\n"),
            Dependabot::DependencyFile.new(name: "mise/conf.d/b.toml", content: "[tools]\nerlang = 'latest'\n"),
            Dependabot::DependencyFile.new(name: "mise/mise.lock", content: "")
          ]
        end
        let(:mise_resolves) { { "erlang@27" => "27.4.0", "erlang@28" => "28.0.1", "erlang@latest" => "28.0.1" } }

        it "updates both manifests" do
          expect(updated).to eq([%w(28 28.0.1), %w(latest 28.0.1)])
        end

        context "when the fuzzy pin would move to an ignored version" do
          let(:ignored_versions) { [">= 28"] }

          it "doesn't relock the other manifest either, because --bump would move both" do
            expect(checker).to be_up_to_date
          end
        end
      end

      context "when mise can't resolve the new pin" do
        let(:mise_resolves) { {} }

        before do
          allow(Dependabot::SharedHelpers).to mise_latest("erlang@28")
            .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "boom", error_context: {}))
        end

        it "pins the selected version exactly" do
          expect(updated).to eq([%w(28.0.1 28.0.1)])
        end
      end

      context "when a partial pin resolves to a build variant" do
        let(:current_version) { "27.3.2-linux-x64" }
        let(:remote_versions) { %w(27.3.2-linux-x64 28.0.1-linux-arm64) }
        let(:mise_resolves) { { "erlang@28" => "28.0.1-linux-arm64" } }

        it "leaves variant selection to mise" do
          expect(updated).to eq([%w(28 28.0.1-linux-arm64)])
        end
      end
    end

    context "with an OTP-qualified Elixir version" do
      let(:tool_name) { "elixir" }
      let(:current_version) { "1.20.4-otp-29" }
      let(:remote_versions) do
        %w(1.20.5 1.20.5-otp-28 1.20.5-otp-29 1.21.0-rc.1-otp-29 1.21.0-rc.2-otp-29)
      end

      it "accepts stable OTP builds and excludes release candidates" do
        expect(checker.latest_version.to_s).to eq("1.20.5-otp-29")
      end

      context "when the same Elixir release is built for a newer OTP" do
        let(:current_version) { "1.20.4-otp-28" }
        let(:remote_versions) { %w(1.20.4 1.20.4-otp-28 1.20.4-otp-29) }

        it "moves to the newer OTP build" do
          expect(checker.updated_requirements.first.requirement_string).to eq("1.20.4-otp-29")
        end
      end

      context "when both the release and its OTP build advance" do
        let(:remote_versions) { super() + %w(1.20.5-otp-30) }

        it "selects the newest release's highest OTP build" do
          expect(checker.latest_version.to_s).to eq("1.20.5-otp-30")
        end
      end

      context "when the current OTP build is a prerelease" do
        let(:current_version) { "1.21.0-rc.1-otp-29" }

        it "allows newer prereleases" do
          expect(checker.latest_version.to_s).to eq("1.21.0-rc.2-otp-29")
        end
      end

      context "when the prerelease follows the OTP suffix" do
        let(:current_version) { "1.21.0-otp-29-rc1" }
        let(:remote_versions) { %w(1.21.0-otp-28-rc4 1.21.0-otp-29-rc2 1.21.0-otp-30-rc3 1.21.0-rc4) }

        it "keeps a build suffix" do
          expect(checker.latest_version.to_s).to eq("1.21.0-otp-30-rc3")
        end
      end

      context "when the newer release only has a build without the suffix" do
        let(:remote_versions) { %w(1.20.5) }

        it "leaves the requirement unchanged" do
          expect(checker.updated_dependencies(requirements_to_unlock: :own)).to be_empty
          expect(checker.updated_requirements).to eq(dependency.requirements)
        end
      end

      context "when the newer OTP builds are ignored" do
        let(:ignored_versions) { %w(1.20.5-otp-28 1.20.5-otp-29) }

        it "does not fall back to the build without the suffix" do
          expect(checker.updated_dependencies(requirements_to_unlock: :own)).to be_empty
        end
      end

      context "when the newer OTP build is still in cooldown" do
        let(:checker) do
          described_class.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: [],
            update_cooldown: Dependabot::Package::ReleaseCooldownOptions.new(default_days: 30)
          )
        end

        before do
          allow(Dependabot::SharedHelpers).to mise_ls_remote(tool_name)
            .and_return(JSON.dump(
                          [
                            { "version" => current_version, "created_at" => "2026-01-13T20:06:42Z" },
                            { "version" => "1.20.5-otp-29", "created_at" => Time.now.utc.iso8601 },
                            { "version" => "1.21.0", "created_at" => "2026-01-13T20:06:42Z" }
                          ]
                        ))
        end

        it "does not fall back to the build without the suffix" do
          expect(checker.latest_version.to_s).to eq(current_version)
          expect(checker.updated_dependencies(requirements_to_unlock: :own)).to be_empty
        end
      end

      context "when another manifest pins the build without the suffix" do
        let(:dependency_files) do
          [mise_toml, Dependabot::DependencyFile.new(name: "mise.dev.toml", content: "[tools]\nelixir = '1.20.4'\n")]
        end
        let(:requirements) do
          super() + [{ requirement: "1.20.4", file: "mise.dev.toml", groups: [], source: nil }]
        end

        it "keeps each manifest's build" do
          expect(checker.updated_requirements.to_h { |req| [req.file, req.requirement_string] }).to eq(
            "mise.toml" => "1.20.5-otp-29", "mise.dev.toml" => "1.20.5"
          )
        end
      end
    end

    context "with another stable build qualifier" do
      let(:tool_name) { "custom-tool" }
      let(:current_version) { "1.2.3-linux-x64" }
      let(:remote_versions) { %w(1.2.4 1.2.4-linux-x64 1.3.0-rc1-linux-x64) }

      it "accepts stable builds and excludes release candidates" do
        expect(checker.latest_version.to_s).to eq("1.2.4-linux-x64")
      end

      context "when the manifest pins a plain version" do
        let(:current_version) { "1.2.3" }

        it "does not introduce a build qualifier" do
          expect(checker.latest_version.to_s).to eq("1.2.4")
        end
      end
    end
  end

  context "when mise ls-remote returns empty" do
    before do
      allow(Dependabot::SharedHelpers).to mise_ls_remote(dependency.name)
        .and_return("[]")
    end

    describe "#latest_version" do
      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    describe "#updated_requirements" do
      it "returns the original requirements unchanged" do
        expect(checker.updated_requirements).to eq(dependency.requirements)
      end
    end
  end

  context "when mise ls-remote fails" do
    before do
      allow(Dependabot::SharedHelpers).to mise_ls_remote(dependency.name)
        .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                     message: "mise not found",
                     error_context: {}
                   ))
    end

    describe "#latest_version" do
      it "returns nil gracefully" do
        expect(checker.latest_version).to be_nil
      end
    end
  end

  context "with Ruby releases from multiple implementations" do
    let(:mise_toml) do
      Dependabot::DependencyFile.new(name: "mise.toml", content: "[tools]\nruby = '3.3.0'\n")
    end

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "ruby",
        version: "3.3.0",
        package_manager: "mise",
        requirements: [{ requirement: "3.3.0", file: "mise.toml", groups: [], source: nil }]
      )
    end

    let(:remote_versions) { %w(3.3.0 artichoke-dev jruby-9.4.12.0 3.4.2 truffleruby-24.2.0 4.1.0-preview1) }

    before do
      allow(Dependabot::SharedHelpers).to mise_ls_remote("ruby")
        .and_return(JSON.dump(remote_versions.map { |version| { "version" => version } }))
    end

    it "finds the latest supported release without discarding valid versions" do
      expect(checker.latest_version).to eq("3.4.2")
    end

    context "when no releases have supported versions" do
      let(:remote_versions) { %w(artichoke-dev jruby-9.4.12.0 truffleruby-24.2.0) }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end
  end

  context "when mise ls-remote returns invalid JSON" do
    before do
      allow(Dependabot::SharedHelpers).to mise_ls_remote(dependency.name)
        .and_return("{")
    end

    it "returns nil" do
      expect(checker.latest_version).to be_nil
    end
  end

  context "when a release has an invalid timestamp" do
    before do
      allow(Dependabot::SharedHelpers).to mise_ls_remote(dependency.name)
        .and_return(JSON.dump([{ "version" => "28.4.1", "created_at" => "invalid" }]))
    end

    it "does not hide the timestamp parsing error" do
      expect { checker.latest_version }.to raise_error(ArgumentError)
    end
  end

  context "when dependency has a fuzzy version pin" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "node",
        version: "latest",
        package_manager: "mise",
        requirements: [{
          requirement: "latest",
          file: "mise.toml",
          groups: [],
          source: nil
        }]
      )
    end

    describe "#latest_version" do
      it "returns the latest available version" do
        expect(checker.latest_version).to eq "28.4.1"
      end
    end
  end

  context "with cooldown options" do
    let(:checker) do
      described_class.new(
        dependency: dependency,
        dependency_files: [mise_toml],
        credentials: [],
        ignored_versions: [],
        raise_on_ignored: false,
        update_cooldown: Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 30
        )
      )
    end

    context "when latest version was released within the cooldown period" do
      before do
        allow(Dependabot::SharedHelpers).to mise_ls_remote(dependency.name)
          .and_return(JSON.dump(
                        [
                          { "version" => "27.3.2", "created_at" => "2026-01-13T20:06:42.23Z", "rolling" => false },
                          { "version" => "28.4.1", "created_at" => Time.now.utc.iso8601, "rolling" => false }
                        ]
                      ))
      end

      it "returns the previous version instead of the latest" do
        expect(checker.latest_version).to eq("27.3.2")
      end
    end

    context "when latest version was released outside the cooldown period" do
      before do
        allow(Dependabot::SharedHelpers).to mise_ls_remote(dependency.name)
          .and_return(JSON.dump(
                        [
                          { "version" => "27.3.2", "created_at" => "2026-01-13T20:06:42.23Z", "rolling" => false },
                          { "version" => "28.4.1", "created_at" => "2026-01-13T20:06:42.23Z", "rolling" => false }
                        ]
                      ))
      end

      it "returns the latest version" do
        expect(checker.latest_version.to_s).to eq("28.4.1")
      end
    end

    context "when created_at is missing" do
      before do
        allow(Dependabot::SharedHelpers).to mise_ls_remote(dependency.name)
          .and_return(JSON.dump(
                        [
                          { "version" => "27.3.2", "rolling" => false },
                          { "version" => "28.4.1", "rolling" => false }
                        ]
                      ))
      end

      it "returns the latest version ignoring cooldown" do
        expect(checker.latest_version.to_s).to eq("28.4.1")
      end
    end
  end
end
