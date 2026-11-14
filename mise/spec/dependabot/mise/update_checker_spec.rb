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

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: [],
      raise_on_ignored: false
    )
  end

  before do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with(
        ["mise", "ls-remote", "--json", "--", dependency.name],
        stderr_to_stdout: false,
        env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
      )
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
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(
          ["mise", "ls-remote", "--json", "--", tool_name],
          stderr_to_stdout: false,
          env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
        )
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

    context "with an OTP-qualified Elixir version" do
      let(:tool_name) { "elixir" }
      let(:current_version) { "1.18.4-otp-27" }
      let(:remote_versions) { %w(1.18.5-otp-27 1.19.0-rc.1-otp-27 1.19.0-rc.2-otp-27) }

      it "accepts stable OTP builds and excludes release candidates" do
        expect(checker.latest_version.to_s).to eq("1.18.5-otp-27")
      end

      context "when the current OTP build is a prerelease" do
        let(:current_version) { "1.19.0-rc.1-otp-27" }

        it "allows newer prereleases" do
          expect(checker.latest_version.to_s).to eq("1.19.0-rc.2-otp-27")
        end
      end
    end

    context "with another stable build qualifier" do
      let(:tool_name) { "custom-tool" }
      let(:current_version) { "1.2.3-linux-x64" }
      let(:remote_versions) { %w(1.2.4-linux-x64 1.3.0-rc1-linux-x64) }

      it "accepts stable builds and excludes release candidates" do
        expect(checker.latest_version.to_s).to eq("1.2.4-linux-x64")
      end
    end
  end

  context "when mise ls-remote returns empty" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(
          ["mise", "ls-remote", "--json", "--", dependency.name],
          stderr_to_stdout: false,
          env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
        )
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
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(
          ["mise", "ls-remote", "--json", "--", dependency.name],
          stderr_to_stdout: false,
          env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
        )
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
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(
          ["mise", "ls-remote", "--json", "--", "ruby"],
          stderr_to_stdout: false,
          env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
        )
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
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(
          ["mise", "ls-remote", "--json", "--", dependency.name],
          stderr_to_stdout: false,
          env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
        )
        .and_return("{")
    end

    it "returns nil" do
      expect(checker.latest_version).to be_nil
    end
  end

  context "when a release has an invalid timestamp" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(
          ["mise", "ls-remote", "--json", "--", dependency.name],
          stderr_to_stdout: false,
          env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
        )
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
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            ["mise", "ls-remote", "--json", "--", dependency.name],
            stderr_to_stdout: false,
            env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
          )
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
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            ["mise", "ls-remote", "--json", "--", dependency.name],
            stderr_to_stdout: false,
            env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
          )
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
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            ["mise", "ls-remote", "--json", "--", dependency.name],
            stderr_to_stdout: false,
            env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
          )
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

    context "when versions include release candidates filtered via ignored_versions" do
      let(:checker) do
        described_class.new(
          dependency: dependency,
          dependency_files: [mise_toml],
          credentials: [],
          ignored_versions: ["*rc*"],
          raise_on_ignored: false
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            ["mise", "ls-remote", "--json", "--", dependency.name],
            stderr_to_stdout: false,
            env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
          )
          .and_return(JSON.dump(
                        [
                          { "version" => "27.3.2", "created_at" => "2026-01-13T20:06:42.23Z",
                            "rolling" => false },
                          { "version" => "28.0-rc1", "created_at" => "2026-03-01T00:00:00Z",
                            "rolling" => false },
                          { "version" => "28.0-rc2", "created_at" => "2026-03-10T00:00:00Z",
                            "rolling" => false }
                        ]
                      ))
      end

      it "does not suggest a release candidate as the latest version" do
        expect(checker.latest_version.to_s).to eq("27.3.2")
      end
    end
  end
end
