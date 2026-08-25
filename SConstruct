#!/usr/bin/scons

from os.path import abspath, dirname, expanduser, join, normpath
from SCons.Script import (
    ARGUMENTS,
    BoolVariable,
    Copy,
    Delete,
    EnumVariable,
    Environment,
    Mkdir,
    PathVariable,
    SConscript,
    Touch,
    Variables,
)
import glob
import os
import platform
import shutil
import sys

PROJECT_DIR = Dir("#").abspath
DEFAULT_SDK = normpath(join(PROJECT_DIR, "..", "SDKs", "iPhoneOS8.4.sdk"))
IS_MAC = platform.system() == "Darwin"


def find_ldid():
    for candidate in (
        shutil.which("ldid"),
        join(PROJECT_DIR, "ldid-2.1.5-amd64"),
    ):
        if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


vars = Variables(None, ARGUMENTS)
vars.Add(PathVariable("TOOLING_PATH", "Toolchain bin dir", "/usr/bin", PathVariable.PathIsDir))
vars.Add(PathVariable("SDKROOT", "iOS SDK root", DEFAULT_SDK, PathVariable.PathIsDir))
vars.Add(BoolVariable("debug", "debug build", False))
vars.Add(EnumVariable("device", "install target", "default",
                      allowed_values=["default", "ios5", "ios6", "ios7"]))

env = Environment(Variables=vars)

if not IS_MAC and "TOOLING_PATH" not in vars.args:
    print(vars.GenerateHelpText(env))
    sys.exit(1)

sdkroot = normpath(vars.args.get("SDKROOT", DEFAULT_SDK))
tooling_path = vars.args.get("TOOLING_PATH", "/usr/bin")
arch = "armv7"
min_version = "5.0"

if IS_MAC:
    cc = "xcrun clang"
    cxx = "xcrun clang++"
    ar = "xcrun ar"
    ranlib = "xcrun ranlib"
    strip_cmd = shutil.which("llvm-strip") or shutil.which("strip") or "strip"
    ldid_cmd = find_ldid()
    env_vars = {"PATH": os.environ.get("PATH", "/usr/bin:/bin")}
else:
    cc = "arm-apple-darwin9-clang"
    cxx = "arm-apple-darwin9-clang++"
    ar = "arm-apple-darwin9-ar"
    ranlib = "arm-apple-darwin9-ranlib"
    strip_cmd = "llvm-strip"
    ldid_cmd = join(PROJECT_DIR, "ldid-2.1.5-amd64")
    env_vars = {
        "PATH": tooling_path + ":/usr/bin:/bin",
        "LD_LIBRARY_PATH": os.environ.get("LD_LIBRARY_PATH", ""),
    }

common_cflags = [
    "-isysroot", sdkroot,
    "-arch", arch,
    "-miphoneos-version-min=" + min_version,
    "-fblocks",
    "-fobjc-arc",
    "-Icurl",
    "-Wno-deprecated-declarations",
]

if not IS_MAC:
    common_cflags.extend(["-std=c11", "-Werror"])
else:
    common_cflags.append("-std=c11")

common_cxxflags = [
    "-isysroot", sdkroot,
    "-arch", arch,
    "-miphoneos-version-min=" + min_version,
    "-fblocks",
    "-fobjc-arc",
    "-Icurl",
    "-Wno-deprecated-declarations",
    "-std=c++11",
]
if IS_MAC:
    common_cxxflags.append("-stdlib=libstdc++")
else:
    common_cxxflags.append("-stdlib=libc++")
if not IS_MAC:
    common_cxxflags.append("-Werror")

env = Environment(
    variables=vars,
    AR=ar,
    CC=cc,
    CXX=cxx,
    RANLIB=ranlib,
    CFLAGS=common_cflags,
    CPPFLAGS=[
        "-arch", arch,
        "-isysroot", sdkroot,
        "-miphoneos-version-min=" + min_version,
    ] + ([] if IS_MAC else ["-Werror"]),
    LINKFLAGS=[
        "-arch", arch,
        "-isysroot", sdkroot,
        "-miphoneos-version-min=" + min_version,
        "-F" + join(sdkroot, "System/Library/PrivateFrameworks"),
        "-ObjC",
    ],
    CXXFLAGS=common_cxxflags,
    ENV=env_vars,
)
env["SDKROOT"] = sdkroot
env.Help(vars.GenerateHelpText(env))
env.AppendENVPath("PATH", os.getenv("PATH"))
env.Clean(".", "xcbuild")
env.Clean(".", "Veteris/xcbuild")

print("SCons Veteris: platform=%s SDKROOT=%s CC=%s" % (platform.system(), sdkroot, cc))


