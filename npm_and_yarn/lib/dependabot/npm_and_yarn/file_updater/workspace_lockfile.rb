# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/logger"
require "dependabot/npm_and_yarn/file_updater"
require "dependabot/package/npm_package_json"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      class WorkspaceLockfile
        extend T::Sig

        ObjectHash = T.type_alias { T::Hash[String, Object] }
        DEPENDENCY_TYPES = %w(dependencies devDependencies peerDependencies optionalDependencies).freeze

        sig do
          params(
            lockfile: DependencyFile,
            original_lockfile: DependencyFile,
            manifest_file: DependencyFile
          ).void
        end
        def initialize(lockfile:, original_lockfile:, manifest_file:)
          @path = T.let(lockfile.path, String)
          @data = T.let(object(T.cast(JSON.parse(T.must(lockfile.content)), Object), "root"), ObjectHash)
          @original = T.let(
            object(T.cast(JSON.parse(T.must(original_lockfile.content)), Object), "original root"),
            ObjectHash
          )
          @manifest_path = T.let(manifest_file.path, String)
          @manifest = T.let(parse_manifest(manifest_file), Dependabot::Package::NpmPackageJson)
        end

        sig { params(indent: String).returns(T.nilable(String)) }
        def cleaned_content(indent:)
          value = @data["packages"]
          return unless value

          packages = object(value, "packages")
          originals = object(@original["packages"] || {}, "original packages")
          updated = packages.dup
          root = packages[""]
          updated[""] = cleaned_root(object(root, "packages root")) if root

          originals.each do |path, entry|
            next if updated.key?(path)
            next unless entry.is_a?(Hash)
            next unless T.cast(entry["optional"], Object) == true && T.cast(entry["peer"], Object) == true

            Dependabot.logger.info("Restoring optional peer dependency removed during workspace update: #{path}")
            updated[path] = entry
          end
          return if updated == packages

          "#{JSON.pretty_generate(@data.merge('packages' => updated), indent: indent)}\n"
        end

        private

        sig { params(file: DependencyFile).returns(Dependabot::Package::NpmPackageJson) }
        def parse_manifest(file)
          Dependabot::Package::NpmPackageJson.from_file(file)
        rescue TypeError => e
          raise DependencyFileNotParseable.new(file.path, e.message)
        end

        sig { params(root: ObjectHash).returns(ObjectHash) }
        def cleaned_root(root)
          updated = root.dup
          DEPENDENCY_TYPES.each do |type|
            value = root[type]
            next unless value

            requirements = object(value, "packages root #{type}")
            names = manifest_names(type)
            retained = requirements.dup
            retained.keep_if { |name, _| names&.include?(name) }
            if retained.empty?
              updated.delete(type)
            else
              updated[type] = retained
            end
          end
          updated
        end

        sig { params(type: String).returns(T.nilable(T::Set[String])) }
        def manifest_names(type)
          @manifest.dependency_names(type)&.to_set
        rescue TypeError => e
          raise DependencyFileNotParseable.new(@manifest_path, e.message)
        end

        sig { params(value: Object, field: String).returns(ObjectHash) }
        def object(value, field)
          raise DependencyFileNotParseable.new(@path, "#{field} must be an object") unless value.is_a?(Hash)

          T.let(value, ObjectHash)
        end
      end
    end
  end
end
