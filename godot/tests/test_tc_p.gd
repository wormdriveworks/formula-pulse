# 플랫폼 예외 시나리오 TC-P (D14 §7) — 전 플랫폼 항목의 헤드리스 자동화분.
# 실행: godot --headless --path godot --script tests/test_tc_p.gd
#
# 대상: TC-P8 세이브 손상 → 백업 1세대 복구 / TC-P9 마이그레이션 · 클라우드 충돌 정책 ·
#       프로필 3 독립성. (TC-P1~P7·P10·P11 = 모바일 광고·스토어 제출물 전제 — MS-2 범위 외)
extends SceneTree

var _failures := 0
var _checked := 0


func _init() -> void:
	_clean_profiles()
	_tc_p8_corruption_recovery()
	_tc_p9_migration()
	_tc_p9_conflict_policy()
	_tc_p9_profile_isolation()
	_snapshot_is_single_use()
	_clean_profiles()
	print("")
	if _failures == 0:
		print("TC_P_TEST_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("TC_P_TEST_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if not condition:
		_failures += 1
		print("  [FAIL] %s %s" % [label, detail])


func _clean_profiles() -> void:
	for profile_index in range(1, 5):
		SaveService.delete_save(SaveManager.progress_path(profile_index))
		SaveService.delete_save(SaveManager.backup_path(profile_index))
		SaveService.delete_save(SaveManager.snapshot_path(profile_index))


# 정본을 훼손해 체크섬 불일치를 만든다 (D14 TC-P8 '체크섬 불일치 파일 주입').
# 봉투를 파싱해 payload_json 본문만 바꾸고 checksum 필드는 그대로 둔다 —
# JSON 표기(들여쓰기·수치 표기)에 의존하지 않으므로 직렬화 방식이 바뀌어도 성립한다.
func _corrupt(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var envelope: Dictionary = parsed
	if not envelope.has("payload_json"):
		return false
	envelope["payload_json"] = String(envelope["payload_json"]) + " "
	var target := FileAccess.open(path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_string(JSON.stringify(envelope, "", true))
	target.close()
	return true


# ── TC-P8 세이브 손상 — 백업 1세대 복구 성립 · 복구 불능 시 정의된 경로 ──
func _tc_p8_corruption_recovery() -> void:
	var first := {"lap": 1, "sector": 2, "marker": "generation_1"}
	var second := {"lap": 1, "sector": 3, "marker": "generation_2"}
	_ok("TC-P8 1세대 저장", bool(SaveManager.save_progress(1, first)["ok"]))
	var second_result := SaveManager.save_progress(1, second)
	_ok("TC-P8 2세대 저장", bool(second_result["ok"]))
	_ok("TC-P8 백업 회전 발생", bool(second_result["backup_rotated"]))
	# 정본이 정상일 때는 정본을 읽는다
	var healthy := SaveManager.load_progress(1)
	_ok("TC-P8 정상 로드 = 정본", bool(healthy["ok"]) and String(healthy["source"]) == "primary",
		str(healthy.get("source")))
	_ok("TC-P8 정본 내용 = 최신 세대",
		String(Dictionary(healthy["payload"]).get("marker", "")) == "generation_2",
		str(healthy["payload"]))
	# 정본을 훼손하면 체크섬 불일치가 감지돼야 한다
	_ok("TC-P8 훼손 주입", _corrupt(SaveManager.progress_path(1)))
	var direct := SaveService.load_from(SaveManager.progress_path(1))
	_ok("TC-P8 체크섬 불일치 감지", String(direct["error"]) == "checksum_mismatch", str(direct["error"]))
	# 백업 1세대로 복구된다
	var recovered := SaveManager.load_progress(1)
	_ok("TC-P8 백업 복구 성립", bool(recovered["ok"]), str(recovered))
	_ok("TC-P8 복구 출처 표기", String(recovered["source"]) == "backup", str(recovered.get("source")))
	_ok("TC-P8 복구 내용 = 직전 세대",
		String(Dictionary(recovered["payload"]).get("marker", "")) == "generation_1",
		str(recovered["payload"]))
	# 백업까지 잃으면 '복구 불능'이 명시된다 (침묵 성공 금지)
	SaveService.delete_save(SaveManager.backup_path(1))
	var unrecoverable := SaveManager.load_progress(1)
	_ok("TC-P8 복구 불능 명시", not bool(unrecoverable["ok"])
		and String(unrecoverable["source"]) == "unrecoverable", str(unrecoverable))
	# 세이브가 아예 없는 상태와 손상 상태는 구분돼야 한다 (신규 시작 vs 복구 안내)
	_clean_profiles()
	var missing := SaveManager.load_progress(1)
	_ok("TC-P8 미존재 = not_found", String(missing["error"]) == "not_found", str(missing))
	_ok("TC-P8 미존재 출처 = none", String(missing["source"]) == "none", str(missing.get("source")))


# ── TC-P9 마이그레이션 — 구버전 세이브 로드 정합 · 다운그레이드 거부 ──
func _tc_p9_migration() -> void:
	# 실주행 상태를 v1(레조넌스 필드 부재) 형태로 만들어 저장한다 = MS-1 세이브 재현
	var data := GameData.new()
	if not data.load_all():
		_failures += 1
		print("  [FAIL] data load")
		return
	var rng := RngService.new()
	rng.setup(4242)
	var engine := RaceEngine.new()
	engine.setup(data, rng)
	engine.start_gp()
	engine.begin_turn()
	var v2_payload := engine.serialize()
	var v1_payload := v2_payload.duplicate(true)
	v1_payload.erase("resonance_sector_slot")
	v1_payload.erase("resonance_announced")
	v1_payload.erase("resonance_duel_bonus")
	_ok("TC-P9 v1 재현 (필드 부재)", not v1_payload.has("resonance_sector_slot"))
	var migrated := SaveManager.migrate(v1_payload, 1)
	_ok("TC-P9 마이그레이션 성립", bool(migrated["ok"]), str(migrated.get("error")))
	var payload: Dictionary = migrated["payload"]
	_ok("TC-P9 신설 필드 충전", payload.has("resonance_sector_slot")
		and payload.has("resonance_announced") and payload.has("resonance_duel_bonus"))
	_ok("TC-P9 신설 필드 = 구조적 부재값", int(payload["resonance_sector_slot"]) == 0
		and not bool(payload["resonance_announced"]), str(payload.get("resonance_sector_slot")))
	# 마이그레이션된 payload로 엔진이 복원돼야 한다 (구버전 세이브가 살아난다)
	var restored := RaceEngine.new()
	restored.setup(data, RngService.new())
	_ok("TC-P9 구버전 세이브 복원", restored.restore(payload))
	_ok("TC-P9 복원 후 진행 상태 일치", restored.lap == engine.lap and restored.sector == engine.sector,
		"lap=%d sector=%d" % [restored.lap, restored.sector])
	# 다운그레이드 = 거부 (D12 §7.1 확정)
	var downgrade := SaveManager.migrate(v2_payload, SaveManager.SCHEMA_VERSION + 1)
	_ok("TC-P9 다운그레이드 거부", not bool(downgrade["ok"])
		and String(downgrade["error"]) == "downgrade_refused", str(downgrade))
	# 미등록 판번은 조용히 통과하지 않는다
	var unknown := SaveManager.migrate(v2_payload, 0)
	_ok("TC-P9 미등록 판번 거부", not bool(unknown["ok"]), str(unknown))


# ── TC-P9 클라우드 충돌 정책 (D12 §7.3) ──
func _tc_p9_conflict_policy() -> void:
	# 진행도 우선
	_ok("TC-P9 진행도 앞선 쪽 채택 (로컬)",
		SaveManager.resolve_cloud_conflict({"progress_counter": 5, "saved_at": 100},
			{"progress_counter": 3, "saved_at": 90}) == SaveManager.ConflictChoice.LOCAL)
	_ok("TC-P9 진행도 앞선 쪽 채택 (원격)",
		SaveManager.resolve_cloud_conflict({"progress_counter": 3, "saved_at": 90},
			{"progress_counter": 5, "saved_at": 100}) == SaveManager.ConflictChoice.REMOTE)
	# 진행도 동률 → 최신 타임스탬프
	_ok("TC-P9 동률 시 최신 타임스탬프",
		SaveManager.resolve_cloud_conflict({"progress_counter": 4, "saved_at": 200},
			{"progress_counter": 4, "saved_at": 100}) == SaveManager.ConflictChoice.LOCAL)
	_ok("TC-P9 동률 시 최신 타임스탬프 (원격)",
		SaveManager.resolve_cloud_conflict({"progress_counter": 4, "saved_at": 100},
			{"progress_counter": 4, "saved_at": 200}) == SaveManager.ConflictChoice.REMOTE)
	# 두 축이 어긋나면 사용자 선택 — 자동으로 한쪽을 지우지 않는다
	_ok("TC-P9 축 불일치 = 사용자 선택",
		SaveManager.resolve_cloud_conflict({"progress_counter": 5, "saved_at": 100},
			{"progress_counter": 3, "saved_at": 300}) == SaveManager.ConflictChoice.ASK)
	_ok("TC-P9 완전 동률 = 전송 불요",
		SaveManager.resolve_cloud_conflict({"progress_counter": 4, "saved_at": 100},
			{"progress_counter": 4, "saved_at": 100}) == SaveManager.ConflictChoice.LOCAL)


# ── TC-P9 프로필 3 독립성 — 한 프로필의 저장·손상이 다른 프로필에 닿지 않는다 ──
func _tc_p9_profile_isolation() -> void:
	var data := GameData.new()
	if not data.load_all():
		_failures += 1
		print("  [FAIL] data load")
		return
	var profile_count := data.param_int("param_save_profile_count")
	_ok("TC-P9 프로필 수 3 (D12 §7.1)", profile_count == 3, "count=%d" % profile_count)
	_ok("TC-P9 프로필 범위 하한", not SaveManager.is_valid_profile(data, 0))
	_ok("TC-P9 프로필 범위 상한", not SaveManager.is_valid_profile(data, profile_count + 1))
	for profile_index in range(1, profile_count + 1):
		_ok("TC-P9 프로필 %d 유효" % profile_index, SaveManager.is_valid_profile(data, profile_index))
		_ok("TC-P9 프로필 %d 저장" % profile_index,
			bool(SaveManager.save_progress(profile_index, {"lap": 1, "owner": "profile_%d" % profile_index})["ok"]))
	# 경로가 프로필별로 갈라져 있는지 (같은 파일을 공유하면 독립성이 성립하지 않는다)
	var seen: Dictionary = {}
	for profile_index in range(1, profile_count + 1):
		var path := SaveManager.progress_path(profile_index)
		_ok("TC-P9 프로필 %d 경로 유일" % profile_index, not seen.has(path), path)
		seen[path] = true
	# 각 프로필이 자기 내용을 읽는다
	for profile_index in range(1, profile_count + 1):
		var loaded := SaveManager.load_progress(profile_index)
		_ok("TC-P9 프로필 %d 내용 독립" % profile_index,
			bool(loaded["ok"]) and String(Dictionary(loaded["payload"]).get("owner", "")) == "profile_%d" % profile_index,
			str(loaded.get("payload")))
	# 프로필 2를 손상시켜도 1·3은 무영향
	_ok("TC-P8 프로필 2 훼손", _corrupt(SaveManager.progress_path(2)))
	SaveService.delete_save(SaveManager.backup_path(2))
	var broken := SaveManager.load_progress(2)
	_ok("TC-P9 프로필 2 손상 감지", not bool(broken["ok"]), str(broken))
	for profile_index in [1, 3]:
		var other := SaveManager.load_progress(profile_index)
		_ok("TC-P9 프로필 %d 무영향" % profile_index,
			bool(other["ok"]) and String(Dictionary(other["payload"]).get("owner", "")) == "profile_%d" % profile_index,
			str(other.get("payload")))


# ── 서스펜드 스냅샷 1회성 (D12 §7.2 · §6.2 스커밍 무효) ──
func _snapshot_is_single_use() -> void:
	var payload := {"lap": 1, "sector": 1, "marker": "suspend"}
	_ok("스냅샷 저장", SaveManager.save_snapshot(1, payload))
	_ok("스냅샷 존재", SaveManager.has_snapshot(1))
	var first := SaveManager.consume_snapshot(1)
	_ok("스냅샷 1회 소비 성립", bool(first["ok"]), str(first))
	_ok("스냅샷 소비 후 소거", not SaveManager.has_snapshot(1))
	var second := SaveManager.consume_snapshot(1)
	_ok("스냅샷 재소비 불가", not bool(second["ok"]), str(second))
