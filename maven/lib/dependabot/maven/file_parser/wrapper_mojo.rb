# typed: strong
# frozen_string_literal: true

# Parses maven-wrapper.properties and emits Dependency objects for the two
# tracked Maven coordinates: org.apache.maven:apache-maven (the maven distribution)
# and org.apache.maven.wrapper:maven-wrapper (the wrapper plugin).
require "dependabot/maven/file_parser"
require "dependabot/maven/distributions"

module Dependabot
  module Maven
    class FileParser
      # Model of the Maven Wrapper plugin's WrapperMojo goal. Mirrors the
      # properties recognized by the upstream plugin:
      # https://github.com/apache/maven-wrapper/blob/master/maven-wrapper-plugin/src/main/java/org/apache/maven/plugins/wrapper/WrapperMojo.java
      class WrapperMojo
        extend T::Sig

        class WrapperProperties < T::Struct
          # Resolved distributionUrl value with Java-Properties \: escapes
          # stripped, making it a valid URI. Used for HTTP calls and registry
          # matching. Nil when the file contains no distributionUrl line.
          const :distribution_url, T.nilable(String)

          # distributionUrl value exactly as written in the file, \: escapes
          # preserved. Used as the gsub target in update_properties_file_directly
          # so the substitution matches the original bytes precisely.
          # Always nil when distribution_url is nil.
          const :distribution_replace, T.nilable(String)

          # Value of distributionSha256Sum, or nil when the property is absent.
          # Tracked as a second requirement on the Apache Maven dependency so the
          # checksum is updated atomically with the version.
          const :distribution_sha256_sum, T.nilable(String)

          # Version of the Maven Wrapper tooling, e.g. "3.3.4". Sourced from
          # the first strategy that succeeds: wrapperVersion property (>=3.3.1),
          # version segment of wrapperUrl JAR filename (<3.3.0), or version
          # comment in the mvnw script body (3.3.0 only, see MWRAPPER-120 and
          # MWRAPPER-134). Nil when none of these sources yield a version.
          const :wrapper_version, T.nilable(String)

          # The raw text to replace when updating the wrapper tooling version.
          # "3.3.4" for wrapperVersion (bare string), the full JAR URL for
          # wrapperUrl, or nil when the version came from the script body (3.3.0
          # gap) in which case the native wrapper command handles regeneration.
          const :wrapper_replace, T.nilable(String)

          # Value of distributionType, controlling which binary artifacts are
          # committed alongside the wrapper scripts: "bin" (JAR present),
          # "script" (JAR present), "only-script" (no JAR), "source"
          # (MavenWrapperDownloader.java present). Defaults to "bin" when the
          # property is absent, matching pre-3.3.0 behavior.
          const :distribution_type, String
        end

        # Extracts the version from a distributionUrl value (the resolved URL,
        # not the raw properties line). Matches the version from the directory
        # path segment (e.g. `.../apache-maven/3.9.9/apache-maven-3.9.9-bin.zip`)
        # to avoid capturing classifiers like `-bin` or `-src` as part of the version.
        DIST_URL_VERSION_REGEX = %r{/apache-maven/(?<version>[^/]+)/apache-maven-}x

        sig do
          params(
            properties_file: DependencyFile,
            script_files: T::Array[DependencyFile]
          ).returns(T::Array[Dependency])
        end
        def self.resolve_dependencies(properties_file, script_files: [])
          content = properties_file.content
          return [] unless content

          props = load_properties(content)
          return [] unless props.distribution_url

          props = fill_wrapper_version(props, script_files) if props.wrapper_version.nil? && script_files.any?

          match = T.must(props.distribution_url).match(DIST_URL_VERSION_REGEX)&.named_captures
          return [] unless match

          dist_version = T.must(match.fetch("version"))
          deps = [build_dist_dependency(properties_file, props, dist_version)]
          deps << T.must(build_wrapper_dependency(properties_file, props, dist_version)) if props.wrapper_version
          deps.compact
        end

        sig do
          params(props: WrapperProperties, script_files: T::Array[DependencyFile]).returns(WrapperProperties)
        end
        def self.fill_wrapper_version(props, script_files)
          # Maven Wrapper 3.3.0 shipped with wrapperUrl removed
          # and wrapperVersion landed in 3.3.1, leaving
          # no machine-readable wrapper version in the properties file.
          # This method is a fall back to scanning the generated mvnw/mvnw.cmd script body for the version comment.
          # See https://issues.apache.org/jira/browse/MWRAPPER-134
          Dependabot.logger.warn "Maven Wrapper with no wrapperVersion or wrapperUrl in properties file"
          WrapperProperties.new(
            distribution_url: props.distribution_url,
            distribution_replace: props.distribution_replace,
            distribution_sha256_sum: props.distribution_sha256_sum,
            wrapper_version: load_wrapper_version_from_scripts(script_files),
            wrapper_replace: nil,
            distribution_type: props.distribution_type
          )
        end

        sig do
          params(
            properties_file: DependencyFile,
            props: WrapperProperties,
            dist_version: String
          ).returns(Dependency)
        end
        def self.build_dist_dependency(properties_file, props, dist_version)
          Dependency.new(
            name: Distributions::MAVEN_DISTRIBUTION_PACKAGE,
            version: dist_version,
            requirements: build_distribution_requirements(properties_file, props, dist_version),
            package_manager: "maven"
          )
        end

        sig do
          params(
            properties_file: DependencyFile,
            props: WrapperProperties,
            dist_version: String
          ).returns(T.nilable(Dependency))
        end
        def self.build_wrapper_dependency(properties_file, props, dist_version)
          return unless props.wrapper_version

          Dependency.new(
            name: Distributions::MAVEN_WRAPPER_PACKAGE,
            version: props.wrapper_version,
            requirements: [
              {
                requirement: props.wrapper_version,
                file: properties_file.name,
                source: {
                  type: Distributions::DISTRIBUTION_DEPENDENCY_TYPE,
                  property: wrapper_property_name(props),
                  replace_string: props.wrapper_replace
                },
                groups: []
              },
              {
                requirement: dist_version,
                file: properties_file.name,
                source: {
                  type: Distributions::DISTRIBUTION_DEPENDENCY_TYPE,
                  property: "distributionUrl",
                  url: props.distribution_url,
                  replace_string: props.distribution_replace
                },
                groups: []
              }
            ],
            package_manager: "maven"
          )
        end

        DISTRIBUTION_TYPE_REGEX = /\AdistributionType\s*=\s*(?<type>\S+)\s*\z/

        sig { params(content: String).returns(String) }
        def self.distribution_type(content)
          content.lines.each do |line|
            m = line.strip.match(DISTRIBUTION_TYPE_REGEX)
            return T.must(m[:type]) if m
          end
          "bin"
        end

        sig { params(dir: String).returns(T::Array[String]) }
        def self.read_wrapper_options(dir)
          args = T.let([], T::Array[String])
          debug_scripts = %w(mvnwDebug mvnwDebug.cmd)
          has_debug = debug_scripts.any? { |s| File.exist?(File.join(dir, s)) }
          args << "-DincludeDebugScript=true" if has_debug
          args
        end

        DISTRIBUTION_URL_REGEX = /
          \AdistributionUrl \s* = \s*
          (?<replaceString>
            \S*                                   # optional URL prefix or path
            apache-maven-
            (?<version>\d+\.\d+(?:\.\d+)?         # e.g. 3.9.9
              (?:-\w+)*                            # optional pre-release suffix
            )
            (?:-bin|-src)?                         # optional classifier
            \.zip
          )
          \s*\z
        /x

        sig { params(content: String).returns(WrapperProperties) }
        def self.load_properties(content)
          distribution_url     = T.let(nil, T.nilable(String))
          distribution_replace = T.let(nil, T.nilable(String))
          distribution_sha256_sum = T.let(nil, T.nilable(String))
          wrapper_version      = T.let(nil, T.nilable(String))
          wrapper_replace      = T.let(nil, T.nilable(String))
          distribution_type    = T.let("bin", String)

          content.lines.each do |raw_line|
            line = raw_line.strip

            if (m = line.match(DISTRIBUTION_URL_REGEX))
              distribution_replace = m[:replaceString]
              distribution_url     = m[:replaceString]&.gsub("\\:", ":")
              next
            end

            if (m = line.match(/\AdistributionSha256Sum\s*=\s*(?<v>\S+)\s*\z/))
              distribution_sha256_sum = m[:v]
              next
            end

            if (m = line.match(DISTRIBUTION_TYPE_REGEX))
              distribution_type = T.must(m[:type])
              next
            end

            ver, rep = parse_wrapper_version_line(line, wrapper_version)
            if ver
              wrapper_version = ver
              wrapper_replace = rep
            end
          end

          WrapperProperties.new(
            distribution_url: distribution_url,
            distribution_replace: distribution_replace,
            distribution_sha256_sum: distribution_sha256_sum,
            wrapper_version: wrapper_version,
            wrapper_replace: wrapper_replace,
            distribution_type: distribution_type
          )
        end

        WRAPPER_VERSION_REGEX = /
          \AwrapperVersion \s* = \s*
          (?<replaceString>
            (?<version>\d+\.\d+(?:\.\d+)?)         # e.g. 3.3.4
          )
          \s*\z
        /x

        WRAPPER_URL_REGEX = /
          \AwrapperUrl \s* = \s*
          (?<replaceString>
            \S*                                   # optional URL prefix or path
            -(?<version>\d+\.\d+(?:\.\d+)?        # version in JAR filename
              (?:-\w+)*
            )
            (?:-bin)?                              # optional classifier
            \.jar
          )
          \s*\z
        /x

        sig do
          params(line: String, current_version: T.nilable(String))
            .returns(T.nilable([T.nilable(String), T.nilable(String)]))
        end
        def self.parse_wrapper_version_line(line, current_version)
          if (m = line.match(WRAPPER_VERSION_REGEX))
            return [m[:version], m[:replaceString]]
          end

          if current_version.nil? && (m = line.match(WRAPPER_URL_REGEX))
            return [m[:version], m[:replaceString]]
          end

          nil
        end

        sig do
          params(
            properties_file: DependencyFile,
            props: WrapperProperties,
            dist_version: String
          ).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def self.build_distribution_requirements(properties_file, props, dist_version)
          reqs = T.let(
            [{
              requirement: dist_version,
              file: properties_file.name,
              source: {
                type: Distributions::DISTRIBUTION_DEPENDENCY_TYPE,
                url: props.distribution_url,
                property: "distributionUrl",
                replace_string: props.distribution_replace
              },
              groups: [],
              # The Apache Maven distribution is not a JAR, but a POM is available
              # We can use this POM to query for new versions using the existing update checker for maven
              metadata: { packaging_type: "pom" }
            }],
            T::Array[T::Hash[Symbol, T.untyped]]
          )

          if props.distribution_sha256_sum
            reqs << {
              requirement: T.must(props.distribution_sha256_sum),
              file: properties_file.name,
              source: {
                type: Distributions::DISTRIBUTION_DEPENDENCY_TYPE,
                url: "#{props.distribution_url}.sha256",
                property: "distributionSha256Sum",
                replace_string: nil
              },
              groups: []
            }
          end

          Dependabot.logger.debug "Maven distribution reqs #{reqs}"
          reqs
        end

        sig { params(props: WrapperProperties).returns(String) }
        def self.wrapper_property_name(props)
          if props.wrapper_replace.nil?
            "scriptVersion"
          elsif T.must(props.wrapper_replace).include?(".jar")
            "wrapperUrl"
          else
            "wrapperVersion"
          end
        end

        private_class_method :build_distribution_requirements
        private_class_method :fill_wrapper_version
        private_class_method :build_dist_dependency
        private_class_method :build_wrapper_dependency
        private_class_method :wrapper_property_name

        # Matches the human-readable banner embedded in mvnw / mvnw.cmd, e.g.:
        #   "Apache Maven Wrapper startup script, version 3.3.2"
        #   "Apache Maven Wrapper startup batch script, version 3.3.2"
        SCRIPT_VERSION_REGEX = /
          Apache \s Maven \s Wrapper \s startup \s (?:batch \s)?
          script, \s version \s
          (?<version>\d+\.\d+(?:\.\d+)?)
        /x

        # Extracts the Maven Wrapper version declared in the mvnw / mvnw.cmd
        # shell scripts. Unix scripts (mvnw) are checked before Windows scripts
        # (mvnw.cmd); if neither contains the banner, nil is returned and the
        # caller falls back to other sources.
        sig { params(script_files: T::Array[DependencyFile]).returns(T.nilable(String)) }
        def self.load_wrapper_version_from_scripts(script_files)
          # Preferred order: Unix script first, Windows script as fallback.
          windows_scripts, unix_scripts = script_files.partition { |f| f.name.end_with?(".cmd") }
          unix_scripts.chain(windows_scripts).each do |file|
            next unless file.content

            T.must(file.content).each_line do |line|
              m = line.match(SCRIPT_VERSION_REGEX)
              return m[:version] if m
            end
          end
          nil
        end

        private_class_method :load_wrapper_version_from_scripts
        private_class_method :parse_wrapper_version_line
      end
    end
  end
end
