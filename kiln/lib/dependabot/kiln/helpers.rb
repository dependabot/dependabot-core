module Dependabot
  module Kiln
    module Helpers
      def self.dir_with_dependencies(dependency_files)
        Dir.mktmpdir do |tempdir|
          dependency_files.each do |dependency_file|
            File.write(File.join(tempdir, dependency_file.name), dependency_file.content)
          end
          kilnfile_path = File.join(tempdir, 'Kilnfile')
          lockfile_path = File.join(tempdir, 'Kilnfile.lock')
          yield kilnfile_path, lockfile_path
        end
      end
    end
  end
end
