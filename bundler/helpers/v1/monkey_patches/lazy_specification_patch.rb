# typed: false
# frozen_string_literal: true

# Adds default_gem? method to Bundler::LazySpecification
# https://github.com/rubygems/rubygems/blob/bundler-v2.5.9/lib/rubygems/basic_specification.rb#L96-L99

require "bundler/lazy_specification"

# Check if the gem is a default gem
# Ensure loaded_from is not nil and check if the gem is located in the default specifications directory
module LazySpecificationDefaultGemPatch
  attr_accessor :loaded_from unless instance_methods.include?(:loaded_from)

  def default_gem?
    # Ensure `loaded_from` is not nil and check if it's in the default specifications directory
    if loaded_from
      File.dirname(File.expand_path(loaded_from)) == Gem.default_specifications_dir
    else
      false
    end
  end
end

# Prepend the module to Bundler::LazySpecification to add the default_gem? method
Bundler::LazySpecification.prepend(LazySpecificationDefaultGemPatch)
