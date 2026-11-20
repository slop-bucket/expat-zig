const std = @import("std");
const Translator = @import("translate_c").Translator;
const manifest = @import("build.zig.zon");

const package_version_str = manifest.version;
const package_version = std.SemanticVersion.parse(package_version_str) catch unreachable;
const package_name = @tagName(manifest.name);
const package_tarname = package_name;
const package_string = package_name ++ " " ++ package_version_str;
const package_bugreport = "https://github.com/libexpat/libexpat/issues";
const package_url = "";

// Sync with configure.ac / ref/CMakeLists.txt (LIBCURRENT, LIBREVISION, LIBAGE).
const lib_current: u32 = 14;
const lib_revision: u32 = 1;
const lib_age: u32 = 13;
const lib_current_minus_age: u32 = lib_current - lib_age;

const CharType = enum {
    char,
    ushort,
    wchar_t,
};

const EntropyKind = enum {
    arc4random,
    arc4random_buf,
    getentropy,
    getrandom,
    syscall_getrandom,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Note: EXPAT_ATTR_INFO and EXPAT_MIN_SIZE were removed upstream; Zig's CLI
    // rejects unknown -D options directly. _EXPAT_M32 is superseded by -Dtarget.
    const shared = b.option(
        bool,
        "shared",
        "Build a shared expat library (EXPAT_SHARED_LIBS)",
    ) orelse (target.result.os.tag != .wasi and target.result.os.tag != .freestanding);

    const char_type = b.option(
        CharType,
        "char-type",
        "Character type to use: char, ushort, wchar_t [default: char]",
    ) orelse .char;

    const short_wchar = b.option(
        bool,
        "short-wchar",
        "Pass -fshort-wchar (required for -Dchar-type=wchar_t on non-Windows targets)",
    ) orelse false;

    const build_tools_opt = b.option(
        bool,
        "build-tools",
        "Build the xmlwf and gennmtab tools (EXPAT_BUILD_TOOLS)",
    );
    const build_examples_opt = b.option(
        bool,
        "build-examples",
        "Build the examples for expat library (EXPAT_BUILD_EXAMPLES)",
    );
    const build_tests_opt = b.option(
        bool,
        "build-tests",
        "Build the tests for expat library (EXPAT_BUILD_TESTS)",
    );
    const build_docs_opt = b.option(
        bool,
        "build-docs",
        "Build man page for xmlwf (EXPAT_BUILD_DOCS)",
    );
    const build_fuzzers = b.option(
        bool,
        "build-fuzzers",
        "Build fuzzers for the expat library (EXPAT_BUILD_FUZZERS)",
    ) orelse false;
    const ossfuzz_build = b.option(
        bool,
        "ossfuzz-build",
        "Build fuzzers via OSS-Fuzz (EXPAT_OSSFUZZ_BUILD)",
    ) orelse false;
    const fuzzing_engine_opt = b.option(
        []const u8,
        "fuzzing-engine",
        "Path to fuzzing engine archive/object (e.g. libFuzzer) for non-OSS-Fuzz builds",
    );
    const build_pkgconfig = b.option(
        bool,
        "build-pkgconfig",
        "Build pkg-config file (EXPAT_BUILD_PKGCONFIG)",
    ) orelse !(target.result.os.tag == .windows and target.result.abi == .msvc);
    const pkgconfig_prefix = b.option(
        []const u8,
        "pkgconfig-prefix",
        "Install prefix written into expat.pc [default: relocatable ${pcfiledir}/../..]",
    ) orelse "${pcfiledir}/../..";
    const enable_install = b.option(
        bool,
        "enable-install",
        "Install expat files in install step (EXPAT_ENABLE_INSTALL)",
    ) orelse true;

    const context_bytes = b.option(
        u32,
        "context-bytes",
        "How much context to retain around the current parse point, 0 to disable [default: 1024]",
    ) orelse 1024;
    const symbol_versioning = b.option(
        bool,
        "symbol-versioning",
        "Provide symbol versioning via libexpat.map (EXPAT_SYMBOL_VERSIONING)",
    ) orelse false;
    const enable_dtd = b.option(
        bool,
        "dtd",
        "Make parameter entity parsing functionality available (EXPAT_DTD) [default: true]",
    ) orelse true;
    const enable_ge = b.option(
        bool,
        "ge",
        "Make general entity parsing functionality available (EXPAT_GE) [default: true]",
    ) orelse true;
    const enable_ns = b.option(
        bool,
        "ns",
        "Make XML Namespaces functionality available (EXPAT_NS) [default: true]",
    ) orelse true;
    const warnings_as_errors = b.option(
        bool,
        "warnings-as-errors",
        "Treat all compiler warnings as errors (EXPAT_WARNINGS_AS_ERRORS)",
    ) orelse false;
    const large_size = b.option(
        bool,
        "large-size",
        "[DEPRECATED] Make XML_GetCurrent* functions return long long (EXPAT_LARGE_SIZE)",
    ) orelse false;
    const postfix_opt = b.option(
        []const u8,
        "postfix",
        "Override library filename postfix (EXPAT_<CONFIG>_POSTFIX)",
    );

    const dev_urandom_opt = b.option(
        bool,
        "dev-urandom",
        "Include code reading entropy from /dev/urandom (EXPAT_DEV_URANDOM)",
    ) orelse (if (comptime @hasField(std.Target.Os.Tag, "aix")) target.result.os.tag == .aix else false);
    const with_arc4random = b.option(
        bool,
        "with-arc4random",
        "Make use of arc4random function [default: auto-detect]",
    );
    const with_arc4random_buf = b.option(
        bool,
        "with-arc4random-buf",
        "Make use of arc4random_buf function [default: auto-detect]",
    );
    const with_getentropy = b.option(
        bool,
        "with-getentropy",
        "Make use of getentropy function [default: auto-detect]",
    );
    const with_getrandom = b.option(
        bool,
        "with-getrandom",
        "Make use of getrandom function [default: auto-detect]",
    );
    const with_sys_getrandom = b.option(
        bool,
        "with-sys-getrandom",
        "Make use of syscall SYS_getrandom [default: auto-detect]",
    );

    const build_tools = build_tools_opt orelse
        (char_type == .char or (char_type == .wchar_t and target.result.os.tag == .windows));
    const build_examples = build_examples_opt orelse (char_type != .ushort);
    const build_tests = build_tests_opt orelse (char_type != .ushort);

    const docbook_to_man: ?[]const u8 = if (build_tools and !(target.result.os.tag == .windows and target.result.abi == .msvc) and build_docs_opt != false)
        b.findProgram(.{
            .names = &.{ "docbook2x-man", "db2x_docbook2man", "docbook2man", "docbook-to-man" },
        })
    else
        null;
    const build_docs = build_docs_opt orelse (docbook_to_man != null);

    // Validation checks matching ref/CMakeLists.txt.
    if (enable_dtd and !enable_ge) {
        return failBuild(b, "Option -Ddtd=true requires -Dge=true. Please either enable -Dge=true (recommended) or pass -Ddtd=false.");
    }

    if (char_type == .ushort) {
        if (build_examples_opt == true) {
            return failBuild(b, "Examples can not be built with -Dchar-type=ushort. Please pass -Dchar-type=(char|wchar_t) or -Dbuild-examples=false.");
        }
        if (build_tests_opt == true) {
            return failBuild(b, "The testsuite can not be built with -Dchar-type=ushort. Please pass -Dchar-type=(char|wchar_t) or -Dbuild-tests=false.");
        }
        if (build_tools_opt == true) {
            return failBuild(b, "The xmlwf tool can not be built with -Dchar-type=ushort. Please pass -Dchar-type=(char|wchar_t) or -Dbuild-tools=false.");
        }
    } else if (char_type == .wchar_t and target.result.os.tag != .windows) {
        if (!short_wchar) {
            return failBuild(b, "Configuration -Dchar-type=wchar_t on non-Windows requires -Dshort-wchar=true (-fshort-wchar) and libc compiled with -fshort-wchar, too.");
        }
        if (build_tools_opt == true) {
            return failBuild(b, "The xmlwf tool can not be built with -Dchar-type=wchar_t outside of Windows. Please pass -Dchar-type=char or -Dbuild-tools=false.");
        }
    }

    if (ossfuzz_build and !build_fuzzers) {
        return failBuild(b, "Attempting to perform an OSS-Fuzz build without turning on fuzzers. Consider adding -Dbuild-fuzzers=true.");
    }

    if (build_docs_opt == true) {
        if (!build_tools) {
            return failBuild(b, "Option -Dbuild-docs=true requires -Dbuild-tools=true.");
        }
        if (target.result.os.tag == .windows and target.result.abi == .msvc) {
            return failBuild(b, "Option -Dbuild-docs=true is not supported with MSVC targets.");
        }
        if (docbook_to_man == null) {
            return failBuild(b, "Option -Dbuild-docs=true was requested, but docbook2x-man/db2x_docbook2man/docbook2man/docbook-to-man was not found in PATH.");
        }
    }

    if (symbol_versioning and shared and (target.result.os.tag == .windows or target.result.os.tag.isDarwin())) {
        return failBuild(b, "Option -Dsymbol-versioning=true uses an ELF linker version script (libexpat.map) and is only supported on ELF shared libraries.");
    }

    const triple_alloc = target.result.zigTriple(b.allocator) catch @panic("OOM");
    const have_arc4random = resolveEntropy(b, target.result, with_arc4random, .arc4random, "function arc4random", "with-arc4random", triple_alloc) orelse return;
    const have_arc4random_buf = resolveEntropy(b, target.result, with_arc4random_buf, .arc4random_buf, "function arc4random_buf", "with-arc4random-buf", triple_alloc) orelse return;
    const have_getentropy = resolveEntropy(b, target.result, with_getentropy, .getentropy, "function getentropy", "with-getentropy", triple_alloc) orelse return;
    const have_getrandom = resolveEntropy(b, target.result, with_getrandom, .getrandom, "function getrandom", "with-getrandom", triple_alloc) orelse return;
    const have_syscall_getrandom = resolveEntropy(b, target.result, with_sys_getrandom, .syscall_getrandom, "syscall SYS_getrandom", "with-sys-getrandom", triple_alloc) orelse return;

    const fuzzing_engine: ?[]const u8 = if (build_fuzzers and ossfuzz_build)
        b.graph.environ_map.get("LIB_FUZZING_ENGINE") orelse {
            return failBuild(b, "OSS-Fuzz builds require the environment variable LIB_FUZZING_ENGINE to be set.");
        }
    else
        fuzzing_engine_opt;

    const unicode = char_type != .char;
    const unicode_wchar_t = char_type == .wchar_t;
    const default_postfix = b.fmt("{s}{s}", .{
        if (unicode) "w" else "",
        if (target.result.os.tag == .windows and optimize == .debug) "d" else "",
    });
    const postfix = postfix_opt orelse default_postfix;
    const output_name = if (target.result.os.tag == .windows and target.result.abi != .gnu) "libexpat" else "expat";
    const dev_urandom = if (target.result.os.tag == .windows) false else dev_urandom_opt;

    const expat_dep = b.dependency("expat", .{});
    const expat_root = expat_dep.path("expat");
    const lib_inc = expat_dep.path("expat/lib");

    // Generate expat_config.h matching ref/CMakeLists.txt + expat_config.h.cmake.
    const config_header = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "expat_config.h",
    }, .{
        .BYTEORDER = @as(i64, if (target.result.cpu.arch.endian() == .big) 4321 else 1234),
        .HAVE_ARC4RANDOM = boolDefine(have_arc4random),
        .HAVE_ARC4RANDOM_BUF = boolDefine(have_arc4random_buf),
        .HAVE_DLFCN_H = boolDefine(target.result.os.tag != .windows and target.result.os.tag != .wasi),
        .HAVE_FCNTL_H = boolDefine(true),
        .HAVE_GETPAGESIZE = boolDefine(target.result.os.tag != .windows and target.result.os.tag != .wasi),
        .HAVE_GETRANDOM = boolDefine(have_getrandom),
        .HAVE_GETENTROPY = boolDefine(have_getentropy),
        .HAVE_INTTYPES_H = boolDefine(true),
        .HAVE_MEMORY_H = boolDefine(true),
        .HAVE_MMAP = boolDefine(target.result.os.tag != .windows and target.result.os.tag != .wasi),
        .HAVE_STDINT_H = boolDefine(true),
        .HAVE_STDLIB_H = boolDefine(true),
        .HAVE_STRINGS_H = boolDefine(!(target.result.os.tag == .windows and target.result.abi == .msvc)),
        .HAVE_STRING_H = boolDefine(true),
        .HAVE_SYSCALL_GETRANDOM = boolDefine(have_syscall_getrandom),
        .HAVE_SYS_STAT_H = boolDefine(true),
        .HAVE_SYS_TYPES_H = boolDefine(true),
        .HAVE_UNISTD_H = boolDefine(!(target.result.os.tag == .windows and target.result.abi == .msvc)),
        .PACKAGE = package_name,
        .PACKAGE_BUGREPORT = package_bugreport,
        .PACKAGE_NAME = package_name,
        .PACKAGE_STRING = package_string,
        .PACKAGE_TARNAME = package_tarname,
        .PACKAGE_URL = package_url,
        .PACKAGE_VERSION = package_version_str,
        .STDC_HEADERS = boolDefine(true),
        .WORDS_BIGENDIAN = boolDefine(target.result.cpu.arch.endian() == .big),
        .XML_CONTEXT_BYTES = @as(i64, context_bytes),
        .XML_DEV_URANDOM = boolDefine(target.result.os.tag != .windows and dev_urandom),
        .XML_DTD = boolDefine(enable_dtd),
        .XML_GE = @as(i64, if (enable_ge) 1 else 0),
        .XML_NS = boolDefine(enable_ns),
        .off_t = @as(?enum { long }, null),
    });

    // Compiler flags and source file list.
    const c_flags = buildCFlags(b, target.result, unicode_wchar_t, short_wchar, warnings_as_errors);
    const expat_c_sources = buildExpatCSources(
        b,
        target.result,
        dev_urandom,
        have_arc4random,
        have_arc4random_buf,
        have_getentropy,
        have_getrandom,
        have_syscall_getrandom,
    );

    // Exported Zig configuration module (port of ref/expat-config.cmake.in).
    const config_opts = b.addOptions();
    config_opts.addOption([]const u8, "version", package_version_str);
    config_opts.addOption(bool, "attr_info", false);
    config_opts.addOption(bool, "min_size", false);
    config_opts.addOption(bool, "dtd", enable_dtd);
    config_opts.addOption(bool, "ge", enable_ge);
    config_opts.addOption(bool, "ns", enable_ns);
    config_opts.addOption(bool, "large_size", large_size);
    config_opts.addOption(u32, "context_bytes", context_bytes);
    config_opts.addOption(CharType, "char_type", char_type);
    config_opts.addOption(bool, "shared", shared);
    _ = b.addModule("config", .{
        .root_source_file = config_opts.getOutput(),
    });

    // Main C library target: expat.
    const lib_name = b.fmt("{s}{s}", .{ output_name, postfix });
    const lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_mod.addConfigHeader(config_header);
    lib_mod.addIncludePath(lib_inc);
    applyCommonMacros(lib_mod, target.result, shared, large_size, unicode, unicode_wchar_t);
    if (target.result.os.tag == .windows and !shared) {
        lib_mod.addCMacro("XML_STATIC", "1");
    }
    lib_mod.addCSourceFiles(.{
        .root = expat_root,
        .files = expat_c_sources,
        .flags = c_flags,
    });
    if (needsLibm(target.result)) {
        lib_mod.linkSystemLibrary("m", .{});
    }

    const dtd_or_ge = enable_dtd or enable_ge;
    var win32_def_file: ?std.Build.LazyPath = null;
    if (target.result.os.tag == .windows and shared) {
        const dll_ver = b.fmt("-DVER_FILEVERSION={d},{d},{d},0", .{
            package_version.major,
            package_version.minor,
            package_version.patch,
        });
        const dll_ver_str = b.fmt("-DVER_FILEVERSION_STR=\"{s}.0\"", .{package_version_str});
        lib_mod.addWin32ResourceFile(.{
            .file = b.path("build/version.rc"),
            .flags = &.{ dll_ver, dll_ver_str },
        });

        win32_def_file = addConfiguredTemplate(
            b,
            expat_dep.path("expat/lib/libexpat.def.cmake"),
            "libexpat.def",
            if (dtd_or_ge) " " else ";",
        );
    }

    const lib = b.addLibrary(.{
        .name = lib_name,
        .linkage = if (shared) .dynamic else .static,
        .version = if (shared and target.result.os.tag != .windows)
            .{
                .major = lib_current_minus_age,
                .minor = lib_age,
                .patch = lib_revision,
            }
        else
            null,
        .win32_module_definition = win32_def_file,
        .root_module = lib_mod,
    });

    if (target.result.os.tag != .windows and shared and symbol_versioning) {
        const map_file = addConfiguredTemplate(
            b,
            expat_dep.path("expat/lib/libexpat.map.in"),
            "libexpat.map",
            if (dtd_or_ge) " " else "#",
        );
        lib.setVersionScript(map_file);
    }

    lib.installHeader(expat_dep.path("expat/lib/expat.h"), "expat.h");
    lib.installHeader(expat_dep.path("expat/lib/expat_external.h"), "expat_external.h");
    lib.installConfigHeader(config_header);

    if (enable_install) {
        b.installArtifact(lib);
    } else {
        b.getInstallStep().dependOn(&lib.step);
    }

    // Exported Zig module wrapping expat.h via translate-c.
    const translate_c = b.dependency("translate_c", .{});
    const expat_translator: Translator = .init(translate_c, .{
        .name = "expat",
        .c_source_file = expat_dep.path("expat/lib/expat.h"),
        .target = target,
        .optimize = optimize,
    });
    expat_translator.addIncludePath(lib_inc);
    expat_translator.linkLibrary(lib);
    if (large_size) {
        expat_translator.defineCMacro("XML_LARGE_SIZE", "1");
    }
    if (unicode) {
        expat_translator.defineCMacro("XML_UNICODE", "1");
        if (unicode_wchar_t) {
            expat_translator.defineCMacro("XML_UNICODE_WCHAR_T", "1");
        }
    }
    if (enable_dtd) {
        expat_translator.defineCMacro("XML_DTD", "1");
    }
    expat_translator.defineCMacro("XML_GE", if (enable_ge) "1" else "0");
    if (target.result.os.tag == .windows and !shared) {
        expat_translator.defineCMacro("XML_STATIC", "1");
    }
    b.modules.put(b.allocator, b.dupe("expat"), expat_translator.mod) catch @panic("OOM");

    const zig_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/expat_zig_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    zig_test_mod.addImport("expat", expat_translator.mod);
    if (shared and target.result.os.tag != .windows) {
        if (target.result.os.tag.isDarwin()) {
            zig_test_mod.addRPathSpecial("@loader_path/../lib");
        } else if (target.result.os.tag != .wasi) {
            zig_test_mod.addRPathSpecial("$ORIGIN/../lib");
        }
    }
    const zig_test_exe = b.addTest(.{
        .name = "expat-zig-test",
        .root_module = zig_test_mod,
    });
    const run_zig_test = b.addRunArtifact(zig_test_exe);
    const zig_test_step = b.step("zig-test", "Run Zig integration tests for the expat module");
    zig_test_step.dependOn(&run_zig_test.step);

    // pkg-config file (expat.pc).
    if (build_pkgconfig) {
        const pc_content = b.fmt(@embedFile("build/expat.pc.in"), .{
            pkgconfig_prefix,
            postfix,
            package_version_str,
            lib_name,
            if (target.result.os.tag != .windows and target.result.os.tag != .wasi and target.result.os.tag != .freestanding) "-lm" else "",
        });
        const pc_file = b.addWriteFiles().add("expat.pc", pc_content);
        if (enable_install) {
            b.getInstallStep().dependOn(&b.addInstallLibFile(pc_file, "pkgconfig/expat.pc").step);
        }
    }

    // Documentation files (AUTHORS, changelog, optional xmlwf.1 man page).
    if (enable_install) {
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(
            expat_dep.path("expat/AUTHORS"),
            .prefix,
            "share/doc/expat/AUTHORS",
        ).step);
        b.getInstallStep().dependOn(&b.addInstallFileWithDir(
            expat_dep.path("expat/Changes"),
            .prefix,
            "share/doc/expat/changelog",
        ).step);
    }

    // Tools: xmlwf and gennmtab.
    var xmlwf_exe: ?*std.Build.Step.Compile = null;
    if (build_tools) {
        const xmlwf_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        xmlwf_mod.addConfigHeader(config_header);
        xmlwf_mod.addIncludePath(lib_inc);
        xmlwf_mod.addIncludePath(expat_dep.path("expat/xmlwf"));
        applyCommonMacros(xmlwf_mod, target.result, shared, large_size, unicode, unicode_wchar_t);
        if (target.result.os.tag == .windows and !shared) {
            xmlwf_mod.addCMacro("XML_STATIC", "1");
        }
        xmlwf_mod.addCSourceFiles(.{
            .root = expat_root,
            .files = &.{
                "lib/xcs.c",
                "xmlwf/codepage.c",
                "xmlwf/readfilemap.c",
                "xmlwf/xmlfile.c",
                "xmlwf/xmlwf.c",
            },
            .flags = c_flags,
        });
        xmlwf_mod.linkLibrary(lib);
        if (needsLibm(target.result)) {
            xmlwf_mod.linkSystemLibrary("m", .{});
        }
        if (shared and target.result.os.tag != .windows) {
            if (target.result.os.tag.isDarwin()) {
                xmlwf_mod.addRPathSpecial("@loader_path/../lib");
            } else if (target.result.os.tag != .wasi) {
                xmlwf_mod.addRPathSpecial("$ORIGIN/../lib");
            }
        }

        const xmlwf = b.addExecutable(.{
            .name = "xmlwf",
            .root_module = xmlwf_mod,
        });
        if (target.result.os.tag == .windows and target.result.abi == .gnu and unicode_wchar_t) {
            xmlwf.mingw_unicode_entry_point = true;
        }
        xmlwf_exe = xmlwf;

        if (enable_install) {
            b.installArtifact(xmlwf);
        } else {
            b.getInstallStep().dependOn(&xmlwf.step);
        }

        const run_xmlwf = b.addRunArtifact(xmlwf);
        run_xmlwf.addPassthruArgs();
        const xmlwf_step = b.step("xmlwf", "Run the xmlwf CLI tool");
        xmlwf_step.dependOn(&run_xmlwf.step);

        // Internal table generator tool gennmtab (built, not installed to bin/).
        // Upstream gennmtab/gennmtab.c:425 shifts signed 1 << 31; disable C UBSan so Debug runs cleanly.
        const gennmtab_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .sanitize_c = .off,
        });
        applyCommonMacros(gennmtab_mod, target.result, shared, large_size, unicode, unicode_wchar_t);
        gennmtab_mod.addCSourceFiles(.{
            .root = expat_root,
            .files = &.{"gennmtab/gennmtab.c"},
            .flags = c_flags,
        });
        const gennmtab = b.addExecutable(.{
            .name = "gennmtab",
            .root_module = gennmtab_mod,
        });
        b.getInstallStep().dependOn(&gennmtab.step);

        const run_gennmtab = b.addRunArtifact(gennmtab);
        run_gennmtab.addPassthruArgs();
        const gennmtab_step = b.step("gennmtab", "Run the gennmtab table generator");
        gennmtab_step.dependOn(&run_gennmtab.step);

        if (build_docs) {
            if (docbook_to_man) |tool| {
                const man_step = b.addSystemCommand(&.{
                    "sh",
                    "-c",
                    "mkdir -p \"$1\" && cd \"$1\" && \"$2\" \"$3\" && mv XMLWF.1 xmlwf.1",
                    "_",
                });
                const out_dir = man_step.addOutputDirectoryArg("doc");
                man_step.addArg(tool);
                man_step.addFileArg(expat_dep.path("expat/doc/xmlwf.xml"));

                b.getInstallStep().dependOn(&man_step.step);
                if (enable_install) {
                    const man_file = out_dir.path(b, "xmlwf.1");
                    b.getInstallStep().dependOn(&b.addInstallFileWithDir(
                        man_file,
                        .prefix,
                        "share/man/man1/xmlwf.1",
                    ).step);
                }
            }
        }
    }

    // Examples: element_declarations, elements, outline.
    if (build_examples) {
        const examples_step = b.step("examples", "Build and install Expat example programs to zig-out/examples");
        const example_names = [_][]const u8{
            "element_declarations",
            "elements",
            "outline",
        };
        for (example_names) |name| {
            const ex_mod = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            ex_mod.addIncludePath(lib_inc);
            applyCommonMacros(ex_mod, target.result, shared, large_size, unicode, unicode_wchar_t);
            if (target.result.os.tag == .windows and !shared) {
                ex_mod.addCMacro("XML_STATIC", "1");
            }
            ex_mod.addCSourceFiles(.{
                .root = expat_root,
                .files = &.{b.fmt("examples/{s}.c", .{name})},
                .flags = c_flags,
            });
            ex_mod.linkLibrary(lib);
            if (shared and target.result.os.tag != .windows) {
                if (target.result.os.tag.isDarwin()) {
                    ex_mod.addRPathSpecial("@loader_path/../lib");
                } else if (target.result.os.tag != .wasi) {
                    ex_mod.addRPathSpecial("$ORIGIN/../lib");
                }
            }

            const ex = b.addExecutable(.{
                .name = name,
                .root_module = ex_mod,
            });
            b.getInstallStep().dependOn(&ex.step);

            const install_ex = b.addInstallArtifact(ex, .{
                .dest_dir = .{ .override = .{ .custom = "examples" } },
            });
            examples_step.dependOn(&install_ex.step);
        }
    }

    // Tests: runtests + benchmark.
    if (build_tests) {
        const test_sources = [_][]const u8{
            "tests/acc_tests.c",
            "tests/alloc_tests.c",
            "tests/basic_tests.c",
            "tests/chardata.c",
            "tests/common.c",
            "tests/dummy.c",
            "tests/handlers.c",
            "tests/hash_tests.c",
            "tests/entities_tests.c",
            // Note: ref/CMakeLists.txt references tests/fifth_edition_tests.c (post-2.10.0);
            // it does not exist in the Expat 2.10.0 release tarball.
            "tests/memcheck.c",
            "tests/minicheck.c",
            "tests/misc_tests.c",
            "tests/ns_tests.c",
            "tests/nsalloc_tests.c",
            "tests/props_tests.c",
            "tests/runtests.c",
            "tests/structdata.c",
            "tests/xcs_tests.c",
        };

        const runtests_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        runtests_mod.addConfigHeader(config_header);
        runtests_mod.addIncludePath(lib_inc);
        runtests_mod.addIncludePath(expat_dep.path("expat/tests"));
        applyCommonMacros(runtests_mod, target.result, shared, large_size, unicode, unicode_wchar_t);
        runtests_mod.addCMacro("XML_TESTING", "1");
        if (target.result.os.tag == .windows) {
            runtests_mod.addCMacro("XML_STATIC", "1");
        }
        runtests_mod.addCSourceFiles(.{
            .root = expat_root,
            .files = &test_sources,
            .flags = c_flags,
        });
        runtests_mod.addCSourceFiles(.{
            .root = expat_root,
            .files = expat_c_sources,
            .flags = c_flags,
        });
        if (needsLibm(target.result)) {
            runtests_mod.linkSystemLibrary("m", .{});
        }

        const runtests = b.addExecutable(.{
            .name = "runtests",
            .root_module = runtests_mod,
        });
        b.getInstallStep().dependOn(&runtests.step);

        const run_tests = b.addRunArtifact(runtests);
        run_tests.addPassthruArgs();
        const test_step = b.step("test", "Run the Expat unit test suite");
        test_step.dependOn(&run_tests.step);

        // Benchmark executable.
        const bench_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        bench_mod.addIncludePath(lib_inc);
        applyCommonMacros(bench_mod, target.result, shared, large_size, unicode, unicode_wchar_t);
        if (target.result.os.tag == .windows and !shared) {
            bench_mod.addCMacro("XML_STATIC", "1");
        }
        bench_mod.addCSourceFiles(.{
            .root = expat_root,
            .files = &.{"tests/benchmark/benchmark.c"},
            .flags = c_flags,
        });
        bench_mod.linkLibrary(lib);
        if (shared and target.result.os.tag != .windows) {
            if (target.result.os.tag.isDarwin()) {
                bench_mod.addRPathSpecial("@loader_path/../lib");
            } else if (target.result.os.tag != .wasi) {
                bench_mod.addRPathSpecial("$ORIGIN/../lib");
            }
        }
        const benchmark = b.addExecutable(.{
            .name = "benchmark",
            .root_module = bench_mod,
        });
        b.getInstallStep().dependOn(&benchmark.step);

        const run_bench = b.addRunArtifact(benchmark);
        run_bench.addPassthruArgs();
        const bench_step = b.step("benchmark", "Run the Expat benchmark tool");
        bench_step.dependOn(&run_bench.step);
    }

    // W3C XML conformance suite (run-xmltest).
    if (build_tools and !(target.result.os.tag == .windows and target.result.abi == .msvc)) {
        if (xmlwf_exe) |xmlwf| {
            const xmltest_cmd = b.addSystemCommand(&.{"sh"});
            xmltest_cmd.addFileArg(b.path("build/run_xmltest.sh"));
            xmltest_cmd.addArg(".zig-cache/xmltest");
            xmltest_cmd.addDirectoryArg(expat_root);
            xmltest_cmd.addArtifactArg(xmlwf);
            const xmltest_step = b.step("run-xmltest", "Download W3C XML conformance suite and run xmlwf against it");
            xmltest_step.dependOn(&xmltest_cmd.step);
        }
    }

    // Fuzzers (fuzzpat + libFuzzer targets; xml_lpm_fuzzer requires external protobuf/LPM).
    if (build_fuzzers) {
        const fuzzpat_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .fuzz = if (!ossfuzz_build) true else null,
        });
        fuzzpat_mod.addConfigHeader(config_header);
        fuzzpat_mod.addIncludePath(lib_inc);
        applyCommonMacros(fuzzpat_mod, target.result, shared, large_size, unicode, unicode_wchar_t);
        if (target.result.os.tag == .windows) {
            fuzzpat_mod.addCMacro("XML_STATIC", "1");
        }
        fuzzpat_mod.addCSourceFiles(.{
            .root = expat_root,
            .files = expat_c_sources,
            .flags = c_flags,
        });
        const fuzzpat = b.addLibrary(.{
            .name = "fuzzpat",
            .linkage = .static,
            .root_module = fuzzpat_mod,
        });

        const fuzz_main_c: ?std.Build.LazyPath = if (fuzzing_engine == null)
            b.path("build/fuzz_main.c")
        else
            null;

        const fuzzers_step = b.step("fuzzers", "Build Expat libFuzzer targets");
        const fuzz_targets = [_][]const u8{ "xml_parse_fuzzer", "xml_parsebuffer_fuzzer" };
        const encoding_types = [_][]const u8{
            "UTF-16",
            "UTF-8",
            "ISO-8859-1",
            "US-ASCII",
            "UTF-16BE",
            "UTF-16LE",
        };

        for (fuzz_targets) |fuzz_target| {
            for (encoding_types) |enc| {
                const fuzzer_name = b.fmt("{s}_{s}", .{ fuzz_target, enc });
                const fuzzer_mod = b.createModule(.{
                    .target = target,
                    .optimize = optimize,
                    .link_libc = true,
                    .fuzz = if (!ossfuzz_build) true else null,
                });
                fuzzer_mod.addIncludePath(lib_inc);
                applyCommonMacros(fuzzer_mod, target.result, shared, large_size, unicode, unicode_wchar_t);
                fuzzer_mod.addCMacro("ENCODING_FOR_FUZZING", enc);
                if (target.result.os.tag == .windows) {
                    fuzzer_mod.addCMacro("XML_STATIC", "1");
                }
                fuzzer_mod.addCSourceFiles(.{
                    .root = expat_root,
                    .files = &.{b.fmt("fuzz/{s}.c", .{fuzz_target})},
                    .flags = c_flags,
                });
                if (fuzz_main_c) |runner_c| {
                    fuzzer_mod.addCSourceFile(.{
                        .file = runner_c,
                        .flags = c_flags,
                    });
                }
                fuzzer_mod.linkLibrary(fuzzpat);
                if (fuzzing_engine) |engine_path| {
                    fuzzer_mod.link_libcpp = true;
                    fuzzer_mod.addObjectFile(.{ .cwd_relative = engine_path });
                }

                const fuzzer_exe = b.addExecutable(.{
                    .name = fuzzer_name,
                    .root_module = fuzzer_mod,
                });
                b.getInstallStep().dependOn(&fuzzer_exe.step);
                fuzzers_step.dependOn(&fuzzer_exe.step);
            }
        }
    }
}

