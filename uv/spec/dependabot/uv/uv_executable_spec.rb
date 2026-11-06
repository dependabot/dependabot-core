# typed: false
# frozen_string_literal: true

require "dependabot/credential"
require "dependabot/uv/uv_executable"
require_relative "../../spec_helper"

RSpec.describe Dependabot::Uv::UvExecutable do
  subject(:executable) { described_class.resolve(credentials: credentials) }

  let(:credentials) { [] }
  let(:install_root) { Dir.mktmpdir }
  let(:project_dir) { Dir.mktmpdir }
  let(:pyproject) { "[tool.uv]\nrequired-version = \">=0.8.22, <0.9\"\n" }
  let(:probe) { "pyenv exec uv cache dir" }
  let(:pip_install) { [] }
  let(:pip_configs) { [] }
  let(:mismatch_error) do
    Dependabot::SharedHelpers::HelperSubprocessFailed.new(
      message: "error: Required uv version `>=0.8.22, <0.9` does not match the running version `0.13.7`",
      error_context: {}
    )
  end

  around do |example|
    File.write(File.join(project_dir, "pyproject.toml"), pyproject)
    Dir.chdir(project_dir) { example.run }
  ensure
    FileUtils.rm_rf([project_dir, install_root])
  end

  before do
    stub_const("#{described_class}::INSTALL_ROOT", install_root)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("pyenv prefix").and_return("/pyenv/versions/3.13.1\n")
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      array_including("pyenv", "exec", "pip", "install"), fingerprint: anything, env: anything
    ) do |argv, env:, **|
      pip_install << argv
      pip_configs << (env["PIP_CONFIG_FILE"] && File.read(env["PIP_CONFIG_FILE"]))
      install_uv(argv[argv.index("--target") + 1])
    end
  end

  def install_uv(target)
    FileUtils.mkdir_p(File.join(target, "bin"))
    File.write(File.join(target, "bin", "uv"), "")
    File.chmod(0o755, File.join(target, "bin", "uv"))
    ""
  end

  context "when no uv config declares required-version" do
    let(:pyproject) { "[tool.uv]\nmanaged = true\n" }

    it "runs the bundled uv without probing it" do
      expect(executable.command).to eq("pyenv exec uv")
      expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command).with(probe, fingerprint: probe)
    end
  end

  context "when the bundled uv satisfies the project" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(probe, fingerprint: probe).and_return("")
    end

    it "runs the bundled uv" do
      expect(executable.command).to eq("pyenv exec uv")
      expect(executable.env).to eq({})
    end
  end

  context "when the probe fails for a reason other than required-version" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(probe, fingerprint: probe).and_raise(
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "TOML parse error", error_context: {})
      )
    end

    it "leaves the error to the real command" do
      expect(executable.command).to eq("pyenv exec uv")
    end
  end

  context "when the project's required-version rejects the bundled uv" do
    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(probe, fingerprint: probe).and_raise(mismatch_error)
    end

    it "installs a uv satisfying the pin and runs it on the active Python's PATH" do
      expect(executable.command).to start_with(install_root).and end_with("/bin/uv")
      expect(executable.fingerprint).not_to include(install_root)
      expect(pip_install.map(&:last)).to eq(["uv>=0.8.22, <0.9"])
      expect(executable.env.fetch("PATH")).to start_with("/pyenv/versions/3.13.1/bin:")
    end

    it "installs each requirement once per job" do
      first = described_class.resolve(credentials: credentials)
      second = described_class.resolve(credentials: credentials)

      expect(second.command).to eq(first.command)
      expect(pip_install.size).to eq(1)
    end

    it "replaces a partial install left by a failed attempt" do
      target = File.dirname(described_class.resolve(credentials: credentials).command, 2)
      File.delete(File.join(target, "bin", "uv"))

      described_class.resolve(credentials: credentials)

      expect(pip_install.size).to eq(2)
    end

    context "when a Python index replaces PyPI" do
      let(:credentials) do
        [
          Dependabot::Credential.new(
            {
              "type" => "python_index",
              "index-url" => "https://mirror.example.com/simple",
              "token" => "user:secret",
              "replaces-base" => true
            }
          ),
          Dependabot::Credential.new("type" => "python_index", "index-url" => "https://extra.example.com/simple")
        ]
      end

      it "installs uv from that index without putting its credentials on the command line" do
        executable

        expect(pip_configs.first).to include("index-url = https://user:secret@mirror.example.com/simple")
        expect(pip_configs.first).not_to include("extra.example.com")
        expect(pip_install.first.join(" ")).not_to include("secret")
      end
    end

    context "when the required uv cannot be installed" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          array_including("pyenv", "exec", "pip", "install"), fingerprint: anything, env: anything
        ).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "ERROR: No matching distribution found for uv==99.0",
            error_context: {}
          )
        )
      end

      it "reports the requirement Dependabot could not meet" do
        expect { executable }.to raise_error(Dependabot::ToolVersionNotSupported) do |error|
          expect(error.detected_version).to eq(">=0.8.22, <0.9")
          expect(error.supported_versions).to include("0.13.7")
        end
      end
    end

    context "when the disk fills up during the install" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
          array_including("pyenv", "exec", "pip", "install"), fingerprint: anything, env: anything
        ).and_raise(
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "ERROR: Could not install packages due to an OSError: [Errno 28] No space left on device",
            error_context: {}
          )
        )
      end

      it "reports the disk, not the uv version" do
        expect { executable }.to raise_error(Dependabot::OutOfDisk)
      end
    end
  end
end
