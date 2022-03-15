# frozen_string_literal: true

require "bundler/resolver/spec_group"

# Port
# https://github.com/rubygems/bundler/commit/30a690edbdf5ee64ea54afc7d0c91d910ff2b80e
# to fix flaky failures on Bundler 1

module BundlerResolverSpecGroupSaneEql
  def eql?(other)
    return unless other.is_a?(self.class)

    super(other)
  end
end

Bundler::Resolver::SpecGroup.prepend(BundlerResolverSpecGroupSaneEql)
