const std = @import("std");
const Translator = @import("translate_c").Translator;

const package_version: std.SemanticVersion = .{ .major = 2, .minor = 10, .patch = 0 };
const package_version_str = "2.10.0";
const package_name = "expat";
const package_tarname = "expat";
const package_string = "expat 2.10.0";
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

const EntropyOption = enum {
    auto,
    on,
    off,
};

const PlatformInfo = struct {
    is_windows: bool,
    is_mingw: bool,
    is_msvc: bool,
    is_darwin: bool,
    is_wasi: bool,
    is_big_endian: bool,
    link_libm: bool,
    pkgconfig_libm: bool,

    have_dlfcn_h: bool,
    have_fcntl_h: bool,
    have_inttypes_h: bool,
    have_memory_h: bool,
    have_stdint_h: bool,
    have_stdlib_h: bool,
    have_strings_h: bool,
    have_string_h: bool,
    have_sys_stat_h: bool,
    have_sys_types_h: bool,
    have_unistd_h: bool,
    stdc_headers: bool,
    have_off_t: bool,
    have_getpagesize: bool,
    have_mmap: bool,

    detect_arc4random: bool,
    detect_arc4random_buf: bool,
    detect_getentropy: bool,
    detect_getrandom: bool,
    detect_syscall_getrandom: bool,
};

