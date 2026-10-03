# typed: strong
# frozen_string_literal: true

require "yaml"
require "dependabot/errors"
require "dependabot/experiments"
require "dependabot/bun/file_parser"
require "dependabot/bun/bun_package_manager"
require "dependabot/bun/helpers"
require "sorbet-runtime"

module Dependabot
  module Bun
    class FileParser < Dependabot::FileParsers::Base
      class BunLock
        extend T::Sig

        require_relative "bun_lock/record"
        require_relative "bun_lock/workspace"
        require_relative "bun_lock/dependency_type_resolver"

        DEVELOPMENT_SECTIONS = %w(devDependencies).freeze

        sig { params(dependency_file: DependencyFile).void }
        def initialize(dependency_file)
          @dependency_file = dependency_file
          @parsed = T.let(nil, T.nilable(T::Hash[Object, Object]))
          @records = T.let(nil, T.nilable(T::Hash[String, Record]))
          @workspaces = T.let(nil, T.nilable(T::Array[Workspace]))
          @production_by_key_for = T.let(nil, T.nilable(T::Hash[String, T::Boolean]))
        end

        sig { returns(T::Hash[Object, Object]) }
        def parsed
          @parsed ||= begin
            content = parse_document
            version = content["lockfileVersion"]
            raise_invalid!("expected 'lockfileVersion' to be an integer") unless version.is_a?(Integer)
            raise_invalid!("expected 'lockfileVersion' to be >= 0") unless version >= 0
            raise_unsupported_lockfile_version!(version) if
              version > BunPackageManager::MAX_SUPPORTED_LOCKFILE_VERSION

            # configVersion was introduced in Bun v1.3.2 to control install behavior.
            # When present, it must be preserved or Bun will use different install defaults.
            # See https://bun.sh/blog/bun-v1.3.2#lockfile-configversion-stabilizes-install-defaults
            if content.key?("configVersion")
              config_version = content["configVersion"]
              unless config_version.is_a?(Integer) && config_version >= 0
                raise_invalid!("expected 'configVersion' to be a non-negative integer")
              end
            end

            content
          end
        end
        private :parsed

        sig { returns(T.nilable(T::Hash[String, Record])) }
        def records
          return @records if @records

          packages = parsed["packages"]
          return unless packages.is_a?(Hash)

          @records = packages.to_h do |raw_key, value|
            key = T.cast(raw_key, Object)
            raise_invalid!("expected package keys to be strings") unless key.is_a?(String)

            [key, Record.new(T.cast(value, Object), path: @dependency_file.path, context: "packages.#{key}")]
          end
        end

        # The roots of the dependency graph, one per entry in the "workspaces" object.
        # Malformed entries are skipped rather than reported, because only dependency
        # type classification reads them.
        sig { returns(T::Array[Workspace]) }
        def workspaces
          @workspaces ||= parse_workspaces
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependencies
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          # bun.lock v0 format:
          # https://github.com/oven-sh/bun/blob/c130df6c589fdf28f9f3c7f23ed9901140bc9349/src/install/bun.lock.zig#L595-L605

          packages = records
          raise_invalid!("expected 'packages' to be an object") unless packages

          production_by_key = production_by_key_for(packages)

          packages.each do |key, record|
            name = record.name
            next if name.empty?

            semver = record.version
            next unless semver

            dependency_set << Dependency.new(
              name: name,
              version: semver,
              package_manager: "bun",
              requirements: [],
              subdependency_metadata: subdependency_metadata_for(key, production_by_key)
            )
          end

          dependency_set
        end

        sig { params(packages: T::Hash[String, Record]).returns(T.nilable(T::Hash[String, T::Boolean])) }
        def production_by_key_for(packages)
          return unless Dependabot::Experiments.enabled?(:enable_bun_subdependency_types)

          @production_by_key_for ||=
            DependencyTypeResolver.new(workspaces: workspaces, records: packages).production_by_key
        end
        private :production_by_key_for

        # The packages key a manifest dependency resolves to in this lockfile: the
        # workspace's own nested copy (such as "app/ms") first, then the hoisted copy.
        sig { params(dependency_name: String, workspace_name: T.nilable(String)).returns(T.nilable(String)) }
        def manifest_key(dependency_name, workspace_name)
          packages = records
          return unless packages

          [workspace_name && "#{workspace_name}/#{dependency_name}", dependency_name]
            .compact
            .find { |candidate| packages.key?(candidate) }
        end

        # Whether the copy at a packages key is installed through a production dependency.
        # False unless dependency types are enabled, or when no workspace reaches the key.
        sig { params(key: String).returns(T::Boolean) }
        def production_key?(key)
          packages = records
          return false unless packages

          production_by_key = production_by_key_for(packages)
          return false unless production_by_key

          production_by_key.fetch(key, false)
        end

        # Whether the copy a manifest dependency resolves to is installed through a
        # production dependency. Other copies of the name do not count: a production-only
        # "debug/ms" says nothing about the root's own "ms".
        sig { params(dependency_name: String, workspace_name: T.nilable(String)).returns(T::Boolean) }
        def production_reachable?(dependency_name, workspace_name)
          key = manifest_key(dependency_name, workspace_name)
          key ? production_key?(key) : false
        end

        # Record the type for every package, not only development ones. DependencySet joins
        # metadata across copies of a package, so a copy with no entry next to one marked
        # { production: false } would make the package look development-only.
        sig do
          params(key: String, production_by_key: T.nilable(T::Hash[String, T::Boolean]))
            .returns(T::Array[T::Hash[Symbol, T::Boolean]])
        end
        def subdependency_metadata_for(key, production_by_key)
          return [] unless production_by_key

          # Packages that no workspace reaches keep the previous default of production.
          [{ production: production_by_key.fetch(key, true) }]
        end
        private :subdependency_metadata_for

        sig do
          params(dependency_name: String, _requirement: T.nilable(String), _manifest_name: String)
            .returns(T.nilable(Dependabot::Package::NpmLockfileDetails))
        end
        def details(dependency_name, _requirement, _manifest_name)
          records&.[](dependency_name)&.lookup_details
        end

        private

        sig { returns(T::Array[Workspace]) }
        def parse_workspaces
          raw_workspaces = parsed["workspaces"]
          return [] unless raw_workspaces.is_a?(Hash)

          raw_workspaces.filter_map do |raw_path, raw_details|
            path = T.cast(raw_path, Object)
            details = T.cast(raw_details, Object)
            next unless path.is_a?(String) && details.is_a?(Hash)

            name = T.cast(details["name"], Object)
            Workspace.new(
              key_prefix: path.empty? || !name.is_a?(String) ? nil : name,
              production_names: Record.section_names(details, Record::EDGE_SECTIONS),
              development_names: Record.section_names(details, DEVELOPMENT_SECTIONS)
            )
          end
        end

        sig { returns(T::Hash[Object, Object]) }
        def parse_document
          # Since bun.lock is a JSONC file, which is a subset of YAML, we can use YAML to parse it
          content = T.cast(YAML.load(T.must(@dependency_file.content)), Object)
          raise_invalid!("expected to be an object") unless content.is_a?(Hash)

          content.to_h { |key, value| [T.cast(key, Object), T.cast(value, Object)] }
        rescue Psych::SyntaxError => e
          raise_invalid!("malformed JSONC at line #{e.line}, column #{e.column}")
        end

        sig { params(message: String).returns(T.noreturn) }
        def raise_invalid!(message)
          raise Dependabot::DependencyFileNotParseable.new(@dependency_file.path, "Invalid bun.lock file: #{message}")
        end

        # The lockfile is well-formed and we can read it, but the bun binary we shell out to cannot.
        # Without this, bun discards the lockfile it failed to parse, re-resolves from scratch and
        # writes a downgraded lockfile back, all while exiting successfully.
        sig { params(version: Integer).returns(T.noreturn) }
        def raise_unsupported_lockfile_version!(version)
          raise Dependabot::DependencyFileNotSupported,
                "Unsupported bun.lock 'lockfileVersion' #{version} in #{@dependency_file.path}. " \
                "The bun version Dependabot runs supports up to " \
                "#{BunPackageManager::MAX_SUPPORTED_LOCKFILE_VERSION}."
        end
      end
    end
  end
end
