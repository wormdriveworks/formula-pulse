# AGENTS.md

이 프로젝트의 AI 에이전트 규칙은 [`CLAUDE.md`](CLAUDE.md)에 있다. 모든 AI 도구는 그것을 먼저 읽는다.

**시작 전 반드시**: `echo "$DISPLAY$WAYLAND_DISPLAY"` 로 환경을 확인.
- 비어있음 → 원격 헤드리스 서버: 로직/스크립트/검증. MCP `godot`의 편집·`validate` 도구 + Bash `godot --headless`.
- 값 있음 → 주력 GUI 머신: 씬 구성·시각/런타임 검증. GDAI MCP + 에디터.

공통: Godot 4.7 계열 고정(D12 v1.1 §1.1) · `*.uid`·`*.import` 커밋 · `.godot/`·`.mcp/`·`.omc/` 무시 · 씬 소유권은 주력 머신 · 작업 전 `git pull`.
