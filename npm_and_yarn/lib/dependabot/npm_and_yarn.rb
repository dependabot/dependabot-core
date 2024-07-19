# typed: strict
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/npm_and_yarn/file_fetcher"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/update_checker"
require "dependabot/npm_and_yarn/file_updater"
require "dependabot/npm_and_yarn/metadata_finder"
require "dependabot/npm_and_yarn/requirement"
require "dependabot/npm_and_yarn/version"

require "dependabot/pull_request_creator/labeler"
Dependabot::PullRequestCreator::Labeler
  .register_label_details("npm_and_yarn", name: "javascript", colour: "168700")

require "dependabot/dependency"
Dependabot::Dependency.register_production_check(
  "npm_and_yarn",
  lambda do |groups|
    return true if groups.empty?
    return true if groups.include?("optionalDependencies")

    groups.include?("dependencies")
  end
)

module Dependabot
  module NpmAndYarn
    NODE_VERSION_NOT_SATISFY_REGEX = /The current Node version (?<current_version>v?\d+\.\d+\.\d+) does not satisfy the required version (?<required_version>v?\d+\.\d+\.\d+)\./ # rubocop:disable Layout/LineLength

    # Used to check if package manager registry is public npm registry
    NPM_REGISTRY = "registry.npmjs.org"

    # Used to check if url is http or https
    HTTP_CHECK_REGEX = %r{https?://}

    # Error message when a package.json name include invalid characters
    INVALID_NAME_IN_PACKAGE_JSON = "Name contains illegal characters"

    # Used to identify error messages indicating a package is missing, unreachable,
    # or there are network issues (e.g., ENOBUFS, ETIMEDOUT, registry down).
    PACKAGE_MISSING_REGEX = /(ENOBUFS|ETIMEDOUT|The registry may be down)/

    # Used to check if error message contains timeout fetching package
    TIMEOUT_FETCHING_PACKAGE_REGEX = %r{(?<url>.+)/(?<package>[^/]+): ETIMEDOUT}

    # Used to identify git unreachable error
    UNREACHABLE_GIT_CHECK_REGEX = /ls-remote --tags --heads (?<url>.*)/

    # Used to check if yarn workspace is enabled in non-private workspace
    ONLY_PRIVATE_WORKSPACE_TEXT = "Workspaces can only be enabled in priva"

    # Used to identify local path error in yarn when installing sub-dependency
    SUB_DEP_LOCAL_PATH_TEXT = "refers to a non-existing file"

    # Used to identify invalid package error when package is not found in registry
    INVALID_PACKAGE_REGEX = /Can't add "(?<package_req>.*)": invalid/

    # Used to identify error if node_modules state file not resolved
    NODE_MODULES_STATE_FILE_NOT_FOUND = "Couldn't find the node_modules state file"

    # Used to find error message in yarn error output
    YARN_USAGE_ERROR_TEXT = "Usage Error:"

    # Used to identify error if tarball is not in network
    TARBALL_IS_NOT_IN_NETWORK = "Tarball is not in network and can not be located in cache"

    # Used to identify if authentication failure error
    AUTHENTICATION_TOKEN_NOT_PROVIDED = "authentication token not provided"
    AUTHENTICATION_IS_NOT_CONFIGURED = "No authentication configured for request"

    # Used to identify if error message is related to yarn workspaces
    DEPENDENCY_FILE_NOT_RESOLVABLE = "conflicts with direct dependency"

    ENV_VAR_NOT_RESOLVABLE = /Failed to replace env in config: \$\{(?<var>.*)\}/

    class Utils
      extend T::Sig

      sig { params(error_message: String).returns(T::Hash[Symbol, String]) }
      def self.extract_node_versions(error_message)
        match_data = error_message.match(NODE_VERSION_NOT_SATISFY_REGEX)
        return {} unless match_data

        {
          current_version: match_data[:current_version],
          required_version: match_data[:required_version]
        }
      end

      sig { params(error_message: String).returns(String) }
      def self.extract_var(error_message)
        match_data = T.must(error_message.match(ENV_VAR_NOT_RESOLVABLE)).named_captures["var"]
        return "" unless match_data

        match_data
      end
    end

    YARN_CODE_REGEX = /(YN\d{4})/
    YARN_ERROR_CODES = T.let({
      "YN0001" => {
        message: "Exception error",
        new_error: ->(_error, message) { Dependabot::DependabotError.new(message) }
      },
      "YN0002" => {
        message: "Missing peer dependency",
        new_error: ->(_error, message) { Dependabot::DependencyFileNotResolvable.new(message) }
      },
      "YN0016" => {
        message: "Remote not found",
        new_error: ->(_error, message) { Dependabot::GitDependenciesNotReachable.new(message) }
      },
      "YN0020" => {
        message: "Missing lockfile entry",
        new_error: ->(_error, message) { Dependabot::DependencyFileNotFound.new(message) }
      },
      "YN0046" => {
        message: "Automerge failed to parse",
        new_error: ->(_error, message) { Dependabot::MisconfiguredTooling.new("Yarn", message) }
      },
      "YN0047" => {
        message: "Automerge immutable",
        new_error: ->(_error, message) { Dependabot::MisconfiguredTooling.new("Yarn", message) }
      },
      "YN0062" => {
        message: "Incompatible OS",
        new_error: ->(_error, message) { Dependabot::DependabotError.new(message) }
      },
      "YN0063" => {
        message: "Incompatible CPU",
        new_error: ->(_error, message) { Dependabot::IncompatibleCPU.new(message) }
      },
      "YN0071" => {
        message: "NM can't install external soft link",
        new_error: ->(_error, message) { Dependabot::MisconfiguredTooling.new("Yarn", message) }
      },
      "YN0072" => {
        message: "NM preserve symlinks required",
        new_error: ->(_error, message) { Dependabot::MisconfiguredTooling.new("Yarn", message) }
      },
      "YN0075" => {
        message: "Prolog instantiation error",
        new_error: ->(_error, message) { Dependabot::MisconfiguredTooling.new("Yarn", message) }
      },
      "YN0077" => {
        message: "Ghost architecture",
        new_error: ->(_error, message) { Dependabot::MisconfiguredTooling.new("Yarn", message) }
      },
      "YN0080" => {
        message: "Network disabled",
        new_error: ->(_error, message) { Dependabot::MisconfiguredTooling.new("Yarn", message) }
      },
      "YN0081" => {
        message: "Network unsafe HTTP",
        new_error: ->(_error, message) { Dependabot::NetworkUnsafeHTTP.new(message) }
      }
    }.freeze, T::Hash[String, {
      message: T.any(String, NilClass),
      new_error: T.proc.params(error: Dependabot::DependabotError, message: String).returns(Dependabot::DependabotError)
    }])

    # Group of patterns to validate error message and raise specific error
    VALIDATION_GROUP_PATTERNS = T.let([
      {
        patterns: [NODE_MODULES_STATE_FILE_NOT_FOUND],
        new_error: ->(_error, message) { Dependabot::MisconfiguredTooling.new("Yarn", message) },
        in_usage: true,
        matchfn: nil
      },
      {
        patterns: [TARBALL_IS_NOT_IN_NETWORK],
        new_error: ->(_error, message) { Dependabot::DependencyFileNotResolvable.new(message) },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [NODE_VERSION_NOT_SATISFY_REGEX],
        new_error: lambda { |_error, message|
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
        patterns: [AUTHENTICATION_TOKEN_NOT_PROVIDED, AUTHENTICATION_IS_NOT_CONFIGURED],
        new_error: ->(_error, message) { Dependabot::PrivateSourceAuthenticationFailure.new(message) },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [DEPENDENCY_FILE_NOT_RESOLVABLE],
        new_error: ->(_error, message) { DependencyFileNotResolvable.new(message) },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [ENV_VAR_NOT_RESOLVABLE],
        new_error: lambda { |_error, message|
          var = Utils.extract_var(message)
          Dependabot::MissingEnvironmentVariable.new(var, message)
        },
        in_usage: false,
        matchfn: nil
      }
    ].freeze, T::Array[{
      patterns: T::Array[T.any(String, Regexp)],
      new_error: T.proc.params(error: Dependabot::DependabotError,
                               message: String).returns(Dependabot::DependabotError),
      in_usage: T.nilable(T::Boolean),
      matchfn: T.nilable(T.proc.params(usage: String, message: String).returns(T::Boolean))
    }])
  end
end
