# typed: strong
# frozen_string_literal: true

class StringScanner
  sig { params(string: String).void }
  def initialize(string); end

  sig { params(pattern: T.any(Regexp, String)).returns(T.nilable(String)) }
  def scan(pattern); end

  sig { params(pattern: T.any(Regexp, String)).returns(T.nilable(String)) }
  def scan_until(pattern); end

  sig { returns(T::Boolean) }
  def eos?; end

  sig { returns(String) }
  def rest; end
end
