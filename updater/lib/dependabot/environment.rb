# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Environment
    extend T::Sig
    extend T::Generic

    sig { returns(String) }
    def self.job_id
      @job_id ||= T.let(environment_variable("DEPENDABOT_JOB_ID"), T.nilable(String))
    end

    sig { returns(String) }
    def self.job_token
      @job_token ||= T.let(environment_variable("DEPENDABOT_JOB_TOKEN"), T.nilable(String))
    end

    sig { returns(T::Boolean) }
    def self.debug_enabled?
      @debug_enabled ||= T.let(job_debug_enabled? || environment_debug_enabled?, T.nilable(T::Boolean))
    end

    sig { returns(Symbol) }
    def self.log_level
      debug_enabled? ? :debug : :info
    end

    sig { returns(String) }
    def self.api_url
      @api_url ||= T.let(environment_variable("DEPENDABOT_API_URL", "http://localhost:3001"), T.nilable(String))
    end

    sig { returns(String) }
    def self.job_path
      @job_path ||= T.let(environment_variable("DEPENDABOT_JOB_PATH"), T.nilable(String))
    end

    sig { returns(String) }
    def self.output_path
      @output_path ||= T.let(environment_variable("DEPENDABOT_OUTPUT_PATH"), T.nilable(String))
    end

    sig { returns(T.nilable(String)) }
    def self.repo_contents_path
      @repo_contents_path ||= T.let(environment_variable("DEPENDABOT_REPO_CONTENTS_PATH", nil), T.nilable(String))
    end

    sig { returns(T::Boolean) }
    def self.github_actions?
      b = T.cast(environment_variable("GITHUB_ACTIONS", false), T::Boolean)
      @github_actions ||= T.let(b, T.nilable(T::Boolean))
    end

    sig { returns(T::Boolean) }
    def self.deterministic_updates?
      b = T.cast(environment_variable("UPDATER_DETERMINISTIC", false), T::Boolean)
      @deterministic_updates ||= T.let(b, T.nilable(T::Boolean))
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def self.job_definition
      @job_definition ||= T.let(JSON.parse(File.read(job_path)), T.nilable(T::Hash[String, T.untyped]))
    end

    sig do
      type_parameters(:T)
        .params(variable_name: String, default: T.any(Symbol, T.type_parameter(:T)))
        .returns(T.any(String, T.type_parameter(:T)))
    end
    private_class_method def self.environment_variable(variable_name, default = :_undefined)
      case default
      when :_undefined
        ENV.fetch(variable_name) do
          raise ArgumentError, "Missing environment variable #{variable_name}"
        end
      else
        val = ENV.fetch(variable_name, default)
        case val
        when String
          val = val.casecmp("true") || val === 1 if [true, false, 1, 0].include? default
        end
        T.cast(val, T.type_parameter(:T))
      end
    end

    sig { returns(T::Boolean) }
    private_class_method def self.job_debug_enabled?
      !!job_definition.dig("job", "debug")
    end

    sig { returns(T::Boolean) }
    private_class_method def self.environment_debug_enabled?
      !!environment_variable("DEPENDABOT_DEBUG", false)
    end
  end
end
