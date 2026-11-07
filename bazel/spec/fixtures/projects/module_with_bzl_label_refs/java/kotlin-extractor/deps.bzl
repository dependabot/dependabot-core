load("//lib:utils.bzl", "util_fn")

_src = Label("//java/kotlin-extractor:src")
_template = Label("//tools:template.txt")

def _my_ext_impl(ctx):
    pass

my_ext = module_extension(implementation = _my_ext_impl)
