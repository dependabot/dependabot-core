# typed: false
# frozen_string_literal: true

require "open3"
require "spec_helper"
require "tmpdir"

class RunScript
  def initialize(script_path:, updater_root:, environment:)
    @script_path = script_path
    @updater_root = updater_root
    @environment = environment
  end

  def call(command, environment = {})
    Open3.capture3(@environment.merge(environment), @script_path, command, chdir: @updater_root)
  end
end

RSpec.describe RunScript do
  let(:updater_root) { File.expand_path("../..", __dir__) }
  let(:script_path) { File.join(updater_root, "bin/run") }
  let(:run_script) { described_class.new(script_path:, updater_root:, environment:) }
  let(:environment) { { "PATH" => "#{bin_directory}:#{ENV.fetch('PATH')}" } }
  let(:bin_directory) { Dir.mktmpdir }

  before do
    bundle_path = File.join(bin_directory, "bundle")
    File.write(bundle_path, "#!/bin/sh\nprintf 'bundle %s\\n' \"$*\"\n")
    FileUtils.chmod(0o755, bundle_path)
  end

  after { FileUtils.rm_rf(bin_directory) }

  it "keeps fetch_files as a no-op by default" do
    stdout, stderr, status = run_script.call("fetch_files")

    expect(status).to be_success
    expect(stderr).to be_empty
    expect(stdout).to include("fetch_files command is disabled")
    expect(stdout).not_to include("bundle exec")
  end

  it "runs fetch_files when the feature flag is enabled" do
    stdout, stderr, status = run_script.call(
      "fetch_files",
      "DEPENDABOT_ENABLE_FETCH_FILES_COMMAND" => "true"
    )

    expect(status).to be_success
    expect(stderr).to be_empty
    expect(stdout).to eq("bundle exec ruby bin/fetch_files.rb\n")
  end
end
