# `shout`

`shout` replaces parts of a file with the output of shell scripts in the same.

`shout` is a portmanteau of "shell out".

# Installation

Copy `./shout.sh` into your repo.
It's a single file with no dependencies outside of POSIX utilities.

# Usage

## Basic example

```sh
# {{{sh printf '\nexport VERSION="%s"\n# ' "$(cat ./VERSION)" }}} {{{out
export VERSION="0.0.0"
# }}}
```

## When to use `shout`

When you want a quick-and-dirty / lightweight hack to inline output.

`shout` is inspired by [`cog`][cog], which replaces parts of files with the output of commented shell scripts.
If you can guaruntee `cog` and a compatible verion of python are present in your development environment, you should probably use `cog`!
Python snippets tend to be more readable than shell snippets, and so tend to be easier to maintain.

You should consider using a more robust templating system if you care about performance and want better guarantees about inserting values.

If you want to intergrate with your compiler, consider looking for a native way to embed text in files.
For example, rust has `include_str!("file")` and go has `//go:embed`
<!-- TODO: link -->

You should use `shout` when you don't have access to python, don't want to pull python into your development/CI environment, don't want to depend on `cog`, and don't care about performance or compile-time correctness.

## Command-line interface

<!-- {{{sh skip=1 -->
```sh
{
  printf "shout version: "
  ./shout.sh --version
  ./shout.sh --help
} | sed 's/^/# /g'
```
<!-- }}} skip=1 -->
<!-- {{{out skip=1 -->
```sh
# shout version: 0.0.0
# USAGE: shout [-h|--help] [-V|--version] [-o|--outdir DIR]
#              [-r|--replace] [-c|--check] [-a|--accept] [-d|--diff[=CMD]]
#              [--log-level=LEVEL] [-q|--quiet] [-v|--verbose] [-vv|--trace]
#              FILE...
# 
# -h | --help       Print this help message.
# -V | --version    Print the version number.
# -o | --outdir DIR Write the output to DIR.
# -r | --replace    Replace the input file with the output.
# -c | --check      Check that the files would not change if run again.
# -a | --accept     Accept the current changes and update the input file.
# -d | --diff[=CMD] View the diff of the generated output. CMD is an arbitrary
#                   shell command accepting the before and after files.
#                   Defaults to the value of $SHOUT_DIFF_CMD or `diff -u`
# --log-level=LEVEL Set the log level to LEVEL.
#                   Allowed values: error, warn, info, debug, trace.
# -q  | --quiet     Only print error logs
# -v  | --verbose   Print info, warning, and debug logs
# -vv | --trace     Print all logs
#                   shell command accepting the before and after files.
#                   defaults to `diff -u`
```
<!-- }}} skip=1 -->

## Inline scripts

### Skipping margins
To avoid having to re-generate lines Markdown, you can

```txt
{{{sh skip=2 (everything after "skip=<digits>" is ignored)
program start margin: skipped
program start margin: skipped
echo
echo "generated"
echo
program end margin: skipped
}}} skip=1 (again, everything after skip="<digits>" is ignored)

Intermediate text
{{{out skip=1
output start margin: skipped

generated

output end margin: skipped
}}} skip=1
```

### single-line
```txt
You can run use `shout` to generate content
even in the {{{sh printf " %s" ok }}}{{{out ok}}} middle of a line
```

## When to use `shout`

When you want a quick-and-dirty hack to inline output.

`shout` is inspired by [`cog`][cog], which replaces parts of files with the output of commented shell scripts.
If you can guaruntee `cog` and a compatible verion of python are present in your development environment, you should probably use `cog`!
Python snippets tend to be more readable than shell snippets, and so tend to be easier to maintain.

You should consider using a more robust templating system if you care about performance and want better guarantees about inserting values.

If you want to intergrate with your compiler, consider looking for a native way to embed text in files.
For example, rust has `include_str!("file")` and go has `//go:embed`
<!-- TODO: link -->

You should use `shout` when you don't have access to python, don't want to pull python into your development/CI environment, don't want to depend on `cog`, and don't care about performance or compile-time correctness.
 " %s" middle}}}{{{out middle}}} of a line
```

### prefixed
```sh
# {{{sh echo; echo;
# echo "#>>> whatever came before {{{sh is"
# echo "#>>> stripped from subsequent lines"
echo "#>>> if present; unprefixed lines are also"
echo "#>>> valid."
# printf "\n# " }}}{{{out

#>>> whatever came before {{{sh is
#>>> stripped from subsequent lines
#>>> if present; unprefixed lines are also
#>>> valid.

# }}}
```

# Advanced usage

`shout` works by
  1. extracting a program from a file
  2. writing that program to a temporary file
  3. then running that file like `sh "${temp_program_file}.sh"` 
Writing out the shellscripts that get run makes debugging easier (you can look at the file without mentally removing quotes, prefixes, and shout's markers).

Here's an example script that yields itself:
<!-- {{{sh
echo "# contents of $0"
cd - >/dev/null # silently go to shout's working directory
cat "$0" |      # $0 is relative to shout's pwd
  sed 's/^# extracted from .*/# extracted from <PATH>:<LINE>:<COL>/g'
}}}{{{out skip=1 -->
```sh
# contents of ./.cache/.shout/current/.%README.md/command.6.sh
#!/bin/sh
# extracted from <PATH>:<LINE>:<COL>
set -e
cd .
echo "# contents of $0"
cd - >/dev/null # silently go to shout's working directory
cat "$0" |      # $0 is relative to shout's pwd
  sed 's/^# extracted from .*/# extracted from <PATH>:<LINE>:<COL>/g'

```
<!-- }}} skip=1 -->

Since the files are present on-disk, you can run `shellcheck` to validate your scripts:
<!-- {{{sh skip=1 -->
```sh
cd - >/dev/null
find ./.cache/.shout/current \
  -name 'command.*.sh' \
  -exec shellcheck '{}' ';' | sed 's/^/# /g'
```
<!-- }}} skip=1 -->
<!-- {{{out skip=1 -->
```sh
# 
# In ./.cache/.shout/current/.%README.md/command.6.sh line 7:
# cat "$0" |      # $0 is relative to shout's pwd
#     ^--^ SC2002 (style): Useless cat. Consider 'cmd < file | ..' or 'cmd file | ..' instead.
# 
# For more information:
#   https://www.shellcheck.net/wiki/SC2002 -- Useless cat. Consider 'cmd < file...
```
<!-- }}} skip=1 -->


<!-- comments -->
[cog]: https://cog.readthedocs.io/en/latest/
