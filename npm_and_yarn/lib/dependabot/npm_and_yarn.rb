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

## A type used for defining a proc that creates a new error object
ErrorHandler = T.type_alias do
  T.proc
   .params(message: String, error: Dependabot::DependabotError, params: T::Hash[Symbol, T.untyped])
   .returns(Dependabot::DependabotError)
end

module Dependabot
  # rubocop:disable Metrics/ModuleLength
  module NpmAndYarn
    NODE_VERSION_NOT_SATISFY_REGEX = /The current Node version (?<current_version>v?\d+\.\d+\.\d+) does not satisfy the required version (?<required_version>v?\d+\.\d+\.\d+)\./ # rubocop:disable Layout/LineLength

    # Used to check if package manager registry is public npm registry
    NPM_REGISTRY = "registry.npmjs.org"

    # Used to check if url is http or https
    HTTP_CHECK_REGEX = %r{https?://}

    # Used to check capture url match in regex capture group
    URL_CAPTURE = "url"

    # When package name contains package.json name cannot contain characters like empty string or @.
    INVALID_NAME_IN_PACKAGE_JSON = "Name contains illegal characters"

    # Used to identify error messages indicating a package is missing, unreachable,
    # or there are network issues (e.g., ENOBUFS, ETIMEDOUT, registry down).
    PACKAGE_MISSING_REGEX = /(ENOBUFS|ETIMEDOUT|The registry may be down)/

    # Used to check if error message contains timeout fetching package
    TIMEOUT_FETCHING_PACKAGE_REGEX = %r{(?<url>.+)/(?<package>[^/]+): ETIMEDOUT}

    ESOCKETTIMEDOUT = /(?<package>.*?): ESOCKETTIMEDOUT/

    SOCKET_HANG_UP = /(?<url>.*?): socket hang up/

    # Misc errors
    EEXIST = /EEXIST: file already exists, mkdir '(?<regis>.*)'/

    # registry access errors
    REQUEST_ERROR_E403 = /Request "(?<url>.*)" returned a 403/ # Forbidden access to the URL.
    AUTH_REQUIRED_ERROR = /(?<url>.*): authentication required/ # Authentication is required for the URL.
    PERMISSION_DENIED = /(?<url>.*): Permission denied/ # Lack of permission to access the URL.
    BAD_REQUEST = /(?<url>.*): bad_request/ # Inconsistent request while accessing resource.
    INTERNAL_SERVER_ERROR = /Request failed "500 Internal Server Error"/ # Server error response by remote registry.

    # Used to identify git unreachable error
    UNREACHABLE_GIT_CHECK_REGEX = /ls-remote --tags --heads (?<url>.*)/

    # Used to check if yarn workspace is enabled in non-private workspace
    ONLY_PRIVATE_WORKSPACE_TEXT = "Workspaces can only be enabled in priva"

    # Used to identify local path error in yarn when installing sub-dependency
    SUB_DEP_LOCAL_PATH_TEXT = "refers to a non-existing file"

    # Used to identify invalid package error when package is not found in registry
    INVALID_PACKAGE_REGEX = /Can't add "[\w\-.]+": invalid/

    # Used to identify error if package not found in registry
    PACKAGE_NOT_FOUND = "Couldn't find package"
    PACKAGE_NOT_FOUND_PACKAGE_NAME_REGEX = /package "(?<package_req>.*?)"/
    PACKAGE_NOT_FOUND_PACKAGE_NAME_CAPTURE = "package_req"
    PACKAGE_NOT_FOUND_PACKAGE_NAME_CAPTURE_SPLIT_REGEX = /(?<=\w)\@/

    YARN_PACKAGE_NOT_FOUND_CODE = /npm package "(?<dep>.*)" does not exist under owner "(?<regis>.*)"/
    YARN_PACKAGE_NOT_FOUND_CODE_1 = /Couldn't find package "[^@].*(?<dep>.*)" on the "(?<regis>.*)" registry./
    YARN_PACKAGE_NOT_FOUND_CODE_2 = /Couldn't find package "[^@].*(?<dep>.*)" required by "(?<pkg>.*)" on the "(?<regis>.*)" registry./ # rubocop:disable Layout/LineLength

    YN0035 = T.let({
      PACKAGE_NOT_FOUND: %r{(?<package_req>@[\w-]+\/[\w-]+@\S+): Package not found},
      FAILED_TO_RETRIEVE: %r{(?<package_req>@[\w-]+\/[\w-]+@\S+): The remote server failed to provide the requested resource} # rubocop:disable Layout/LineLength
    }.freeze, T::Hash[String, Regexp])

    YN0082_PACKAGE_NOT_FOUND_REGEX = /YN0082:.*?(\S+@\S+): No candidates found/

    PACKAGE_NOT_FOUND2 = %r{/[^/]+: Not found}
    PACKAGE_NOT_FOUND2_PACKAGE_NAME_REGEX = %r{/(?<package_name>[^/]+): Not found}
    PACKAGE_NOT_FOUND2_PACKAGE_NAME_CAPTURE = "package_name"

    # Used to identify error if package not found in registry
    DEPENDENCY_VERSION_NOT_FOUND = "Couldn't find any versions"
    DEPENDENCY_NOT_FOUND = ": Not found"
    DEPENDENCY_MATCH_NOT_FOUND = "Couldn't find match for"

    DEPENDENCY_NO_VERSION_FOUND = "Couldn't find any versions"

    # Manifest not found
    MANIFEST_NOT_FOUND = /Cannot read properties of undefined \(reading '(?<file>.*)'\)/

    # Used to identify error if node_modules state file not resolved
    NODE_MODULES_STATE_FILE_NOT_FOUND = "Couldn't find the node_modules state file"

    # Used to find error message in yarn error output
    YARN_USAGE_ERROR_TEXT = "Usage Error:"

    # Used to identify error if tarball is not in network
    TARBALL_IS_NOT_IN_NETWORK = "Tarball is not in network and can not be located in cache"

    # Used to identify if authentication failure error
    AUTHENTICATION_TOKEN_NOT_PROVIDED = "authentication token not provided"
    AUTHENTICATION_IS_NOT_CONFIGURED = "No authentication configured for request"
    AUTHENTICATION_HEADER_NOT_PROVIDED = "Unauthenticated: request did not include an Authorization header."

    # Used to identify if error message is related to yarn workspaces
    DEPENDENCY_FILE_NOT_RESOLVABLE = "conflicts with direct dependency"

    ENV_VAR_NOT_RESOLVABLE = /Failed to replace env in config: \$\{(?<var>.*)\}/

    OUT_OF_DISKSPACE = / Out of diskspace/

    # yarnrc.yml errors
    YARNRC_PARSE_ERROR = /Parse error when loading (?<filename>.*?); /
    YARNRC_ENV_NOT_FOUND = /Usage Error: Environment variable not found /
    YARNRC_ENV_NOT_FOUND_REGEX = /Usage Error: Environment variable not found \((?<token>.*)\) in (?<filename>.*?) /
    YARNRC_EAI_AGAIN = /getaddrinfo EAI_AGAIN/
    YARNRC_ENOENT = /Internal Error: ENOENT/
    YARNRC_ENOENT_REGEX = /Internal Error: ENOENT: no such file or directory, stat '(?<filename>.*?)'/

    # if not package found with specified version
    YARN_PACKAGE_NOT_FOUND = /MessageError: Couldn't find any versions for "(?<pkg>.*?)" that matches "(?<ver>.*?)"/

    YN0001_DEPS_RESOLUTION_FAILED = T.let({
      DEPS_INCORRECT_MET: /peer dependencies are incorrectly met/
    }.freeze, T::Hash[String, Regexp])

    YN0001_FILE_NOT_RESOLVED_CODES = T.let({
      FIND_PACKAGE_LOCATION: /YN0001:(.*?)UsageError: Couldn't find the (?<pkg>.*) state file/,
      NO_CANDIDATE_FOUND: /YN0001:(.*?)Error: (?<pkg>.*): No candidates found/,
      NO_SUPPORTED_RESOLVER: /YN0001:(.*?)Error: (?<pkg>.*) isn't supported by any available resolver/,
      WORKSPACE_NOT_FOUND: /YN0001:(.*?)Error: (?<pkg>.*): Workspace not found/,
      ENOENT: /YN0001:(.*?)Thrown Error: (?<pkg>.*) ENOENT/,
      MANIFEST_NOT_FOUND: /YN0001:(.*?)Error: (?<pkg>.*): Manifest not found/,
      LIBZIP_ERROR: /YN0001:(.*?)Libzip Error: Failed to open the cache entry for (?<pkg>.*): Not a zip archive/
    }.freeze, T::Hash[String, Regexp])

    YN0001_AUTH_ERROR_CODES = T.let({
      AUTH_ERROR: /YN0001:*.*Fatal Error: could not read Username for '(?<url>.*)': terminal prompts disabled/
    }.freeze, T::Hash[String, Regexp])

    YN0001_REQ_NOT_FOUND_CODES = T.let({
      REQUIREMENT_NOT_SATISFIED: /provides (?<dep>.*)(.*?)with version (?<ver>.*), which doesn't satisfy what (?<pkg>.*) requests/, # rubocop:disable Layout/LineLength
      REQUIREMENT_NOT_PROVIDED: /(?<dep>.*)(.*?)doesn't provide (?<pkg>.*)(.*?), requested by (?<parent>.*)/
    }.freeze, T::Hash[String, Regexp])

    YN0001_INVALID_TYPE_ERRORS = T.let({
      INVALID_URL: /TypeError: (?<dep>.*): Invalid URL/
    }.freeze, T::Hash[String, Regexp])

    YN0086_DEPS_RESOLUTION_FAILED = /peer dependencies are incorrectly met/

    # registry returns malformed response
    REGISTRY_NOT_REACHABLE = /Received malformed response from registry for "(?<ver>.*)". The registry may be down./

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

    YARN_CODE_REGEX = /(YN\d{4})/
    YARN_ERROR_CODES = T.let({
      "YN0001" => {
        message: "Exception error",
        handler: lambda { |message, _error, _params|
          YN0001_FILE_NOT_RESOLVED_CODES.each do |(_yn0001_key, yn0001_regex)|
            if (msg = message.match(yn0001_regex))
              return Dependabot::DependencyFileNotResolvable.new(msg)
            end
          end

          YN0001_AUTH_ERROR_CODES.each do |(_yn0001_key, yn0001_regex)|
            if (msg = message.match(yn0001_regex))
              url = msg.named_captures.fetch(URL_CAPTURE)
              return Dependabot::PrivateSourceAuthenticationFailure.new(url)
            end
          end

          YN0001_REQ_NOT_FOUND_CODES.each do |(_yn0001_key, yn0001_regex)|
            if (msg = message.match(yn0001_regex))
              return Dependabot::DependencyFileNotResolvable.new(msg)
            end
          end

          YN0001_DEPS_RESOLUTION_FAILED.each do |(_yn0001_key, yn0001_regex)|
            if (msg = message.match(yn0001_regex))
              return Dependabot::DependencyFileNotResolvable.new(msg)
            end
          end

          YN0001_INVALID_TYPE_ERRORS.each do |(_yn0001_key, yn0001_regex)|
            if (msg = message.match(yn0001_regex))

              return Dependabot::DependencyFileNotResolvable.new(msg)
            end
          end

          Dependabot::DependabotError.new(message)
        }
      },
      "YN0002" => {
        message: "Missing peer dependency",
        handler: lambda { |message, _error, _params|
          Dependabot::DependencyFileNotResolvable.new(message)
        }
      },
      "YN0009" => {
        message: "Build Failed",
        handler: lambda { |message, _error, _params|
          Dependabot::DependencyFileNotResolvable.new(message)
        }
      },
      "YN0016" => {
        message: "Remote not found",
        handler: lambda { |message, _error, _params|
          Dependabot::GitDependenciesNotReachable.new(message)
        }
      },
      "YN0020" => {
        message: "Missing lockfile entry",
        handler: lambda { |message, _error, _params|
          Dependabot::DependencyFileNotFound.new(message)
        }
      },
      "YN0035" => {
        message: "Package not found",
        handler: lambda { |message, _error, _params|
          YN0035.each do |(_yn0035_key, yn0035_regex)|
            if (match_data = message.match(yn0035_regex)) && (package_req = match_data[:package_req])
              return Dependabot::DependencyNotFound.new(
                "#{package_req} Detail: #{message}"
              )
            end
          end
          Dependabot::DependencyNotFound.new(message)
        }
      },
      "YN0041" => {
        message: "Invalid authentication",
        handler: lambda { |message, _error, _params|
          url = T.must(URI.decode_www_form_component(message).split("https://").last).split("/").first
          Dependabot::PrivateSourceAuthenticationFailure.new(url)
        }
      },
      "YN0046" => {
        message: "Automerge failed to parse",
        handler: lambda { |message, _error, _params|
          Dependabot::MisconfiguredTooling.new("Yarn", message)
        }
      },
      "YN0047" => {
        message: "Automerge immutable",
        handler: lambda { |message, _error, _params|
          Dependabot::MisconfiguredTooling.new("Yarn", message)
        }
      },
      "YN0062" => {
        message: "Incompatible OS",
        handler: lambda { |message, _error, _params|
          Dependabot::DependabotError.new(message)
        }
      },
      "YN0063" => {
        message: "Incompatible CPU",
        handler: lambda { |message, _error, _params|
          Dependabot::IncompatibleCPU.new(message)
        }
      },
      "YN0068" => {
        message: "No matching package",
        handler: lambda { |message, _error, _params|
          Dependabot::DependencyFileNotResolvable.new(message)
        }
      },
      "YN0071" => {
        message: "NM can't install external soft link",
        handler: lambda { |message, _error, _params|
          Dependabot::MisconfiguredTooling.new("Yarn", message)
        }
      },
      "YN0072" => {
        message: "NM preserve symlinks required",
        handler: lambda { |message, _error, _params|
          Dependabot::MisconfiguredTooling.new("Yarn", message)
        }
      },
      "YN0075" => {
        message: "Prolog instantiation error",
        handler: lambda { |message, _error, _params|
          Dependabot::MisconfiguredTooling.new("Yarn", message)
        }
      },
      "YN0077" => {
        message: "Ghost architecture",
        handler: lambda { |message, _error, _params|
          Dependabot::MisconfiguredTooling.new("Yarn", message)
        }
      },
      "YN0080" => {
        message: "Network disabled",
        handler: lambda { |message, _error, _params|
          Dependabot::MisconfiguredTooling.new("Yarn", message)
        }
      },
      "YN0081" => {
        message: "Network unsafe HTTP",
        handler: lambda { |message, _error, _params|
          Dependabot::NetworkUnsafeHTTP.new(message)
        }
      },
      "YN0082" => {
        message: "No candidates found",
        handler: lambda { |message, _error, _params|
          match_data = message.match(YN0082_PACKAGE_NOT_FOUND_REGEX)
          if match_data
            package_req = match_data[1]
            Dependabot::DependencyNotFound.new("#{package_req} Detail: #{message}")
          else
            Dependabot::DependencyNotFound.new(message)
          end
        }
      },
      "YN0086" => {
        message: "deps resolution failed",
        handler: lambda { |message, _error, _params|
          msg = message.match(YN0086_DEPS_RESOLUTION_FAILED)
          Dependabot::DependencyFileNotResolvable.new(msg || message)
        }
      }
    }.freeze, T::Hash[String, {
      message: T.any(String, NilClass),
      handler: ErrorHandler
    }])

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
        patterns: [YARNRC_PARSE_ERROR],
        handler: lambda { |message, _error, _params|
          filename = message.match(YARNRC_PARSE_ERROR).named_captures["filename"]

          msg = "Error while loading \"#{filename.split('/').last}\"."
          Dependabot::DependencyFileNotResolvable.new(msg)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [YARNRC_ENV_NOT_FOUND],
        handler: lambda { |message, _error, _params|
          error_message = message.gsub(/[[:space:]]+/, " ").strip

          filename = error_message.match(YARNRC_ENV_NOT_FOUND_REGEX)
                                    .named_captures["filename"]

          env_var = error_message.match(YARNRC_ENV_NOT_FOUND_REGEX)
                                .named_captures["token"]

          msg = "Environment variable \"#{env_var}\" not found in \"#{filename.split('/').last}\"."
          Dependabot::MissingEnvironmentVariable.new(env_var, msg)
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [YARNRC_EAI_AGAIN],
        handler: lambda { |_message, _error, _params|
          Dependabot::DependencyFileNotResolvable.new("Network error while resolving dependency.")
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [YARNRC_ENOENT],
        handler: lambda { |message, _error, _params|
          error_message = message.gsub(/[[:space:]]+/, " ").strip
          filename = error_message.match(YARNRC_ENOENT_REGEX).named_captures["filename"]

          Dependabot::DependencyFileNotResolvable.new("Internal error while resolving dependency." \
                                                      "File not found \"#{filename.split('/').last}\"")
        },
        in_usage: false,
        matchfn: nil
      },
      {
        patterns: [YARN_PACKAGE_NOT_FOUND],
        handler: lambda { |message, _error, _params|
          package_name = message.match(YARN_PACKAGE_NOT_FOUND).named_captures["pkg"]
          version = message.match(YARN_PACKAGE_NOT_FOUND).named_captures["ver"]

          Dependabot::InconsistentRegistryResponse.new("Couldn't find any versions for \"#{package_name}\" that " \
                                                       "matches \"#{version}\"")
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
  # rubocop:enable Metrics/ModuleLength
end
