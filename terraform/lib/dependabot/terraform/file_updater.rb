# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"
require "dependabot/terraform/file_selector"
require "dependabot/shared_helpers"

module Dependabot
  module Terraform
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      include FileSelector

      PRIVATE_MODULE_ERROR = /Could not download module.*code from\n.*\"(?<repo>\S+)\":/
      MODULE_NOT_INSTALLED_ERROR =  /Module not installed.*module\s*\"(?<mod>\S+)\"/m
      GIT_HTTPS_PREFIX = %r{^git::https://}

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/\.tf$/, /\.hcl$/]
      end

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
        updated_content.gsub!(regex) do |regex_match|
          regex_match.sub(/^\s*version\s*=.*/) do |req_line_match|
            req_line_match.sub(old_req&.fetch(:requirement), new_req[:requirement])
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
              fingerprint: "terraform providers lock -platform=<arch> <provider_source> -no-color"
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
            fingerprint: "terraform providers lock <platforms> <provider_source>"
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
          SharedHelpers.run_shell_command("terraform init -backend=false -input=false -no-color")
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
        }mx
        regex_source_preceeds = %r{
          ((source\s*=\s*["'](#{registry_host}/)?#{name}["']|\s*#{name}\s*=\s*\{.*)
          (?:(?!^\}).)+)
        }mx

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
        }mx
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

        raise Dependabot::DependencyFileNotResolvable, "Error while updating lockfile, " \
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
