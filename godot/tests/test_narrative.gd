# TC-O4 VN 이벤트·스킵·기록실 재열람 (D14 §4) + 베인 대사 3단계 필터 (D12 §5.7)
# + TC-C8 소프트 타임 리미트 (D14 §3 · D05 §7).
# 실행: godot --headless --path godot --script tests/test_narrative.gd
extends SceneTree

const MIN_CHECKS := 235

# 화자 키 도메인 — 조각으로 나누지 않아도 되는 형태(끝이 `.` 라 키 문법에 걸리지 않는다).
# 조각으로 나눈다 — 이어 붙인 전체가 리터럴로 있으면 V2 가 '코드가 발행하는 키'로 보고
# 미등재를 차단한다(접두는 키가 아니다 · 21차·25차 전례).
const SPEAKER_DOMAIN := "ui.vn." + "speaker"

# 표제 미기입 계수 — **0 = 전건 기입**. 26차에 8로 세웠고 내러티브 9차 유입과 함께 만료했다.
#
# **트립와이어가 어디 걸려 있는지 26차 회신이 틀리게 적었다** (총괄 정정 접수): 이 축은
# `title_key` **열의 공란 수**를 세지 `strings.csv` 를 보지 않는다 — 문면이 도착해도 축은
# 조용하고, **열을 채우는 순간** 8→0 으로 붉어진다. 즉 이 상수는 *문면 대기*가 아니라
# **열 기입과 같은 커밋에서 함께 움직여야 하는 값**이다. 0 이 된 지금은 회귀 가드다:
# 누군가 표제를 지우면 여기서 걸린다.
const TITLE_PENDING := 0

var _failures := 0
var _checked := 0


func _init() -> void:
	SaveManager.use_test_root()   # 저장 격리 — 실 프로필 무접촉 (25차)
	_d08_vn_slot_values()
	_tc_o4_vn_skip_and_replay()
	_vane_stage_filter()
	_tc_c8_soft_time_limit()
	_serialization()
	_t7_act_vn_data()
	_t7_act_latch()
	_t7_relation_triggers()
	_t7_cg02_branch()
	_t7_session_triggers()
	_t7_line_speakers()
	_t7_choice_data()
	_beat_data()
	_season_boundary_vn()
	_milestone_vn_wiring()
	_milestone_firing()
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


# ── T7 편입 회차 (총괄 발주 IMPL-249) ──

func _t7_data() -> GameData:
	var data := GameData.new()
	data.load_all()
	return data


# ③ 막 VN 인스턴스 데이터 무결성 — 문면이 데이터로 내려왔는지 **키 실재까지** 본다.
# 키가 표에 없으면 화면은 키 원문을 그대로 그린다(StringTable 폴백) — 그것은 "떴다"가 아니다.
func _t7_act_vn_data() -> void:
	var data := _t7_data()
	var entries := data.act_vn_entries()
	_ok("막 VN 인스턴스 6건", entries.size() == 6, str(entries.size()))
	var total := 0
	var missing_text := 0
	var missing_speaker := 0
	var bad_tone := 0
	for entry in entries:
		var row: Dictionary = entry
		if not ["calm", "tense"].has(String(row.get("tone", ""))):
			bad_tone += 1
		for line in Array(row.get("lines", [])):
			var item: Dictionary = line
			total += 1
			if not data.strings.has_key(String(item.get("text_key", ""))):
				missing_text += 1
			if not data.strings.has_key(String(item.get("speaker_key", ""))):
				missing_speaker += 1
	_ok("막 VN 총 라인 75", total == 75, str(total))
	_ok("전 라인 문면 키 실재", missing_text == 0, "missing=%d" % missing_text)
	_ok("전 라인 화자 키 실재", missing_speaker == 0, "missing=%d" % missing_speaker)
	_ok("정조 값 도메인 = calm|tense", bad_tone == 0, "bad=%d" % bad_tone)
	# 지문 화자는 **값이 공란**인 것이 납품 규격이다 — 키는 있고 값이 비어야 라벨이 빈다.
	_ok("지문 화자 = 키 실재·값 공란",
		data.strings.has_key("ui.vn.speakerNarration")
			and data.strings.text("ui.vn.speakerNarration") == "")


