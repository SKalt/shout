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
# TODO: parse marker options
# TODO: prefix option for easy indenting, commenting, etc.
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
should_replace=false
shout_log_level=1
shout_program_start_marker="{{start"
shout_program_end_marker="{{end"
shout_output_start_marker="{{out"
shout_output_end_marker="{{done"
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


# parse options
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

# utility functions
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

if (
  test -t 2 && # stderr (device 2) is a tty
  test -z "${NO_COLOR:-}" && # the NO_COLOR variable isn't set
  command -v tput >/dev/null 2>&1 # the `tput` command is available
); then shout_should_use_color=true; fi
if [ "$shout_should_use_color" = "true" ]; then
  shout_red="$(tput setaf 1)"
  shout_green="$(tput setaf 2)"
  shout_orange="$(tput setaf 3)"
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

# {{start}}
# cat ./shout.posix.awk | sed "s/'/'\\\\''/g; s/^/  /g; "
# {{end}}
# {{out skip=2}}
# shellcheck disable=SC2016
awk_prog='
  #!/usr/bin/awk
  # must use POSIX awk for compatibility reasons
  # see https://pubs.opengroup.org/onlinepubs/9699919799/utilities/awk.html
  # variables
  function parse_skip(line) {
    log_debug("parse_skip:: " line)
    if (match(line, "skip=[0-9]+")) {
      log_debug("match::skip:: " line)
      return substr(line, RSTART + 5, RLENGTH - 5)
    } else {
      log_debug("match::skip::none:: " line)
      return 0
    }
  }
  function log_message(level, name, color, message) {
    if (level >= log_level) {
      print color name reset " " message >> "/dev/stderr"
    }
  }
  function log_debug(msg) { log_message(0, "DBUG", blue, msg) }
  function log_info(msg) { log_message(1, "INFO", green, msg) }
  function log_warn(msg) { log_message(2, "WARN", orange, msg) }
  function log_error(msg) { log_message(3, "ERRR", red, msg) }
  
  function shell_quote(str) {
    result="" str
    gsub(/'\''/, "'\''\\'\'''\''", result)
    return result
  }
  function append_line(str, line) {
    if (str) {
      return str "\n" line
    } else {
      return line
    }
  }
  function escape_newlines(str) {
    result="" str
    gsub(/\n/, "\\n", result)
    return result
  }
  function input_file_directory() {
    f=FILENAME
    result=""
    split(f, path_segments, "/")
    for (i = 1; i < length(path_segments); i++) {
      if (result) result=result "/" path_segments[i]
      else result=path_segments[i]
    }
    return result
  }
  
  
  BEGIN {
    # the following variables MUST be set
    # eof_error: true or false
    # bin_dir: directory where shout helpers are located
    if (!program_start_marker) {
      log_error("program_start_marker not set")
      exit 1
    }
    if (!program_end_marker) {
      log_error("program_end_marker not set")
      exit 1
    }
    if (!output_start_marker) {
      log_error("output_start_marker not set")
      exit 1
    }
    if (!output_end_marker) {
      log_error("output_end_marker not set")
      exit 1
    }
    # program_start_marker: start of the shout block
    # program_end_marker: end of the shout block
    # output_start_marker: start of the output block
    # output_end_marker: end of the output block
    # log_level: 1 (debug), 2 (info), 3 (warn), 4 (error)
    state = 0
    # 0: before program
    # 1: in program
    # 2: after program
    # 3: in output
    # 4: after output (goto 1)
    log_debug("log_level:: " log_level)
    program=""
    prev_output=""
    output=""
    program_prefix=""
    exit_code=0
    skip_lines=0
    # TODO: fail fast?
  }
  {
    line=$0
    log_debug(FILENAME " line " NR " loop::state=" state ";skip_lines=" skip_lines ":: " substr(line, 1, 10))
    if (state == 0) { # parsing text as normal
      program_line_start=match(line, program_start_marker)
      if (program_line_start > 0) {
        log_debug("match::p::start:: " line)
        print line
        state = 1
        program="" # just to be sure
        program_prefix=substr(line, 1, program_line_start - 1)
        program_prefix_len=length(program_prefix)
        skip_lines=parse_skip(substr(line, program_line_start))
      } else {
        print line
      }
      next
    }
    if (state == 1) { # in the program
      print line # always re-emit the program
      if (skip_lines > 0) {
        log_debug("skip:: " line)
        skip_lines--
        next
      }
      program_line_end=match(line, program_end_marker)
      if (program_line_end > 0) {
        log_debug("match::p::end:: " line)
        state = 2
        skip_lines=parse_skip(substr(line, program_line_end))
        next
      } else {
        if (substr(line, 1, program_prefix_len) == program_prefix) {
          _val = substr(line, length(program_prefix) + 1)
        } else {
          _val = line
        }
        program = append_line(program, _val)
        next
      }
    }
    if (state == 2) { # program ended
      print line # always re-emit post-program, pre-output text
      if (skip_lines > 0) {
        # print all but the last `skip_lines` lines of the program
        n_lines = split(program, _lines, "\n")
        log_debug("program::construction::pre " escape_newlines(program))
        log_debug("n_lines:: " n_lines)
        _program=""
        for (_i = 1; _i + skip_lines <= n_lines; _i++) {
          _program=append_line(_program, _lines[_i])
        }
        program=_program
        skip_lines=0
      }
      if (!program) {
        log_warn("missing program @ " FILENAME " line " NR)
      }
      log_debug("program::construction::post " escape_newlines(program))
      _program=""
      output_line_start=match(line, output_start_marker)
      if (output_line_start > 0) {
        state = 3
        skip_lines=parse_skip(substr(line, output_line_start))
        next
      } else {
        next
      }
    }
    if (state == 3) { # in the output section
      if (skip_lines > 0) {
        skip_lines--
        log_debug("skip:: " line)
        print line
        next
      }
      prev_output=prev_output "\n" line
      output_line_end=match(line, output_end_marker)
      if (output_line_end > 0) {
        log_debug("match::o::end:: " line)
        state = 4
        skip_lines=parse_skip(substr(line, output_line_end))
        suffix=""
        if (skip_lines > 0) {
          # print the last skip_lines lines of the previously-rendered output section
          _n_lines = split(prev_output, _lines, "\n")
          for (_i = _n_lines - skip_lines; _i < _n_lines; _i++) {
            suffix = append_line(suffix, _lines[_i])
          }
          skip_lines=0
        }
        suffix=append_line(suffix, line)
        # TODO: move working directory to that of FILENAME
        _program="sh -c '\''set -eu && cd " input_file_directory() " && " shell_quote(program) " 2>&1'\''"
        log_debug("exec::pre:: about to run " escape_newlines(_program))
        program_exit=system(_program) # writes directly to stdout
        log_debug("exec::post:: program finished with exit code " program_exit)
        print suffix
        if (program_exit > 0) {
          log_error("program failed @ " FILENAME ":" NR)
          exit_code++
        } else {
          log_debug("program succeeded @ " FILENAME ":" NR)
        }
        state = 0
        program=""
        prev_output=""
        output=""
        program_prefix=""
        skip_lines=0
      }
      next
    }
  }
  END {
    if (state != 0) {
      exit_code++
      msg="Missing a "
      if (state == 1) msg=msg program_end_marker
      if (state == 2) msg=msg output_start_marker
      if (state == 3) msg=msg output_end_marker
      if (state == 4) msg=msg "???"
      msg=msg" tag in " FILENAME " after line " NR
      log_error(msg)
    }
    exit exit_code
  }
