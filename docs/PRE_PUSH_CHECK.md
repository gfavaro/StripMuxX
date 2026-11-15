# Developer push quality gate

The repository provides an **opt-in** Git pre-push hook. It runs `make check`
before allowing a push. Install it once in a local clone:

```sh
python3 script/install_git_hooks.py
```

It refuses to overwrite an existing `pre-push` hook or an existing
`core.hooksPath` configuration. A deliberate, one-time emergency override is
`STRIPMUXX_SKIP_PREPUSH_CHECK=1 git push`; do not use this for normal development.
The hook is not automatically installed by cloning or pulling the repository.
CI is still required to enforce checks for all contributors.
