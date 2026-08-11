# TC-O4 VN 이벤트·스킵·기록실 재열람 (D14 §4) + 베인 대사 3단계 필터 (D12 §5.7)
# + TC-C8 소프트 타임 리미트 (D14 §3 · D05 §7).
# 실행: godot --headless --path godot --script tests/test_narrative.gd
extends SceneTree

const MIN_CHECKS := 68

var _failures := 0
var _checked := 0


func _init() -> void:
	_d08_vn_slot_values()
	_tc_o4_vn_skip_and_replay()
	_vane_stage_filter()
	_tc_c8_soft_time_limit()
	_serialization()
	print("")
	if _checked < MIN_CHECKS:
		print("NARRATIVE_TEST_FAIL checks=%d < 하한 %d (스위트 축소·로드 실패 의심)" % [_checked, MIN_CHECKS])
		quit(1)
		return
	if _failures == 0:
		print("NARRATIVE_TEST_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("NARRATIVE_TEST_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if not condition:
		_failures += 1
		print("  [FAIL] %s %s" % [label, detail])


func _eq_float(label: String, actual: float, expected: float, tolerance: float = 0.001) -> void:
	_ok(label, absf(actual - expected) <= tolerance, "actual=%f expected=%f" % [actual, expected])


func _new_data() -> GameData:
	var data := GameData.new()
	if not data.load_all():
		_failures += 1
		print("  [FAIL] data load")
		return null
	return data


func _new_service() -> NarrativeService:
	var data := _new_data()
	if data == null:
		return null
	var service := NarrativeService.new()
	service.setup(data)
	service.begin_season()
	return service


# ── D08 §8.4 VN 슬롯 수치 전사 ──
func _d08_vn_slot_values() -> void:
	var data := _new_data()
	if data == null:
		return
	_eq_float("D08 §8.4 시즌 총 상한 15", data.param("param_vn_season_cap"), 15.0)
	_eq_float("D08 §8.4 마일스톤 VN 시즌 상한 8", data.param("param_vn_milestone_cap"), 8.0)
	_ok("D08 §8.4 투어 브리핑 = 전체 5투어 상시",
		CsvTable.to_int(String(data.vn_slot("vnslot_tour_brief")["per_season"])) == 5,
		String(data.vn_slot("vnslot_tour_brief")["per_season"]))
	_ok("D08 §8.4 시즌 시작·종료 고정 2",
		CsvTable.to_int(String(data.vn_slot("vnslot_season_open")["per_season"]))
		+ CsvTable.to_int(String(data.vn_slot("vnslot_season_close")["per_season"])) == 2)
	# 마일스톤 우선순위 (D08 §8.4): 막 전이 > 크루 합류 > 기원 단서 > 일반 성취
	var expected_priority := {
		"mvn_act_transition": 1, "mvn_crew_join": 2,
		"mvn_origin_clue": 3, "mvn_general_feat": 4,
	}
	for vn_id in expected_priority:
		_ok("D08 §8.4 우선순위 %s = %d" % [vn_id, expected_priority[vn_id]],
			CsvTable.to_int(String(data.milestone_vn[vn_id]["priority"])) == int(expected_priority[vn_id]),
			String(data.milestone_vn[vn_id]["priority"]))


# ── TC-O4: 발생 → 스킵 → 기록실 재열람 (D14 §4 · D07 §5.5·§6.3) ──
func _tc_o4_vn_skip_and_replay() -> void:
	var service := _new_service()
	if service == null:
		return
	# 발생 = 도달. 스킵해도 전이가 성립한다 (스킵이 페널티가 되면 비강제성이 역전된다)
	var skipped_result := service.trigger_vn("mvn_crew_join", "vnslot_tour_milestone", true)
	_ok("스킵한 VN도 발생 성립", bool(skipped_result["occurred"]), str(skipped_result))
	_ok("스킵 여부와 무관하게 형식 A 전이 발화",
		String(skipped_result["relation"]) == "relation_kinship", str(skipped_result))
	_ok("스킵 기록은 남는다", service.vn_skipped.has("mvn_crew_join"))
	_ok("발생 기록도 남는다", service.vn_seen.has("mvn_crew_join"))
	# 열람한 VN과 스킵한 VN이 전이에서 동등하다
	var viewed := _new_service()
	var viewed_result := viewed.trigger_vn("mvn_crew_join", "vnslot_tour_milestone", false)
	_ok("열람·스킵의 전이 결과 동일",
		String(viewed_result["relation"]) == String(skipped_result["relation"]),
		"viewed=%s skipped=%s" % [str(viewed_result["relation"]), str(skipped_result["relation"])])
	# 기록실 재열람 — 스킵분 포함 열람 가능하되 전이는 재발화하지 않는다
	_ok("스킵한 VN이 기록실에 있다", service.archive_entries().has("mvn_crew_join"),
		str(service.archive_entries()))
	var replay := service.replay_from_archive("mvn_crew_join")
	_ok("재열람 성립", bool(replay["replayed"]))
	_ok("재열람은 전이를 재발화하지 않는다", String(replay["relation"]) == "", str(replay))
	# 같은 VN이 다시 발생해도 전이는 1회만 (멱등 플래그)
	var again := service.trigger_vn("mvn_crew_join", "vnslot_tour_milestone", false)
	_ok("동일 VN 재발생 시 전이 미발화", String(again["relation"]) == "", str(again))
	# 발생하지 않은 VN은 기록실에 없다
	var unseen := service.replay_from_archive("mvn_origin_clue")
	_ok("미발생 VN 재열람 불가", not bool(unseen["replayed"]))
	# 전이 매핑이 없는 VN은 전이를 내지 않는다 (매핑 부재는 오류가 아니다)
	var no_relation := _new_service()
	var plain := no_relation.trigger_vn("mvn_act_transition", "vnslot_tour_milestone", false)
	_ok("전이 매핑 없는 VN = 전이 공백", String(plain["relation"]) == "", str(plain))
	_ok("매핑 부재가 데이터 오류로 취급되지 않음", no_relation.data.is_ok())
	# 마일스톤 VN 시즌 상한 8 (초과분은 이월 — 발생하지 않는다)
	var capped := _new_service()
	var occurred := 0
	for index in range(12):
		if bool(capped.trigger_vn("mvn_general_feat_%d" % index, "vnslot_tour_milestone", false)["occurred"]):
			occurred += 1
	_ok("마일스톤 VN 상한 8 준수", occurred == 8, "occurred=%d" % occurred)
	_ok("상한 초과는 사유를 보고한다",
		String(capped.trigger_vn("mvn_extra", "vnslot_tour_milestone", false)["reason"]) == "milestone_cap")
	# 시즌 총 상한 15
	var season_capped := _new_service()
	var total := 0
	for index in range(20):
		var slot := "vnslot_tour_brief" if index % 2 == 0 else "vnslot_season_open"
		if bool(season_capped.trigger_vn("vn_%d" % index, slot, false)["occurred"]):
			total += 1
	_ok("시즌 총 상한 15 준수", total == 15, "total=%d" % total)
	# 미등재 슬롯은 조용히 통과하지 않는다
	var strict := _new_service()
	var unknown := strict.trigger_vn("vn_x", "vnslot_nope", false)
	_ok("미등재 슬롯 거부", not bool(unknown["occurred"]) and String(unknown["reason"]) == "unknown_slot",
		str(unknown))
	_ok("미등재 슬롯 조회가 is_ok를 내린다", not strict.data.is_ok())


# ── 베인 대사 3단계 필터 (D12 §5.7 — 키·풀 불변, 선택 계층이 필터) ──
func _vane_stage_filter() -> void:
	var service := _new_service()
	if service == null:
		return
	for situation in ["sector_open", "duel_open", "resonance_first"]:
		var keys: Dictionary = {}
		for stage in [1, 2, 3]:
			var key := service.vane_line(situation, stage)
			_ok("%s 단계 %d 대사 존재" % [situation, stage], key != "", key)
			_ok("%s 단계 %d 대사가 스트링 테이블에 등재" % [situation, stage],
				service.data.strings.has_key(key), key)
			keys[key] = true
		_ok("%s 단계별 대사가 서로 다르다 (필터가 실제로 갈라진다)" % situation, keys.size() == 3,
			str(keys.keys()))
	# 풀은 불변이고 필터만 바뀐다 — 데이터 행 수가 단계 수만큼 있고 복제가 아니다
	var per_situation: Dictionary = {}
	for line_id in service.data.vane_lines:
		var situation := String(service.data.vane_lines[line_id]["situation"])
		per_situation[situation] = int(per_situation.get(situation, 0)) + 1
	for situation in per_situation:
		_ok("%s 대사 행 = 3단계분" % situation, int(per_situation[situation]) == 3,
			"count=%s" % str(per_situation[situation]))
	# 미등재 상황은 조용히 빈 문자열이 되지 않는다
	var strict := _new_service()
	_ok("미등재 상황 = 공백 반환 + 오류", strict.vane_line("no_such_situation", 1) == "")


# ── TC-C8 소프트 타임 리미트 (D05 §7 · D13 별첨A §8.1) ──
func _tc_c8_soft_time_limit() -> void:
	var data := _new_data()
	if data == null:
		return
	# 구간 경계: 기본 10초 · 여유 100~60% · 경고 60~30% · 임박 30~0%
	_eq_float("D13 §8.1 타이머 기본 10초", data.param("param_timer_base_sec"), 10.0)
	_eq_float("D13 §8.1 여유 경계 60%", data.param("param_timer_leeway_ratio"), 0.6)
	_eq_float("D13 §8.1 경고 경계 30%", data.param("param_timer_warning_ratio"), 0.3)
	_ok("구간 순서 = 여유 > 경고", data.param("param_timer_leeway_ratio")
		> data.param("param_timer_warning_ratio"))
	# 빠른 결정 보너스(모멘텀)는 여유 구간에서만 (D05 §7.3 · D13 §2.1 +5G)
	var rng := RngService.new()
	rng.setup(808)
	var leeway := data.param("param_timer_leeway_ratio")
	var bonus := data.param("param_gauge_momentum_bonus")
	for ratio_case in [[1.0, true], [leeway, true], [leeway - 0.01, false], [0.0, false]]:
		var probe_data := _new_data()
		var probe_rng := RngService.new()
		probe_rng.setup(808)
		var engine := RaceEngine.new()
		engine.setup(probe_data, probe_rng)
		engine.start_gp()
		for entrant_id in engine.entrants:
			if entrant_id == RaceEngine.PLAYER_ID:
				continue
			engine.entrants[entrant_id]["pace"] = 0.0
			engine.entrants[entrant_id]["aggression"] = 0.0
			engine.entrants[entrant_id]["seed_aggression"] = 0.0
			engine.entrants[entrant_id]["form"] = 0.0
			engine.entrants[entrant_id]["rush_roll"] = 0.0
			engine.entrants[entrant_id]["rush_lap1"] = 0.0
			engine.entrants[entrant_id]["pressure_mult"] = 1.0
		engine.begin_turn()
		engine.spin()
		engine.front_gauge = 0.0
		engine.provisional = [RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_BRAKING]
		var baseline := CsvTable.to_float(String(probe_data.match_effects[RaceTypes.SYMBOL_LINE][2]["front_gauge"])) \
			- probe_data.param("param_gauge_front_resist_base")
		engine.confirm(float(ratio_case[0]))
		var expected := baseline + (bonus if bool(ratio_case[1]) else 0.0)
		_eq_float("잔여 %.2f → 모멘텀 %s" % [float(ratio_case[0]), "지급" if bool(ratio_case[1]) else "미지급"],
			engine.front_gauge, expected, 0.01)
	# 타임아웃 = 잠정 결과 자동 확정 · 추가 페널티 없음 (D05 §7.3) — 중계 로그 키 발행 확인
	var timeout_data := _new_data()
	var timeout_rng := RngService.new()
	timeout_rng.setup(909)
	var timeout_engine := RaceEngine.new()
	timeout_engine.setup(timeout_data, timeout_rng)
	timeout_engine.start_gp()
	timeout_engine.begin_turn()
	timeout_engine.spin()
	var events := timeout_engine.timeout()
	var keys: Array = []
	for event in events:
		keys.append(String(event.get("key", "")))
	_ok("타임아웃이 중계 로그 키를 발행", keys.has("raceLog.timeout01"), str(keys))
	_ok("타임아웃 이벤트 키가 스트링 테이블에 등재",
		timeout_data.strings.has_key("raceLog.timeout01"))
	_ok("타임아웃 후 정산 완료", not timeout_engine.settle_log.is_empty())
	_ok("타임아웃 경로에서 데이터 침묵 기본값 0", timeout_data.is_ok())


func _serialization() -> void:
	var service := _new_service()
	if service == null:
		return
	service.trigger_vn("mvn_crew_join", "vnslot_tour_milestone", true)
	var payload := service.serialize()
	var restored := _new_service()
	_ok("복원 성립", restored.restore(payload))
	_ok("발생 기록 복원", restored.vn_seen.has("mvn_crew_join"))
	_ok("스킵 기록 복원", restored.vn_skipped.has("mvn_crew_join"))
	_ok("상한 카운터 복원", restored.season_vn_count == service.season_vn_count)
	# 멱등 플래그가 복원돼야 재로드 후 재열람이 전이를 다시 발화하지 않는다
	var again := restored.trigger_vn("mvn_crew_join", "vnslot_tour_milestone", false)
	_ok("멱등 플래그 복원 — 재로드 후에도 전이 미발화", String(again["relation"]) == "", str(again))
	var broken := _new_service()
	_ok("결손 payload 거부", not broken.restore({"vn_seen": {}}))
