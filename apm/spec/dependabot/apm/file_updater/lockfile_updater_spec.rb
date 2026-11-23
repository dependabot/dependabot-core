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
      allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command)
        .with("install --no-frozen --target claude,copilot") do
        File.write("apm.lock.yaml", "lockfile_version: '2'\n# #{File.read('apm.yml').lines.fetch(-1).strip}\n")
        ""
      end
    end

    it "runs apm install --no-frozen for each supported harness with project files" do
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
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("install --no-frozen") do
          File.write("apm.lock.yaml", "lockfile_version: '2'\n# installed for the manifest's targets\n")
          ""
        end
      end

      it "runs apm install --no-frozen and lets APM use the manifest's targets" do
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
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("install --no-frozen") do
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
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("install --no-frozen") do
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
    let(:recorded_reference) { "# Reference\n" }
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
              .claude/skills/edge-ai/reference.md: #{digest.call(recorded_reference)}
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
      let(:apm_command) { "install --no-frozen" }

      it "leaves the unmodified deployed files in place for apm install" do
        expect(updated_lockfile_content).to eq("lockfile_version: '2'\n")
        expect(present_during_apm).to eq(
          %w(.claude/skills/edge-ai/SKILL.md .claude/skills/edge-ai/linked.md .claude/skills/edge-ai/reference.md)
        )
        expect(File.read(outside_file)).to eq(skill)
      end

      context "when a deployed file is checked out with CRLF line endings" do
        let(:reference) { "# Reference\r\n" }

        it "matches it against the LF digest APM records and runs apm install" do
          expect(updated_lockfile_content).to eq("lockfile_version: '2'\n")
          expect(Dependabot::Apm::NativeHelpers).to have_received(:run_apm_command).with("install --no-frozen")
        end
      end

      context "when a deployed file differs from its digest only by a bare carriage return" do
        let(:reference) { "# Reference\r" }

        it "treats it as edited" do
          expect { updated_lockfile_content }.to raise_error(Dependabot::DependencyFileNotResolvable, /reference\.md/)
        end
      end

      context "when a deployed binary file differs from its digest only by line endings" do
        let(:reference) { "\0\r\n" }
        let(:recorded_reference) { "\0\n" }

        it "hashes it raw and treats it as edited" do
          expect { updated_lockfile_content }.to raise_error(Dependabot::DependencyFileNotResolvable, /reference\.md/)
        end
      end

      context "when a deployed file has been edited" do
        let(:reference) { "# Reference\nlocal note\n" }

        it "fails before installing, naming only the edited file" do
          expect { updated_lockfile_content }.to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message).to include(".claude/skills/edge-ai/reference.md")
            expect(error.message).to include("no local deployment receipt")
            expect(error.message).not_to include("SKILL.md")
          end
          expect(Dependabot::Apm::NativeHelpers).not_to have_received(:run_apm_command).with("install --no-frozen")
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

  context "when a branch pin moves to a new head commit" do
    let(:old_commit) { "1a" * 20 }
    let(:new_commit) { "2b" * 20 }
    let(:manifest_content) do
      "targets: [claude]\ndependencies:\n  apm:\n    - acme/skills/review#main\n    - microsoft/edge-ai#v1.2.0\n"
    end
    let(:lockfile) do
      Dependabot::DependencyFile.new(
        name: "apm.lock.yaml",
        content: <<~YAML
          lockfile_version: '2'
          dependencies:
          - repo_url: acme/skills
            host: github.com
            virtual_path: review
            resolved_commit: #{old_commit}
            resolved_ref: main
            content_hash: sha256:abc
        YAML
      )
    end
    let(:branch_name) { "acme/skills/review" }
    let(:branch_url) { "https://github.com/acme/skills" }
    let(:branch_declaration) { "acme/skills/review#main" }
    let(:branch_lockfile_key) { "acme/skills//review" }
    let(:branch_dependency) do
      requirement = {
        file: "apm.yml",
        requirement: nil,
        groups: [],
        source: { type: "git", url: branch_url, ref: "main", branch: "main" },
        metadata: { declaration_string: branch_declaration, lockfile_key: branch_lockfile_key }
      }

      Dependabot::Dependency.new(
        name: branch_name,
        version: new_commit,
        previous_version: old_commit,
        requirements: [requirement],
        previous_requirements: [requirement],
        package_manager: "apm"
      )
    end
    let(:dependencies) { [branch_dependency] }
    let(:lockfile_updater) do
      described_class.new(
        dependencies: dependencies,
        lockfile: lockfile,
        manifest_content: manifest_content,
        credentials: [],
        repo_contents_path: nil
      )
    end
    let(:locked_commits) { [] }

    before do
      ["install --no-frozen", "update --yes acme/skills/review"].each do |command|
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with(command) do
          locked_commits << [command, File.read("apm.lock.yaml")[/resolved_commit: (\h+)/, 1]]
          File.write("apm.lock.yaml", "#{File.read('apm.lock.yaml')}# #{command}\n")
          ""
        end
      end
    end

    it "moves it with apm update while the lockfile still names the deployed commit" do
      expect(updated_lockfile_content).to end_with("# update --yes acme/skills/review\n")
      expect(locked_commits).to eq([["update --yes acme/skills/review", old_commit]])
    end

    context "when the lockfile records its targets" do
      let(:manifest_content) { "dependencies:\n  apm:\n    - acme/skills/review#main\n" }
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "apm.lock.yaml",
          content: <<~YAML
            lockfile_version: '2'
            dependencies:
            - repo_url: acme/skills
              host: github.com
              virtual_path: review
              resolved_commit: #{old_commit}
              resolved_ref: main
            deployments:
            - kind: project-relative
              target: claude
              value: .claude/skills/review/SKILL.md
              scope: project
          YAML
        )
      end

      before do
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command)
          .with("targets --json --all", stderr_to_stdout: false)
          .and_return(JSON.generate([{ target: "claude", status: "inactive" }]))
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command)
          .with("update --yes --target claude acme/skills/review") do
          locked_commits << File.read("apm.lock.yaml")[/resolved_commit: (\h+)/, 1]
          ""
        end
      end

      it "passes apm update the same targets" do
        updated_lockfile_content
        expect(locked_commits).to eq([old_commit])
      end
    end

    context "when it is on a host with a non-default port" do
      let(:branch_name) { "ghe.example.com:8443/Acme/Prompts" }
      let(:branch_url) { "https://ghe.example.com:8443/Acme/Prompts" }
      let(:branch_declaration) { "https://ghe.example.com:8443/Acme/Prompts.git#main" }
      let(:branch_lockfile_key) { "ghe.example.com/Acme/Prompts" }
      let(:manifest_content) { "targets: [claude]\ndependencies:\n  apm:\n    - #{branch_declaration}\n" }
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "apm.lock.yaml",
          content: <<~YAML
            lockfile_version: '2'
            dependencies:
            - repo_url: Acme/Prompts
              host: ghe.example.com
              port: 8443
              resolved_commit: #{old_commit}
              resolved_ref: main
          YAML
        )
      end

      before do
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command)
          .with("update --yes ghe.example.com:8443/Acme/Prompts") do
          locked_commits << File.read("apm.lock.yaml")[/resolved_commit: (\h+)/, 1]
          ""
        end
      end

      it "names the package with its port, as APM does" do
        updated_lockfile_content
        expect(locked_commits).to eq([old_commit])
      end
    end

    context "when it is cloned over SSH on a non-default port" do
      let(:branch_name) { "git.example.com/acme/prompts" }
      let(:branch_url) { "https://git.example.com/acme/prompts" }
      let(:branch_declaration) { "ssh://git@git.example.com:2222/acme/prompts.git#main" }
      let(:branch_lockfile_key) { "git.example.com/acme/prompts" }
      let(:manifest_content) { "targets: [claude]\ndependencies:\n  apm:\n    - #{branch_declaration}\n" }
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "apm.lock.yaml",
          content: <<~YAML
            lockfile_version: '2'
            dependencies:
            - repo_url: acme/prompts
              host: git.example.com
              port: 2222
              resolved_commit: #{old_commit}
              resolved_ref: main
          YAML
        )
      end

      before do
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command)
          .with("update --yes git.example.com:2222/acme/prompts") do
          locked_commits << File.read("apm.lock.yaml")[/resolved_commit: (\h+)/, 1]
          ""
        end
      end

      it "names the package with the SSH port APM records" do
        updated_lockfile_content
        expect(locked_commits).to eq([old_commit])
      end
    end

    context "when it is declared in object form" do
      let(:branch_declaration) { "git: https://github.com/acme/skills.git, path: review, ref: main" }
      let(:manifest_content) do
        "targets: [claude]\ndependencies:\n  apm:\n    - git: https://github.com/acme/skills.git\n" \
          "      path: review\n      ref: main\n"
      end

      it "names the package by its repository and path" do
        expect(updated_lockfile_content).to end_with("# update --yes acme/skills/review\n")
        expect(locked_commits).to eq([["update --yes acme/skills/review", old_commit]])
      end
    end

    context "when it is updated alongside a tag pin" do
      let(:dependencies) { [branch_dependency, dependency] }

      it "installs the tag first, then moves the branch, both from the deployed commit" do
        expect(updated_lockfile_content).to end_with("# install --no-frozen\n# update --yes acme/skills/review\n")
        expect(locked_commits.map(&:last)).to eq([old_commit, old_commit])
      end
    end

    context "when APM only locks the manifest" do
      let(:manifest_content) { "dependencies:\n  apm:\n    - acme/skills/review#main\n" }

      before do
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock") do
          locked_commits << File.read("apm.lock.yaml")[/resolved_commit: (\h+)/, 1]
          ""
        end
      end

      it "moves the lock entry to the new commit for apm lock" do
        updated_lockfile_content
        expect(locked_commits).to eq([new_commit])
      end
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
