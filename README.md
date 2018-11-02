Compilation database with Bazel [![Build Status](https://travis-ci.org/grailbio/bazel-compilation-database.svg?branch=master)](https://travis-ci.org/grailbio/bazel-compilation-database)
===============================

If you use [Bazel][bazel] and want to use libclang based editors and tools, you
can now generate [JSON compilation database][compdb] easily without using build
intercept hooks.  The advantage is that you can generate the database even if
your source code does not compile, and the generation process is much faster.

For more information on compilation database, [Guillaume Papin][sarcasm] has an
[excellent article][compdb2].

How to Use
----------

Make the files in this github repo available somewhere in your repo, and run
the `generate.sh` script.  This will create a `compile_commands.json` file at
your workspace root. For example,

```sh
RELEASE_VERSION=0.3.0
curl -L https://github.com/grailbio/bazel-compilation-database/archive/${RELEASE_VERSION}.tar.gz | tar -xz
bazel-compilation-database-${RELEASE_VERSION}/generate.sh
```

An alternative to running the `generate.sh` script is to define a target of
rule type `compilation_database` with the attribute `targets` as a list of
top-level `cc_.*` labels which you want to include in your compilation database. 
For example,

```python
## Replace workspace_name and dir_path as per your setup.
load("@workspace_name//dir_path:aspects.bzl", "compilation_database")

compilation_database(
    name = "example_compdb",
    targets = [
        "//a_cc_binary_label",
        "//a_cc_library_label",
    ],
    # ideally should be the same as `bazel info execution_root`.
    exec_root = "/path/to/bazel/exec_root",
)
```

ycmd
----
If you want to use this project solely for semantic auto completion using
[ycmd][ycm] (YouCompleteMe) based editor plugins, then the recommended approach
is to set your extra conf script to the bundled .ycm_extra_conf.py. With this,
you don't have to maintain a separate compile_commands.json file through a
script and/or a `compilation_database` target. Compile commands are fetched
from bazel as the files are opened in your editor.

Follow the instructions as above for making the files available in this repo
somewhere in the workspace, and then configure vim to use the
`.ycm_extra_conf.py` script that you just extracted. One way is to make a
symlink to the py script from the top of your workspace root. Another way is to
set the `ycm_global_ycm_extra_conf` variable in vim.

Contributing
------------

Contributions are most welcome. Please submit a pull request giving the owners
of this github repo access to your branch for minor style related edits, etc.

Known Issues
------------

Please check open issues at the github repo.

We have tested only for C and C++ code, and with tools like
[YouCompleteMe][ycm], [rtags][rtags], and the [woboq code browser][woboq].

Alternatives
------------

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
