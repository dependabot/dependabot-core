# Package

version       = "0.1.0"
author        = "someone"
description   = "An example package"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0.0", "chronos >= 4.0.4"
requires "bearssl"   # no version: any
requires("unittest2 ~= 0.2.0")
# requires "commented >= 1.0"
requires "pinned == 1.2.3",
         "ranged >= 1.0 & < 2.0"
requires "https://github.com/someone/gitonly#head", "branchy#main"

taskRequires "test", "balls ^= 5.0"

task test, "Run the tests":
  exec "nim c -r tests/all"
