# frozen_string_literal: true

require "cgi"
require "excon"
require "nokogiri"
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Terraform
      class Terraform < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        ARCHIVE_EXTENSIONS = %w(.zip .tbz2 .tgz .txz).freeze

        def parse
          dependency_set = DependencySet.new

          terraform_files.each do |file|
            modules = parsed_file(file).fetch("module", []).map(&:first)
            modules.each do |name, details|
              details = details.first

              source = source_from(details)
              dep_name =
                source[:type] == "registry" ? source[:module_identifier] : name
              version_req = details["version"]&.strip

              dependency_set << Dependency.new(
                name: dep_name,
                version: version_req&.match?(/^\d/) ? version_req : nil,
                package_manager: "terraform",
                requirements: [
                  requirement: version_req,
                  groups: [],
                  file: file.name,
                  source: source
                ]
              )
            end
          end

          dependency_set.dependencies
        end

        private

        # Full docs at https://www.terraform.io/docs/modules/sources.html
        def source_from(details_hash)
          raw_source = details_hash.fetch("source")
          bare_source = get_proxied_source(raw_source)

          source_details =
            case source_type(bare_source)
            when :http_archive, :path, :mercurial, :s3
              { type: source_type(bare_source).to_s, url: bare_source }
            when :github, :bitbucket, :git
              git_source_details_from(bare_source)
            when :registry
              registry_source_details_from(bare_source)
            end

          source_details[:proxy_url] = raw_source if raw_source != bare_source
          source_details
        end

        def registry_source_details_from(source_string)
          parts = source_string.split("/")

          if parts.count == 3
            {
              type: "registry",
              registry_hostname: "registry.terraform.io",
              module_identifier: source_string
            }
          elsif parts.count == 4
            {
              type: "registry",
              registry_hostname: parts.first,
              module_identifier: parts[1..3].join("/")
            }
          else
            raise "Unexpected registry format: #{source_string}"
          end
        end

        def git_source_details_from(source_string)
          git_url = source_string.strip.gsub(/^git::/, "")
          git_url = "https://" + git_url unless git_url.start_with?("http")

          querystr = URI.parse(git_url).query
          git_url = git_url.split(%r{(?<!:)//}).first.gsub("?#{querystr}", "")

          {
            type: "git",
            url: git_url,
            branch: nil,
            ref: CGI.parse(querystr.to_s)["ref"].first
          }
        end

        # See https://www.terraform.io/docs/modules/sources.html#http-urls for
        # details of how Terraform handle HTTP(S) sources for modules
        def get_proxied_source(raw_source)
          return raw_source unless raw_source.start_with?("http")

          uri = URI.parse(raw_source.split(%r{(?<!:)//}).first)
          return raw_source if uri.path.end_with?(*ARCHIVE_EXTENSIONS)
          return raw_source if URI.parse(raw_source).query.include?("archive=")

          url = raw_source.split(%r{(?<!:)//}).first + "?terraform-get=1"

          response = Excon.get(
            url,
            idempotent: true,
            **SharedHelpers.excon_defaults
          )

          if response.headers["X-Terraform-Get"]
            return response.headers["X-Terraform-Get"]
          end

          doc = Nokogiri::XML(response.body)
          doc.css("meta").find do |tag|
            tag.attributes&.fetch("name", nil)&.value == "terraform-get"
          end&.attributes&.fetch("content", nil)&.value
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def source_type(source_string)
          return :path if source_string.start_with?(".")
          return :github if source_string.start_with?("github.com/")
          return :bitbucket if source_string.start_with?("bitbucket.org/")
          return :git if source_string.start_with?("git::")
          return :mercurial if source_string.start_with?("hg::")
          return :s3 if source_string.start_with?("s3::")

          if source_string.split("/").first.include?("::")
            raise "Unknown src: #{source_string}"
          end

          return :registry unless source_string.start_with?("http")

          path_uri = URI.parse(source_string.split(%r{(?<!:)//}).first)
          query_uri = URI.parse(source_string)
          return :http_archive if path_uri.path.end_with?(*ARCHIVE_EXTENSIONS)
          return :http_archive if query_uri.query.include?("archive=")

          raise "HTTP source, but not an archive!"
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        def parsed_file(file)
          @parsed_buildfile ||= {}
          @parsed_buildfile[file.name] ||=
            SharedHelpers.in_a_temporary_directory do
              File.write("tmp.tf", file.content)

              command = "#{terraform_parser_path} -reverse < tmp.tf"
              raw_response = nil
              IO.popen(command) { |process| raw_response = process.read }

              unless $CHILD_STATUS.success?
                raise SharedHelpers::HelperSubprocessFailed.new(
                  raw_response,
                  command
                )
              end

              JSON.parse(raw_response)
            end
        end

        def terraform_parser_path
          Pathname.new(
            "#{terraform_helper_path}/json2hcl.#{platform}"
          ).cleanpath.to_path
        end

        def platform
          case RbConfig::CONFIG["arch"]
          when /linux/ then "linux"
          when /darwin/ then "darwin"
          else raise "Invalid platform #{RbConfig::CONFIG['arch']}"
          end
        end

        def terraform_helper_path
          File.join(project_root, "helpers/terraform")
        end

        def project_root
          File.join(File.dirname(__FILE__), "../../../..")
        end

        def terraform_files
          dependency_files.select { |f| f.name.end_with?(".tf") }
        end

        def check_required_files
          return if terraform_files.any?
          raise "No Terraform configuration file!"
        end
      end
    end
  end
end
