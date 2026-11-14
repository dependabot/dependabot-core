# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/mise"

RSpec.describe Dependabot::Mise::FileUpdater do
  describe "updating independent manifests" do
    let(:versions_by_file) { { "mise.toml" => "27.3.2", "mise.dev.toml" => "28.0-rc1" } }
    let(:dependency_files) do
      versions_by_file.map do |filename, version|
        Dependabot::DependencyFile.new(
          name: filename,
          content: "[env]\nerlang = '#{version}'\n[tools]\nerlang = '#{version}'\n"
        )
      end
    end
    let(:dependency) do
      Dependabot::Mise::FileParser.new(dependency_files: dependency_files, source: nil).parse.fetch(0)
    end
    let(:releases) { %w(27.3.2 27.3.3 28.0-rc1 28.0-rc2).map { |version| { "version" => version } } }
    let(:releases_by_file) { versions_by_file.transform_values { releases } }
    let(:cooldown) { nil }
    let(:ignored_versions) { [] }
    let(:raise_on_ignored) { false }
    let(:checker) do
      Dependabot::Mise::UpdateChecker.new(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: [],
        update_cooldown: cooldown,
        ignored_versions: ignored_versions,
        raise_on_ignored: raise_on_ignored
      )
    end
    let(:updated_dependencies) { checker.updated_dependencies(requirements_to_unlock: :own) }
    let(:updater) do
      described_class.new(dependencies: updated_dependencies, dependency_files: dependency_files, credentials: [])
    end
    let(:updated_contents) { updater.updated_dependency_files.to_h { |file| [file.name, file.content] } }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(
          ["mise", "ls-remote", "--json", "--", "erlang"],
          stderr_to_stdout: false,
          env: hash_including("MISE_YES" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => anything)
        ) do |_, env:, **|
        JSON.dump(releases_by_file.fetch(env.fetch("MISE_OVERRIDE_CONFIG_FILENAMES")))
      end
    end

    it "keeps stable and prerelease requirements on their own release channels" do
      expect(checker.updated_requirements.to_h { |req| [req.file, req.requirement_string] }).to eq(
        "mise.toml" => "27.3.3", "mise.dev.toml" => "28.0-rc2"
      )
    end

    it "updates both files without changing unrelated configuration" do
      expect(updated_contents).to eq(
        "mise.toml" => "[env]\nerlang = '27.3.2'\n[tools]\nerlang = '27.3.3'\n",
        "mise.dev.toml" => "[env]\nerlang = '28.0-rc1'\n[tools]\nerlang = '28.0-rc2'\n"
      )
    end

    context "with nested configuration files" do
      let(:versions_by_file) do
        {
          ".config/mise.toml" => "27.3.2",
          ".mise/config.dev.local.toml" => "28.0-rc1",
          "mise/conf.d/erlang.toml" => "27.3.2",
          ".config/mise/conf.d/erlang/mise.local.toml" => "28.0-rc1"
        }
      end

      it "updates the right tool in each file and preserves its path" do
        expect(updated_contents).to eq(
          ".config/mise.toml" => "[env]\nerlang = '27.3.2'\n[tools]\nerlang = '27.3.3'\n",
          ".mise/config.dev.local.toml" => "[env]\nerlang = '28.0-rc1'\n[tools]\nerlang = '28.0-rc2'\n",
          "mise/conf.d/erlang.toml" => "[env]\nerlang = '27.3.2'\n[tools]\nerlang = '27.3.3'\n",
          ".config/mise/conf.d/erlang/mise.local.toml" => "[env]\nerlang = '28.0-rc1'\n[tools]\nerlang = '28.0-rc2'\n"
        )
      end
    end

    context "when only the prerelease pin can advance" do
      let(:versions_by_file) { { "mise.toml" => "27.3.3", "mise.dev.toml" => "28.0-rc1" } }

      it "updates only the development manifest" do
        expect(updated_contents).to eq(
          "mise.dev.toml" => "[env]\nerlang = '28.0-rc1'\n[tools]\nerlang = '28.0-rc2'\n"
        )
      end

      it "reports the prerelease version that actually changed" do
        updated = updated_dependencies.fetch(0)
        expect([updated.previous_version, updated.version]).to eq(%w(28.0-rc1 28.0-rc2))
      end
    end

    context "when only the stable pin can advance" do
      let(:versions_by_file) { { "mise.toml" => "27.3.2", "mise.dev.toml" => "28.0-rc2" } }

      it "updates only the stable manifest" do
        expect(updated_contents).to eq(
          "mise.toml" => "[env]\nerlang = '27.3.2'\n[tools]\nerlang = '27.3.3'\n"
        )
      end

      it "reports the stable version that actually changed" do
        updated = updated_dependencies.fetch(0)
        expect([updated.previous_version, updated.version]).to eq(%w(27.3.2 27.3.3))
      end
    end

    context "when both manifests are already current" do
      let(:versions_by_file) { { "mise.toml" => "27.3.3", "mise.dev.toml" => "28.0-rc2" } }

      it "reports the dependency as up to date" do
        expect(checker).to be_up_to_date
      end

      it "does not produce an empty update" do
        expect(updated_dependencies).to be_empty
        expect(updated_contents).to be_empty
      end
    end

    context "when the available releases are older than the pins" do
      let(:releases) { %w(27.3.1 28.0-rc0).map { |version| { "version" => version } } }

      it "leaves both pins unchanged" do
        expect(checker.updated_requirements).to eq(dependency.requirements)
        expect(updated_dependencies).to be_empty
      end
    end

    context "when each manifest exposes a different release list" do
      let(:releases_by_file) do
        {
          "mise.toml" => [{ "version" => "27.3.3" }],
          "mise.dev.toml" => [{ "version" => "29.0-rc1" }]
        }
      end

      it "uses the release list from the corresponding manifest" do
        expect(updated_contents).to eq(
          "mise.toml" => "[env]\nerlang = '27.3.2'\n[tools]\nerlang = '27.3.3'\n",
          "mise.dev.toml" => "[env]\nerlang = '28.0-rc1'\n[tools]\nerlang = '29.0-rc1'\n"
        )
      end
    end

    context "when prerelease updates are ignored" do
      let(:ignored_versions) { [">= 28.a"] }
      let(:raise_on_ignored) { true }

      it "updates the stable pin without downgrading the prerelease pin" do
        expect(updated_contents).to eq(
          "mise.toml" => "[env]\nerlang = '27.3.2'\n[tools]\nerlang = '27.3.3'\n"
        )
      end

      context "when the ignored manifest is listed first" do
        let(:versions_by_file) { { "mise.dev.toml" => "28.0-rc1", "mise.toml" => "27.3.2" } }

        it "still updates the stable manifest" do
          expect(updated_contents).to eq(
            "mise.toml" => "[env]\nerlang = '27.3.2'\n[tools]\nerlang = '27.3.3'\n"
          )
        end
      end

      context "when the stable manifest is already current" do
        let(:versions_by_file) { { "mise.toml" => "27.3.3", "mise.dev.toml" => "28.0-rc1" } }

        it "reports that the remaining updates were ignored" do
          expect { checker.latest_version }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end

      context "when every manifest has only ignored updates" do
        let(:ignored_versions) { [">= 27.3.3"] }

        it "reports that all updates were ignored" do
          expect { checker.latest_version }.to raise_error(Dependabot::AllVersionsIgnored)
        end
      end
    end

    context "with different cooldowns for major and patch releases" do
      let(:versions_by_file) { { "mise.toml" => "27.3.2", "mise.dev.toml" => "28.0.0" } }
      let(:cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 0, semver_major_days: 30)
      end
      let(:releases) do
        [
          { "version" => "27.3.2", "created_at" => (Time.now.utc - (60 * 86_400)).iso8601 },
          { "version" => "28.0.0", "created_at" => Time.now.utc.iso8601 },
          { "version" => "28.0.1", "created_at" => Time.now.utc.iso8601 }
        ]
      end

      it "applies cooldown using each manifest's current version" do
        expect(updated_contents).to eq(
          "mise.dev.toml" => "[env]\nerlang = '28.0.0'\n[tools]\nerlang = '28.0.1'\n"
        )
      end
    end

    context "when requirement metadata has been deserialized" do
      let(:dependency) do
        parsed = super()
        Dependabot::Dependency.new(**JSON.parse(JSON.dump(parsed.to_h)).transform_keys(&:to_sym))
      end

      it "preserves per-file version information" do
        expect(updated_dependencies.first.requirements.map { |req| req.metadata_string("resolved_version") })
          .to eq(%w(27.3.3 28.0-rc2))
      end
    end
  end
end
