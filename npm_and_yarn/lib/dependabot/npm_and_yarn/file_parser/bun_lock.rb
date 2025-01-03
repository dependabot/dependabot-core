# typed: strict
# frozen_string_literal: true

require "yaml"
require "dependabot/errors"
require "dependabot/npm_and_yarn/helpers"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      class BunLock
        extend T::Sig

        sig { params(dependency_file: DependencyFile).void }
        def initialize(dependency_file)
          @dependency_file = dependency_file
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed
          @content ||= T.let(nil, T.nilable(T::Hash[String, T.untyped]))
          return @content if @content

          # Since bun.lock is a JSONC file, which is a subset of YAML, we can use YAML to parse it
          content = YAML.load(T.must(@dependency_file.content))
          raise_invalid!("expected to be an object") unless content.is_a?(Hash)

          version = content["lockfileVersion"]
          raise_invalid!("expected 'lockfileVersion' to be an integer") unless version.is_a?(Integer)
          raise_invalid!("expected 'lockfileVersion' to be >= 0") unless version >= 0
          unless version.zero?
            raise_invalid!(<<~ERROR
              unsupported 'lockfileVersion' = #{version}, please open an issue with Dependabot to support this:
              https://github.com/dependabot/dependabot/issues/new
            ERROR
                          )
          end

          @content = T.let(content, T::Hash[String, T.untyped])
        rescue Psych::SyntaxError => e
          raise_invalid!("malformed JSONC at line #{e.line}, column #{e.column}")
        end

        sig { returns(Integer) }
        def version
          parsed["lockfileVersion"]
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependencies
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          # bun.lock v0 format:
          # https://github.com/oven-sh/bun/blob/c130df6c589fdf28f9f3c7f23ed9901140bc9349/src/install/bun.lock.zig#L595-L605

          packages = parsed["packages"]
          raise_invalid!("expected 'packages' to be an object") unless packages.is_a?(Hash)

          packages.each do |key, details|
            raise_invalid!("expected 'packages.#{key}' to be an array") unless details.is_a?(Array)

            resolution = details.first
            raise_invalid!("expected 'packages.#{key}[0]' to be a string") unless resolution.is_a?(String)

            name, version = resolution.split(/(?<=\w)\@/)
            next if name.empty?

            semver = Version.semver_for(version)
            next unless semver

            dependency_set << Dependency.new(
              name: name,
              version: semver.to_s,
              package_manager: "npm_and_yarn",
              requirements: []
            )
          end

          dependency_set
        end

        sig do
          params(dependency_name: String, requirement: T.untyped, _manifest_name: String)
            .returns(T.nilable(T::Hash[String, T.untyped]))
        end
        def details(dependency_name, requirement, _manifest_name)
          packages = parsed["packages"]
          return unless packages.is_a?(Hash)

          candidates =
            packages
            .select { |name, _| name == dependency_name }
            .values

          # If there's only one entry for this dependency, use it, even if
          # the requirement in the lockfile doesn't match
          if candidates.one?
            parse_details(candidates.first)
          else
            candidate = candidates.find do |label, _|
              label.scan(/(?<=\w)\@(?:npm:)?([^\s,]+)/).flatten.include?(requirement)
            end&.last
            parse_details(candidate)
          end
        end

        private

        sig { params(message: String).void }
        def raise_invalid!(message)
          raise Dependabot::DependencyFileNotParseable.new(@dependency_file.path, "Invalid bun.lock file: #{message}")
        end

        sig do
          params(entry: T.nilable(T::Array[T.untyped])).returns(T.nilable(T::Hash[String, T.untyped]))
        end
        def parse_details(entry)
          return unless entry.is_a?(Array)

          # Either:
          # - "{name}@{version}", registry, details, integrity
          # - "{name}@{resolution}", details
          resolution = entry.first
          return unless resolution.is_a?(String)

          name, version = resolution.split(/(?<=\w)\@/)
          semver = Version.semver_for(version)

          if semver
            registry, details, integrity = entry[1..3]
            {
              "name" => name,
              "version" => semver.to_s,
              "registry" => registry,
              "details" => details,
              "integrity" => integrity
            }
          else
            details = entry[1]
            {
              "name" => name,
              "resolution" => version,
              "details" => details
            }
          end
        end
      end
    end
  end
end
