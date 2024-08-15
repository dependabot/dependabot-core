# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/utils"

module Dependabot
  extend T::Sig

  module ErrorAttributes
    BACKTRACE         = "error-backtrace"
    CLASS             = "error-class"
    DETAILS           = "error-details"
    FINGERPRINT       = "fingerprint"
    MESSAGE           = "error-message"
    DEPENDENCIES      = "job-dependencies"
    DEPENDENCY_GROUPS = "job-dependency-groups"
    JOB_ID            = "job-id"
    PACKAGE_MANAGER   = "package-manager"
    SECURITY_UPDATE   = "security-update"
  end

  # rubocop:disable Metrics/MethodLength
  sig { params(error: StandardError).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.fetcher_error_details(error)
    case error
    when Dependabot::ToolVersionNotSupported
      {
        "error-type": "tool_version_not_supported",
        "error-detail": {
          "tool-name": error.tool_name,
          "detected-version": error.detected_version,
          "supported-versions": error.supported_versions
        }
      }
    when Dependabot::BranchNotFound
      {
        "error-type": "branch_not_found",
        "error-detail": { "branch-name": error.branch_name }
      }
    when Dependabot::DirectoryNotFound
      {
        "error-type": "directory_not_found",
        "error-detail": { "directory-name": error.directory_name }
      }
    when Dependabot::RepoNotFound
      # This happens if the repo gets removed after a job gets kicked off.
      # This also happens when a configured personal access token is not authz'd to fetch files from the job repo.
      {
        "error-type": "job_repo_not_found",
        "error-detail": { message: error.message }
      }
    when Dependabot::DependencyFileNotParseable
      {
        "error-type": "dependency_file_not_parseable",
        "error-detail": {
          message: error.message,
          "file-path": error.file_path
        }
      }
    when Dependabot::DependencyFileNotFound
      {
        "error-type": "dependency_file_not_found",
        "error-detail": {
          message: error.message,
          "file-path": error.file_path
        }
      }
    when Dependabot::OutOfDisk
      {
        "error-type": "out_of_disk",
        "error-detail": {}
      }
    when Dependabot::PathDependenciesNotReachable
      {
        "error-type": "path_dependencies_not_reachable",
        "error-detail": { dependencies: error.dependencies }
      }
    when Octokit::Unauthorized
      { "error-type": "octokit_unauthorized" }
    when Octokit::ServerError
      # If we get a 500 from GitHub there's very little we can do about it,
      # and responsibility for fixing it is on them, not us. As a result we
      # quietly log these as errors
      { "error-type": "server_error" }
    when *Octokit::RATE_LIMITED_ERRORS
      # If we get a rate-limited error we let dependabot-api handle the
      # retry by re-enqueing the update job after the reset
      {
        "error-type": "octokit_rate_limited",
        "error-detail": {
          "rate-limit-reset": T.cast(error, Octokit::Error).response_headers["X-RateLimit-Reset"]
        }
      }
    end
  end

  sig { params(error: StandardError).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.parser_error_details(error)
    case error
    when Dependabot::DependencyFileNotEvaluatable
      {
        "error-type": "dependency_file_not_evaluatable",
        "error-detail": { message: error.message }
      }
    when Dependabot::DependencyFileNotResolvable
      {
        "error-type": "dependency_file_not_resolvable",
        "error-detail": { message: error.message }
      }
    when Dependabot::BranchNotFound
      {
        "error-type": "branch_not_found",
        "error-detail": { "branch-name": error.branch_name }
      }
    when Dependabot::DependencyFileNotParseable
      {
        "error-type": "dependency_file_not_parseable",
        "error-detail": {
          message: error.message,
          "file-path": error.file_path
        }
      }
    when Dependabot::DependencyFileNotFound
      {
        "error-type": "dependency_file_not_found",
        "error-detail": {
          message: error.message,
          "file-path": error.file_path
        }
      }
    when Dependabot::PathDependenciesNotReachable
      {
        "error-type": "path_dependencies_not_reachable",
        "error-detail": { dependencies: error.dependencies }
      }
    when Dependabot::PrivateSourceAuthenticationFailure
      {
        "error-type": "private_source_authentication_failure",
        "error-detail": { source: error.source }
      }
    when Dependabot::GitDependenciesNotReachable
      {
        "error-type": "git_dependencies_not_reachable",
        "error-detail": { "dependency-urls": error.dependency_urls }
      }
    when Dependabot::NotImplemented
      {
        "error-type": "not_implemented",
        "error-detail": {
          message: error.message
        }
      }
    when Octokit::ServerError
      # If we get a 500 from GitHub there's very little we can do about it,
      # and responsibility for fixing it is on them, not us. As a result we
      # quietly log these as errors
      { "error-type": "server_error" }
    end
  end

  # rubocop:disable Lint/RedundantCopDisableDirective
  # rubocop:disable Metrics/CyclomaticComplexity
  sig { params(error: StandardError).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.updater_error_details(error)
    case error
    when Dependabot::DependencyFileNotResolvable
      {
        "error-type": "dependency_file_not_resolvable",
        "error-detail": { message: error.message }
      }
    when Dependabot::DependencyFileNotEvaluatable
      {
        "error-type": "dependency_file_not_evaluatable",
        "error-detail": { message: error.message }
      }
    when Dependabot::GitDependenciesNotReachable
      {
        "error-type": "git_dependencies_not_reachable",
        "error-detail": { "dependency-urls": error.dependency_urls }
      }
    when Dependabot::ToolVersionNotSupported
      {
        "error-type": "tool_version_not_supported",
        "error-detail": {
          "tool-name": error.tool_name,
          "detected-version": error.detected_version,
          "supported-versions": error.supported_versions
        }
      }
    when Dependabot::MisconfiguredTooling
      {
        "error-type": "misconfigured_tooling",
        "error-detail": { "tool-name": error.tool_name, message: error.tool_message }
      }
    when Dependabot::GitDependencyReferenceNotFound
      {
        "error-type": "git_dependency_reference_not_found",
        "error-detail": { dependency: error.dependency }
      }
    when Dependabot::PrivateSourceAuthenticationFailure
      {
        "error-type": "private_source_authentication_failure",
        "error-detail": { source: error.source }
      }
    when Dependabot::DependencyNotFound
      {
        "error-type": "dependency_not_found",
        "error-detail": { source: error.source }
      }
    when Dependabot::PrivateSourceTimedOut
      {
        "error-type": "private_source_timed_out",
        "error-detail": { source: error.source }
      }
    when Dependabot::PrivateSourceCertificateFailure
      {
        "error-type": "private_source_certificate_failure",
        "error-detail": { source: error.source }
      }
    when Dependabot::MissingEnvironmentVariable
      {
        "error-type": "missing_environment_variable",
        "error-detail": {
          "environment-variable": error.environment_variable,
          "error-message": error.message
        }
      }
    when Dependabot::OutOfDisk
      {
        "error-type": "out_of_disk",
        "error-detail": {}
      }
    when Dependabot::GoModulePathMismatch
      {
        "error-type": "go_module_path_mismatch",
        "error-detail": {
          "declared-path": error.declared_path,
          "discovered-path": error.discovered_path,
          "go-mod": error.go_mod
        }
      }
    when BadRequirementError
      {
        "error-type": "illformed_requirement",
        "error-detail": { message: error.message }
      }
    when
      IncompatibleCPU,
      NetworkUnsafeHTTP
      error.detail

    when Dependabot::NotImplemented
      {
        "error-type": "not_implemented",
        "error-detail": {
          message: error.message
        }
      }
    when Dependabot::InvalidGitAuthToken
      {
        "error-type": "git_token_auth_error",
        "error-detail": { message: error.message }
      }
    when *Octokit::RATE_LIMITED_ERRORS
      # If we get a rate-limited error we let dependabot-api handle the
      # retry by re-enqueing the update job after the reset
      {
        "error-type": "octokit_rate_limited",
        "error-detail": {
          "rate-limit-reset": T.cast(error, Octokit::Error).response_headers["X-RateLimit-Reset"]
        }
      }
    end
  end
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Metrics/CyclomaticComplexity
  # rubocop:enable Lint/RedundantCopDisableDirective

  class DependabotError < StandardError
    extend T::Sig

    BASIC_AUTH_REGEX = %r{://(?<auth>[^:@]*:[^@%\s/]+(@|%40))}
    # Remove any path segment from fury.io sources
    FURY_IO_PATH_REGEX = %r{fury\.io/(?<path>.+)}

    sig { params(message: T.any(T.nilable(String), MatchData)).void }
    def initialize(message = nil)
      super(sanitize_message(message))
    end

    private

    sig { params(message: T.any(T.nilable(String), MatchData)).returns(T.any(T.nilable(String), MatchData)) }
    def sanitize_message(message)
      return message unless message.is_a?(String)

      path_regex =
        Regexp.escape(Utils::BUMP_TMP_DIR_PATH) + "\\/" +
        Regexp.escape(Utils::BUMP_TMP_FILE_PREFIX) + "[a-zA-Z0-9-]*"

      message = message.gsub(/#{path_regex}/, "dependabot_tmp_dir").strip
      filter_sensitive_data(message)
    end

    sig { params(message: String).returns(String) }
    def filter_sensitive_data(message)
      replace_capture_groups(message, BASIC_AUTH_REGEX, "")
    end

    sig { params(source: String).returns(String) }
    def sanitize_source(source)
      source = filter_sensitive_data(source)
      replace_capture_groups(source, FURY_IO_PATH_REGEX, "<redacted>")
    end

    sig do
      params(
        string: String,
        regex: Regexp,
        replacement: String
      ).returns(String)
    end
    def replace_capture_groups(string, regex, replacement)
      string.scan(regex).flatten.compact.reduce(string) do |original_msg, match|
        original_msg.gsub(match, replacement)
      end
    end
  end

  class TypedDependabotError < Dependabot::DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :error_type

    sig { params(error_type: String, message: T.any(T.nilable(String), MatchData)).void }
    def initialize(error_type, message = nil)
      @error_type = T.let(error_type, String)

      super(message || error_type)
    end

    sig { params(hash: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Hash[Symbol, T.untyped]) }
    def detail(hash = nil)
      {
        "error-type": error_type,
        "error-detail": hash || {
          message: message
        }
      }
    end
  end

  class OutOfDisk < DependabotError; end

  class OutOfMemory < DependabotError; end

  class NotImplemented < DependabotError; end

  class InvalidGitAuthToken < DependabotError; end

  #####################
  # Repo level errors #
  #####################

  class DirectoryNotFound < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :directory_name

    sig { params(directory_name: String, msg: T.nilable(String)).void }
    def initialize(directory_name, msg = nil)
      @directory_name = directory_name
      super(msg)
    end
  end

  class BranchNotFound < DependabotError
    extend T::Sig

    sig { returns(T.nilable(String)) }
    attr_reader :branch_name

    sig { params(branch_name: T.nilable(String), msg: T.nilable(String)).void }
    def initialize(branch_name, msg = nil)
      @branch_name = branch_name
      super(msg)
    end
  end

  class RepoNotFound < DependabotError
    extend T::Sig

    sig { returns(T.any(Dependabot::Source, String)) }
    attr_reader :source

    sig { params(source: T.any(Dependabot::Source, String), msg: T.nilable(String)).void }
    def initialize(source, msg = nil)
      @source = source
      super(msg)
    end
  end

  #####################
  # File level errors #
  #####################

  class MisconfiguredTooling < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :tool_name

    sig { returns(String) }
    attr_reader :tool_message

    sig do
      params(
        tool_name: String,
        tool_message: String
      ).void
    end
    def initialize(tool_name, tool_message)
      @tool_name = tool_name
      @tool_message = tool_message

      msg = "Dependabot detected that #{tool_name} is misconfigured in this repository. " \
            "Running `#{tool_name.downcase}` results in the following error: #{tool_message}"
      super(msg)
    end
  end

  class ToolVersionNotSupported < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :tool_name

    sig { returns(String) }
    attr_reader :detected_version

    sig { returns(String) }
    attr_reader :supported_versions

    sig do
      params(
        tool_name: String,
        detected_version: String,
        supported_versions: String
      ).void
    end
    def initialize(tool_name, detected_version, supported_versions)
      @tool_name = tool_name
      @detected_version = detected_version
      @supported_versions = supported_versions

      msg = "Dependabot detected the following #{tool_name} requirement for your project: '#{detected_version}'." \
            "\n\nCurrently, the following #{tool_name} versions are supported in Dependabot: #{supported_versions}."
      super(msg)
    end
  end

  class DependencyFileNotFound < DependabotError
    extend T::Sig

    sig { returns(T.nilable(String)) }
    attr_reader :file_path

    sig { params(file_path: T.nilable(String), msg: T.nilable(String)).void }
    def initialize(file_path, msg = nil)
      @file_path = file_path
      super(msg || "#{file_path} not found")
    end

    sig { returns(T.nilable(String)) }
    def file_name
      return unless file_path

      T.must(file_path).split("/").last
    end

    sig { returns(T.nilable(String)) }
    def directory
      # Directory should always start with a `/`
      return unless file_path

      T.must(T.must(file_path).split("/")[0..-2]).join("/").sub(%r{^/*}, "/")
    end
  end

  class DependencyFileNotParseable < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :file_path

    sig { params(file_path: String, msg: T.nilable(String)).void }
    def initialize(file_path, msg = nil)
      @file_path = file_path
      super(msg || "#{file_path} not parseable")
    end

    sig { returns(String) }
    def file_name
      T.must(file_path.split("/").last)
    end

    sig { returns(String) }
    def directory
      # Directory should always start with a `/`
      T.must(file_path.split("/")[0..-2]).join("/").sub(%r{^/*}, "/")
    end
  end

  class DependencyFileNotEvaluatable < DependabotError; end

  class DependencyFileNotResolvable < DependabotError; end

  class BadRequirementError < Gem::Requirement::BadRequirementError; end

  #######################
  # Source level errors #
  #######################

  class PrivateSourceAuthenticationFailure < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :source

    sig { params(source: T.nilable(String)).void }
    def initialize(source)
      @source = T.let(sanitize_source(T.must(source)), String)
      msg = "The following source could not be reached as it requires " \
            "authentication (and any provided details were invalid or lacked " \
            "the required permissions): #{@source}"
      super(msg)
    end
  end

  class PrivateSourceTimedOut < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :source

    sig { params(source: String).void }
    def initialize(source)
      @source = T.let(sanitize_source(source), String)
      super("The following source timed out: #{@source}")
    end
  end

  class PrivateSourceCertificateFailure < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :source

    sig { params(source: String).void }
    def initialize(source)
      @source = T.let(sanitize_source(source), String)
      super("Could not verify the SSL certificate for #{@source}")
    end
  end

  class MissingEnvironmentVariable < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :environment_variable

    sig { returns(String) }
    attr_reader :message

    sig { params(environment_variable: String, message: String).void }
    def initialize(environment_variable, message = "")
      @environment_variable = environment_variable
      @message = message

      super("Missing environment variable #{@environment_variable}. #{@message}")
    end
  end

  class DependencyNotFound < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :source

    sig { params(source: T.nilable(String)).void }
    def initialize(source)
      @source = T.let(sanitize_source(T.must(source)), String)
      msg = "The following dependency could not be found : #{@source}"
      super(msg)
    end
  end

  class InvalidGitAuthToken < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :source

    sig { params(source: String).void }
    def initialize(source)
      @source = T.let(sanitize_source(source), String)
      msg = "Missing or invalid authentication token while accessing github package : #{@source}"
      super(msg)
    end
  end

  # Useful for JS file updaters, where the registry API sometimes returns
  # different results to the actual update process
  class InconsistentRegistryResponse < DependabotError; end

  ###########################
  # Dependency level errors #
  ###########################

  class GitDependenciesNotReachable < DependabotError
    extend T::Sig

    sig { returns(T::Array[String]) }
    attr_reader :dependency_urls

    sig { params(dependency_urls: T.any(String, T::Array[String])).void }
    def initialize(*dependency_urls)
      @dependency_urls =
        T.let(dependency_urls.flatten.map { |uri| filter_sensitive_data(uri) }, T::Array[String])

      msg = "The following git URLs could not be retrieved: " \
            "#{@dependency_urls.join(', ')}"
      super(msg)
    end
  end

  class GitDependencyReferenceNotFound < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :dependency

    sig { params(dependency: String).void }
    def initialize(dependency)
      @dependency = dependency

      msg = "The branch or reference specified for #{@dependency} could not " \
            "be retrieved"
      super(msg)
    end
  end

  class PathDependenciesNotReachable < DependabotError
    extend T::Sig

    sig { returns(T::Array[String]) }
    attr_reader :dependencies

    sig { params(dependencies: T.any(String, T::Array[String])).void }
    def initialize(*dependencies)
      @dependencies = T.let(dependencies.flatten, T::Array[String])
      msg = "The following path based dependencies could not be retrieved: " \
            "#{@dependencies.join(', ')}"
      super(msg)
    end
  end

  class GoModulePathMismatch < DependabotError
    extend T::Sig

    sig { returns(String) }
    attr_reader :go_mod

    sig { returns(String) }
    attr_reader :declared_path

    sig { returns(String) }
    attr_reader :discovered_path

    sig { params(go_mod: String, declared_path: String, discovered_path: String).void }
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

  class IncompatibleCPU < TypedDependabotError
    sig { params(message: T.any(T.nilable(String), MatchData)).void }
    def initialize(message = nil)
      super("incompatible_cpu", message)
    end
  end

  class NetworkUnsafeHTTP < TypedDependabotError
    sig { params(message: T.any(T.nilable(String), MatchData)).void }
    def initialize(message = nil)
      super("network_unsafe_http", message)
    end
  end
end
