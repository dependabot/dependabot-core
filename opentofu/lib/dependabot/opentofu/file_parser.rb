# typed: strict
# frozen_string_literal: true

require "excon"
require "nokogiri"
require "open3"
require "uri"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/hcl2_json_document"
require "dependabot/file_parsers/hcl_module_source"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/opentofu/file_selector"
require "dependabot/opentofu/registry_client"
require "dependabot/opentofu/package_manager"

module Dependabot
  module Opentofu
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      include FileSelector

      HclDocument = Dependabot::FileParsers::Hcl2JsonDocument
      ModuleSource = Dependabot::FileParsers::HclModuleSource

      class OciSource < T::ImmutableStruct
        extend T::Sig

        class Tag < T::ImmutableStruct
          const :value, String
        end

        class Digest < T::ImmutableStruct
          const :value, String
        end

        const :artifact_identifier, T.nilable(String)
        const :subdirectory, T.nilable(String)
        const :pin, T.nilable(T.any(Tag, Digest))
        const :proxy_url, T.nilable(String)

        sig { params(source: String, proxy_url: T.nilable(String)).returns(T.nilable(OciSource)) }
        def self.parse(source, proxy_url:)
          location = source.split("oci://").last
          # Keep the error for a bare scheme distinct from a source without a query.
          raise NoMethodError, "undefined method 'split' for nil" unless location

          uri_part, query = location.split("?", 2)
          return if query.nil?

          # Only the bare repository, before the sub-module path, is queryable for tags.
          artifact_identifier, subdirectory = T.must(uri_part).split(%r{(?<!:)//}, 2)
          new(
            artifact_identifier: artifact_identifier,
            subdirectory: subdirectory,
            pin: pin_from(source, query),
            proxy_url: proxy_url
          )
        end

        sig { returns(T.nilable(String)) }
        def version
          pin&.value
        end

        sig { returns(ModuleSource::RequirementSource) }
        def to_requirement_source
          source_pin = pin
          ModuleSource.with_proxy_url(
            {
              type: "oci",
              artifact_identifier: artifact_identifier,
              subdirectory: subdirectory,
              tag: (source_pin.value if source_pin.is_a?(Tag)),
              digest: (source_pin.value if source_pin.is_a?(Digest)),
              version: version
            },
            proxy_url
          )
        end

        sig { params(source: String, query: String).returns(T.nilable(T.any(Tag, Digest))) }
        def self.pin_from(source, query)
          pins = URI.decode_www_form(query).to_h
          tag = pins["tag"]
          digest = pins["digest"]

          if tag && !tag.empty?
            if digest && !digest.empty?
              raise DependencyFileNotEvaluatable,
                    "Invalid OCI source '#{source}': only one of `tag` or `digest` may be specified"
            end

            return Tag.new(value: tag)
          end

          Digest.new(value: digest) if digest && !digest.empty?
        end
        private_class_method :pin_from
      end

      SourceVariant = T.type_alias { T.any(ModuleSource::Variant, OciSource) }

      DEFAULT_REGISTRY = "registry.opentofu.org"
      DEFAULT_NAMESPACE = "hashicorp"
      # https://opentofu.org/docs/language/providers/requirements/#source-addresses
      PROVIDER_SOURCE_ADDRESS = %r{\A((?<hostname>.+)/)?(?<namespace>.+)/(?<name>.+)\z}
      LOCAL_REFERENCE_REGEX = /\A\$\{local\.(?<var_name>[^}]+)\}\z/

      # Namespaces reserved for providers bundled with the OpenTofu/Terraform
      # binary. Providers in these namespaces cannot be updated independently
      # because their version tracks the binary itself.
      # See: https://pkg.go.dev/github.com/opentofu/registry-address/v2#Provider.IsBuiltIn
      BUILTIN_PROVIDER_NAMESPACES = %w(
        terraform.io/builtin
        opentofu.org/builtin
      ).freeze

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        parse_opentofu_files(dependency_set)

        parse_terragrunt_files(dependency_set)

        dependency_set.dependencies.sort_by(&:name)
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          begin
            Ecosystem.new(
              name: ECOSYSTEM,
              package_manager: package_manager
            )
          end,
          T.nilable(Dependabot::Ecosystem)
        )
      end

      private

      sig { returns(T::Hash[String, T::Hash[Symbol, String]]) }
      def locals_lookup
        @locals_lookup ||= T.let(
          begin
            lookup = T.let({}, T::Hash[String, T::Hash[Symbol, String]])
            opentofu_files.each do |file|
              parsed_file(file).local_strings.each do |var_name, value|
                next if value.include?("${")

                lookup[var_name] = { value: value, file: file.name }
              end
            end
            lookup
          end,
          T.nilable(T::Hash[String, T::Hash[Symbol, String]])
        )
      end

      sig { params(version_string: String).returns(T.nilable(T::Hash[Symbol, String])) }
      def resolve_local_reference(version_string)
        match = version_string.match(LOCAL_REFERENCE_REGEX)
        return nil unless match

        var_name = T.must(match[:var_name])
        local_entry = locals_lookup[var_name]
        return nil unless local_entry

        { value: T.must(local_entry[:value]), variable: var_name, file: T.must(local_entry[:file]) }
      end

      sig { params(source_address: T.nilable(String)).returns(T::Boolean) }
      def builtin_provider?(source_address)
        return false unless source_address

        normalized = source_address.downcase
        BUILTIN_PROVIDER_NAMESPACES.any? { |ns| normalized.start_with?("#{ns}/") }
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).void }
      def parse_opentofu_files(dependency_set)
        opentofu_files.each do |file|
          next if file.support_file?

          document = parsed_file(file)
          overrides = override_opentofu_files.map { |override_file| parsed_file(override_file) }
          document.module_declarations(overrides: overrides).each do |details|
            source = source_from(details.source)
            next unless source

            # Cannot update modules using early evaluation yet
            if source.is_a?(ModuleSource::Interpolation)
              Dependabot.logger.warn(
                "Cannot parse module source name with early evaluation for #{details.name} in #{file.name}."
              )
              next
            end

            dependency_set << build_opentofu_dependency(file, source, details)
          end

          parsed_file(file).provider_declarations.each do |provider|
            deprecated_provider_error(file) if provider.is_a?(HclDocument::DeprecatedProvider)
            source_address = provider.source
            if builtin_provider?(source_address)
              Dependabot.logger.info("Skipping built-in provider #{provider.name} in #{file.name}")
              next
            end

            dependency_set << build_provider_dependency(file, provider.name, source_address, provider.version)
          end
        end
      end

      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).void }
      def parse_terragrunt_files(dependency_set)
        terragrunt_files.each do |file|
          parsed_file(file).terragrunt_sources.each do |raw_source|
            source = source_from(raw_source)
            next unless source

            # Cannot update modules using early evaluation yet
            if source.is_a?(ModuleSource::Interpolation)
              Dependabot.logger.warn(
                "Cannot parse terragrunt module source with early evaluation in #{file.name}."
              )
              next
            end

            dependency_set << build_terragrunt_dependency(file, source)
          end
        end
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          source: SourceVariant,
          details: HclDocument::ModuleDeclaration
        )
          .returns(Dependabot::Dependency)
      end
      def build_opentofu_dependency(file, source, details)
        # dep_name should be unique for a source, using the info derived from
        # the source or the source name provides this uniqueness
        dep_name = case source
                   when ModuleSource::Registry then source.module_identifier
                   when ModuleSource::Git then source.dependency_name(details.name)
                   else details.name
                   end
        version_req = details.version&.strip

        req_file = file.name
        resolved = version_req ? resolve_local_reference(version_req) : nil
        if resolved
          version_req = resolved[:value]
          req_file = T.must(resolved[:file])
        end

        version =
          if source.is_a?(ModuleSource::Git) || source.is_a?(OciSource) then source.version
          elsif version_req&.match?(/^\d/) then version_req
          end

        requirement_source = source.to_requirement_source
        requirement_source[:local_variable] = resolved[:variable] if resolved

        Dependency.new(
          name: dep_name,
          version: version,
          package_manager: "opentofu",
          requirements: [
            { requirement: version_req,
              groups: [],
              file: req_file,
              source: requirement_source }
          ]
        )
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          name: String,
          source_address: T.nilable(String),
          requirement: T.nilable(String)
        )
          .returns(Dependabot::Dependency)
      end
      def build_provider_dependency(file, name, source_address, requirement)
        version_req = requirement&.strip
        hostname, namespace, name = provider_source_from(source_address, name)
        dependency_name = source_address ? "#{namespace}/#{name}" : name

        Dependency.new(
          name: dependency_name,
          version: determine_version_for(hostname, namespace, name, version_req),
          package_manager: "opentofu",
          requirements: [
            { requirement: version_req,
              groups: [],
              file: file.name,
              source: {
                type: "provider",
                registry_hostname: hostname,
                module_identifier: "#{namespace}/#{name}"
              } }
          ]
        )
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.noreturn) }
      def deprecated_provider_error(file)
        raise Dependabot::DependencyFileNotParseable.new(
          file.path,
          "This provider syntax is now deprecated.\n" \
          "See https://opentofu.org/docs/language/providers/requirements/" \
          "for the supported provider syntax."
        )
      end

      sig { params(file: Dependabot::DependencyFile, source: SourceVariant).returns(Dependabot::Dependency) }
      def build_terragrunt_dependency(file, source)
        url = source.url if source.is_a?(ModuleSource::Git) || source.is_a?(ModuleSource::Url)

        Dependency.new(
          name: ModuleSource.terragrunt_name(url),
          version: source.is_a?(ModuleSource::Git) ? source.version : nil,
          package_manager: "opentofu",
          requirements: [
            { requirement: nil,
              groups: [],
              file: file.name,
              source: source.to_requirement_source }
          ]
        )
      end

      # Full docs at https://opentofu.org/docs/language/modules/sources/
      sig { params(raw_source: String).returns(T.nilable(T.any(SourceVariant, ModuleSource::Interpolation))) }
      def source_from(raw_source)
        bare_source = RegistryClient.get_proxied_source(raw_source)
        proxy_url = raw_source == bare_source ? nil : raw_source
        if bare_source.include?("oci://") && !ModuleSource.interpolation?(bare_source)
          return OciSource.parse(bare_source, proxy_url: proxy_url)
        end

        share_registry_identifier_case(
          ModuleSource.parse(
            bare_source,
            default_registry: DEFAULT_REGISTRY,
            archive_extensions: RegistryClient::ARCHIVE_EXTENSIONS,
            proxy_url: proxy_url
          )
        )
      end

      # Declarations of the same module that only differ in case must share one
      # source, otherwise `Dependency#source_details` raises "Multiple sources!".
      # The first declaration found decides the case that is used for all of them.
      sig do
        params(source: T.nilable(T.any(SourceVariant, ModuleSource::Interpolation)))
          .returns(T.nilable(T.any(SourceVariant, ModuleSource::Interpolation)))
      end
      def share_registry_identifier_case(source)
        return source unless source.is_a?(ModuleSource::Registry)

        @module_identifiers ||= T.let({}, T.nilable(T::Hash[String, String]))
        identifier = @module_identifiers[source.module_identifier.downcase] ||= source.module_identifier
        return source if identifier == source.module_identifier

        ModuleSource::Registry.new(
          registry_hostname: source.registry_hostname,
          module_identifier: identifier,
          proxy_url: source.proxy_url
        )
      end

      sig { params(source_address: T.nilable(String), name: String).returns([String, String, String]) }
      def provider_source_from(source_address, name)
        matches = source_address&.match(PROVIDER_SOURCE_ADDRESS)
        matches = {} if matches.nil?

        # OpenTofu provider source addresses are case-insensitive, so we normalize
        # to lowercase to avoid treating e.g. "Azure/azapi" and "azure/azapi" as
        # different sources when merging dependencies across multiple files.
        [
          (matches[:hostname] || DEFAULT_REGISTRY).downcase,
          (matches[:namespace] || DEFAULT_NAMESPACE).downcase,
          (matches[:name] || name).downcase
        ]
      end

      # rubocop:enable Metrics/PerceivedComplexity

      sig { params(file: Dependabot::DependencyFile).returns(HclDocument) }
      def parsed_file(file)
        @parsed_buildfile ||= T.let({}, T.nilable(T::Hash[String, HclDocument]))
        @parsed_buildfile[file.name] ||= SharedHelpers.in_a_temporary_directory do
          File.write("tmp.tf", file.content)

          command = "#{opentofu_hcl2_parser_path} < tmp.tf"
          start = Time.now
          stdout, stderr, process = Open3.capture3(command)
          time_taken = Time.now - start

          unless process.success?
            raise SharedHelpers::HelperSubprocessFailed.new(
              message: stderr,
              error_context: {
                command: command,
                time_taken: time_taken,
                process_exit_value: process.to_s
              }
            )
          end

          HclDocument.from_helper_output(stdout, file: file)
        end
      rescue SharedHelpers::HelperSubprocessFailed => e
        msg = e.message.strip
        raise Dependabot::DependencyFileNotParseable.new(file.path, msg)
      end

      sig { returns(String) }
      def opentofu_parser_path
        helper_bin_dir = File.join(native_helpers_root, "opentofu/bin")
        Pathname.new(File.join(helper_bin_dir, "json2hcl")).cleanpath.to_path
      end

      sig { returns(String) }
      def opentofu_hcl2_parser_path
        helper_bin_dir = File.join(native_helpers_root, "opentofu/bin")
        Pathname.new(File.join(helper_bin_dir, "hcl2json")).cleanpath.to_path
      end

      sig { returns(String) }
      def native_helpers_root
        default_path = File.join(__dir__, "../../../helpers/install-dir")
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
      end

      sig { override.void }
      def check_required_files
        return if [*opentofu_files, *terragrunt_files].any?

        raise "No OpenTofu configuration file!"
      end

      sig do
        params(
          hostname: String,
          namespace: String,
          name: String,
          constraint: T.nilable(String)
        )
          .returns(T.nilable(String))
      end
      def determine_version_for(hostname, namespace, name, constraint)
        return constraint if constraint&.match?(/\A\d/)

        lockfile_content&.provider_version("#{hostname}/#{namespace}/#{name}")
      end

      sig { returns(T.nilable(HclDocument)) }
      def lockfile_content
        @lockfile_content ||= T.let(
          begin
            lockfile = dependency_files.find do |file|
              file.name == ".terraform.lock.hcl"
            end
            parsed_file(lockfile) if lockfile
          end,
          T.nilable(HclDocument)
        )
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(T.must(opentofu_version)),
          T.nilable(Dependabot::Opentofu::PackageManager)
        )
      end

      sig { returns(T.nilable(String)) }
      def opentofu_version
        @opentofu_version ||= T.let(
          begin
            version = SharedHelpers.run_shell_command("tofu --version")
            version.match(Dependabot::Ecosystem::VersionManager::DEFAULT_VERSION_PATTERN)&.captures&.first
          end,
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileParsers
  .register("opentofu", Dependabot::Opentofu::FileParser)