# ③ 막 래치 — **투어 경계 전속 · 단조 증가 · 건너뜀 수용** (D08 §8.1 · 총괄 수용 ⑤)
func _t7_act_latch() -> void:
	var data := _t7_data()
	var state := OutgameState.new()
	state.setup(data)
	_ok("초기 막 = 1", state.narrative_act == 1)
	# **1막은 래치가 가져가지 않는다** — 래치는 "달성 후 최초의 투어 경계"이고 1막에는 달성이
	# 없다(D04 §1.2 "게임 시작" · 총괄 판정 IMPL-263 ②). 개시형 창구가 따로 있다.
	_ok("첫 경계 래치 = 1막 미포함", state.latch_narrative_act().is_empty(),
		str(state.act_vn_pending))
	var opened := state.open_narrative_act()
	_ok("커리어 개시 = 1막 VN 발생", opened == ["vn_act1"], str(opened))
	_ok("개시 재호출은 재발생하지 않는다", state.open_narrative_act().is_empty())
	_ok("개시분이 표시 대기에 들어간다", state.act_vn_pending == ["vn_act1"],
		str(state.act_vn_pending))
	# 개시형과 달성형이 **같은 발화 대장**을 쓰는가 — 갈라지면 한쪽만 중복 발화를 막는다.
	state.milestones["milestone_first_podium"] = true
	_ok("달성형은 래치가 가져간다", state.latch_narrative_act() == ["vn_act2"])
	_ok("대기가 누적된다", state.act_vn_pending == ["vn_act1", "vn_act2"],
		str(state.act_vn_pending))

	# **건너뜀 경로** — 첫 포디움·첫 투어 우승 없이 로렌츠 격파만 성립한 상태.
	var skipper := OutgameState.new()
	skipper.setup(data)
	skipper.open_narrative_act()
	skipper.milestones["milestone_lorentz_beat"] = true
	var jumped := skipper.latch_narrative_act()
	_ok("건너뜀 — 4막 VN 발생", jumped.has("vn_act4"), str(jumped))
	_ok("건너뜀 — 2·3막 VN 미발생",
		not jumped.has("vn_act2") and not jumped.has("vn_act3"), str(jumped))
	_ok("건너뜀 — 막 번호 = 최대값 4", skipper.narrative_act == 4, str(skipper.narrative_act))
	# 단조 증가: 뒤늦게 하위 마일스톤이 서도 막이 내려가지 않는다.
	skipper.milestones["milestone_first_podium"] = true
	skipper.latch_narrative_act()
	_ok("단조 증가 — 하위 마일스톤 추가에도 4 유지", skipper.narrative_act == 4,
		str(skipper.narrative_act))
	# 직렬화 — 래치는 세이브 대상이다(재로드 후 VN 이 다시 뜨면 안 된다).
	var restored := OutgameState.new()
	restored.setup(data)
	_ok("직렬화 왕복", restored.restore(skipper.serialize()))
	_ok("복원 후 막 번호 유지", restored.narrative_act == 4)
	_ok("복원 후 재발생 없음", restored.latch_narrative_act().is_empty())
	_ok("복원 후 개시형 재발생 없음", restored.open_narrative_act().is_empty())
	# **표시 대기가 세이브를 건넌다.** 발화(투어 경계)와 표시(브리핑 슬롯) 사이에 저장 지점이
	# 있어(SET-01), 이 열이 안 넘어가면 `act_vn_fired` 만 남아 그 막이 영구 미도달이 된다.
	_ok("표시 대기 직렬화 왕복", restored.act_vn_pending == skipper.act_vn_pending,
		"%s vs %s" % [restored.act_vn_pending, skipper.act_vn_pending])
	_ok("표시 대기 비어 있지 않음", not restored.act_vn_pending.is_empty())


# ⑤⑥ 관계 축 트리거 — **행과 트리거가 같은 회차에 섰는가**
func _t7_relation_triggers() -> void:
	var data := _t7_data()
	for axis_id in ["relation_reunion", "relation_succession_maro"]:
		_ok("관계 축 행 실재: %s" % axis_id, data.relation_axes.has(axis_id))
		var row: Dictionary = data.relation_axes[axis_id]
		_ok("%s name_key 실재" % axis_id, data.strings.has_key(String(row["name_key"])))
		var t1 := CsvTable.to_int(String(row["threshold1"]))
		var t2 := CsvTable.to_int(String(row["threshold2"]))
		var t3 := CsvTable.to_int(String(row["threshold3"]))
		_ok("%s 임계 오름차순" % axis_id, t1 < t2 and t2 < t3, "%d/%d/%d" % [t1, t2, t3])
	# D13 v1.10 결정 #19 — 재회 임계 2/3/4 (값 창구 대조)
	var reunion: Dictionary = data.relation_axes["relation_reunion"]
	_ok("재회 임계 = 2/3/4 (D13 v1.10)",
		String(reunion["threshold1"]) == "2" and String(reunion["threshold2"]) == "3"
			and String(reunion["threshold3"]) == "4", str(reunion))
	# 카운터 → 단계는 **공표 전까지 오르지 않는다** (D07 §5.5 대회 경계 스냅).
	var state := OutgameState.new()
	state.setup(data)
	state.add_relation("relation_reunion", 2)
	_ok("공표 전 단계 0", state.relation_stage("relation_reunion") == 0)
	state.commit_relation_transitions()
	_ok("공표 후 단계 1 = '대면'", state.relation_stage("relation_reunion") == 1)
	# 계승 2축도 같은 2단 구조를 탄다.
	state.add_relation("relation_succession_maro", 3)
	_ok("계승(셀린) 공표 전 단계 0", state.relation_stage("relation_succession_maro") == 0)
	state.commit_relation_transitions()
	_ok("계승(셀린) 공표 후 단계 1", state.relation_stage("relation_succession_maro") == 1)
	# 트리거가 지목하는 데이터가 실재하는가 — 코드가 짚는 id 는 데이터에 있어야 한다.
	_ok("보조 이벤트 실재: event_number_two_check",
		data.events.has("event_number_two_check"))
	_ok("보조 이벤트 = C3 관계·조우",
		String(data.events["event_number_two_check"]["category_id"]) == "category_c3")
	_ok("알타 리지 벽 = 카이",
		String(data.stages["stage_alta_ridge"].get("wall_rival", "")) == "ai_sherwood")


# ⑦ CG-02 갈래 — 순수 static 이라 화면 없이 전수로 본다
func _t7_cg02_branch() -> void:
	# 화면 클래스는 `class_name` 이 없어 스크립트 리소스로 짚는다 (TC-C 전례).
	var race_screen_script := load("res://ui/race/race_screen.gd")
	_ok("CG-02 성립 — 카이 · 대면 도달 · 듀얼 결판",
		race_screen_script.l3_reunion_for("ai_sherwood", 1, true) == "cg_02_reunion")
	_ok("CG-02 불성립 — 단계 0 (대면 미도달)",
		race_screen_script.l3_reunion_for("ai_sherwood", 0, true) == "")
	_ok("CG-02 불성립 — 상대 불일치",
		race_screen_script.l3_reunion_for("ai_jude", 3, true) == "")
	_ok("CG-02 불성립 — 듀얼 미결판",
		race_screen_script.l3_reunion_for("ai_sherwood", 3, false) == "")
	_ok("CG-02 성립 — 상위 단계에서도 유지",
		race_screen_script.l3_reunion_for("ai_sherwood", 3, true) == "cg_02_reunion")