def disable_arc(env, srcs, src_file_name):
    try:
        idx = next(i for i, s in enumerate(srcs) if src_file_name in s)
    except StopIteration:
        print("File %s not found in srcs" % src_file_name)
        return
    srcs[idx] = env.SharedObject(srcs[idx], CFLAGS=env["CFLAGS"] + ["-fno-objc-arc"])


env.AddMethod(disable_arc)

debug = ARGUMENTS.get("debug", 0)
if int(debug):
    env.Append(CFLAGS=["-DDEBUG=1", "-g", "-O0"])
    env.Append(CPPFLAGS=["-DDEBUG=1", "-g", "-O0"])
else:
    env.Append(CFLAGS=["-O3", "-g"])
    env.Append(CPPFLAGS=["-O3", "-g"])

download_debug = (not os.environ.get("FINALPACKAGE")) or int(ARGUMENTS.get("download_debug", 0)) or int(debug) or os.environ.get("VETERIS_DOWNLOAD_DEBUG")
if download_debug:
    env.Append(CFLAGS=["-DVETERIS_DOWNLOAD_DEBUG=1"])
    env.Append(CPPFLAGS=["-DVETERIS_DOWNLOAD_DEBUG=1"])

use_ios7 = ARGUMENTS.get("use_ios7", 0)
use_ios6 = ARGUMENTS.get("use_ios6", 1)
use_ios5 = ARGUMENTS.get("use_ios5", 0)

VERSION = "2.1.1"
MARKETING_VERSION = os.environ.get("VETERIS_MARKETING_VERSION", VERSION)
BUILD_VERSION = os.environ.get("VETERIS_BUILD_VERSION", MARKETING_VERSION)
PACKAGE_VERSION = os.environ.get("VETERIS_PACKAGE_VERSION", MARKETING_VERSION)
VERSION_SUBST = {
    "%VERSION%": MARKETING_VERSION,
    "%MARKETING_VERSION%": MARKETING_VERSION,
    "%BUILD_VERSION%": BUILD_VERSION,
}
IOS6_IP = "192.168.10.99"
IOS7_IP = "192.168.1.186"
IOS5_IP = "192.168.1.122"
if int(use_ios6):
    IPHONE_IP = IOS6_IP
elif int(use_ios7):
    IPHONE_IP = IOS7_IP
elif int(use_ios5):
    IPHONE_IP = IOS5_IP
else:
    IPHONE_IP = "192.168.1.189"

Export("env")

kscrash = SConscript("KSCrash/SConscript")
nanopb = SConscript("nanopb/SConscript")
env.Prepend(LIBS=[kscrash, nanopb])
veteris_prog = SConscript("Veteris/SConscript")

if ldid_cmd:
    sign_cmd = "%s -SVeteris/ent.xml $TARGET" % ldid_cmd
else:
    sign_cmd = "cp $SOURCE $TARGET"

signed_prog = env.Command(
    "xcbuild/Veteris.signed",
    veteris_prog,
    [
        Delete("$TARGET"),
        Copy("$TARGET", "$SOURCE"),
        sign_cmd,
    ],
)

if not int(debug):
    env.Command(
        "xcbuild/Veteris.stripped",
        signed_prog,
        [
            Delete("$TARGET"),
            Copy("$TARGET", "$SOURCE"),
            strip_cmd + " -s $TARGET",
        ],
    )

debug_symbols = env.Command(
    "xcbuild/Veteris.dSYM",
    veteris_prog,
    "dsymutil $SOURCE -o $TARGET",
)

resources = [
    "Veteris/IMPORTANT SERVER INFOS",
    "Veteris/Images.xcassets",
    "Veteris/SVProgressHUD/SVProgressHUD.bundle",
]
png_resources = glob.glob("Veteris/Images/*.png")
settings_bundle_files = [
    file
    for file in glob.glob("Veteris/Settings.bundle/**/*", recursive=True)
    if os.path.isfile(file) and file != "Veteris/Settings.bundle/Root.plist"
]
resources_preserve_path = [
    file
    for i in glob.glob("Veteris/*.lproj")
    for file in glob.glob("%s/*.strings" % i)
]

generated_settings = env.Substfile(
    "xcbuild/generated/Root.plist",
    "Veteris/Settings.bundle/Root.plist",
    SUBST_DICT=VERSION_SUBST,
)

generated_info = env.Substfile(
    "xcbuild/generated/Info.plist",
    "Veteris/Veteris-Info.plist",
    SUBST_DICT=VERSION_SUBST,
)

storyboard_precompiled = "Veteris/en.lproj/MainStoryboard.storyboardc"
storyboard_deps = sorted(glob.glob(storyboard_precompiled + "/*"))

