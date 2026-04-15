load("@aspect_rules_ts//ts:defs.bzl", _ts_project = "ts_project")
load("@aspect_rules_swc//swc:defs.bzl", "swc")
load("@bazel_skylib//lib:partial.bzl", "partial")

def ts_project(**kwargs):
    """Provides defaults for ts_project"""

    tsconfig = kwargs.pop("tsconfig", "//public:tsconfig")
    validate = kwargs.pop("validate", False)
    transpiler = kwargs.pop("transpiler", partial.make(swc, swcrc = "//:.swcrc"))
    declaration = kwargs.pop("declaration", False)
    source_map = kwargs.pop("source_map", False)

    _ts_project(
        tsconfig = tsconfig,
        validate = validate,
        transpiler = transpiler,
        declaration = declaration,
        source_map = source_map,
        **kwargs,
    )
