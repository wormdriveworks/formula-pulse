# 플랫폼 예외 시나리오 TC-P (D14 §7) — 전 플랫폼 항목의 헤드리스 자동화분.
# 실행: godot --headless --path godot --script tests/test_tc_p.gd
#
# 대상: TC-P8 세이브 손상 → 백업 1세대 복구 / TC-P9 마이그레이션 · 클라우드 충돌 정책 ·
#       프로필 3 독립성. (TC-P1~P7·P10·P11 = 모바일 광고·스토어 제출물 전제 — MS-2 범위 외)
extends SceneTree

var _failures := 0
var _checked := 0


func _init() -> void:
	_configure()
	_clean_profiles()
	_tc_p8_corruption_recovery()
	_tc_p9_migration()
	_tc_p9_conflict_policy()
	_tc_p9_profile_isolation()
	_snapshot_is_single_use()
	_profile_range_enforced()
	_backup_never_takes_corrupt_primary()
	_progress_counter_monotonic()
	_disk_envelope_end_to_end()
	_paths_are_distinct()
	_counter_survives_corruption()
	_not_configured_is_distinct()
	_clean_profiles()
	print("")
	# 검사 수 하한 — 클래스 로드 실패 등으로 스위트가 쪼그라들면 "통과"가 아니다.
	# 실행되지 않은 검사와 통과한 검사를 구분하는 유일한 수단이다.
	if _checked < 110:
		print("TC_P_TEST_FAIL checks=%d < 하한 110 (스위트 축소·로드 실패 의심)" % _checked)
		quit(1)
		return
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
	# 범위 밖 인덱스까지 지운다. 사본 프로젝트도 같은 user:// 디렉토리를 공유하므로
	# 다른 실행이 남긴 profile_-1·profile_9 류가 '미생성' 단언을 오염시킨다.
	for profile_index in range(-2, 12):
		SaveService.delete_save(SaveManager.progress_path(profile_index))
		SaveService.delete_save(SaveManager.backup_path(profile_index))
		SaveService.delete_save(SaveManager.snapshot_path(profile_index))
		SaveService.delete_save(SaveManager.quarantine_path(profile_index))


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


# SaveManager는 설정된 프로필 범위 밖의 저장·로드를 거부해야 한다.
func _configure() -> void:
	var data := GameData.new()
	if not data.load_all():
		_failures += 1
		print("  [FAIL] data load")
		return
	SaveManager.configure(data)


# ── 프로필 범위 강제 (독립 검증: 범위 밖 프로필 디렉토리가 실제로 생성됐다) ──
# is_valid_profile()의 정확성만 검사하면 '강제되는가'는 무검증이다 — 강제를 직접 시험한다.
func _profile_range_enforced() -> void:
	var data := GameData.new()
	if not data.load_all():
		return
	var count := data.param_int("param_save_profile_count")
	for invalid_index in [0, -1, count + 1, count + 6]:
		var result := SaveManager.save_progress(invalid_index, {"lap": 1})
		_ok("범위 밖 프로필 %d 저장 거부" % invalid_index,
			not bool(result["ok"]) and String(result["error"]) == "profile_out_of_range", str(result))
		_ok("범위 밖 프로필 %d 파일 미생성" % invalid_index,
			not FileAccess.file_exists(SaveManager.progress_path(invalid_index)))
		var loaded := SaveManager.load_progress(invalid_index)
		_ok("범위 밖 프로필 %d 로드 거부" % invalid_index,
			not bool(loaded["ok"]) and String(loaded["error"]) == "profile_out_of_range", str(loaded))
		_ok("범위 밖 프로필 %d 스냅샷 거부" % invalid_index,
			not SaveManager.save_snapshot(invalid_index, {"lap": 1}))


# ── 백업 회전이 손상본을 백업 슬롯에 올리지 않는다 ──
# 자동 저장 단일 모델에서는 손상을 모른 채 다음 GP를 끝내면 자동 저장이 일어난다.
# 그 저장이 손상본을 백업으로 회전하면, 방금 복구에 쓴 유일한 성한 세대가 사라진다.
func _backup_never_takes_corrupt_primary() -> void:
	_clean_profiles()
	SaveManager.save_progress(1, {"lap": 1, "marker": "good_A"})
	SaveManager.save_progress(1, {"lap": 1, "marker": "good_B"})
	_ok("손상 전 백업 = good_A",
		String(Dictionary(SaveManager._load_and_migrate(SaveManager.backup_path(1))["payload"]).get("marker", "")) == "good_A")
	_ok("정본 훼손 주입", _corrupt(SaveManager.progress_path(1)))
	var recovered := SaveManager.load_progress(1)
	_ok("백업 복구 성립", bool(recovered["ok"]) and String(recovered["source"]) == "backup", str(recovered.get("source")))
	# 손상 상태에서 자동 저장이 일어난다
	var saved := SaveManager.save_progress(1, {"lap": 2, "marker": "good_C"})
	_ok("손상 상태 저장 성립", bool(saved["ok"]), str(saved))
	_ok("손상본을 백업으로 회전하지 않음", not bool(saved["backup_rotated"]), str(saved))
	_ok("회전 보류 사유 기록", String(saved["backup_kept_reason"]) == "checksum_mismatch",
		str(saved.get("backup_kept_reason")))
	var backup_after := SaveManager._load_and_migrate(SaveManager.backup_path(1))
	_ok("백업이 성한 세대로 남아 있다", bool(backup_after["ok"])
		and String(Dictionary(backup_after["payload"]).get("marker", "")) == "good_A",
		str(backup_after.get("payload")))
	# 그 다음 손상도 여전히 복구 가능하다 (복구 창이 닫히지 않았다)
	_ok("2차 훼손 주입", _corrupt(SaveManager.progress_path(1)))
	var recovered2 := SaveManager.load_progress(1)
	_ok("복구 창 유지", bool(recovered2["ok"]) and String(recovered2["source"]) == "backup", str(recovered2))


