# 게이트 보조 — Godot 이 **실제로 쓰는** user:// 절대 경로를 찍는다.
# 실행: godot --headless --path godot --script tests/print_user_dir.gd
#
# **왜 물어보는가.** `run_tests.sh` 의 실 프로필 무접촉 대조는 경로를 손으로 적거나
# 환경 변수로 받으면 안 된다 — `GODOT_USER_DIR` 는 **Godot 이 모르는 이름**이고(실측:
# 값을 바꿔도 `OS.get_user_data_dir()` 는 불변), 그 변수를 신뢰하면 **스냅숏 경로만
# 옮겨져 실 파일은 그대로 변조되면서 대조는 녹색이 된다**(거짓 녹색).
# 그래서 경로의 정본을 엔진에게 묻는다 — 대조 대상과 기록 대상이 구조적으로 같아진다.
extends SceneTree


func _init() -> void:
	print("USER_DATA_DIR=%s" % OS.get_user_data_dir())
	quit(0)