fn addConfiguredTemplate(
    b: *std.Build,
    template: std.Build.LazyPath,
    output_name: []const u8,
    replacement: []const u8,
) std.Build.LazyPath {
    const exe = b.addExecutable(.{
        .name = "expat-configure-file",
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/configure_file.zig"),
            .target = b.graph.host,
        }),
    });
    const run = b.addRunArtifact(exe);
    run.addFileArg(template);
    const out = run.addOutputFileArg(output_name);
    run.addArg(replacement);
    return out;
}

fn needsLibm(t: std.Target) bool {
    return t.os.tag != .windows and t.os.tag != .wasi and !t.os.tag.isDarwin() and t.os.tag != .freestanding;
}

fn detectEntropy(t: std.Target, kind: EntropyKind) bool {
    const os_tag = t.os.tag;
    if (os_tag.isDarwin()) {
        return switch (kind) {
            .arc4random => true,
            .arc4random_buf => if (os_tag == .macos)
                t.os.version_range.semver.min.order(.{ .major = 10, .minor = 7, .patch = 0 }) != .lt
            else
                true,
            .getentropy => if (os_tag == .macos)
                t.os.version_range.semver.min.order(.{ .major = 10, .minor = 12, .patch = 0 }) != .lt
            else
                true,
            .getrandom, .syscall_getrandom => false,
        };
    }
    if (os_tag == .linux) {
        if (t.isGnuLibC()) {
            const glibc = t.os.version_range.linux.glibc;
            return switch (kind) {
                .getrandom, .getentropy => glibc.order(.{ .major = 2, .minor = 25, .patch = 0 }) != .lt,
                .arc4random, .arc4random_buf => glibc.order(.{ .major = 2, .minor = 36, .patch = 0 }) != .lt,
                .syscall_getrandom => true,
            };
        } else if (t.isMuslLibC()) {
            return switch (kind) {
                .getrandom, .getentropy, .syscall_getrandom => true,
                .arc4random, .arc4random_buf => false,
            };
        } else if (t.abi.isAndroid()) {
            return true;
        } else {
            return kind == .syscall_getrandom;
        }
    }
    if (os_tag == .freebsd or os_tag == .netbsd or os_tag == .illumos) {
        return kind != .syscall_getrandom;
    }
    if (os_tag == .openbsd or os_tag == .dragonfly or os_tag == .haiku or os_tag == .wasi) {
        return switch (kind) {
            .arc4random, .arc4random_buf, .getentropy => true,
            .getrandom, .syscall_getrandom => false,
        };
    }
    return false;
}

