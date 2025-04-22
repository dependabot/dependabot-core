# typed: strict
# frozen_string_literal: true

# Consolidated require statements
require "dependabot/bun/file_fetcher"
require "dependabot/bun/file_parser"
require "dependabot/bun/update_checker"
require "dependabot/bun/file_updater"
require "dependabot/bun/metadata_finder"
require "dependabot/bun/requirement"
require "dependabot/bun/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("bun", name: "javascript", colour: "168700")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "bun",
  lambda do |groups|
    return true if groups.empty?
    return true if groups.include?("optionalDependencies")

    groups.include?("dependencies")
  end
)

module Dependabot
  module Bun
    # Optimized regular expressions
    NODE_VERSION_NOT_SATISFY_REGEX = /The current Node version (?:v?\d+\.\d+\.\d+) does not satisfy the required version (?:v?\d+\.\d+\.\d+)\./.freeze

    # Used to check if package manager registry is public npm registry
    NPM_REGISTRY = "registry.npmjs.org".freeze

    # Used to check if url is http or https
    HTTP_CHECK_REGEX = %r{https?://}.freeze

    # Used to check capture url match in regex capture group
    URL_CAPTURE = "url".freeze

    # When package name contains package.json name cannot contain characters like empty string or @.
    INVALID_NAME_IN_PACKAGE_JSON = "Name contains illegal characters".freeze

    # Used to identify error messages indicating a package is missing, unreachable,
    # or there are network issues (e.g., ENOBUFS, ETIMEDOUT, registry down).
    PACKAGE_MISSING_REGEX = /(ENOBUFS|ETIMEDOUT|The registry may be down)/.freeze

    # Used to check if error message contains timeout fetching package
    TIMEOUT_FETCHING_PACKAGE_REGEX = %r{(?<url>.+)/(?<package>[^/]+): ETIMEDOUT}.freeze

    ESOCKETTIMEDOUT = /(?<package>.*?): ESOCKETTIMEDOUT/.freeze

    SOCKET_HANG_UP = /(?<url>.*?): socket hang up/.freeze

    # Misc errors
    EEXIST = /EEXIST: file already exists, mkdir '(?<regis>.*)'/.freeze

    # registry access errors
    REQUEST_ERROR_E403 = /Request "(?<url>.*)" returned a 403/.freeze # Forbidden access to the URL.
    AUTH_REQUIRED_ERROR = /(?<url>.*): authentication required/.freeze # Authentication is required for the URL.
    PERMISSION_DENIED = /(?<url>.*): Permission denied/.freeze # Lack of permission to access the URL.
    BAD_REQUEST = /(?<url>.*): bad_request/.freeze # Inconsistent request while accessing resource.
    INTERNAL_SERVER_ERROR = /Request failed "500 Internal Server Error"/.freeze # Server error response by remote registry.

    # Used to identify git unreachable error
    UNREACHABLE_GIT_CHECK_REGEX = /ls-remote --tags --heads (?<url>.*)/.freeze

    # Used to check if yarn workspace is enabled in non-private workspace
    ONLY_PRIVATE_WORKSPACE_TEXT = "Workspaces can only be enabled in priva".freeze

    # Used to identify local path error in yarn when installing sub-dependency
    SUB_DEP_LOCAL_PATH_TEXT = "refers to a non-existing file".freeze

    # Used to identify invalid package error when package is not found in registry
    INVALID_PACKAGE_REGEX = /Can't add "[\w\-.]+": invalid/.freeze

    # Used to identify error if package not found in registry
    PACKAGE_NOT_FOUND = "Couldn't find package".freeze
    PACKAGE_NOT_FOUND_PACKAGE_NAME_REGEX = /package "(?<package_req>.*?)"/.freeze
    PACKAGE_NOT_FOUND_PACKAGE_NAME_CAPTURE = "package_req".freeze
    PACKAGE_NOT_FOUND_PACKAGE_NAME_CAPTURE_SPLIT_REGEX = /(?<=\w)\@/.freeze

    YARN_PACKAGE_NOT_FOUND_CODE = /npm package "(?<dep>.*)" does not exist under owner "(?<regis>.*)"/.freeze
    YARN_PACKAGE_NOT_FOUND_CODE_1 = /Couldn't find package "[^@].*(?<dep>.*)" on the "(?<regis>.*)" registry./.freeze
    YARN_PACKAGE_NOT_FOUND_CODE_2 = /Couldn't find package "[^@].*(?<dep>.*)" required by "(?<pkg>.*)" on the "(?<regis>.*)" registry./.freeze # rubocop:disable Layout/LineLength

    PACKAGE_NOT_FOUND2 = %r{/[^/]+: Not found}.freeze
    PACKAGE_NOT_FOUND2_PACKAGE_NAME_REGEX = %r{/(?<package_name>[^/]+): Not found}.freeze
    PACKAGE_NOT_FOUND2_PACKAGE_NAME_CAPTURE = "package_name".freeze

    # Used to identify error if package not found in registry
    DEPENDENCY_VERSION_NOT_FOUND = "Couldn't find any versions".freeze
    DEPENDENCY_NOT_FOUND = ": Not found".freeze
    DEPENDENCY_MATCH_NOT_FOUND = "Couldn't find match for".freeze

    DEPENDENCY_NO_VERSION_FOUND = "Couldn't find any versions".freeze

    # Manifest not found
    MANIFEST_NOT_FOUND = /Cannot read properties of undefined \(reading '(?<file>.*)'\)/.freeze

    # Used to identify error if node_modules state file not resolved
    NODE_MODULES_STATE_FILE_NOT_FOUND = "Couldn't find the node_modules state file".freeze

    # Used to find error message in yarn error output
    YARN_USAGE_ERROR_TEXT = "Usage Error:".freeze

    # Used to identify error if tarball is not in network
    TARBALL_IS_NOT_IN_NETWORK = "Tarball is not in network and can not be located in cache".freeze

    # Used to identify if authentication failure error
    AUTHENTICATION_TOKEN_NOT_PROVIDED = "authentication token not provided".freeze
    AUTHENTICATION_IS_NOT_CONFIGURED = "No authentication configured for request".freeze
    AUTHENTICATION_HEADER_NOT_PROVIDED = "Unauthenticated: request did not include an Authorization header.".freeze

    # Used to identify if error message is related to yarn workspaces
    DEPENDENCY_FILE_NOT_RESOLVABLE = "conflicts with direct dependency".freeze

    ENV_VAR_NOT_RESOLVABLE = /Failed to replace env in config: \$\{(?<var>.*)\}/.freeze

    OUT_OF_DISKSPACE = / Out of diskspace/.freeze

    # registry returns malformed response
    REGISTRY_NOT_REACHABLE = /Received malformed response from registry for "(?<ver>.*)". The registry may be down./.freeze

    ## A type used for defining a proc that creates a new error object
    ErrorHandler = T.type_alias do
      T.proc
       .params(message: String, error: Dependabot::DependabotError, params: T::Hash[Symbol, T.untyped])
       .returns(Dependabot::DependabotError)
    end

    class Utils
      extend T::Sig

      # Cache for frequently used data
      @node_version_cache = T.let({}, T::Hash[String, T::Hash[Symbol, String]])

      sig { params(error_message: String).returns(T::Hash[Symbol, String]) }
      def self.extract_node_versions(error_message)
        return @node_version_cache[error_message] if @node_version_cache.key?(error_message)

        match_data = error_message.match(NODE_VERSION_NOT_SATISFY_REGEX)
        return {} unless match_data

        versions = {
          current_version: match_data[:current_version],
          required_version: match_data[:required_version]
        }
        @node_version_cache[error_message] = versions
        versions
      end

      sig { params(error_message: String).returns(String) }
      def self.extract_var(error_message)
        match_data = T.must(error_message.match(ENV_VAR_NOT_RESOLVABLE)).named_captures["var"]
        return "" unless match_data

        match_data
      end

      sig do
        params(
          error_message: String,
          dependencies: T::Array[Dependabot::Dependency],
          yarn_lock: Dependabot::DependencyFile
        ).returns(String)
      end
      def self.sanitize_resolvability_message(error_message, dependencies, yarn_lock)
        dependency_names = dependencies.map(&:name).join(", ")
        "Error whilst updating #{dependency_names} in #{yarn_lock.path}:\n#{error_message}"
      end
    end

    # Group of patterns to validate error message and raise specific error
    VALIDATION_GROUP_PATTERNS = T.let([
      {
        patterns: [INVALID_NAME_IN_PACKAGE_JSON],
        handler: lambda { |message, _error, _params|
          Dependabot::DependencyFileNotResolvable.new(message)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        # Check if sub dependency is using local path and raise a resolvability error
        patterns: [INVALID_PACKAGE_REGEX, SUB_DEP_LOCAL_PATH_TEXT],
        handler: lambda { |message, _error, params|
          Dependabot::DependencyFileNotResolvable.new(
            Utils.sanitize_resolvability_message(
              message,
              params[:dependencies],
              params[:yarn_lock]
            )
          )
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [NODE_MODULES_STATE_FILE_NOT_FOUND],
        handler: lambda { |message, _error, _params|
          Dependabot::MisconfiguredTooling.new("Yarn", message)
        },
        in_usage: true,
        matchfn: nil
      },
      {
        patterns: [TARBALL_IS_NOT_IN_NETWORK],
        handler: lambda { |message, _error, _params|
          Dependabot::DependencyFileNotResolvable.new(message)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [NODE_VERSION_NOT_SATISFY_REGEX],
        handler: lambda { |message, _error, _params|
          versions = Utils.extract_node_versions(message)
          current_version = versions[:current_version]
          required_version = versions[:required_version]

          return Dependabot::DependabotError.new(message) unless current_version && required_version

          Dependabot::ToolVersionNotSupported.new("Yarn", current_version, required_version)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [AUTHENTICATION_TOKEN_NOT_PROVIDED, AUTHENTICATION_IS_NOT_CONFIGURED,
                   AUTHENTICATION_HEADER_NOT_PROVIDED],
        handler: lambda { |message, _error, _params|
          Dependabot::PrivateSourceAuthenticationFailure.new(message)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [DEPENDENCY_FILE_NOT_RESOLVABLE],
        handler: lambda { |message, _error, _params|
          DependencyFileNotResolvable.new(message)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [ENV_VAR_NOT_RESOLVABLE],
        handler: lambda { |message, _error, _params|
          var = Utils.extract_var(message)

          Dependabot::MissingEnvironmentVariable.new(var, message)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [ONLY_PRIVATE_WORKSPACE_TEXT],
        handler: lambda { |message, _error, _params|
          Dependabot::DependencyFileNotEvaluatable.new(message)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [UNREACHABLE_GIT_CHECK_REGEX],
        handler: lambda { |message, _error, _params|
          dependency_url = message.match(UNREACHABLE_GIT_CHECK_REGEX).named_captures.fetch(URL_CAPTURE)

          Dependabot::GitDependenciesNotReachable.new(dependency_url)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [SOCKET_HANG_UP],
        handler: lambda { |message, _error, _params|
          url = message.match(SOCKET_HANG_UP).named_captures.fetch(URL_CAPTURE)

          Dependabot::PrivateSourceTimedOut.new(url.gsub(HTTP_CHECK_REGEX, ""))
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [ESOCKETTIMEDOUT],
        handler: lambda { |message, _error, _params|
          package_req = message.match(ESOCKETTIMEDOUT).named_captures.fetch("package")

          Dependabot::PrivateSourceTimedOut.new(package_req.gsub(HTTP_CHECK_REGEX, ""))
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [OUT_OF_DISKSPACE],
        handler: lambda { |message, _error, _params|
          Dependabot::OutOfDisk.new(message)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [YARN_PACKAGE_NOT_FOUND_CODE, YARN_PACKAGE_NOT_FOUND_CODE_1, YARN_PACKAGE_NOT_FOUND_CODE_2],
        handler: lambda { |message, _error, _params|
          msg = message.match(YARN_PACKAGE_NOT_FOUND_CODE) || message.match(YARN_PACKAGE_NOT_FOUND_CODE_1) ||
          message.match(YARN_PACKAGE_NOT_FOUND_CODE_2)

          Dependabot::DependencyFileNotResolvable.new(msg)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [REQUEST_ERROR_E403, AUTH_REQUIRED_ERROR, PERMISSION_DENIED, BAD_REQUEST],
        handler: lambda { |message, _error, _params|
          dependency_url = T.must(URI.decode_www_form_component(message).split("https://").last).split("/").first

          Dependabot::PrivateSourceAuthenticationFailure.new(dependency_url)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [MANIFEST_NOT_FOUND],
        handler: lambda { |message, _error, _params|
          msg = message.match(MANIFEST_NOT_FOUND)
          Dependabot::DependencyFileNotResolvable.new(msg)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [INTERNAL_SERVER_ERROR],
        handler: lambda { |message, _error, _params|
          msg = message.match(INTERNAL_SERVER_ERROR)
          Dependabot::DependencyFileNotResolvable.new(msg)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [REGISTRY_NOT_REACHABLE],
        handler: lambda { |message, _error, _params|
          msg = message.match(REGISTRY_NOT_REACHABLE)
          Dependabot::DependencyFileNotResolvable.new(msg)
        },
        in_usage: false,
        matchfn: nil
      }
    ].freeze, T::Array[{
      patterns: T::Array[T.any(String, Regexp)],
      handler: ErrorHandler,
      in_usage: T.nilable(T::Boolean),
      matchfn: T.nilable(T.proc.params(usage: String, message: String).returns(T::Boolean))
    }])
  end
end