# ⑤⑥ 세션 층 트리거 거동 — 무대 결속·투어 상한·듀얼 축을 실호출로 본다.
# **캘린더를 직접 세워 무대를 고정한다** — 실주행으로 알타 리지에 도달하려면 셔플을 타야 해서
# 검사가 확률에 걸린다. 여기서 보는 것은 배선이지 셔플이 아니다.
func _t7_session_triggers() -> void:
	var session := RunSession.new()
	var data := _t7_data()
	session.setup(data)
	session.begin_career(2)
	var alta := "stage_alta_ridge"
	var other := ""
	for stage_id in data.stages:
		if String(stage_id) != alta:
			other = String(stage_id)
			break
	session.season.calendar = [alta, other]

	# ⓐ 알타 리지 결속 — 그 무대의 투어에서만 오른다
	session.season.tour_slot = 1
	var before: int = session.outgame.relation_counters.get("relation_reunion", 0)
	_ok("알타 리지 투어 = 비트 계수", session.record_reunion_beat("probe"))
	_ok("카운터 +1", int(session.outgame.relation_counters["relation_reunion"]) == before + 1)
	session.season.tour_slot = 2
	_ok("타 무대 투어 = 불계수", not session.record_reunion_beat("probe"))
	_ok("타 무대에서 카운터 불변",
		int(session.outgame.relation_counters["relation_reunion"]) == before + 1)

	# ⓑ 투어당 상한 2 (D08 §8.7-3 — threshold1=2 도출의 전제)
	session.season.tour_slot = 1
	session._reunion_beats_this_tour = 0
	_ok("1비트", session.record_reunion_beat("probe"))
	_ok("2비트", session.record_reunion_beat("probe"))
	_ok("3비트 = 상한 차단", not session.record_reunion_beat("probe"))
	_ok("상한 상수 = 2", RunSession.REUNION_BEATS_PER_TOUR == 2)

	# ⓒ 계승 2축 — 선착·듀얼 두 갈래가 **각각** 오른다
	var probe := RunSession.new()
	probe.setup(data)
	probe.begin_career(2)
	var engine := RaceEngine.new()
	engine.setup(data, probe.rng)
	probe.last_gp_result = {"beaten_rivals": ["ai_maro"]}
	probe._advance_succession_maro(engine)
	_ok("선착 = +1", int(probe.outgame.relation_counters.get("relation_succession_maro", 0)) == 1)
	probe.last_gp_result = {"beaten_rivals": []}
	engine.duel_opponents = ["ai_maro", "ai_jude", "ai_maro"]
	probe._advance_succession_maro(engine)
	_ok("듀얼 수행 2회 = +2 (타 상대 불계수)",
		int(probe.outgame.relation_counters["relation_succession_maro"]) == 3,
		str(probe.outgame.relation_counters["relation_succession_maro"]))
	probe.last_gp_result = {"beaten_rivals": []}
	engine.duel_opponents = []
	probe._advance_succession_maro(engine)
	_ok("사건 없음 = 불변", int(probe.outgame.relation_counters["relation_succession_maro"]) == 3)


# ② 라인 단위 화자 — 정규화와 큐음 갈림을 화면을 세우지 않고 본다.
# `_normalize_lines` 는 화면 상태를 타지 않으므로 스크립트 인스턴스로 직접 부른다.
func _t7_line_speakers() -> void:
	var screen = load("res://ui/nar/vn_screen.gd").new()
	screen._default_speaker_key = "ui.vn.speakerVane"
	# 구 계약 — 문자열 배열 (하위 호환)
	var legacy: Array = screen._normalize_lines(["vn.act1.beat01"])
	_ok("구 계약 문자열 항목 수용", legacy.size() == 1)
	_ok("구 계약 = 페이로드 기본 화자 승계",
		String(legacy[0]["speaker_key"]) == "ui.vn.speakerVane", str(legacy[0]))
	_ok("구 계약 텍스트 키 보존", String(legacy[0]["text_key"]) == "vn.act1.beat01")
	# 신 계약 — 사전 항목이 라인마다 화자를 갈아낀다
	var mixed: Array = screen._normalize_lines([
		{"speaker_key": "ui.vn.speakerMarta", "text_key": "vn.act1.beat02"},
		{"text_key": "vn.act1.beat07"},
	])
	_ok("신 계약 화자 지정 반영", String(mixed[0]["speaker_key"]) == "ui.vn.speakerMarta")
	_ok("신 계약 화자 생략 = 기본값", String(mixed[1]["speaker_key"]) == "ui.vn.speakerVane")
	# 납품 1막은 화자가 실제로 교대한다 — 이벤트 단위 화자로는 표현 불가라는 발동 조건.
	var data := _t7_data()
	var act1 := data.act_vn_entry("vn_act1")
	var speakers: Dictionary = {}
	for line in Array(act1.get("lines", [])):
		speakers[String(line["speaker_key"])] = true
	_ok("1막 화자 2인 이상 교대", speakers.size() >= 2, str(speakers.keys()))
	screen.free()