# ── 진행도 카운터 단조 증가 (충돌 정책 1차 축의 실효) ──
# 호출 층이 카운터 없는 payload를 반복 저장해도 디스크 값이 올라가야 한다.
func _progress_counter_monotonic() -> void:
	_clean_profiles()
	var previous := 0
	for iteration in range(5):
		var result := SaveManager.save_progress(1, {"lap": iteration + 1})
		_ok("저장 %d회차 성립" % (iteration + 1), bool(result["ok"]), str(result))
		var counter := int(result["progress_counter"])
		_ok("카운터 단조 증가 (%d → %d)" % [previous, counter], counter == previous + 1,
			"counter=%d previous=%d" % [counter, previous])
		previous = counter
		var loaded := SaveManager.load_progress(1)
		_ok("디스크 카운터 일치 %d" % counter,
			int(Dictionary(loaded["payload"]).get("progress_counter", -1)) == counter,
			str(loaded.get("payload")))
	_ok("저장 결과가 갱신된 payload를 돌려준다",
		int(Dictionary(SaveManager.save_progress(1, {"lap": 9})["payload"]).get("progress_counter", -1)) == previous + 1)
	# 내용이 다른데 진행도·시각이 동률이면 자동 폐기하지 않는다 (체크섬 축)
	_ok("동률 + 내용 상이 = 사용자 선택",
		SaveManager.resolve_cloud_conflict(
			{"progress_counter": 4, "saved_at": 100, "content_checksum": "aaa"},
			{"progress_counter": 4, "saved_at": 100, "content_checksum": "bbb"}) == SaveManager.ConflictChoice.ASK)
	_ok("동률 + 내용 동일 = 전송 불요",
		SaveManager.resolve_cloud_conflict(
			{"progress_counter": 4, "saved_at": 100, "content_checksum": "aaa"},
			{"progress_counter": 4, "saved_at": 100, "content_checksum": "aaa"}) == SaveManager.ConflictChoice.LOCAL)


# ── 디스크 봉투 → 마이그레이션 결선 (migrate()를 직접 부르는 검사로는 볼 수 없는 축) ──
# SaveService.save_to는 항상 최신 판번을 적으므로, 구버전 봉투를 손으로 만들어 놓고
# load_progress가 그것을 읽어 마이그레이션하는지 확인한다.
func _disk_envelope_end_to_end() -> void:
	_clean_profiles()
	SaveManager.ensure_profile_dir(1)
	var v1_payload := {"lap": 3, "sector": 2, "marker": "legacy"}
	var payload_json := JSON.stringify(v1_payload, "", true)
	var envelope := {
		"schema_version": 1,
		"checksum": payload_json.md5_text(),
		"payload_json": payload_json,
	}
	var file := FileAccess.open(SaveManager.progress_path(1), FileAccess.WRITE)
	if file == null:
		_failures += 1
		print("  [FAIL] cannot write legacy envelope")
		return
	file.store_string(JSON.stringify(envelope, "", true))
	file.close()
	var loaded := SaveManager.load_progress(1)
	_ok("디스크 v1 봉투 로드 성립", bool(loaded["ok"]), str(loaded.get("error")))
	_ok("마이그레이션 출처 판번 기록", int(loaded["migrated_from"]) == 1,
		"migrated_from=%s" % str(loaded.get("migrated_from")))
	var payload: Dictionary = loaded["payload"]
	_ok("v1 → 최신 필드 전량 충전",
		payload.has("resonance_sector_slot") and payload.has("resonance_circuit_id")
		and payload.has("resonance_consumed"), str(payload))
	_ok("원 내용 보존", String(payload.get("marker", "")) == "legacy" and int(payload.get("lap", 0)) == 3,
		str(payload))
	# 상위 판번 봉투는 손상이 아니라 '너무 새 버전'으로 구분 보고된다
	var future_envelope := {
		"schema_version": SaveManager.SCHEMA_VERSION + 5,
		"checksum": payload_json.md5_text(),
		"payload_json": payload_json,
	}
	var file2 := FileAccess.open(SaveManager.progress_path(2), FileAccess.WRITE)
	if file2 != null:
		file2.store_string(JSON.stringify(future_envelope, "", true))
		file2.close()
	var future := SaveManager.load_progress(2)
	_ok("상위 판번 = version_too_new (손상과 구분)",
		not bool(future["ok"]) and String(future["source"]) == "version_too_new", str(future))


