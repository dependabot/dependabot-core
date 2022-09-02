# frozen_string_literal: true

require "dependabot/utils"

module Dependabot
  class DependabotError < StandardError
    BASIC_AUTH_REGEX = %r{://(?<auth>[^:]*:[^@%\s]+(@|%40))}.freeze
    # Remove any path segment from fury.io sources
    FURY_IO_PATH_REGEX = %r{fury\.io/(?<path>.+)}.freeze

    def initialize(message = nil)
      super(sanitize_message(message))
    end

    private

    def sanitize_message(message)
      return message unless message.is_a?(String)

      path_regex =
        Regexp.escape(Utils::BUMP_TMP_DIR_PATH) + "\/" +
        Regexp.escape(Utils::BUMP_TMP_FILE_PREFIX) + "[a-zA-Z0-9-]*"

      message = message.gsub(/#{path_regex}/, "dependabot_tmp_dir").strip
      filter_sensitive_data(message)
    end

    def filter_sensitive_data(message)
      replace_capture_groups(message, BASIC_AUTH_REGEX, "")
    end

    def sanitize_source(source)
      source = filter_sensitive_data(source)
      replace_capture_groups(source, FURY_IO_PATH_REGEX, "<redacted>")
    end

    def replace_capture_groups(string, regex, replacement)
      return string unless string.is_a?(String)

      string.scan(regex).flatten.compact.reduce(string) do |original_msg, match|
        original_msg.gsub(match, replacement)
      end
    end
  end

  class OutOfDisk < DependabotError; end

  class OutOfMemory < DependabotError; end

  class NotImplemented < DependabotError; end

  #####################
  # Repo level errors #
  #####################

  class BranchNotFound < DependabotError
    attr_reader :branch_name

    def initialize(branch_name, msg = nil)
      @branch_name = branch_name
      super(msg)
    end
  end

  class RepoNotFound < DependabotError
    attr_reader :source

    def initialize(source, msg = nil)
      @source = source
      super(msg)
    end
  end

  #####################
  # File level errors #
  #####################

  class DependencyFileNotFound < DependabotError
    attr_reader :file_path

    def initialize(file_path, msg = nil)
      @file_path = file_path
      super(msg)
    end

    def file_name
      file_path.split("/").last
    end

    def directory
      # Directory should always start with a `/`
      file_path.split("/")[0..-2].join("/").sub(%r{^/*}, "/")
    end
  end

  class DependencyFileNotParseable < DependabotError
    attr_reader :file_path

    def initialize(file_path, msg = nil)
      @file_path = file_path
      super(msg)
    end

    def file_name
      file_path.split("/").last
    end

    def directory
      # Directory should always start with a `/`
      file_path.split("/")[0..-2].join("/").sub(%r{^/*}, "/")
    end
  end

  class DependencyFileNotEvaluatable < DependabotError; end

  class DependencyFileNotResolvable < DependabotError; end

  #######################
  # Source level errors #
  #######################

  class PrivateSourceAuthenticationFailure < DependabotError
    attr_reader :source

    def initialize(source)
      @source = sanitize_source(source)
      msg = "The following source could not be reached as it requires " \
            "authentication (and any provided details were invalid or lacked " \
            "the required permissions): #{@source}"
      super(msg)
    end
  end

  class PrivateSourceTimedOut < DependabotError
    attr_reader :source

    def initialize(source)
      @source = sanitize_source(source)
      super("The following source timed out: #{@source}")
    end
  end

  class PrivateSourceCertificateFailure < DependabotError
    attr_reader :source

    def initialize(source)
      @source = sanitize_source(source)
      super("Could not verify the SSL certificate for #{@source}")
    end
  end

  class MissingEnvironmentVariable < DependabotError
    attr_reader :environment_variable

    def initialize(environment_variable)
      @environment_variable = environment_variable
      super("Missing environment variable #{@environment_variable}")
    end
  end

  # Useful for JS file updaters, where the registry API sometimes returns
  # different results to the actual update process
  class InconsistentRegistryResponse < DependabotError; end

  ###########################
  # Dependency level errors #
  ###########################

  class GitDependenciesNotReachable < DependabotError
    attr_reader :dependency_urls

    def initialize(*dependency_urls)
      @dependency_urls =
        dependency_urls.flatten.map { |uri| filter_sensitive_data(uri) }

      msg = "The following git URLs could not be retrieved: " \
            "#{@dependency_urls.join(', ')}"
      super(msg)
    end
  end

  class GitDependencyReferenceNotFound < DependabotError
    attr_reader :dependency

    def initialize(dependency)
      @dependency = dependency

      msg = "The branch or reference specified for #{@dependency} could not " \
            "be retrieved"
      super(msg)
    end
  end

  class PathDependenciesNotReachable < DependabotError
    attr_reader :dependencies

    def initialize(*dependencies)
      @dependencies = dependencies.flatten
      msg = "The following path based dependencies could not be retrieved: " \
            "#{@dependencies.join(', ')}"
      super(msg)
    end
  end

  class GoModulePathMismatch < DependabotError
    attr_reader :go_mod, :declared_path, :discovered_path

    def initialize(go_mod, declared_path, discovered_path)
      @go_mod = go_mod
      @declared_path = declared_path
      @discovered_path = discovered_path

      msg = "The module path '#{@declared_path}' found in #{@go_mod} doesn't " \
            "match the actual path '#{@discovered_path}' in the dependency's " \
            "go.mod"
      super(msg)
    end
  end

  # Raised by UpdateChecker if all candidate updates are ignored
  class AllVersionsIgnored < DependabotError; end

  # Raised by FileParser if processing may execute external code in the update context
  class UnexpectedExternalCode < DependabotError; end
end
