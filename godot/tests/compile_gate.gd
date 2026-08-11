# 컴파일 게이트 — 전 `.gd`를 실제로 로드해 파스 에러를 잡는다.
# 실행: godot --headless --path godot --script tests/compile_gate.gd
#
# 왜 필요한가: 클래스 하나가 파스 에러로 로드 실패해도 스위트는 "통과"로 보고될 수 있다.
# 로드 실패한 클래스의 호출은 `Nonexistent function`으로 끝나고 실패 카운터를 올리지 않으므로,
# **검사가 실행되지 않은 것과 통과한 것이 구분되지 않는다.** 실측된 사례: `save_manager.gd`가
# 파스 에러인 상태에서 TC-P 검사 수가 108 → 2로 붕괴했는데 `TESTS_PASS suites=6` · exit=0.
# 종료코드 자체가 거짓말을 하는 구간이므로, 컴파일 성립을 별도 게이트로 앞단에 둔다.
extends SceneTree

const SKIP_PREFIXES := ["res://tests/"]   # 테스트 스크립트는 각자 실행이 곧 컴파일 검사다


func _init() -> void:
	var scripts := _collect("res://")
	var failures: Array = []
	for path in scripts:
		var resource: Variant = load(path)
		if resource == null:
			failures.append(path)
	print("COMPILE_GATE scanned=%d" % scripts.size())
	if scripts.is_empty():
		print("COMPILE_GATE_FAIL no scripts found — 스캔 경로가 잘못됐다")
		quit(1)
		return
	if failures.is_empty():
		print("COMPILE_GATE_PASS scripts=%d" % scripts.size())
		quit(0)
	else:
		for path in failures:
			print("  [FAIL] compile: %s" % path)
		print("COMPILE_GATE_FAIL failures=%d" % failures.size())
		quit(1)


func _collect(dir_path: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full_path := dir_path + entry if dir_path.ends_with("/") else dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry.begins_with(".") and entry != "addons":
				found.append_array(_collect(full_path + "/"))
		elif entry.ends_with(".gd") and not _skipped(full_path):
			found.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


func _skipped(path: String) -> bool:
	for prefix in SKIP_PREFIXES:
		if path.begins_with(prefix):
			return true
	return false