const BuildConfig = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    platform: PlatformInfo,
    shared: bool,
    char_type: CharType,
    short_wchar: bool,
    unicode: bool,
    unicode_wchar_t: bool,
    large_size: bool,
    enable_dtd: bool,
    enable_ge: bool,
    enable_ns: bool,
    context_bytes: u32,
    warnings_as_errors: bool,
    symbol_versioning: bool,
    enable_install: bool,
    build_tools: bool,
    build_examples: bool,
    build_tests: bool,
    build_docs: bool,
    build_fuzzers: bool,
    ossfuzz_build: bool,
    build_pkgconfig: bool,
    pkgconfig_prefix: []const u8,
    dev_urandom: bool,
    have_arc4random: bool,
    have_arc4random_buf: bool,
    have_getentropy: bool,
    have_getrandom: bool,
    have_syscall_getrandom: bool,
    postfix: []const u8,
    output_name: []const u8,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const platform = detectPlatform(target.result);

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
    ) orelse !platform.is_msvc;
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
        EntropyOption,
        "with-arc4random",
        "Make use of arc4random function: auto, on, off [default: auto]",
    ) orelse .auto;
    const with_arc4random_buf = b.option(
        EntropyOption,
        "with-arc4random-buf",
        "Make use of arc4random_buf function: auto, on, off [default: auto]",
    ) orelse .auto;
    const with_getentropy = b.option(
        EntropyOption,
        "with-getentropy",
        "Make use of getentropy function: auto, on, off [default: auto]",
    ) orelse .auto;
    const with_getrandom = b.option(
        EntropyOption,
        "with-getrandom",
        "Make use of getrandom function: auto, on, off [default: auto]",
    ) orelse .auto;
    const with_sys_getrandom = b.option(
        EntropyOption,
        "with-sys-getrandom",
        "Make use of syscall SYS_getrandom: auto, on, off [default: auto]",
    ) orelse .auto;

    const build_tools = build_tools_opt orelse
        (char_type == .char or (char_type == .wchar_t and platform.is_windows));
    const build_examples = build_examples_opt orelse (char_type != .ushort);
    const build_tests = build_tests_opt orelse (char_type != .ushort);

    const docbook_to_man: ?[]const u8 = if (build_tools and !platform.is_msvc and build_docs_opt != false)
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
    } else if (char_type == .wchar_t and !platform.is_windows) {
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
        if (platform.is_msvc) {
            return failBuild(b, "Option -Dbuild-docs=true is not supported with MSVC targets.");
        }
        if (docbook_to_man == null) {
            return failBuild(b, "Option -Dbuild-docs=true was requested, but docbook2x-man/db2x_docbook2man/docbook2man/docbook-to-man was not found in PATH.");
        }
    }

    if (symbol_versioning and shared and (platform.is_windows or platform.is_darwin)) {
        return failBuild(b, "Option -Dsymbol-versioning=true uses an ELF linker version script (libexpat.map) and is only supported on ELF shared libraries.");
    }

    const triple_alloc = target.result.zigTriple(b.allocator) catch @panic("OOM");
    const have_arc4random = resolveEntropy(b, platform.is_windows, with_arc4random, platform.detect_arc4random, "function arc4random", "with-arc4random", triple_alloc) orelse return;
    const have_arc4random_buf = resolveEntropy(b, platform.is_windows, with_arc4random_buf, platform.detect_arc4random_buf, "function arc4random_buf", "with-arc4random-buf", triple_alloc) orelse return;
    const have_getentropy = resolveEntropy(b, platform.is_windows, with_getentropy, platform.detect_getentropy, "function getentropy", "with-getentropy", triple_alloc) orelse return;
    const have_getrandom = resolveEntropy(b, platform.is_windows, with_getrandom, platform.detect_getrandom, "function getrandom", "with-getrandom", triple_alloc) orelse return;
    const have_syscall_getrandom = resolveEntropy(b, platform.is_windows, with_sys_getrandom, platform.detect_syscall_getrandom, "syscall SYS_getrandom", "with-sys-getrandom", triple_alloc) orelse return;

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
        if (platform.is_windows and optimize == .debug) "d" else "",
    });
    const postfix = postfix_opt orelse default_postfix;
    const output_name = if (platform.is_windows and !platform.is_mingw) "libexpat" else "expat";

    const cfg: BuildConfig = .{
        .target = target,
        .optimize = optimize,
        .platform = platform,
        .shared = shared,
        .char_type = char_type,
        .short_wchar = short_wchar,
        .unicode = unicode,
        .unicode_wchar_t = unicode_wchar_t,
        .large_size = large_size,
        .enable_dtd = enable_dtd,
        .enable_ge = enable_ge,
        .enable_ns = enable_ns,
        .context_bytes = context_bytes,
        .warnings_as_errors = warnings_as_errors,
        .symbol_versioning = symbol_versioning,
        .enable_install = enable_install,
        .build_tools = build_tools,
        .build_examples = build_examples,
        .build_tests = build_tests,
        .build_docs = build_docs,
        .build_fuzzers = build_fuzzers,
        .ossfuzz_build = ossfuzz_build,
        .build_pkgconfig = build_pkgconfig,
        .pkgconfig_prefix = pkgconfig_prefix,
        .dev_urandom = if (platform.is_windows) false else dev_urandom_opt,
        .have_arc4random = have_arc4random,
        .have_arc4random_buf = have_arc4random_buf,
        .have_getentropy = have_getentropy,
        .have_getrandom = have_getrandom,
        .have_syscall_getrandom = have_syscall_getrandom,
        .postfix = postfix,
        .output_name = output_name,
    };

    const expat_dep = b.dependency("expat", .{});
    const expat_root = expat_dep.path("expat");
    const lib_inc = expat_dep.path("expat/lib");

    // Generate expat_config.h matching ref/CMakeLists.txt + expat_config.h.cmake.
    const config_header = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "expat_config.h",
    }, .{
        .BYTEORDER = @as(i64, if (platform.is_big_endian) 4321 else 1234),
        .HAVE_ARC4RANDOM = boolDefine(cfg.have_arc4random),
        .HAVE_ARC4RANDOM_BUF = boolDefine(cfg.have_arc4random_buf),
        .HAVE_DLFCN_H = boolDefine(platform.have_dlfcn_h),
        .HAVE_FCNTL_H = boolDefine(platform.have_fcntl_h),
        .HAVE_GETPAGESIZE = boolDefine(platform.have_getpagesize),
        .HAVE_GETRANDOM = boolDefine(cfg.have_getrandom),
        .HAVE_GETENTROPY = boolDefine(cfg.have_getentropy),
        .HAVE_INTTYPES_H = boolDefine(platform.have_inttypes_h),
        .HAVE_MEMORY_H = boolDefine(platform.have_memory_h),
        .HAVE_MMAP = boolDefine(platform.have_mmap),
        .HAVE_STDINT_H = boolDefine(platform.have_stdint_h),
        .HAVE_STDLIB_H = boolDefine(platform.have_stdlib_h),
        .HAVE_STRINGS_H = boolDefine(platform.have_strings_h),
        .HAVE_STRING_H = boolDefine(platform.have_string_h),
        .HAVE_SYSCALL_GETRANDOM = boolDefine(cfg.have_syscall_getrandom),
        .HAVE_SYS_STAT_H = boolDefine(platform.have_sys_stat_h),
        .HAVE_SYS_TYPES_H = boolDefine(platform.have_sys_types_h),
        .HAVE_UNISTD_H = boolDefine(platform.have_unistd_h),
        .PACKAGE = package_name,
        .PACKAGE_BUGREPORT = package_bugreport,
        .PACKAGE_NAME = package_name,
        .PACKAGE_STRING = package_string,
        .PACKAGE_TARNAME = package_tarname,
        .PACKAGE_URL = package_url,
        .PACKAGE_VERSION = package_version_str,
        .STDC_HEADERS = boolDefine(platform.stdc_headers),
        .WORDS_BIGENDIAN = boolDefine(platform.is_big_endian),
        .XML_CONTEXT_BYTES = @as(i64, cfg.context_bytes),
        .XML_DEV_URANDOM = boolDefine(!platform.is_windows and cfg.dev_urandom),
        .XML_DTD = boolDefine(cfg.enable_dtd),
        .XML_GE = @as(i64, if (cfg.enable_ge) 1 else 0),
        .XML_NS = boolDefine(cfg.enable_ns),
        .off_t = @as(?enum { long }, if (platform.have_off_t) null else .long),
    });

    // Compiler flags and source file list.
    const c_flags = buildCFlags(b, &cfg);
    const expat_c_sources = buildExpatCSources(b, &cfg);

    // Exported Zig configuration module (port of ref/expat-config.cmake.in).
    const config_opts = b.addOptions();
    config_opts.addOption([]const u8, "version", package_version_str);
    config_opts.addOption(bool, "attr_info", false);
    config_opts.addOption(bool, "min_size", false);
    config_opts.addOption(bool, "dtd", cfg.enable_dtd);
    config_opts.addOption(bool, "ge", cfg.enable_ge);
    config_opts.addOption(bool, "ns", cfg.enable_ns);
    config_opts.addOption(bool, "large_size", cfg.large_size);
    config_opts.addOption(u32, "context_bytes", cfg.context_bytes);
    config_opts.addOption(CharType, "char_type", cfg.char_type);
    config_opts.addOption(bool, "shared", cfg.shared);
    _ = b.addModule("config", .{
        .root_source_file = config_opts.getOutput(),
    });

    // Main C library target: expat.
    const lib_name = b.fmt("{s}{s}", .{ cfg.output_name, cfg.postfix });
    const lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_mod.addConfigHeader(config_header);
    lib_mod.addIncludePath(lib_inc);
    applyCommonMacros(lib_mod, &cfg);
    if (platform.is_windows and !cfg.shared) {
        lib_mod.addCMacro("XML_STATIC", "1");
    }
    lib_mod.addCSourceFiles(.{
        .root = expat_root,
        .files = expat_c_sources,
        .flags = c_flags,
    });
    if (platform.link_libm) {
        lib_mod.linkSystemLibrary("m", .{});
    }

    const dtd_or_ge = cfg.enable_dtd or cfg.enable_ge;
    var win32_def_file: ?std.Build.LazyPath = null;
    if (platform.is_windows and cfg.shared) {
        const version_rc = b.addWriteFiles().add(
            "win32/version.rc",
            renderVersionRc(b),
        );
        const dll_ver = b.fmt("-DVER_FILEVERSION={d},{d},{d},0", .{
            package_version.major,
            package_version.minor,
            package_version.patch,
        });
        lib_mod.addWin32ResourceFile(.{
            .file = version_rc,
            .flags = &.{dll_ver},
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
        .linkage = if (cfg.shared) .dynamic else .static,
        .version = if (cfg.shared and !platform.is_windows)
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

    if (!platform.is_windows and cfg.shared and cfg.symbol_versioning) {
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

    if (cfg.enable_install) {
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
    if (cfg.large_size) {
        expat_translator.defineCMacro("XML_LARGE_SIZE", "1");
    }
    if (cfg.unicode) {
        expat_translator.defineCMacro("XML_UNICODE", "1");
        if (cfg.unicode_wchar_t) {
            expat_translator.defineCMacro("XML_UNICODE_WCHAR_T", "1");
        }
    }
    if (cfg.enable_dtd) {
        expat_translator.defineCMacro("XML_DTD", "1");
    }
    expat_translator.defineCMacro("XML_GE", if (cfg.enable_ge) "1" else "0");
    if (platform.is_windows and !cfg.shared) {
        expat_translator.defineCMacro("XML_STATIC", "1");
    }
    b.modules.put(b.allocator, b.dupe("expat"), expat_translator.mod) catch @panic("OOM");

    const zig_test_wf = b.addWriteFiles();
    const zig_test_src = zig_test_wf.add("expat_zig_test.zig", zig_expat_test_zig);
    const zig_test_mod = b.createModule(.{
        .root_source_file = zig_test_src,
        .target = target,
        .optimize = optimize,
    });
    zig_test_mod.addImport("expat", expat_translator.mod);
    if (cfg.shared and !platform.is_windows) {
        if (platform.is_darwin) {
            zig_test_mod.addRPathSpecial("@loader_path/../lib");
        } else if (!platform.is_wasi) {
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
    if (cfg.build_pkgconfig) {
        const pc_content = b.fmt(
            \\prefix={s}
            \\exec_prefix=${{prefix}}
            \\libdir=${{exec_prefix}}/lib
            \\includedir=${{prefix}}/include
            \\
            \\Name: expat{s}
            \\Version: {s}
            \\Description: expat XML parser
            \\URL: https://libexpat.github.io/
            \\Libs: -L${{libdir}} -l{s}
            \\Libs.private: {s}
            \\Cflags: -I${{includedir}}
            \\Cflags.private: -DXML_STATIC
            \\
        , .{
            cfg.pkgconfig_prefix,
            cfg.postfix,
            package_version_str,
            lib_name,
            if (platform.pkgconfig_libm) "-lm" else "",
        });
        const pc_file = b.addWriteFiles().add("expat.pc", pc_content);
        if (cfg.enable_install) {
            b.getInstallStep().dependOn(&b.addInstallLibFile(pc_file, "pkgconfig/expat.pc").step);
        }
    }

    // Documentation files (AUTHORS, changelog, optional xmlwf.1 man page).
    if (cfg.enable_install) {
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
    if (cfg.build_tools) {
        const xmlwf_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        xmlwf_mod.addConfigHeader(config_header);
        xmlwf_mod.addIncludePath(lib_inc);
        xmlwf_mod.addIncludePath(expat_dep.path("expat/xmlwf"));
        applyCommonMacros(xmlwf_mod, &cfg);
        if (platform.is_windows and !cfg.shared) {
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
        if (platform.link_libm) {
            xmlwf_mod.linkSystemLibrary("m", .{});
        }
        if (cfg.shared and !platform.is_windows) {
            if (platform.is_darwin) {
                xmlwf_mod.addRPathSpecial("@loader_path/../lib");
            } else if (!platform.is_wasi) {
                xmlwf_mod.addRPathSpecial("$ORIGIN/../lib");
            }
        }

        const xmlwf = b.addExecutable(.{
            .name = "xmlwf",
            .root_module = xmlwf_mod,
        });
        if (platform.is_mingw and cfg.unicode_wchar_t) {
            xmlwf.mingw_unicode_entry_point = true;
        }
        xmlwf_exe = xmlwf;

        if (cfg.enable_install) {
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
        applyCommonMacros(gennmtab_mod, &cfg);
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

        if (cfg.build_docs) {
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
                if (cfg.enable_install) {
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
    if (cfg.build_examples) {
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
            applyCommonMacros(ex_mod, &cfg);
            if (platform.is_windows and !cfg.shared) {
                ex_mod.addCMacro("XML_STATIC", "1");
            }
            ex_mod.addCSourceFiles(.{
                .root = expat_root,
                .files = &.{b.fmt("examples/{s}.c", .{name})},
                .flags = c_flags,
            });
            ex_mod.linkLibrary(lib);
            if (cfg.shared and !platform.is_windows) {
                if (platform.is_darwin) {
                    ex_mod.addRPathSpecial("@loader_path/../lib");
                } else if (!platform.is_wasi) {
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
    if (cfg.build_tests) {
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
        applyCommonMacros(runtests_mod, &cfg);
        runtests_mod.addCMacro("XML_TESTING", "1");
        if (platform.is_windows) {
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
        if (platform.link_libm) {
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
        applyCommonMacros(bench_mod, &cfg);
        if (platform.is_windows and !cfg.shared) {
            bench_mod.addCMacro("XML_STATIC", "1");
        }
        bench_mod.addCSourceFiles(.{
            .root = expat_root,
            .files = &.{"tests/benchmark/benchmark.c"},
            .flags = c_flags,
        });
        bench_mod.linkLibrary(lib);
        if (cfg.shared and !platform.is_windows) {
            if (platform.is_darwin) {
                bench_mod.addRPathSpecial("@loader_path/../lib");
            } else if (!platform.is_wasi) {
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
    if (cfg.build_tools and !platform.is_msvc) {
        if (xmlwf_exe) |xmlwf| {
            const xmltest_cmd = b.addSystemCommand(&.{
                "sh",
                "-c",
                \\set -eu
                \\WORK="$1"
                \\SRC="$2"
                \\XMLWF="$3"
                \\mkdir -p "$WORK/tests"
                \\if [ ! -f "$WORK/tests/xmlts.zip" ]; then
                \\  if command -v curl >/dev/null 2>&1; then
                \\    curl -fsSL -o "$WORK/tests/xmlts.zip" https://www.w3.org/XML/Test/xmlts20080827.zip
                \\  else
                \\    wget -O "$WORK/tests/xmlts.zip" https://www.w3.org/XML/Test/xmlts20080827.zip
                \\  fi
                \\fi
                \\if [ ! -d "$WORK/tests/xmlconf" ]; then
                \\  (cd "$WORK/tests" && unzip -q xmlts.zip)
                \\fi
                \\(cd "$WORK" && bash "$SRC/tests/xmltest.sh" "$XMLWF" > "$WORK/tests/xmltest.log" 2>&1 || true)
                \\cp "$WORK/tests/xmltest.log" "$WORK/tests/xmltest.log.raw"
                \\bash "$SRC/fix-xmltest-log.sh" "$WORK/tests/xmltest.log"
                \\diff -u "$SRC/tests/xmltest.log.expected" "$WORK/tests/xmltest.log"
                ,
                "_",
                ".zig-cache/xmltest",
            });
            xmltest_cmd.addDirectoryArg(expat_root);
            xmltest_cmd.addArtifactArg(xmlwf);
            const xmltest_step = b.step("run-xmltest", "Download W3C XML conformance suite and run xmlwf against it");
            xmltest_step.dependOn(&xmltest_cmd.step);
        }
    }

    // Fuzzers (fuzzpat + libFuzzer targets; xml_lpm_fuzzer requires external protobuf/LPM).
    if (cfg.build_fuzzers) {
        const fuzzpat_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .fuzz = if (!cfg.ossfuzz_build) true else null,
        });
        fuzzpat_mod.addConfigHeader(config_header);
        fuzzpat_mod.addIncludePath(lib_inc);
        applyCommonMacros(fuzzpat_mod, &cfg);
        if (platform.is_windows) {
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
            b.addWriteFiles().add("fuzz_main.c", fuzz_corpus_runner_c)
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
                    .fuzz = if (!cfg.ossfuzz_build) true else null,
                });
                fuzzer_mod.addIncludePath(lib_inc);
                applyCommonMacros(fuzzer_mod, &cfg);
                fuzzer_mod.addCMacro("ENCODING_FOR_FUZZING", enc);
                if (platform.is_windows) {
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

    // Configuration summary step (port of ref/CMakeLists.txt lines 1022-1100).
    const summary_text = formatSummary(b, &cfg, triple_alloc);
    const summary_wf = b.addWriteFiles();
    _ = summary_wf.add("summary.txt", summary_text);
    const summary_src = summary_wf.add("summary.zig", summary_helper_zig);
    const summary_exe = b.addExecutable(.{
        .name = "expat-summary",
        .root_module = b.createModule(.{
            .root_source_file = summary_src,
            .target = b.graph.host,
        }),
    });
    const run_summary = b.addRunArtifact(summary_exe);
    const summary_step = b.step("summary", "Print the Expat build configuration summary");
    summary_step.dependOn(&run_summary.step);
}

fn addConfiguredTemplate(
    b: *std.Build,
    template: std.Build.LazyPath,
    output_name: []const u8,
    replacement: []const u8,
) std.Build.LazyPath {
    const wf = b.addWriteFiles();
    const src = wf.add("configure_file.zig", configure_file_helper_zig);
    const exe = b.addExecutable(.{
        .name = "expat-configure-file",
        .root_module = b.createModule(.{
            .root_source_file = src,
            .target = b.graph.host,
        }),
    });
    const run = b.addRunArtifact(exe);
    run.addFileArg(template);
    const out = run.addOutputFileArg(output_name);
    run.addArg(replacement);
    return out;
}

fn detectPlatform(t: std.Target) PlatformInfo {
    const os_tag = t.os.tag;
    const is_windows = os_tag == .windows;
    const is_mingw = is_windows and t.abi == .gnu;
    const is_msvc = is_windows and t.abi == .msvc;
    const is_darwin = os_tag.isDarwin();
    const is_wasi = os_tag == .wasi;
    const is_big_endian = t.cpu.arch.endian() == .big;

    var detect_arc4random = false;
    var detect_arc4random_buf = false;
    var detect_getentropy = false;
    var detect_getrandom = false;
    var detect_syscall_getrandom = false;

    if (is_darwin) {
        detect_arc4random = true;
        if (os_tag == .macos) {
            const min_ver = t.os.version_range.semver.min;
            detect_arc4random_buf = min_ver.order(.{ .major = 10, .minor = 7, .patch = 0 }) != .lt;
            detect_getentropy = min_ver.order(.{ .major = 10, .minor = 12, .patch = 0 }) != .lt;
        } else {
            detect_arc4random_buf = true;
            detect_getentropy = true;
        }
    } else if (os_tag == .linux) {
        if (t.isGnuLibC()) {
            const glibc = t.os.version_range.linux.glibc;
            detect_getrandom = glibc.order(.{ .major = 2, .minor = 25, .patch = 0 }) != .lt;
            detect_getentropy = glibc.order(.{ .major = 2, .minor = 25, .patch = 0 }) != .lt;
            detect_arc4random = glibc.order(.{ .major = 2, .minor = 36, .patch = 0 }) != .lt;
            detect_arc4random_buf = glibc.order(.{ .major = 2, .minor = 36, .patch = 0 }) != .lt;
            detect_syscall_getrandom = true;
        } else if (t.isMuslLibC()) {
            detect_getrandom = true;
            detect_getentropy = true;
            detect_syscall_getrandom = true;
        } else if (t.abi.isAndroid()) {
            detect_arc4random = true;
            detect_arc4random_buf = true;
            detect_getrandom = true;
            detect_getentropy = true;
            detect_syscall_getrandom = true;
        } else {
            detect_syscall_getrandom = true;
        }
    } else if (os_tag == .freebsd or os_tag == .netbsd or os_tag == .illumos) {
        detect_arc4random = true;
        detect_arc4random_buf = true;
        detect_getentropy = true;
        detect_getrandom = true;
    } else if (os_tag == .openbsd or os_tag == .dragonfly or os_tag == .haiku or is_wasi) {
        detect_arc4random = true;
        detect_arc4random_buf = true;
        detect_getentropy = true;
    }

    return .{
        .is_windows = is_windows,
        .is_mingw = is_mingw,
        .is_msvc = is_msvc,
        .is_darwin = is_darwin,
        .is_wasi = is_wasi,
        .is_big_endian = is_big_endian,
        .link_libm = !is_windows and !is_wasi and !is_darwin and os_tag != .freestanding,
        .pkgconfig_libm = !is_windows and !is_wasi and os_tag != .freestanding,
        .have_dlfcn_h = !is_windows and !is_wasi,
        .have_fcntl_h = true,
        .have_inttypes_h = true,
        .have_memory_h = true,
        .have_stdint_h = true,
        .have_stdlib_h = true,
        .have_strings_h = !is_msvc,
        .have_string_h = true,
        .have_sys_stat_h = true,
        .have_sys_types_h = true,
        .have_unistd_h = !is_msvc,
        .stdc_headers = true,
        .have_off_t = true,
        .have_getpagesize = !is_windows and !is_wasi,
        .have_mmap = !is_windows and !is_wasi,
        .detect_arc4random = detect_arc4random,
        .detect_arc4random_buf = detect_arc4random_buf,
        .detect_getentropy = detect_getentropy,
        .detect_getrandom = detect_getrandom,
        .detect_syscall_getrandom = detect_syscall_getrandom,
    };
}

fn resolveEntropy(
    b: *std.Build,
    is_windows: bool,
    opt: EntropyOption,
    detected: bool,
    thing_lower: []const u8,
    opt_name: []const u8,
    triple: []const u8,
) ?bool {
    if (is_windows) return false;
    return switch (opt) {
        .auto => detected,
        .on => if (detected) true else {
            failBuild(b, b.fmt("Use of {s} was enforced by -D{s}=on but it is not available on target {s}.", .{
                thing_lower,
                opt_name,
                triple,
            }));
            return null;
        },
        .off => false,
    };
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
        .{ .name = "summary", .desc = "Print the Expat build configuration summary" },
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

fn buildCFlags(b: *std.Build, cfg: *const BuildConfig) []const []const u8 {
    var flags: std.ArrayList([]const u8) = .empty;
    flags.append(b.allocator, "-std=c99") catch @panic("OOM");
    flags.append(b.allocator, "-fno-strict-aliasing") catch @panic("OOM");
    flags.append(b.allocator, "-Wimplicit-fallthrough") catch @panic("OOM");
    if (!cfg.platform.is_windows) {
        flags.append(b.allocator, "-fvisibility=hidden") catch @panic("OOM");
    }
    if (cfg.unicode_wchar_t and !cfg.platform.is_windows and cfg.short_wchar) {
        flags.append(b.allocator, "-fshort-wchar") catch @panic("OOM");
    }
    if (cfg.warnings_as_errors) {
        flags.append(b.allocator, "-Werror") catch @panic("OOM");
        if (cfg.platform.is_mingw) {
            flags.append(b.allocator, "-Wno-format") catch @panic("OOM");
        }
    }
    return flags.items;
}

fn buildExpatCSources(b: *std.Build, cfg: *const BuildConfig) []const []const u8 {
    var srcs: std.ArrayList([]const u8) = .empty;
    srcs.appendSlice(b.allocator, &.{
        "lib/xcs.c",
        "lib/xmlparse.c",
        "lib/xmlrole.c",
        "lib/xmltok.c",
    }) catch @panic("OOM");
    if (cfg.have_arc4random) {
        srcs.append(b.allocator, "lib/random_arc4random.c") catch @panic("OOM");
    }
    if (cfg.have_arc4random_buf) {
        srcs.append(b.allocator, "lib/random_arc4random_buf.c") catch @panic("OOM");
    }
    if (!cfg.platform.is_windows and cfg.dev_urandom) {
        srcs.append(b.allocator, "lib/random_dev_urandom.c") catch @panic("OOM");
    }
    if (cfg.have_getentropy) {
        srcs.append(b.allocator, "lib/random_getentropy.c") catch @panic("OOM");
    }
    if (cfg.have_getrandom or cfg.have_syscall_getrandom) {
        srcs.append(b.allocator, "lib/random_getrandom.c") catch @panic("OOM");
    }
    if (cfg.platform.is_windows) {
        srcs.append(b.allocator, "lib/random_rand_s.c") catch @panic("OOM");
    }
    return srcs.items;
}

fn applyCommonMacros(mod: *std.Build.Module, cfg: *const BuildConfig) void {
    if (cfg.large_size) {
        mod.addCMacro("XML_LARGE_SIZE", "1");
    }
    if (cfg.unicode) {
        mod.addCMacro("XML_UNICODE", "1");
        if (cfg.unicode_wchar_t) {
            mod.addCMacro("XML_UNICODE_WCHAR_T", "1");
        }
    }
    if (!cfg.platform.is_windows and cfg.shared) {
        mod.addCMacro("XML_ENABLE_VISIBILITY", "1");
    }
    if (cfg.platform.is_msvc) {
        mod.addCMacro("_CRT_SECURE_NO_WARNINGS", "1");
    }
}

fn renderVersionRc(b: *std.Build) []const u8 {
    return b.fmt(
        \\1 VERSIONINFO
        \\FILEVERSION VER_FILEVERSION
        \\PRODUCTVERSION VER_FILEVERSION
        \\BEGIN
        \\  BLOCK "StringFileInfo"
        \\  BEGIN
        \\    BLOCK "040904E4"
        \\    BEGIN
        \\      VALUE "FileVersion", "{s}.0"
        \\      VALUE "ProductVersion", "{s}.0"
        \\    END
        \\  END
        \\  BLOCK "VarFileInfo"
        \\  BEGIN
        \\    VALUE "Translation", 0x0409, 1252
        \\  END
        \\END
        \\
    , .{ package_version_str, package_version_str });
}

fn formatSummary(b: *std.Build, cfg: *const BuildConfig, triple: []const u8) []const u8 {
    const char_summary = switch (cfg.char_type) {
        .char => "char (UTF-8)",
        .ushort => "ushort (unsigned short, UTF-16)",
        .wchar_t => if (cfg.platform.is_windows) "wchar_t (UTF-16)" else "wchar_t (UTF-32)",
    };
    const entropy_block = if (cfg.platform.is_windows)
        b.fmt("    rand_s ................... ON\n", .{})
    else
        b.fmt(
            \\    arc4random ............... {s}
            \\    arc4random_buf ........... {s}
            \\    getentropy ............... {s}
            \\    getrandom ................ {s}
            \\    syscall SYS_getrandom .... {s}
            \\    /dev/urandom ............. {s}
            \\
        , .{
            onOff(cfg.have_arc4random),
            onOff(cfg.have_arc4random_buf),
            onOff(cfg.have_getentropy),
            onOff(cfg.have_getrandom),
            onOff(cfg.have_syscall_getrandom),
            onOff(cfg.dev_urandom),
        });

    return b.fmt(
        \\===========================================================================
        \\
        \\Expat version ................ {s}
        \\
        \\Configuration
        \\  Target ..................... {s}
        \\  Optimize ................... {s}
        \\  Prefix (pkgconfig) ......... {s}
        \\  Shared libraries ........... {s}
        \\  Character type ............. {s}
        \\  Library name postfix ....... {s}
        \\
        \\  Build documentation ........ {s}
        \\  Build examples ............. {s}
        \\  Build fuzzers .............. {s}
        \\  Build tests ................ {s}
        \\  Build tools (xmlwf) ........ {s}
        \\  Build pkg-config file ...... {s}
        \\  Install files .............. {s}
        \\  Symbol versioning .......... {s}
        \\
        \\  Features
        \\    Context bytes ............ {d}
        \\    DTD support .............. {s}
        \\    General entities ......... {s}
        \\    Large size ............... {s}
        \\    Namespace support ........ {s}
        \\
        \\  Entropy sources
        \\{s}
        \\===========================================================================
        \\
    , .{
        package_version_str,
        triple,
        @tagName(cfg.optimize),
        cfg.pkgconfig_prefix,
        onOff(cfg.shared),
        char_summary,
        if (cfg.postfix.len > 0) cfg.postfix else "(none)",
        onOff(cfg.build_docs),
        onOff(cfg.build_examples),
        onOff(cfg.build_fuzzers),
        onOff(cfg.build_tests),
        onOff(cfg.build_tools),
        onOff(cfg.build_pkgconfig),
        onOff(cfg.enable_install),
        onOff(cfg.symbol_versioning),
        cfg.context_bytes,
        onOff(cfg.enable_dtd),
        onOff(cfg.enable_ge),
        onOff(cfg.large_size),
        onOff(cfg.enable_ns),
        entropy_block,
    });
}

fn onOff(val: bool) []const u8 {
    return if (val) "ON" else "OFF";
}

const zig_expat_test_zig =
    \\const std = @import("std");
    \\const expat = @import("expat");
    \\
    \\const State = struct {
    \\    seen_root: bool = false,
    \\};
    \\
    \\fn startElement(user_data: ?*anyopaque, name: [*c]const expat.XML_Char, atts: [*c]const [*c]const expat.XML_Char) callconv(.c) void {
    \\    _ = name;
    \\    _ = atts;
    \\    const state: *State = @ptrCast(@alignCast(user_data.?));
    \\    state.seen_root = true;
    \\}
    \\
    \\test "expat parse from Zig" {
    \\    const ver = expat.XML_ExpatVersionInfo();
    \\    try std.testing.expectEqual(@as(c_int, 2), ver.major);
    \\    try std.testing.expectEqual(@as(c_int, 10), ver.minor);
    \\    try std.testing.expectEqual(@as(c_int, 0), ver.micro);
    \\
    \\    const parser = expat.XML_ParserCreate(null) orelse return error.OutOfMemory;
    \\    defer expat.XML_ParserFree(parser);
    \\
    \\    var state: State = .{};
    \\    expat.XML_SetUserData(parser, &state);
    \\    expat.XML_SetElementHandler(parser, startElement, null);
    \\
    \\    const xml = "<root><child/></root>";
    \\    const status = expat.XML_Parse(parser, xml.ptr, @intCast(xml.len), 1);
    \\    try std.testing.expectEqual(@as(c_uint, expat.XML_STATUS_OK), status);
    \\    try std.testing.expect(state.seen_root);
    \\}
    \\
;

const configure_file_helper_zig =
    \\const std = @import("std");
    \\
    \\pub fn main(init: std.process.Init) !void {
    \\    const arena = init.arena.allocator();
    \\    const args = try init.minimal.args.toSlice(arena);
    \\    if (args.len != 4) return error.InvalidArgs;
    \\    const input_path = args[1];
    \\    const output_path = args[2];
    \\    const replacement = args[3];
    \\
    \\    const contents = if (std.fs.path.isAbsolute(input_path)) blk: {
    \\        var file = try std.Io.Dir.openFileAbsolute(init.io, input_path, .{});
    \\        defer file.close(init.io);
    \\        var buf: [4096]u8 = undefined;
    \\        var reader = file.reader(init.io, &buf);
    \\        break :blk try reader.interface.allocRemaining(arena, .limited(1024 * 1024));
    \\    } else try std.Io.Dir.cwd().readFileAlloc(
    \\        init.io,
    \\        input_path,
    \\        arena,
    \\        .limited(1024 * 1024),
    \\    );
    \\
    \\    const replaced = try std.mem.replaceOwned(
    \\        u8,
    \\        arena,
    \\        contents,
    \\        "@_EXPAT_COMMENT_DTD_OR_GE@",
    \\        replacement,
    \\    );
    \\
    \\    if (std.fs.path.isAbsolute(output_path)) {
    \\        var file = try std.Io.Dir.createFileAbsolute(init.io, output_path, .{});
    \\        defer file.close(init.io);
    \\        try file.writeStreamingAll(init.io, replaced);
    \\    } else {
    \\        try std.Io.Dir.cwd().writeFile(init.io, .{
    \\            .sub_path = output_path,
    \\            .data = replaced,
    \\        });
    \\    }
    \\}
    \\
;

const summary_helper_zig =
    \\const std = @import("std");
    \\const summary_text = @embedFile("summary.txt");
    \\
    \\pub fn main(init: std.process.Init) !void {
    \\    var buf: [4096]u8 = undefined;
    \\    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &buf);
    \\    try stdout_writer.interface.writeAll(summary_text);
    \\    try stdout_writer.interface.flush();
    \\}
    \\
;

const fuzz_corpus_runner_c =
    \\#include <stdint.h>
    \\#include <stdio.h>
    \\#include <stdlib.h>
    \\
    \\int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);
    \\
    \\int main(int argc, char **argv) {
    \\  if (argc <= 1) {
    \\    const uint8_t empty = 0;
    \\    LLVMFuzzerTestOneInput(&empty, 0);
    \\    return 0;
    \\  }
    \\  for (int i = 1; i < argc; ++i) {
    \\    FILE *f = fopen(argv[i], "rb");
    \\    if (!f) {
    \\      perror(argv[i]);
    \\      return 1;
    \\    }
    \\    if (fseek(f, 0, SEEK_END) != 0) {
    \\      fclose(f);
    \\      return 1;
    \\    }
    \\    long len = ftell(f);
    \\    if (len < 0) {
    \\      fclose(f);
    \\      return 1;
    \\    }
    \\    rewind(f);
    \\    uint8_t *buf = len > 0 ? malloc((size_t)len) : NULL;
    \\    if (len > 0 && !buf) {
    \\      fclose(f);
    \\      return 1;
    \\    }
    \\    size_t n = len > 0 ? fread(buf, 1, (size_t)len, f) : 0;
    \\    fclose(f);
    \\    LLVMFuzzerTestOneInput(buf ? buf : (const uint8_t *)"", n);
    \\    free(buf);
    \\  }
    \\  return 0;
    \\}
    \\
;