bundle_nodes = []
bundle_nodes += env.Install("xcbuild/Veteris.app", resources)
bundle_nodes += env.Install("xcbuild/Veteris.app", png_resources)
bundle_nodes += env.InstallAs("xcbuild/Veteris.app/Veteris", signed_prog)
bundle_nodes += env.InstallAs("xcbuild/Veteris.app/Info.plist", generated_info)
for source_path in settings_bundle_files:
    rel = source_path.replace("Veteris/", "", 1)
    bundle_nodes += env.InstallAs("xcbuild/Veteris.app/%s" % rel, source_path)
storyboard_install = env.Command(
    "xcbuild/Veteris.app/en.lproj/MainStoryboard.storyboardc/.installed",
    storyboard_deps,
    "rm -rf xcbuild/Veteris.app/en.lproj/MainStoryboard.storyboardc "
    "xcbuild/Veteris.app/MainStoryboard.storyboardc && "
    "mkdir -p xcbuild/Veteris.app/en.lproj && "
    "cp -R %s xcbuild/Veteris.app/en.lproj/MainStoryboard.storyboardc && "
    "touch $TARGET" % storyboard_precompiled,
)
env.AlwaysBuild(storyboard_install)
bundle_nodes += storyboard_install
bundle_nodes += env.InstallAs(
    "xcbuild/Veteris.app/Settings.bundle/Root.plist",
    generated_settings,
)

for source_path in resources_preserve_path:
    rel = source_path.replace("Veteris/", "", 1)
    bundle_nodes += env.InstallAs("xcbuild/Veteris.app/%s" % rel, source_path)

if IS_MAC:
    bundle_actions = [
        Delete("xcbuild/Veteris.app/VeterisLauncher"),
        Delete("xcbuild/Veteris.app/VeterisBinary"),
        "chmod 755 xcbuild/Veteris.app/Veteris",
        "find xcbuild/Veteris.app -name '*.plist' -print0 | xargs -0 -I{} plutil -convert binary1 {}",
        "find xcbuild/Veteris.app -name '*.strings' -print0 | xargs -0 -I{} plutil -convert binary1 {}",
        Touch("$TARGET"),
    ]
else:
    bundle_actions = [
        Delete("xcbuild/Veteris.app/VeterisLauncher"),
        Delete("xcbuild/Veteris.app/VeterisBinary"),
        "chmod 755 xcbuild/Veteris.app/Veteris",
        "find xcbuild/Veteris.app -name '*.png' -print0 | xargs -0 -r ios-pngcrush -c",
        "find xcbuild/Veteris.app -name '*.plist' -print0 | xargs -0 -r ios-plutil -c",
        "find xcbuild/Veteris.app -name '*.strings' -print0 | xargs -0 -r ios-plutil -c",
        Touch("$TARGET"),
    ]

bundle_stamp = env.Command(
    "xcbuild/Veteris.app/.bundle_stamp",
    bundle_nodes,
    bundle_actions,
)

app = env.Alias("app", bundle_stamp)

if shutil.which("sshpass"):
    ios_install = env.Alias(
        "ios-install",
        app,
        [
            "sshpass -p alpine ssh -o PreferredAuthentications=password root@%s 'rm -fr /Applications/Veteris.app'" % IPHONE_IP,
            "sshpass -p alpine scp -Or xcbuild/Veteris.app root@%s:/Applications/Veteris.app" % IPHONE_IP,
            "sshpass -p alpine ssh -o PreferredAuthentications=password mobile@%s 'uicache'" % IPHONE_IP,
            "sshpass -p alpine ssh -o PreferredAuthentications=password mobile@%s 'killall -9 Veteris'" % IPHONE_IP,
        ],
    )
    env.AlwaysBuild(ios_install)

if shutil.which("dpkg-deb") and not IS_MAC:
    deb_pkg = env.Command(
        "xcbuild/Veteris-v%s.deb" % PACKAGE_VERSION,
        bundle_stamp,
        [
            Delete("xcbuild/Veteris-deb"),
            Mkdir("xcbuild/Veteris-deb/DEBIAN"),
            Mkdir("xcbuild/Veteris-deb/Applications"),
            "cp -r xcbuild/Veteris.app xcbuild/Veteris-deb/Applications/Veteris.app",
            "cp deb-stuff/control xcbuild/Veteris-deb/DEBIAN/control",
            "echo Version: %s >> xcbuild/Veteris-deb/DEBIAN/control" % PACKAGE_VERSION,
            "dpkg-deb -b -Zgzip --root-owner-group xcbuild/Veteris-deb $TARGET",
        ],
    )
    env.Alias("deb", deb_pkg)

dist_nodes = [signed_prog, app]
if debug:
    dist_nodes.append(debug_symbols)
dist = env.Alias("dist", dist_nodes)

env.Clean(bundle_stamp, "xcbuild")
env.Default(veteris_prog)
