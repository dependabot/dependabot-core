# typed: false
# frozen_string_literal: true

require "spec_helper"
require "json"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/file_updaters"
require "dependabot/devbox/file_updater"

RSpec.describe Dependabot::Devbox::FileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: credentials
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
  let(:manifest_content) { '{ "packages": ["python@3.10"] }' }
  let(:lockfile_content) do
    JSON.dump("lockfile_version" => "1", "packages" => { "python@3.10" => { "version" => "3.10.13" } })
  end
  let(:files) do
    [
      Dependabot::DependencyFile.new(name: "devbox.json", content: manifest_content),
      Dependabot::DependencyFile.new(name: "devbox.lock", content: lockfile_content)
    ]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "python",
      version: "3.11.2",
      previous_version: "3.10.13",
      requirements: [{ requirement: new_constraint, file: "devbox.json", groups: [], source: { type: "nixhub" } }],
      previous_requirements: [{ requirement: old_constraint, file: "devbox.json", groups: [],
                                source: { type: "nixhub" } }],
      package_manager: "devbox"
    )
  end
  let(:old_constraint) { "3.10" }
  let(:new_constraint) { "3.11" }

  it "is registered for the devbox package manager" do
    expect(Dependabot::FileUpdaters.for_package_manager("devbox")).to eq(described_class)
  end

  describe "#updated_dependency_files" do
    # Stub the devbox shell-out: write `regenerated_lock` into the temp dir so the
    # updater reads it back, mimicking a real `devbox update --no-install`.
    let(:regenerated_lock) do
      JSON.dump("lockfile_version" => "1", "packages" => { "python@3.11" => { "version" => "3.11.2" } })
    end

    before do
      allow(Dependabot::Devbox::Helpers).to receive(:run_devbox_command) do |*_args, dir:|
        File.write(File.join(dir, "devbox.lock"), regenerated_lock)
        ""
      end
    end

    context "when the constraint changes (pinned bump)" do
      it "rewrites the manifest entry and regenerates the lockfile" do
        updated = updater.updated_dependency_files
        manifest = updated.find { |f| f.name == "devbox.json" }
        lockfile = updated.find { |f| f.name == "devbox.lock" }

        expect(manifest.content).to include('"python@3.11"')
        expect(manifest.content).not_to include('"python@3.10"')
        expect(lockfile.content).to eq(regenerated_lock)
      end
    end

    context "with a latest constraint (lockfile-only)" do
      let(:manifest_content) { '{ "packages": ["ripgrep@latest"] }' }
      let(:old_constraint) { "latest" }
      let(:new_constraint) { "latest" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "ripgrep",
          version: "14.1.0",
          previous_version: "14.0.0",
          requirements: [{ requirement: "latest", file: "devbox.json", groups: [], source: { type: "nixhub" } }],
          previous_requirements: [{ requirement: "latest", file: "devbox.json", groups: [],
                                    source: { type: "nixhub" } }],
          package_manager: "devbox"
        )
      end

      it "updates only the lockfile" do
        updated = updater.updated_dependency_files
        expect(updated.map(&:name)).to contain_exactly("devbox.lock")
      end
    end

    context "when the lockfile does not change" do
      let(:regenerated_lock) { lockfile_content }

      it "raises DependencyFileContentNotChanged" do
        expect { updater.updated_dependency_files }
          .to raise_error(Dependabot::DependencyFileContentNotChanged)
      end
    end

    context "when the devbox command fails" do
      before do
        allow(Dependabot::Devbox::Helpers).to receive(:run_devbox_command)
          .and_raise(
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(
              message: "boom",
              error_context: { command: "devbox update" }
            )
          )
      end

      it "raises DependencyFileNotResolvable" do
        expect { updater.updated_dependency_files }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /boom/)
      end
    end
  end

  describe "#updated_dependency_files with the real devbox binary", :slow do
    let(:files) { project_dependency_files("devbox/with_lockfile") }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "python",
        version: "3.10.19",
        previous_version: "3.10.0",
        requirements: [{ requirement: "3.10", file: "devbox.json", groups: [], source: { type: "nixhub" } }],
        previous_requirements: [{ requirement: "3.10", file: "devbox.json", groups: [], source: { type: "nixhub" } }],
        package_manager: "devbox"
      )
    end

    before do
      skip "devbox binary not available" unless system("which devbox > /dev/null 2>&1")
    end

    it "regenerates devbox.lock to a newer resolved python version" do
      updated = updater.updated_dependency_files
      lockfile = updated.find { |f| f.name == "devbox.lock" }

      parsed = JSON.parse(lockfile.content)
      expect(parsed.dig("packages", "python@3.10", "version")).not_to eq("3.10.0")
    end
  end
end
