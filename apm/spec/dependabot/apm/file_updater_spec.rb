# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the child-context-only declaration_spans fixture.

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/apm/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Apm::FileUpdater do
  let(:manifest_body) do
    <<~YAML
      dependencies:
        apm:
          - microsoft/edge-ai#v1.0.0
          - microsoft/edge-ai-extras#v1.0.0
    YAML
  end
  let(:manifest) do
    Dependabot::DependencyFile.new(name: "apm.yml", content: manifest_body)
  end
  let(:declaration_span) { "2:6:2:30" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "microsoft/edge-ai",
      version: "1.2.0",
      previous_version: "1.0.0",
      requirements: [{
        file: "apm.yml",
        requirement: nil,
        groups: [],
        source: {
          type: "git",
          url: "https://github.com/microsoft/edge-ai",
          ref: "v1.2.0",
          branch: nil
        },
        metadata: { declaration_string: "microsoft/edge-ai#v1.0.0", declaration_span: declaration_span }
      }],
      previous_requirements: [{
        file: "apm.yml",
        requirement: nil,
        groups: [],
        source: {
          type: "git",
          url: "https://github.com/microsoft/edge-ai",
          ref: "v1.0.0",
          branch: nil
        },
        metadata: { declaration_string: "microsoft/edge-ai#v1.0.0", declaration_span: declaration_span }
      }],
      package_manager: "apm"
    )
  end
  let(:updater) do
    described_class.new(
      dependency_files: [manifest],
      dependencies: [dependency],
      credentials: [Dependabot::Credential.new(
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      )]
    )
  end

  it_behaves_like "a dependency file updater"

  describe ".updated_files_regex" do
    it "matches apm.yml and its lockfile" do
      expect(described_class.updated_files_regex).to all(be_a(Regexp))
      %w(apm.yml apm.lock.yaml).each do |name|
        expect(described_class.updated_files_regex.any? { |re| name.match?(re) }).to be(true)
      end
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns a single updated manifest" do
      expect(updated_files.length).to eq(1)
      expect(updated_files.first.name).to eq("apm.yml")
    end

    it "bumps the pinned ref" do
      expect(updated_files.first.content).to include("microsoft/edge-ai#v1.2.0")
    end

    it "does not touch an entry that merely shares the same prefix" do
      expect(updated_files.first.content).to include("microsoft/edge-ai-extras#v1.0.0")
    end

    context "when the repo contains a lockfile and a similarly named file" do
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "apm.lock.yaml",
          content: "lockfile_version: '1'\napm_version: 0.33.0\n",
          support_file: true
        )
      end
      let(:decoy) do
        Dependabot::DependencyFile.new(name: "legacy-apm.yml", content: manifest_body)
      end
      let(:updater) do
        described_class.new(
          dependency_files: [manifest, lockfile, decoy],
          dependencies: [dependency],
          credentials: []
        )
      end

      it "selects only the manifest, by exact basename" do
        expect(updater.send(:manifest_files).map(&:name)).to eq(["apm.yml"])
      end

      context "when apm lock re-resolves the bumped entry" do
        before do
          allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock") do
            File.write(
              "apm.lock.yaml",
              "lockfile_version: '1'\napm_version: 0.33.0\n" \
              "# locked against: #{File.read('apm.yml').lines.fetch(2).strip}\n"
            )
            ""
          end
        end

        it "regenerates the lockfile against the updated manifest" do
          expect(updated_files.map(&:name)).to eq(["apm.yml", "apm.lock.yaml"])
          expect(updated_files.last.content).to include("# locked against: - microsoft/edge-ai#v1.2.0")
        end
      end

      context "when apm lock leaves the lockfile unchanged" do
        before do
          allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock").and_return("")
        end

        it "updates only apm.yml" do
          expect(updated_files.map(&:name)).to eq(["apm.yml"])
        end
      end
    end

    context "when apm install redeploys the skills in a cloned repository" do
      let(:repo_contents_path) { Dir.mktmpdir }
      let(:digest) { ->(content) { "sha256:#{Digest::SHA256.hexdigest(content)}" } }
      let(:skill_v1) { "# Edge AI v1.0.0\n" }
      let(:skill_v2) { "# Edge AI v1.2.0\n" }
      let(:reference) { "# Reference\n" }
      let(:retired) { "# Retired in v1.2.0\n" }
      let(:added) { "# Added in v1.2.0\n" }
      let(:manifest_body) do
        <<~YAML
          targets: [claude]
          dependencies:
            apm:
              - microsoft/edge-ai#v1.0.0
              - microsoft/edge-ai-extras#v1.0.0
        YAML
      end
      let(:declaration_span) { "3:6:3:30" }
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "apm.lock.yaml",
          content: <<~YAML
            lockfile_version: '2'
            dependencies:
            - repo_url: microsoft/edge-ai
              resolved_ref: v1.0.0
              deployed_files:
              - .claude/skills/edge-ai
              - .claude/skills/edge-ai/SKILL.md
              - .claude/skills/edge-ai/reference.md
              - .claude/skills/edge-ai/retired.md
              deployed_file_hashes:
                .claude/skills/edge-ai/SKILL.md: #{digest.call(skill_v1)}
                .claude/skills/edge-ai/reference.md: #{digest.call(reference)}
                .claude/skills/edge-ai/retired.md: #{digest.call(retired)}
          YAML
        )
      end
      let(:new_lockfile_content) do
        <<~YAML
          lockfile_version: '2'
          dependencies:
          - repo_url: microsoft/edge-ai
            resolved_ref: v1.2.0
            deployed_files:
            - .claude/skills/edge-ai
            - .claude/skills/edge-ai/SKILL.md
            - .claude/skills/edge-ai/reference.md
            - .claude/skills/edge-ai/added.md
            deployed_file_hashes:
              .claude/skills/edge-ai/SKILL.md: #{digest.call(skill_v2)}
              .claude/skills/edge-ai/reference.md: #{digest.call(reference)}
              .claude/skills/edge-ai/added.md: #{digest.call(added)}
        YAML
      end
      let(:gitignore) { "apm_modules/\n" }
      let(:deployed_files) do
        {
          ".claude/skills/edge-ai/SKILL.md" => skill_v1,
          ".claude/skills/edge-ai/reference.md" => reference,
          ".claude/skills/edge-ai/retired.md" => retired
        }
      end
      let(:updater) do
        described_class.new(
          dependency_files: [manifest, lockfile],
          dependencies: [dependency],
          credentials: [],
          repo_contents_path: repo_contents_path
        )
      end
      let(:deployed_changes) do
        updated_files.drop(2).to_h do |file|
          [file.name, [file.operation, file.content, file.vendored_file?, file.directory]]
        end
      end

      before do
        Dir.chdir(repo_contents_path) do
          File.write(".gitignore", gitignore)
          File.write("apm.yml", manifest_body)
          File.write("apm.lock.yaml", lockfile.content)
          deployed_files.each do |path, content|
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, content)
          end
          system(
            "git init -q && git add . && git -c user.name=test -c user.email=test@example.com commit -qm init",
            exception: true
          )
        end

        # Mimics APM deploying v1.2.0: it rewrites SKILL.md and reference.md
        # (the workaround for microsoft/apm#3625 removed both, as they match
        # their recorded digests), deploys added.md, leaves retired.md removed,
        # downloads into apm_modules and writes an MCP config it doesn't record
        # as deployed.
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("install") do
          FileUtils.mkdir_p(".claude/skills/edge-ai")
          File.write(".claude/skills/edge-ai/SKILL.md", skill_v2)
          File.write(".claude/skills/edge-ai/reference.md", reference)
          File.write(".claude/skills/edge-ai/added.md", added)
          FileUtils.mkdir_p("apm_modules/microsoft/edge-ai")
          File.write("apm_modules/microsoft/edge-ai/apm.yml", "name: edge-ai\n")
          File.write(".mcp.json", "{}\n")
          File.write("apm.lock.yaml", new_lockfile_content)
          ""
        end
      end

      after { FileUtils.rm_rf(repo_contents_path) }

      context "when the repository commits its deployed files" do
        it "returns the deployed files APM added, changed and removed with the manifest and lockfile" do
          expect(updated_files.first(2).map(&:name)).to eq(%w(apm.yml apm.lock.yaml))
          expect(updated_files[1].content).to eq(new_lockfile_content)
          expect(deployed_changes).to eq(
            ".claude/skills/edge-ai/SKILL.md" => [Dependabot::DependencyFile::Operation::UPDATE, skill_v2, true, "/"],
            ".claude/skills/edge-ai/added.md" => [Dependabot::DependencyFile::Operation::CREATE, added, true, "/"],
            ".claude/skills/edge-ai/retired.md" => [Dependabot::DependencyFile::Operation::DELETE, nil, true, "/"]
          )
          expect(updated_files.find { |file| file.name.end_with?("retired.md") }).to be_deleted
        end

        it "removes what apm install wrote, including the file it added" do
          updated_files

          Dir.chdir(repo_contents_path) do
            expect(Dir.exist?("apm_modules")).to be(false)
            expect(File.exist?(".mcp.json")).to be(false)
            expect(File.exist?(".claude/skills/edge-ai/added.md")).to be(false)
          end
        end
      end

      context "when a grouped update runs it in a workspace before updating another dependency" do
        let(:extras_dependency) do
          requirement = lambda do |ref|
            {
              file: "apm.yml",
              requirement: nil,
              groups: [],
              source: { type: "git", url: "https://github.com/microsoft/edge-ai-extras", ref: ref, branch: nil },
              metadata: { declaration_string: "microsoft/edge-ai-extras#v1.0.0", declaration_span: "4:6:4:37" }
            }
          end
          Dependabot::Dependency.new(
            name: "microsoft/edge-ai-extras",
            version: "1.1.0",
            previous_version: "1.0.0",
            requirements: [requirement.call("v1.1.0")],
            previous_requirements: [requirement.call("v1.0.0")],
            package_manager: "apm"
          )
        end
        let(:extras_lockfile_content) do
          "#{new_lockfile_content}- repo_url: microsoft/edge-ai-extras\n  resolved_ref: v1.1.0\n"
        end

        before { Dependabot::Workspace.setup(repo_contents_path: repo_contents_path, directory: Pathname.new("/")) }

        after { Dependabot::Workspace.cleanup! }

        it "keeps the file it added for the workspace to commit, so the next update doesn't return it again" do
          first_update = updated_files
          expect(File.read(File.join(repo_contents_path, ".claude/skills/edge-ai/added.md"))).to eq(added)
          expect(File.exist?(File.join(repo_contents_path, ".mcp.json"))).to be(false)
          Dependabot::Workspace.store_change(memo: "Update microsoft/edge-ai")

          # Mimics APM deploying every file the lockfile records, as the
          # workaround removed the unmodified ones, while bumping the extras.
          allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("install") do
            File.write(".claude/skills/edge-ai/SKILL.md", skill_v2)
            File.write(".claude/skills/edge-ai/reference.md", reference)
            File.write(".claude/skills/edge-ai/added.md", added)
            File.write("apm.lock.yaml", extras_lockfile_content)
            ""
          end
          second_update = described_class.new(
            dependency_files: first_update.first(2),
            dependencies: [extras_dependency],
            credentials: [],
            repo_contents_path: repo_contents_path
          ).updated_dependency_files

          expect(second_update.map(&:name)).to eq(%w(apm.yml apm.lock.yaml))
          expect(second_update.first.content).to include("microsoft/edge-ai-extras#v1.1.0")
        end
      end

      context "when the repository commits an executable deployed script" do
        let(:script) { ".claude/skills/edge-ai/scripts/run.sh" }
        let(:added_script) { ".claude/skills/edge-ai/scripts/setup.sh" }

        before do
          Dir.chdir(repo_contents_path) do
            FileUtils.mkdir_p(File.dirname(script))
            File.write(script, "#!/bin/sh\necho v1.0.0\n")
            File.chmod(0o755, script)
            system(
              "git add . && git -c user.name=test -c user.email=test@example.com commit -qm script",
              exception: true
            )
          end
          allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("install") do
            File.write(".claude/skills/edge-ai/SKILL.md", skill_v2)
            File.write(script, "#!/bin/sh\necho v1.2.0\n")
            File.write(added_script, "#!/bin/sh\necho setup\n")
            File.chmod(0o755, added_script)
            File.write("apm.lock.yaml", new_lockfile_content)
            ""
          end
        end

        it "keeps the executable mode of the scripts it returns" do
          modes = updated_files.drop(2).to_h { |file| [file.name, file.mode] }

          expect(modes).to include(
            ".claude/skills/edge-ai/SKILL.md" => Dependabot::DependencyFile::Mode::FILE,
            script => Dependabot::DependencyFile::Mode::EXECUTABLE,
            added_script => Dependabot::DependencyFile::Mode::EXECUTABLE
          )
        end
      end

      context "when the repository ignores its deployed files" do
        let(:gitignore) { "apm_modules/\n.claude/\n.mcp.json\n" }
        let(:deployed_files) { {} }

        it "returns only the manifest and lockfile" do
          expect(updated_files.map(&:name)).to eq(%w(apm.yml apm.lock.yaml))
        end
      end

      context "when the lockfile records no harness, so apm lock runs" do
        let(:manifest_body) do
          <<~YAML
            dependencies:
              apm:
                - microsoft/edge-ai#v1.0.0
                - microsoft/edge-ai-extras#v1.0.0
          YAML
        end
        let(:declaration_span) { "2:6:2:30" }

        before do
          allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock") do
            File.write("apm.lock.yaml", new_lockfile_content)
            ""
          end
        end

        it "returns only the manifest and lockfile, as apm lock deploys nothing" do
          expect(updated_files.map(&:name)).to eq(%w(apm.yml apm.lock.yaml))
          expect(File.read(File.join(repo_contents_path, ".claude/skills/edge-ai/SKILL.md"))).to eq(skill_v1)
        end
      end
    end

    context "when a full SHA pin moves to a new release" do
      let(:old_sha) { "a" * 40 }
      let(:new_sha) { "b" * 40 }
      let(:dependency) do
        requirement = lambda do |ref, span, metadata = {}|
          {
            file: "apm.yml",
            requirement: nil,
            groups: [],
            source: { type: "git", url: "https://github.com/microsoft/edge-ai", ref: ref, branch: nil },
            metadata: { declaration_string: "microsoft/edge-ai##{old_sha}", declaration_span: span }.merge(metadata)
          }
        end

        Dependabot::Dependency.new(
          name: "microsoft/edge-ai",
          version: new_sha,
          previous_version: old_sha,
          requirements: declaration_spans.map { |span| requirement.call(new_sha, span, release_tag: "v1.2.0") },
          previous_requirements: declaration_spans.map { |span| requirement.call(old_sha, span) },
          package_manager: "apm"
        )
      end

      context "when the entry ends its line" do
        let(:manifest_body) { "dependencies:\n  apm:\n    - microsoft/edge-ai##{old_sha}\n" }
        let(:declaration_spans) { ["2:6:2:64"] }

        it "rewrites the SHA and annotates it with the release tag" do
          expect(updated_files.first.content).to eq(
            "dependencies:\n  apm:\n    - microsoft/edge-ai##{new_sha} # v1.2.0\n"
          )
        end
      end

      context "when the entry already carries a comment" do
        let(:manifest_body) { "dependencies:\n  apm:\n    - microsoft/edge-ai##{old_sha}   # v1.0.0\n" }
        let(:declaration_spans) { ["2:6:2:64"] }

        it "replaces the comment with the new release tag" do
          expect(updated_files.first.content).to eq(
            "dependencies:\n  apm:\n    - microsoft/edge-ai##{new_sha} # v1.2.0\n"
          )
        end
      end

      context "when the entry is in a flow sequence" do
        let(:manifest_body) { "dependencies: { apm: [microsoft/edge-ai##{old_sha}] }\n" }
        let(:declaration_spans) { ["0:22:0:80"] }

        it "rewrites the SHA without adding a comment" do
          expect(updated_files.first.content).to eq("dependencies: { apm: [microsoft/edge-ai##{new_sha}] }\n")
        end
      end
    end

    context "when a branch pin moves to a new head commit" do
      let(:old_commit) { "1a" * 20 }
      let(:new_commit) { "2b" * 20 }
      let(:manifest_body) { "dependencies:\n  apm:\n    - microsoft/edge-ai#main\n" }
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "apm.lock.yaml",
          content: <<~YAML
            lockfile_version: '1'
            apm_version: 0.33.0
            dependencies:
            - repo_url: microsoft/edge-ai
              host: github.com
              resolved_commit: #{old_commit}
              resolved_ref: main
              package_type: apm_package
              content_hash: sha256:abc
          YAML
        )
      end
      let(:dependency) do
        requirement = {
          file: "apm.yml",
          requirement: nil,
          groups: [],
          source: { type: "git", url: "https://github.com/microsoft/edge-ai", ref: "main", branch: "main" },
          metadata: {
            declaration_string: "microsoft/edge-ai#main",
            declaration_span: "2:6:2:28",
            lockfile_key: "microsoft/edge-ai"
          }
        }

        Dependabot::Dependency.new(
          name: "microsoft/edge-ai",
          version: new_commit,
          previous_version: old_commit,
          requirements: [requirement],
          previous_requirements: [requirement],
          package_manager: "apm"
        )
      end
      let(:updater) do
        described_class.new(dependency_files: [manifest, lockfile], dependencies: [dependency], credentials: [])
      end

      before do
        allow(Dependabot::Apm::NativeHelpers).to receive(:run_apm_command).with("lock") do
          # APM re-hashes the entry whose stale content_hash was dropped.
          File.write("apm.lock.yaml", "#{File.read('apm.lock.yaml')}  content_hash: sha256:def\n")
          ""
        end
      end

      it "updates only the lockfile, moving the entry to the new commit" do
        expect(updated_files.map(&:name)).to eq(["apm.lock.yaml"])
        expect(updated_files.first.content).to include("resolved_commit: #{new_commit}")
        expect(updated_files.first.content).to include("content_hash: sha256:def")
        expect(updated_files.first.content).not_to include("sha256:abc")
      end
    end

    context "when the manifest quotes the entry" do
      let(:manifest_body) do
        <<~YAML
          dependencies:
            apm:
              - "microsoft/edge-ai#v1.0.0"
        YAML
      end
      let(:declaration_span) { "2:6:2:32" }

      it "still bumps the pinned ref and keeps the quotes" do
        expect(updated_files.first.content).to include("\"microsoft/edge-ai#v1.2.0\"")
      end
    end

    context "when the quoted entry carries trailing whitespace after the ref" do
      let(:manifest_body) do
        <<~YAML
          dependencies:
            apm:
              - "microsoft/edge-ai#v1.0.0 "
        YAML
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "microsoft/edge-ai",
          version: "1.2.0",
          previous_version: "1.0.0",
          requirements: [{
            file: "apm.yml",
            requirement: nil,
            groups: [],
            source: { type: "git", url: "https://github.com/microsoft/edge-ai", ref: "v1.2.0", branch: nil },
            metadata: { declaration_string: "microsoft/edge-ai#v1.0.0 ", declaration_span: "2:6:2:33" }
          }],
          previous_requirements: [{
            file: "apm.yml",
            requirement: nil,
            groups: [],
            source: { type: "git", url: "https://github.com/microsoft/edge-ai", ref: "v1.0.0", branch: nil },
            metadata: { declaration_string: "microsoft/edge-ai#v1.0.0 ", declaration_span: "2:6:2:33" }
          }],
          package_manager: "apm"
        )
      end

      it "bumps the pinned ref while preserving the trailing whitespace" do
        expect(updated_files.first.content).to include("\"microsoft/edge-ai#v1.2.0 \"")
      end
    end

    context "when the manifest uses a flow sequence" do
      let(:manifest_body) do
        <<~YAML
          dependencies: { apm: ["microsoft/edge-ai#v1.0.0"] }
        YAML
      end
      let(:declaration_span) { "0:22:0:48" }

      it "bumps the pinned ref inside the flow sequence" do
        expect(updated_files.first.content)
          .to include("dependencies: { apm: [\"microsoft/edge-ai#v1.2.0\"] }")
      end
    end

    context "when the same text appears elsewhere in the manifest" do
      let(:manifest_body) do
        <<~YAML
          # keep microsoft/edge-ai#v1.0.0 until the audit clears
          dependencies:
            apm:
              - microsoft/edge-ai#v1.0.0
          notes:
            reference: microsoft/edge-ai#v1.0.0
        YAML
      end
      let(:declaration_span) { "3:6:3:30" }

      it "rewrites only the real dependency entry" do
        content = updated_files.first.content
        expect(content).to include("    - microsoft/edge-ai#v1.2.0")
        expect(content).to include("# keep microsoft/edge-ai#v1.0.0 until the audit clears")
        expect(content).to include("reference: microsoft/edge-ai#v1.0.0")
      end
    end

    context "when a duplicated entry shares a line and the bumped ref is longer" do
      let(:manifest_body) do
        <<~YAML
          dependencies: { apm: ["acme/widgets#v1.9.0", "acme/widgets#v1.9.0"] }
        YAML
      end
      let(:dependency) do
        requirement = lambda do |ref, span|
          {
            file: "apm.yml",
            requirement: nil,
            groups: [],
            source: { type: "git", url: "https://github.com/acme/widgets", ref: ref, branch: nil },
            metadata: { declaration_string: "acme/widgets#v1.9.0", declaration_span: span }
          }
        end

        Dependabot::Dependency.new(
          name: "acme/widgets",
          version: "1.10.0",
          previous_version: "1.9.0",
          requirements: [requirement.call("v1.10.0", "0:22:0:43"), requirement.call("v1.10.0", "0:45:0:66")],
          previous_requirements: [requirement.call("v1.9.0", "0:22:0:43"), requirement.call("v1.9.0", "0:45:0:66")],
          package_manager: "apm"
        )
      end

      it "updates both occurrences even though the earlier edit shifts later offsets" do
        expect(updated_files.first.content)
          .to eq(%(dependencies: { apm: ["acme/widgets#v1.10.0", "acme/widgets#v1.10.0"] }\n))
      end
    end

    context "when nothing changed" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "microsoft/edge-ai",
          version: "1.0.0",
          previous_version: "1.0.0",
          requirements: [{
            file: "apm.yml",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/microsoft/edge-ai",
              ref: "v1.0.0",
              branch: nil
            },
            metadata: { declaration_string: "microsoft/edge-ai#v1.0.0" }
          }],
          previous_requirements: [{
            file: "apm.yml",
            requirement: nil,
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/microsoft/edge-ai",
              ref: "v1.0.0",
              branch: nil
            },
            metadata: { declaration_string: "microsoft/edge-ai#v1.0.0" }
          }],
          package_manager: "apm"
        )
      end

      it "raises because no files were changed" do
        expect { updated_files }.to raise_error("No files changed!")
      end
    end
  end
end
