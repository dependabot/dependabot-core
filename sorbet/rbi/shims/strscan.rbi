# typed: strong
# frozen_string_literal: true

class StringScanner < Object
  sig { params(_: Regexp).returns(T.nilable(String)) }
  def scan_until(_); end
end
