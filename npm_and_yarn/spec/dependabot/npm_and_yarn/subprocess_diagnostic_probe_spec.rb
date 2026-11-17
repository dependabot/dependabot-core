# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "rbconfig"
require "dependabot/npm_and_yarn/subprocess_diagnostic_probe"

RSpec.describe Dependabot::NpmAndYarn::SubprocessDiagnosticProbe do
  extend T::Sig

  sig { params(script: String, executable: String).returns(Dependabot::ErrorReportContext::Context) }
  def probe(script, executable: "npm")
    Dependabot::SharedHelpers.in_a_temporary_directory do
      filename = executable.split.first.to_s
      File.write(filename, "#!#{RbConfig.ruby}\n#{script}")
      File.chmod(0o755, filename)
      described_class.new(executable: executable, env: { "PATH" => "#{Dir.pwd}:#{ENV.fetch('PATH')}" }).context
    end
  end

  before { allow(Dependabot.logger).to receive(:warn) }

  it "reports only the post-failure version and sanitized global registry host" do
    context = probe(<<~RUBY)
      abort unless ENV["COREPACK_ENABLE_NETWORK"] == "0" && ENV["COREPACK_ENABLE_DOWNLOAD_PROMPT"] == "0"
      if ARGV == ["--version"]
        puts "Launcher notice"
        puts "10.9.0"
      elsif ARGV == ["config", "get", "registry"]
        puts "https://user:secret@registry.example.com/private-token"
      else
        abort "Unexpected diagnostic command"
      end
    RUBY

    expect(context).to eq(
      "post-failure-package-manager-version" => "10.9.0",
      "post-failure-global-registry-hosts" => ["registry.example.com"]
    )
    expect(context.to_s).not_to include("secret", "private-token")
  end

  it "uses the Classic registry setting when the Yarn version probe reports version one" do
    context = probe(<<~RUBY, executable: "yarn")
      if ARGV == ["--version"]
        puts "1.22.22"
      elsif ARGV == ["config", "get", "registry"]
        puts "https://classic.example.com"
      else
        abort
      end
    RUBY

    expect(context).to eq(
      "post-failure-package-manager-version" => "1.22.22",
      "post-failure-global-registry-hosts" => ["classic.example.com"]
    )
  end

  it "queries Berry's registry setting using the same Corepack selector" do
    Dependabot::SharedHelpers.in_a_temporary_directory do
      File.write("corepack", <<~RUBY)
        #!#{RbConfig.ruby}
        abort unless ARGV.shift == "yarn@4"
        if ARGV == ["--version"]
          puts "4.9.2"
        elsif ARGV == ["config", "get", "npmRegistryServer"]
          puts "https://berry.example.com"
        else
          abort
        end
      RUBY
      File.chmod(0o755, "corepack")
      context = described_class.new(
        executable: "corepack yarn@4", env: { "PATH" => "#{Dir.pwd}:#{ENV.fetch('PATH')}" }
      ).context
      expect(context).to include(
        "post-failure-package-manager-version" => "4.9.2",
        "post-failure-global-registry-hosts" => ["berry.example.com"]
      )
    end
  end

  it "omits failed probes without logging their potentially sensitive output" do
    expect(probe('warn "secret"; exit 1')).to eq({})
    expect(Dependabot.logger).to have_received(:warn)
      .with("Post-failure package manager probe exited unsuccessfully").twice
  end

  it "omits malformed versions and interpolated registry URLs" do
    expect(probe(<<~RUBY)).to eq({})
      puts ARGV == ["--version"] ? "secret-not-a-version" : 'https://${TOKEN}.example.com/private'
    RUBY
  end

  it "terminates and reaps a continuously printing process at the wall-clock deadline" do
    stub_const("#{described_class}::TIMEOUT", 0.3)
    Dependabot::SharedHelpers.in_a_temporary_directory do
      pid_file = File.join(Dir.pwd, "probe.pid")
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      context = probe(<<~RUBY)
        File.write(#{pid_file.inspect}, Process.pid)
        STDOUT.sync = true
        loop do
          puts "still running"
          sleep 0.01
        end
      RUBY
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

      expect(context).to eq({})
      expect(elapsed).to be < 1.5
      pid = File.read(pid_file).to_i
      expect { Process.kill(0, pid) }.to raise_error(Errno::ESRCH)
      expect { Process.waitpid(pid) }.to raise_error(Errno::ECHILD)
    end
  end

  it "bounds silent processes with either open or closed stdout" do
    stub_const("#{described_class}::TIMEOUT", 0.3)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(probe("sleep 60")).to eq({})
    expect(probe("STDOUT.close; sleep 60")).to eq({})
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).to be < 1.5
    expect(Dependabot.logger).to have_received(:warn)
      .with("Post-failure package manager probe exceeded its wall-clock deadline").twice
  end

  it "terminates descendants in the probe's process group" do
    stub_const("#{described_class}::TIMEOUT", 0.5)
    Dependabot::SharedHelpers.in_a_temporary_directory do
      child_file = File.join(Dir.pwd, "child.pid")
      expect(probe(<<~RUBY)).to eq({})
        child = Process.spawn(#{RbConfig.ruby.inspect}, "-e", "sleep 60")
        File.write(#{child_file.inspect}, child)
        Process.waitpid(child)
      RUBY

      child_pid = File.read(child_file).to_i
      # An orphan may remain as a zombie until the container's init reaps it.
      status_file = "/proc/#{child_pid}/stat"
      expect(File.read(status_file).split[2]).to eq("Z") if File.exist?(status_file)
    end
  end

  it "shares one deadline between version and registry probes" do
    stub_const("#{described_class}::TIMEOUT", 0.8)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    context = probe(<<~RUBY)
      if ARGV == ["--version"]
        sleep 0.3
        puts "10.9.0"
      else
        sleep 0.6
        puts "https://registry.example.com"
      end
    RUBY

    expect(context).to eq("post-failure-package-manager-version" => "10.9.0")
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).to be < 1.5
  end

  it "stops collecting output once its memory limit is exceeded" do
    stub_const("#{described_class}::MAX_OUTPUT_BYTES", 100)
    expect(probe('puts "secret" * 100')).to eq({})
    expect(Dependabot.logger).to have_received(:warn)
      .with("Post-failure package manager probe exceeded its output limit").twice
  end
end
