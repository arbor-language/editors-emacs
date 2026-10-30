# arbor-mode

An initial Emacs major mode for writing Arbor examples. Requires Emacs 27.1 or
newer; no packages, parser generators, language server, or compiler are needed.

## Load it

Add this to your Emacs configuration, adjusting the path:

```elisp
(add-to-list 'load-path "/path/to/arbor/editors/emacs")
(require 'arbor-mode)
```

Files ending in `.arb` then select `arbor-mode` automatically. For an existing
buffer, run `M-x arbor-mode` after loading the file.

To try the mode without changing your configuration, run this from the directory
containing this README:

```sh
emacs -Q -L . -l arbor-mode.el examples/showcase.arb
```

On macOS, if the `emacs` shell command is unavailable, evaluate the two setup
forms with `M-:` in your usual Emacs application, then open the example file.
Use a real absolute path for the directory in `load-path`.

## What works

* Highlighting for keywords, declarations, built-in types, constants, numbers,
  decorators, and function calls, using your existing Emacs theme.
* Ordinary double-quoted strings, triple-quoted strings, and prefixed literals
  such as `date'...'`, `instant'...'`, and `secret'...'`.
* Experimental `{expression}` interpolation in `term'...'`, `t'...'`, and
  `f"..."`, including nested literals, comments, and braces inside expressions.
* Separate highlighting for terminal controls such as `$bold` and `${red}`.
  These remain style controls; `${red}` is not a variable interpolation.
* `//` line comments and standard Emacs comment commands such as `M-;`.
* Basic bracket-based indentation, four spaces by default. Change
  `arbor-indent-offset` to customize it.

Open `examples/showcase.arb` to inspect the faces in your own theme. In particular,
try editing the quotes and braces in the nested timestamp example. Emacs should
continue to distinguish code from string contents as you type.

## Deliberate limits

This is an editing aid for an evolving language, not a parser or syntax checker.
It follows recent discussion where that is newer than `DESIGN.md`. Supporting an
experimental spelling here does not finalize the compiler grammar or APIs.

The mode does not implement completion, navigation, type checking, formatting,
or Tree-sitter integration. Indentation uses bracket depth rather than the full
grammar; it does not align continuation expressions. It preserves indentation
inside strings. Interpolation delimiters use Emacs string syntax properties, so
they do not participate in normal brace matching as code braces do.

Lexical properties and fontification are recomputed across the whole buffer on
edits. This keeps nested contexts understandable and is intended for small
example programs; incremental scanning can follow later.

The mode contains no project or dependency hooks and does not run Arbor code.
This directory can become the official Emacs tool submodule when its repository
and remote are created; it is currently an ordinary directory.

## Checks

The ERT tests cover faces, literal boundaries, nested interpolation, style
controls, edits, indentation, Unicode identifiers, and `.arb` file detection:

```sh
make test
make compile
```

For an application bundle on macOS, you can select its executable explicitly:

```sh
make test EMACS=/Applications/Emacs.app/Contents/MacOS/Emacs
```

The authoring environment does not currently have Emacs installed. The ERT tests
and byte compilation must therefore be run in an environment with Emacs before
this version can be considered verified.