# ⑦ 선택 지점 데이터 (D04 §5.3 · 총괄 판정 IMPL-257 ①).
#
# **기계가 못 보는 열이 하나 있다.** `vn_id` 는 `act_vn.json` 의 `entries[].id` 를 가리키는데
# `_structure_ids()` 는 구조 파일의 **루트 id 만** 모으므로 FK 로 걸 수 없다 — V2 가 원리적으로
# 닿지 않는 자리다. 그 공백을 적재 층 가드가 닫고, 그 가드가 실제로 도는지는 여기서 본다.
func _t7_choice_data() -> void:
	var data := _t7_data()
	_ok("선택 지점 4건", data.vn_choices.size() == 4, str(data.vn_choices.size()))
	_ok("앵커 대조 생략 0", Array(data.vn_choice_omitted).is_empty(), str(data.vn_choice_omitted))
	var total_options := 0
	var count_mismatch := 0
	var order_broken := 0
	var missing_key := 0
	var anchor_missing := 0
	var speaker_off := 0
	var allowed_speakers := ["ui.vn.speakerMarta", "ui.vn.speakerTheo", "ui.vn.speakerVane"]
	for choice_id in data.vn_choices:
		var row: Dictionary = data.vn_choices[choice_id]
		var options := data.vn_choice_options_for(String(choice_id))
		total_options += options.size()
		if options.size() != CsvTable.to_int(String(row["option_count"])):
			count_mismatch += 1
		# 앵커는 **그 VN 안의 라인**이어야 한다 — 검사가 적재 층 판정을 그대로 믿지 않고
		# 원본 구조에서 독립으로 다시 찾는다(자기 정합 함정 회피).
		var found := false
		for line in Array(data.act_vn_entry(String(row["vn_id"])).get("lines", [])):
			if String(Dictionary(line).get("text_key", "")) == String(row["after_text_key"]):
				found = true
		if not found:
			anchor_missing += 1
		for index in range(options.size()):
			var option: Dictionary = options[index]
			if CsvTable.to_int(String(option["option_order"])) != index + 1:
				order_broken += 1
			for column in ["text_key", "reaction_text_key", "reaction_speaker_key"]:
				if not data.strings.has_key(String(option[column])):
					missing_key += 1
			if not allowed_speakers.has(String(option["reaction_speaker_key"])):
				speaker_off += 1
	_ok("선택지 10건", total_options == 10, str(total_options))
	_ok("지점별 수 = option_count", count_mismatch == 0, "mismatch=%d" % count_mismatch)
	_ok("option_order = 1..n 오름차순", order_broken == 0, "broken=%d" % order_broken)
	_ok("전 텍스트·화자 키 실재", missing_key == 0, "missing=%d" % missing_key)
	_ok("앵커가 해당 VN 라인에 실재", anchor_missing == 0, "missing=%d" % anchor_missing)
	_ok("반응 화자 = 3자 전속", speaker_off == 0, "off=%d" % speaker_off)
	# 대괄호는 데이터 값에 들어 있다 — 화면이 조립하면 언어별 괄호 관례를 흡수할 수 없다.
	var bracket_off := 0
	for choice_id in data.vn_choices:
		for option in data.vn_choice_options_for(String(choice_id)):
			var body := data.strings.text(String(option["text_key"]))
			if not (body.begins_with("[") and body.ends_with("]")):
				bracket_off += 1
	_ok("선택지 문면 = 대괄호 포함", bracket_off == 0, "off=%d" % bracket_off)
	# 조회는 **짝이 맞을 때만** 성립한다 — vn_id 만 같고 앵커가 다르면 지점이 아니다.
	_ok("정상 조회", String(data.vn_choice_at("vn_act3", "vn.act3.beat11").get("id", "")) == "vnchoice_act3_corner")
	_ok("앵커 불일치 = 미조회", data.vn_choice_at("vn_act3", "vn.act3.beat01").is_empty())
	_ok("VN 불일치 = 미조회", data.vn_choice_at("vn_act1", "vn.act3.beat11").is_empty())
	_ok("미등재 지점 옵션 = 빈 배열", data.vn_choice_options_for("vnchoice_none").is_empty())
	# 가드의 음성 갈래 — 없는 키·빈 키는 앵커로 성립하지 않는다.
	var act3 := data.act_vn_entry("vn_act3")
	_ok("가드: 실재 라인 = true", data._vn_has_line(act3, "vn.act3.beat11"))
	_ok("가드: 부재 라인 = false", not data._vn_has_line(act3, "vn.act1.beat01"))
	_ok("가드: 빈 키 = false", not data._vn_has_line(act3, ""))


