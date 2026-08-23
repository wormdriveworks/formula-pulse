# MS-1 완료 판정 3 검증 — 세이브 → 재로드 → 동일 릴 결과 재현 (스커밍 무효, D12 §6.2).
# 실행: godot --headless --path godot --script tests/test_save_reload.gd
extends SceneTree

const SNAPSHOT_PATH := "user://test_suspend_snapshot.json"


func _init() -> void:
	SaveManager.use_test_root()   # 저장 격리 — 실 프로필 무접촉 (25차)
	var failures := 0
	failures += _test_reel_reproduction()
	failures += _test_checksum_guard()
	if failures == 0:
		print("SAVE_RELOAD_TEST_PASS")
		quit(0)
	else:
		print("SAVE_RELOAD_TEST_FAIL failures=", failures)
		quit(1)


func _test_reel_reproduction() -> int:
	var data := GameData.new()
	if not data.load_all():
		print("FAIL data load")
		return 1
	var rng := RngService.new()
	rng.setup(20260810)
	var engine := RaceEngine.new()
	engine.setup(data, rng)
	engine.start_gp()
	# 3턴 진행 후 T1 시점 스냅샷
	for i in range(3):
		engine.begin_turn()
		engine.spin()
		engine.timeout()
	engine.begin_turn()
	if not SaveService.save_to(SNAPSHOT_PATH, engine.serialize()):
		print("FAIL snapshot save")
		return 1
	engine.spin()
	var original: Array = engine.get_provisional()
	# 재로드 — 별도 인스턴스로 복원 (재로드 리롤 무효 검증)
	var loaded := SaveService.load_from(SNAPSHOT_PATH)
	if not loaded["ok"]:
		print("FAIL snapshot load: ", loaded["error"])
		return 1
	var rng2 := RngService.new()
	var engine2 := RaceEngine.new()
	engine2.setup(data, rng2)
	if not engine2.restore(loaded["payload"]):
		print("FAIL restore")
		return 1
	engine2.spin()
	var replayed: Array = engine2.get_provisional()
	if original != replayed:
		print("FAIL reel mismatch: ", original, " vs ", replayed)
		return 1
	print("REEL_REPRODUCED ", original)
	# 스냅샷 1회성 소거 (D12 §7.2)
	SaveService.delete_save(SNAPSHOT_PATH)
	if FileAccess.file_exists(SNAPSHOT_PATH):
		print("FAIL snapshot not deleted")
		return 1
	return 0


func _test_checksum_guard() -> int:
	var payload := {"probe": 1}
	SaveService.save_to(SNAPSHOT_PATH, payload)
	# 손상 주입
	var file := FileAccess.open(SNAPSHOT_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	text = text.replace("probe", "xrobe")
	file = FileAccess.open(SNAPSHOT_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var loaded := SaveService.load_from(SNAPSHOT_PATH)
	SaveService.delete_save(SNAPSHOT_PATH)
	if loaded["ok"] or String(loaded["error"]) != "checksum_mismatch":
		print("FAIL checksum guard: ", loaded)
		return 1
	print("CHECKSUM_GUARD_OK")
	return 0
