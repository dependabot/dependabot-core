# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module GoModules
    module ResolvabilityErrors
      extend T::Sig

      GITHUB_REPO_REGEX = %r{github.com/[^:@]*}

      sig { params(message: String, goprivate: T.untyped).void }
      def self.handle(message, goprivate:)
        # TODO: currently this matches last. Instead, if more than one match, and they
        # aren't identical, then don't try to be clever with GitDependenciesNotReachable
        # but instead raise DependencyFileNotResolvable and report the whole error.
        # This would have resulted in a more obvious error message for #4625
        mod_path = message.scan(GITHUB_REPO_REGEX).last
        if mod_path
          # TODO: if mod_path doesn't look like a URL, don't continue, but instead raise
          # DependencyFileNotResolvable and report the whole error.
          # This would have resulted in a more obvious error message for #4625
          # How to implement this though?
          # * Ruby has no built-in URL parsing, and no great alternatives in https://stackoverflow.com/q/1805761/770425...
          # Not sure what Dependabot team policy is on using 3rd-party gems?
          # Alternatively a basic sanity check of "it should not contain whitespace" may suffice for now... ??
        unless mod_path && message.include?("If this is a private repository")
          raise Dependabot::DependencyFileNotResolvable, message
        end

        # Module not found on github.com - query for _any_ version to know if it
        # doesn't exist (or is private) or we were just given a bad revision by this manifest
        SharedHelpers.in_a_temporary_directory do
          File.write("go.mod", "module dummy\n")

          mod_path = T.cast(mod_path, String)
          mod_split = mod_path.split("/")
          repo_path = if mod_split.size > 3
                        T.must(mod_split[0..2]).join("/")
                      else
                        mod_path
                      end

          env = { "GOPRIVATE" => goprivate }
          _, _, status = Open3.capture3(env, SharedHelpers.escape_command("go list -m -versions #{repo_path}"))
          raise Dependabot::DependencyFileNotResolvable, message if status.success?

          raise Dependabot::GitDependenciesNotReachable, [repo_path]
        end
      end
    end
  end
end
