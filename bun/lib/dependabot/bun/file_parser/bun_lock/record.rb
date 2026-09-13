# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bun/file_parser/bun_lock"
require "dependabot/package/npm_lockfile_details"

module Dependabot
  module Bun
    class FileParser < Dependabot::FileParsers::Base
      class BunLock
        class Record
          extend T::Sig

          # Sections whose packages Bun installs alongside the package that declares them.
          EDGE_SECTIONS = %w(dependencies optionalDependencies peerDependencies).freeze

          # Returns the string keys of the given sections, skipping sections that are not objects.
          sig { params(details: T::Hash[Object, Object], sections: T::Array[String]).returns(T::Array[String]) }
          def self.section_names(details, sections)
            sections.flat_map do |section|
              names = T.cast(details[section], Object)
              next [] unless names.is_a?(Hash)

              names.keys.filter_map do |raw_name|
                name = T.cast(raw_name, Object)
                name if name.is_a?(String)
              end
            end.uniq
          end

          sig { params(data: Object, path: String, context: String).void }
          def initialize(data, path:, context:)
            @data = data
            @path = path
            @context = context
            @entry = T.let(nil, T.nilable(T::Array[Object]))
          end

          sig { returns(T::Boolean) }
          def graph_compatible?
            data = @data
            data.is_a?(Array) && T.cast(data.first, Object).is_a?(String)
          end

          sig { returns(String) }
          def name
            name = resolution_label.split(/(?<=\w)\@/).first
            invalid!("#{@context}[0] must contain a package name") unless name

            name
          end

          sig { returns(T.nilable(String)) }
          def version
            Version.semver_for(package_resolution)&.to_s
          end

          sig { returns(Dependabot::Package::NpmLockfileDetails) }
          def lookup_details
            semver = version
            Dependabot::Package::NpmLockfileDetails.new(
              version: semver,
              resolution: semver ? nil : package_resolution
            )
          end

          sig { returns(T::Array[String]) }
          def dependency_names
            details = entry[2]
            return [] if details.nil?

            invalid!("#{@context} details must be an object") unless details.is_a?(Hash)
            dependencies = T.cast(details["dependencies"], Object)
            return [] if dependencies.nil?

            invalid!("#{@context}.dependencies must be an object") unless dependencies.is_a?(Hash)
            dependencies.keys.map do |raw_name|
              child = T.cast(raw_name, Object)
              invalid!("#{@context}.dependencies keys must be strings") unless child.is_a?(String)

              child
            end
          end

          # Names of the packages this entry pulls in, used to classify dependency types.
          # Registry entries keep their details in slot two; git and local entries keep
          # them in slot one. Unreadable details give no edges rather than an error, so
          # classification never makes an otherwise valid lockfile fail to parse.
          sig { returns(T::Array[String]) }
          def edge_names
            return [] unless graph_compatible?

            slot_two = entry[2]
            slot_one = entry[1]
            details = slot_two.is_a?(Hash) ? slot_two : slot_one
            return [] unless details.is_a?(Hash)

            self.class.section_names(details, EDGE_SECTIONS)
          end

          private

          sig { returns(T::Array[Object]) }
          def entry
            return @entry if @entry

            data = @data
            invalid!("#{@context} must be an array") unless data.is_a?(Array)
            @entry = data.map { |value| T.cast(value, Object) }
          end

          sig { returns(String) }
          def resolution_label
            label = entry.first
            invalid!("#{@context}[0] must be a string") unless label.is_a?(String)

            label
          end

          sig { returns(T.nilable(String)) }
          def package_resolution
            resolution_label.split(/(?<=\w)\@/)[1]
          end

          sig { params(message: String).returns(T.noreturn) }
          def invalid!(message)
            raise DependencyFileNotParseable.new(@path, "Invalid bun.lock file: #{message}")
          end
        end
      end
    end
  end
end