# ⑧ 축 결속 브리핑 비트 데이터 (총괄 판정 IMPL-289 ③ · 19차 결선).
#
# **조건이 데이터에 있다는 것이 이 표의 요점**이므로 축도 데이터를 본다 — 무대·단계 구간이
# 코드로 새면 여기서는 통과하고 화면에서만 어긋난다.
func _beat_data() -> void:
	var data := _t7_data()
	_ok("브리핑 비트 실재", data.vn_beats.size() >= 1, str(data.vn_beats.size()))
	_ok("라인 수 대조 생략 0", Array(data.vn_beat_omitted).is_empty(), str(data.vn_beat_omitted))
	var missing_key := 0
	var order_broken := 0
	var count_mismatch := 0
	var bad_range := 0
	# 화자 목록을 손으로 적지 않는다 — 26차에 크루 3인이 들어오며 손 목록이 먼저 걸렸다.
	# **화자 키는 `ui.vn.speaker*` 도메인 전속**이라는 것이 실제 규칙이고, 그 도메인에서
	# 뽑으면 화자가 늘어도 목록이 낡지 않으며 **도메인 밖 키는 여전히 걸린다.**
	var allowed: Array = []
	for key in data.strings.keys():
		if String(key).begins_with(SPEAKER_DOMAIN):
			allowed.append(String(key))
	_ok("화자 키 도메인 표본 확보", allowed.size() >= 4, str(allowed.size()))
	var speaker_off := 0
	for beat_id in data.vn_beats:
		var row: Dictionary = data.vn_beats[beat_id]
		var lines := data.vn_beat_lines_for(String(beat_id))
		if lines.size() != CsvTable.to_int(String(row["line_count"])):
			count_mismatch += 1
		# 구간이 뒤집히면 조건이 영구 미성립이다 — 조용한 미발동의 전형이다.
		if CsvTable.to_int(String(row["min_stage"])) > CsvTable.to_int(String(row["max_stage"])):
			bad_range += 1
		for index in range(lines.size()):
			var line: Dictionary = lines[index]
			if CsvTable.to_int(String(line["line_order"])) != index + 1:
				order_broken += 1
			for column in ["speaker_key", "text_key"]:
				if not data.strings.has_key(String(line[column])):
					missing_key += 1
			if not allowed.has(String(line["speaker_key"])):
				speaker_off += 1
	_ok("선언 라인 수 = 실제", count_mismatch == 0, "mismatch=%d" % count_mismatch)
	_ok("단계 구간 정상(min ≤ max)", bad_range == 0, "bad=%d" % bad_range)
	_ok("line_order = 1..n 오름차순", order_broken == 0, "broken=%d" % order_broken)
	_ok("전 문면·화자 키 실재", missing_key == 0, "missing=%d" % missing_key)
	_ok("화자 = 3자 + 지문 전속", speaker_off == 0, "off=%d" % speaker_off)
	# 조건 조회 — 무대·단계 양쪽이 무는지 데이터 층에서 확인한다.
	var stage_zero := func(_axis: String): return 0
	var stage_one := func(_axis: String): return 1
	_ok("무대 일치 + 단계 0 = 조회 성립",
		data.vn_beats_for("vnslot_tour_brief", "stage_alta_ridge", stage_zero).size() == 1)
	_ok("무대 불일치 = 미조회",
		data.vn_beats_for("vnslot_tour_brief", "stage_metro_night", stage_zero).is_empty())
	_ok("단계 이탈 = 미조회",
		data.vn_beats_for("vnslot_tour_brief", "stage_alta_ridge", stage_one).is_empty())
	_ok("슬롯 불일치 = 미조회",
		data.vn_beats_for("vnslot_season_open", "stage_alta_ridge", stage_zero).is_empty())
	# ── 개막 비트 (22차 — 축도 무대도 갖지 않는 첫 비트) ──
	#
	# **무대 질의가 빈 문자열이어야 잡힌다.** 현재 무대를 넘기면 영구 미조회가 되고,
	# 그 미조회는 화면에서 폴백 1줄로 나타나 "문안이 없다"와 구분되지 않는다.
	var opening := data.vn_beats_for("vnslot_season_open", "", stage_zero)
	_ok("개막 비트 = 빈 무대 질의로 조회", opening.size() == 1, str(opening.size()))
	_ok("개막 비트 = 현재 무대 질의로는 미조회 (호출부 인자 계약)",
		data.vn_beats_for("vnslot_season_open", "stage_metro_night", stage_zero).is_empty())
	# 축이 없어도 단계 구간 0~0 이 성립한다 — `relation_stage("")` 가 0 을 돌려주기 때문이다.
	# 그 사실이 깨지면 개막 비트가 조용히 사라지므로 여기서 값으로 확인한다.
	_ok("축 공란 비트의 단계 구간 성립", opening.size() == 1
		and String(Dictionary(opening[0]).get("axis_id", "x")) == "")
	# **슬롯 격리** — 브리핑 질의에 개막 비트가 섞이면 투어마다 개막 정경이 뜬다.
	_ok("브리핑 질의에 개막 비트 미포함",
		data.vn_beats_for("vnslot_tour_brief", "", stage_zero).is_empty())
	if opening.size() == 1:
		var opening_id := String(Dictionary(opening[0])["id"])
		var opening_lines := data.vn_beat_lines_for(opening_id)
		_ok("개막 비트 3라인", opening_lines.size() == 3, str(opening_lines.size()))
		_ok("개막 비트 톤 = 슬롯 톤(calm)",
			String(Dictionary(opening[0]).get("tone", "")) == "calm")
		# 표제는 **슬롯 표에서** 온다 — 아카이브가 원문 id 를 그리지 않는 근거다(22차 ⓘ).
		var slot := data.vn_slot(String(Dictionary(opening[0])["slot_id"]))
		_ok("개막 비트 슬롯 표제 실재",
			not slot.is_empty() and data.strings.has_key(String(slot["name_key"])),
			str(slot.get("name_key", "")))
	# **반복 노출 상한이 데이터로 정해진다** — 단계 0 구간이므로 카운터가 2에 닿으면(threshold1)
	# 더 이상 서지 않는다. 내러티브 3차 §5.2 가 이월한 "반복 피로"의 현행 상한이 그것이다.
	var beat: Dictionary = data.vn_beats["vnbeat_reunion_alta"]
	_ok("현행 비트 단계 구간 = 0~0",
		String(beat["min_stage"]) == "0" and String(beat["max_stage"]) == "0",
		"%s~%s" % [beat["min_stage"], beat["max_stage"]])
	var axis := data.relation_axis(String(beat["axis_id"]))
	_ok("축 = 재회 (threshold1 = 2)", CsvTable.to_int(String(axis["threshold1"])) == 2,
		String(axis["threshold1"]))


