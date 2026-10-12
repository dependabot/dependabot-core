# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "time"

require "dependabot/logger"
require "dependabot/shared_helpers"

require "dependabot/vcpkg"
require "dependabot/vcpkg/version"

module Dependabot
  module Vcpkg
    module Package
      # Reads the vcpkg registry's versions database from the checkout the updater image ships.
      #
      # `versions/<letter>-/<port>.json` lists every published version of a port, newest first,
      # along with the scheme it was published under. `versions/baseline.json` at a given commit
      # gives the version floor that commit sets for every port.
      #
      # See https://learn.microsoft.com/vcpkg/users/versioning.concepts#acquiring-port-versions
      class VersionsDatabase
        extend T::Sig

        class PortVersion < T::Struct
          const :version, Dependabot::Vcpkg::Version
          const :scheme, String
          const :git_tree, T.nilable(String)
        end

        sig { params(repository_path: String).void }
        def initialize(repository_path: Vcpkg.repository_path)
          @repository_path = repository_path
          @port_versions = T.let({}, T::Hash[String, T::Array[PortVersion]])
          @baselines = T.let({}, T::Hash[String, T::Hash[String, Dependabot::Vcpkg::Version]])
          @release_dates = T.let({}, T::Hash[String, T::Hash[String, Time]])
          @release_tags = T.let(nil, T.nilable(T::Array[String]))
          @registry_ref = T.let(nil, T.nilable(String))
          @fetched = T.let(false, T::Boolean)
        end

        sig { returns(String) }
        attr_reader :repository_path

        sig { returns(T::Boolean) }
        def available?
          File.directory?(File.join(repository_path, ".git"))
        end

        # Every published version of a port, newest first.
        sig { params(port: String).returns(T::Array[PortVersion]) }
        def versions_for(port)
          @port_versions[port] ||= read_port_versions(port)
        end

        # The version floor `ref` sets for `port`, or nil when the port did not exist there.
        sig { params(port: String, ref: String).returns(T.nilable(Dependabot::Vcpkg::Version)) }
        def baseline_version_for(port:, ref:)
          baseline_versions(ref)[port]
        end

        sig { params(ref: String).returns(T::Hash[String, Dependabot::Vcpkg::Version]) }
        def baseline_versions(ref)
          @baselines[ref] ||= read_baseline_versions(ref)
        end

        # vcpkg's release tags, oldest first.
        sig { returns(T::Array[String]) }
        def release_tags
          @release_tags ||= read_release_tags
        end

        # When each version of a port was published, keyed by the version's git-tree. The versions
        # database records no dates, so they come from the commit that added each entry.
        sig { params(port: String).returns(T::Hash[String, Time]) }
        def release_dates_for(port)
          @release_dates[port] ||= read_release_dates(port)
        end

        sig { params(ref: String).returns(T.nilable(String)) }
        def commit_sha_for(ref)
          run_git("rev-list", "-n", "1", ref)&.strip
        end

        # Whether `descendant` contains `ancestor`, used to make sure a baseline is only ever
        # moved forwards.
        sig { params(ancestor: String, descendant: String).returns(T::Boolean) }
        def ancestor?(ancestor:, descendant:)
          fetch_registry
          return false unless available?

          Dependabot::SharedHelpers.run_shell_command(
            "git merge-base --is-ancestor #{ancestor} #{descendant}",
            cwd: repository_path
          )
          true
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed
          false
        end

        # The ref the versions database is read from. Prefers the fetched remote branch so a fix
        # published after the image was built is still visible.
        sig { returns(String) }
        def registry_ref
          @registry_ref ||= begin
            remote_ref = "origin/#{VCPKG_DEFAULT_BASELINE_DEFAULT_BRANCH}"
            ref_exists?(remote_ref) ? remote_ref : "HEAD"
          end
        end

        COMMIT_HEADER_PATTERN = /\A[0-9a-f]{40}\t(?<date>\S+)\z/
        ADDED_GIT_TREE_PATTERN = /\A\+\s*"git-tree":\s*"(?<git_tree>[0-9a-f]{40})"/

        private

        sig { params(port: String).returns(T::Array[PortVersion]) }
        def read_port_versions(port)
          content = show(registry_ref, port_versions_path(port))
          return [] unless content

          parsed = JSON.parse(content)
          entries = parsed.is_a?(Hash) ? parsed["versions"] : nil
          return [] unless entries.is_a?(Array)

          entries.filter_map { |entry| build_port_version(entry) }
        rescue JSON::ParserError => e
          Dependabot.logger.warn("Failed to parse the vcpkg versions database for #{port}: #{e.message}")
          []
        end

        sig { params(entry: Object).returns(T.nilable(PortVersion)) }
        def build_port_version(entry)
          return nil unless entry.is_a?(Hash)

          scheme = VCPKG_VERSION_SCHEME_KEYS.find { |key| entry[key].is_a?(String) }
          return nil unless scheme

          text = entry.fetch(scheme)
          port_version = entry["port-version"].to_i
          version_string = port_version.zero? ? text : "#{text}##{port_version}"
          return nil unless Dependabot::Vcpkg::Version.correct?(version_string)

          PortVersion.new(
            version: Dependabot::Vcpkg::Version.new(version_string),
            scheme: scheme,
            git_tree: entry["git-tree"]
          )
        end

        sig { params(ref: String).returns(T::Hash[String, Dependabot::Vcpkg::Version]) }
        def read_baseline_versions(ref)
          content = show(ref, VCPKG_BASELINE_DATABASE_PATH)
          return {} unless content

          parsed = JSON.parse(content)
          entries = parsed.is_a?(Hash) ? parsed["default"] : nil
          return {} unless entries.is_a?(Hash)

          entries.each_with_object({}) do |(port, entry), baselines|
            version = baseline_version(entry)
            baselines[port] = version if version
          end
        rescue JSON::ParserError => e
          Dependabot.logger.warn("Failed to parse the vcpkg baseline at #{ref}: #{e.message}")
          {}
        end

        sig { params(entry: Object).returns(T.nilable(Dependabot::Vcpkg::Version)) }
        def baseline_version(entry)
          return nil unless entry.is_a?(Hash)

          text = entry["baseline"]
          return nil unless text.is_a?(String)

          port_version = entry["port-version"].to_i
          version_string = port_version.zero? ? text : "#{text}##{port_version}"
          return nil unless Dependabot::Vcpkg::Version.correct?(version_string)

          Dependabot::Vcpkg::Version.new(version_string)
        end

        sig { returns(T::Array[String]) }
        def read_release_tags
          # A release published since the image was built only appears once the registry is
          # fetched, and a security fix may well be carried by it.
          fetch_registry
          output = run_git("tag", "--list")
          return [] unless output

          output
            .lines
            .map(&:strip)
            .select { |tag| VCPKG_RELEASE_TAG_PATTERN.match?(tag) }
            .sort_by { |tag| Dependabot::Vcpkg::Version.new(tag.delete_prefix("v")) }
        end

        sig { params(port: String).returns(String) }
        def port_versions_path(port)
          File.join(VCPKG_VERSIONS_DIRECTORY, "#{port[0].to_s.downcase}-", "#{port}.json")
        end

        sig { params(port: String).returns(T::Hash[String, Time]) }
        def read_release_dates(port)
          # `run_shell_command` splits the command on whitespace, so the format cannot contain a
          # literal space. The walk has to start from the same ref the versions themselves are read
          # from, or an entry published since the image was built gets no date and skips cooldown.
          log_arguments = [
            "log", "--format=tformat:%H%x09%cI", "--patch", "--unified=0",
            registry_ref, "--", port_versions_path(port)
          ]
          output = run_git(*log_arguments)
          return {} unless output

          current_date = T.let(nil, T.nilable(Time))
          # `git log` walks newest first, so later assignments are older commits and win.
          output.lines.each_with_object({}) do |line, dates|
            line = line.chomp
            if (header = COMMIT_HEADER_PATTERN.match(line))
              current_date = parse_time(header[:date])
            elsif (added = ADDED_GIT_TREE_PATTERN.match(line)) && current_date
              dates[added[:git_tree]] = current_date
            end
          end
        end

        sig { params(value: T.nilable(String)).returns(T.nilable(Time)) }
        def parse_time(value)
          return nil unless value

          Time.parse(value)
        rescue ArgumentError
          nil
        end

        sig { params(ref: String, path: String).returns(T.nilable(String)) }
        def show(ref, path)
          fetch_registry
          run_git("show", "#{ref}:#{path}")
        end

        sig { params(ref: String).returns(T::Boolean) }
        def ref_exists?(ref)
          fetch_registry
          !run_git("rev-parse", "--verify", "--quiet", ref).nil?
        end

        # The image's checkout is frozen at build time, so refs published since then are only
        # reachable after a fetch. A failure here is not fatal: whatever is already local still
        # answers most questions.
        sig { void }
        def fetch_registry
          return if @fetched

          @fetched = true
          return unless available?

          run_git("fetch", "--quiet", "--tags", "--force", "origin")
        end

        sig { params(arguments: String).returns(T.nilable(String)) }
        def run_git(*arguments)
          return nil unless available?

          Dependabot::SharedHelpers.run_shell_command(
            ["git", *arguments].join(" "),
            cwd: repository_path
          )
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
          Dependabot.logger.debug("git #{arguments.join(' ')} failed in #{repository_path}: #{e.message}")
          nil
        end
      end
    end
  end
end
