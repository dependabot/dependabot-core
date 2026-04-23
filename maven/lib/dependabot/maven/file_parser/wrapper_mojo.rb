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
          # Resolved distributionUrl value (the raw value from the properties file).
          # This value is mandatory
          const :distribution_url, String
          # The Maven Version extracted from the distributionUrl, e.g. "3.9.9"
          const :distribution_version, String

          # Value of distributionSha256Sum, or nil when the property is absent.
          # Checksum verification is not mandatory
          # Tracked as a second requirement on the Apache Maven dependency so the
          # checksum is updated atomically with the version.
          const :distribution_sha256_sum, T.nilable(String)

          # Value of wrapperSha256Sum, or nil when the property is absent.
          # Used to verify the wrapper JAR download
          const :wrapper_sha256_sum, T.nilable(String)

          # Version of the Maven Wrapper plugin, e.g. "3.3.4".
          # Sourced from the first strategy that succeeds:
          #  - wrapperVersion property (>=3.3.1),
          #  - version segment of wrapperUrl JAR filename (<3.3.0), or
          #  - comment in the mvnw script body (3.3.0 only, see MWRAPPER-120 and MWRAPPER-134).
          # This field is mandatory and raises if none of the sources yield a version.
          const :wrapper_version, String

          # The full JAR URL from the wrapperUrl property
          # (e.g. "https://.../maven-wrapper-3.3.3.jar"), used to compute the
          # new download URL for wrapperSha256Sum recomputation.
          # Present in both old-format (wrapperUrl only) and new-format (wrapperVersion + wrapperUrl) files.
          # nil only when the version was read from the mvnw script body (very old wrappers).
          const :wrapper_url, T.nilable(String)

          # Value of distributionType, controlling which binary artifacts are committed
          # alongside the wrapper scripts:
          #  - "bin" (JAR present),
          #  - "script" (JAR present),
          #  - "only-script" (no JAR),
          #  - "source" (MavenWrapperDownloader.java present).
          # Defaults to "bin" when the property is absent, matching pre-3.3.0 behavior.
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

          distribution_url = get_property_value(content, "distributionUrl")
          if distribution_url&.include?("mvnd")
            Dependabot.logger.warn("Maven daemon (mvnd) distribution is not supported, skipping wrapper update")
            return []
          end

          props = load_properties(content, script_files: script_files)

          if props.wrapper_url&.include?("takari")
            Dependabot.logger.warn("The Takari distribution is not supported, skipping wrapper update")
            return []
          end

          file_name = properties_file.name
          has_debug_scripts = debug_scripts?(script_files)
          deps = [build_distribution_dependency(file_name, props, props.distribution_version, has_debug_scripts)]
          deps << build_wrapper_dependency(
            file_name, props, props.distribution_version, props.wrapper_version, has_debug_scripts
          )
          deps.compact
        end

        sig do
          params(
            file_name: String,
            props: WrapperProperties,
            dist_version: String,
            has_debug_scripts: T::Boolean
          ).returns(Dependency)
        end
        def self.build_distribution_dependency(file_name, props, dist_version, has_debug_scripts)
          Dependency.new(
            name: Distributions::MAVEN_DISTRIBUTION_PACKAGE,
            version: dist_version,
            requirements: build_distribution_requirements(file_name, props, dist_version, has_debug_scripts),
            package_manager: "maven"
          )
        end

        sig do
          params(
            file_name: String,
            props: WrapperProperties,
            dist_version: String,
            has_debug_scripts: T::Boolean
          ).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def self.build_distribution_requirements(file_name, props, dist_version, has_debug_scripts)
          metadata = T.let(
            {
              packaging_type: "pom",
              wrapper_version: props.wrapper_version,
              distribution_type: props.distribution_type,
              distribution_version: dist_version,
              include_debug_script: has_debug_scripts
            },
            T::Hash[Symbol, T.untyped]
          )
          metadata[:distribution_sha256_sum] = props.distribution_sha256_sum if props.distribution_sha256_sum

          main_req = T.let(
            {
              requirement: dist_version,
              file: file_name,
              source: {
                type: Distributions::DISTRIBUTION_DEPENDENCY_TYPE,
                url: props.distribution_url,
                property: "distributionUrl"
              },
              groups: [],
              # The Apache Maven distribution is not a JAR, but a POM is available
              # We can use this POM to query for new versions using the existing update checker for maven
              metadata: metadata
            },
            T::Hash[Symbol, T.untyped]
          )

          requirements = T.let([main_req], T::Array[T::Hash[Symbol, T.untyped]])
          requirements.concat(build_wrapper_url_requirement(file_name, props))
          requirements
        end

        sig do
          params(
            file_name: String,
            props: WrapperProperties
          ).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def self.build_wrapper_url_requirement(file_name, props)
          return [] unless props.wrapper_url

          Dependabot.logger.debug "wrapperUrl is present #{props.wrapper_url} version=#{props.wrapper_version}"
          metadata = T.let({}, T::Hash[Symbol, T.untyped])
          metadata[:wrapper_sha256_sum] = props.wrapper_sha256_sum if props.wrapper_sha256_sum

          req = T.let(
            {
              requirement: props.wrapper_version,
              file: file_name,
              source: {
                type: Distributions::DISTRIBUTION_DEPENDENCY_TYPE,
                property: "wrapperUrl",
                url: props.wrapper_url
              },
              groups: []
            },
            T::Hash[Symbol, T.untyped]
          )
          req[:metadata] = metadata if metadata.any?
          [req]
        end

        sig do
          params(
            file_name: String,
            props: WrapperProperties,
            dist_version: String,
            wrapper_version: String,
            has_debug_scripts: T::Boolean
          ).returns(Dependency)
        end
        def self.build_wrapper_dependency(file_name, props, dist_version, wrapper_version, has_debug_scripts)
          metadata = T.let(
            {
              packaging_type: "pom",
              distribution_version: dist_version,
              wrapper_version: wrapper_version,
              distribution_type: props.distribution_type,
              include_debug_script: has_debug_scripts
            },
            T::Hash[Symbol, T.untyped]
          )
          Dependency.new(
            name: Distributions::MAVEN_WRAPPER_PACKAGE,
            version: props.wrapper_version,
            requirements: [
              {
                requirement: props.wrapper_version,
                file: file_name,
                source: {
                  type: Distributions::DISTRIBUTION_DEPENDENCY_TYPE,
                  property: "wrapperVersion"
                },
                groups: [],
                metadata: metadata
              }
            ],
            package_manager: "maven"
          )
        end

        sig { params(content: String).returns(String) }
        def self.resolve_distribution_type(content)
          get_property_value(content, "distributionType") || "bin"
        end

        sig { params(script_files: T::Array[DependencyFile]).returns(T::Boolean) }
        def self.debug_scripts?(script_files)
          debug_scripts = %w(mvnwDebug mvnwDebug.cmd)
          script_files.any? { |f| debug_scripts.any? { |s| f.name.end_with?(s) } }
        end

        sig { params(content: String, script_files: T::Array[DependencyFile]).returns(WrapperProperties) }
        def self.load_properties(content, script_files: [])
          distribution_url = get_property_value!(content, "distributionUrl")
          distribution_version = extract_distribution_version(distribution_url)
          distribution_sha256_sum = get_property_value(content, "distributionSha256Sum")
          wrapper_url = get_property_value(content, "wrapperUrl")
          wrapper_sha256_sum = get_property_value(content, "wrapperSha256Sum")
          distribution_type = resolve_distribution_type(content)
          wrapper_version = resolve_wrapper_version(content, wrapper_url, script_files)

          WrapperProperties.new(
            distribution_url: distribution_url,
            distribution_version: distribution_version,
            distribution_sha256_sum: distribution_sha256_sum,
            wrapper_sha256_sum: wrapper_sha256_sum,
            wrapper_version: wrapper_version,
            wrapper_url: wrapper_url,
            distribution_type: distribution_type
          )
        end

        sig { params(content: String).returns(String) }
        def self.extract_distribution_version(content)
          match = content.match(DIST_URL_VERSION_REGEX)
          raise "Could not extract Maven version from content" unless match && match[:version]

          T.must(match[:version])
        end

        sig { params(content: String, target_key: String).returns(T.nilable(String)) }
        def self.get_property_value(content, target_key)
          # 1. Handle Java line continuations (the backslash edge case)
          # We join lines ending in \ before splitting into an array
          normalized_content = content.gsub(/\\\n\s*/, "")

          # 2. Escape the key for Regex safety
          escaped_key = Regexp.escape(target_key)

          # 3. Define the pattern:
          # Start of line -> Key -> optional space -> delimiter (= or :) -> value
          pattern = /^\s*#{escaped_key}\s*[=:]\s*(.*)$/

          normalized_content.lines.each do |line|
            next if line.start_with?("#", "!") # Skip Java comments

            if (match = line.match(pattern))
              return T.must(match[1]).strip
            end
          end
          nil
        end

        sig { params(content: String, target_key: String).returns(String) }
        def self.get_property_value!(content, target_key)
          value = get_property_value(content, target_key)

          raise "Missing mandatory property: #{target_key}" if value.nil?

          value
        end

        private_class_method :build_distribution_dependency
        private_class_method :build_wrapper_dependency
        private_class_method :build_distribution_requirements
        private_class_method :build_wrapper_url_requirement

        # Matches the human-readable banner embedded in mvnw / mvnw.cmd, e.g.:
        #   "Apache Maven Wrapper startup script, version 3.3.2"
        #   "Apache Maven Wrapper startup batch script, version 3.3.2"
        SCRIPT_VERSION_REGEX = /
          Apache \s Maven \s Wrapper \s startup \s (?:batch \s)?
          script, \s version \s
          (?<version>\d+\.\d+(?:\.\d+)?)
        /x

        sig do
          params(
            content: String,
            wrapper_url: T.nilable(String),
            script_files: T::Array[DependencyFile]
          ).returns(String)
        end
        def self.resolve_wrapper_version(content, wrapper_url, script_files)
          version = get_property_value(content, "wrapperVersion")
          return version if version

          version = parse_version_from_wrapper_url(wrapper_url) if wrapper_url
          return version if version

          if script_files.any?
            Dependabot.logger.warn "Maven Wrapper with no wrapperVersion or wrapperUrl in properties file"
            version = load_wrapper_version_from_scripts(script_files)
          end

          if version.nil?
            raise "Could not determine Maven Wrapper version from wrapperVersion, wrapperUrl, or script files"
          end

          version
        end

        sig { params(url: String).returns(T.nilable(String)) }
        def self.parse_version_from_wrapper_url(url)
          match = url.match(/-(?<version>\d+\.\d+(?:\.\d+)?(?:-\w+)*)(?:-bin)?\.jar/)
          match&.[](:version)
        end

        # Extracts the Maven Wrapper version declared in the mvnw / mvnw.cmd
        # shell scripts. Unix scripts (mvnw) are checked before Windows scripts (mvnw.cmd)
        # if neither contains the banner, nil is returned and the caller falls back to other sources.
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

        private_class_method :resolve_wrapper_version
        private_class_method :parse_version_from_wrapper_url
        private_class_method :load_wrapper_version_from_scripts
      end
    end
  end
end