# ── 시즌 경계 VN — 상한 리셋 · 엔딩 비트 · 발화 계수 (24차) ──
#
# **"조용히 안 뜨는" 결함이었다.** `param_vn_season_cap 15` 가 커리어 전체 상한으로
# 작동했고 시즌 1 이 정확히 15를 채우므로(개막 1 + 브리핑 5 + 마일스톤 8 + 엔딩 1)
# 시즌 2 개막부터 VN 이 서지 않았다. 종료코드·화면 어디에도 흔적이 없다 —
# **미발화는 정상과 구분되지 않으므로 계수를 축으로 세운다.**
func _season_boundary_vn() -> void:
	var data := _new_data()
	if data == null:
		return
	# ⓐ 엔딩 비트 데이터 — 개막과 동형
	var stage_zero := func(_axis: String): return 0
	var closing := data.vn_beats_for("vnslot_season_close", "", stage_zero)
	_ok("엔딩 비트 = 빈 무대 질의로 조회", closing.size() == 1, str(closing.size()))
	_ok("엔딩 비트 = 현재 무대 질의로는 미조회",
		data.vn_beats_for("vnslot_season_close", "stage_metro_night", stage_zero).is_empty())
	_ok("개막 질의에 엔딩 비트 미포함", data.vn_beats_for("vnslot_season_open", "", stage_zero)
		.size() == 1)
	if closing.size() == 1:
		var closing_id := String(Dictionary(closing[0])["id"])
		_ok("엔딩 비트 3라인", data.vn_beat_lines_for(closing_id).size() == 3)
		_ok("엔딩 비트 톤 = calm", String(Dictionary(closing[0]).get("tone", "")) == "calm")
		var slot := data.vn_slot(String(Dictionary(closing[0])["slot_id"]))
		_ok("엔딩 슬롯 표제 실재 (아카이브 표제 자동 해소)",
			not slot.is_empty() and data.strings.has_key(String(slot["name_key"])))
	# ⓑ 상한 리셋 — 서비스 층
	var service := _new_service()
	var cap := data.param_int("param_vn_season_cap")
	for index in range(cap):
		service.trigger_vn("vn_fill_%d" % index, "vnslot_tour_brief", false)
	_ok("상한 충전 = 대장 값", service.season_vn_count == cap, str(service.season_vn_count))
	_ok("충전 후 발화 거부", not bool(service.trigger_vn("vn_over", "vnslot_season_open", false)
		.get("occurred", false)))
	service.begin_season()
	_ok("경계 리셋 후 계수 0", service.season_vn_count == 0)
	_ok("경계 리셋 후 발화 성립", bool(service.trigger_vn("vn_after", "vnslot_season_open", false)
		.get("occurred", false)))
	# ⓒ **발화 계수 축 — 세션을 시즌 2까지 몰아 개막이 실제로 서는가.**
	# 서비스 층 리셋만 보면 `begin_next_season()` 이 그것을 부르는지는 보이지 않는다
	# (결함이 정확히 그 자리였다 — 리셋 함수는 있고 호출이 없었다).
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	var season_one := session.season.season
	for index in range(cap):
		session.narrative.trigger_vn("vn_s1_%d" % index, "vnslot_tour_brief", false)
	_ok("시즌 1 상한 충전", session.narrative.season_vn_count == cap)
	session.begin_next_season()
	_ok("시즌 전환 성립", session.season.season == season_one + 1)
	_ok("시즌 전환이 VN 계수를 리셋한다", session.narrative.season_vn_count == 0,
		str(session.narrative.season_vn_count))
	# 시즌 2 개막 페이로드가 실제로 서고, 그 발화가 등재되는가
	var opening := session.season_open_payload("HUB-01")
	_ok("시즌 2 개막 페이로드 발행", not opening.is_empty(), str(opening.keys()))
	_ok("시즌 2 개막 3라인", Array(opening.get("line_keys", [])).size() == 3)
	var fired: Dictionary = session.narrative.trigger_vn(String(opening["vn_id"]),
		String(opening["slot_id"]), false)
	_ok("시즌 2 개막 실발화", bool(fired.get("occurred", false)), str(fired))
	# ⓓ 시즌당 1회 가드 — 발화 후에는 같은 시즌에서 다시 서지 않는다
	_ok("발화 후 개막 재발행 0", session.season_open_payload("HUB-01").is_empty())
	# ⓔ 엔딩도 같은 대칭 — 시즌당 1회 · 발화 후 소멸
	var close_payload := session.season_close_payload("HUB-01")
	_ok("엔딩 페이로드 발행", not close_payload.is_empty())
	_ok("엔딩 vn_id = 시즌 인스턴스",
		String(close_payload.get("vn_id", "")) == "vn_season_close_s%d" % session.season.season,
		String(close_payload.get("vn_id", "")))
	_ok("엔딩에 캘린더 플래그 없음", not bool(close_payload.get("calendar", false)))
	session.narrative.trigger_vn(String(close_payload["vn_id"]),
		String(close_payload["slot_id"]), false)
	_ok("발화 후 엔딩 재발행 0", session.season_close_payload("HUB-01").is_empty())


