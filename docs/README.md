# Docs

Documentation source for imp, built with `mdbook`.

## Development

```sh
nix run .#docs        # serve with live reload
nix run .#build-docs  # build to ./docs
```

Both commands auto-generate the reference documentation before building.

## Auto-generated Reference

The following files are generated automatically using [nixdoc](https://github.com/nix-community/nixdoc):

- `src/reference/methods.md` - API methods from doc-comments in `src/*.nix`
- `src/reference/options.md` - Module options from `src/options-schema.nix`

### How it works

**Methods documentation** is extracted from doc-comments (`/** ... */`) in `src/*`.

The standalone utilities use nixdoc's `--export` flag to document specific let bindings.

**Options documentation** uses nixdoc's `options` subcommand to render module options from `src/options-schema.nix`.

### Manual building

```sh
nix build .#api-reference
```
