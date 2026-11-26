# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/credential"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/hex/update_checker/version_resolver"
require "tmpdir"

RSpec.describe Dependabot::Hex::UpdateChecker::VersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      prepared_dependency_files: prepared_files,
      credentials: credentials
    )
  end

  let(:mix_attempts) { [] }
  let(:credentials) do
    [
      Dependabot::Credential.new(
        {
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      )
    ]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: dependency_requirements,
      package_manager: "hex"
    )
  end

  let(:dependency_name) { "plug" }
  let(:version) { "1.3.0" }
  let(:dependency_requirements) do
    [{ file: "mix.exs", requirement: "~> 1.3.0", groups: [], source: nil }]
  end

  let(:prepared_files) { [sanitized_mixfile, lockfile] }
  let(:mixfile) do
    Dependabot::DependencyFile.new(
      name: "mix.exs",
      content: mixfile_fixture_body
    )
  end
  let(:sanitized_mixfile) do
    sanitized_content =
      Dependabot::Hex::FileUpdater::MixfileSanitizer
      .new(mixfile_content: mixfile_fixture_body)
      .sanitized_content
    Dependabot::DependencyFile.new(
      name: "mix.exs",
      content: sanitized_content
    )
  end
  let(:mixfile_fixture_body) { fixture("mixfiles", mixfile_fixture_name) }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "mix.lock",
      content: fixture("lockfiles", lockfile_fixture_name)
    )
  end

  let(:mixfile_fixture_name) { "minor_version" }
  let(:lockfile_fixture_name) { "minor_version" }

  # Prepare the mixfile in the same way the FilePreparer would
  before { mixfile_fixture_body.gsub!("~> 1.3.0", ">= 1.3.0") }

  shared_context "with local nested Git dependencies" do
    let(:git_fixture_mixfile) do
      lambda do |app, dependencies|
        module_name = app.to_s.split("_").map(&:capitalize).join
        dependency_lines = dependencies.map { |dependency| "      #{dependency}" }.join(",\n")

        <<~ELIXIR
          defmodule #{module_name}.MixProject do
            use Mix.Project

            def project do
              [
                app: :#{app},
                version: "0.1.0",
                deps: [
          #{dependency_lines}
                ]
              ]
            end
          end
        ELIXIR
      end
    end
    let(:initialize_git_repository) do
      lambda do |path|
        Dependabot::SharedHelpers.run_shell_command(
          ["git", "-C", path, "init", "--quiet", "--initial-branch=main"]
        )
      end
    end
    let(:commit_git_repository) do
      lambda do |path, message|
        Dependabot::SharedHelpers.run_shell_command(["git", "-C", path, "add", "."])
        Dependabot::SharedHelpers.run_shell_command(
          [
            "git", "-C", path,
            "-c", "user.name=Dependabot",
            "-c", "user.email=support@dependabot.com",
            "commit", "--quiet", "-m", message
          ]
        )
        Dependabot::SharedHelpers.run_shell_command(["git", "-C", path, "rev-parse", "HEAD"]).strip
      end
    end

    let(:constraint_git_repo) { Dir.mktmpdir("dependabot-hex-constraint-git") }
    let(:constraint_git_url) { "file://#{constraint_git_repo}" }
    let(:constraint_git_revision) do
      File.write(
        File.join(constraint_git_repo, "mix.exs"),
        git_fixture_mixfile.call(:constraint_git, ['{:poison, "< 3.0.0"}'])
      )
      initialize_git_repository.call(constraint_git_repo)
      commit_git_repository.call(constraint_git_repo, "Constrain poison")
    end
    let(:constraint_git_head_revision) do
      constraint_git_revision
      File.write(File.join(constraint_git_repo, "README.md"), "new source revision\n")
      commit_git_repository.call(constraint_git_repo, "Advance constraint source")
    end
    let(:outer_git_repo) { Dir.mktmpdir("dependabot-hex-outer-git") }
    let(:outer_git_url) { "file://#{outer_git_repo}" }
    let(:outer_git_locked_revision) do
      File.write(
        File.join(outer_git_repo, "mix.exs"),
        git_fixture_mixfile.call(
          :outer_git,
          [%({:constraint_git, git: "#{constraint_git_url}", ref: "#{constraint_git_revision}"})]
        )
      )
      initialize_git_repository.call(outer_git_repo)
      commit_git_repository.call(outer_git_repo, "Add nested Git dependency")
    end
    let(:outer_git_head_revision) do
      outer_git_locked_revision
      File.write(File.join(outer_git_repo, "README.md"), "candidate\n")
      commit_git_repository.call(outer_git_repo, "Advance target")
    end

    after do
      FileUtils.remove_entry(constraint_git_repo)
      FileUtils.remove_entry(outer_git_repo)
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    it "returns a non-normalized version, following semver" do
      expect(latest_resolvable_version.segments.count).to eq(3)
    end

    it "respects the resolvability of the mix.exs" do
      expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
      expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
    end

    context "when an unchanged Git dependency constrains the target" do
      include_context "with local nested Git dependencies"
      let(:dependency_name) { "poison" }
      let(:version) { "2.2.0" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: ">= 2.2.0", groups: [], source: nil }]
      end
      let(:mixfile_fixture_body) do
        mixfile_for(
          :dependabot_test,
          [
            '{:plug, "1.2.0"}',
            '{:poison, ">= 2.2.0"}',
            %({:constraint_git, git: "#{constraint_git_url}", ref: "#{constraint_git_revision}"})
          ]
        )
      end
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "mix.lock",
          content: git_source_lockfile(
            "\"constraint_git\": {:git, \"#{constraint_git_url}\", \"#{constraint_git_revision}\", " \
            "[ref: \"#{constraint_git_revision}\"]}"
          )
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      end

      it "includes the Git dependency's child requirements" do
        expect(latest_resolvable_version).to be < Gem::Version.new("3.0.0")
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including("mix", "run", end_with("/fetch_git_dependencies.exs"), "--", "poison"),
          hash_including(
            env: hash_including("HEX_HOME" => a_string_matching(%r{/dependabot-hex-home})),
            fingerprint: "mix run fetch_git_dependencies.exs <dependency_name>",
            timeout: 120
          )
        )
      end

      context "when the Git dependency is scoped to another environment" do
        before do
          mixfile_fixture_body.sub!(
            %(ref: "#{constraint_git_revision}"),
            %(ref: "#{constraint_git_revision}", only: :test)
          )
        end

        it "includes its child requirements" do
          expect(latest_resolvable_version).to be < Gem::Version.new("3.0.0")
        end
      end

      context "when the locked target checksum is invalid" do
        let(:dependency_name) { "plug" }
        let(:version) { "1.2.0" }
        let(:dependency_requirements) do
          [{ file: "mix.exs", requirement: ">= 1.2.0", groups: [], source: nil }]
        end
        let(:lockfile) do
          Dependabot::DependencyFile.new(
            name: "mix.lock",
            content: git_source_lockfile(
              "\"constraint_git\": {:git, \"#{constraint_git_url}\", \"#{constraint_git_revision}\", " \
              "[ref: \"#{constraint_git_revision}\"]}"
            ).sub(
              "496bef96634a49d7803ab2671482f0c5ce9ce0b7b9bc25bc0ae8e09859dd2004",
              "0" * 64
            )
          )
        end

        before { mixfile_fixture_body.sub!('{:plug, "1.2.0"}', '{:plug, ">= 1.2.0"}') }

        it "bootstraps the Git dependency before replacing the target lock" do
          expect(latest_resolvable_version).to be > Gem::Version.new("1.2.0")
        end
      end
    end

    context "when an unchanged Git dependency has a locked Git child" do
      include_context "with local nested Git dependencies"
      let(:dependency_name) { "poison" }
      let(:version) { "2.2.0" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: ">= 2.2.0", groups: [], source: nil }]
      end
      let(:mixfile_fixture_body) do
        mixfile_for(
          :dependabot_test,
          [
            '{:plug, "1.2.0"}',
            '{:poison, ">= 2.2.0"}',
            %({:outer_git, git: "#{outer_git_url}", ref: "#{outer_git_locked_revision}"})
          ]
        )
      end
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "mix.lock",
          content: git_source_lockfile(
            "\"outer_git\": {:git, \"#{outer_git_url}\", \"#{outer_git_locked_revision}\", " \
            "[ref: \"#{outer_git_locked_revision}\"]}",
            "\"constraint_git\": {:git, \"#{constraint_git_url}\", \"#{constraint_git_revision}\", " \
            "[ref: \"#{constraint_git_revision}\"]}"
          )
        )
      end

      it "recursively fetches both Git dependencies before updating" do
        expect(latest_resolvable_version).to be < Gem::Version.new("3.0.0")
      end
    end

    context "when the target Git dependency has a locked Git child" do
      include_context "with local nested Git dependencies"
      let(:dependency_name) { "outer_git" }
      let(:version) { outer_git_locked_revision }
      let(:dependency_requirements) do
        [
          {
            file: "mix.exs",
            requirement: nil,
            groups: [],
            source: { type: "git", url: outer_git_url, branch: "main", ref: nil }
          }
        ]
      end
      let(:constraint_checkouts_seen) { [] }
      let(:mixfile_fixture_body) do
        mixfile_for(
          :dependabot_test,
          [
            '{:poison, ">= 2.2.0"}',
            %({:outer_git, git: "#{outer_git_url}", branch: "main"})
          ]
        )
      end
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "mix.lock",
          content: git_source_lockfile(
            %("outer_git": {:git, "#{outer_git_url}", "#{outer_git_locked_revision}", [branch: "main"]}),
            "\"constraint_git\": {:git, \"#{constraint_git_url}\", \"#{constraint_git_revision}\", " \
            "[ref: \"#{constraint_git_revision}\"]}"
          )
        )
      end

      before do
        outer_git_head_revision
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs"), dependency_name), anything)
          .and_wrap_original do |original, command, **options|
            constraint_checkouts_seen << File.exist?("deps/constraint_git/mix.exs")
            original.call(command, **options)
          end
      end

      it "fetches the candidate and its locked Git children before updating" do
        expect(latest_resolvable_version).to eq(outer_git_head_revision)
        expect(constraint_checkouts_seen).to contain_exactly(true)
      end
    end

    context "when an unrelated dependency changes from Git to Hex" do
      let(:dependency_name) { "poison" }
      let(:version) { "2.2.0" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: ">= 2.2.0", groups: [], source: nil }]
      end
      let(:mixfile_fixture_body) do
        mixfile_for(
          :dependabot_test,
          ['{:poison, ">= 2.2.0"}', '{:phoenix, "1.2.0"}']
        )
      end
      let(:lockfile_fixture_name) { "git_source" }

      before { stub_update_result("2.2.0") }

      it "ignores the stale Git lock during bootstrap" do
        expect(latest_resolvable_version).to eq(Dependabot::Hex::Version.new("2.2.0"))
      end
    end

    context "when an unrelated Git dependency changes ref" do
      include_context "with local nested Git dependencies"
      let(:dependency_name) { "poison" }
      let(:version) { "2.2.0" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: ">= 2.2.0", groups: [], source: nil }]
      end
      let(:mixfile_fixture_body) do
        mixfile_for(
          :dependabot_test,
          [
            '{:poison, ">= 2.2.0"}',
            %({:constraint_git, git: "#{constraint_git_url}", ref: "#{constraint_git_head_revision}"})
          ]
        )
      end
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "mix.lock",
          content: git_source_lockfile(
            "\"constraint_git\": {:git, \"#{constraint_git_url}\", \"#{constraint_git_revision}\", " \
            "[ref: \"#{constraint_git_revision}\"]}"
          )
        )
      end

      before { stub_update_result("2.2.0") }

      it "allows Mix to reconcile the changed source" do
        expect(latest_resolvable_version).to eq(Dependabot::Hex::Version.new("2.2.0"))
      end
    end

    context "when the locked target release is unavailable" do
      let(:lockfile) do
        Dependabot::DependencyFile.new(
          name: "mix.lock",
          content: fixture("lockfiles", "minor_version").sub(
            "141058cca1fa800128391ece7f442f71a7b42a7411e6eaa56dc8f85283c8dde7",
            "0" * 64
          )
        )
      end

      it "updates without fetching the obsolete target artifact" do
        expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
      end
    end

    context "with a legacy lock entry whose child must update" do
      let(:mixfile_fixture_name) { "old_elixir" }
      let(:lockfile_fixture_name) { "old_elixir" }
      let(:dependency_name) { "phoenix" }
      let(:version) { "1.2.5" }
      let(:dependency_requirements) do
        [{ file: "mix.exs", requirement: "~> 1.2.1", groups: [], source: nil }]
      end

      before { mixfile_fixture_body.gsub!("~> 1.2.1", ">= 1.2.1") }

      it "updates the target's children across legacy tuple sizes" do
        expect(latest_resolvable_version).to be >= Gem::Version.new("1.3.0")
      end
    end

    context "when Hex needs the installed target lock for cooldown decisions" do
      let(:lockfiles_seen_by_update) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs"), dependency_name), anything) do
            lockfiles_seen_by_update << File.read("mix.lock")
            File.write(".dependabot-result", "1.3.6")
            ""
          end
      end

      it "keeps the original target entry on disk for the update task" do
        expect(latest_resolvable_version).to eq(Dependabot::Hex::Version.new("1.3.6"))
        expect(lockfiles_seen_by_update).to contain_exactly(a_string_including(%("plug": {:hex, :plug, "1.3.5")))
      end
    end

    context "with a call to read a version file in a support file" do
      let(:mixfile_fixture_name) { "loads_file_with_require" }
      let(:prepared_files) { [sanitized_mixfile, lockfile, support_file] }
      let(:support_file) do
        Dependabot::DependencyFile.new(
          name: "module_version.ex",
          content: fixture("support_files", "module_version"),
          support_file: true
        )
      end

      it "still finds a resolvable version" do
        expect(latest_resolvable_version).not_to be_nil
      end
    end

    context "with a dependency with a bad specification" do
      let(:mixfile_fixture_name) { "bad_spec" }

      it "raises a DependencyFileNotResolvable error", :skip_ci do
        expect { resolver.latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with an unresolvable mixfile" do
      let(:mixfile_fixture_name) { "unresolvable" }

      it "preserves Hex's generic resolution failure" do
        expect { resolver.latest_resolvable_version }
          .to raise_error(
            Dependabot::SharedHelpers::HelperSubprocessFailed,
            "** (Mix) Hex dependency resolution failed"
          )
      end
    end

    context "with a mix.exs that generates a deps warnings" do
      let(:mixfile_fixture_name) { "deps_warning" }

      it "respects the resolvability of the mix.exs" do
        expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
      end
    end

    context "when the update helper writes a result alongside stdout output" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including("mix", "run", end_with("/check_update.exs"), "plug"), anything) do
            File.write(".dependabot-result", "1.3.6")
            "warning from mix.exs"
          end
      end

      it "reads the version from the filesystem using an isolated Hex home" do
        expect(latest_resolvable_version).to eq(Dependabot::Hex::Version.new("1.3.6"))
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including("mix", "run", end_with("/check_update.exs"), "--", "plug"),
          hash_including(
            env: hash_including("HEX_HOME" => a_string_matching(%r{/dependabot-hex-home})),
            fingerprint: "mix run check_update.exs <dependency_name>",
            timeout: 30
          )
        )
      end
    end

    context "when the update helper returns a git SHA" do
      let(:git_sha) { "a" * 40 }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs"), "plug"), anything) do
            File.write(".dependabot-result", git_sha)
            ""
          end
      end

      it "returns the SHA without parsing it as a version" do
        expect(latest_resolvable_version).to eq(git_sha)
      end
    end

    context "when the update helper does not write a result" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs"), "plug"), anything)
          .and_return("")
      end

      it "preserves the missing result as an internal error" do
        expect { latest_resolvable_version }.to raise_error(Errno::ENOENT, /\.dependabot-result/)
      end
    end

    context "when the update helper writes an invalid result" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs"), "plug"), anything) do
            File.write(".dependabot-result", "not a version")
            ""
          end
      end

      it "preserves the invalid result as an internal error" do
        expect { latest_resolvable_version }.to raise_error(ArgumentError, /Malformed version number string/)
      end
    end

    context "when dependency resolution times out" do
      let(:timeout_error) do
        helper_failure(
          "Timed out due to inactivity after 30 seconds",
          process_exit_value: "pid 123 exit 124"
        )
      end

      before do
        stub_resolution_failure(timeout_error)
      end

      it "preserves the inactivity timeout as an internal helper failure after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, /30 seconds/)
      end
    end

    context "when Hex names the unauthenticated source" do
      let(:original_cause) { RuntimeError.new("raw helper details") }
      let(:authentication_error) do
        helper_failure(
          "** (Mix) No authenticated organization found for dependabot. " \
          "Do you want to authenticate it now? [Yn] "
        )
      end

      before { stub_resolution_failure(authentication_error, cause: original_cause) }

      it "reports that source after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("dependabot")
            expect(error.cause).to be_nil
          end
      end
    end

    context "when repository credentials omit the URL" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "acme/private"
            }
          )
        ]
      end

      it "reports the repository name" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("acme/private")
          end
      end
    end

    context "with credentials configured for resolution" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "private_repo",
              "url" => "https://private.example",
              "public_key" => "public key"
            }
          )
        ]
      end

      it "shares one external temporary Hex home and removes it afterwards" do
        hex_homes = []
        mix_exs_values = []
        project_directory = T.let(nil, T.nilable(String))
        original_mix_exs = ENV.fetch("MIX_EXS", nil)

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including("lib/configure_credentials.exs"), anything) do |_command, options|
            hex_homes << options.fetch(:env).fetch("HEX_HOME")
            mix_exs_values << options.fetch(:env).fetch("MIX_EXS")
            ""
          end
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs")), anything) do |_command, options|
            hex_homes << options.fetch(:env).fetch("HEX_HOME")
            mix_exs_values << options.fetch(:env).fetch("MIX_EXS")
            project_directory = Dir.pwd
            File.write(".dependabot-result", "1.3.6")

            ""
          end

        ENV["MIX_EXS"] = "inherited/mix.exs"
        expect(latest_resolvable_version).to eq(Dependabot::Hex::Version.new("1.3.6"))
        expect(hex_homes.length).to eq(2)
        expect(hex_homes.uniq.length).to eq(1)
        expect(mix_exs_values.uniq).to eq(["mix.exs"])
        expect(project_directory).not_to be_nil
        expect(hex_homes.first).not_to start_with(project_directory.to_s)
        expect(File.exist?(hex_homes.first)).to be(false)
      ensure
        ENV["MIX_EXS"] = original_mix_exs
      end
    end

    context "with dependency task aliases" do
      let(:mixfile_fixture_name) { "dependency_task_aliases" }

      it "resolves without invoking the project aliases" do
        expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
      end
    end

    context "when the environments for another dependency diverge" do
      # Updating `credo` adds its `poison` subdependency to `dev`, while the
      # Mixfile explicitly limits `poison` to `test`.
      let(:mixfile_fixture_name) { "diverging_environments" }
      let(:lockfile_fixture_name) { "diverging_environments" }
      let(:dependency_name) { "credo" }
      let(:version) { "0.6.0" }
      let(:dependency_requirements) do
        [{
          file: "mix.exs",
          requirement: "~> 0.6",
          groups: %w(dev test),
          source: nil
        }]
      end

      it "returns no update from the real Mix diagnostic" do
        # In an ideal world, Dependabot would update the environment specified
        # in the Mixfile. In the meantime, we treat this as impossible to update.
        expect(resolver.latest_resolvable_version).to be_nil
      end
    end

    {
      "with an invalid requirement diagnostic" =>
        "** (Version.InvalidRequirementError) invalid requirement: >= nope",
      "with Hex 2.5.4's malformed root requirement diagnostic" =>
        "** (Mix) Required version >= nope for package jason is incorrectly specified (from: mix.exs)",
      "with Hex 2.5.4's malformed requirement diagnostic in a complex umbrella path" =>
        "** (Mix) Required version >= nope for package jason is incorrectly specified " \
        "(from: umbrella apps/geschäft/mix.exs)",
      "with the target missing from the active environment" =>
        "** (Mix) Unknown dependency plug for environment prod"
    }.each do |description, diagnostic|
      context description do
        let(:project_error) do
          helper_failure("warning: project output\n#{diagnostic}\n    stack trace")
        end

        before { stub_resolution_failure(project_error) }

        it "reports the user-facing project error" do
          expect { latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable, diagnostic)
        end
      end
    end

    context "with a generic Hex dependency resolution failure" do
      let(:resolution_error) { helper_failure("** (Mix) Hex dependency resolution failed") }

      before { stub_resolution_failure(resolution_error) }

      it "preserves the original helper failure after one attempt" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, resolution_error.message)
        expect(mix_attempts).to contain_exactly(:resolution)
      end
    end

    context "with a confirmed Mix dependency divergence" do
      let(:resolution_error) do
        helper_failure(
          "warning: project output\n" \
          "Dependencies have diverged:\n" \
          "** (Mix) Can't continue due to errors on dependencies\n"
        )
      end

      before { stub_resolution_failure(resolution_error) }

      it "returns no resolvable version" do
        expect(latest_resolvable_version).to be_nil
      end
    end

    context "when an operational failure follows a dependency divergence header" do
      let(:resolution_error) do
        helper_failure(
          "Dependencies have diverged:\n" \
          "fatal: unable to access repository\n"
        )
      end

      before { stub_resolution_failure(resolution_error) }

      it "preserves the operational failure" do
        expect { latest_resolvable_version }.to raise_error do |error|
          expect(error).to equal(resolution_error)
        end
      end
    end

    context "when Git bootstrap output mentions dependency divergence before failing" do
      let(:bootstrap_error) do
        helper_failure("project output: Dependencies have diverged\nfatal: Git checkout failed")
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/fetch_git_dependencies.exs"), dependency_name), anything)
          .and_raise(bootstrap_error)
      end

      it "preserves the operational failure" do
        expect { latest_resolvable_version }.to raise_error do |error|
          expect(error).to equal(bootstrap_error)
        end
      end
    end

    context "with a repository public-key authentication failure" do
      let(:resolution_error) do
        helper_failure('Downloading public key for repo "dependabot" failed with code: 401')
      end

      before { stub_resolution_failure(resolution_error) }

      it "raises an authentication error without retrying" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("dependabot")
            expect(error.cause).to be_nil
          end
      end
    end

    context "when a resolution error contains a raw repository URL query pair" do
      let(:repository_url) { "https://private.example?access_token=secret%2Bvalue" }
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "private_repo",
              "url" => repository_url
            }
          )
        ]
      end
      let(:resolution_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Could not fetch #{repository_url}",
          error_context: { "url" => repository_url },
          trace: ["Fetching #{repository_url}"]
        )
      end
      let(:cause) { RuntimeError.new("cause contains secret%2Bvalue") }

      before do
        allow(Dependabot::Hex::CredentialHelpers).to receive(:configure)
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including(end_with("/check_update.exs"), dependency_name), anything) do
            mix_attempts << :resolution
            raise resolution_error, cause: cause
          end
      end

      it "sanitizes the error and detaches the original cause" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
            expect(error.message).to include("access_token=***")
            expect(error.full_message).not_to include("secret%2Bvalue")
            expect(error.error_context.to_s).not_to include("secret%2Bvalue")
            expect(error.trace.to_s).not_to include("secret%2Bvalue")
            expect(error.cause).to be_nil
          end
      end
    end

    {
      "with a qualified fetch failure and ambiguous access diagnostic" => <<~ERROR,
        Failed to fetch record for private_repo/plug from registry
        This could be because the package does not exist, it was spelled incorrectly or you don't have permissions to it
        ** (Mix) Hex dependency resolution failed
      ERROR
      "when diagnostics mention multiple private sources" => <<~ERROR,
        Failed to fetch record for first_repo/plug from registry
        :timeout
        Failed to fetch record for second_repo/jason from registry
        Authentication failed (401)
        ** (Mix) Hex dependency resolution failed
      ERROR
      "with an unknown package in the lockfile" =>
        "Unknown package version plug 9.9.9 in lockfile",
      "with an unexpected helper exception" =>
        "** (RuntimeError) unexpected helper failure"
    }.each do |description, diagnostic|
      context description do
        let(:untranslated_error) { helper_failure(diagnostic) }

        before { stub_resolution_failure(untranslated_error) }

        it "preserves the original helper failure" do
          expect { latest_resolvable_version }.to raise_error do |error|
            expect(error).to equal(untranslated_error)
          end
        end
      end
    end

    context "without a lockfile" do
      let(:prepared_files) { [sanitized_mixfile] }

      it "respects the resolvability of the mix.exs" do
        expect(latest_resolvable_version).to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).to be < Gem::Version.new("1.4.0")
      end

      context "with a mix.exs that has caused trouble in the past" do
        let(:mixfile_fixture_name) { "coxir" }
        let(:dependency_name) { "kcl" }
        let(:version) { nil }
        let(:dependency_requirements) do
          [{ file: "mix.exs", requirement: "~> 1.1", groups: [], source: nil }]
        end

        it "resolves without issue" do
          expect(latest_resolvable_version).to be >= Gem::Version.new("1.1.0")
        end
      end
    end

    def helper_failure(message, error_context = {})
      Dependabot::SharedHelpers::HelperSubprocessFailed.new(
        message: message,
        error_context: error_context
      )
    end

    def mixfile_for(app, dependencies)
      module_name = app.to_s.split("_").map(&:capitalize).join
      dependency_lines = dependencies.map { |dependency| "      #{dependency}" }.join(",\n")

      <<~ELIXIR
        defmodule #{module_name}.MixProject do
          use Mix.Project

          def project do
            [
              app: :#{app},
              version: "0.1.0",
              deps: [
        #{dependency_lines}
              ]
            ]
          end
        end
      ELIXIR
    end

    def git_source_lockfile(*entries)
      content = fixture("lockfiles", "git_source").sub(/^  "phoenix":.*\n/, "")
      insertion = entries.map { |entry| "  #{entry},\n" }.join
      content.sub("%{", "%{\n#{insertion}")
    end

    def stub_update_result(version)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(array_including(end_with("/check_update.exs"), dependency_name), anything) do
          File.write(".dependabot-result", version)
          ""
        end
    end

    def stub_resolution_failure(error, cause: nil)
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(array_including(end_with("/check_update.exs"), dependency_name), anything)
        .and_wrap_original do
          mix_attempts << :resolution
          raise error, cause: cause
        end
    end
  end
end
