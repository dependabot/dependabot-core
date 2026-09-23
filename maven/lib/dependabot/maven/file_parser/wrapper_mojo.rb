# typed: strong
# frozen_string_literal: true

# Parses maven-wrapper.properties and emits Dependency objects for the two
# tracked Maven coordinates: org.apache.maven:apache-maven (the maven distribution)
# and org.apache.maven.wrapper:maven-wrapper (the wrapper plugin).
require "uri"
require "dependabot/dependency_requirement"
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
          # When none of the sources yield a version, load_properties returns nil and the
          # wrapper is skipped, so this field is only ever set to a resolved version.
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
        # not the raw properties line). Match the standard artifact filename so
        # custom mirrors do not need to preserve Maven Central's directory layout.
        DIST_URL_VERSION_REGEX = %r{
          /apache-maven-(?<version>[^/?#]+)-(?:bin|src)\.(?:zip|tar\.gz)(?:[?#].*)?\z
        }x

        # Apache Maven Wrapper JAR as it appears in a wrapperUrl path. Anchored to the artifact
        # directory, a numeric version directory, and a `maven-wrapper-<version>.jar` filename whose
        # version equals that directory (via the \k<version> backreference), mirroring Maven's
        # mandatory repository layout. This rejects foreign JARs sharing the directory (e.g.
        # .../maven-wrapper/3.3.4/foreign-3.3.4.jar), non-artifact filenames
        # (.../3.3.4/maven-wrapper-foreign.jar) and mismatched coordinates
        # (.../3.3.4/maven-wrapper-9.9.9.jar). Matched on the path only (not the host, query, or
        # fragment) so wrappers proxied through private registries are still recognised, while
        # wrappers from other vendors (e.g. legacy io.takari) are not. Applied in apache_wrapper_url?.
        WRAPPER_COORDINATE_REGEX = %r{
          /org/apache/maven/wrapper/maven-wrapper/    # Apache Maven Wrapper artifact directory
          (?<version>\d+\.\d+(?:\.\d+)?(?:-\w+)*)/     # version directory
          maven-wrapper-\k<version>\.jar\z            # artifact JAR named for that same version
        }xi

        sig do
          params(
            properties_file: DependencyFile,
            script_files: T::Array[DependencyFile]
          ).returns(T::Array[Dependency])
        end
        def self.resolve_dependencies(properties_file, script_files: [])
          content = properties_file.content
          return [] unless content

          # load_properties returns nil for wrappers we cannot safely update (missing
          # mandatory data or an unsupported vendor/distribution). The reason is logged there,
          # and we skip the wrapper without disrupting ordinary POM dependency parsing.
          props = load_properties(content, script_files: script_files)
          return [] unless props

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
          ).returns(T::Array[Dependabot::DependencyRequirement])
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
            Dependabot::DependencyRequirement::ObjectHash
          )
          metadata[:distribution_sha256_sum] = props.distribution_sha256_sum if props.distribution_sha256_sum

          main_req = Dependabot::DependencyRequirement.create(
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
            }
          )

          requirements = T.let([main_req], T::Array[Dependabot::DependencyRequirement])
          requirements.concat(build_wrapper_url_requirement(file_name, props))
          requirements
        end

        sig do
          params(
            file_name: String,
            props: WrapperProperties
          ).returns(T::Array[Dependabot::DependencyRequirement])
        end
        def self.build_wrapper_url_requirement(file_name, props)
          return [] unless props.wrapper_url

          Dependabot.logger.debug "wrapperUrl is present #{props.wrapper_url} version=#{props.wrapper_version}"
          metadata = T.let({}, Dependabot::DependencyRequirement::ObjectHash)
          metadata[:wrapper_sha256_sum] = props.wrapper_sha256_sum if props.wrapper_sha256_sum

          req = Dependabot::DependencyRequirement.create(
            {
              requirement: props.wrapper_version,
              file: file_name,
              source: {
                type: Distributions::DISTRIBUTION_DEPENDENCY_TYPE,
                property: "wrapperUrl",
                url: props.wrapper_url
              },
              groups: []
            }
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
            Dependabot::DependencyRequirement::ObjectHash
          )
          Dependency.new(
            name: Distributions::MAVEN_WRAPPER_PACKAGE,
            version: props.wrapper_version,
            requirements: [
              Dependabot::DependencyRequirement.create(
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
              )
            ],
            package_manager: "maven"
          )
        end

        # Resolves the distribution type, matching the maven-wrapper-plugin's own precedence:
        # an explicit distributionType wins; otherwise the plugin defaults to "only-script" (since
        # 3.2.0). Legacy pre-3.3.0 files omit distributionType but carry a wrapperUrl pointing at the
        # maven-wrapper JAR, which means a JAR-based ("bin") setup, so we keep that for them.
        # https://maven.apache.org/tools/wrapper/maven-wrapper-plugin/wrapper-mojo.html
        sig { params(content: String, wrapper_url: T.nilable(String)).returns(String) }
        def self.resolve_distribution_type(content, wrapper_url)
          explicit = get_property_value(content, "distributionType")
          return explicit if explicit

          wrapper_url ? "bin" : "only-script"
        end

        sig { params(script_files: T::Array[DependencyFile]).returns(T::Boolean) }
        def self.debug_scripts?(script_files)
          debug_scripts = %w(mvnwDebug mvnwDebug.cmd)
          script_files.any? { |f| debug_scripts.any? { |s| f.name.end_with?(s) } }
        end

        sig { params(content: String, script_files: T::Array[DependencyFile]).returns(T.nilable(WrapperProperties)) }
        def self.load_properties(content, script_files: [])
          distribution_url = get_property_value(content, "distributionUrl")
          return skip_wrapper("distributionUrl property is missing") unless distribution_url

          return skip_wrapper("Maven daemon (mvnd) distribution is not supported") if distribution_url.include?("mvnd")

          distribution_version = extract_distribution_version(distribution_url)
          return skip_wrapper("could not extract Maven version from distributionUrl") unless distribution_version

          wrapper_url = get_property_value(content, "wrapperUrl")
          if wrapper_url && !apache_wrapper_url?(wrapper_url)
            return skip_wrapper("wrapperUrl is not an Apache Maven Wrapper")
          end

          wrapper_version = resolve_wrapper_version(content, wrapper_url, script_files)
          unless wrapper_version
            return skip_wrapper(
              "could not determine Maven Wrapper version from wrapperVersion, wrapperUrl, or script files"
            )
          end

          WrapperProperties.new(
            distribution_url: distribution_url,
            distribution_version: distribution_version,
            distribution_sha256_sum: get_property_value(content, "distributionSha256Sum"),
            wrapper_sha256_sum: get_property_value(content, "wrapperSha256Sum"),
            wrapper_version: wrapper_version,
            wrapper_url: wrapper_url,
            distribution_type: resolve_distribution_type(content, wrapper_url)
          )
        end

        # Signals that the wrapper cannot be updated: logs the reason and returns nil so the
        # caller treats the wrapper as absent rather than aborting the whole Maven parse.
        sig { params(reason: String).returns(NilClass) }
        def self.skip_wrapper(reason)
          Dependabot.logger.warn("#{reason}, skipping Maven Wrapper update")
          nil
        end

        sig { params(content: String).returns(T.nilable(String)) }
        def self.extract_distribution_version(content)
          match = content.match(DIST_URL_VERSION_REGEX)
          match && match[:version]
        end

        # True when the wrapperUrl points at the Apache Maven Wrapper artifact. The coordinate is
        # matched against the URL path only (never the query or fragment) so that a non-Apache JAR
        # cannot slip through the allowlist by carrying the coordinate in a `?redirect=...` query.
        # A malformed URL that cannot be parsed is treated as not-Apache.
        sig { params(url: String).returns(T::Boolean) }
        def self.apache_wrapper_url?(url)
          path = URI.parse(url).path
          return false unless path

          path.match?(WRAPPER_COORDINATE_REGEX)
        rescue URI::InvalidURIError
          false
        end

        sig { params(content: String, target_key: String).returns(T.nilable(String)) }
        def self.get_property_value(content, target_key)
          # 1. Handle Java line continuations (the backslash edge case)
          # We join lines ending in \ before splitting into an array
          normalized_content = content.gsub(/\\\n\s*/, "")

          # 2. Escape the key for Regex safety
          escaped_key = Regexp.escape(target_key)

          # Start of line -> Key -> optional space -> delimiter (= or :) -> value.
          # Bounded to spaces/tabs (not \s) so the per-line match can't backtrack polynomially.
          pattern = /^[ \t]*#{escaped_key}[ \t]*[=:][ \t]*(.*)$/

          normalized_content.lines.each do |line|
            next if line.start_with?("#", "!") # Skip Java comments

            if (match = line.match(pattern))
              return decode_property_value(T.must(match[1]).strip)
            end
          end
          nil
        end

        # Decodes Java properties escapes so URLs are usable by URI parsing, registry matching, and
        # HTTP clients. Maven commonly writes URL schemes as `https\://` in legacy wrapper files.
        sig { params(value: String).returns(String) }
        def self.decode_property_value(value)
          value.gsub(/\\(?:u(?<unicode>[0-9a-fA-F]{4})|(?<escaped>.))/) do
            unicode = Regexp.last_match(:unicode)
            next [unicode.hex].pack("U") if unicode

            case Regexp.last_match(:escaped)
            when "t" then "\t"
            when "n" then "\n"
            when "r" then "\r"
            when "f" then "\f"
            else Regexp.last_match(:escaped)
            end
          end
        end

        private_class_method :build_distribution_dependency
        private_class_method :build_wrapper_dependency
        private_class_method :build_distribution_requirements
        private_class_method :build_wrapper_url_requirement
        private_class_method :decode_property_value

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
          ).returns(T.nilable(String))
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
        private_class_method :skip_wrapper
        private_class_method :apache_wrapper_url?
      end
    end
  end
end
