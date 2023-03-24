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

    attr_reader :base_commit_sha, :dependency_files

    def initialize(job:, base_commit_sha:, dependency_files:)
      @job = job
      @base_commit_sha = base_commit_sha
      @dependency_files = dependency_files
    end

    def dependencies
      return @dependencies if defined?(@dependencies)

      parse_files!
    end

    private

    attr_reader :job

    # TODO: Parse files during instantiation?
    #
    # To avoid having to re-home Dependabot::Updater#handle_parser_error,
    # we perform the parsing lazily when the `dependencies` method is first
    # referenced.
    #
    # We have some unusual behaviour where we handle a parse error by
    # returning an empty dependency array in Dependabot::Updater#dependencies
    # in order to 'fall through' to an error outcome elsewhere in the class.
    #
    # Given this uncertainity, and the need to significantly refactor tests,
    # it makes sense to introduce this shim and then deal with the call
    # site once we've split out the downstream behaviour in the updater.
    #
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
