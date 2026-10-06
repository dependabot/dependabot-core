# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/pnpm_workspace_config"

RSpec.describe Dependabot::NpmAndYarn::PnpmWorkspaceConfig do
  subject(:lockfile_per_project) { described_class.lockfile_per_project?(files) }

  def workspace(content)
    Dependabot::DependencyFile.new(name: "pnpm-workspace.yaml", content: content)
  end

  def npmrc(content)
    Dependabot::DependencyFile.new(name: ".npmrc", content: content)
  end

  # pnpm only takes the setting from `.npmrc` below 11, and only where the
  # repository says which pnpm runs, so these cases need a pin to be read at all.
  def manifest(pin = "pnpm@10.34.5", name: "package.json", directory: "/")
    Dependabot::DependencyFile.new(
      name: name,
      content: JSON.dump({ "packageManager" => pin }.compact),
      directory: directory
    )
  end

  context "when nothing in the repository mentions the setting" do
    let(:files) { [workspace("packages:\n  - ./packages/*\n"), npmrc("registry=https://example.com\n")] }

    it { is_expected.to be(false) }
  end

  context "when no files are given at all" do
    let(:files) { [] }

    it { is_expected.to be(false) }
  end

  describe "pnpm-workspace.yaml" do
    context "when it disables the shared lockfile" do
      let(:files) { [workspace("packages:\n  - ./packages/*\n\nsharedWorkspaceLockfile: false\n")] }

      it { is_expected.to be(true) }
    end

    context "when it enables the shared lockfile" do
      let(:files) { [workspace("sharedWorkspaceLockfile: true\n")] }

      it { is_expected.to be(false) }
    end

    context "when the mapping is written in flow style" do
      let(:files) { [workspace("{ packages: ['packages/*'], sharedWorkspaceLockfile: false }\n")] }

      it { is_expected.to be(true) }
    end

    context "when the value is quoted" do
      let(:files) { [workspace("sharedWorkspaceLockfile: 'false'\n")] }

      it "reads it as the string pnpm reads, not as false" do
        expect(lockfile_per_project).to be(false)
      end
    end

    context "when the value is double-quoted" do
      let(:files) { [workspace('sharedWorkspaceLockfile: "false"' + "\n")] }

      it { is_expected.to be(false) }
    end

    context "when the value is a YAML 1.1 boolean pnpm does not resolve" do
      %w(no off).each do |spelling|
        context "with #{spelling}" do
          let(:files) { [workspace("sharedWorkspaceLockfile: #{spelling}\n")] }

          it { is_expected.to be(false) }
        end
      end
    end

    context "when the value is capitalised" do
      let(:files) { [workspace("sharedWorkspaceLockfile: FALSE\n")] }

      it { is_expected.to be(true) }
    end

    context "when a comment follows the value" do
      let(:files) { [workspace("sharedWorkspaceLockfile: false # one lockfile each\n")] }

      it { is_expected.to be(true) }
    end

    # js-yaml resolves an alias to whatever the anchor held, so the value is a
    # bare boolean as far as pnpm is concerned.
    context "when the value is a YAML alias for a bare false" do
      let(:files) { [workspace("disabled: &disabled false\nsharedWorkspaceLockfile: *disabled\n")] }

      it { is_expected.to be(true) }
    end

    context "when the value is a YAML alias for a bare true" do
      let(:files) { [workspace("enabled: &enabled true\nsharedWorkspaceLockfile: *enabled\n")] }

      it { is_expected.to be(false) }
    end

    context "when the value is a YAML alias for a quoted string" do
      let(:files) { [workspace("disabled: &disabled 'false'\nsharedWorkspaceLockfile: *disabled\n")] }

      it "reads the string pnpm reads, not a boolean" do
        expect(lockfile_per_project).to be(false)
      end
    end

    context "when the value aliases an anchor that does not exist" do
      let(:files) { [workspace("sharedWorkspaceLockfile: *missing\n")] }

      it "reads as unset rather than raising" do
        expect { lockfile_per_project }.not_to raise_error
        expect(lockfile_per_project).to be(false)
      end
    end

    context "when it uses the kebab-case spelling pnpm ignores there" do
      let(:files) { [workspace("shared-workspace-lockfile: false\n")] }

      it { is_expected.to be(false) }
    end

    context "when the file cannot be parsed" do
      let(:files) { [workspace("packages: [\n")] }

      it { is_expected.to be(false) }
    end

    context "when the file holds no document at all" do
      ["", "   \n", "# nothing but a comment\n"].each do |content|
        context "with #{content.inspect}" do
          let(:files) { [workspace(content)] }

          it "reads as unset rather than raising" do
            expect { lockfile_per_project }.not_to raise_error
            expect(lockfile_per_project).to be(false)
          end
        end
      end
    end

    context "when the file is not a mapping" do
      let(:files) { [workspace("- just\n- a list\n")] }

      it { is_expected.to be(false) }
    end
  end

  describe ".npmrc" do
    context "when it disables the shared lockfile" do
      let(:files) { [manifest, npmrc("shared-workspace-lockfile=false\n")] }

      it { is_expected.to be(true) }
    end

    context "when it enables the shared lockfile" do
      let(:files) { [manifest, npmrc("shared-workspace-lockfile=true\n")] }

      it { is_expected.to be(false) }
    end

    context "when a later line overrides an earlier one" do
      let(:files) { [manifest, npmrc("shared-workspace-lockfile=false\nshared-workspace-lockfile=true\n")] }

      it { is_expected.to be(false) }
    end

    context "when a semicolon comment follows the value" do
      let(:files) { [manifest, npmrc("shared-workspace-lockfile=false ; one each\n")] }

      it { is_expected.to be(true) }
    end

    context "when it uses the camelCase spelling pnpm ignores there" do
      let(:files) { [manifest, npmrc("sharedWorkspaceLockfile=false\n")] }

      it { is_expected.to be(false) }
    end
  end

  describe "precedence between the two files" do
    context "when pnpm-workspace.yaml enables it and .npmrc disables it" do
      let(:files) do
        [manifest, workspace("sharedWorkspaceLockfile: true\n"), npmrc("shared-workspace-lockfile=false\n")]
      end

      it "follows pnpm-workspace.yaml, as pnpm does" do
        expect(lockfile_per_project).to be(false)
      end
    end

    context "when pnpm-workspace.yaml disables it and .npmrc enables it" do
      let(:files) do
        [manifest, workspace("sharedWorkspaceLockfile: false\n"), npmrc("shared-workspace-lockfile=true\n")]
      end

      it "follows pnpm-workspace.yaml, as pnpm does" do
        expect(lockfile_per_project).to be(true)
      end
    end

    context "when only .npmrc states it" do
      let(:files) { [manifest, workspace("packages:\n  - ./packages/*\n"), npmrc("shared-workspace-lockfile=false\n")] }

      it { is_expected.to be(true) }
    end

    # A key pnpm reads as a string is still a key it read: it leaves the shared
    # lockfile on AND stops `.npmrc` being consulted. Measured on pnpm 10.34.5 —
    # dropping the key from this pair is what produces a lockfile per project.
    context "when pnpm-workspace.yaml states a non-boolean and .npmrc disables it" do
      let(:files) do
        [manifest, workspace("sharedWorkspaceLockfile: 'false'\n"), npmrc("shared-workspace-lockfile=false\n")]
      end

      it "treats the key as stated, so .npmrc does not decide it" do
        expect(lockfile_per_project).to be(false)
      end
    end

    context "when pnpm-workspace.yaml holds the key with no value at all" do
      let(:files) do
        [manifest, workspace("sharedWorkspaceLockfile:\n"), npmrc("shared-workspace-lockfile=false\n")]
      end

      it "still counts as stated" do
        expect(lockfile_per_project).to be(false)
      end
    end
  end

  # `.npmrc` only states this setting for a pnpm that still reads it, and only a
  # `packageManager` pin says which pnpm that is. Asked of the files alone, so no
  # caller can answer it differently.
  describe "whether pnpm still reads .npmrc" do
    let(:disabled_in_npmrc) { npmrc("shared-workspace-lockfile=false\n") }

    context "when the repository pins pnpm 10" do
      let(:files) { [manifest("pnpm@10.34.5"), disabled_in_npmrc] }

      it { is_expected.to be(true) }
    end

    context "when the repository pins pnpm 11" do
      let(:files) { [manifest("pnpm@11.2.0"), disabled_in_npmrc] }

      it "ignores a file that pnpm no longer reads" do
        expect(lockfile_per_project).to be(false)
      end
    end

    context "when the repository pins no version at all" do
      let(:files) { [manifest(nil), disabled_in_npmrc] }

      it "leaves it alone rather than guessing which pnpm runs" do
        expect(lockfile_per_project).to be(false)
      end
    end

    context "when there is no manifest to read the pin from" do
      let(:files) { [disabled_in_npmrc] }

      it { is_expected.to be(false) }
    end

    context "when the manifest cannot be parsed" do
      let(:files) do
        [Dependabot::DependencyFile.new(name: "package.json", content: "{"), disabled_in_npmrc]
      end

      it "reads as unpinned rather than raising" do
        expect { lockfile_per_project }.not_to raise_error
        expect(lockfile_per_project).to be(false)
      end
    end

    context "when pnpm-workspace.yaml states it on pnpm 11" do
      let(:files) { [manifest("pnpm@11.2.0"), workspace("sharedWorkspaceLockfile: false\n")] }

      it "still reads the file pnpm honours at every version" do
        expect(lockfile_per_project).to be(true)
      end
    end
  end

  context "when only a nested project's .npmrc disables it" do
    let(:files) do
      [Dependabot::DependencyFile.new(
        name: "packages/package1/.npmrc",
        content: "shared-workspace-lockfile=false\n"
      )]
    end

    it "ignores it, since pnpm takes a workspace-level setting from the root" do
      expect(lockfile_per_project).to be(false)
    end
  end

  # Names are relative to the job directory, so when the job targets a member the
  # workspace files arrive as `../...` while the member's own files keep the bare
  # name. Only the repository path tells those apart.
  describe "when the job targets a workspace member" do
    let(:job_dir) { "/packages/app" }
    let(:workspace_above) { at("../pnpm-workspace.yaml", "packages:\n  - '*'\n") }
    let(:manifest_above) { at("../package.json", JSON.dump("packageManager" => "pnpm@10.34.5")) }

    def at(name, content)
      Dependabot::DependencyFile.new(name: name, content: content, directory: job_dir)
    end

    context "when the workspace-root .npmrc disables it" do
      let(:files) { [manifest_above, workspace_above, at("../.npmrc", "shared-workspace-lockfile=false\n")] }

      it "reads it, since that is where the workspace root is" do
        expect(lockfile_per_project).to be(true)
      end
    end

    context "when only the member's own .npmrc disables it" do
      let(:files) { [workspace_above, at(".npmrc", "shared-workspace-lockfile=false\n")] }

      it "ignores it, since the root is the directory above" do
        expect(lockfile_per_project).to be(false)
      end
    end

    context "when the member's own .npmrc contradicts the root one" do
      let(:files) do
        [
          manifest_above,
          workspace_above,
          at("../.npmrc", "shared-workspace-lockfile=false\n"),
          at(".npmrc", "shared-workspace-lockfile=true\n")
        ]
      end

      it "follows the workspace root" do
        expect(lockfile_per_project).to be(true)
      end
    end

    context "when the workspace file above states it directly" do
      let(:files) { [at("../pnpm-workspace.yaml", "sharedWorkspaceLockfile: false\n")] }

      it { is_expected.to be(true) }
    end

    context "when the workspace root is two levels up" do
      let(:job_dir) { "/apps/web/app" }
      let(:files) do
        [
          at("../../package.json", JSON.dump("packageManager" => "pnpm@10.34.5")),
          at("../../pnpm-workspace.yaml", "packages:\n  - '*'\n"),
          at("../../.npmrc", "shared-workspace-lockfile=false\n")
        ]
      end

      it { is_expected.to be(true) }
    end
  end

  context "when a nested .npmrc contradicts the root one" do
    let(:files) do
      [
        manifest,
        npmrc("shared-workspace-lockfile=false\n"),
        Dependabot::DependencyFile.new(
          name: "packages/package1/.npmrc",
          content: "shared-workspace-lockfile=true\n"
        )
      ]
    end

    it "follows the root, whatever order the files arrive in" do
      expect(lockfile_per_project).to be(true)
    end
  end
end
