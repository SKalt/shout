# `shout`

`shout` replaces parts of files with the output of commented shell scripts.

`shout` is a portmanteau of "shell out".

# Usage
<!-- {{start skip=1}} -->
```sh
{
  printf "shout version: "
  ./shout.sh --version
  ./shout.sh --help
} | sed 's/^/# /g'
```
<!-- {{end skip=1}} -->
<!-- {{out skip=1}} -->
```sh
# shout version: 0.0.0
# USAGE: shout [-h|--help]
# -r | --replace  Replace the input file with the output.
# -s STRING       Suffix all generated output lines with STRING.
# -x              Excise all the generated output without running the generators.
#     --check     Check that the files would not change if run again.
# -q | --quiet    Do not print the output file name.
# -v | --verbose  Print the output file name.
# -h | --help     Print this help message.
# -V | --version  Print the version number.
```
<!-- {{done skip=1}} -->

## When to use `shout`

When you want a quick-and-dirty hack to inline output.

`shout` is inspired by [`cog`][cog], which replaces parts of files with the output of commented shell scripts.
If you can guaruntee `cog` and a compatible verion of python are in your development environment, you should use `cog`!
Python snippets tend to be more readable than shell snippets, and so tend to be easier to maintain.

You should consider using a more robust templating system if you care about performance and want better guarantees about inserting values.

If you want to intergrate with your compiler, consider looking for a native way to embed text in files.
For example, rust has `include_str!("file")` and go has `//go:embed`
<!-- TODO: link -->

You should use `shout` when you don't have access to python, don't want to pull python into your development/CI environment, don't want to depend on `cog`, and don't care about performance or compile-time correctness.


<!-- comments -->
[cog]: https://cog.readthedocs.io/en/latest/
