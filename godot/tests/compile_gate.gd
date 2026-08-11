# 컴파일 게이트 — 전 `.gd`를 실제로 로드해 파스 에러를 잡는다.
# 실행: godot --headless --path godot --script tests/compile_gate.gd
#
# 왜 필요한가: 클래스 하나가 파스 에러로 로드 실패해도 스위트는 "통과"로 보고될 수 있다.
# 로드 실패한 클래스의 호출은 `Nonexistent function`으로 끝나고 실패 카운터를 올리지 않으므로,
# **검사가 실행되지 않은 것과 통과한 것이 구분되지 않는다.** 실측된 사례: `save_manager.gd`가
# 파스 에러인 상태에서 TC-P 검사 수가 108 → 2로 붕괴했는데 `TESTS_PASS suites=6` · exit=0.
# 종료코드 자체가 거짓말을 하는 구간이므로, 컴파일 성립을 별도 게이트로 앞단에 둔다.
extends SceneTree

# 테스트 스크립트도 포함한다. 스위트 자체가 파스 에러면 "검사 0건 + 종료코드"로만 드러나므로
# 앞단에서 원인을 명확히 잡는 편이 낫다. 자기 자신만 제외한다(실행 중이므로 자명하게 정상).
const SKIP_PATHS := ["res://tests/compile_gate.gd"]


func _init() -> void:
	var scripts := _collect("res://")
	var failures: Array = []
	for path in scripts:
		# **load()만으로는 판정할 수 없다** — Godot 4.7의 load()는 파스 에러 스크립트에도
		# non-null을 돌려준다(실측: 정상 reload=0 / 파손 reload=43). 초기 구현이 이 때문에
		# 무동작이었고, 메인 씬 스크립트가 로드 불가인 상태로 전 게이트가 초록이었다.
		var script := load(path) as GDScript
		if script == null:
			failures.append("%s (load 실패)" % path)
		elif script.reload() != OK:
			failures.append("%s (파스 에러)" % path)
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
	for skip in SKIP_PATHS:
		if path == String(skip):
			return true
	return false
