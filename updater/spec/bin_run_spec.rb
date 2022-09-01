# frozen_string_literal: true

require "json"
require "spec_helper"

RSpec.describe "bin/run" do
  describe "fetch_files" do
    before do
      ENV["DEPENDABOT_JOB_ID"] = "1"
      ENV["DEPENDABOT_JOB_TOKEN"] = "token"
      ENV["DEPENDABOT_JOB_PATH"] =
        "spec/fixtures/jobs/job_with_credentials.json"
      ENV["DEPENDABOT_OUTPUT_PATH"] = File.join(Dir.mktmpdir, "output.json")
      ENV["DEPENDABOT_API_URL"] = "http://example.com"
    end

    after do
      ENV["DEPENDABOT_JOB_ID"] = nil
      ENV["DEPENDABOT_JOB_TOKEN"] = nil
      ENV["DEPENDABOT_JOB_PATH"] = nil
      ENV["DEPENDABOT_API_URL"] = nil
    end

    it "completes the job successfully and persists the files" do
      result = `bin/run fetch_files`
      expect(result).to include("Starting job processing")
      expect(result).to include("Finished job processing")
      job_output = JSON.parse(File.read(ENV.fetch("DEPENDABOT_OUTPUT_PATH", nil)))
      expect(job_output.fetch("base64_dependency_files").length).to eq(1)
    end
  end
end
