# Contributing to Ollama‑Llama3.2‑3G‑auto‑setup

Thank you for your interest in contributing! We welcome bug reports, feature
requests, documentation improvements and pull requests.

## Bug reports and feature requests

1. **Search first:** please search the [issue tracker](https://github.com/MarcusFunt/Ollama-Llama3.2-3G-auto-setup/issues)
   to see if your issue has already been reported. If not, open a new issue and
   provide as much detail as possible.
2. **Include context:** describe your environment (OS, Docker version, whether
   you have an NVIDIA GPU installed) and include the exact commands you ran
   and any relevant logs or error messages.
3. **Suggest improvements:** if you have ideas for new features or enhancements
   (for example, support for additional models), open a feature request and
   explain the use case.

## Pull requests

We love pull requests! Please follow these guidelines to make it easier for us
to review your changes:

1. **Fork the repository** and create a new branch for your changes.
2. **Commit atomically:** keep changes focused and describe what you’ve done in
   the commit message. If your changes address an open issue, reference it.
3. **Update documentation and tests** if you change behavior or introduce new
   functionality. The README and `.env.example` should reflect new options.
4. **Run the installer in a clean environment** (with and without NVIDIA GPU)
   to verify your changes. If you introduce new dependencies, please update
   the dependency checks in `install.sh` accordingly.
5. **Submit a pull request:** fill in the PR template and clearly describe
   why this change is needed. A maintainer will review your PR and may ask
   for additional information or changes.

Please be patient; maintainers review contributions in their spare time. We
appreciate your effort to improve the project!