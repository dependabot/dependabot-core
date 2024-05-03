# typed: false
# frozen_string_literal: true

# Adds default_gem? method to Bundler::LazySpecification
# https://github.com/rubygems/rubygems/blob/bundler-v2.5.9/lib/rubygems/basic_specification.rb#L96-L99

require "bundler/lazy_specification"

# Check if the gem is a default gem
# Ensure loaded_from is not nil and check if the gem is located in the default specifications directory
module LazySpecificationDefaultGemPatch
  def default_gem?
    loaded_from && File.dirname(loaded_from) == Gem.default_specifications_dir
  end
end

# Prepend the module to Bundler::LazySpecification to add the default_gem? method
Bundler::LazySpecification.prepend(LazySpecificationDefaultGemPatch)
