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
  gsub(/'/, "'\\''", result)
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
      _program="sh -c 'set -eu && cd " input_file_directory() " && " shell_quote(program) " 2>&1'"
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
