# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the child-context-only apm_output fixture used by the parent hook.

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/apm/file_updater/lockfile_updater"

RSpec.describe Dependabot::Apm::FileUpdater::LockfileUpdater do
  subject(:updated_lockfile_content) { lockfile_updater.updated_lockfile_content }

  let(:lockfile_updater) do
    described_class.new(
      dependencies: [dependency],
      lockfile: lockfile,
      manifest_content: "dependencies:\n  apm:\n    - microsoft/edge-ai#v1.2.0\n",
      credentials: [],
      repo_contents_path: nil
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "apm.lock.yaml", content: "lockfile_version: '1'\ndependencies: []\n")
  end
  let(:dependency) do
    requirement = lambda do |ref|
      {
        file: "apm.yml",
        requirement: nil,
        groups: [],
        source: { type: "git", url: "https://github.com/microsoft/edge-ai", ref: ref, branch: nil },
        metadata: { declaration_string: "microsoft/edge-ai#v1.0.0" }
      }
    end

    Dependabot::Dependency.new(
      name: "microsoft/edge-ai",
      version: "1.2.0",
      previous_version: "1.0.0",
      requirements: [requirement.call("v1.2.0")],
      previous_requirements: [requirement.call("v1.0.0")],
      package_manager: "apm"
    )
  end

  context "when the lockfile records no deployed files" do
    before do
      allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock") do
        File.write("apm.lock.yaml", "lockfile_version: '1'\n# #{File.read('apm.yml').lines.fetch(-1).strip}\n")
        ""
      end
    end

    it "returns the lockfile apm lock wrote for the updated manifest" do
      expect(updated_lockfile_content).to eq("lockfile_version: '1'\n# - microsoft/edge-ai#v1.2.0\n")
    end
  end

  context "when the lockfile records deployed files" do
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "apm.lock.yaml",
        content: <<~YAML
          lockfile_version: '2'
          dependencies: []
          deployments:
          - kind: project-relative
            target: copilot
            value: .github/skills/edge-ai/SKILL.md
            scope: project
          - kind: project-relative
            target: claude
            value: .claude/skills/edge-ai/SKILL.md
            scope: project
          - kind: project-relative
            target: copilot
            value: .github/skills/edge-ai/README.md
            scope: project
          - kind: uri
            target: mcp
            value: context7
            runtime: claude
            scope: project
          - kind: uri
            target: lsp
            value: pyright
            runtime: claude
            scope: project
          - kind: project-relative
            target: codex
            value: .codex/skills/edge-ai/SKILL.md
            scope: user
          - kind: project-relative
            target: legacy
            value: .agents/skills/edge-ai/SKILL.md
            scope: project
          - kind: project-relative
            target: "claude; touch pwned"
            value: .claude/skills/edge-ai/README.md
            scope: project
        YAML
      )
    end
    let(:apm_targets_output) do
      JSON.generate(%w(claude copilot codex agent-skills).map { |target| { target: target, status: "inactive" } })
    end

    before do
      allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command)
        .with("targets --json --all", stderr_to_stdout: false).and_return(apm_targets_output)
      allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("install --target claude,copilot") do
        File.write("apm.lock.yaml", "lockfile_version: '2'\n# #{File.read('apm.yml').lines.fetch(-1).strip}\n")
        ""
      end
    end

    it "runs apm install for each supported harness with project files" do
      expect(updated_lockfile_content).to eq("lockfile_version: '2'\n# - microsoft/edge-ai#v1.2.0\n")
    end

    context "when an MCP server is configured for a runtime outside the recorded targets" do
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "apm.lock.yaml",
          content: <<~YAML
            lockfile_version: '2'
            dependencies: []
            deployments:
            - kind: project-relative
              target: copilot
              value: .github/skills/edge-ai/SKILL.md
              scope: project
            - kind: uri
              target: mcp
              value: context7
              runtime: intellij
              scope: project
          YAML
        )
      end

      before do
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock") do
          File.write("apm.lock.yaml", "lockfile_version: '2'\n# locked\n")
          ""
        end
      end

      it "runs apm lock rather than reconciling the MCP server for another runtime" do
        expect(updated_lockfile_content).to eq("lockfile_version: '2'\n# locked\n")
      end
    end

    context "when apm targets fails" do
      before do
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command)
          .with("targets --json --all", stderr_to_stdout: false).and_raise(
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "No such command", error_context: {})
          )
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock") do
          File.write("apm.lock.yaml", "lockfile_version: '2'\n# locked\n")
          ""
        end
      end

      it "runs apm lock" do
        expect(updated_lockfile_content).to eq("lockfile_version: '2'\n# locked\n")
      end
    end

    context "when the manifest declares its targets" do
      let(:manifest_content) { "targets:\n  - intellij\ndependencies:\n  apm:\n    - microsoft/edge-ai#v1.2.0\n" }
      let(:lockfile_updater) do
        described_class.new(
          dependencies: [dependency],
          lockfile: lockfile,
          manifest_content: manifest_content,
          credentials: [],
          repo_contents_path: nil
        )
      end

      before do
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("install") do
          File.write("apm.lock.yaml", "lockfile_version: '2'\n# installed for the manifest's targets\n")
          ""
        end
      end

      it "runs apm install and lets APM use the manifest's targets" do
        expect(updated_lockfile_content).to eq("lockfile_version: '2'\n# installed for the manifest's targets\n")
      end

      context "when the manifest uses a YAML alias" do
        let(:manifest_content) do
          "x-skills: &skills microsoft/edge-ai#v1.2.0\ntargets: [claude]\ndependencies:\n  apm:\n    - *skills\n"
        end

        it "still reads the declared targets" do
          expect(updated_lockfile_content).to eq("lockfile_version: '2'\n# installed for the manifest's targets\n")
        end
      end

      context "when the manifest declares targets as a comma-separated string" do
        let(:manifest_content) { "target: claude,copilot\ndependencies:\n  apm:\n    - microsoft/edge-ai#v1.2.0\n" }

        it "runs apm install" do
          expect(updated_lockfile_content).to eq("lockfile_version: '2'\n# installed for the manifest's targets\n")
        end
      end

      context "when the manifest declares the legacy all target" do
        let(:manifest_content) { "targets: [claude, all]\ndependencies:\n  apm:\n    - microsoft/edge-ai#v1.2.0\n" }

        it "treats the targets as unspecified and uses the recorded ones" do
          expect(updated_lockfile_content).to eq("lockfile_version: '2'\n# - microsoft/edge-ai#v1.2.0\n")
        end
      end
    end
  end

  context "when apm install deploys files into a reused checkout" do
    let(:repo_contents_path) { Dir.mktmpdir }
    let(:deployed_file) { File.join(repo_contents_path, ".claude", "skills", "edge-ai", "SKILL.md") }
    let(:tracked_file) { File.join(repo_contents_path, ".claude", "settings.json") }
    let(:lockfile_updater) do
      described_class.new(
        dependencies: [dependency],
        lockfile: lockfile,
        manifest_content: "targets: [claude]\ndependencies:\n  apm:\n    - microsoft/edge-ai#v1.2.0\n",
        credentials: [],
        repo_contents_path: repo_contents_path
      )
    end

    before do
      Dir.chdir(repo_contents_path) do
        FileUtils.mkdir_p(".claude")
        File.write(".gitignore", ".claude/skills/\n")
        File.write(".claude/settings.json", "{}\n")
        system(
          "git init -q && git add . && git -c user.name=test -c user.email=test@example.com commit -qm init",
          exception: true
        )
      end
    end

    after { FileUtils.rm_rf(repo_contents_path) }

    context "when the install succeeds" do
      before do
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("install") do
          FileUtils.mkdir_p(".claude/skills/edge-ai")
          File.write(".claude/skills/edge-ai/SKILL.md", "skill")
          File.write("apm.lock.yaml", "lockfile_version: '2'\n")
          ""
        end
      end

      it "removes the deployed files and keeps tracked harness files" do
        expect(updated_lockfile_content).to eq("lockfile_version: '2'\n")
        expect(File.exist?(deployed_file)).to be(false)
        expect(File.exist?(tracked_file)).to be(true)
      end
    end

    context "when the install fails after deploying files" do
      before do
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("install") do
          FileUtils.mkdir_p(".claude/skills/edge-ai")
          File.write(".claude/skills/edge-ai/SKILL.md", "skill")
          raise Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "boom", error_context: {})
        end
      end

      it "still removes the deployed files" do
        expect { updated_lockfile_content }.to raise_error(Dependabot::DependencyFileNotResolvable)
        expect(File.exist?(deployed_file)).to be(false)
      end
    end
  end

  context "when the checkout commits the files APM deployed" do
    let(:repo_contents_path) { Dir.mktmpdir }
    let(:outside_directory) { Dir.mktmpdir }
    let(:skill) { "# Edge AI\n" }
    let(:reference) { "# Reference\n" }
    let(:outside_file) { File.join(outside_directory, "SKILL.md") }
    let(:lockfile) do
      digest = ->(content) { "sha256:#{Digest::SHA256.hexdigest(content)}" }
      Dependabot::DependencyFile.new(
        name: "apm.lock.yaml",
        content: <<~YAML
          lockfile_version: '1'
          dependencies:
          - repo_url: microsoft/edge-ai
            deployed_file_hashes:
              .claude/skills/edge-ai/SKILL.md: #{digest.call(skill)}
              .claude/skills/edge-ai/reference.md: #{digest.call("# Reference\n")}
              .claude/skills/edge-ai/linked.md: #{digest.call(skill)}
              #{outside_file}: #{digest.call(skill)}
              ../#{File.basename(outside_directory)}/SKILL.md: #{digest.call(skill)}
        YAML
      )
    end
    let(:lockfile_updater) do
      described_class.new(
        dependencies: [dependency],
        lockfile: lockfile,
        manifest_content: manifest_content,
        credentials: [],
        repo_contents_path: repo_contents_path
      )
    end
    let(:manifest_content) { "targets: [claude]\ndependencies:\n  apm:\n    - microsoft/edge-ai#v1.2.0\n" }
    let(:present_during_apm) { [] }

    before do
      File.write(outside_file, skill)
      Dir.chdir(repo_contents_path) do
        FileUtils.mkdir_p(".claude/skills/edge-ai")
        File.write(".claude/skills/edge-ai/SKILL.md", skill)
        File.write(".claude/skills/edge-ai/reference.md", reference)
        File.symlink(outside_file, ".claude/skills/edge-ai/linked.md")
        system(
          "git init -q && git add . && git -c user.name=test -c user.email=test@example.com commit -qm init",
          exception: true
        )
      end
      allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with(apm_command) do
        present_during_apm.concat(Dir.glob(".claude/skills/edge-ai/*"))
        File.write("apm.lock.yaml", "lockfile_version: '2'\n")
        ""
      end
    end

    after do
      FileUtils.rm_rf(repo_contents_path)
      FileUtils.rm_rf(outside_directory)
    end

    context "when apm install runs" do
      let(:apm_command) { "install" }

      it "removes only the unmodified deployed files inside the checkout before installing" do
        expect(updated_lockfile_content).to eq("lockfile_version: '2'\n")
        expect(present_during_apm).to eq(%w(.claude/skills/edge-ai/linked.md))
        expect(File.read(outside_file)).to eq(skill)
      end

      context "when a deployed file has been edited" do
        let(:reference) { "# Reference\nlocal note\n" }

        it "fails before installing, naming the edited file and removing nothing" do
          expect { updated_lockfile_content }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include(".claude/skills/edge-ai/reference.md")
            expect(error.message).to include("microsoft/apm#3625")
            expect(error.message).not_to include("SKILL.md")
          end
          expect(Dependabot::Apm::NativeHelpers).not_to have_received(:run_apm_command).with("install")
          expect(File.exist?(File.join(repo_contents_path, ".claude/skills/edge-ai/SKILL.md"))).to be(true)
        end
      end
    end

    context "when apm lock runs" do
      let(:manifest_content) { "dependencies:\n  apm:\n    - microsoft/edge-ai#v1.2.0\n" }
      let(:apm_command) { "lock" }

      it "leaves the deployed files in place" do
        expect(updated_lockfile_content).to eq("lockfile_version: '2'\n")
        expect(present_during_apm).to eq(
          %w(.claude/skills/edge-ai/SKILL.md .claude/skills/edge-ai/linked.md .claude/skills/edge-ai/reference.md)
        )
      end
    end
  end

  context "when a legacy lockfile records deployed files without deployments" do
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "apm.lock.yaml",
        content: <<~YAML
          lockfile_version: '1'
          dependencies:
          - repo_url: microsoft/edge-ai
            deployed_files:
            - .claude/skills/edge-ai
        YAML
      )
    end

    before do
      allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock") do
        File.write("apm.lock.yaml", "lockfile_version: '1'\n# locked\n")
        ""
      end
    end

    it "runs apm lock rather than inferring harnesses from the deployed paths" do
      expect(updated_lockfile_content).to eq("lockfile_version: '1'\n# locked\n")
    end
  end

  context "when a previous update left packages in apm_modules" do
    let(:repo_contents_path) { Dir.mktmpdir }
    let(:stale_package) { File.join(repo_contents_path, "apm_modules", "microsoft", "edge-ai", "apm.yml") }
    let(:lockfile_updater) do
      described_class.new(
        dependencies: [dependency],
        lockfile: lockfile,
        manifest_content: "dependencies:\n  apm:\n    - microsoft/edge-ai#v1.2.0\n",
        credentials: [],
        repo_contents_path: repo_contents_path
      )
    end

    before do
      Dir.chdir(repo_contents_path) do
        File.write(".gitignore", "apm_modules/\n")
        system(
          "git init -q && git add .gitignore && git -c user.name=test -c user.email=test@example.com commit -qm init",
          exception: true
        )
      end
      FileUtils.mkdir_p(File.dirname(stale_package))
      File.write(stale_package, "stale")

      allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock") do
        modules_present = Dir.exist?("apm_modules")
        FileUtils.mkdir_p("apm_modules/microsoft/edge-ai")
        File.write("apm.lock.yaml", "apm_modules_present: #{modules_present}\n")
        ""
      end
    end

    after { FileUtils.rm_rf(repo_contents_path) }

    it "runs apm lock without them and removes the packages it downloaded" do
      expect(updated_lockfile_content).to eq("apm_modules_present: false\n")
      expect(Dir.exist?(File.join(repo_contents_path, "apm_modules"))).to be(false)
    end
  end

  context "when apm lock fails" do
    before do
      allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock").and_raise(
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: apm_output, error_context: {})
      )
    end

    context "when a repository can't be authenticated" do
      let(:apm_output) do
        "Failed to download dependency x/y: Failed to clone repository x/y: Authentication failed for clone " \
          "on github.com. No token available.\nfatal: Authentication failed for 'https://github.com/x/y.git/'"
      end

      it "raises a GitDependenciesNotReachable error for the repository" do
        expect { updated_lockfile_content }.to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
          expect(error.dependency_urls).to eq(["https://github.com/x/y.git/"])
        end
      end
    end

    context "when APM reports a rejected clone without git's error" do
      let(:apm_output) do
        "  [x] 1 package failed:\n    +- y -- Failed to download dependency x/y: Failed to clone repository x/y. " \
          "Authentication failed for clone on github.com.\nNo token available.\n" \
          "[x] Installation failed with 1 error(s)."
      end

      it "raises a GitDependenciesNotReachable error for the repository" do
        expect { updated_lockfile_content }.to raise_error(Dependabot::GitDependenciesNotReachable) do |error|
          expect(error.dependency_urls).to eq(["https://github.com/x/y"])
        end
      end
    end

    context "when a pinned branch no longer exists" do
      let(:apm_output) do
        "Failed to download dependency microsoft/edge-ai: Failed to clone repository: " \
          "fatal: Remote branch gone not found in upstream origin"
      end

      it "raises a GitDependencyReferenceNotFound error for the dependency" do
        expect { updated_lockfile_content }.to raise_error(Dependabot::GitDependencyReferenceNotFound) do |error|
          expect(error.dependency).to eq("microsoft/edge-ai")
        end
      end
    end

    context "when a pinned reference can't be resolved" do
      let(:apm_output) do
        "Failed to download dependency microsoft/edge-ai: Reference 'v9.9.9' not found in repository " \
          "https://github.com/microsoft/edge-ai"
      end

      it "raises a GitDependencyReferenceNotFound error for the dependency" do
        expect { updated_lockfile_content }.to raise_error(Dependabot::GitDependencyReferenceNotFound)
      end
    end

    context "when another package fails before the one with a missing reference" do
      let(:apm_output) do
        "  [x] 2 packages failed:\n" \
          "    +- first -- Failed to download dependency acme/first: Failed to clone repository acme/first: " \
          "timed out\n" \
          "    +- second -- Failed to download dependency acme/second: Reference 'v9.9.9' not found in repository " \
          "https://github.com/acme/second\n"
      end

      it "attributes the missing reference to the package it belongs to" do
        expect { updated_lockfile_content }.to raise_error(Dependabot::GitDependencyReferenceNotFound) do |error|
          expect(error.dependency).to eq("acme/second")
        end
      end
    end

    context "when a transitive dependency's reference can't be resolved" do
      let(:apm_output) do
        "    +- second -- Failed to resolve transitive dep acme/second (via acme/parent > second): " \
          "Could not resolve reference 'v9.9.9' in repository acme/second: " \
          "Reference 'v9.9.9' not found in repository acme/second\n"
      end

      it "raises a GitDependencyReferenceNotFound error for the transitive dependency" do
        expect { updated_lockfile_content }.to raise_error(Dependabot::GitDependencyReferenceNotFound) do |error|
          expect(error.dependency).to eq("acme/second")
        end
      end
    end

    context "when a pinned commit can't be fetched because of a network failure" do
      let(:apm_output) do
        "Failed to download dependency acme/first: Could not resolve commit '#{'a' * 40}' in repository " \
          "acme/first: fatal: unable to access 'https://github.com/acme/first/': Could not resolve host: github.com"
      end

      it "doesn't report the commit as missing" do
        expect { updated_lockfile_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /Could not resolve host/)
      end
    end

    context "when a pinned commit doesn't exist" do
      let(:apm_output) do
        "Failed to download dependency acme/first: Could not resolve commit '#{'a' * 40}' in repository " \
          "acme/first: fatal: Needed a single revision"
      end

      it "raises a GitDependencyReferenceNotFound error for the dependency" do
        expect { updated_lockfile_content }.to raise_error(Dependabot::GitDependencyReferenceNotFound) do |error|
          expect(error.dependency).to eq("acme/first")
        end
      end
    end

    context "when apm fails for any other reason" do
      let(:apm_output) { "Invalid apm.yml: dependencies.apm must be a list" }

      it "raises a DependencyFileNotResolvable error with apm's message" do
        expect { updated_lockfile_content }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /must be a list/)
      end
    end
  end
end
