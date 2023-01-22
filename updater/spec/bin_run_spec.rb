# frozen_string_literal: true

require "json"
require "spec_helper"

RSpec.describe "bin/run" do
  describe "fetch_files" do
    around do |example|
      Dir.mktmpdir do |tempdir|
        output_path = File.join(tempdir, "output.json")
        job_path = File.join(tempdir, "job.json")

        job_info = JSON.parse(File.read("spec/fixtures/jobs/job_with_credentials.json"))
        job_info["credentials"][0]["password"] = test_access_token

        File.write(job_path, JSON.dump(job_info))

        ENV["DEPENDABOT_JOB_ID"] = "1"
        ENV["DEPENDABOT_JOB_TOKEN"] = "token"
        ENV["DEPENDABOT_JOB_PATH"] = job_path
        ENV["DEPENDABOT_OUTPUT_PATH"] = output_path
        ENV["DEPENDABOT_API_URL"] = "http://example.com"

        example.run
      ensure
        ENV["DEPENDABOT_JOB_ID"] = nil
        ENV["DEPENDABOT_JOB_TOKEN"] = nil
        ENV["DEPENDABOT_JOB_PATH"] = nil
        ENV["DEPENDABOT_OUTPUT_PATH"] = nil
        ENV["DEPENDABOT_API_URL"] = nil
      end
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
