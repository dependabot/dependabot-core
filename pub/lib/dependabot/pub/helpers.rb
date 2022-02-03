# frozen_string_literal: true

require "json"
require "open3"
require "digest"

require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/pub/requirement"

module Dependabot
  module Pub
    module Helpers
      private

      def dependency_services_list
        JSON.parse(run_dependency_services("list"))["dependencies"]
      end

      def dependency_services_report
        sha256 = Digest::SHA256.new
        dependency_files.each do |f|
          sha256 << f.path + "\n" + f.content + "\n"
        end
        hash = sha256.hexdigest

        cache_file = "/tmp/report-#{hash}-pid-#{Process.pid}.json"
        return JSON.parse(File.read(cache_file)) if File.file?(cache_file)

        report = JSON.parse(run_dependency_services("report"))["dependencies"]
        File.write(cache_file, JSON.generate(report))
        report
      end

      def dependency_services_apply(dependency_changes)
        run_dependency_services("apply", stdin_data: dependencies_to_json(dependency_changes)) do
          dependency_files.map do |f|
            updated_file = f.dup
            updated_file.content = File.read(f.name)
            updated_file
          end
        end
      end

      def run_dependency_services(command, stdin_data: nil)
        SharedHelpers.in_a_temporary_directory do
          dependency_files.each do |f|
            in_path_name = File.join(Dir.pwd, f.directory, f.name)
            FileUtils.mkdir_p File.dirname(in_path_name)
            File.write(in_path_name, f.content)
          end
          SharedHelpers.with_git_configured(credentials: credentials) do
            env = {
              "CI" => "true",
              "PUB_ENVIRONMENT" => "dependabot",
              "FLUTTER_ROOT" => "/opt/dart/flutter",
              "PUB_HOSTED_URL" => options[:pub_hosted_url]
            }
            Dir.chdir File.join(Dir.pwd, dependency_files.first.directory) do
              stdout, stderr, status = Open3.capture3(
                env.compact,
                "dart",
                "pub",
                "global",
                "run",
                "pub:dependency_services",
                command,
                stdin_data: stdin_data
              )
              raise Dependabot::DependabotError, "dart pub failed: #{stderr}" unless status.success?
              return stdout unless block_given?

              yield
            end
          end
        end
      end

      def to_dependency(json)
        params = {
          name: json["name"],
          version: json["version"],
          package_manager: "pub",
          requirements: []
        }
        if json["kind"] != "transitive" && !json["constraint"].nil?
          constraint = json["constraint"]
          params[:requirements] << {
            requirement: constraint,
            groups: [json["kind"]],
            source: nil, # TODO: Expose some information about the source
            file: "pubspec.yaml"
          }
        end
        if json["previousVersion"]
          params = {
            **params,
            previous_version: json["previousVersion"],
            previous_requirements: []
          }
          if json["kind"] != "transitive" && !json["previousConstraint"].nil?
            constraint = json["previousConstraint"]
            params[:previous_requirements] << {
              requirement: constraint,
              groups: [json["kind"]],
              source: nil, # TODO: Expose some information about the source
              file: "pubspec.yaml"
            }
          end
        end
        Dependency.new(**params)
      end

      def dependencies_to_json(dependencies)
        if dependencies.nil?
          nil
        else
          deps = dependencies.map do |d|
            obj = {
              "name" => d.name,
              "version" => d.version
            }

            obj["constraint"] = d.requirements[0][:requirement].to_s unless d.requirements.nil? || d.requirements.empty?
            obj
          end
          JSON.generate({
            "dependencyChanges" => deps
          })
        end
      end
    end
  end
end
