# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/mise/file_fetcher"
require "dependabot/mise/helpers"

module Dependabot
  module Mise
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig
      include Dependabot::Mise::Helpers

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        mise_toml = dependency_files.find { |f| f.name == Dependabot::Mise::FileFetcher::MANIFEST_FILE }
        return updated_files unless mise_toml

        new_content = updated_mise_toml_content(mise_toml.content.to_s)
        updated_files << updated_file(file: mise_toml, content: new_content) if new_content != mise_toml.content

        updated_files
      end

      private

      sig { params(content: String).returns(String) }
      def updated_mise_toml_content(content)
        dependencies.each_with_object(content.dup) do |dep, updated_content|
          updated_content.replace(update_dependency(updated_content, dep))
        end
      end

      sig { params(content: String, dep: Dependabot::Dependency).returns(String) }
      def update_dependency(content, dep)
        tool = Regexp.escape(dep.name)
        old_version = Regexp.escape(requested_version_for(dep))
        new_version = new_version_string_for(dep)

        # Handles plain keys:   erlang = "27.3.2"
        # Handles quoted keys:  "npm:@redocly/cli" = "2.19.1"
        content = content.gsub(
          /^("#{tool}"|#{tool})\s*=\s*"#{old_version}"/,
          "\\1 = \"#{new_version}\""
        )

        # Handles inline table: python = { version = "3.11.0", virtualenv = ".venv" }
        content = content.gsub(
          /^("#{tool}"|#{tool})(\s*=\s*\{.*?version\s*=\s*)"#{old_version}"/,
          "\\1\\2\"#{new_version}\""
        )

        # Handles table header: [tools.golang]
        #                       version = "1.18"
        content.gsub(
          /(\[tools\.#{tool}\][^\[]*version\s*=\s*)"#{old_version}"/m,
          "\\1\"#{new_version}\""
        )
      end

      sig { params(dep: Dependabot::Dependency).returns(String) }
      def requested_version_for(dep)
        T.must(dep.previous_requirements)
         .filter_map { |r| r[:requirement] }
         .first || dep.previous_version.to_s
      end

      sig { params(dep: Dependabot::Dependency).returns(String) }
      def new_version_string_for(dep)
        dep.requirements
           .filter_map { |r| r[:requirement] }
           .first || dep.version.to_s
      end

      sig { override.void }
      def check_required_files
        return if get_original_file(Dependabot::Mise::FileFetcher::MANIFEST_FILE)

        raise "No #{Dependabot::Mise::FileFetcher::MANIFEST_FILE} file found!"
      end
    end
  end
end

Dependabot::FileUpdaters.register("mise", Dependabot::Mise::FileUpdater)
