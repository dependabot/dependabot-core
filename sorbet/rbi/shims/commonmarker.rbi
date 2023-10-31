# typed: strong
# frozen_string_literal: true

module CommonMarker
  class << self
    sig { params(src: String, options: Symbol, extensions: T::Array[Symbol]).returns(CommonMarker::Node) }
    def render_doc(src, options = :DEFAULT, extensions = []); end
  end

  class Node
    class << self
      sig { params(_arg0: Symbol).returns(Node) }
      def new(_arg0); end
    end

    sig { params(block: T.proc.params(arg0: Node).void).void }
    def walk(&block); end

    sig { returns(Symbol) }
    def type; end

    sig { returns(String) }
    def url; end

    sig { returns(String) }
    def string_content; end

    sig { params(content: T.nilable(String)).void }
    def string_content=(content); end

    sig { returns(T.nilable(CommonMarker::Node)) }
    def parent; end

    sig { params(block: T.proc.params(arg0: Node).void).void }
    def each(&block); end

    sig { params(options: T.any(Symbol, T::Array[Symbol]), width: Integer).returns(String) }
    def to_commonmark(options = :DEFAULT, width = 0); end

    sig { params(options: T.any(Symbol, T::Array[Symbol]), extensions: T::Array[Symbol]).returns(String) }
    def to_html(options = :DEFAULT, extensions = []); end
  end
end
