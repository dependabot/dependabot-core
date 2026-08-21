# typed: false
# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "tmpdir"

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nix/file_updater"
require_common_spec "file_updaters/shared_examples_for_file_updaters"

RSpec.describe Dependabot::Nix::FileUpdater do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "nixpkgs",
      version: "new_sha_abc123",
      previous_version: "3030f185ba6a4bf4f18b87f345f104e6a6961f34",
      requirements: [{
        file: "flake.lock",
        requirement: nil,
        source: {
          type: "git",
          url: "https://github.com/NixOS/nixpkgs",
          branch: nil,
          ref: "nixos-unstable"
        },
        groups: []
      }],
      previous_requirements: [{
        file: "flake.lock",
        requirement: nil,
        source: {
          type: "git",
          url: "https://github.com/NixOS/nixpkgs",
          branch: nil,
          ref: "nixos-unstable"
        },
        groups: []
      }],
      package_manager: "nix"
    )
  end
  let(:updater) do
    described_class.new(
      dependency_files: [flake_nix, flake_lock],
      dependencies: [dependency],
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  let(:flake_nix) do
    Dependabot::DependencyFile.new(
      name: "flake.nix",
      content: flake_nix_content
    )
  end

  let(:flake_lock) do
    Dependabot::DependencyFile.new(
      name: "flake.lock",
      content: flake_lock_content
    )
  end

  let(:flake_nix_content) do
    fixture("flake.nix")
  end

  let(:flake_lock_content) do
    fixture("flake.lock")
  end

  def fixture(filename)
    File.read(File.join(__dir__, "fixtures", filename))
  end

  it_behaves_like "a dependency file updater"

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    let(:updated_lock_content) do
      flake_lock_content.gsub(
        "3030f185ba6a4bf4f18b87f345f104e6a6961f34",
        "new_sha_abc123"
      )
    end

    before do
      allow(Dependabot::SharedHelpers)
        .to receive(:in_a_temporary_repo_directory)
        .and_yield
      allow(Dependabot::SharedHelpers)
        .to receive(:run_shell_command)
      allow(File).to receive(:write).and_call_original
      allow(File).to receive(:write).with("flake.nix", anything)
      allow(File).to receive(:write).with("flake.lock", anything)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("flake.lock").and_return(updated_lock_content)
    end

    context "with a branch-tracking input (ref unchanged)" do
      it "returns only the updated flake.lock" do
        expect(updated_files.length).to eq(1)
        expect(updated_files.first.name).to eq("flake.lock")
      end

      it "locks the input to the selected revision" do
        updated_files
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with(
            [
              "nix", "flake", "lock", "--override-input",
              "nixpkgs", "github:NixOS/nixpkgs/new_sha_abc123"
            ],
            fingerprint: "nix flake lock --override-input <input_path> <flake_ref>"
          )
      end

      context "when Nix writes a different revision" do
        let(:updated_lock_content) do
          flake_lock_content.gsub(
            "3030f185ba6a4bf4f18b87f345f104e6a6961f34",
            "unexpected_sha_def456"
          )
        end

        it "reports the requested and generated revisions" do
          expect { updated_files }
            .to raise_error(
              Dependabot::DependencyFileNotResolvable,
              /new_sha_abc123.*unexpected_sha_def456/
            )
        end
      end

      context "when Nix omits the locked revision" do
        let(:updated_lock_content) do
          content = JSON.parse(flake_lock_content)
          content.fetch("nodes").fetch("nixpkgs").fetch("locked").delete("rev")
          JSON.pretty_generate(content)
        end

        it "reports the missing revision" do
          expect { updated_files }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /new_sha_abc123.*nil/)
        end
      end
    end

    context "with a generic Git ref change" do
      let(:flake_nix_content) do
        <<~NIX
          {
            inputs.generic-git.url = "git+https://example.com/myorg/repo.git?ref=v1.0.0&dir=nix";
            outputs = { self, generic-git }: { };
          }
        NIX
      end
      let(:dependency) do
        git_dependency(
          name: "generic-git",
          version: "new_sha_abc123",
          previous_version: "old_sha_abc123",
          url: "https://example.com/myorg/repo.git",
          ref: "v2.0.0",
          previous_ref: "v1.0.0"
        )
      end
      let(:flake_lock_content) do
        git_lock_content(
          name: "generic-git",
          revision: "old_sha_abc123",
          source: {
            "type" => "git",
            "url" => "https://example.com/myorg/repo.git",
            "ref" => "v1.0.0",
            "dir" => "nix"
          }
        )
      end
      let(:updated_lock_content) do
        flake_lock_content.gsub("old_sha_abc123", "new_sha_abc123")
      end

      it "updates flake.nix and uses the new ref for the lock override" do
        expect(updated_files.map(&:name)).to contain_exactly("flake.nix", "flake.lock")
        expect(updated_files.find { |file| file.name == "flake.nix" }.content)
          .to include("ref=v2.0.0&dir=nix")
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with(
            lock_command(
              input_path: "generic-git",
              ref: "git+https://example.com/myorg/repo.git" \
                   "?dir=nix&ref=v2.0.0&rev=new_sha_abc123"
            ),
            fingerprint: "nix flake lock --override-input <input_path> <flake_ref>"
          )
      end
    end

    context "with an input name Nix's CLI can't parse" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "_1password-shell-plugins",
          version: "new_sha_abc123",
          previous_version: "old_sha_abc123",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "git",
              url: "https://github.com/1Password/shell-plugins",
              branch: nil,
              ref: "main"
            },
            groups: []
          }],
          previous_requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "git",
              url: "https://github.com/1Password/shell-plugins",
              branch: nil,
              ref: "main"
            },
            groups: []
          }],
          package_manager: "nix"
        )
      end

      it "includes the invalid input name in the error" do
        expect { updated_files }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /_1password-shell-plugins/)
        expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
      end
    end

    [
      {
        description: "GitHub Enterprise input",
        name: "internal-lib",
        url: "https://github.corp.example.com/myteam/internal-lib",
        source: {
          "type" => "github",
          "owner" => "myteam",
          "repo" => "internal-lib",
          "ref" => "main",
          "host" => "github.corp.example.com",
          "dir" => "nix"
        },
        expected_ref: "github:myteam/internal-lib/new_sha_abc123?dir=nix&host=github.corp.example.com"
      },
      {
        description: "GitLab subgroup input",
        name: "gitlab-dep",
        url: "https://gitlab.com/myorg/subgroup/myrepo",
        source: {
          "type" => "gitlab",
          "owner" => "myorg/subgroup",
          "repo" => "myrepo",
          "ref" => "main"
        },
        expected_ref: "gitlab:myorg%2Fsubgroup/myrepo/new_sha_abc123"
      },
      {
        description: "SourceHut input",
        name: "sourcehut-dep",
        url: "https://git.sr.ht/~user/myrepo",
        source: {
          "type" => "sourcehut",
          "owner" => "~user",
          "repo" => "myrepo",
          "ref" => "main"
        },
        expected_ref: "sourcehut:~user/myrepo/new_sha_abc123"
      },
      {
        description: "generic HTTPS Git input",
        name: "generic-git",
        url: "https://example.com/myorg/repo.git",
        source: {
          "type" => "git",
          "url" => "https://example.com/myorg/repo.git",
          "ref" => "main",
          "dir" => "nix",
          "submodules" => true
        },
        expected_ref: "git+https://example.com/myorg/repo.git" \
                      "?dir=nix&ref=main&rev=new_sha_abc123&submodules=1"
      },
      {
        description: "SCP-style Git input",
        name: "ssh-git",
        url: "git@example.com:myorg/repo.git",
        source: {
          "type" => "git",
          "url" => "git@example.com:myorg/repo.git",
          "ref" => "main"
        },
        expected_ref: "git+ssh://git@example.com/myorg/repo.git?ref=main&rev=new_sha_abc123"
      }
    ].each do |test_case|
      context "with a #{test_case.fetch(:description)}" do
        let(:dependency) do
          git_dependency(
            name: test_case.fetch(:name),
            version: "new_sha_abc123",
            previous_version: "old_sha_abc123",
            url: test_case.fetch(:url),
            ref: "main"
          )
        end
        let(:flake_lock_content) do
          git_lock_content(
            name: test_case.fetch(:name),
            revision: "old_sha_abc123",
            source: test_case.fetch(:source)
          )
        end
        let(:updated_lock_content) do
          flake_lock_content.gsub("old_sha_abc123", "new_sha_abc123")
        end

        it "builds an exact reference without changing the source type" do
          updated_files
          expect(Dependabot::SharedHelpers)
            .to have_received(:run_shell_command)
            .with(
              lock_command(
                input_path: test_case.fetch(:name),
                ref: test_case.fetch(:expected_ref)
              ),
              fingerprint: "nix flake lock --override-input <input_path> <flake_ref>"
            )
        end
      end
    end

    context "with an indirect registry input" do
      let(:flake_nix_content) do
        <<~NIX
          {
            inputs.nixpkgs.url = "nixpkgs/nixos-24.11";
            outputs = { self, nixpkgs }: { };
          }
        NIX
      end
      let(:dependency) do
        git_dependency(
          name: "nixpkgs",
          version: "new_sha_abc123",
          previous_version: "old_sha_abc123",
          url: "https://github.com/NixOS/nixpkgs",
          ref: "nixos-24.11"
        )
      end
      let(:flake_lock_content) do
        JSON.pretty_generate(
          "nodes" => {
            "nixpkgs" => {
              "locked" => {
                "lastModified" => 1_700_000_000,
                "narHash" => "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                "owner" => "NixOS",
                "repo" => "nixpkgs",
                "rev" => "old_sha_abc123",
                "type" => "github"
              },
              "original" => {
                "id" => "nixpkgs",
                "ref" => "nixos-24.11",
                "type" => "indirect"
              }
            },
            "root" => {
              "inputs" => {
                "nixpkgs" => "nixpkgs"
              }
            }
          },
          "root" => "root",
          "version" => 7
        )
      end
      let(:updated_lock_content) do
        flake_lock_content.gsub("old_sha_abc123", "new_sha_abc123")
      end

      it "uses the resolved source for the lock override" do
        expect(updated_files.map(&:name)).to eq(["flake.lock"])
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with(
            lock_command(
              input_path: "nixpkgs",
              ref: "github:NixOS/nixpkgs/new_sha_abc123"
            ),
            fingerprint: "nix flake lock --override-input <input_path> <flake_ref>"
          )
      end
    end

    context "with a root input that follows a nested input" do
      let(:dependency) do
        git_dependency(
          name: "alias",
          version: "new_sha_abc123",
          previous_version: "old_sha_abc123",
          url: "https://github.com/example/target",
          ref: "main"
        )
      end
      let(:flake_lock_content) do
        JSON.pretty_generate(
          "nodes" => {
            "parent-node" => {
              "inputs" => {
                "nested" => "target-node"
              },
              "locked" => {
                "rev" => "parent-revision"
              },
              "original" => {
                "type" => "github",
                "owner" => "example",
                "repo" => "parent"
              }
            },
            "target-node" => {
              "locked" => {
                "rev" => "old_sha_abc123"
              },
              "original" => {
                "type" => "github",
                "owner" => "example",
                "repo" => "target",
                "ref" => "main"
              }
            },
            "root" => {
              "inputs" => {
                "alias" => %w(parent nested),
                "parent" => "parent-node"
              }
            }
          },
          "root" => "root",
          "version" => 7
        )
      end
      let(:updated_lock_content) do
        flake_lock_content.gsub("old_sha_abc123", "new_sha_abc123")
      end

      it "uses the path followed by the root input" do
        expect(JSON.parse(updated_files.fetch(0).content).dig("nodes", "root", "inputs", "alias"))
          .to eq(%w(parent nested))
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with(
            lock_command(
              input_path: "parent/nested",
              ref: "github:example/target/new_sha_abc123"
            ),
            fingerprint: "nix flake lock --override-input <input_path> <flake_ref>"
          )
      end
    end

    context "with unsupported lockfile source metadata" do
      let(:dependency) do
        git_dependency(
          name: "unsupported",
          version: "new_sha_abc123",
          previous_version: "old_sha_abc123",
          url: "https://example.com/repo",
          ref: "main"
        )
      end
      let(:flake_lock_content) do
        git_lock_content(
          name: "unsupported",
          revision: "old_sha_abc123",
          source: {
            "type" => "mercurial",
            "url" => "https://example.com/repo",
            "ref" => "main"
          }
        )
      end

      it "rejects the source before running Nix" do
        expect { updated_files }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /source type "mercurial" is not supported/)
        expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
      end
    end

    context "with a tag-pinned input (ref changed)" do
      let(:flake_nix_content) { fixture("flake_with_tag.nix") }
      let(:flake_lock_content) do
        git_lock_content(
          name: "devenv",
          revision: "old_sha_abc123",
          source: {
            "type" => "github",
            "owner" => "cachix",
            "repo" => "devenv",
            "ref" => "v0.5"
          }
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "devenv",
          version: "new_sha_def456",
          previous_version: "old_sha_abc123",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "git",
              url: "https://github.com/cachix/devenv",
              branch: nil,
              ref: "v0.6.2"
            },
            groups: []
          }],
          previous_requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "git",
              url: "https://github.com/cachix/devenv",
              branch: nil,
              ref: "v0.5"
            },
            groups: []
          }],
          package_manager: "nix"
        )
      end

      let(:updated_lock_content) do
        flake_lock_content.gsub("old_sha_abc123", "new_sha_def456")
      end

      it "returns both flake.nix and flake.lock" do
        expect(updated_files.length).to eq(2)
        expect(updated_files.map(&:name)).to contain_exactly("flake.nix", "flake.lock")
      end

      it "rewrites the tag in flake.nix" do
        nix_file = updated_files.find { |f| f.name == "flake.nix" }
        expect(nix_file.content).to include('"github:cachix/devenv/v0.6.2"')
        expect(nix_file.content).not_to include('"github:cachix/devenv/v0.5"')
      end

      it "preserves other inputs in flake.nix" do
        nix_file = updated_files.find { |f| f.name == "flake.nix" }
        expect(nix_file.content).to include('"github:NixOS/nixpkgs/nixos-unstable"')
        expect(nix_file.content).to include('"github:numtide/flake-utils"')
      end

      it "writes the updated flake.nix before running nix" do
        updated_files
        expect(File).to have_received(:write)
          .with("flake.nix", a_string_including("github:cachix/devenv/v0.6.2"))
      end

      it "locks the input to the selected tag commit" do
        updated_files
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with(
            lock_command(
              input_path: "devenv",
              ref: "github:cachix/devenv/new_sha_def456"
            ),
            fingerprint: "nix flake lock --override-input <input_path> <flake_ref>"
          )
      end
    end

    context "with a versioned branch input (ref changed)" do
      let(:flake_nix_content) { fixture("flake_with_versioned_branch.nix") }
      let(:flake_lock_content) do
        git_lock_content(
          name: "nixpkgs",
          revision: "old_sha_abc123",
          source: {
            "type" => "github",
            "owner" => "NixOS",
            "repo" => "nixpkgs",
            "ref" => "nixos-24.11"
          }
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "new_sha_def456",
          previous_version: "old_sha_abc123",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "git",
              url: "https://github.com/NixOS/nixpkgs",
              branch: nil,
              ref: "nixos-25.05"
            },
            groups: []
          }],
          previous_requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "git",
              url: "https://github.com/NixOS/nixpkgs",
              branch: nil,
              ref: "nixos-24.11"
            },
            groups: []
          }],
          package_manager: "nix"
        )
      end

      let(:updated_lock_content) do
        flake_lock_content.gsub("old_sha_abc123", "new_sha_def456")
      end

      it "returns both flake.nix and flake.lock" do
        expect(updated_files.length).to eq(2)
        expect(updated_files.map(&:name)).to contain_exactly("flake.nix", "flake.lock")
      end

      it "rewrites the branch in flake.nix" do
        nix_file = updated_files.find { |f| f.name == "flake.nix" }
        expect(nix_file.content).to include('"github:NixOS/nixpkgs/nixos-25.05"')
        expect(nix_file.content).not_to include("nixos-24.11")
      end

      it "locks the input to the selected branch commit" do
        updated_files
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with(
            lock_command(
              input_path: "nixpkgs",
              ref: "github:NixOS/nixpkgs/new_sha_def456"
            ),
            fingerprint: "nix flake lock --override-input <input_path> <flake_ref>"
          )
      end
    end

    context "with a NixOS channel tarball input (channel bumped)" do
      let(:flake_nix_content) do
        <<~NIX
          {
            inputs = {
              nixpkgs.url = "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz";
            };
            outputs = { self, nixpkgs }: { };
          }
        NIX
      end
      let(:flake_lock_content) do
        tarball_lock_content(
          revision: "old_rev_aaa",
          url: "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz"
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "new_rev_bbb",
          previous_version: "old_rev_aaa",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "tarball",
              url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz",
              branch: nil,
              ref: "nixos-26.05"
            },
            groups: []
          }],
          previous_requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "tarball",
              url: "https://channels.nixos.org/nixos-25.05/nixexprs.tar.xz",
              branch: nil,
              ref: "nixos-25.05"
            },
            groups: []
          }],
          package_manager: "nix"
        )
      end

      let(:updated_lock_content) do
        flake_lock_content.gsub("old_rev_aaa", "new_rev_bbb")
      end

      it "returns both flake.nix and flake.lock" do
        expect(updated_files.length).to eq(2)
        expect(updated_files.map(&:name)).to contain_exactly("flake.nix", "flake.lock")
      end

      it "rewrites the channel in flake.nix" do
        nix_file = updated_files.find { |f| f.name == "flake.nix" }
        expect(nix_file.content).to include('"https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz"')
        expect(nix_file.content).not_to include("nixos-25.05")
      end

      it "runs nix flake update for the input" do
        updated_files
        expect(Dependabot::SharedHelpers)
          .to have_received(:run_shell_command)
          .with(
            %w(nix flake update nixpkgs),
            fingerprint: "nix flake update <input_name>"
          )
      end
    end

    context "with a NixOS channel tarball input (lock refresh only)" do
      let(:flake_nix_content) do
        <<~NIX
          {
            inputs = {
              nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";
            };
            outputs = { self, nixpkgs }: { };
          }
        NIX
      end
      let(:flake_lock_content) do
        tarball_lock_content(
          revision: "old_rev_aaa",
          url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz"
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nixpkgs",
          version: "new_rev_bbb",
          previous_version: "old_rev_aaa",
          requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "tarball",
              url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz",
              branch: nil,
              ref: "nixos-26.05"
            },
            groups: []
          }],
          previous_requirements: [{
            file: "flake.lock",
            requirement: nil,
            source: {
              type: "tarball",
              url: "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz",
              branch: nil,
              ref: "nixos-26.05"
            },
            groups: []
          }],
          package_manager: "nix"
        )
      end

      let(:updated_lock_content) do
        flake_lock_content.gsub("old_rev_aaa", "new_rev_bbb")
      end

      it "returns only the updated flake.lock" do
        expect(updated_files.length).to eq(1)
        expect(updated_files.first.name).to eq("flake.lock")
      end
    end
  end

  describe "with the real Nix command" do
    let(:input_repo) { Dir.mktmpdir("dependabot-nix-input") }
    let(:flake_project) { Dir.mktmpdir("dependabot-nix-project") }

    after do
      FileUtils.rm_rf(input_repo)
      FileUtils.rm_rf(flake_project)
    end

    it "locks the selected commit, not the current branch tip" do
      initialize_git_flake(input_repo)
      existing_revision = commit_input_version(input_repo, "existing")
      selected_revision = commit_input_version(input_repo, "selected")
      live_revision = commit_input_version(input_repo, "live")

      run_command("git", "reset", "--hard", existing_revision, chdir: input_repo)
      write_flake_project(flake_project, input_repo)
      run_command("nix", "flake", "lock", chdir: flake_project)
      original_lock_content = File.read(File.join(flake_project, "flake.lock"))
      run_command("git", "reset", "--hard", live_revision, chdir: input_repo)

      dependency = Dependabot::Dependency.new(
        name: "local_input",
        version: selected_revision,
        previous_version: existing_revision,
        requirements: [{
          file: "flake.lock",
          requirement: nil,
          source: {
            type: "git",
            url: "file://#{input_repo}",
            branch: nil,
            ref: "main"
          },
          groups: []
        }],
        previous_requirements: [{
          file: "flake.lock",
          requirement: nil,
          source: {
            type: "git",
            url: "file://#{input_repo}",
            branch: nil,
            ref: "main"
          },
          groups: []
        }],
        package_manager: "nix"
      )

      updater = described_class.new(
        dependency_files: [
          Dependabot::DependencyFile.new(
            name: "flake.nix",
            content: File.read(File.join(flake_project, "flake.nix"))
          ),
          Dependabot::DependencyFile.new(
            name: "flake.lock",
            content: original_lock_content
          )
        ],
        dependencies: [dependency],
        credentials: []
      )

      updated_lock = JSON.parse(updater.updated_dependency_files.fetch(0).content)
      node_name = updated_lock.fetch("nodes").fetch("root").fetch("inputs").fetch("local_input")
      input_node = updated_lock.fetch("nodes").fetch(node_name)

      expect(input_node.fetch("locked").fetch("rev")).to eq(selected_revision)
      expect(input_node.fetch("locked").fetch("rev")).not_to eq(live_revision)
      expect(input_node.fetch("original").fetch("ref")).to eq("main")
    end
  end

  def git_lock_content(name:, revision:, source:)
    JSON.pretty_generate(
      "nodes" => {
        name => {
          "locked" => source.merge(
            "lastModified" => 1_700_000_000,
            "narHash" => "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "rev" => revision
          ).except("ref"),
          "original" => source
        },
        "root" => {
          "inputs" => {
            name => name
          }
        }
      },
      "root" => "root",
      "version" => 7
    )
  end

  def git_dependency(name:, version:, previous_version:, url:, ref:, previous_ref: ref)
    Dependabot::Dependency.new(
      name: name,
      version: version,
      previous_version: previous_version,
      requirements: [{
        file: "flake.lock",
        requirement: nil,
        source: {
          type: "git",
          url: url,
          branch: nil,
          ref: ref
        },
        groups: []
      }],
      previous_requirements: [{
        file: "flake.lock",
        requirement: nil,
        source: {
          type: "git",
          url: url,
          branch: nil,
          ref: previous_ref
        },
        groups: []
      }],
      package_manager: "nix"
    )
  end

  def lock_command(input_path:, ref:)
    ["nix", "flake", "lock", "--override-input", input_path, ref]
  end

  def tarball_lock_content(revision:, url:)
    JSON.pretty_generate(
      "nodes" => {
        "nixpkgs" => {
          "locked" => {
            "lastModified" => 1_700_000_000,
            "narHash" => "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "rev" => revision,
            "type" => "tarball",
            "url" => "https://releases.nixos.org/#{revision}/nixexprs.tar.xz"
          },
          "original" => {
            "type" => "tarball",
            "url" => url
          }
        },
        "root" => {
          "inputs" => {
            "nixpkgs" => "nixpkgs"
          }
        }
      },
      "root" => "root",
      "version" => 7
    )
  end

  def initialize_git_flake(path)
    run_command("git", "init", "--initial-branch", "main", chdir: path)
    run_command("git", "config", "user.email", "dependabot@example.com", chdir: path)
    run_command("git", "config", "user.name", "Dependabot Test", chdir: path)
    File.write(
      File.join(path, "flake.nix"),
      "{ outputs = { self }: { }; }\n"
    )
  end

  def commit_input_version(path, version)
    File.write(File.join(path, "version.txt"), "#{version}\n")
    run_command("git", "add", ".", chdir: path)
    run_command("git", "commit", "-m", version, chdir: path)
    run_command("git", "rev-parse", "HEAD", chdir: path).strip
  end

  def write_flake_project(path, input_repo)
    File.write(
      File.join(path, "flake.nix"),
      <<~NIX
        {
          inputs.local_input.url = "git+file://#{input_repo}?ref=main";
          outputs = { self, local_input }: { };
        }
      NIX
    )
  end

  def run_command(*command, chdir:)
    output, status = Open3.capture2e(*command, chdir: chdir)
    raise "Command failed: #{command.join(' ')}\n#{output}" unless status.success?

    output
  end
end
