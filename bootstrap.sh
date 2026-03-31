#!/usr/bin/env bash
set -euo pipefail

required_lynx_commit="faeec5c7b8e21be2c906d4a9b32d80df596deeb3"
minimum_python_version="3.9"
minimum_ruby_version="2.7"

script_dir=$(cd "$(dirname "$0")" && pwd -P)
default_lynx_root=$(cd "$script_dir/.." && pwd -P)/lynx

action_hint() {
  printf '  %s\n' "$1"
}

info() {
  printf '[INFO] %s\n' "$1"
}

success() {
  printf '[OK] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1" >&2
}

fail() {
  printf '[ERROR] %s\n' "$1" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  local install_hint="$2"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "$command_name is required. $install_hint"
  fi
}

check_git() {
  require_command git "Install Git before building LynxExplorer_iOS."
  success "Git version: $(git --version | sed 's/^git version //')"
}

check_xcode() {
  require_command xcode-select "Install Xcode 15.0 or later and enable Command Line Tools."
  require_command xcodebuild "Install Xcode 15.0 or later and enable Command Line Tools."

  local developer_dir
  developer_dir=$(xcode-select -p 2>/dev/null || true)
  [ -n "$developer_dir" ] || fail "Xcode Command Line Tools are not configured. Open Xcode > Settings > Locations and select a Command Line Tools version."
  success "Xcode Command Line Tools: $developer_dir"

  local xcode_version_output
  local xcode_version
  xcode_version_output=$(xcodebuild -version 2>/dev/null || true)
  xcode_version=$(printf '%s\n' "$xcode_version_output" | awk '/^Xcode / {print $2; exit}')
  [ -n "$xcode_version" ] || fail "Unable to detect the installed Xcode version."

  if ! awk -v current="$xcode_version" 'BEGIN { split(current, parts, "."); exit !((parts[1] + 0) >= 15) }'; then
    fail "Xcode $xcode_version detected. Xcode 15.0 or later is required."
  fi
  success "Xcode version: $xcode_version"
}

check_python() {
  require_command python3 "Install Python 3.9 or later."

  local python_version
  python_version=$(python3 -c 'import sys; print("{}.{}".format(sys.version_info[0], sys.version_info[1]))')
  if ! python3 - <<'PY'
import sys
sys.exit(0 if sys.version_info >= (3, 9) else 1)
PY
  then
    fail "Python $python_version detected. Python $minimum_python_version or later is required."
  fi
  success "Python version: $python_version"

  if ! python3 - <<'PY'
import importlib.util
import sys
sys.exit(0 if importlib.util.find_spec("yaml") else 1)
PY
  then
    fail "PyYAML is missing for python3. Install it with 'python3 -m pip install pyyaml' or in a virtual environment before continuing."
  fi
  success "PyYAML is available"
}

check_ruby() {
  require_command ruby "Install Ruby 2.7 up to, but not including, 3.4."
  require_command bundle "Install Bundler for the active Ruby environment."

  local ruby_version
  ruby_version=$(ruby -e 'print RUBY_VERSION')
  if ! ruby - <<'RUBY'
version = Gem::Version.new(RUBY_VERSION)
minimum = Gem::Version.new('2.7.0')
maximum = Gem::Version.new('3.4.0')
exit(version >= minimum && version < maximum ? 0 : 1)
RUBY
  then
    fail "Ruby $ruby_version detected. Ruby $minimum_ruby_version up to, but not including, 3.4 is required."
  fi
  success "Ruby version: $ruby_version"
  success "Bundler version: $(bundle --version | sed 's/^Bundler version //')"
}

check_node() {
  require_command node "Install Node.js."
  require_command corepack "Install a Node.js distribution that includes Corepack, or install Corepack separately."

  local node_version
  node_version=$(node --version)
  success "Node.js version: $node_version"
  success "Corepack version: $(corepack --version)"

  if ! command -v pnpm >/dev/null 2>&1; then
    fail "pnpm is not available on PATH. Run 'corepack enable' and open a new shell, then try again."
  fi
  success "pnpm version: $(pnpm --version)"
}

check_lynx_root() {
  local lynx_root="${LYNX_ROOT:-}"

  if [ -z "$lynx_root" ]; then
    if [ -d "$default_lynx_root" ]; then
      lynx_root="$default_lynx_root"
      warn "LYNX_ROOT is not set. Falling back to sibling checkout: $lynx_root"
    else
      fail "LYNX_ROOT is not set. Export LYNX_ROOT to your local lynx checkout before continuing."
    fi
  fi

  [ -d "$lynx_root" ] || fail "LYNX_ROOT does not exist: $lynx_root"
  [ -d "$lynx_root/.git" ] || fail "LYNX_ROOT is not a git checkout: $lynx_root"
  [ -f "$lynx_root/Gemfile" ] || fail "Missing Gemfile in LYNX_ROOT: $lynx_root/Gemfile"
  [ -f "$lynx_root/tools/ios_tools/generate_podspec_scripts_by_gn.py" ] || fail "Missing iOS podspec generator in LYNX_ROOT."

  local lynx_commit
  lynx_commit=$(git -C "$lynx_root" rev-parse HEAD 2>/dev/null || true)
  [ -n "$lynx_commit" ] || fail "Unable to read the current lynx commit from $lynx_root"

  if [ "$lynx_commit" != "$required_lynx_commit" ]; then
    fail "LYNX_ROOT points to $lynx_commit, but this repository expects $required_lynx_commit. Check out the required lynx commit and rerun bootstrap.sh."
  fi

  success "LYNX_ROOT: $lynx_root"
  success "Upstream lynx commit: $lynx_commit"
}

main() {
  info "Checking local build prerequisites for LynxExplorer_iOS"
  check_git
  check_xcode
  check_python
  check_ruby
  check_node
  check_lynx_root

  printf '\n'
  success "Environment checks passed."
  info "Next steps:"
  action_hint "export LYNX_ROOT=${LYNX_ROOT:-$default_lynx_root}"
  action_hint "cd $script_dir/app"
  action_hint "./bundle_install.sh"
}

main "$@"