# ── 경로 분리 — 스냅샷이 진행 세이브를 덮지 않는다 ──
func _paths_are_distinct() -> void:
	_ok("파일명 4종 상호 구분", SaveManager.paths_are_distinct())
	var seen: Dictionary = {}
	for path in [SaveManager.progress_path(1), SaveManager.backup_path(1),
			SaveManager.snapshot_path(1), SaveManager.quarantine_path(1)]:
		_ok("경로 유일: %s" % path, not seen.has(path), path)
		seen[path] = true
	# 손상 스냅샷은 삭제가 아니라 격리된다 (진단 가능 + 재소비 불가)
	_clean_profiles()
	SaveManager.save_snapshot(1, {"lap": 1, "marker": "suspend"})
	_ok("스냅샷 훼손 주입", _corrupt(SaveManager.snapshot_path(1)))
	var consumed := SaveManager.consume_snapshot(1)
	_ok("손상 스냅샷 소비 실패 보고", not bool(consumed["ok"]), str(consumed))
	_ok("손상 스냅샷 재소비 불가", not SaveManager.has_snapshot(1))
	_ok("손상 스냅샷 격리 보존", FileAccess.file_exists(SaveManager.quarantine_path(1)))
	SaveService.delete_save(SaveManager.quarantine_path(1))


# ── 손상 복구가 진행도 카운터를 후퇴시키지 않는다 ──
# 정본이 손상되면 그 값을 신뢰할 수 없어 0이 되는데, 백업을 보지 않으면 카운터가 후퇴한다.
# 후퇴한 카운터는 클라우드 충돌에서 최신 진행을 뒤진 것으로 오판하게 만든다.
func _counter_survives_corruption() -> void:
	_clean_profiles()
	var counter := 0
	for iteration in range(3):
		counter = int(SaveManager.save_progress(1, {"lap": iteration + 1})["progress_counter"])
	_ok("손상 전 카운터 = 3", counter == 3, "counter=%d" % counter)
	_ok("손상 주입", _corrupt(SaveManager.progress_path(1)))
	var after := SaveManager.save_progress(1, {"lap": 9})
	_ok("손상 상태 저장 성립", bool(after["ok"]), str(after))
	# 백업은 한 세대 뒤지므로 손상 후 카운터의 '증가'까지 보장되지는 않는다.
	# 방어 대상은 **후퇴**다 — 백업을 보지 않던 버그 상태에서는 3 → 1로 떨어졌다.
	_ok("카운터가 후퇴하지 않는다", int(after["progress_counter"]) >= counter,
		"after=%d before=%d" % [int(after["progress_counter"]), counter])
	# 후퇴하면 충돌 판정이 원격을 최신으로 오판한다 — 그 귀결까지 확인한다
	var local := {"progress_counter": int(after["progress_counter"]), "saved_at": 100}
	var remote := {"progress_counter": counter, "saved_at": 90}
	_ok("복구 후에도 로컬이 최신으로 판정",
		SaveManager.resolve_cloud_conflict(local, remote) == SaveManager.ConflictChoice.LOCAL,
		"local=%s remote=%s" % [str(local), str(remote)])


# ── configure() 미호출은 '범위 밖'과 구분돼야 한다 ──
# 같은 코드로 보고하면 호출 층이 "프로필 번호가 잘못됐다"고 읽고 설정 누락을 영원히 못 찾는다.
func _not_configured_is_distinct() -> void:
	SaveManager._profile_count = 0
	var save_result := SaveManager.save_progress(1, {"lap": 1})
	_ok("미설정 저장 거부", not bool(save_result["ok"]))
	_ok("미설정 오류 코드 = not_configured", String(save_result["error"]) == "not_configured",
		String(save_result["error"]))
	var load_result := SaveManager.load_progress(1)
	_ok("미설정 로드 오류 코드 = not_configured", String(load_result["error"]) == "not_configured",
		String(load_result["error"]))
	_configure()
	var valid := SaveManager.save_progress(1, {"lap": 1})
	_ok("설정 후 정상 저장", bool(valid["ok"]), str(valid))
	SaveManager._profile_count = 0
	var out_of_range_probe := SaveManager.save_progress(99, {"lap": 1})
	_ok("미설정 상태에서는 범위 밖도 not_configured로 보고",
		String(out_of_range_probe["error"]) == "not_configured", String(out_of_range_probe["error"]))
	_configure()
	var real_out_of_range := SaveManager.save_progress(99, {"lap": 1})
	_ok("설정 후 범위 밖 = profile_out_of_range",
		String(real_out_of_range["error"]) == "profile_out_of_range", String(real_out_of_range["error"]))
	_clean_profiles()
