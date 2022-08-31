# frozen_string_literal: true

module Dependabot
  module Environment
    def self.job_id
      @job_id ||= environment_variable("DEPENDABOT_JOB_ID")
    end

    def self.token
      @token ||= environment_variable("DEPENDABOT_JOB_TOKEN")
    end

    def self.api_url
      default = "http://localhost:3001"
      @api_url ||= environment_variable("DEPENDABOT_API_URL", default)
    end

    def self.job_path
      @job_path ||= environment_variable("DEPENDABOT_JOB_PATH")
    end

    def self.output_path
      @output_path ||= environment_variable("DEPENDABOT_OUTPUT_PATH")
    end

    def self.repo_contents_path
      @repo_contents_path ||= environment_variable("DEPENDABOT_REPO_CONTENTS_PATH", nil)
    end

    def self.github_actions?
      @github_actions ||= environment_variable("GITHUB_ACTIONS", false)
    end

    def self.environment_variable(variable_name, default = :_undefined)
      return ENV.fetch(variable_name, default) unless default == :_undefined

      ENV.fetch(variable_name) do
        raise ArgumentError, "Missing environment variable #{variable_name}"
      end
    end

    private_class_method :environment_variable
  end
end
