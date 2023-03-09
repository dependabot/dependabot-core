# frozen_string_literal: true

require "spec_helper"

require "dependabot/environment"

RSpec.describe Dependabot::Environment do
  subject(:environment) { described_class }

  describe "::debug_enabled?" do
    after do
      # Reset the memoisation after each test
      environment.remove_instance_variable(:@debug_enabled)
    end

    it "is false by default" do
      allow(environment).to receive(:job_definition).and_return({})
      allow(ENV).to receive(:fetch).with("DEPENDABOT_DEBUG", false).and_return(false)

      expect(environment).not_to be_debug_enabled
    end

    it "is true if enabled in ENV" do
      allow(environment).to receive(:job_definition).and_return({})
      allow(ENV).to receive(:fetch).with("DEPENDABOT_DEBUG", false).and_return("true")

      expect(environment).to be_debug_enabled
    end

    it "is true if enabled in the job definition" do
      allow(environment).to receive(:job_definition).and_return({
        "job" => { "debug" => true }
      })
      allow(ENV).to receive(:fetch).with("DEPENDABOT_DEBUG", false).and_return(false)

      expect(environment).to be_debug_enabled
    end
  end
end
