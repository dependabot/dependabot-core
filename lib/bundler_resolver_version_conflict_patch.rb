# frozen_string_literal: true

require "bundler/resolver"

# rubocop:disable all
module Bundler
  class Resolver
    private

    def version_conflict_message(e)
      e.message_with_trees(
        :solver_name => "Bundler",
        :possibility_type => "gem",
        :reduce_trees => lambda do |trees|
          # bail out if tree size is too big for Array#combination to make any sense
          return trees if trees.size > 15
          maximal = 1.upto(trees.size).map do |size|
            trees.map(&:last).flatten(1).combination(size).to_a
          end.flatten(1).select do |deps|
            Bundler::VersionRanges.empty?(*Bundler::VersionRanges.for_many(deps.map(&:requirement)))
          end.min_by(&:size)
          trees = trees.reject {|t| !maximal.include?(t.last) } if maximal

          trees = trees.sort_by {|t| t.flatten.map(&:to_s) }
          trees.uniq! {|t| t.flatten.map {|dep| [dep.name, dep.requirement] } }

          trees.sort_by {|t| t.reverse.map(&:name) }
        end,
        :printable_requirement => lambda {|req| SharedHelpers.pretty_dependency(req) },
        :additional_message_for_conflict => lambda do |o, name, conflict|
          if name == "bundler"
            o << %(\n  Current Bundler version:\n    bundler (#{Bundler::VERSION}))
            other_bundler_required = !conflict.requirement.requirement.satisfied_by?(Gem::Version.new(Bundler::VERSION))
          end

          if name == "bundler" && other_bundler_required
            o << "\n"
            o << "This Gemfile requires a different version of Bundler.\n"
            o << "Perhaps you need to update Bundler by running `gem install bundler`?\n"
          end
          if conflict.locked_requirement
            o << "\n"
            o << %(Running `bundle update` will rebuild your snapshot from scratch, using only\n)
            o << %(the gems in your Gemfile, which may resolve the conflict.\n)
          elsif !conflict.existing
            o << "\n"

            relevant_sources = if conflict.requirement.source
              [conflict.requirement.source]
            elsif conflict.requirement.all_sources
              conflict.requirement.all_sources
            elsif @lockfile_uses_separate_rubygems_sources
              # every conflict should have an explicit group of sources when we
              # enforce strict pinning
              raise "no source set for #{conflict}"
            else
              []
            end.compact.map(&:to_s).uniq.sort

            o << "Could not find gem '#{SharedHelpers.pretty_dependency(conflict.requirement)}'"
            if conflict.requirement_trees.first.size > 1
              o << ", which is required by "
              o << "gem '#{SharedHelpers.pretty_dependency(conflict.requirement_trees.first[-2])}',"
            end
            o << " "

            o << if relevant_sources.empty?
                   "in any of the sources.\n"
                 else
                   "in any of the relevant sources:\n  #{relevant_sources * "\n  "}\n"
                 end
          end
        end,
        :version_for_spec => lambda {|spec| spec.version }
      )
    end
  end
end
# rubocop:enable all
