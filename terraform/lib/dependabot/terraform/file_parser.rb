# typed: strict
# frozen_string_literal: true

require "cgi"
require "excon"
require "nokogiri"
require "open3"
require "digest"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/git_commit_checker"
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
        @ecosystem ||= T.let(begin
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          )
        end, T.nilable(Dependabot::Ecosystem))
      end

      private

      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).void }
      def parse_terraform_files(dependency_set)
        terraform_files.each do |file|
          modules = parsed_file(file).fetch("module", {})
          # If override.tf files are present, we need to merge the modules
          if override_terraform_files.any?
            override_terraform_files.each do |override_file|
              override_modules = parsed_file(override_file).fetch("module", {})
              modules = merge_modules(override_modules, modules)
            end
          end

          modules.each do |name, details|
            details = details.first

            source = source_from(details)
            # Cannot update local path modules, skip
            next if source && source[:type] == "path"

            dependency_set << build_terraform_dependency(file, name, T.must(source), details)
          end

          parsed_file(file).fetch("terraform", []).each do |terraform|
            required_providers = terraform.fetch("required_providers", {})
            required_providers.each do |provider|
              provider.each do |name, details|
                dependency_set << build_provider_dependency(file, name, details)
              end
            end
          end
        end
      end

      sig { params(dependency_set: Dependabot::FileParsers::Base::DependencySet).void }
      def parse_terragrunt_files(dependency_set)
        terragrunt_files.each do |file|
          modules = parsed_file(file).fetch("terraform", [])
          modules.each do |details|
            next unless details["source"]

            source = source_from(details)
            # Cannot update nil (interpolation sources) or local path modules, skip
            next if source.nil? || source[:type] == "path"

            dependency_set << build_terragrunt_dependency(file, source)
          end
        end
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          name: String,
          source: T::Hash[Symbol, T.untyped],
          details: T.untyped
        )
          .returns(Dependabot::Dependency)
      end
      def build_terraform_dependency(file, name, source, details)
        # dep_name should be unique for a source, using the info derived from
        # the source or the source name provides this uniqueness
        dep_name = case source[:type]
                   when "registry" then source[:module_identifier]
                   when "provider" then details["source"]
                   when "git" then git_dependency_name(name, source)
                   else name
                   end
        version_req = details["version"]&.strip
        version =
          if source[:type] == "git" then version_from_ref(source[:ref])
          elsif version_req&.match?(/^\d/) then version_req
          end

        Dependency.new(
          name: dep_name,
          version: version,
          package_manager: "terraform",
          requirements: [
            requirement: version_req,
            groups: [],
            file: file.name,
            source: source
          ]
        )
      end

      sig do
        params(
          file: Dependabot::DependencyFile,
          name: String,
          details: T.any(String, T::Hash[String, T.untyped])
        )
          .returns(Dependabot::Dependency)
      end
      def build_provider_dependency(file, name, details = {})
        deprecated_provider_error(file) if deprecated_provider?(details)

        source_address = T.cast(details, T::Hash[String, T.untyped]).fetch("source", nil)
        version_req = details["version"]&.strip
        hostname, namespace, name = provider_source_from(source_address, name)
        dependency_name = source_address ? "#{namespace}/#{name}" : name

        Dependency.new(
          name: T.must(dependency_name),
          version: determine_version_for(T.must(hostname), T.must(namespace), T.must(name), version_req),
          package_manager: "terraform",
          requirements: [
            requirement: version_req,
            groups: [],
            file: file.name,
            source: {
              type: "provider",
              registry_hostname: hostname,
              module_identifier: "#{namespace}/#{name}"
            }
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

      sig { params(details: Object).returns(T::Boolean) }
      def deprecated_provider?(details)
        # The old syntax for terraform providers v0.12- looked like
        # "tls ~> 2.1" which gets parsed as a string instead of a hash
        details.is_a?(String)
      end

      sig { params(file: Dependabot::DependencyFile, source: T::Hash[Symbol, String]).returns(Dependabot::Dependency) }
      def build_terragrunt_dependency(file, source)
        dep_name = Source.from_url(source[:url]) ? T.must(Source.from_url(source[:url])).repo : source[:url]
        version = version_from_ref(source[:ref])

        Dependency.new(
          name: T.must(dep_name),
          version: version,
          package_manager: "terraform",
          requirements: [
            requirement: nil,
            groups: [],
            file: file.name,
            source: source
          ]
        )
      end

      # Full docs at https://www.terraform.io/docs/modules/sources.html
      sig { params(details_hash: T::Hash[String, String]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def source_from(details_hash)
        raw_source = details_hash.fetch("source")
        bare_source = RegistryClient.get_proxied_source(raw_source)

        source_details =
          case source_type(bare_source)
          when :http_archive, :path, :mercurial, :s3
            { type: source_type(bare_source).to_s, url: bare_source }
          when :github, :bitbucket, :git
            git_source_details_from(bare_source)
          when :registry
            registry_source_details_from(bare_source)
          when :interpolation
            return nil
          end

        T.must(source_details)[:proxy_url] = raw_source if raw_source != bare_source
        source_details
      end

      sig { params(source_address: T.nilable(String), name: String).returns(T::Array[String]) }
      def provider_source_from(source_address, name)
        matches = source_address&.match(PROVIDER_SOURCE_ADDRESS)
        matches = {} if matches.nil?

        [
          matches[:hostname] || DEFAULT_REGISTRY,
          matches[:namespace] || DEFAULT_NAMESPACE,
          matches[:name] || name
        ]
      end

      sig { params(source_string: T.untyped).returns(T::Hash[Symbol, String]) }
      def registry_source_details_from(source_string)
        parts = source_string.split("//").first.split("/")

        if parts.count == 3
          {
            type: "registry",
            registry_hostname: "registry.terraform.io",
            module_identifier: source_string.split("//").first
          }
        elsif parts.count == 4
          {
            type: "registry",
            registry_hostname: parts.first,
            module_identifier: parts[1..3].join("/")
          }
        else
          msg = "Invalid registry source specified: '#{source_string}'"
          raise DependencyFileNotEvaluatable, msg
        end
      end

      sig { params(name: String, source: T::Hash[Symbol, T.untyped]).returns(String) }
      def git_dependency_name(name, source)
        git_source = Source.from_url(source[:url])
        if git_source && source[:ref]
          name + "::" + git_source.provider + "::" + git_source.repo + "::" + source[:ref]
        elsif git_source
          name + "::" + git_source.provider + "::" + git_source.repo
        elsif source[:ref]
          name + "::git_provider::repo_name/git_repo(" \
          + Digest::SHA1.hexdigest(source[:url]) + ")::" + source[:ref]
        else
          name + "::git_provider::repo_name/git_repo(" + Digest::SHA1.hexdigest(source[:url]) + ")"
        end
      end

      sig { params(source_string: String).returns(T::Hash[Symbol, T.nilable(String)]) }
      def git_source_details_from(source_string)
        git_url = source_string.strip.gsub(/^git::/, "")
        git_url = "https://" + git_url unless git_url.start_with?("git@") || git_url.include?("://")

        bare_uri =
          if git_url.include?("git@")
            T.must(git_url.split("git@").last).sub(":", "/")
          else
            git_url.sub(%r{(?:\w{3,5})?://}, "")
          end

        querystr = URI.parse("https://" + bare_uri).query
        git_url = git_url.gsub("?#{querystr}", "").split(%r{(?<!:)//}).first

        {
          type: "git",
          url: git_url,
          branch: nil,
          ref: CGI.parse(querystr.to_s)["ref"].first&.split(%r{(?<!:)//})&.first
        }
      end

      sig { params(ref: T.nilable(String)).returns(T.nilable(String)) }
      def version_from_ref(ref)
        version_regex = GitCommitChecker::VERSION_REGEX
        return unless ref&.match?(version_regex)

        ref.match(version_regex)&.named_captures&.fetch("version")
      end

      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/CyclomaticComplexity
      sig { params(source_string: String).returns(Symbol) }
      def source_type(source_string)
        return :interpolation if source_string.include?("${")
        return :path if source_string.start_with?(".")
        return :github if source_string.start_with?("github.com/")
        return :bitbucket if source_string.start_with?("bitbucket.org/")
        return :git if source_string.start_with?("git::", "git@")
        return :mercurial if source_string.start_with?("hg::")
        return :s3 if source_string.start_with?("s3::")

        raise "Unknown src: #{source_string}" if source_string.split("/").first&.include?("::")

        return :registry unless source_string.start_with?("http")

        path_uri = URI.parse(T.must(source_string.split(%r{(?<!:)//}).first))
        query_uri = URI.parse(source_string)
        return :http_archive if RegistryClient::ARCHIVE_EXTENSIONS.any? { |ext| path_uri.path&.end_with?(ext) }
        return :http_archive if query_uri.query&.include?("archive=")

        raise "HTTP source, but not an archive!"
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      # == Returns:
      # A Hash representing each module found in the specified file
      #
      # E.g.
      # {
      #   "module" => {
      #     {
      #       "consul" => [
      #         {
      #           "source"=>"consul/aws",
      #           "version"=>"0.1.0"
      #         }
      #       ]
      #     }
      #   },
      #   "terragrunt"=>[
      #     {
      #       "include"=>[{ "path"=>"${find_in_parent_folders()}" }],
      #       "terraform"=>[{ "source" => "git::git@github.com:gruntwork-io/modules-example.git//consul?ref=v0.0.2" }]
      #     }
      #   ],
      # }
      sig { params(file: Dependabot::DependencyFile).returns(T::Hash[String, T.untyped]) }
      def parsed_file(file)
        @parsed_buildfile ||= T.let({}, T.nilable(T::Hash[String, T.untyped]))
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

          JSON.parse(stdout)
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

        lockfile_content
          .dig("provider", "#{hostname}/#{namespace}/#{name}", 0, "version")
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def lockfile_content
        @lockfile_content ||= T.let(
          begin
            lockfile = dependency_files.find do |file|
              file.name == ".terraform.lock.hcl"
            end
            lockfile ? parsed_file(lockfile) : {}
          end,
          T.nilable(T::Hash[String, T.untyped])
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