fn resolveEntropy(
    b: *std.Build,
    t: std.Target,
    opt: ?bool,
    kind: EntropyKind,
    thing_lower: []const u8,
    opt_name: []const u8,
    triple: []const u8,
) ?bool {
    if (t.os.tag == .windows) return false;
    const detected = detectEntropy(t, kind);
    if (opt) |enforced| {
        if (!enforced) return false;
        if (detected) return true;
        failBuild(b, b.fmt("Use of {s} was enforced by -D{s}=true but it is not available on target {s}.", .{
            thing_lower,
            opt_name,
            triple,
        }));
        return null;
    }
    return detected;
}

fn failBuild(b: *std.Build, msg: []const u8) void {
    const fail = b.addFail(msg);
    b.getInstallStep().dependOn(&fail.step);
    const step_names = [_]struct { name: []const u8, desc: []const u8 }{
        .{ .name = "test", .desc = "Run the Expat unit test suite" },
        .{ .name = "zig-test", .desc = "Run Zig integration tests for the expat module" },
        .{ .name = "examples", .desc = "Build and install Expat example programs" },
        .{ .name = "xmlwf", .desc = "Run the xmlwf CLI tool" },
        .{ .name = "gennmtab", .desc = "Run the gennmtab table generator" },
        .{ .name = "benchmark", .desc = "Run the Expat benchmark tool" },
        .{ .name = "fuzzers", .desc = "Build Expat libFuzzer targets" },
        .{ .name = "run-xmltest", .desc = "Download W3C XML conformance suite and run xmlwf against it" },
    };
    for (step_names) |s| {
        if (b.top_level_steps.get(s.name) == null) {
            b.step(s.name, s.desc).dependOn(&fail.step);
        }
    }
}