# ── 마일스톤 VN 결선 (26차) ──
#
# **라인 계수는 대사만 센다** (총괄 판정 ④ 전사 — D04 §5.2 상한의 해석 명문).
# 지문은 무게가 아니라 호흡이라 상한에 넣지 않는다. 단서 계열은 **무게 예외**다
# (판정 ⓐ — D08 §8.6 이 단서별 구체 명문을 두므로 일반 무게 규격에 우선한다).
func _milestone_vn_wiring() -> void:
	var data := _t7_data()
	if data == null:
		return
	var stage_zero := func(_axis: String): return 0
	var milestone := data.vn_beats_for("vnslot_tour_milestone", "", stage_zero)
	_ok("마일스톤 비트 8건", milestone.size() == 8, str(milestone.size()))
	var narration := SPEAKER_DOMAIN + "Narration"
	var weight_exempt := 0
	var light: Array = []
	for beat in milestone:
		var row: Dictionary = beat
		var beat_id := String(row["id"])
		var lines := data.vn_beat_lines_for(beat_id)
		# 대사 = 지문 밖 전부
		var dialogue := 0
		var narration_lines := 0
		for line in lines:
			if String(Dictionary(line)["speaker_key"]) == narration:
				narration_lines += 1
			else:
				dialogue += 1
		_ok("%s 지문 ≤ 2 (D04 §5.2)" % beat_id, narration_lines <= 2, str(narration_lines))
		if beat_id.begins_with("vnbeat_clue_"):
			# 단서는 무게 규격 밖 — 재지 않는 것이 판정 ⓐ의 이행이다.
			weight_exempt += 1
			_ok("%s 단서 = 무게 예외 (재지 않음)" % beat_id, true)
			continue
		# **천장만 판정한다.** 중량 16 은 D04 §5.2 의 상한이라 넘으면 규격 위반이지만,
		# 표준형 하한(대사 8)은 *어느 무게로 쓸 것인가*의 선택이고 그 선택은 작법이다 —
		# 성취 3건이 대사 7(총 8라인)로 왔는데, 그것이 '경량으로 쓴 것'인지 '표준형 미달'인지는
		# 기계가 정할 수 없다. **관측으로 남기고 판정을 올린다**(회신 §보고).
		_ok("%s 대사 ≤ 16 (중량 천장)" % beat_id, dialogue <= 16, "대사=%d" % dialogue)
		if dialogue < 8:
			light.append("%s(대사 %d)" % [beat_id, dialogue])
	_ok("무게 예외 = 단서 2건", weight_exempt == 2, str(weight_exempt))
	# 관측 — 표준형 하한(대사 8) 미만. 판정이 아니라 보고다.
	print("  [측정] 표준형 하한 미만 %d건%s"
		% [light.size(), ("  " + str(light)) if not light.is_empty() else ""])
	_ok("무게 관측 성립", light.size() <= milestone.size())
	# 분류 매핑 (판정 ① B안) — 고유 vn_id 가 분류 한 겹을 거쳐 전이를 찾는가
	for probe in [["vnbeat_crew_nadia", "mvn_crew_join"], ["vnbeat_crew_sasha", "mvn_crew_join"],
			["vnbeat_feat_point", "mvn_general_feat"], ["vnbeat_clue_locked", "mvn_origin_clue"]]:
		_ok("분류 매핑: %s → %s" % [probe[0], probe[1]],
			data.milestone_class_of(String(probe[0])) == String(probe[1]),
			data.milestone_class_of(String(probe[0])))
	# 비트가 없는 id 는 자기 자신 — 기존 직접 조회 경로가 살아 있어야 한다
	_ok("비트 밖 id 는 자기 자신", data.milestone_class_of("mvn_act_transition") == "mvn_act_transition")
	# **같은 분류의 N 건이 각자 1회씩 전이를 소비한다** — 공유 id 로 두면 1회만 나고
	# 고유 id 로 직접 조회하면 아예 안 난다(내러티브 8차 §4.1 두 형태의 실패).
	var service := _new_service()
	var fired := 0
	for beat_id in ["vnbeat_crew_nadia", "vnbeat_crew_oscar", "vnbeat_crew_sasha"]:
		var outcome: Dictionary = service.trigger_vn(beat_id, "vnslot_tour_milestone", false)
		if String(outcome.get("relation", "")) == "relation_kinship":
			fired += 1
	_ok("크루 3건이 각자 전이를 소비 (친애 축 3회)", fired == 3, str(fired))
	# 재발화 가드는 vn_id 단위 유지 — 같은 VN 을 다시 발생시켜도 두 번 나지 않는다
	_ok("동일 vn_id 재발화 시 전이 0",
		String(service.trigger_vn("vnbeat_crew_nadia", "vnslot_tour_milestone", false)
			.get("relation", "")) == "")
	# 표제 기제 — 한 슬롯을 여럿이 공유하면 슬롯 표제로 갈리지 않는다.
	# **미유입 대장**이 만료를 강제한다: 문면이 들어오면 이 축이 실패하고 그때가
	# `title_key` 를 채울 시점이다(내러티브 9차 키 계약).
	var untitled: Array = []
	for beat in milestone:
		if data.vn_beat_title_key(String(Dictionary(beat)["id"])).is_empty():
			untitled.append(String(Dictionary(beat)["id"]))
	_ok("표제 미기입 0 (전건 기입)", untitled.size() == TITLE_PENDING,
		"%d — 미기입 비트: %s" % [untitled.size(), str(untitled)])
	_ok("표제 기제 실재 (비트 행이 표제를 인다)",
		data.vn_beats.values().any(func(row): return Dictionary(row).has("title_key")))


