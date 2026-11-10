# typed: strong
# frozen_string_literal: true

require "dependabot/gradle/file_parser"

module Dependabot
  module Gradle
    class FileParser
      class LockfileParser
        extend T::Sig

        DEPENDENCY_REGEX = /\A(?<name>[^:\s=#]+:[^:\s=]+):(?<version>[^:\s=]+)=(?<configurations>[^\r\n]*)\z/

        class Entry < T::Struct
          const :name, String
          const :version, String
          const :configurations, T::Array[String]
        end

        sig { params(lockfile: Dependabot::DependencyFile).void }
        def initialize(lockfile:)
          @lockfile = lockfile
        end

        sig { returns(T::Array[Entry]) }
        def entries
          T.must(@lockfile.content).lines.filter_map do |line|
            line = line.strip
            next if line.empty? || line.start_with?("#", "empty=")

            match = DEPENDENCY_REGEX.match(line)
            unless match
              raise Dependabot::DependencyFileNotParseable.new(@lockfile.path, "Invalid Gradle lockfile entry: #{line}")
            end

            configurations = T.must(match[:configurations]).split(",", -1)
            if configurations.empty? || configurations.any?(&:empty?)
              raise Dependabot::DependencyFileNotParseable.new(@lockfile.path, "Missing locked configurations: #{line}")
            end

            Entry.new(
              name: T.must(match[:name]),
              version: T.must(match[:version]),
              configurations: configurations
            )
          end
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def parse
          entries.filter_map do |entry|
            unless Gradle::Version.correct?(entry.version)
              Dependabot.logger.warn(
                "Skipping Gradle lockfile dependency #{entry.name}: unsupported version #{entry.version}"
              )
              next
            end

            Dependabot::Dependency.new(
              name: entry.name,
              version: entry.version,
              package_manager: "gradle",
              requirements: [],
              subdependency_metadata: [{
                file: @lockfile.name,
                version: entry.version,
                configurations: entry.configurations
              }]
            )
          end
        end
      end
    end
  end
end
