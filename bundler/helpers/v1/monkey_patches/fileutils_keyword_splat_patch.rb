# frozen_string_literal: true

require "bundler/vendor/fileutils/lib/fileutils"

# Port
# https://github.com/ruby/fileutils/commit/a5eca84a4240e29bb7886c3ef7085d464a972dd0
# to fix keyword argument errors on Ruby 3.1

module BundlerFileUtilsKeywordSplatPatch
  def entries
    opts = {}
    opts[:encoding] = ::Encoding::UTF_8 if fu_windows?
    Dir.entries(path, **opts).
      reject { |n| n == "." || n == ".." }.
      map { |n| self.class.new(prefix, join(rel, n.untaint)) }
  end
end

Bundler::FileUtils::Entry_.prepend(BundlerFileUtilsKeywordSplatPatch)
