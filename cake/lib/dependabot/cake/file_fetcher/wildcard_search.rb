# frozen_string_literal: true

require "pathname"

module Dependabot
  module Cake
    class FileFetcher
      class WildcardSearch
        def initialize(enumerate_files_fn:)
          @enumerate_files_fn = enumerate_files_fn
        end

        def perform_search(base_path, search_path)
          search_path += "**/*" if WildcardSearch.directory_path?(search_path)

          # basePath, search_path = normalize_base_path(basePath, search_path);
          normalized_base_path =
            get_path_to_enumerate_from(base_path, search_path)

          # Append the basePath to searchPattern and get the search regex.
          # We need to do this because the search regex is matched from
          # line start.
          search_regex = wildcard_to_regex(
            Pathname.new("#{base_path}/#{search_path}").
                cleanpath.to_path.gsub(%r{^/+}, "")
          )

          recursive_search = search_path.index("**") != -1
          _perform_search(normalized_base_path,
                          search_regex,
                          recursive_search)
        end

        def self.wildcard_search?(pattern)
          !pattern.index(/[*?]/).nil?
        end

        def self.directory_path?(path)
          !path.nil? && path.length > 1 && path[path.length - 1] == "/"
        end

        private

        attr_reader :enumerate_files_fn

        def _perform_search(path,
                            search_regex,
                            recursive_search)
          matched_files = []
          files = @enumerate_files_fn.call(path)

          files.each do |file|
            if file.type == "file"
              matched_files << file.path if search_regex.match?(file.path)
              next
            end
            next unless recursive_search

            matched_files << _perform_search("#{path}/#{file.name}",
                                             search_regex,
                                             recursive_search)
          end
          matched_files.flatten
        end

        # rubocop:disable Layout/LineLength
        def wildcard_to_regex(wildcard)
          # regex wildcard adjustments for *nix-style file systems
          pattern = Regexp.escape(wildcard).
                    sub("\\.\\*\\*", "\.[^/.]*"). # .** should not match on ../file or ./file but will match .file
                    sub("\\*\\*/", "(.+/)*"). # For recursive wildcards /**/, include the current directory.
                    sub("\\*\\*", ".*"). # For recursive wildcards that don't end in a slash e.g. **.txt would be treated as a .txt file at any depth
                    sub("\\*", "[^/]*(/)?"). # For non recursive searches, limit it any character that is not a directory separator
                    sub("\\?", ".") # ? translates to a single any character
          Regexp.new("^#{pattern}$", Regexp::IGNORECASE)
        end

        def get_path_to_enumerate_from(base_path, search_path)
          wildcard_index = search_path.index("*")
          if wildcard_index == -1
            return Pathname.new("#{base_path}/#{File.dirname(search_path)}").cleanpath.to_path
          end

          # If not, find the first directory separator and use the path to the left of it as the base path to enumerate from.
          separator_index = search_path.rindex("/", wildcard_index)
          if separator_index == -1
            # We're looking at a path like "NuGet*.dll", NuGet*\bin\release\*.dll
            # In this case, the basePath would continue to be the path to begin enumeration from.
            return base_path
          end

          non_wildcard_portion = search_path[0, separator_index]
          Pathname.new("#{base_path}/#{non_wildcard_portion}").cleanpath.to_path
        end
        # rubocop:enable Layout/LineLength
      end
    end
  end
end
