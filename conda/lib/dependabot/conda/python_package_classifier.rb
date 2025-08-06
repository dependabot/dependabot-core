# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Conda
    class PythonPackageClassifier
      extend T::Sig

      # Known non-Python packages that should be ignored
      NON_PYTHON_PATTERNS = T.let([
        /^r-/i,           # R packages (r-base, r-essentials, etc.)
        /^r$/i,           # R language itself
        /^python$/i,      # Python interpreter (conda-specific, not on PyPI)
        /^git$/i,         # Git version control
        /^gcc$/i,         # GCC compiler
        /^cmake$/i,       # CMake build system
        /^make$/i,        # Make build tool
        /^curl$/i,        # cURL utility
        /^wget$/i,        # Wget utility
        /^vim$/i,         # Vim editor
        /^nano$/i,        # Nano editor
        /^nodejs$/i,      # Node.js runtime
        /^java$/i,        # Java runtime
        /^go$/i,          # Go language
        /^rust$/i,        # Rust language
        /^julia$/i,       # Julia language
        /^perl$/i,        # Perl language
        /^ruby$/i,        # Ruby language
        # System libraries
        /^openssl$/i,     # OpenSSL
        /^zlib$/i,        # zlib compression
        /^libffi$/i,      # Foreign Function Interface library
        /^ncurses$/i,     # Terminal control library
        /^readline$/i,    # Command line editing
        # Compiler and build tools
        /^_libgcc_mutex$/i,
        /^_openmp_mutex$/i,
        /^binutils$/i,
        /^gxx_linux-64$/i,
        # Multimedia libraries
        /^ffmpeg$/i,      # Video processing
        /^opencv$/i,      # Computer vision (note: opencv-python is different)
        /^imageio$/i      # Image I/O (note: imageio python package is different)
      ].freeze, T::Array[Regexp])

      # Determine if a package name represents a Python package
      sig { params(package_name: String).returns(T::Boolean) }
      def self.python_package?(package_name)
        return false if package_name.empty?

        # Extract just the package name without version or channel information
        normalized_name = extract_package_name(package_name).downcase.strip
        return false if normalized_name.empty?

        # Check if it's explicitly a non-Python package
        return false if NON_PYTHON_PATTERNS.any? { |pattern| normalized_name.match?(pattern) }

        # Block obvious binary/system files
        return false if normalized_name.match?(/\.(exe|dll|so|dylib)$/i)
        return false if normalized_name.match?(/^lib.+\.a$/i) # Static libraries

        # Block system mutexes
        return false if normalized_name.match?(/^_[a-z0-9]+_mutex$/i)

        # Default: treat as Python package
        # This aligns with the strategic decision to focus on Python packages
        # Most packages in conda environments are Python packages
        true
      end

      # Extract package name from conda specification (remove channel prefix if present)
      sig { params(spec: String).returns(String) }
      def self.extract_package_name(spec)
        # Handle channel specifications like "conda-forge::numpy=1.21.0"
        parts = spec.split("::")
        package_spec = parts.last || spec

        # Extract package name (before = or space or version operators)
        package_spec.split(/[=<>!~\s]/).first&.strip || spec
      end
    end
  end
end
