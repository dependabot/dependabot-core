# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/julia/registry_client"

module Dependabot
  module Julia
    class RegistryClient
      module Result
        extend T::Sig

        ObjectHash = T.type_alias { T::Hash[String, Object] }

        module ValueParser
          extend T::Sig

          sig { params(value: Object, context: String).returns(ObjectHash) }
          def self.object_hash(value, context)
            raise TypeError, "#{context} must be an object" unless value.is_a?(Hash)

            result = T.let({}, ObjectHash)
            value.each do |raw_key, raw_value|
              key = T.cast(raw_key, Object)
              raise TypeError, "#{context} keys must be strings" unless key.is_a?(String)

              result[key] = T.cast(raw_value, Object)
            end
            result
          end

          sig { params(hash: ObjectHash, key: String, context: String).returns(Object) }
          def self.value(hash, key, context)
            raise TypeError, "#{context} #{key} is required" unless hash.key?(key)

            hash[key]
          end

          sig { params(hash: ObjectHash, key: String, context: String).returns(String) }
          def self.string(hash, key, context)
            string_value(value(hash, key, context), "#{context} #{key}")
          end

          sig { params(hash: ObjectHash, key: String, context: String).returns(T.nilable(String)) }
          def self.nilable_string(hash, key, context)
            optional_string_value(value(hash, key, context), "#{context} #{key}")
          end

          sig { params(hash: ObjectHash, key: String, context: String).returns(T.nilable(String)) }
          def self.optional_string(hash, key, context)
            optional_string_value(hash[key], "#{context} #{key}")
          end

          sig { params(value: Object, context: String).returns(String) }
          def self.string_value(value, context)
            return value if value.is_a?(String)

            raise TypeError, "#{context} must be a string"
          end

          sig { params(value: Object, context: String).returns(T.nilable(String)) }
          def self.optional_string_value(value, context)
            return if value.nil?
            return value if value.is_a?(String)

            raise TypeError, "#{context} must be a string or nil"
          end

          sig { params(value: Object, context: String).returns(T::Array[String]) }
          def self.string_array(value, context)
            raise TypeError, "#{context} must be an array" unless value.is_a?(Array)

            value.map do |item|
              string_value(T.cast(item, Object), "#{context} entry")
            end
          end

          sig { params(value: Object, context: String).returns(T::Array[ObjectHash]) }
          def self.object_array(value, context)
            raise TypeError, "#{context} must be an array" unless value.is_a?(Array)

            value.map do |item|
              object_hash(T.cast(item, Object), "#{context} entry")
            end
          end

          sig { params(value: Object, context: String).returns(T::Hash[String, String]) }
          def self.string_map(value, context)
            result = T.let({}, T::Hash[String, String])
            object_hash(value, context).each do |key, raw_value|
              result[key] = string_value(raw_value, "#{context} #{key}")
            end
            result
          end
        end
        private_constant :ValueParser

        class Failure < T::ImmutableStruct
          const :message, String
        end

        sig { params(hash: ObjectHash, _context: String).returns(T.nilable(Failure)) }
        def self.failure_from(hash, _context)
          error = hash["error"]
          return unless hash.length == 1 && error.is_a?(String)

          Failure.new(message: error)
        end

        class Version < T::ImmutableStruct
          extend T::Sig

          const :version, String
          const :package_uuid, T.nilable(String), default: nil

          sig { params(value: Object, context: String).returns(T.any(Version, Failure)) }
          def self.from_object(value, context:)
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            new(
              version: ValueParser.string(hash, "version", context),
              package_uuid: ValueParser.optional_string(hash, "package_uuid", context)
            )
          end

          sig { params(value: Object, context: String).returns(T.any(Version, Failure)) }
          def self.from_batch_value(value, context:)
            return new(version: value) if value.is_a?(String)

            from_object(value, context: context)
          end
        end

        class PackageMetadata < T::ImmutableStruct
          extend T::Sig

          const :name, String
          const :uuid, String
          const :latest_version, String
          const :available_versions, T::Array[String]

          sig { params(value: Object, context: String).returns(T.any(PackageMetadata, Failure)) }
          def self.from_object(value, context:)
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            new(
              name: ValueParser.string(hash, "name", context),
              uuid: ValueParser.string(hash, "uuid", context),
              latest_version: ValueParser.string(hash, "latest_version", context),
              available_versions: ValueParser.string_array(
                ValueParser.value(hash, "available_versions", context),
                "#{context} available_versions"
              )
            )
          end
        end

        class ProjectDependency < T::ImmutableStruct
          extend T::Sig

          const :name, String
          const :uuid, String
          const :requirement, T.nilable(String), default: nil

          sig { params(value: Object).returns(ProjectDependency) }
          def self.from_object(value)
            context = "project dependency"
            hash = ValueParser.object_hash(value, context)

            new(
              name: ValueParser.string(hash, "name", context),
              uuid: ValueParser.string(hash, "uuid", context),
              requirement: ValueParser.optional_string(hash, "requirement", context)
            )
          end
        end

        class Project < T::ImmutableStruct
          extend T::Sig

          const :name, T.nilable(String)
          const :version, T.nilable(String)
          const :uuid, T.nilable(String)
          const :julia_version, String
          const :dependencies, T::Array[ProjectDependency]
          const :weak_dependencies, T::Array[ProjectDependency]
          const :project_path, String

          sig { params(value: Object).returns(T.any(Project, Failure)) }
          def self.from_object(value)
            context = "project result"
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            new(
              name: ValueParser.nilable_string(hash, "name", context),
              version: ValueParser.nilable_string(hash, "version", context),
              uuid: ValueParser.nilable_string(hash, "uuid", context),
              julia_version: ValueParser.string(hash, "julia_version", context),
              dependencies: parse_dependencies(hash, "dependencies", context),
              weak_dependencies: parse_dependencies(hash, "weak_dependencies", context),
              project_path: ValueParser.string(hash, "project_path", context)
            )
          end

          sig do
            params(
              hash: ObjectHash,
              key: String,
              context: String
            ).returns(T::Array[ProjectDependency])
          end
          def self.parse_dependencies(hash, key, context)
            ValueParser.object_array(
              ValueParser.value(hash, key, context),
              "#{context} #{key}"
            ).map { |dependency| ProjectDependency.from_object(dependency) }
          end
          private_class_method :parse_dependencies
        end

        class ManifestDependency < T::ImmutableStruct
          extend T::Sig

          const :name, String
          const :uuid, String
          const :version, String
          const :tree_hash, String
          const :repo_url, String
          const :repo_rev, String
          const :path, String
          const :dependencies, T::Hash[String, String]

          sig { params(value: Object).returns(ManifestDependency) }
          def self.from_object(value)
            context = "manifest dependency"
            hash = ValueParser.object_hash(value, context)
            raw_dependencies = hash["dependencies"]
            dependencies = if raw_dependencies.nil?
                             {}
                           else
                             ValueParser.string_map(raw_dependencies, "#{context} dependencies")
                           end

            new(
              name: ValueParser.string(hash, "name", context),
              uuid: ValueParser.string(hash, "uuid", context),
              version: ValueParser.string(hash, "version", context),
              tree_hash: ValueParser.string(hash, "tree_hash", context),
              repo_url: ValueParser.string(hash, "repo_url", context),
              repo_rev: ValueParser.string(hash, "repo_rev", context),
              path: ValueParser.string(hash, "path", context),
              dependencies: dependencies
            )
          end
        end

        class Manifest < T::ImmutableStruct
          extend T::Sig

          const :dependencies, T::Array[ManifestDependency]
          const :manifest_path, String

          sig { params(value: Object).returns(T.any(Manifest, Failure)) }
          def self.from_object(value)
            context = "manifest result"
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            dependencies = ValueParser.object_array(
              ValueParser.value(hash, "dependencies", context),
              "#{context} dependencies"
            ).map { |dependency| ManifestDependency.from_object(dependency) }

            new(
              dependencies: dependencies,
              manifest_path: ValueParser.string(hash, "manifest_path", context)
            )
          end
        end

        class EnvironmentFiles < T::ImmutableStruct
          extend T::Sig

          const :project_file, String
          const :manifest_file, String

          sig { params(value: Object).returns(T.any(EnvironmentFiles, Failure)) }
          def self.from_object(value)
            context = "environment files result"
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            new(
              project_file: ValueParser.string(hash, "project_file", context),
              manifest_file: ValueParser.string(hash, "manifest_file", context)
            )
          end
        end

        class WorkspaceFiles < T::ImmutableStruct
          extend T::Sig

          const :project_files, T::Array[String]
          const :manifest_file, String
          const :workspace_root, String

          sig { params(value: Object).returns(T.any(WorkspaceFiles, Failure)) }
          def self.from_object(value)
            context = "workspace files result"
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            new(
              project_files: ValueParser.string_array(
                ValueParser.value(hash, "project_files", context),
                "#{context} project_files"
              ),
              manifest_file: ValueParser.string(hash, "manifest_file", context),
              workspace_root: ValueParser.string(hash, "workspace_root", context)
            )
          end
        end

        class Source < T::ImmutableStruct
          extend T::Sig

          const :source_url, String
          const :source_type, String
          const :package_uuid, String

          sig { params(value: Object).returns(T.any(Source, Failure)) }
          def self.from_object(value)
            context = "package source result"
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            new(
              source_url: ValueParser.string(hash, "source_url", context),
              source_type: ValueParser.string(hash, "source_type", context),
              package_uuid: ValueParser.string(hash, "package_uuid", context)
            )
          end
        end

        class ManifestUpdate < T::ImmutableStruct
          extend T::Sig

          const :manifest_content, String
          const :manifest_path, String

          sig { params(value: Object).returns(T.any(ManifestUpdate, Failure)) }
          def self.from_object(value)
            context = "manifest update result"
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            new(
              manifest_content: ValueParser.string(hash, "manifest_content", context),
              manifest_path: ValueParser.string(hash, "manifest_path", context)
            )
          end
        end

        class AvailableVersions < T::ImmutableStruct
          extend T::Sig

          const :versions, T::Array[String]

          sig { params(value: Object, context: String).returns(T.any(AvailableVersions, Failure)) }
          def self.from_object(value, context:)
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            new(
              versions: ValueParser.string_array(
                ValueParser.value(hash, "versions", context),
                "#{context} versions"
              )
            )
          end

          sig { params(value: Object, context: String).returns(T.any(AvailableVersions, Failure)) }
          def self.from_batch_value(value, context:)
            return new(versions: ValueParser.string_array(value, context)) if value.is_a?(Array)

            from_object(value, context: context)
          end
        end

        class ReleaseDate < T::ImmutableStruct
          extend T::Sig

          const :release_date, T.nilable(String)

          sig { params(value: Object, context: String).returns(T.any(ReleaseDate, Failure)) }
          def self.from_object(value, context:)
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            new(release_date: ValueParser.nilable_string(hash, "release_date", context))
          end

          sig { params(value: Object, context: String).returns(T.any(ReleaseDate, Failure)) }
          def self.from_batch_value(value, context:)
            return new(release_date: nil) if value.nil?
            return new(release_date: value) if value.is_a?(String)

            from_object(value, context: context)
          end
        end

        class PackageInfo < T::ImmutableStruct
          extend T::Sig

          const :available_versions, T.any(AvailableVersions, Failure)
          const :latest_version, T.any(Version, Failure)
          const :metadata, T.nilable(T.any(PackageMetadata, Failure)), default: nil

          sig { params(value: Object, context: String).returns(T.any(PackageInfo, Failure)) }
          def self.from_object(value, context:)
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            metadata = if hash.key?("metadata")
                         PackageMetadata.from_object(
                           ValueParser.value(hash, "metadata", context),
                           context: "#{context} metadata"
                         )
                       end

            new(
              available_versions: AvailableVersions.from_batch_value(
                ValueParser.value(hash, "available_versions", context),
                context: "#{context} available_versions"
              ),
              latest_version: Version.from_batch_value(
                ValueParser.value(hash, "latest_version", context),
                context: "#{context} latest_version"
              ),
              metadata: metadata
            )
          end
        end

        class PackageInfoBatch < T::ImmutableStruct
          extend T::Sig

          const :packages, T::Hash[String, T.any(PackageInfo, Failure)]

          sig { params(value: Object).returns(T.any(PackageInfoBatch, Failure)) }
          def self.from_object(value)
            context = "batch package info result"
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            packages = T.let({}, T::Hash[String, T.any(PackageInfo, Failure)])
            hash.each do |name, raw_info|
              packages[name] = PackageInfo.from_object(raw_info, context: "#{context} #{name}")
            end
            new(packages: packages)
          end
        end

        class ReleaseDates < T::ImmutableStruct
          extend T::Sig

          const :dates, T::Hash[String, T.any(ReleaseDate, Failure)]

          sig { params(value: Object, context: String).returns(T.any(ReleaseDates, Failure)) }
          def self.from_object(value, context:)
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            dates = T.let({}, T::Hash[String, T.any(ReleaseDate, Failure)])
            hash.each do |version, raw_date|
              dates[version] = ReleaseDate.from_batch_value(raw_date, context: "#{context} #{version}")
            end
            new(dates: dates)
          end
        end

        class ReleaseDatesBatch < T::ImmutableStruct
          extend T::Sig

          const :packages, T::Hash[String, T.any(ReleaseDates, Failure)]

          sig { params(value: Object).returns(T.any(ReleaseDatesBatch, Failure)) }
          def self.from_object(value)
            context = "batch release dates result"
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            packages = T.let({}, T::Hash[String, T.any(ReleaseDates, Failure)])
            hash.each do |name, raw_dates|
              packages[name] = ReleaseDates.from_object(raw_dates, context: "#{context} #{name}")
            end
            new(packages: packages)
          end
        end

        class AvailableVersionsBatch < T::ImmutableStruct
          extend T::Sig

          const :packages, T::Hash[String, T.any(AvailableVersions, Failure)]

          sig { params(value: Object).returns(T.any(AvailableVersionsBatch, Failure)) }
          def self.from_object(value)
            context = "batch available versions result"
            hash = ValueParser.object_hash(value, context)
            failure = Result.failure_from(hash, context)
            return failure if failure

            packages = T.let({}, T::Hash[String, T.any(AvailableVersions, Failure)])
            hash.each do |name, raw_versions|
              packages[name] = AvailableVersions.from_object(
                raw_versions,
                context: "#{context} #{name}"
              )
            end
            new(packages: packages)
          end
        end

        class PackageVersionsRequest < T::ImmutableStruct
          extend T::Sig

          const :name, String
          const :uuid, String
          const :versions, T::Array[String]

          sig { returns(T::Hash[Symbol, Object]) }
          def to_h
            T.let(
              {
                name: name,
                uuid: uuid,
                versions: versions
              },
              T::Hash[Symbol, Object]
            )
          end
        end
      end
    end
  end
end
