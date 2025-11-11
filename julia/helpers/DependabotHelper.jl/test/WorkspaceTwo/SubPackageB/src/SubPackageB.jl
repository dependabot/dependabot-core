module SubPackageB

using JSON
using Dates

greet() = println("Hello from SubPackageB at $(now())!")

end # module SubPackageB
