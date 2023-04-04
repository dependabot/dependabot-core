# frozen_string_literal: true

module Dependabot
  module Environment
    def self.job_id
      @job_id ||= environment_variable("DEPENDABOT_JOB_ID")
    end

    def self.job_token
      @job_token ||= environment_variable("DEPENDABOT_JOB_TOKEN")
    end

    def self.debug_enabled?
      @debug_enabled ||= job_debug_enabled? || environment_debug_enabled?
    end

    def self.log_level
      debug_enabled? ? :debug : :info
    end

    def self.api_url
      @api_url ||= environment_variable("DEPENDABOT_API_URL", "http://localhost:3001")
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

    def self.deterministic_updates?
      @deterministic_updates ||= environment_variable("UPDATER_DETERMINISTIC", false)
    end

    def self.job_definition
      @job_definition ||= JSON.parse(File.read(job_path))
    end

    private_class_method def self.environment_variable(variable_name, default = :_undefined)
      return ENV.fetch(variable_name, default) unless default == :_undefined

      ENV.fetch(variable_name) do
        raise ArgumentError, "Missing environment variable #{variable_name}"
      end
    end

    private_class_method def self.job_debug_enabled?
      !!job_definition.dig("job", "debug")
    end

    private_class_method def self.environment_debug_enabled?
      !!environment_variable("DEPENDABOT_DEBUG", false)
    end
  end
end