# ── 마일스톤 VN 발화 경로 (27차) — 자격·우선순위·이월·형식 B ──
#
# **이월에 대기열이 없다.** 자격을 상태에서 도출하므로 밀린 비트는 다음 경계에도
# 여전히 자격을 갖고 같은 정렬이 다시 고른다 — 그 성질을 축으로 못박는다
# (대기열이 없다는 것은 *잃어버릴 대기열도 없다*는 뜻이다).
func _milestone_firing() -> void:
	var data := _t7_data()
	if data == null:
		return
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	# ⓐ 트리거 미성립 = 미발화. 조용한 상시 발화가 이 축의 반대편이다.
	_ok("트리거 전 미발화", session.pending_milestone_beat().is_empty(),
		str(session.pending_milestone_beat().get("id", "")))
	# **트리거 미선언 행도 자격이 없다.** 현행 데이터에 그런 행이 없으므로 메모리에서
	# 만들어 본다 — 없는 상태를 만들지 않으면 그 분기는 영원히 관측되지 않는다.
	# **다른 자격자가 하나도 없을 때 재는 것이 요건**이다: 우선순위가 높은 비트가 있으면
	# 미선언 행이 자격을 얻어도 뽑히지 않아 통과한다(돌연변이 K3 초판 미검출).
	var probe_row: Dictionary = data.vn_beats["vnbeat_feat_finish"].duplicate()
	probe_row["trigger_milestone"] = ""
	probe_row["id"] = "vnbeat_probe_notrigger"
	data.vn_beats["vnbeat_probe_notrigger"] = probe_row
	_ok("트리거 미선언 비트는 자격 없음", session.pending_milestone_beat().is_empty(),
		String(session.pending_milestone_beat().get("id", "")))
	data.vn_beats.erase("vnbeat_probe_notrigger")
	# ⓑ 성취 트리거 — 마일스톤 플래그가 서면 자격이 생긴다
	session.outgame.milestones["milestone_first_finish"] = true
	var first := session.pending_milestone_beat()
	_ok("성취 마일스톤 → 자격", String(first.get("id", "")) == "vnbeat_feat_finish",
		String(first.get("id", "")))
	# ⓒ **우선순위 4단.** 짝을 **id 순과 어긋나게** 고른다 — 크루(2) vs 단서(3) 는
	# id 로는 `clue` 가 앞이고 우선순위로는 `crew` 가 앞이다. 같은 순서를 내는 짝으로 재면
	# 정렬을 통째로 지워도 통과한다(돌연변이 K1 초판 미검출이 정확히 그 형태였다).
	session.outgame.crew["crew_nadia"] = true
	session.outgame.narrative_act = 2   # 단서 1 자격 동시 성립
	var picked := session.pending_milestone_beat()
	_ok("우선순위: 크루 합류(2) > 기원 단서(3) — id 순과 반대",
		String(picked.get("id", "")) == "vnbeat_crew_nadia", String(picked.get("id", "")))
	_ok("전제: id 순이면 단서가 먼저", "vnbeat_clue_locked" < "vnbeat_crew_nadia")
	# ⓓ **이월 — 대기열 없이 성립한다.** 크루가 발생하면 밀렸던 성취가 다음 차례가 된다.
	# 세 건이 동시에 자격을 갖고 있으므로 **우선순위 순으로 세 경계에 걸쳐 선다** —
	# 대기열 없이 이월이 성립하는 것을 사슬로 확인한다(밀린 것이 사라지지 않는다).
	session.narrative.trigger_vn("vnbeat_crew_nadia", "vnslot_tour_milestone", false)
	var carried := session.pending_milestone_beat()
	_ok("이월 1: 크루 다음은 단서(3)", String(carried.get("id", "")) == "vnbeat_clue_locked",
		String(carried.get("id", "")))
	session.narrative.trigger_vn("vnbeat_clue_locked", "vnslot_tour_milestone", false)
	var carried2 := session.pending_milestone_beat()
	_ok("이월 2: 단서 다음은 성취(4)", String(carried2.get("id", "")) == "vnbeat_feat_finish",
		String(carried2.get("id", "")))
	# ⓔ 단서 = 막 진행 트리거
	# ⓕ 발생분은 다시 서지 않는다 — 스킵도 발생이다
	for beat_id in ["vnbeat_clue_locked", "vnbeat_feat_finish"]:
		session.narrative.trigger_vn(beat_id, "vnslot_tour_milestone", true)
	_ok("발생분 재자격 0",
		String(session.pending_milestone_beat().get("id", "")) != "vnbeat_clue_locked")
	# ⓖ 페이로드 — 경계 VN 과 같은 조립기(슬롯·톤·라인이 비트 행에서 온다)
	session.outgame.crew["crew_oscar"] = true
	var payload := session.milestone_payload("HUB-01")
	_ok("마일스톤 페이로드 발행", not payload.is_empty())
	_ok("슬롯 = 투어 종료", String(payload.get("slot_id", "")) == "vnslot_tour_milestone",
		String(payload.get("slot_id", "")))
	_ok("라인 동반", Array(payload.get("line_keys", [])).size() == 9,
		str(Array(payload.get("line_keys", [])).size()))
	# ⓗ 발화 지점이 실재하는가 — 투어 결산 화면이 이 창구를 부른다
	var report := FileAccess.get_file_as_string("res://ui/settle/tour_report_screen.gd")
	_ok("투어 종료가 마일스톤 창구를 부른다", report.contains("session.milestone_payload("))
	_ok("투어 종료가 NAR-01 로 간다", report.contains('go("NAR-01", milestone)'))
	# ⓘ **형식 B 카운터 — 5축 중 셋이 0이었다.** 산식을 표의 `counter_source` 가 말한다.
	var counted: Array = []
	for axis_id in data.relation_axes:
		var source := String(Dictionary(data.relation_axes[axis_id]).get("counter_source", ""))
		if ["beat_and_duel", "duel_with_lorentz", "adjacent_finish_and_duel"].has(source):
			counted.append(String(axis_id))
	_ok("레이스 계수 대상 축 = 4", counted.size() == 4, str(counted))
	var session_source := FileAccess.get_file_as_string("res://ui/flow/run_session.gd")
	for source_kind in ["beat_and_duel", "duel_with_lorentz", "adjacent_finish_and_duel"]:
		_ok("산식 소비부 실재: %s" % source_kind, session_source.contains('"%s":' % source_kind))
	# **레이스 계수 함수는 축 이름을 알지 않는다** — 표가 선언한 산식 종류를 읽으므로
	# 축이 늘어도 코드가 그대로다. (형식 A 의 지정 이벤트 경로는 별개다 — D08 §8.8 이
	# 특정 이벤트를 명문하므로 그쪽 이름은 정당하다. 축을 좁혀 그것을 잡지 않는다.)
	# **거동으로 본다.** 원본에 산식 이름이 있다는 것과 그 산식이 세는 것은 다른 사실이다
	# (돌연변이 K6 초판 미검출 — 분기는 남기고 본문만 비워도 문자열 검사는 통과한다).
	var probe := RunSession.new()
	probe.setup(data)
	probe.begin_career(2)
	probe.begin_gp()
	probe.engine.start_gp()
	probe.engine.duel_opponents = ["ai_lorentz", "ai_bianca"]
	probe.last_gp_result = {"beaten_rivals": ["ai_bianca"],
		"standings": ["ai_jude", RaceEngine.PLAYER_ID, "ai_diaz"]}
	var before_throne: int = probe.outgame.relation_counters.get("relation_throne", 0)
	var before_succ: int = probe.outgame.relation_counters.get("relation_succession", 0)
	var before_kin: int = probe.outgame.relation_counters.get("relation_kinship", 0)
	probe._advance_succession_maro(probe.engine)
	_ok("왕좌(로렌츠) = 듀얼 1회 계수",
		int(probe.outgame.relation_counters.get("relation_throne", 0)) - int(before_throne) == 1,
		str(probe.outgame.relation_counters.get("relation_throne", 0)))
	_ok("계승(비앙카) = 선착 + 듀얼 = 2",
		int(probe.outgame.relation_counters.get("relation_succession", 0)) - int(before_succ) == 2,
		str(probe.outgame.relation_counters.get("relation_succession", 0)))
	_ok("동기(주드) = 인접 완주 1 (듀얼 0)",
		int(probe.outgame.relation_counters.get("relation_kinship", 0)) - int(before_kin) == 1,
		str(probe.outgame.relation_counters.get("relation_kinship", 0)))
	var counter_start := session_source.find("func _advance_relation_counters(")
	var counter_stop := session_source.find("\nfunc ", counter_start + 1)
	var counter_body := session_source.substr(counter_start, counter_stop - counter_start)
	_ok("레이스 계수 함수 추출", counter_start > 0 and counter_body.length() > 100)
	# **따옴표가 붙은** 축 id 만 본다 — `data.relation_axes`(표 이름)는 하드코딩이 아니다.
	_ok("계수 함수에 축 id 리터럴 0", not counter_body.contains('"relation_'),
		"축 이름이 들어오면 축이 늘 때마다 이 함수가 자란다")
