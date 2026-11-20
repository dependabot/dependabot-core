#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

# Refreshes common/lib/dependabot/dependency_graphers/graph_versions.json after the sources that shape a
# package manager's dependency graph change. Every owner whose sources changed needs an explicit decision:
#   bin/update-manifest-set-graph-versions.rb --bump pip   # graph output can change: bump pip's graph_version
#   bin/update-manifest-set-graph-versions.rb --keep pip   # graph output cannot change (e.g. a pure refactor)
#   bin/update-manifest-set-graph-versions.rb --check      # exit 1 if any owner is stale
# --bump may also be given for an owner whose sources did not change.

require "optparse"

$LOAD_PATH.unshift(File.expand_path("../common/lib", __dir__))
require "dependabot/dependency_graphers/graph_versions"

graph_versions = Dependabot::DependencyGraphers::GraphVersions
bump = []
keep = []
check = T.let(false, T::Boolean)
OptionParser.new do |opts|
  opts.on("--bump OWNER", "Bump OWNER's graph_version") { |owner| bump << owner }
  opts.on("--keep OWNER", "Keep OWNER's graph_version") { |owner| keep << owner }
  opts.on("--check", "Exit 1 if the lock is stale") { check = true }
end.parse!

entries = graph_versions.entries
unknown = (bump + keep).uniq - entries.keys
abort("unknown owners: #{unknown.join(', ')}") unless unknown.empty?
abort("an owner cannot be both bumped and kept: #{(bump & keep).join(', ')}") if bump.intersect?(keep)

stale = graph_versions.stale_owners(entries: entries)
if check
  abort("graph versions are stale for: #{stale.join(', ')}; run #{$PROGRAM_NAME} --bump or --keep") unless stale.empty?
  puts "graph versions are up to date"
  exit
end

undecided = stale - bump - keep
unless undecided.empty?
  abort(
    "sources changed for #{undecided.join(', ')}: pass --bump OWNER if the graph output can change, " \
    "or --keep OWNER if it cannot"
  )
end

updated = entries.to_h do |owner, entry|
  version = entry.graph_version
  if bump.include?(owner)
    unless version.match?(/\A[1-9][0-9]*\z/)
      abort("#{owner}'s graph_version #{version.inspect} is not an integer; edit it by hand")
    end
    version = (version.to_i + 1).to_s
  end
  [owner, graph_versions::Entry.new(
    graph_version: version,
    sources: entry.sources,
    sources_sha256: graph_versions.sources_sha256(entry.sources)
  )]
end
File.write(graph_versions::LOCK_PATH, graph_versions.render(updated))
updated.each { |owner, entry| puts "#{owner}: graph_version #{entry.graph_version}" }
