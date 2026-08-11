# Vulpina

This project uses `AGENTS.md` as its single source of truth for build commands,
coding conventions, and development rules. All AI agents MUST read that file first.

See `AGENTS.md` for:

- Build commands (`make build` / `make test` / `make release` / `make clean`)
- Toolchain requirements (Swift 6.3+, Swift 6 language mode)
- `VN` prefix naming convention (VNView, VNWindow, VNApplication)
- Backend-agnostic core policy (no Wayland/X11 code in the core target)
- Coding conventions and testing requirements
- Verification checklist
