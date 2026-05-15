# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module GoModules
    module ResolvabilityErrors
      extend T::Sig

      GITHUB_REPO_REGEX = T.let(%r{github.com/[^:@ '\n]*}, Regexp)
      INSECURE_PROTOCOL_REPOSITORY_REGEX = T.let(
        /go(?: get)?: .*: no secure protocol found for repository/m,
        Regexp
      )
      GO_MODULE_WITH_VERSION_REGEX = T.let(/go(?: get)?:\s*(?<module>[^\s@]+)@/, Regexp)
      GO_PREFIXED_HOSTED_REPO_REGEX = T.let(
        %r{(?:^|\n)\s*go(?: get)?:\s*(?<repo>[a-z0-9.-]+\.[a-z]{2,}/[^:@\s]+)(?:[:\s]|$)}i,
        Regexp
      )
      REACHABILITY_CHECK_HINTS = T.let(
        [
          /If this is a private repository/i,
          /Write access to repository not granted/i,
          /Authentication failed/i
        ].freeze,
        T::Array[Regexp]
      )

      sig { params(message: String).void }
      def self.handle(message)
        mod_path = extract_module_path(message)

        if mod_path && insecure_protocol_repo_error?(message)
          raise Dependabot::GitDependenciesNotReachable, [repo_path_for(mod_path)]
        end

        raise Dependabot::DependencyFileNotResolvable, message unless mod_path && requires_reachability_check?(message)

        # Module not found in the module repository (e.g., GitHub, Gerrit) - query for _any_ version
        # to know if it doesn't exist (or is private) or we were just given a bad revision by this manifest
        SharedHelpers.in_a_temporary_directory do
          File.write("go.mod", "module dummy\n")

          repo_path = repo_path_for(mod_path)

          _, _, status = Open3.capture3(SharedHelpers.escape_command("go list -m -versions #{repo_path}"))
          raise Dependabot::DependencyFileNotResolvable, message if status.success?

          raise Dependabot::GitDependenciesNotReachable, [repo_path]
        end
      end

      sig { params(message: String).returns(T.nilable(String)) }
      def self.extract_module_path(message)
        github_repo_paths = T.let(
          message.scan(GITHUB_REPO_REGEX).filter_map do |match|
            next match if match.is_a?(String)

            match.first
          end,
          T::Array[String]
        )
        return github_repo_paths.last&.delete_suffix("/") if github_repo_paths.any?

        module_with_version_match = message.match(GO_MODULE_WITH_VERSION_REGEX)
        return module_with_version_match[:module] if module_with_version_match

        hosted_repo_match = message.match(GO_PREFIXED_HOSTED_REPO_REGEX)
        return hosted_repo_match[:repo] if hosted_repo_match

        nil
      end

      sig { params(message: String).returns(T::Boolean) }
      def self.requires_reachability_check?(message)
        REACHABILITY_CHECK_HINTS.any? { |regex| message.match?(regex) }
      end

      sig { params(message: String).returns(T::Boolean) }
      def self.insecure_protocol_repo_error?(message)
        message.match?(INSECURE_PROTOCOL_REPOSITORY_REGEX)
      end

      sig { params(mod_path: String).returns(String) }
      def self.repo_path_for(mod_path)
        normalized_mod_path = mod_path.delete_suffix("/")
        mod_split = normalized_mod_path.split("/")
        return normalized_mod_path unless mod_split.first == "github.com" && mod_split.size > 3

        T.must(mod_split[0..2]).join("/")
      end
    end
  end
end
