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
    YARN_CODE_REGEX = /(YN\d{4})/
    YARN_ERROR_CODES = T.let({
      "YN0001" => { message: "Exception error", error_class: Dependabot::DependabotError },
      "YN0002" => { message: "Missing peer dependency", error_class: Dependabot::DependencyFileNotResolvable },
      "YN0016" => { message: "Remote not found", error_class: Dependabot::GitDependenciesNotReachable },
      "YN0020" => { message: "Missing lockfile entry", error_class: Dependabot::DependencyFileNotFound },
      "YN0046" => { message: "Automerge failed to parse", error_class: Dependabot::AutoMergeParseFailure },
      "YN0047" => { message: "Automerge immutable", error_class: AutoMergeImmutable },
      "YN0062" => { message: "Incompatible OS", error_class: Dependabot::IncompatibleOS },
      "YN0063" => { message: "Incompatible CPU", error_class: Dependabot::IncompatibleCPU },
      "YN0071" => { message: "NM can't install external soft link", error_class: Dependabot::NMExternalSoftLink },
      "YN0072" => { message: "NM preserve symlinks required", error_class: Dependabot::NMPreserveSymlinksRequired },
      "YN0075" => { message: "Prolog instantiation error", error_class: Dependabot::PrologInstantiationError },
      "YN0077" => { message: "Ghost architecture", error_class: Dependabot::GhostArchitecture },
      "YN0080" => { message: "Network disabled", error_class: Dependabot::NetworkDisabled },
      "YN0081" => { message: "Network unsafe HTTP", error_class: Dependabot::NetworkUnsafeHTTP }
    }.freeze, T::Hash[String, { message: String, error_class: T.class_of(Dependabot::DependabotError) }])

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

    # Finding errors such as "The current Node version 20.15.1 does not satisfy the required version 20.11.0"
    NODE_VERSION_NOT_SATISFY_REGEX = /The current .*Node.* version.*does not satisfy the required version/

    # Used to identify if authentication failure error
    AUTHENTICATION_TOKEN_NOT_PROVIDED = "authentication token not provided"
    AUTHENTICATION_IS_NOT_CONFIGURED = "No authentication configured for request"

    # Used to identify if error message is related to yarn workspaces
    DEPENDENCY_CONFLICT = "conflicts with direct dependency"

    # Group of patterns to validate error message and raise specific error
    VALIDATION_GROUP_PATTERNS = T.let([
      {
        patterns: [NODE_MODULES_STATE_FILE_NOT_FOUND],
        error_class: Dependabot::StateFileNotFound,
        in_usage: true,
        matchfn: nil
      },
      {
        patterns: [TARBALL_IS_NOT_IN_NETWORK],
        error_class: Dependabot::DependencyFileNotResolvable,
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [NODE_VERSION_NOT_SATISFY_REGEX],
        error_class: Dependabot::RequiredVersionIsNotSatisfied,
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [AUTHENTICATION_TOKEN_NOT_PROVIDED, AUTHENTICATION_IS_NOT_CONFIGURED],
        error_class: Dependabot::PrivateSourceAuthenticationFailure,
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [DEPENDENCY_CONFLICT],
        error_class: Dependabot::DependencyConflict,
        in_usage: false,
        matchfn: nil
      }
    ].freeze, T::Array[{
      patterns: T::Array[T.any(String, Regexp)],
      error_class: T.class_of(Dependabot::DependabotError),
      in_usage: T.nilable(T::Boolean),
      matchfn: T.nilable(T.proc.params(usage: String, message: String).returns(T::Boolean))
    }])
  end
end
