#!/usr/bin/env bash
# TL-1 로컬 단일 명령 (원격 헤드리스/리눅스) — 빌드 전 단계 고정 (D12 §4.2)
set -euo pipefail
cd "$(dirname "$0")/../.."
godot --headless --path . --script tools/validators/run_validators.gd
