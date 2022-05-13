# frozen_string_literal: true

require "spec_helper"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::SharedHelpers do
  let(:spec_root) { File.join(File.dirname(__FILE__), "..") }

  describe ".in_a_temporary_directory" do
    def existing_tmp_folders
      Dir.glob(File.join(Dependabot::Utils::BUMP_TMP_DIR_PATH, "*"))
    end

    subject(:in_a_temporary_directory) do
      Dependabot::SharedHelpers.in_a_temporary_directory { output_dir.call }
    end

    let(:output_dir) { -> { Dir.pwd } }
    it "runs inside the temporary directory created" do
      expect(in_a_temporary_directory).to match(%r{tmp\/dependabot_+.})
    end

    it "yields the path to the temporary directory created" do
      expect { |b| described_class.in_a_temporary_directory(&b) }.
        to yield_with_args(Pathname)
    end

    it "removes the temporary directory after use" do
      expect { in_a_temporary_directory }.not_to(change { existing_tmp_folders })
    end
  end

  describe ".in_a_temporary_repo_directory" do
    subject(:in_a_temporary_repo_directory) do
      Dependabot::SharedHelpers.
        in_a_temporary_repo_directory(directory, repo_contents_path) do
          on_create.call
        end
    end

    let(:directory) { "/" }
    let(:on_create) { -> { Dir.pwd } }
    let(:project_name) { "vendor_gems" }
    let(:repo_contents_path) { build_tmp_repo(project_name) }

    it "runs inside the temporary repo directory" do
      expect(in_a_temporary_repo_directory).to eq(repo_contents_path)
    end

    context "with a valid directory" do
      let(:directory) { "vendor/cache" }
      let(:on_create) { -> { `ls .` } }

      it "yields the directory contents" do
        expect(in_a_temporary_repo_directory).
          to include("business-1.4.0.gem")
      end
    end

    context "with a missing directory" do
      let(:directory) { "missing/directory" }

      it "creates the missing directory " do
        expect(in_a_temporary_repo_directory).
          to eq(Pathname.new(repo_contents_path).join(directory).to_s)
      end
    end

    context "with modifications to the repo contents" do
      before do
        Dir.chdir(repo_contents_path) do
          `touch some-file.txt`
        end
      end

      let(:on_create) { -> { `stat some-file.txt 2>&1` } }

      it "resets the changes " do
        expect(in_a_temporary_repo_directory).
          to include("No such file or directory")
      end
    end

    context "without repo_contents_path" do
      before do
        allow(described_class).to receive(:in_a_temporary_directory).
          and_call_original
      end

      it "falls back to creating a temporary directory" do
        expect { |b| described_class.in_a_temporary_repo_directory(&b) }.
          to yield_with_args(Pathname)
        expect(described_class).to have_received(:in_a_temporary_directory)
      end
    end
  end

  describe ".run_helper_subprocess" do
    let(:function) { "example" }
    let(:args) { ["foo"] }
    let(:env) { nil }
    let(:stderr_to_stdout) { false }

    subject(:run_subprocess) do
      bin_path = File.join(spec_root, "helpers/test/run.rb")
      command = "ruby #{bin_path}"
      Dependabot::SharedHelpers.run_helper_subprocess(
        command: command,
        function: function,
        args: args,
        env: env,
        stderr_to_stdout: stderr_to_stdout
      )
    end

    context "when the subprocess is successful" do
      it "returns the result" do
        expect(run_subprocess).to eq("function" => function, "args" => args)
      end

      context "with an env" do
        let(:env) { { "MIX_EXS" => "something" } }

        it "runs the function passed, as expected" do
          expect(run_subprocess).to eq("function" => function, "args" => args)
        end
      end

      context "when sending stderr to stdout" do
        let(:stderr_to_stdout) { true }
        let(:function) { "useful_error" }

        it "raises a HelperSubprocessFailed error with stderr output" do
          expect { run_subprocess }.
            to raise_error(
              Dependabot::SharedHelpers::HelperSubprocessFailed
            ) do |error|
              expect(error.message).
                to include("Some useful error")
            end
        end
      end
    end

    context "when the subprocess fails gracefully" do
      let(:function) { "error" }

      it "raises a HelperSubprocessFailed error" do
        expect { run_subprocess }.
          to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)
      end
    end

    context "when the subprocess fails gracefully with sensitive data" do
      let(:function) { "sensitive_error" }

      it "raises a HelperSubprocessFailed error" do
        expect { run_subprocess }.
          to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed) do |error|
            expect(error.message).to eq("Something went wrong: https://www.example.com")
          end
      end
    end

    context "when the subprocess fails ungracefully" do
      let(:function) { "hard_error" }

      it "raises a HelperSubprocessFailed error" do
        expect { run_subprocess }.
          to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)
      end
    end

    context "when the subprocess is killed" do
      let(:function) { "killed" }

      it "raises a HelperSubprocessFailed error" do
        expect { run_subprocess }.
          to(raise_error do |error|
            expect(error).
              to be_a(Dependabot::SharedHelpers::HelperSubprocessFailed)
            expect(error.error_context[:process_termsig]).to eq(9)
          end)
      end
    end
  end

  describe ".run_shell_command" do
    let(:command) { File.join(spec_root, "helpers/test/run_bash") + " output" }
    let(:env) { nil }

    subject(:run_shell_command) do
      Dependabot::SharedHelpers.run_shell_command(command, env: env)
    end

    context "when the subprocess is successful" do
      it "returns the result" do
        expect(run_shell_command).to eq("output\n")
      end
    end

    context "with bash command as argument" do
      let(:command) do
        File.join(spec_root, "helpers/test/run_bash") + " $(ps)"
      end

      it "returns the argument" do
        expect(run_shell_command).to eq("$(ps)\n")
      end

      context "when allowing unsafe shell command" do
        subject(:run_shell_command) do
          Dependabot::SharedHelpers.
            run_shell_command(command, allow_unsafe_shell_command: true)
        end

        it "returns the command output" do
          output = run_shell_command
          expect(output).not_to eq("$(ps)\n")
          expect(output).to include("PID")
        end
      end
    end

    context "with an environment variable" do
      let(:env) { { "TEST_ENV" => "prefix:" } }

      it "is available to the command" do
        expect(run_shell_command).to eq("prefix:output\n")
      end
    end

    context "when the subprocess exits" do
      let(:command) { File.join(spec_root, "helpers/test/error_bash") }

      it "raises a HelperSubprocessFailed error" do
        expect { run_shell_command }.
          to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed)
      end
    end
  end

  describe ".escape_command" do
    let(:command) { "yes | foo=1 &  'na=1'  name  > file" }

    subject(:escape_command) do
      Dependabot::SharedHelpers.escape_command(command)
    end

    it do
      is_expected.to eq("yes \\| foo\\=1 \\& \\'na\\=1\\' name \\> file")
    end

    context "when empty" do
      let(:command) { "" }

      it { is_expected.to eq("") }
    end
  end

  describe ".excon_headers" do
    it "includes dependabot user-agent header" do
      expect(described_class.excon_headers).to include(
        "User-Agent" => %r{
          dependabot-core/#{Dependabot::VERSION}\s|
          excon/[\.0-9]+\s|
          ruby/[\.0-9]+\s\(.+\)\s|
          (|
          \+https://github.com/dependabot/|dependabot-core|
          )|
        }x
      )
    end

    it "allows extra headers" do
      expect(
        described_class.excon_headers(
          "Accept" => "text/html"
        )
      ).to include(
        "User-Agent" => /dependabot/,
        "Accept" => "text/html"
      )
    end

    it "allows overriding user-agent headers" do
      expect(
        described_class.excon_headers(
          "User-Agent" => "custom"
        )
      ).to include(
        "User-Agent" => "custom"
      )
    end
  end

  describe ".excon_defaults" do
    subject(:excon_defaults) do
      described_class.excon_defaults
    end

    it "includes the defaults" do
      expect(subject).to eq(
        connect_timeout: 5,
        write_timeout: 5,
        read_timeout: 20,
        retry_limit: 4,
        omit_default_port: true,
        middlewares: described_class.excon_middleware,
        headers: described_class.excon_headers
      )
    end

    it "allows overriding options and merges headers" do
      expect(
        described_class.excon_defaults(
          read_timeout: 30,
          headers: {
            "Accept" => "text/html"
          }
        )
      ).to include(
        connect_timeout: 5,
        write_timeout: 5,
        read_timeout: 30,
        omit_default_port: true,
        middlewares: described_class.excon_middleware,
        headers: {
          "User-Agent" => /dependabot/,
          "Accept" => "text/html"
        }
      )
    end
  end

  describe ".with_git_configured" do
    config_header = "Generated by dependabot/dependabot-core"

    credentials_helper = <<~CONFIG.chomp
      [credential]
      	helper = !#{Dependabot::SharedHelpers.credential_helper_path} --file #{Dir.pwd}/git.store
    CONFIG

    def alternatives(host)
      <<~CONFIG.chomp
        [url "https://#{host}/"]
        	insteadOf = ssh://git@#{host}/
        	insteadOf = ssh://git@#{host}:
        	insteadOf = git@#{host}:
        	insteadOf = git@#{host}/
        	insteadOf = git://#{host}/
      CONFIG
    end

    let(:credentials) { [] }

    def with_git_configured(&block)
      Dependabot::SharedHelpers.with_git_configured(credentials: credentials) { block.call }
    end

    let(:configured_git_config) { with_git_configured { `cat ~/.gitconfig` } }
    let(:configured_git_credentials) { with_git_configured { `cat #{Dir.pwd}/git.store` } }

    context "when the global .gitconfig has a safe directory" do
      before do
        Open3.capture2("git config --global --add safe.directory /home/dependabot/dependabot-core/repo")
      end
      after do
        Open3.capture2("git config --global --unset safe.directory /home/dependabot/dependabot-core/repo")
      end

      it "is preserved in the temporary .gitconfig" do
        expect(configured_git_config).to include("directory = /home/dependabot/dependabot-core/repo")
      end

      context "when the global .gitconfig has two safe directories" do
        before do
          Open3.capture2("git config --global --add safe.directory /home/dependabot/dependabot-core/repo2")
        end
        after do
          Open3.capture2("git config --global --unset safe.directory /home/dependabot/dependabot-core/repo2")
        end

        it "is preserved in the temporary .gitconfig" do
          expect(configured_git_config).to include("directory = /home/dependabot/dependabot-core/repo")
          expect(configured_git_config).to include("directory = /home/dependabot/dependabot-core/repo2")
        end
      end
    end

    context "when providing no extra credentials" do
      let(:credentials) { [] }

      it "creates a .gitconfig that contains the Dependabot header" do
        expect(configured_git_config).to include(config_header)
      end

      it "creates a .gitconfig that contains the credentials helper" do
        expect(configured_git_config).to include(credentials_helper)
      end

      it "creates a .gitconfig that contains the github.com alternatives" do
        expect(configured_git_config).to include(alternatives("github.com"))
      end

      it "creates a git credentials store that is empty" do
        expect(configured_git_credentials).to eq("")
      end
    end

    context "when providing github.com credentials" do
      let(:credentials) do
        [
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "fake-token"
          }
        ]
      end

      it "creates a .gitconfig that contains the Dependabot header" do
        expect(configured_git_config).to include(config_header)
      end

      it "creates a .gitconfig that contains the credentials helper" do
        expect(configured_git_config).to include(credentials_helper)
      end

      it "creates a .gitconfig that contains the github.com alternatives" do
        expect(configured_git_config).to include(alternatives("github.com"))
      end

      it "creates a git credentials store that contains github.com credentials" do
        expect(configured_git_credentials).to eq("https://x-access-token:fake-token@github.com\n")
      end
    end

    context "when providing multiple github.com credentials" do
      let(:credentials) do
        [
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "v1.fake-token"
          },
          {
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "fake-token"
          }
        ]
      end

      it "creates a git credentials store that contains non-app-token github.com credentials" do
        expect(configured_git_credentials).to eq("https://x-access-token:fake-token@github.com\n")
      end
    end

    context "when providing private git_source credentials" do
      let(:credentials) do
        [
          {
            "type" => "git_source",
            "host" => "private.com",
            "username" => "x-access-token",
            "password" => "fake-token"
          }
        ]
      end

      it "creates a .gitconfig that contains the Dependabot header" do
        expect(configured_git_config).to include(config_header)
      end

      it "creates a .gitconfig that contains the credentials helper" do
        expect(configured_git_config).to include(credentials_helper)
      end

      it "creates a .gitconfig that contains the github.com alternatives" do
        expect(configured_git_config).to include(alternatives("github.com"))
      end

      it "creates a .gitconfig that contains the private.com alternatives" do
        expect(configured_git_config).to include(alternatives("private.com"))
      end

      it "creates a git credentials store that contains private git credentials" do
        expect(configured_git_credentials).to eq("https://x-access-token:fake-token@private.com\n")
      end
    end

    context "when the host has run out of disk space" do
      before do
        allow(File).to receive(:open).
          with(described_class::GIT_CONFIG_GLOBAL_PATH, anything).
          and_raise(Errno::ENOSPC)
      end

      specify { expect { configured_git_config }.to raise_error(Dependabot::OutOfDisk) }
    end
  end
end
