# frozen_string_literal: true

require "base64"
require "dependabot/file_parsers"

# This class describes the dependencies obtained from a project at a specific commit SHA
# including both the Dependabot::DependencyFile objects at that reference as well as
# means to parse them into a set of Dependabot::Dependency objects.
#
# This class is the input for a Dependabot::Updater process with Dependabot::DependencyChange
# representing the output.
module Dependabot
  class DependencySnapshot
    def self.create_from_job_definition(job:, job_definition:)
      decoded_dependency_files = job_definition.fetch("base64_dependency_files").map do |a|
        file = Dependabot::DependencyFile.new(**a.transform_keys(&:to_sym))
        file.content = Base64.decode64(file.content).force_encoding("utf-8") unless file.binary? && !file.deleted?
        file
      end

      new(
        job: job,
        base_commit_sha: job_definition.fetch("base_commit_sha"),
        dependency_files: decoded_dependency_files
      )
    end

    attr_reader :base_commit_sha, :dependency_files, :dependencies

    private

    def initialize(job:, base_commit_sha:, dependency_files:)
      @job = job
      @base_commit_sha = base_commit_sha
      @dependency_files = dependency_files

      parse_files!
    end

    attr_reader :job

    def parse_files!
      @dependencies = dependency_file_parser.parse
    end

    def dependency_file_parser
      Dependabot::FileParsers.for_package_manager(job.package_manager).new(
        dependency_files: dependency_files,
        repo_contents_path: job.repo_contents_path,
        source: job.source,
        credentials: job.credentials,
        reject_external_code: job.reject_external_code?,
        options: job.experiments
      )
    end
  end
end
