# typed: strong
# frozen_string_literal: true

require "json"
require "dependabot/errors"
require "dependabot/logger"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/package/npm_lockfile_details"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      class JsonLock
        extend T::Sig

        require_relative "json_lock/record"

        sig { params(dependency_file: DependencyFile, dealias_packages: T::Boolean).void }
        def initialize(dependency_file, dealias_packages: false)
          @dependency_file = dependency_file
          @dealias_packages = dealias_packages
          @modern_lockfile = T.let(nil, T.nilable(T::Boolean))
        end

        sig { returns(Record) }
        def parsed
          @parsed ||= T.let(
            Record.new(
              T.cast(JSON.parse(T.must(@dependency_file.content)), Object),
              path: @dependency_file.path,
              context: "lockfile"
            ),
            T.nilable(Record)
          )
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, @dependency_file.path
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependencies
          recursively_fetch_dependencies(parsed)
        end

        sig { returns(T::Hash[String, Record]) }
        def legacy_dependencies
          parsed.legacy_entries
        end

        sig do
          params(dependency: Dependabot::Dependency, original: Dependabot::DependencyFile)
            .returns(T.nilable(Version))
        end
        def updated_dependency_version(dependency:, original:)
          original_lock = self.class.new(original)
          paths = original_lock.versions_by_path(dependency.name)
                               .select { |_, version| version == dependency.version }.keys
          original_records = records_by_path(original_lock.parsed)
          updated_records = records_by_path(parsed)
          updated_versions = versions_by_path(dependency.name)

          paths.flat_map do |path|
            resolution_paths(original_records, path, dependency.name).map do |candidates|
              updated_path = candidates.find { |candidate| updated_records.key?(candidate) }
              version = updated_path ? updated_versions[updated_path] : nil
              unless version
                Dependabot.logger.info(
                  "Cannot verify updated npm resolution for #{path}; keeping current version"
                )
              end
              Version.new(version || T.must(dependency.version))
            end
          end.min
        end

        sig { params(dependency_name: String).returns(T::Hash[String, String]) }
        def versions_by_path(dependency_name)
          records_by_path(parsed).filter_map do |path, record|
            next if path.empty?
            next unless package_name_for(path, record) == dependency_name

            version = record.version
            [path, version] if version
          end.to_h
        end

        sig do
          params(dependency_name: String, _requirement: T.nilable(String), manifest_name: String)
            .returns(T.nilable(Dependabot::Package::NpmLockfileDetails))
        end
        def details(dependency_name, _requirement, manifest_name)
          modern = modern_lockfile?
          details = if modern
                      # NOTE: npm 8 sometimes doesn't install workspace dependencies in the
                      # workspace folder so we need to fallback to checking top-level
                      parsed.package_entry(
                        node_modules_path(manifest_name, dependency_name),
                        "node_modules/#{dependency_name}"
                      )
                    else
                      parsed.legacy_entry(dependency_name)
                    end
          return if details.nil?

          Dependabot::Package::NpmLockfileDetails.new(
            version: details.version,
            resolved: details.resolved,
            resolution: modern ? nil : details.resolution
          )
        end

        private

        sig { returns(T::Boolean) }
        def modern_lockfile?
          return @modern_lockfile unless @modern_lockfile.nil?

          @modern_lockfile = Helpers.parse_npm8?(@dependency_file)
        end

        sig { params(record: Record).returns(T::Hash[String, Record]) }
        def records_by_path(record)
          modern_lockfile? ? record.package_entries : legacy_records_by_path(record)
        end

        sig do
          params(records: T::Hash[String, Record], target: String, name: String)
            .returns(T::Array[T::Array[String]])
        end
        def resolution_paths(records, target, name)
          modern = modern_lockfile?
          incoming = records.filter_map do |path, record|
            next unless record.dependency_names(modern: modern).include?(name)

            candidates = resolution_candidates(path, name)
            candidates if candidates.find { |candidate| records.key?(candidate) } == target
          end
          return incoming unless incoming.empty?

          [resolution_candidates(target.rpartition("/node_modules/").first, name)]
        end

        sig { params(parent_path: String, name: String).returns(T::Array[String]) }
        def resolution_candidates(parent_path, name)
          segments = parent_path.split("/node_modules/")
          candidates = T.let([], T::Array[String])
          while segments.any?
            candidates << "#{segments.join('/node_modules/')}/node_modules/#{name}"
            segments.pop
          end
          candidates << "node_modules/#{name}"
        end

        sig { params(record: Record, prefix: String).returns(T::Hash[String, Record]) }
        def legacy_records_by_path(record, prefix = "")
          records = T.let({}, T::Hash[String, Record])
          record.legacy_entries.each do |name, details|
            path = "#{prefix}node_modules/#{name}"
            records[path] = details
            records.merge!(legacy_records_by_path(details, "#{path}/"))
          end
          records
        end

        sig do
          params(object_with_dependencies: Record)
            .returns(Dependabot::FileParsers::Base::DependencySet)
        end
        def recursively_fetch_dependencies(object_with_dependencies)
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          object_with_dependencies.dependency_entries.each do |name, details|
            next if name.empty? # v3 lockfiles include an empty key holding info of the current package

            version = Version.semver_for(details.version)
            next unless version

            package_name = package_name_for(name, details)
            version = version.to_s

            metadata = aliased_package?(name, details) ? { alias: name.split("node_modules/").last } : nil
            subdependency_metadata = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, Object]]))
            subdependency_metadata = [{ npm_bundled: true }] if details.bundled?
            subdependency_metadata = [{ production: false }] if details.dev?

            dependency_set << Dependency.new(
              name: package_name,
              version: version,
              package_manager: "npm_and_yarn",
              requirements: [],
              metadata: metadata,
              subdependency_metadata: subdependency_metadata
            )
            dependency_set += recursively_fetch_dependencies(details)
          end

          dependency_set
        end

        sig { params(package_path: String, details: Record).returns(String) }
        def package_name_for(package_path, details)
          package_name = T.must(package_path.split("node_modules/").last)
          return package_name unless dealias_packages?

          real_package_name = details.name
          return package_name if real_package_name.nil?
          return package_name if real_package_name == package_name

          real_package_name
        end

        sig { params(package_path: String, details: Record).returns(T::Boolean) }
        def aliased_package?(package_path, details)
          return false unless dealias_packages?

          real_package_name = details.name
          return false if real_package_name.nil?

          package_name = T.must(package_path.split("node_modules/").last)
          real_package_name != package_name
        end

        sig { params(manifest_name: String, dependency_name: String).returns(String) }
        def node_modules_path(manifest_name, dependency_name)
          return "node_modules/#{dependency_name}" if manifest_name == "package.json"

          workspace_path = manifest_name.gsub("/package.json", "")
          File.join(workspace_path, "node_modules", dependency_name)
        end

        sig { returns(T::Boolean) }
        def dealias_packages?
          @dealias_packages
        end
      end
    end
  end
end
