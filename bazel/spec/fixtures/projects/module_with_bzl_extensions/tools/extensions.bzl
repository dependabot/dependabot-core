load("//lib:helpers.bzl", "helper_fn")

def _my_ext_impl(ctx):
    pass

my_ext = module_extension(implementation = _my_ext_impl)
