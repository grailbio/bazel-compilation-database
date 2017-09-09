Compilation database with Bazel
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
  git submodule add https://github.com/grailbio/bazel-compilation-database bazel-compdb
  bazel-compdb/generate.sh
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
    ]
)
```

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
