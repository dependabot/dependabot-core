# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "json"
require "open3"
require "securerandom"
require "dependabot/shared_helpers"
require "dependabot/terraform/file_updater"

module Dependabot
  module Terraform
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Builds a Terraform CLI config that uses dev_overrides for non-target
      # providers, preventing Terraform from resolving private/custom providers
      # during lockfile updates.
      class ProviderCliConfigBuilder
        extend T::Sig

        DEFAULT_REGISTRY = "registry.terraform.io"
        DEFAULT_NAMESPACE = "hashicorp"

        sig do
          params(
            dependency: Dependabot::Dependency,
            terraform_files: T::Array[Dependabot::DependencyFile],
            native_helpers_path: T.nilable(String)
          ).void
        end
        def initialize(dependency:, terraform_files:, native_helpers_path: nil)
          @dependency = dependency
          @terraform_files = terraform_files
          @native_helpers_path = native_helpers_path
          @terraform_cli_config_path = T.let(nil, T.nilable(String))
          @dev_override_dir = T.let(nil, T.nilable(String))
        end

        sig { returns(T::Hash[String, String]) }
        def env
          sources = non_target_provider_sources
          return {} if sources.empty?

          config_path = generate_provider_dev_overrides_config(sources)
          { "TF_CLI_CONFIG_FILE" => config_path }
        end

        sig { void }
        def cleanup
          if @terraform_cli_config_path
            FileUtils.rm_f(@terraform_cli_config_path)
            @terraform_cli_config_path = nil
          end
          return unless @dev_override_dir

          FileUtils.rm_rf(@dev_override_dir)
          @dev_override_dir = nil
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :terraform_files

        sig { returns(T::Array[String]) }
        def non_target_provider_sources
          target = target_provider_source
          return [] unless target

          collect_provider_sources_from_files.reject { |s| s == target }
        end

        sig { returns(T.nilable(String)) }
        def target_provider_source
          req = dependency.requirements.first
          return unless req

          source = req[:source]
          return unless source && source[:type] == "provider"

          hostname = source[:registry_hostname] || DEFAULT_REGISTRY
          identifier = source[:module_identifier]
          return unless identifier

          "#{hostname}/#{identifier}".downcase
        end

        sig { returns(T::Array[String]) }
        def collect_provider_sources_from_files
          sources = T.let([], T::Array[String])
          terraform_files.each do |file|
            parsed = parse_hcl_file(file)
            parsed.fetch("terraform", []).each do |terraform_block|
              terraform_block.fetch("required_providers", {}).each do |providers|
                providers.each do |name, details|
                  next unless details.is_a?(Hash)

                  source_address = details.fetch("source", nil)
                  sources << normalize_provider_source(source_address, name)
                end
              end
            end
          end
          sources.uniq
        end

        sig { params(source_address: T.nilable(String), name: String).returns(String) }
        def normalize_provider_source(source_address, name)
          if source_address
            parts = source_address.split("/")
            if parts.length == 2
              "#{DEFAULT_REGISTRY}/#{source_address}".downcase
            else
              source_address.downcase
            end
          else
            "#{DEFAULT_REGISTRY}/#{DEFAULT_NAMESPACE}/#{name}".downcase
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Hash[String, T.untyped]) }
        def parse_hcl_file(file)
          return {} unless file.content

          SharedHelpers.in_a_temporary_directory do
            File.write("tmp.tf", file.content)
            command = "#{terraform_hcl2_parser_path} < tmp.tf"
            stdout, _stderr, process = Open3.capture3(command)
            return {} unless process.success?

            JSON.parse(stdout)
          end
        rescue StandardError
          {}
        end

        sig { params(provider_sources: T::Array[String]).returns(String) }
        def generate_provider_dev_overrides_config(provider_sources)
          dev_override_dir = File.join(Dir.tmpdir, "dependabot-tf-dev-#{SecureRandom.hex(4)}")
          FileUtils.mkdir_p(dev_override_dir)
          @dev_override_dir = dev_override_dir

          overrides = provider_sources.map do |source|
            "    \"#{source}\" = \"#{dev_override_dir}\""
          end.join("\n")

          config_content = <<~CONFIG
            provider_installation {
              dev_overrides {
            #{overrides}
              }
              direct {}
            }
          CONFIG

          config_path = File.join(Dir.tmpdir, "dependabot-terraform-#{SecureRandom.hex(4)}.rc")
          File.write(config_path, config_content)
          @terraform_cli_config_path = config_path

          config_path
        end

        sig { returns(String) }
        def terraform_hcl2_parser_path
          helper_bin_dir = File.join(native_helpers_root, "terraform/bin")
          Pathname.new(File.join(helper_bin_dir, "hcl2json")).cleanpath.to_path
        end

        sig { returns(String) }
        def native_helpers_root
          default_path = File.join(__dir__, "../../../../helpers/install-dir")
          ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
        end
      end
    end
  end
end
