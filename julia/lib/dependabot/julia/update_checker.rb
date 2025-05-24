require "dependabot/update_checkers/base"
require "dependabot/shared_helpers"
require "toml-rb"

module Dependabot
  module Julia
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      def latest_resolvable_version(*)
        in_tmp do |dir|
          pkg_update(dir, dependency.name)
          read_version(dir, dependency.name)
        end
      end

      def updated_dependencies_after_full_update
        in_tmp do |dir|
          pkg_update(dir)
          manifest_diff(dir)
        end
      end

      private

      def in_tmp
        SharedHelpers.in_a_temporary_directory do |dir|
          dependency_files.each { |f| File.write(File.join(dir, f.name), f.content) }
          yield dir
        end
      end

      def pkg_update(dir, dep = nil)
        script = dep ? %(Pkg.update("#{dep}"; io=devnull)) :
                      %(Pkg.update(; io=devnull))
        SharedHelpers.run_shell_command %(julia --project="#{dir}" -e 'using Pkg; #{script}')
      end

      def read_version(dir, name)
        mf = TomlRB.parse(File.read("#{dir}/Manifest.toml"))
        stanza = mf[name]&.find { |s| s["version"] }
        stanza && Version.new(stanza["version"])
      end

      def manifest_diff(dir)
        old = manifest_file ? TomlRB.parse(manifest_file.content) : {}
        new = TomlRB.parse(File.read("#{dir}/Manifest.toml"))
        (new.keys | old.keys).filter_map do |pkg|
          nv = new[pkg]&.find { |s| s["version"] }&.dig("version")
          ov = old[pkg]&.find { |s| s["version"] }&.dig("version")
          next if nv == ov || nv.nil?
          Dependency.new(
            name: pkg,
            package_manager: "julia",
            version: nv,
            previous_version: ov,
            requirements: []
          )
        end
      end

      def manifest_file
        dependency_files.find { |f| f.name.match?(FileFetcher::MF_RE) }
      end
    end
  end
end

Dependabot::UpdateCheckers.register("julia", Dependabot::Julia::UpdateChecker)