fn boolDefine(val: bool) ?i64 {
    return if (val) 1 else null;
}

fn buildCFlags(
    b: *std.Build,
    t: std.Target,
    unicode_wchar_t: bool,
    short_wchar: bool,
    warnings_as_errors: bool,
) []const []const u8 {
    var flags: std.ArrayList([]const u8) = .empty;
    flags.append(b.allocator, "-std=c99") catch @panic("OOM");
    flags.append(b.allocator, "-fno-strict-aliasing") catch @panic("OOM");
    flags.append(b.allocator, "-Wimplicit-fallthrough") catch @panic("OOM");
    if (t.os.tag != .windows) {
        flags.append(b.allocator, "-fvisibility=hidden") catch @panic("OOM");
    }
    if (unicode_wchar_t and t.os.tag != .windows and short_wchar) {
        flags.append(b.allocator, "-fshort-wchar") catch @panic("OOM");
    }
    if (warnings_as_errors) {
        flags.append(b.allocator, "-Werror") catch @panic("OOM");
        if (t.os.tag == .windows and t.abi == .gnu) {
            flags.append(b.allocator, "-Wno-format") catch @panic("OOM");
        }
    }
    return flags.items;
}

fn buildExpatCSources(
    b: *std.Build,
    t: std.Target,
    dev_urandom: bool,
    have_arc4random: bool,
    have_arc4random_buf: bool,
    have_getentropy: bool,
    have_getrandom: bool,
    have_syscall_getrandom: bool,
) []const []const u8 {
    var srcs: std.ArrayList([]const u8) = .empty;
    srcs.appendSlice(b.allocator, &.{
        "lib/xcs.c",
        "lib/xmlparse.c",
        "lib/xmlrole.c",
        "lib/xmltok.c",
    }) catch @panic("OOM");
    if (have_arc4random) {
        srcs.append(b.allocator, "lib/random_arc4random.c") catch @panic("OOM");
    }
    if (have_arc4random_buf) {
        srcs.append(b.allocator, "lib/random_arc4random_buf.c") catch @panic("OOM");
    }
    if (t.os.tag != .windows and dev_urandom) {
        srcs.append(b.allocator, "lib/random_dev_urandom.c") catch @panic("OOM");
    }
    if (have_getentropy) {
        srcs.append(b.allocator, "lib/random_getentropy.c") catch @panic("OOM");
    }
    if (have_getrandom or have_syscall_getrandom) {
        srcs.append(b.allocator, "lib/random_getrandom.c") catch @panic("OOM");
    }
    if (t.os.tag == .windows) {
        srcs.append(b.allocator, "lib/random_rand_s.c") catch @panic("OOM");
    }
    return srcs.items;
}

fn applyCommonMacros(
    mod: *std.Build.Module,
    t: std.Target,
    shared: bool,
    large_size: bool,
    unicode: bool,
    unicode_wchar_t: bool,
) void {
    if (large_size) {
        mod.addCMacro("XML_LARGE_SIZE", "1");
    }
    if (unicode) {
        mod.addCMacro("XML_UNICODE", "1");
        if (unicode_wchar_t) {
            mod.addCMacro("XML_UNICODE_WCHAR_T", "1");
        }
    }
    if (t.os.tag != .windows and shared) {
        mod.addCMacro("XML_ENABLE_VISIBILITY", "1");
    }
    if (t.os.tag == .windows and t.abi == .msvc) {
        mod.addCMacro("_CRT_SECURE_NO_WARNINGS", "1");
    }
}