'
# {{done skip=1}}

render() {
  awk \
    -v program_start_marker="$shout_program_start_marker" \
    -v program_end_marker="$shout_program_end_marker" \
    -v output_start_marker="$shout_output_start_marker" \
    -v output_end_marker="$shout_output_end_marker" \
    -v log_level="$shout_log_level" \
    -v red="$shout_red" \
    -v green="$shout_green" \
    -v orange="$shout_orange" \
    -v blue="$shout_blue" \
    -v reset="$shout_reset" \
   "$awk_prog" "$1"
}
shout_time="$(iso_date)"
if [ "$#" = 0 ]; then
  log_error "no files to render"
  exit 1
fi
for f in "$@"; do
  log_debug "rendering $f -> $shout_dir/${f##*/}"
  shout_target="$shout_dir/$shout_time.${f##*/}"
  render "$f" > "$shout_target"
  if diff -u "$f" "$shout_target" >"$shout_target.diff" 2>&1; then
    log_info "no changes to $f"
    continue
  else
    if [ "$shout_check" = "true" ]; then
      log_error "would update $f"
      shout_exit_code=1
    elif [ "$should_replace" = "true" ]; then
      log_info "replacing $f"
      cat "$shout_target" > "$f" # preserve file permissions
      continue
    else
      log_info "would replace $f"
    fi
  fi
done

exit $shout_exit_code
