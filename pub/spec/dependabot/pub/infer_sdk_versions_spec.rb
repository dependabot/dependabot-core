# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pub/helpers"
require "webrick"

RSpec.describe "Helpers" do
  let(:dev_null) { WEBrick::Log.new("/dev/null", 7) }
  let(:inferred_result) do
    Dependabot::Pub::Helpers.run_infer_sdk_versions \
      File.join("spec", "fixtures", "projects", project), url: "http://localhost:#{server[:Port]}/flutter_releases.json"
  end
  let(:server) { WEBrick::HTTPServer.new({ Port: 0, AccessLog: [], Logger: dev_null }) }

  before do
    # Because we do the networking in infer_sdk_versions we have to run an
    # actual web server.
    Thread.new do
      server.start
    end
    server.mount_proc "/flutter_releases.json" do |_req, res|
      res.body = File.read(File.join(__dir__, "..", "..", "fixtures", "flutter_releases.json"))
    end
  end

  after do
    server.shutdown
  end

  describe "Will resolve to latest beta if needed" do
    let(:project) { "requires_latest_beta" }

    it "Finds a matching beta" do
      expect(inferred_result["flutter"]).to eq "3.25.0-0.1.pre"
      expect(inferred_result["channel"]).to eq "beta"
    end
  end

  describe "pinned on a beta-release" do
    let(:project) { "requires_old_beta" }

    it "Finds a matching beta" do
      expect(inferred_result["flutter"]).to eq "2.13.0-0.4.pre"
      expect(inferred_result["channel"]).to eq "beta"
    end
  end

  describe "Uses newest stable if allowed" do
    let(:project) { "allows_latest_stable" }

    it "Finds a matching stable" do
      expect(inferred_result["flutter"]).to eq "3.24.1"
      expect(inferred_result["channel"]).to eq "stable"
    end
  end

  describe "The dart constraint is taken into account" do
    let(:project) { "requires_dart_2_15" }

    it "Finds a matching beta" do
      expect(inferred_result["dart"]).to eq "2.15.1"
      expect(inferred_result["channel"]).to eq "stable"
    end
  end
end
