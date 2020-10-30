# frozen_string_literal: true

require "spec_helper"
require "dependabot/shared_helpers"

RSpec.describe Dependabot::SharedHelpers do
  describe ".in_a_temporary_directory" do
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
      expect(in_a_temporary_repo_directory).to eq(repo_contents_path.to_s)
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
          to eq(repo_contents_path.join(directory).to_s)
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
      spec_root = File.join(File.dirname(__FILE__), "..")
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

    context "when the subprocess fails ungracefully" do
      let(:function) { "hard_error" }

      it "raises a HelperSubprocessFailed error" do
        expect { run_subprocess }.
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
end
