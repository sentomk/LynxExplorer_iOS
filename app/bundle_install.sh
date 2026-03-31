# Copyright 2024 The Lynx Authors. All rights reserved.
# Licensed under the Apache License Version 2.0 that can be found in the
# LICENSE file in the root directory of this source tree.
set -e

script_dir=$(cd "$(dirname "$0")" && pwd -P)
repo_root=$(cd "$script_dir/.." && pwd -P)
lynx_root="${LYNX_ROOT:-$repo_root/lynx}"
homepage_dir="$repo_root/homepage"
resource_dir="$script_dir/LynxExplorer/Resource"
gemfile_path="$lynx_root/Gemfile"

echo "repo_root: $repo_root"
echo "lynx_root: $lynx_root"
command="pod install --verbose --repo-update"
project_name="LynxExplorer.xcodeproj"
enable_trace=true

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo " -h, --help         Show this help message"
    echo " --skip-homepage-build  Skip homepage bundle build"
    echo " --disable-trace    Disable trace"
    echo
    echo "Environment variables:"
    echo " LYNX_ROOT          Path to a local lynx checkout"
}

require_path() {
    local path="$1"
    local message="$2"
    if [[ ! -e "$path" ]]; then
        echo "$message"
        exit 1
    fi
}

build_homepage_resources() {
    mkdir -p "$resource_dir"
    pushd "$homepage_dir"
    pnpm install --no-frozen-lockfile
    pnpm run build
    cp "$homepage_dir/dist/main.lynx.bundle" "$resource_dir/homepage.lynx.bundle"
    popd
}

handle_options() {
    for i in "$@"; do
        case $i in
            -h | --help)
                usage
                exit 0
                ;;
            --skip-homepage-build)
                SKIP_HOMEPAGE_BUILD=true
                ;;
            --disable-trace)
                enable_trace=false
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done
}

SKIP_HOMEPAGE_BUILD=false

enable_trace_param=$([ $enable_trace == true ] && echo "--enable-trace" || echo "")

handle_options "$@"
require_path "$lynx_root/tools/ios_tools/generate_podspec_scripts_by_gn.py" \
    "Missing lynx checkout. Clone lynx into $repo_root/lynx or set LYNX_ROOT."
require_path "$gemfile_path" \
    "Missing Gemfile in lynx checkout at $gemfile_path."
require_path "$homepage_dir/package.json" \
    "Missing homepage sources at $homepage_dir."

if [[ "$SKIP_HOMEPAGE_BUILD" == "false" ]]; then
    build_homepage_resources
fi

pushd "$lynx_root"
gn_root_dir=$(cd "$lynx_root" && pwd -P)
echo "gn_root_dir: $gn_root_dir"
generate_ios_podspec_cmd="python3 tools/ios_tools/generate_podspec_scripts_by_gn.py --root $gn_root_dir $enable_trace_param"
echo $generate_ios_podspec_cmd
eval "$generate_ios_podspec_cmd"
popd

# prepare source cache
export COCOAPODS_CONVERT_GIT_TO_HTTP=false
export LANG=en_US.UTF-8
export BUNDLE_GEMFILE="$gemfile_path"
pushd "$script_dir"
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk bundle install -V --path="$repo_root/.bundle"
bundle exec pod deintegrate "$project_name"
rm -rf Podfile.lock
if [[ -n "${source_cache_dir:-}" ]]; then
    COCOAPODS_LOCAL_SOURCE_REPO="$source_cache_dir/.git" bundle exec "$command"
else
    bundle exec "$command"
fi
popd
