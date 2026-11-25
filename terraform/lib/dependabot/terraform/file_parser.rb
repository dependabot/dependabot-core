# typed: strict
# frozen_string_literal: true

require "excon"
require "nokogiri"
require "open3"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/hcl2_json_document"
require "dependabot/file_parsers/hcl_module_source"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/terraform/file_selector"
require "dependabot/terraform/registry_client"
require "dependabot/terraform/package_manager"

module Dependabot
  module Terraform
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      include FileSelector

      HclDocument = Dependabot::FileParsers::Hcl2JsonDocument
      ModuleSource = Dependabot::FileParsers::HclModuleSource

      DEFAULT_REGISTRY = "registry.terraform.io"
      DEFAULT_NAMESPACE = "hashicorp"
      # https://www.terraform.io/docs/language/providers/requirements.html#source-addresses
      PROVIDER_SOURCE_ADDRESS = %r{\A((?<hostname>.+)/)?(?<namespace>.+)/(?<name>.+)\z}

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new

        parse_terraform_files(dependency_set)

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

      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).void }
      def parse_terraform_files(dependency_set)
        terraform_files.each do |file|
          # Process module declarations only for non-support files
          # (we can't update local path modules in support files)
          unless file.support_file?
            document = parsed_file(file)
            overrides = override_terraform_files.map { |override_file| parsed_file(override_file) }
            document.module_declarations(overrides: overrides).each do |details|
              source = source_from(details.source)
              next unless source

              dependency_set << build_terraform_dependency(file, source, details)
            end
          end

          # Always process provider requirements, even in support files
          # (nested local modules can have their own provider requirements)
          parsed_file(file).provider_declarations.each do |provider|
            deprecated_provider_error(file) if provider.is_a?(HclDocument::DeprecatedProvider)
            dependency_set << build_provider_dependency(file, provider.name, provider.source, provider.version)
          end
        end
      end
      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).void }
      def parse_terragrunt_files(dependency_set)
        terragrunt_files.each do |file|
          parsed_file(file).terragrunt_sources.each do |raw_source|
            source = source_from(raw_source)
            next unless source

            dependency_set << build_terragrunt_dependency(file, source)
          end
        end
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          source: ModuleSource::Variant,
          details: HclDocument::ModuleDeclaration
        )
          .returns(Dependabot::Dependency)
      end
      def build_terraform_dependency(file, source, details)
        # dep_name should be unique for a source, using the info derived from
        # the source or the source name provides this uniqueness
        dep_name = case source
                   when ModuleSource::Registry then source.module_identifier
                   when ModuleSource::Git then source.dependency_name(details.name)
                   else details.name
                   end
        version_req = details.version&.strip
        version =
          if source.is_a?(ModuleSource::Git) then source.version
          elsif version_req&.match?(/^\d/) then version_req
          end

        Dependency.new(
          name: dep_name,
          version: version,
          package_manager: "terraform",
          requirements: [
            { requirement: version_req,
              groups: [],
              file: file.name,
              source: source.to_requirement_source }
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
          package_manager: "terraform",
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
          "This terraform provider syntax is now deprecated.\n" \
          "See https://www.terraform.io/docs/language/providers/requirements.html " \
          "for the new Terraform v0.13+ provider syntax."
        )
      end

      sig { params(file: Dependabot::DependencyFile, source: ModuleSource::Variant).returns(Dependabot::Dependency) }
      def build_terragrunt_dependency(file, source)
        url = source.url if source.is_a?(ModuleSource::Git) || source.is_a?(ModuleSource::Url)

        Dependency.new(
          name: ModuleSource.terragrunt_name(url),
          version: source.is_a?(ModuleSource::Git) ? source.version : nil,
          package_manager: "terraform",
          requirements: [
            { requirement: nil,
              groups: [],
              file: file.name,
              source: source.to_requirement_source }
          ]
        )
      end

      # Full docs at https://www.terraform.io/docs/modules/sources.html
      sig { params(raw_source: String).returns(T.nilable(ModuleSource::Variant)) }
      def source_from(raw_source)
        bare_source = RegistryClient.get_proxied_source(raw_source)
        source = ModuleSource.parse(
          bare_source,
          default_registry: DEFAULT_REGISTRY,
          archive_extensions: RegistryClient::ARCHIVE_EXTENSIONS,
          proxy_url: raw_source == bare_source ? nil : raw_source
        )
        source unless source.is_a?(ModuleSource::Interpolation)
      end

      sig { params(source_address: T.nilable(String), name: String).returns([String, String, String]) }
      def provider_source_from(source_address, name)
        matches = source_address&.match(PROVIDER_SOURCE_ADDRESS)
        matches = {} if matches.nil?

        # Terraform provider source addresses are case-insensitive, so we normalize
        # to lowercase to avoid treating e.g. "Azure/azapi" and "azure/azapi" as
        # different sources when merging dependencies across multiple files.
        [
          (matches[:hostname] || DEFAULT_REGISTRY).downcase,
          (matches[:namespace] || DEFAULT_NAMESPACE).downcase,
          (matches[:name] || name).downcase
        ]
      end

      sig { params(file: Dependabot::DependencyFile).returns(HclDocument) }
      def parsed_file(file)
        @parsed_buildfile ||= T.let({}, T.nilable(T::Hash[String, HclDocument]))
        @parsed_buildfile[file.name] ||= SharedHelpers.in_a_temporary_directory do
          File.write("tmp.tf", file.content)

          command = "#{terraform_hcl2_parser_path} < tmp.tf"
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
      def terraform_parser_path
        helper_bin_dir = File.join(native_helpers_root, "terraform/bin")
        Pathname.new(File.join(helper_bin_dir, "json2hcl")).cleanpath.to_path
      end

      sig { returns(String) }
      def terraform_hcl2_parser_path
        helper_bin_dir = File.join(native_helpers_root, "terraform/bin")
        Pathname.new(File.join(helper_bin_dir, "hcl2json")).cleanpath.to_path
      end

      sig { returns(String) }
      def native_helpers_root
        default_path = File.join(__dir__, "../../../helpers/install-dir")
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
      end

      sig { override.void }
      def check_required_files
        return if [*terraform_files, *terragrunt_files].any?

        raise "No Terraform configuration file!"
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
          PackageManager.new(T.must(terraform_version)),
          T.nilable(Dependabot::Terraform::PackageManager)
        )
      end

      sig { returns(T.nilable(String)) }
      def terraform_version
        @terraform_version ||= T.let(
          begin
            version = SharedHelpers.run_shell_command("terraform --version")
            version.match(Dependabot::Ecosystem::VersionManager::DEFAULT_VERSION_PATTERN)&.captures&.first
          end,
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileParsers
  .register("terraform", Dependabot::Terraform::FileParser)
