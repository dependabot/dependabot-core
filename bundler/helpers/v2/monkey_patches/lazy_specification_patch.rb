# typed: false
# frozen_string_literal: true

# Adds default_gem? method to Bundler::LazySpecification
# https://github.com/rubygems/rubygems/blob/bundler-v2.5.9/lib/rubygems/basic_specification.rb#L96-L99

require "bundler/lazy_specification"

# Check if the gem is a default gem
# Ensure loaded_from is not nil and check if the gem is located in the default specifications directory
module LazySpecificationDefaultGemPatch
  def default_gem?
    # Check if `loaded_from` responds and is not nil, and verify its directory
    if respond_to?(:loaded_from) && loaded_from
      File.dirname(loaded_from) == Gem.default_specifications_dir
    else
      false
    end
  end

  # Ensuring loaded_from is defined in the LazySpecification
  def loaded_from
    @loaded_from
  end

  def loaded_from=(path)
    @loaded_from = path
  end
end

# Prepend the module to Bundler::LazySpecification to add the default_gem? method
Bundler::LazySpecification.prepend(LazySpecificationDefaultGemPatch)
