# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"
require "dependabot/terraform/file_selector"
require "dependabot/shared_helpers"
require "json"
require "open3"

module Dependabot
  module Terraform
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      include FileSelector

      PRIVATE_MODULE_ERROR = /Could not download module.*code from\n.*\"(?<repo>\S+)\":/
      MODULE_NOT_INSTALLED_ERROR =  /Module not installed.*module\s*\"(?<mod>\S+)\"/m
      GIT_HTTPS_PREFIX = %r{^git::https://}

      DEFAULT_REGISTRY = "registry.terraform.io"
      DEFAULT_NAMESPACE = "hashicorp"

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        [*terraform_files, *terragrunt_files].each do |file|
          next unless file_changed?(file)

          updated_content = updated_terraform_file_content(file)

          raise "Content didn't change!" if updated_content == file.content

          updated_file = updated_file(file: file, content: updated_content)

          updated_files << updated_file unless updated_files.include?(updated_file)
        end
        updated_lockfile_content = update_lockfile_declaration(updated_files)

        if updated_lockfile_content && T.must(lockfile).content != updated_lockfile_content
          updated_files << updated_file(file: T.must(lockfile), content: updated_lockfile_content)
        end

        updated_files.compact!

        raise "No files changed!" if updated_files.none?

        updated_files
      ensure
        cleanup_terraform_cli_config
      end

      private

      # Terraform allows to use a module from the same source multiple times
      # To detect any changes in dependencies we need to overwrite an implementation from the base class
      #
      # Example (for simplicity other parameters are skipped):
      # previous_requirements = [{requirement: "0.9.1"}, {requirement: "0.11.0"}]
      # requirements = [{requirement: "0.11.0"}, {requirement: "0.11.0"}]
      #
      # Simple difference between arrays gives:
      # requirements - previous_requirements
      #  => []
      # which loses an information that one of our requirements has changed.
      #
      # By using symmetric difference:
      # (requirements - previous_requirements) | (previous_requirements - requirements)
      #  => [{requirement: "0.9.1"}]
      # we can detect that change.
      sig { params(file: Dependabot::DependencyFile, dependency: Dependabot::Dependency).returns(T::Boolean) }
      def requirement_changed?(file, dependency)
        changed_requirements =
          (dependency.requirements - T.must(dependency.previous_requirements)) |
          (T.must(dependency.previous_requirements) - dependency.requirements)

        changed_requirements.any? { |f| f[:file] == file.name }
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_terraform_file_content(file)
        content = T.must(file.content.dup)

        reqs = dependency.requirements.zip(T.must(dependency.previous_requirements))
                         .reject { |new_req, old_req| new_req == old_req }

        # Loop through each changed requirement and update the files and lockfile
        reqs.each do |new_req, old_req|
          raise "Bad req match" unless new_req[:file] == old_req&.fetch(:file)
          next unless new_req.fetch(:file) == file.name

          case new_req[:source][:type]
          when "git"
            update_git_declaration(new_req, old_req, content, file.name)
          when "registry", "provider"
            update_registry_declaration(new_req, old_req, content)
          else
            raise "Don't know how to update a #{new_req[:source][:type]} " \
                  "declaration!"
          end
        end

        content
      end

      sig do
        params(
          new_req: T::Hash[Symbol, T.untyped],
          old_req: T.nilable(T::Hash[Symbol, T.untyped]),
          updated_content: String,
          filename: String
        )
          .void
      end
      def update_git_declaration(new_req, old_req, updated_content, filename)
        url = old_req&.dig(:source, :url)&.gsub(%r{^https://}, "")
        tag = old_req&.dig(:source, :ref)
        url_regex = /#{Regexp.quote(url)}.*ref=#{Regexp.quote(tag)}/

        declaration_regex = git_declaration_regex(filename)

        updated_content.sub!(declaration_regex) do |regex_match|
          regex_match.sub(url_regex) do |url_match|
            url_match.sub(old_req&.dig(:source, :ref), new_req[:source][:ref])
          end
        end
      end

      sig do
        params(
          new_req: T::Hash[Symbol, T.untyped],
          old_req: T.nilable(T::Hash[Symbol, T.untyped]),
          updated_content: String
        )
          .void
      end
      def update_registry_declaration(new_req, old_req, updated_content)
        regex = if new_req[:source][:type] == "provider"
                  provider_declaration_regex(updated_content)
                else
                  registry_declaration_regex
                end

        # Define and break down the version regex for better clarity
        version_key_pattern = /^\s*version\s*=\s*/
        version_value_pattern = /["'].*#{Regexp.escape(old_req&.fetch(:requirement))}.*['"]/
        version_regex = /#{version_key_pattern}#{version_value_pattern}/

        updated_content.gsub!(regex) do |regex_match|
          regex_match.sub(version_regex) do |req_line_match|
            req_line_match.sub!(old_req&.fetch(:requirement), new_req[:requirement])
          end
        end
      end

      sig { params(content: String, declaration_regex: Regexp).returns(T::Array[String]) }
      def extract_provider_h1_hashes(content, declaration_regex)
        content.match(declaration_regex).to_s
               .match(hashes_object_regex).to_s
               .split("\n").map { |hash| hash.match(hashes_string_regex).to_s }
                           .select { |h| h.match?(/^h1:/) }
      end

      sig { params(content: String, declaration_regex: Regexp).returns(String) }
      def remove_provider_h1_hashes(content, declaration_regex)
        content.match(declaration_regex).to_s
               .sub(hashes_object_regex, "")
      end

      sig do
        params(
          new_req: T::Hash[Symbol, T.untyped]
        )
          .returns([String, String, Regexp])
      end
      def lockfile_details(new_req)
        content = T.must(lockfile).content.dup
        provider_source = new_req[:source][:registry_hostname] + "/" + new_req[:source][:module_identifier]
        declaration_regex = lockfile_declaration_regex(provider_source)

        [T.must(content), provider_source, declaration_regex]
      end

      sig { returns(T.nilable(T::Array[Symbol])) }
      def lookup_hash_architecture # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/PerceivedComplexity
        new_req = T.must(dependency.requirements.first)

        # NOTE: Only providers are included in the lockfile, modules are not
        return unless new_req[:source][:type] == "provider"

        architectures = []
        content, provider_source, declaration_regex = lockfile_details(new_req)
        hashes = extract_provider_h1_hashes(content, declaration_regex)

        # These are ordered in assumed popularity
        possible_architectures = %w(
          linux_amd64
          darwin_amd64
          windows_amd64
          darwin_arm64
          linux_arm64
        )

        base_dir = T.must(dependency_files.first).directory
        lockfile_hash_removed = remove_provider_h1_hashes(content, declaration_regex)

        # This runs in the same directory as the actual lockfile update so
        # the platform must be determined before the updated manifest files
        # are written to disk
        SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
          possible_architectures.each do |arch|
            # Exit early if we have detected all of the architectures present
            break if architectures.count == hashes.count

            # Terraform will update the lockfile in place so we use a fresh lockfile for each lookup
            File.write(".terraform.lock.hcl", lockfile_hash_removed)

            SharedHelpers.run_shell_command(
              "terraform providers lock -platform=#{arch} #{provider_source} -no-color",
              fingerprint: "terraform providers lock -platform=<arch> <provider_source> -no-color",
              env: terraform_env
            )

            updated_lockfile = File.read(".terraform.lock.hcl")
            updated_hashes = extract_provider_h1_hashes(updated_lockfile, declaration_regex)
            next if updated_hashes.nil?

            # Check if the architecture is present in the original lockfile
            hashes.each do |hash|
              updated_hashes.select { |h| h.match?(/^h1:/) }.each do |updated_hash|
                architectures.append(arch.to_sym) if hash == updated_hash
              end
            end

            File.delete(".terraform.lock.hcl")
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          if @retrying_lock && e.message.match?(MODULE_NOT_INSTALLED_ERROR)
            mod = T.must(e.message.match(MODULE_NOT_INSTALLED_ERROR)).named_captures.fetch("mod")
            raise Dependabot::DependencyFileNotResolvable, "Attempt to install module #{mod} failed"
          end
          raise if @retrying_lock || !e.message.include?("terraform init")

          # NOTE: Modules need to be installed before terraform can update the lockfile
          @retrying_lock = true
          run_terraform_init
          retry
        end

        architectures.to_a
      end

      sig { returns(T::Array[Symbol]) }
      def architecture_type
        @architecture_type ||= T.let(
          if lookup_hash_architecture.nil? || lookup_hash_architecture&.empty?
            [:linux_amd64]
          else
            T.must(lookup_hash_architecture)
          end,
          T.nilable(T::Array[Symbol])
        )
      end

      sig { params(updated_manifest_files: T::Array[Dependabot::DependencyFile]).returns(T.nilable(String)) }
      def update_lockfile_declaration(updated_manifest_files) # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
        return if lockfile.nil?

        new_req = T.must(dependency.requirements.first)
        # NOTE: Only providers are included in the lockfile, modules are not
        return unless new_req[:source][:type] == "provider"

        content, provider_source, declaration_regex = lockfile_details(new_req)
        lockfile_dependency_removed = content.sub(declaration_regex, "")

        base_dir = T.must(dependency_files.first).directory
        SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
          # Determine the provider using the original manifest files
          platforms = architecture_type.map { |arch| "-platform=#{arch}" }.join(" ")

          # Update the provider requirements in case the previous requirement doesn't allow the new version
          updated_manifest_files.each { |f| File.write(f.name, f.content) }

          File.write(".terraform.lock.hcl", lockfile_dependency_removed)

          SharedHelpers.run_shell_command(
            "terraform providers lock #{platforms} #{provider_source}",
            fingerprint: "terraform providers lock <platforms> <provider_source>",
            env: terraform_env
          )

          updated_lockfile = File.read(".terraform.lock.hcl")
          updated_dependency = T.cast(updated_lockfile.scan(declaration_regex).first, String)

          # Terraform will occasionally update h1 hashes without updating the version of the dependency
          # Here we make sure the dependency's version actually changes in the lockfile
          unless T.cast(updated_dependency.scan(declaration_regex).first, String).scan(/^\s*version\s*=.*/) ==
                 T.cast(content.scan(declaration_regex).first, String).scan(/^\s*version\s*=.*/)
            content.sub!(declaration_regex, updated_dependency)
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          error_handler = FileUpdaterErrorHandler.new
          error_handler.handle_helper_subprocess_failed_error(e)

          if @retrying_lock && e.message.match?(MODULE_NOT_INSTALLED_ERROR)
            mod = T.must(e.message.match(MODULE_NOT_INSTALLED_ERROR)).named_captures.fetch("mod")
            raise Dependabot::DependencyFileNotResolvable, "Attempt to install module #{mod} failed"
          end
          raise if @retrying_lock || !e.message.include?("terraform init")

          # NOTE: Modules need to be installed before terraform can update the lockfile
          @retrying_lock = T.let(true, T.nilable(T::Boolean))
          run_terraform_init
          retry
        end

        content
      end

      sig { void }
      def run_terraform_init
        SharedHelpers.with_git_configured(credentials: credentials) do
          # -backend=false option used to ignore any backend configuration, as these won't be accessible
          # -input=false option used to immediately fail if it needs user input
          # -no-color option used to prevent any color characters being printed in the output
          SharedHelpers.run_shell_command(
            "terraform init -backend=false -input=false -no-color",
            env: terraform_env
          )
        rescue SharedHelpers::HelperSubprocessFailed => e
          output = e.message

          if output.match?(PRIVATE_MODULE_ERROR)
            repo = T.must(output.match(PRIVATE_MODULE_ERROR)).named_captures.fetch("repo")
            if repo&.match?(GIT_HTTPS_PREFIX)
              repo = repo.sub(GIT_HTTPS_PREFIX, "")
              repo = repo.sub(/\.git$/, "")
            end
            raise PrivateSourceAuthenticationFailure, repo
          end

          raise Dependabot::DependencyFileNotResolvable, "Error running `terraform init`: #{output}"
        end
      end

      sig { returns(Dependabot::Dependency) }
      def dependency
        # Terraform updates will only ever be updating a single dependency
        T.must(dependencies.first)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def files_with_requirement
        filenames = dependency.requirements.map { |r| r[:file] }
        dependency_files.select { |file| filenames.include?(file.name) }
      end

      sig { override.void }
      def check_required_files
        return if [*terraform_files, *terragrunt_files].any?

        raise "No Terraform configuration file!"
      end

      sig { returns(Regexp) }
      def hashes_object_regex
        /hashes\s*=\s*[^\]]*\]/m
      end

      sig { returns(Regexp) }
      def hashes_string_regex
        /(?<=\").*(?=\")/
      end

      sig { params(updated_content: String).returns(Regexp) }
      def provider_declaration_regex(updated_content)
        name = Regexp.escape(dependency.name)
        registry_host = Regexp.escape(registry_host_for(dependency))
        regex_version_preceeds = %r{
          (((?<!required_)version\s=\s*["'].*["'])
          (\s*source\s*=\s*["'](#{registry_host}/)?#{name}["']|\s*#{name}\s*=\s*\{.*))
        }mxi
        regex_source_preceeds = %r{
          ((source\s*=\s*["'](#{registry_host}/)?#{name}["']|\s*#{name}\s*=\s*\{.*)
          (?:(?!^\}).)+)
        }mxi

        if updated_content.match(regex_version_preceeds)
          regex_version_preceeds
        else
          regex_source_preceeds
        end
      end

      sig { returns(Regexp) }
      def registry_declaration_regex
        %r{
          (?<=\{)
          (?:(?!^\}).)*
          source\s*=\s*["']
            (#{Regexp.escape(registry_host_for(dependency))}/)?
            #{Regexp.escape(dependency.name)}
            (//modules/\S+)?
            ["']
          (?:(?!^\}).)*
        }mxi
      end

      sig { params(filename: String).returns(Regexp) }
      def git_declaration_regex(filename)
        # For terragrunt dependencies there's not a lot we can base the
        # regex on. Just look for declarations within a `terraform` block
        return /terraform\s*\{(?:(?!^\}).)*/m if terragrunt_file?(filename)

        # For modules we can do better - filter for module blocks that use the
        # name of the module
        module_name = T.must(dependency.name.split("::").first)
        /
         module\s+["']#{Regexp.escape(module_name)}["']\s*\{
         (?:(?!^\}).)*
        /mx
      end

      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def registry_host_for(dependency)
        source = dependency.requirements.filter_map { |r| r[:source] }.first
        source[:registry_hostname] || source["registry_hostname"] || "registry.terraform.io"
      end

      sig { params(provider_source: String).returns(Regexp) }
      def lockfile_declaration_regex(provider_source)
        /
          (?:(?!^\}).)*
          provider\s*["']#{Regexp.escape(provider_source)}["']\s*\{
          (?:(?!^\}).)*}
        /mix
      end

      # Returns env hash with TF_CLI_CONFIG_FILE set to a generated config
      # that uses dev_overrides for non-target providers. This prevents
      # Terraform from trying to resolve private/custom providers from the
      # public registry when they are not the update target.
      sig { returns(T::Hash[String, String]) }
      def terraform_env
        @terraform_env ||= T.let(build_terraform_env, T.nilable(T::Hash[String, String]))
      end

      sig { returns(T::Hash[String, String]) }
      def build_terraform_env
        sources = non_target_provider_sources
        return {} if sources.empty?

        config_path = generate_provider_dev_overrides_config(sources)
        { "TF_CLI_CONFIG_FILE" => config_path }
      end

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
        @dev_override_dir = T.let(dev_override_dir, T.nilable(String))

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
        @terraform_cli_config_path = T.let(config_path, T.nilable(String))

        config_path
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

      sig { void }
      def cleanup_terraform_cli_config
        @terraform_cli_config_path = T.let(@terraform_cli_config_path, T.nilable(String))
        @dev_override_dir = T.let(@dev_override_dir, T.nilable(String))

        if @terraform_cli_config_path
          FileUtils.rm_f(@terraform_cli_config_path)
          @terraform_cli_config_path = nil
        end
        return unless @dev_override_dir

        FileUtils.rm_rf(@dev_override_dir)
        @dev_override_dir = nil
      end
    end

    class FileUpdaterErrorHandler
      extend T::Sig

      RESOLVE_ERROR = /Could not retrieve providers for locking/
      CONSTRAINTS_ERROR = /no available releases match/

      # Handles errors with specific to yarn error codes
      sig { params(error: SharedHelpers::HelperSubprocessFailed).void }
      def handle_helper_subprocess_failed_error(error)
        unless sanitize_message(error.message).match?(RESOLVE_ERROR) &&
               sanitize_message(error.message).match?(CONSTRAINTS_ERROR)
          return
        end

        raise Dependabot::DependencyFileNotResolvable,
              "Error while updating lockfile, " \
              "no matching constraints found."
      end

      sig { params(message: String).returns(String) }
      def sanitize_message(message)
        message.gsub(/\e\[[\d;]*[A-Za-z]/, "").delete("\n").delete("│").squeeze(" ")
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("terraform", Dependabot::Terraform::FileUpdater)
