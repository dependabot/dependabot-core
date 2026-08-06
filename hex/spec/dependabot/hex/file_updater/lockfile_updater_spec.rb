# typed: false
# frozen_string_literal: true

# Sorbet cannot resolve the child-context-only target_version and error_message fixtures.

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/hex/file_updater/lockfile_updater"

RSpec.describe Dependabot::Hex::FileUpdater::LockfileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: files,
      dependencies: [dependency],
      credentials: [credentials]
    )
  end

  let(:credentials) do
    {
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }
  end

  let(:files) { [mixfile, lockfile] }
  let(:mixfile) do
    Dependabot::DependencyFile.new(
      content: fixture("mixfiles", mixfile_fixture_name),
      name: "mix.exs"
    )
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "mix.lock",
      content: fixture("lockfiles", lockfile_fixture_name)
    )
  end
  let(:mixfile_fixture_name) { "exact_version" }
  let(:lockfile_fixture_name) { "exact_version" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "plug",
      version: "1.4.3",
      requirements:
        [{ file: "mix.exs", requirement: "1.4.3", groups: [], source: nil }],
      previous_version: "1.3.0",
      previous_requirements:
        [{ file: "mix.exs", requirement: "1.3.0", groups: [], source: nil }],
      package_manager: "hex"
    )
  end
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  before { FileUtils.mkdir_p(tmp_path) }

  describe "#updated_lockfile_content" do
    subject(:updated_lockfile_content) { updater.updated_lockfile_content }

    it "doesn't store the files permanently" do
      expect { updated_lockfile_content }
        .not_to(change { Dir.entries(tmp_path) })
    end

    it { expect { updated_lockfile_content }.not_to output.to_stdout }

    it "updates the dependency version in the lockfile" do
      expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.3")
      expect(updated_lockfile_content).to include(
        "236d77ce7bf3e3a2668dc0d32a9b6f1f9b1f05361019946aae49874904be4aed"
      )
    end

    context "with a deps.update alias" do
      let(:mixfile_fixture_name) { "deps_update_alias" }
      let(:lockfile_fixture_name) { "minor_version" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "plug",
          version: "1.3.6",
          requirements: [{ file: "mix.exs", requirement: "~> 1.3.0", groups: [], source: nil }],
          previous_version: "1.3.5",
          previous_requirements: [{ file: "mix.exs", requirement: "~> 1.3.0", groups: [], source: nil }],
          package_manager: "hex"
        )
      end

      it "updates without invoking the project alias" do
        expect(updated_lockfile_content).to include %({:hex, :plug, "1.3.6")
      end
    end

    context "with no requirement" do
      let(:mixfile_fixture_name) { "no_requirement" }
      let(:lockfile_fixture_name) { "no_requirement" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "plug",
          version: target_version,
          requirements: [
            { file: "mix.exs", requirement: nil, groups: [], source: nil }
          ],
          previous_version: "1.3.0",
          previous_requirements: [
            { file: "mix.exs", requirement: nil, groups: [], source: nil }
          ],
          package_manager: "hex"
        )
      end

      context "when the target version is 1.3.2" do
        let(:target_version) { "1.3.2" }

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content).to include %({:hex, :plug, "1.3.2")
          expect(updated_lockfile_content).to include(
            "8391d8ba2e2c187de069211110a882599e851f64550c556163b5130e1e2dbc1b"
          )
        end
      end

      context "when the target version is 1.3.6" do
        let(:target_version) { "1.3.6" }

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content).to include %({:hex, :plug, "1.3.6")
          expect(updated_lockfile_content).to include(
            "bcdf94ac0f4bc3b804bdbdbde37ebf598bd7ed2bfa5106ed1ab5984a09b7e75f"
          )
        end
      end
    end

    context "when the subdependencies should have changed" do
      let(:mixfile_fixture_name) { "minor_version" }
      let(:lockfile_fixture_name) { "minor_version" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "1.3.0",
          requirements: [{
            file: "mix.exs",
            requirement: "~> 1.3.0",
            groups: [],
            source: nil
          }],
          previous_version: "1.2.5",
          previous_requirements: [{
            file: "mix.exs",
            requirement: "~> 1.2.1",
            groups: [],
            source: nil
          }],
          package_manager: "hex"
        )
      end

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include %({:hex, :phoenix, "1.3)
        expect(updated_lockfile_content).to include %({:hex, :poison, "3)
      end

      context "with an old-format lockfile" do
        let(:mixfile_fixture_name) { "old_elixir" }
        let(:lockfile_fixture_name) { "old_elixir" }

        it "updates the dependency version in the lockfile" do
          expect(updated_lockfile_content).to start_with('%{"mime"')
          expect(updated_lockfile_content).to end_with("}}\n")
          expect(updated_lockfile_content).to include %({:hex, :phoenix, "1.3)
        end
      end
    end

    context "with upgrade to transitive dependencies" do
      let(:mixfile_fixture_name) { "deep_upgrade" }
      let(:lockfile_fixture_name) { "deep_upgrade" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix_ecto",
          version: "4.2.0",
          requirements: [{
            file: "mix.exs",
            requirement: "~> 4.2.0",
            groups: [],
            source: nil
          }],
          previous_version: "4.1.0",
          previous_requirements: [{
            file: "mix.exs",
            requirement: "~> 4.1.0",
            groups: [],
            source: nil
          }],
          package_manager: "hex"
        )
      end

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include ':hex, :phoenix_ecto, "4.2'
      end

      it "retains management info for transitive dependencies" do
        decimal_lock_line = updated_lockfile_content
                            .split("\n")
                            .find { |l| l.include?('"decimal":') }
        expect(decimal_lock_line).to include ", [:mix], ["
      end
    end

    context "with a mix.exs that opens another file" do
      let(:mixfile_fixture_name) { "loads_file" }
      let(:lockfile_fixture_name) { "exact_version" }

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.3")
        expect(updated_lockfile_content).to include(
          "236d77ce7bf3e3a2668dc0d32a9b6f1f9b1f05361019946aae49874904be4aed"
        )
      end
    end

    context "with a mix.exs that evals another file" do
      let(:mixfile_fixture_name) { "loads_file_with_eval" }
      let(:lockfile_fixture_name) { "exact_version" }
      let(:files) { [mixfile, lockfile, support_file] }
      let(:support_file) do
        Dependabot::DependencyFile.new(
          name: "version",
          content: fixture("support_files", "version"),
          support_file: true
        )
      end

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.3")
        expect(updated_lockfile_content).to include(
          "236d77ce7bf3e3a2668dc0d32a9b6f1f9b1f05361019946aae49874904be4aed"
        )
      end
    end

    context "when SharedHelpers::HelperSubprocessFailed is raised" do
      let(:subprocess_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: error_message,
          error_context: {}
        )
      end
      let(:subprocess_error_cause) { nil }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including("mix", "run", "do_update.exs"), anything) do
            raise subprocess_error, cause: subprocess_error_cause if subprocess_error_cause

            raise subprocess_error
          end
      end

      {
        "with unauthenticated access to a private repo" =>
          "No authenticated organization found for dependabot.",
        "with a newline-terminated unauthenticated organization diagnostic" =>
          "** (Mix) No authenticated organization found for dependabot.\n",
        "with guidance after an unauthenticated organization diagnostic" =>
          "** (Mix) No authenticated organization found for dependabot. " \
          "Do you want to authenticate it now? [Yn] "
      }.each do |description, diagnostic|
        context description do
          let(:error_message) { diagnostic }

          it "raises a PrivateSourceAuthenticationFailure error" do
            expect { updated_lockfile_content }
              .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
                expect(error.source).to eq("dependabot")
              end
          end
        end
      end

      context "with a slash-containing source in an exact missing-credentials diagnostic" do
        let(:error_message) { 'Missing credentials for "acme/private"' }

        it "raises a PrivateSourceAuthenticationFailure error" do
          expect { updated_lockfile_content }
            .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
              expect(error.source).to eq("acme/private")
            end
        end
      end

      context "with unknown mix run error" do
        let(:error_message) { "Unknown subprocess error occurred" }
        let(:subprocess_error_cause) { RuntimeError.new("original helper cause") }

        it "re-raises the original subprocess error unchanged" do
          expect { updated_lockfile_content }.to raise_error do |error|
            expect(error).to equal(subprocess_error)
            expect(error.cause).to equal(subprocess_error_cause)
          end
        end
      end

      {
        "with an explicit dependency resolution failure" =>
          "** (Mix) Hex dependency resolution failed",
        "with a warning before an explicit dependency resolution failure" => <<~ERROR
          warning: function unused/0 is unused
            mix.exs:20
          ** (Mix) Hex dependency resolution failed
        ERROR
      }.each do |description, diagnostic|
        context description do
          let(:error_message) { diagnostic }

          it "raises a DependencyFileNotResolvable error" do
            expect { updated_lockfile_content }
              .to raise_error(
                Dependabot::DependencyFileNotResolvable,
                "Hex dependency resolution failed"
              )
          end
        end
      end

      context "with an unknown lockfile package version" do
        let(:error_message) { "** (Mix) Unknown package version plug 9.9.9 in lockfile" }

        it "raises a DependencyFileNotResolvable error" do
          expect { updated_lockfile_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable, error_message)
        end
      end

      context "with a malformed package requirement" do
        let(:error_message) do
          "** (Mix) Required version >= nope for package jason is incorrectly specified (from: mix.exs)"
        end

        it "raises a DependencyFileNotResolvable error" do
          expect { updated_lockfile_content }
            .to raise_error(Dependabot::DependencyFileNotResolvable, error_message)
        end
      end

      {
        "with a public key fingerprint mismatch" =>
          'Public key fingerprint mismatch for repo "dependabot"',
        "with a generic record fetch failure" =>
          "Failed to fetch record for dependabot",
        "with a parse failure" =>
          "Failed to parse registry response"
      }.each do |description, diagnostic|
        context description do
          let(:error_message) { diagnostic }

          it "re-raises the original subprocess error unchanged" do
            expect { updated_lockfile_content }.to raise_error do |error|
              expect(error).to equal(subprocess_error)
            end
          end
        end
      end

      context "when resolution output includes a repository URL query secret" do
        let(:repository_url) do
          "https://repo.example.com/private?access_token=secret%2Bvalue"
        end
        let(:credentials) do
          Dependabot::Credential.new(
            {
              "type" => "hex_repository",
              "repo" => "dependabot",
              "url" => repository_url,
              "public-key-fingerprint" => "SHA256:public-key-fingerprint"
            }
          )
        end
        let(:error_message) do
          "Failed to fetch #{repository_url}"
        end
        let(:subprocess_error_cause) { RuntimeError.new(error_message) }

        before do
          allow(Dependabot::Hex::CredentialHelpers).to receive(:configure)
        end

        it "redacts the query value and preserves the parameter name" do
          expect { updated_lockfile_content }
            .to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
              expect(error.message).to include("access_token=***")
              expect(error.message).not_to include("secret%2Bvalue")
              expect(error.full_message).not_to include("secret%2Bvalue")
              expect(error.cause).to be_nil
            end
        end
      end
    end

    context "with a mix.exs that opens another file in a required file" do
      let(:mixfile_fixture_name) { "loads_file_with_require" }
      let(:lockfile_fixture_name) { "exact_version" }
      let(:files) { [mixfile, lockfile, support_file] }
      let(:support_file) do
        Dependabot::DependencyFile.new(
          name: "module_version.ex",
          content: fixture("support_files", "module_version"),
          support_file: true
        )
      end

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.3")
        expect(updated_lockfile_content).to include(
          "236d77ce7bf3e3a2668dc0d32a9b6f1f9b1f05361019946aae49874904be4aed"
        )
      end
    end

    context "with an umbrella app" do
      let(:mixfile_fixture_name) { "umbrella" }
      let(:lockfile_fixture_name) { "umbrella" }
      let(:files) { [mixfile, lockfile, sub_mixfile1, sub_mixfile2] }
      let(:sub_mixfile1) do
        Dependabot::DependencyFile.new(
          name: "apps/dependabot_business/mix.exs",
          content: fixture("mixfiles", "dependabot_business")
        )
      end
      let(:sub_mixfile2) do
        Dependabot::DependencyFile.new(
          name: "apps/dependabot_web/mix.exs",
          content: fixture("mixfiles", "dependabot_web")
        )
      end

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "plug",
          version: "1.4.5",
          requirements: [
            {
              requirement: "~> 1.4.0",
              file: "apps/dependabot_business/mix.exs",
              groups: [],
              source: nil
            },
            {
              requirement: "1.4.5",
              file: "apps/dependabot_web/mix.exs",
              groups: [],
              source: nil
            }
          ],
          previous_version: "1.3.6",
          previous_requirements: [
            {
              requirement: "~> 1.3.0",
              file: "apps/dependabot_business/mix.exs",
              groups: [],
              source: nil
            },
            {
              requirement: "1.3.6",
              file: "apps/dependabot_web/mix.exs",
              groups: [],
              source: nil
            }
          ],
          package_manager: "hex"
        )
      end

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.5")
        expect(updated_lockfile_content).to include(
          "7b13869283fff6b8b21b84b8735326cc012c5eef8607095dc6ee24bd0a273d8e"
        )
      end
    end

    context "with a git dependency" do
      let(:mixfile_fixture_name) { "git_source_no_tag" }
      let(:lockfile_fixture_name) { "git_source_no_tag" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "463e9d282e999fff1737cc6ca09074cf3dbca4ff",
          previous_version: "178ce1a2344515e9145599970313fcc190d4b881",
          requirements: [{
            requirement: nil,
            file: "mix.exs",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/phoenix.git",
              branch: "master",
              ref: nil
            }
          }],
          previous_requirements: [{
            requirement: nil,
            file: "mix.exs",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/dependabot-fixtures/phoenix.git",
              branch: "master",
              ref: nil
            }
          }],
          package_manager: "hex"
        )
      end

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include("phoenix.git")
        expect(updated_lockfile_content)
          .not_to include("178ce1a2344515e9145599970313fcc190d4b881")
      end
    end

    context "when updating Hex alongside an unchanged Git dependency" do
      let(:mixfile_fixture_name) { "git_source_no_tag" }
      let(:lockfile_fixture_name) { "git_source_no_tag" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "cors_plug",
          version: "1.3.0",
          previous_version: "1.2.1",
          requirements: [{
            requirement: "~> 1.3.0",
            file: "mix.exs",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            requirement: "~> 1.2.0",
            file: "mix.exs",
            groups: [],
            source: nil
          }],
          package_manager: "hex"
        )
      end

      it "retains the Git dependency's requirements during resolution" do
        expect(updated_lockfile_content).to include %({:hex, :cors_plug, "1.3.0")
        expect(updated_lockfile_content).to include(
          '{:git, "https://github.com/dependabot-fixtures/phoenix.git",'
        )
        expect(updated_lockfile_content).to include('"phoenix_pubsub"')
      end
    end

    context "with a private repo dependency" do
      let(:mixfile_fixture_name) { "private_repo" }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "jason",
          version: "1.1.0",
          requirements:
            [{ file: "mix.exs", requirement: "1.1.0", groups: [], source: nil }],
          previous_version: "1.0.0",
          previous_requirements:
            [{ file: "mix.exs", requirement: "1.0.0", groups: [], source: nil }],
          package_manager: "hex"
        )
      end
      let(:lockfile_fixture_name) { "private_repo" }
      let(:private_registry_url) { "https://dependabot-private.fly.dev" }

      let(:credentials) do
        Dependabot::Credential.new(
          {
            "type" => "hex_repository",
            "repo" => "dependabot",
            "auth_key" => "d6fc2b6n6h7katic6vuq6k5e2csahcm4",
            "url" => private_registry_url,
            "public_key_fingerprint" => "SHA256:z6VBddQXuo/nbwel0AMqHDAxvYuja4wt4qoQTTl3Ew4"
          }
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .and_call_original

        updated_lockfile = <<~LOCKFILE
          %{
            "jason": {:hex, :jason, "1.1.0", "99aa691404239cf4f6dbd4f44a2b208e45c98ed4df55ecca2bee58a6e3e2a1c4", [:mix], [], "dependabot", "b96c400e04b7b765c0854c05a4966323e90c0d11fee0483b1567cda079abb205"},
          }
        LOCKFILE

        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(
            array_including("mix", "run", "lib/configure_credentials.exs", "repository", "dependabot"),
            hash_including(
              env: hash_including(
                "DEPENDABOT_HEX_CREDENTIAL_TOKEN" => "d6fc2b6n6h7katic6vuq6k5e2csahcm4"
              )
            )
          )
          .and_return("")
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(array_including("mix", "run", "do_update.exs", "jason"), anything) do
            File.write("mix.lock", updated_lockfile)
            ""
          end
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mix", "deps.get", "--no-archives-check"], anything)
          .and_return("")
      end

      it "updates the dependency version in the lockfile" do
        expect(updated_lockfile_content).to include %({:hex, :jason, "1.1.0")
        expect(updated_lockfile_content).not_to include(
          "0f7cfa9bdb23fed721ec05419bcee2b2c21a77e926bce0deda029b5adc716fe2"
        )
      end

      it "configures the repository without exposing its auth key" do
        updated_lockfile_content

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including(
            "lib/configure_credentials.exs",
            "--",
            "repository",
            "dependabot",
            "SHA256:z6VBddQXuo/nbwel0AMqHDAxvYuja4wt4qoQTTl3Ew4"
          ),
          hash_including(
            fingerprint: "mix run configure_credentials.exs repository <repository>",
            cwd: Dependabot::Hex::NativeHelpers.hex_helpers_dir,
            env: hash_including(
              "HEX_HOME" => a_string_matching(%r{/dependabot-hex-home}),
              "DEPENDABOT_HEX_CREDENTIAL_TOKEN" => "d6fc2b6n6h7katic6vuq6k5e2csahcm4",
              "DEPENDABOT_HEX_REPOSITORY_URL_TOKEN" => private_registry_url
            )
          )
        )
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(array_including("lib/configure_credentials.exs"), anything) do |command, options|
          expect(command).not_to include("d6fc2b6n6h7katic6vuq6k5e2csahcm4")
          expect(options.fetch(:fingerprint)).not_to include("d6fc2b6n6h7katic6vuq6k5e2csahcm4")
        end
      end
    end

    context "with token-bearing Hex organization credentials" do
      let(:credentials) do
        Dependabot::Credential.new(
          {
            "type" => "hex_organization",
            "organization" => "dependabot",
            "token" => "organization-secret-token"
          }
        )
      end

      let(:hex_homes) { [] }
      let(:mix_exs_values) { [] }
      let(:project_directories) { [] }

      around do |example|
        inherited_mix_exs = ENV.fetch("MIX_EXS", nil)
        ENV["MIX_EXS"] = "/tmp/untrusted/mix.exs"
        example.run
      ensure
        ENV["MIX_EXS"] = inherited_mix_exs
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, **options|
          if options[:env]&.key?("HEX_HOME")
            hex_homes << options.fetch(:env).fetch("HEX_HOME")
            mix_exs_values << options.fetch(:env).fetch("MIX_EXS")
            project_directories << Dir.pwd
          end
          File.write("mix.lock", lockfile.content) if command.include?("do_update.exs")
          ""
        end
      end

      it "configures the organization without exposing its token" do
        updated_lockfile_content

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including("lib/configure_credentials.exs", "--", "organization", "dependabot"),
          hash_including(
            fingerprint: "mix run configure_credentials.exs organization <organization>",
            env: hash_including(
              "HEX_HOME" => a_string_matching(%r{/dependabot-hex-home}),
              "MIX_EXS" => "mix.exs",
              "DEPENDABOT_HEX_CREDENTIAL_TOKEN" => "organization-secret-token"
            )
          )
        )
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(array_including("lib/configure_credentials.exs"), anything) do |command, options|
          expect(command).not_to include("organization-secret-token")
          expect(options.fetch(:fingerprint)).not_to include("organization-secret-token")
        end
      end

      it "shares one external temporary Hex home and removes it afterward" do
        updated_lockfile_content

        expect(hex_homes.uniq.length).to eq(1)
        expect(mix_exs_values.uniq).to eq(["mix.exs"])
        expect(project_directories).not_to include(hex_homes.first)
        expect(hex_homes.first).not_to start_with("#{project_directories.first}/")
        expect(File).not_to exist(hex_homes.first)
      end
    end

    context "with a private organization dependency" do
      let(:mixfile_fixture_name) { "private_package" }
      let(:lockfile_fixture_name) { "private_package" }
      let(:organization_token) { ENV.fetch("HEX_PM_ORGANIZATION_TOKEN", nil) }
      let(:credentials) do
        Dependabot::Credential.new(
          {
            "type" => "hex_organization",
            "organization" => "dependabot",
            "token" => organization_token
          }
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "example_package_a",
          version: "1.1.0",
          requirements: [{ file: "mix.exs", requirement: "~> 1.1.0", groups: [], source: nil }],
          previous_version: "1.0.0",
          previous_requirements: [{ file: "mix.exs", requirement: "~> 1.0.0", groups: [], source: nil }],
          package_manager: "hex"
        )
      end
      let(:hex_homes) { [] }
      let(:oauth_exchange_disabled) { [] }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .and_wrap_original do |method, command, **options|
          if command.include?("do_update.exs")
            hex_home = options.fetch(:env).fetch("HEX_HOME")
            hex_homes << hex_home
            config = File.read(File.join(hex_home, "hex.config"))
            oauth_exchange_disabled << config.include?("oauth_exchange => false")
          end

          method.call(command, **options)
        end
      end

      it "authenticates and resolves through the shared Hex home with OAuth exchange disabled" do
        skip("skipped because env var HEX_PM_ORGANIZATION_TOKEN is not set") if organization_token.nil?

        expect(updated_lockfile_content).to include %({:hex, :example_package_a, "1.1.0")
        expect(hex_homes.uniq.length).to eq(1)
        expect(oauth_exchange_disabled).to all(be(true))
        expect(File).not_to exist(hex_homes.first)
      end
    end

    context "with unused tokenless Hex organization metadata" do
      let(:credentials) do
        Dependabot::Credential.new(
          {
            "type" => "hex_organization",
            "organization" => "dependabot"
          }
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
      end

      it "skips credential setup and reaches the dependency update" do
        expect(updated_lockfile_content).to include %({:hex, :plug, "1.4.3")

        expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
          .with(array_including("lib/configure_credentials.exs"), anything)
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(
            array_including("mix", "run", "do_update.exs", "plug"),
            hash_including(fingerprint: "mix run do_update.exs <dependency_name>")
          )
      end
    end

    context "with a repository public key fingerprint" do
      let(:credentials) do
        Dependabot::Credential.new(
          {
            "type" => "hex_repository",
            "repo" => "dependabot",
            "url" => "https://repo.example.com",
            "auth_key" => "repository-secret-key",
            "public_key_fingerprint" => "SHA256:public-key-fingerprint"
          }
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |command, **|
          File.write("mix.lock", lockfile.content) if command.include?("do_update.exs")
          ""
        end
      end

      it "forwards the fingerprint without exposing the auth key" do
        updated_lockfile_content

        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
          array_including(
            "lib/configure_credentials.exs",
            "--",
            "repository",
            "dependabot",
            "SHA256:public-key-fingerprint"
          ),
          hash_including(
            fingerprint: "mix run configure_credentials.exs repository <repository>",
            env: hash_including(
              "DEPENDABOT_HEX_CREDENTIAL_TOKEN" => "repository-secret-key",
              "DEPENDABOT_HEX_REPOSITORY_URL_TOKEN" => "https://repo.example.com"
            )
          )
        )
        expect(Dependabot::SharedHelpers).to have_received(:run_shell_command)
          .with(array_including("lib/configure_credentials.exs"), anything) do |command, options|
          expect(command).not_to include("repository-secret-key")
          expect(options.fetch(:fingerprint)).not_to include("repository-secret-key")
        end
      end
    end

    context "with Hex credentials missing a URL" do
      let(:credentials) do
        Dependabot::Credential.new(
          {
            "type" => "hex_repository",
            "repo" => "dependabot"
          }
        )
      end

      it "raises a private source authentication error" do
        expect { updated_lockfile_content }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure) do |error|
            expect(error.source).to eq("dependabot")
          end
      end
    end
  end
end
