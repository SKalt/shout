#!/bin/sh
### USAGE: shout [-h|--help]
# -d | --delete   Delete the generator code from the output file.
# -o | --outdir OUTNAME      Write the output to OUTNAME.
### -r | --replace  Replace the input file with the output.
### -s STRING       Suffix all generated output lines with STRING.
### -x              Excise all the generated output without running the generators.
###     --check     Check that the files would not change if run again.
### -q | --quiet    Do not print the output file name.
### -v | --verbose  Print the output file name.
### -h | --help     Print this help message.
### -V | --version  Print the version number.
set -eu # fail on any unset variable or unhandled error
usage() { grep '^###' "$0"  | sed 's/^### //g; s/^###//g'; }

# global state
# state :: constants
shout_version="0.0.0"
shout_log_error=3
shout_log_warn=2
shout_log_info=1
shout_log_debug=0

# state :: options
shout_check=false
should_replace=true
shout_log_level=1
parse_log_level() {
  case "${1:-}" in
  error) shout_log_level=$shout_log_error;; # --quiet; filter out everything but errors
  warn) shout_log_level=$shout_log_warn;;
  info) shout_log_level=$shout_log_info;; # default
  verbose) shout_log_level=$shout_log_debug;; # --verbose; show everything
  *)
    log_error "invalid log level: $1" >&2 
    log_error "expected one of: quiet, warn, info, verbose" >&2
    exit 1;;
  esac
}

shout_dir=".cache/.shout"

# state :: mutable
shout_should_use_color=false
shout_exit_code=0

# state :: colors (cached for performance reasons)
shout_red=""
shout_green=""
shout_orange=""
shout_blue=""
# shout_purple=""
# shout_teal=""
# shout_white=""
shout_reset=""

is_installed() { command -v "$1" >/dev/null 2>&1; }
no_op() { :; }
iso_date() { date +"%Y-%m-%dT%H:%M:%SZ"; }
require_clis() {
  for cli in "$@"; do
    if is_installed "$cli"; then
      log_debug "found $cli @ $(command -v "$cli")"
    else
      log_error "missing required CLI: $1"
      shout_exit_code=127 # command not found
    fi
  done
  if [ $shout_exit_code -ne 0 ]; then
    exit $shout_exit_code
  fi
}
case "$shout_log_level" in
  "$shout_log_warn" | "$shout_log_error")
    log_info() { no_op; }
    ;;
  *)
    log_info() {
      printf "%sINFO%s\t%s\n" "$shout_green" "$shout_reset" "$*" >&2;
    }
    ;;
esac

case "$shout_log_level" in
  "$shout_log_info" | "$shout_log_warn" | "$shout_log_error") log_debug(){ no_op; } ;;
  *)
    log_debug() {
      printf "%sDBUG%s\t%s\n" "$shout_blue" "$shout_reset" "$*" >&2;
    }
  ;;
esac

case "$shout_log_level" in
  "$shout_log_error") log_warn() { no_op; } ;;
  *)
    log_warn() {
      printf "%sWARN%s\t%s\n" "$shout_orange" "$shout_reset" "$*" >&2;
    }
  ;;
esac

log_error() { 
  # always!
  printf "%sERRR%s\t%s\n" "$shout_red" "$shout_reset" "$*" >&2;
}

while [ -n "${1:-}" ]; do
  case "$1" in
    -h|--help) usage && exit 0;;
    -V|--version) printf "%s\n" "$shout_version" && exit 0;;
    -o|--outdir) shift && shout_dir="$1"; shift;;
    -q|--quiet) shout_log_level=3; shift;;
    -r|--replace) should_replace=true; shift;;
    -v|--verbose) shout_log_level=0; shift;;
    --check) shout_check=true; shift;;
    -*) echo "unexpected argument: $1" >&2 && usage >&2 && exit 1;;
    *) break;;
  esac
done
if (
  test -t 2 && # stderr (device 2) is a tty
  test -z "${NO_COLOR:-}" && # the NO_COLOR variable isn't set
  command -v tput >/dev/null 2>&1 # the `tput` command is available
); then shout_should_use_color=true; fi
if [ "$shout_should_use_color" = "true" ]; then
  shout_red="$(tput setaf 1)"
  shout_green="$(tput setaf 2)"
  # shout_orange="$(tput setaf 3)"
  shout_blue="$(tput setaf 4)"
  # shout_purple="$(tput setaf 5)"
  # shout_teal="$(tput setaf 6)"
  # shout_white="$(tput setaf 7)"
  shout_reset="$(tput sgr0)"
fi

# posix builtins -- should always be present
require_clis cat command sh tee test "[" diff mkdir printf sed awk env


log_debug "color: $shout_should_use_color"

# validate the options and fill in defaults
# TODO: handle tempdir maybe/not existing
if [ -z "$shout_dir" ]; then
  shout_dir="${PWD}/.cache/.shout" # TODO: clean up on exit?
fi
log_debug "outdir: $shout_dir"
if [ ! -d "$shout_dir" ]; then
  mkdir -p "$shout_dir"
fi

for f in "$@"; do
  if [ ! -f "$f" ]; then
    log_error "$f is not a file"
    shout_exit_code=127 # file not found
  fi
done
if [ $shout_exit_code -ne 0 ]; then
  exit $shout_exit_code
fi

log_debug "check: $shout_check"

awk_prog="$(cat ./shout.posix.awk)" # FIXME: inline this!
render() {
  awk \
    -v program_start_marker='{{start' \
    -v program_end_marker="{{end" \
    -v output_start_marker="{{out" \
    -v output_end_marker="{{done" \
    -v log_level="$shout_log_level" \
    -v red="$shout_red" \
    -v green="$shout_green" \
    -v orange="$shout_orange" \
    -v blue="$shout_blue" \
    -v reset="$shout_reset" \
   "$awk_prog" "$1"
}
shout_time="$(iso_date)"
for f in "$@"; do
  log_debug "rendering $f -> $shout_dir/${f##*/}"
  shout_target="$shout_dir/$shout_time.${f##*/}"
  render "$f" > "$shout_target"
  if diff "$f" "$shout_target" >"$shout_target.diff" 2>&1; then
    log_info "no changes to $f"
    continue
  else
    # log_debug "$f"
    if [ "$shout_check" = "true" ]; then
      shout_exit_code=1
    elif [ "$should_replace" = "true" ]; then
      log_info "replacing $f"
      mv -f "$shout_target" "$f"
      continue
    else
      log_info "would replace $f"
    fi
  fi
done
