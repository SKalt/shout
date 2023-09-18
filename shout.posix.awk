#!/usr/bin/awk
# must use POSIX awk for compatibility reasons
# see https://pubs.opengroup.org/onlinepubs/9699919799/utilities/awk.html
function log_message(level, name, color, message) {
  if (level < log_level) return
  _state = render_state(state)
  if (_state) _state =  _state "::"
  print color name reset "\tawk::" _state escape_newlines(message) >> "/dev/stderr"
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
  if (str) return str "\n" line
  else     return line
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
function pos() { return FILENAME ":" NR ":" (length($0) - length(_rest)+1) }
function goto_state(to_state) {
  log_debug("goto::" render_state(to_state) " @ " pos())
  line_numbers[state] = NR
  state = to_state
}

function consume(marker, input) {
  # set _matched and _rest globals to the sections of the input through the 
  # first match of marker and after it, respectively
  # also sets RSTART and RLENGTH via `match()`
  _input = "" input # ensure input isn't mutated
  if (match(_input, marker)) {
    _matched = substr(_input, 1, RSTART+RLENGTH)
    _rest = substr(_input, RSTART+RLENGTH)
    log_debug("consume::`"marker"`::some @ " pos())
  } else {
    _matched = ""
    _rest = _input
    log_debug("consume::`"marker"`::none @ " pos())
  }
  return _rest
}
function _assert(_expr, msg) {
  if (!_expr) {
    log_error(msg)
    exit 1
  }
}

function parse_skip(input, _state) {
  # sets the skip_lines global variable, returns remaining input
  _input = "" input # ensure input isn't mutated
  skip_lines=0
  if (match(_input, /^ *skip=[0-9]+/)) {
    _matched = substr(_input, 1, RSTART+RLENGTH)
    _rest = substr(_input, RSTART+RLENGTH+1)
    match(_matched, /[0-9]+/)
    skip_lines=substr(_input, RSTART, RLENGTH)
    log_debug("skip:::: found directive skip=" skip_lines " lines @ " pos())
  } else {
    _matched=""
    _rest = _input
    log_debug("skip::`" _input "` did not match")
  }
  set_margin(_state, skip_lines)
  return _rest
}

function construct_program() {
  # watch out: sets _matched, _rest, _input via consume()
  _assert(FILENAME, "FILENAME not set")
  _assert(NR, "NR not set")
  log_debug("program::construction:: margin before:" margins[PROGRAM_START])
  log_debug("program::construction:: margin after:" margins[PROGRAM_END])
  log_debug("program::construction::pre " sections[PROGRAM])
  n_lines = split(sections[PROGRAM], _lines, "\n")
  log_debug("n_lines:: " n_lines)
  _program=""
  for (i = 1; i <= n_lines; i++) {
    if (i <= margins[PROGRAM_START]) continue
    if (margins[PROGRAM_END] && i >= (n_lines - margins[PROGRAM_END])) break
    _program=append_line(_program, consume(program_prefix, _lines[i]))
  }
  if (!_program) log_warn("missing program @ " pos())
  _program = "sh -c 'set -e && cd " input_file_directory() " && " shell_quote(_program) " 2>&1'"
  # print _program > "/tmp/prog"
  # TODO: persist program for debugging
  return _program
}

function write_str(str) {
  log_debug("writing::str::" str)
  sections[state] = sections[state] str
}
function write_line(str){
  log_debug("writing::line::" str)
  sections[state] = sections[state] str "\n" 
}
function reset_margins() {
  margins[PROGRAM_START] = 0
  margins[PROGRAM_END] = 0
  margins[OUTPUT_START] = 0
  margins[OUTPUT_END] = 0
}
function reset_sections() {
  sections[PROGRAM_START] = ""
  sections[PROGRAM] = ""
  sections[PROGRAM_END] = ""
  sections[INTERMEDIATE] = ""
  sections[OUTPUT_START] = ""
  sections[OUTPUT] = ""
  sections[OUTPUT_END] = ""
}
function reset_line_numbers() {
  # line_numbers[TEXT] denotes the start of the current text block
  line_numbers[PROGRAM_START] = 0
  line_numbers[PROGRAM_END] = 0
  line_numbers[OUTPUT_START] = 0
  line_numbers[OUTPUT_END] = 0
}

function flush_sections() {
  program = construct_program()

  _buffer=""
  _buffer = _buffer sections[PROGRAM_START]
  _buffer = _buffer sections[PROGRAM]
  _buffer = _buffer sections[PROGRAM_END]
  _buffer = _buffer sections[INTERMEDIATE]
  _buffer = _buffer sections[OUTPUT_START]

  _n_lines = split(sections[OUTPUT], _lines, "\n")
  if (margins[OUTPUT_START]) {
    for (i=1; i <= margins[OUTPUT_START] && i <= _n_lines; i++) {
      _buffer = _buffer _lines[i] "\n"
    }
  }
  printf "%s", _buffer
  _buffer=""
  log_debug("exec::pre:: about to run " program)
  print "# " pos() >> temp_dir"/commands.sh"
  print program >> temp_dir"/commands.sh"
  program_exit=system(program) # writes stdout/err directly to stdout
  if (program_exit > 0) {
    log_error("exec::post:: program failed @ " pos())
    exit_code++
  } else {
    log_debug("exec::post:: program succeeded @ " pos())
  }
  if (margins[OUTPUT_END]) {
    for (i=(_n_lines-margins[OUTPUT_END]); i <= _n_lines; i++) {
      if (i > margins[OUTPUT_START]) _buffer = append_line(_buffer, _lines[i])
    }
  }
  _buffer = _buffer sections[OUTPUT_END]
  printf "%s", _buffer
  reset_sections()
  reset_margins()
}
function validate_marker(marker) {
  _assert(marker, "marker`" marker "` not set")
  _assert((!match(marker, /[ \t\r\n]/)), "marker `" marker "` cannot contain whitespace")
}
function set_margin(_state, n_lines) {
  _assert(!margins[_state], "margin::nonzero:: " render_state(_state) "=" margins[_state] " section @ " pos())
  margins[_state] = n_lines
  log_debug("margin::" render_state(_state) "::" margins[_state] " lines @ " pos())
}
function render_state(_state) { return names[_state] }

BEGIN {
  # the following variables MUST be set
  # eof_error: true or false
  # bin_dir: directory where shout helpers are located
  validate_marker(program_start_marker)
  validate_marker(program_end_marker)
  validate_marker(output_start_marker)
  validate_marker(output_end_marker)
  _assert(temp_dir, "temp_dir not set")
  _assert((log_level >=0), "invalid log_level " log_level)
  # program_start_marker: start of the shout block
  # program_end_marker: end of the shout block
  # output_start_marker: start of the output block
  # output_end_marker: end of the output block
  # log_level: 1 (debug), 2 (info), 3 (warn), 4 (error)
  _input = ""
  _matched = ""
  _rest = ""
  # states
  TEXT = 1
  PROGRAM_START = 2
  PROGRAM = 3
  PROGRAM_END = 4
  INTERMEDIATE = 5
  OUTPUT_START = 6
  OUTPUT = 7
  OUTPUT_END = 8

  names[TEXT] = "TEXT"
  names[PROGRAM_START] = "PROGRAM_START"
  names[PROGRAM] = "PROGRAM"
  names[PROGRAM_END] = "PROGRAM_END"
  names[INTERMEDIATE] = "INTERMEDIATE"
  names[OUTPUT_START] = "OUTPUT_START"
  names[OUTPUT] = "OUTPUT"
  names[OUTPUT_END] = "OUTPUT_END"

  state = TEXT

  skip_lines=0
  log_debug("log_level:: " log_level)
  program_prefix = ""
  program = ""
  prev_output = ""
  output = ""
  exit_code = 0

  reset_line_numbers()
  line_numbers[TEXT] = 1
  reset_sections()
  reset_margins()
  # TODO: fail fast?
}
{
  _rest = $0
  if (state == TEXT) {
    if (match(_rest, "shout:disable")) {
      print _rest
      next
    }
    _rest = consume(program_start_marker, _rest)
    if (!_matched) {
      print _rest
      next
    }
    log_debug(render_state(state) ":: " FILENAME " lines " line_numbers[TEXT] ".." NR)
    printf "%s", substr(_input, 1, RSTART - 1)
    goto_state(PROGRAM_START)
    write_str(substr(_input, RSTART, RLENGTH))
    program_prefix=substr(_matched, 1, RSTART - 1)
  }
  if (state == PROGRAM_START) {
    log_debug(_rest)
    _rest = parse_skip(_rest, state)
    if (_matched) {
      log_debug("full-line @ " pos() " :: `" _matched "`")
      write_line(_input)
      goto_state(PROGRAM)
      next
    }
    log_debug("PROGRAM_START::partial-line @ " pos())
    goto_state(PROGRAM) # always transition to PROGRAM
  }
  if (state == PROGRAM) {
    _rest = consume(program_end_marker, _rest)
    if (!_matched) {
      write_line(_rest)
      next
    } else {
      write_str(substr(_input, 1, RSTART - 1))
      goto_state(PROGRAM_END)
      write_str(substr(_input, RSTART, RLENGTH))
      log_debug("PROGRAM:: " FILENAME " lines " line_numbers[PROGRAM_START] ".." NR)
    }
  }
  if (state == PROGRAM_END) {
    _rest=parse_skip(_rest, state)
    if (_matched) {
      log_debug("full-line @ " pos() " :: `" _matched "`")
      write_line(_matched _rest)
      goto_state(INTERMEDIATE)
      next
    }
    log_debug("PROGRAM_END::partial-line @ " pos())
    goto_state(INTERMEDIATE)
  }
  if (state == INTERMEDIATE) {
    _rest=consume(output_start_marker, _rest)
    if (!_matched) {
      write_line(_rest)
      next
    }
    write_str(substr(_input, 1, RSTART - 1))
    log_debug("INTERMEDIATE:: " FILENAME " lines " line_numbers[PROGRAM_END] ".." NR)
    goto_state(OUTPUT_START)
    write_str(substr(_input, RSTART, RLENGTH))
  }
  if (state == OUTPUT_START) {
    _rest=parse_skip(_rest, state)
    if (_matched) {
      write_line(_matched _rest)
      goto_state(OUTPUT)
      next
    }
    goto_state(OUTPUT)
  }
  if (state == OUTPUT) {
    log_debug(_rest)
    _rest=consume(output_end_marker, _rest)
    if (!_matched) {
      write_line(_rest)
      next
    }
    write_str(substr(_input, 1, RSTART - 1))
    goto_state(OUTPUT_END)
    write_str(substr(_input, RSTART, RLENGTH))
  }
  if (state == OUTPUT_END) {
    _rest=parse_skip(_rest, state)
    if (_matched) {
      write_line(_matched _rest)
      flush_sections()
    } else {
      flush_sections()
      print _rest
    }
    goto_state(TEXT)
    next
  }
  _assert(false, "invalid state " state " @ " pos())
}
END {
  if (state != TEXT) {
    exit_code++
    msg="Missing a "
    if (state == PROGRAM_START) msg = msg program_end_marker
    if (state == PROGRAM) msg = msg output_start_marker
    if (state == PROGRAM_END) msg = msg output_start_marker
    if (state == OUTPUT_START) msg = msg output_end_marker
    if (state == OUTPUT) msg = msg output_end_marker
    _assert((state != OUTPUT_END), "Should never be in state " OUTPUT_END " @ EOF in " pos())
    msg=msg" tag in " FILENAME " after line " NR
    log_error(msg)
  }
  exit exit_code
}
