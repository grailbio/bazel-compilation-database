Compilation database with Bazel [![Tests](https://github.com/grailbio/bazel-compilation-database/actions/workflows/tests.yml/badge.svg)](https://github.com/grailbio/bazel-compilation-database/actions/workflows/tests.yml) [![Migration](https://github.com/grailbio/bazel-compilation-database/actions/workflows/migration.yml/badge.svg)](https://github.com/grailbio/bazel-compilation-database/actions/workflows/migration.yml)
===============================

If you use [Bazel][bazel] and want to use libclang based editors and tools, you
can now generate [JSON compilation database][compdb] easily without using build
intercept hooks.  The advantage is that you can generate the database even if
your source code does not compile, and the generation process is much faster.

For more information on compilation database, [Guillaume Papin][sarcasm] has an
[excellent article][compdb2].

## How to Use

### Entire repo

Running generate.py script from this project with current directory somewhere
in your bazel workspace will generate a compile_commands.json file in the
top-level directory of your workspace. You can even symlink the script to
somewhere in your PATH.

For example,
```sh
INSTALL_DIR="/usr/local/bin"
VERSION="0.5.1"

# Download and symlink.
(
  cd "${INSTALL_DIR}" \
  && curl -L "https://github.com/grailbio/bazel-compilation-database/archive/${VERSION}.tar.gz" | tar -xz \
  && ln -f -s "${INSTALL_DIR}/bazel-compilation-database-${VERSION}/generate.py" bazel-compdb
)

bazel-compdb # This will generate compile_commands.json in your workspace root.

# To pass additional flags to bazel, pass the flags as arguments after --
bazel-compdb -- [additional flags for bazel]

# You can tweak some behavior with flags:
# 1. To use the source dir instead of bazel-execroot for directory in which clang commands are run.
bazel-compdb -s
bazel-compdb -s -- [additional flags for bazel]
# 2. To consider only targets given by a specific query pattern, say `//cc/...`. Also see below section for another way.
bazel-compdb -q //cc/...
bazel-compdb -q //cc/... -- [additional flags for bazel]
```

### Selected targets

You can define a target of rule type `compilation_database` with the attribute
`targets` as a list of top-level `cc_.*` labels which you want to include in
your compilation database. You do not need to include targets that are
dependencies of your top-level targets. So these will mostly be targets of type
`cc_binary` and `cc_test`.

For example,

In your WORKSPACE file:
```python
http_archive(
    name = "com_grail_bazel_compdb",
    strip_prefix = "bazel-compilation-database-0.5.1",
    urls = ["https://github.com/grailbio/bazel-compilation-database/archive/0.5.1.tar.gz"],
)

load("@com_grail_bazel_compdb//:deps.bzl", "bazel_compdb_deps")
bazel_compdb_deps()
```

In your BUILD file located in any package:
```python
## Replace workspace_name and dir_path as per your setup.
load("@com_grail_bazel_compdb//:defs.bzl", "compilation_database")
load("@com_grail_bazel_output_base_util//:defs.bzl", "OUTPUT_BASE")

compilation_database(
    name = "example_compdb",
    targets = [
        "//a_cc_binary_label",
        "//a_cc_library_label",
    ],
    # OUTPUT_BASE is a dynamic value that will vary for each user workspace.
    # If you would like your build outputs to be the same across users, then
    # skip supplying this value, and substitute the default constant value
    # "__OUTPUT_BASE__" through an external tool like `sed` or `jq` (see
    # below shell commands for usage).
    output_base = OUTPUT_BASE,
)
```

Then, in your terminal (you can wrap this in a shell script and check it in your repo):
```
# Command to generate the compilation database file.
bazel build //path/to/pkg/dir:example_compdb

# Location of the compilation database file.
outfile="$(bazel info bazel-bin)/path/to/pkg/dir/compile_commands.json"

# [Optional] Command to replace the marker for output_base in the file if you
# did not use the dynamic value in the example above.
output_base=$(bazel info output_base)
sed -i.bak "s@__OUTPUT_BASE__@${output_base}@" "${outfile}"

# The compilation database is now ready to use at this location.
echo "Compilation Database: ${outfile}"
```

### YouCompleteMe

If you want to use this project solely for semantic auto completion using
[ycmd][ycm] (YouCompleteMe) based editor plugins, then the easiest approach
is to install this project as a vim plugin with your favourite plugin manager.
The plugin will set `g:ycm_global_ycm_extra_conf` and instrument bazel with
the correct paths.
e.g. Using Plugged add the following to your vimrc.
```
Plug 'grailbio/bazel-compilation-database'
```

An alternative approach is to follow the instructions as above for making the
files available in this repo somewhere in the workspace, and then configure vim
to use the `.ycm_extra_conf.py` script that you just extracted. One way is to
make a symlink to the py script from the top of your workspace root. Another
way is to set the `ycm_global_ycm_extra_conf` variable in vim.

With both of these approaches, you don't have to maintain a separate
compile_commands.json file through a script and/or a `compilation_database`
target. Compile commands are fetched from bazel as the files are opened in your
editor.

## Contributing

Contributions are most welcome. Please submit a pull request giving the owners
of this github repo access to your branch for minor style related edits, etc.

## Known Issues

Please check open issues at the github repo.

We have tested only for C and C++ code, and with tools like
[YouCompleteMe][ycm], [rtags][rtags], and the [woboq code browser][woboq].

## Alternatives

1. [Kythe][kythe]: uses Bazel action listeners
1. [Bear][bear]: uses build intercept hooks

These approaches could be more accurate than the approach of this tool in some
rare cases, but need a more complicated setup and a full build every time you
refresh the database.

[bazel]: https://bazel.build/
[compdb]: https://clang.llvm.org/docs/JSONCompilationDatabase.html
[sarcasm]: https://github.com/Sarcasm
[compdb2]: https://sarcasm.github.io/notes/dev/compilation-database.html
[cla]: https://www.clahub.com/pages/why_cla
[ycm]: https://github.com/Valloric/YouCompleteMe
[rtags]: https://github.com/Andersbakken/rtags
[woboq]: https://github.com/woboq/woboq_codebrowser
[kythe]: https://github.com/google/kythe/blob/master/tools/cpp/generate_compilation_database.sh
[bear]: https://github.com/rizsotto/Bear
