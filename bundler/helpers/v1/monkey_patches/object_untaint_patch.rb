# typed: false
# frozen_string_literal: true

# Bundler v1 uses the `untaint` method on objects in `Bundler::SharedHelpers`.
# This method has been deprecated for a long time, and is actually a no-op in
# ruby versions 2.7+. In Ruby 3.3 it was finally removed, and it's now causing
# bundler v1 to error.
#
# In order to keep the old behavior, we're monkey patching `Object` to add a
# no-op implementation of untaint.
module ObjectUntaintPatch
  def untaint
    self
  end
end

Object.prepend(ObjectUntaintPatch)
