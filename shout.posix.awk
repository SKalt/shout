#!/usr/bin/awk

# © Steven Kalt
# SPDX-License-Identifier: BSD-3-Clause

# only use POSIX awk functionality for compatibility reasons
# see https://pubs.opengroup.org/onlinepubs/9699919799/utilities/awk.html

function log_message(level, name, color, message) {
  if (level < log_level) return
  _state = render_state(state)
  if (_state) _state =  _state "::"
  print color name reset "\tawk::" _state escape_newlines(message) >> "/dev/stderr"
}
function log_trace(msg) { log_message(1, "TRCE", teal  , msg ) }
function log_debug(msg) { log_message(2, "DBUG", blue   , msg ) }
function log_info(msg)  { log_message(3, "INFO", green  , msg ) }
function log_warn(msg)  { log_message(4, "WARN", orange , msg ) }
function log_error(msg) { log_message(5, "ERRR", red    , msg ) }

function escape(str, pattern, replacement) {
  result="" str
  gsub(pattern, replacement, result)
  return result
}
function escape_newlines(str) { return escape(str, "\n", "\\n") }

function append_line(str, line) {
  if (str) return str "\n" line
  else     return line
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
function row_pos(row_number)  { return FILENAME ":" row_number }
function render_pos(row, col) { return row_pos(row) ":" col }
function col() { 
  _col = length($0) - length(_rest)+1
  _assert(_col >= 0, "invalid column " _col " @ " row_pos(NR) " with `" _rest "`")
  return _col
}
function pos() { return render_pos(NR, col()) }
function current_pos() { if (_current_pos) return " @ "_current_pos }
function set_current_pos() { _current_pos = pos() }
function get_pos(_state) {
  return render_pos(line_numbers[_state], columns[_state])
}
function goto_state(to_state) {
  log_debug(FILENAME " lines " line_numbers[state] ".." NR)
  log_debug("goto::" render_state(to_state) " @ " pos())
  line_numbers[state] = NR;
  columns[state] = col();
  state = to_state
}

function consume(marker, input) {
  # set _matched and _rest globals to the sections of the input through the
  # first match of marker and after it, respectively
  # also sets RSTART and RLENGTH via `match()`
  _input = "" input # ensure input is not mutated
  if (match(_input, marker)) {
    _matched = substr(_input, 1, RSTART+RLENGTH)
    _rest = substr(_input, RSTART+RLENGTH)
    log_trace("consume::`"marker"`::some" current_pos())
  } else {
    _matched = ""
    _rest = _input
    log_trace("consume::`"marker"`::none" current_pos())
  }
  return _rest
}
function parse_next_marker(input) {
  _rest = consume(markers[state+1], input)
  set_current_pos()
  return _rest
}
function _assert(_expr, msg) {
  if (!_expr) {
    log_error(msg)
    exit 1
  }
}

function parse_skip(input, _state) { # TODO: set current position
  # sets the skip_lines global variable, returns remaining input
  _input = "" input # ensure input is not mutated
  skip_lines=0
  if (match(_input, /^ *skip=[0-9]+/)) {
    _matched = substr(_input, 1, RSTART+RLENGTH)
    _rest = substr(_input, RSTART+RLENGTH+1)
    match(_matched, /[0-9]+/)
    skip_lines=substr(_input, RSTART, RLENGTH)
    set_current_pos()
    log_trace("skip::some:: " skip_lines " @ " pos())
  } else {
    _matched=""
    _rest = _input
    log_trace("skip::none:: @ " pos())
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
  log_trace("program::construction::pre " sections[PROGRAM])
  n_lines = split(sections[PROGRAM], _lines, "\n")
  log_debug("n_lines:: " n_lines)
  _program=""
  for (i = 1; i <= n_lines; i++) {
    if (i <= margins[PROGRAM_START]) {
      log_trace("program::construction::skip:: `" _lines[i] "`")
      continue
    }
    if (margins[PROGRAM_END] && i >= (n_lines - margins[PROGRAM_END])) {
      log_trace("program::construction::break:: `" _lines[i] "`")
      break
    }
    log_trace("program::construction::consider::line "i" `" _lines[i] "`")
    _lines[i] = consume("^"program_prefix, _lines[i])
    log_trace("program::construction::append:: `" _lines[i] "`")
    _program=append_line(_program, _lines[i])
  }
  
  if (!_program) log_warn("missing program @ " get_pos(PROGRAM_START))
  n_commands++
  target_file=temp_dir"/command."n_commands".sh"
  print "#!/bin/sh"v                                  >  target_file
  print "# extracted from " get_pos(PROGRAM_START)    >> target_file
  print "set -e"                                      >> target_file
  print "cd " input_file_directory()                  >> target_file
  print _program                                      >> target_file
  return target_file
}

function write_str(str) {
  log_trace("writing::str::" str)
  sections[state] = sections[state] str
}
function write_line(str){
  log_trace("writing::line::" str)
  sections[state] = sections[state] str "\n" 
}
function reset_margins() {
  for (i=PROGRAM_START; i<= OUTPUT_END; i+=2) margins[i] = 0
}
function reset_sections() {
  for (i=PROGRAM_START; i<= OUTPUT_END; i++) sections[i] = ""
}
function reset_positions() {
  # positions[TEXT] denotes the start of the current text block
  line_numbers[PROGRAM_START] = 0; columns[PROGRAM_START] = 0
  line_numbers[PROGRAM_END]   = 0; columns[PROGRAM_END]   = 0
  line_numbers[OUTPUT_START]  = 0; columns[OUTPUT_START]  = 0
  line_numbers[OUTPUT_END]    = 0; columns[OUTPUT_END]    = 0
}
function reset_all() {
  reset_positions()
  reset_sections()
  reset_margins()
}

function flush_sections() {
  program_file = construct_program()

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
  log_debug("exec::pre:: about to run " program_file)
  program_exit=system("sh " program_file) # writes stdout/err directly to stdout
  if (program_exit > 0) {
    log_error("exec::post:: program failed @ " get_pos(PROGRAM_START) " with exit code " program_exit)
    log_info("you can find the exact text of the program in " temp_dir "/commands.sh")
    exit_code++
  } else {
    log_debug("exec::post:: program succeeded @ " get_pos(PROGRAM_START) " with exit code " program_exit)
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
  _assert(temp_dir, "temp_dir not set")
  _assert((log_level >=0), "invalid log_level " log_level)
  # log_level: 1 (debug), 2 (info), 3 (warn), 4 (error)
  _input = ""
  _matched = ""
  _rest = ""
  n_commands=0
  # states ##################################################
  TEXT          = 1; names[TEXT]          = "TEXT"          ;
  PROGRAM_START = 2; names[PROGRAM_START] = "PROGRAM_START" ;
  PROGRAM       = 3; names[PROGRAM]       = "PROGRAM"       ;
  PROGRAM_END   = 4; names[PROGRAM_END]   = "PROGRAM_END"   ;
  INTERMEDIATE  = 5; names[INTERMEDIATE]  = "INTERMEDIATE"  ;
  OUTPUT_START  = 6; names[OUTPUT_START]  = "OUTPUT_START"  ;
  OUTPUT        = 7; names[OUTPUT]        = "OUTPUT"        ;
  OUTPUT_END    = 8; names[OUTPUT_END]    = "OUTPUT_END"    ;

  markers[PROGRAM_START] = program_start_marker
  markers[PROGRAM_END]   = program_end_marker
  markers[OUTPUT_START]  = output_start_marker
  markers[OUTPUT_END]    = output_end_marker
  for (i=PROGRAM_START; i<= OUTPUT_END; i+=2) { # all start/end markers are even
    validate_marker(markers[i])
  }

  state = TEXT

  skip_lines=0
  log_debug("log_level:: " log_level)
  program_prefix = ""
  program = ""
  prev_output = ""
  output = ""
  exit_code = 0

  reset_all()
  line_numbers[TEXT] = 1
  column_numbers[TEXT] = 1
  # TODO: fail fast?
}
{
  _rest = $0
  if (state == TEXT) {
    if (match(_rest, "shout:disable")) {
      print _rest
      next
    }
    _rest = parse_next_marker(_rest)
    if (!_matched) {
      print _rest
      next
    }
    printf "%s", substr(_input, 1, RSTART - 1)
    goto_state(PROGRAM_START)
    write_str(substr(_input, RSTART, RLENGTH))
    program_prefix=substr(_matched, 1, RSTART - 1)
  }
  if (state == PROGRAM_START) {
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
    _rest = parse_next_marker(_rest)
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
    _rest=parse_next_marker(_rest)
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
    _rest=parse_next_marker(_rest)
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
    _stash=_rest # avoid overwriting _rest in flush_sections()
    if (_matched) {
      write_line(_matched _rest)
      flush_sections()
    } else {
      flush_sections()
      print _stash
    }
    _rest = ""
    goto_state(TEXT)
    next
  }
  _assert(false, "invalid state " state " @ " pos())
}
END {
  if (state != TEXT) {
    exit_code++
    msg="Missing a "
    if (state == PROGRAM_START ) msg = msg program_end_marker
    if (state == PROGRAM       ) msg = msg output_start_marker
    if (state == PROGRAM_END   ) msg = msg output_start_marker
    if (state == OUTPUT_START  ) msg = msg output_end_marker
    if (state == OUTPUT        ) msg = msg output_end_marker
    _assert((state != OUTPUT_END), "Should never be in state " OUTPUT_END " @ EOF in " pos())
    msg=msg" tag in " FILENAME " after line " NR
    log_error(msg)
  }
  exit exit_code
}
