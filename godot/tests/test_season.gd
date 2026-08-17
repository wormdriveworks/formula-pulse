# TC-C13 챔피언십 포인트 2계층·시즌 결산 (D14 §3) + 캘린더·그리드 레벨·레조넌스 추첨.
# 실행: godot --headless --path godot --script tests/test_season.gd
extends SceneTree

var _failures := 0
var _checked := 0


func _init() -> void:
	_d13_season_values()
	_tier_separation()
	_tour_standings_and_tiebreak()
	_dropout_handling()
	_season_close_and_grid_level()
	_early_clinch()
	_calendar_rules()
	_resonance_draw()
	_serialization()
	print("")
	# 검사 수 하한 — 클래스 로드 실패 등으로 스위트가 쪼그라들면 "통과"가 아니다.
	# 실행되지 않은 검사와 통과한 검사를 구분하는 유일한 수단이다.
	if _checked < 486:
		print("SEASON_TEST_FAIL checks=%d < 하한 486 (스위트 축소·로드 실패 의심)" % _checked)
		quit(1)
		return
	if _failures == 0:
		print("SEASON_TEST_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("SEASON_TEST_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if not condition:
		_failures += 1
		print("  [FAIL] %s %s" % [label, detail])


func _eq_float(label: String, actual: float, expected: float, tolerance: float = 0.001) -> void:
	_ok(label, absf(actual - expected) <= tolerance, "actual=%f expected=%f" % [actual, expected])


func _new_state(seed_value: int) -> SeasonState:
	var data := GameData.new()
	if not data.load_all():
		_failures += 1
		print("  [FAIL] data load")
		return null
	var rng := RngService.new()
	rng.setup(seed_value)
	var state := SeasonState.new()
	state.setup(data, rng)
	return state


# 16인 그리드의 GP 결과를 만든다 — player를 지정 순위에 놓는다.
func _gp_result(player_position: int, retired: bool = false) -> Dictionary:
	var standings: Array = []
	var filler_index := 1
	for position in range(1, 17):
		if position == player_position:
			standings.append(SeasonState.PLAYER_ID)
		else:
			standings.append("ai_%02d" % filler_index)
			filler_index += 1
	return {"standings": standings, "player_retired": retired}


# ── D13 확정값 전사 (2층 포인트 · 캘린더 구조) ──
func _d13_season_values() -> void:
	var state := _new_state(1)
	if state == null:
		return
	var data := state.data
	# D13 별첨A §6.1 2층: 25/17/14/11/9/7/5/3/2/1 (D05 기준값에서 2~8위 −1 조정분)
	var expected := {1: 25, 2: 17, 3: 14, 4: 11, 5: 9, 6: 7, 7: 5, 8: 3, 9: 2, 10: 1}
	for position in expected:
		_ok("D13 §6.1 2층 P%d = %d점" % [position, expected[position]],
			int(data.points_tier2.get(position, -1)) == int(expected[position]),
			"actual=%s" % str(data.points_tier2.get(position)))
	for position in range(11, 17):
		_ok("D13 §6.1 2층 P%d = 0점" % position, int(data.points_tier2.get(position, -1)) == 0,
			"actual=%s" % str(data.points_tier2.get(position)))
	# 1층과 2층은 별개 표다 — 같은 값이면 계층 분리가 무의미해진다
	_ok("1층 ≠ 2층 (계층 분리)", int(data.points_tier1[1]) != int(data.points_tier2[1]),
		"tier1=%s tier2=%s" % [str(data.points_tier1[1]), str(data.points_tier2[1])])
	# 캘린더 구조 (D08 §2.1 · §4.3)
	_ok("D08 §2 시즌 5투어", state.tours_per_season() == 5, "actual=%d" % state.tours_per_season())
	_ok("D08 §4.3 투어 4대회", state.races_per_tour() == 4, "actual=%d" % state.races_per_tour())
	_ok("D08 §2.1 개막전 고정 = 메트로 나이트",
		String(data.season_calendar["fixed_opening_stage"]) == "stage_metro_night",
		String(data.season_calendar["fixed_opening_stage"]))
	# D13 별첨A §3.2 투어 탈락 시 S4 50% 축소
	_eq_float("D13 §3.2 탈락 S4 비율 0.5", data.param("param_tour_dropout_s4_ratio"), 0.5)
	# D13 별첨A §7.4 그리드 레벨 폭
	_eq_float("D13 §7.4 그리드 레벨 증분 1", data.param("param_grid_level_step"), 1.0)


# ── 2계층 분리: GP 순위 → 투어 포인트 → 투어 종합 순위 → 챔피언십 포인트 ──
func _tier_separation() -> void:
	var state := _new_state(11)
	if state == null:
		return
	state.begin_season(1)
	# 4대회 전부 P1 → 투어 포인트 = 10 × 4 = 40 (D13 §6.1 1층 P1 = 10)
	for race in range(4):
		state.record_gp(_gp_result(1))
	var tier1_p1 := int(state.data.points_tier1[1])
	_ok("1층 누계 = P1 × 4", int(state.tour_points[SeasonState.PLAYER_ID]) == tier1_p1 * 4,
		"actual=%d expected=%d" % [int(state.tour_points[SeasonState.PLAYER_ID]), tier1_p1 * 4])
	var summary := state.close_tour()
	_ok("투어 종합 1위", int(summary["player_position"]) == 1, str(summary["player_position"]))
	# 2층은 투어 종합 순위로만 환산된다 — GP 포인트가 챔피언십에 직접 더해지지 않는다
	var tier2_p1 := int(state.data.points_tier2[1])
	_ok("2층 = 투어 종합 순위 환산",
		int(state.championship_points[SeasonState.PLAYER_ID]) == tier2_p1,
		"actual=%d expected=%d" % [int(state.championship_points[SeasonState.PLAYER_ID]), tier2_p1])
	_ok("2층에 1층 누계가 섞이지 않음",
		int(state.championship_points[SeasonState.PLAYER_ID]) != tier1_p1 * 4)
	# 리타이어한 GP는 1층 포인트 0 (D05 §9.2)
	var retire_state := _new_state(12)
	retire_state.begin_season(1)
	retire_state.record_gp(_gp_result(1, true))
	_ok("리타이어 = 1층 포인트 0",
		int(retire_state.tour_points.get(SeasonState.PLAYER_ID, -1)) == 0,
		"actual=%s" % str(retire_state.tour_points.get(SeasonState.PLAYER_ID)))


# ── 투어 종합 순위·동률 처리 ──
func _tour_standings_and_tiebreak() -> void:
	var state := _new_state(21)
	if state == null:
		return
	state.begin_season(1)
	state.record_gp(_gp_result(3))
	var order := state.tour_standings()
	_ok("종합 순위 = 투어 포인트 내림차순", order.size() == 16, "size=%d" % order.size())
	_ok("P3 완주 → 종합 3위", order.find(SeasonState.PLAYER_ID) == 2,
		"index=%d" % order.find(SeasonState.PLAYER_ID))
	# 동점 시 직전 그랑프리 결과 순 ([가안] — D13 §6.3 챔피언십 동률 규칙 동형 적용)
	var tie_state := _new_state(22)
	tie_state.begin_season(1)
	tie_state.tour_points = {"a": 10, "b": 10, "c": 5}
	tie_state.last_gp_standings = ["b", "a", "c"]
	var tie_order := tie_state.tour_standings()
	_ok("동점 시 직전 GP 우위가 앞", tie_order[0] == "b" and tie_order[1] == "a", str(tie_order))
	_ok("동점이 아닌 항은 포인트 순", tie_order[2] == "c", str(tie_order))


# ── 투어 탈락 (D05 §9.3 · D13 §3.2) ──
func _dropout_handling() -> void:
	var state := _new_state(31)
	if state == null:
		return
	state.begin_season(1)
	state.record_gp(_gp_result(5))
	state.record_gp(_gp_result(6))
	state.mark_dropout()          # 2대회 소화 후 탈락
	var summary := state.close_tour()
	_ok("탈락 표기", bool(summary["dropped_out"]))
	_eq_float("탈락 시 S4 50% 축소", float(summary["s4_ratio"]),
		state.data.param("param_tour_dropout_s4_ratio"))
	_ok("탈락 시 S3 미지급", not bool(summary["s3_paid"]))
	_ok("탈락 시 S10 미지급", not bool(summary["s10_paid"]))
	# 그 시점까지의 성적으로 마감된다 — 챔피언십 포인트는 여전히 부여된다
	_ok("탈락 투어도 챔피언십 포인트 환산",
		int(state.championship_points.get(SeasonState.PLAYER_ID, -1)) > 0,
		"actual=%s" % str(state.championship_points.get(SeasonState.PLAYER_ID)))
	# 시즌은 중단되지 않는다 — 다음 투어가 개막한다
	_ok("탈락 후 다음 투어 개막", state.tour_slot == 2, "tour_slot=%d" % state.tour_slot)
	_ok("다음 투어에서 탈락 상태 해제", not state.tour_dropped_out)
	_ok("다음 투어 투어 포인트 초기화", state.tour_points.is_empty(), str(state.tour_points))
	# 정상 완주 투어는 전액 지급
	var normal := _new_state(32)
	normal.begin_season(1)
	for race in range(4):
		normal.record_gp(_gp_result(2))
	var normal_summary := normal.close_tour()
	_eq_float("완주 시 S4 전액", float(normal_summary["s4_ratio"]), 1.0)
	_ok("완주 시 S3 지급", bool(normal_summary["s3_paid"]))


# ── 시즌 결산·그리드 레벨·에필로그 (D05 §9.4~§10 · D13 §7.4) ──
func _season_close_and_grid_level() -> void:
	var state := _new_state(41)
	if state == null:
		return
	state.begin_season(1)
	# 5투어 전부 종합 1위 → 시즌 챔피언
	for tour in range(5):
		for race in range(4):
			state.record_gp(_gp_result(1))
		state.close_tour()
	_ok("시즌은 5투어를 소화한다", state.season_finished(), "tour_slot=%d" % state.tour_slot)
	var tier2_p1 := int(state.data.points_tier2[1])
	_ok("챔피언십 누계 = 2층 P1 × 5투어",
		int(state.championship_points[SeasonState.PLAYER_ID]) == tier2_p1 * 5,
		"actual=%d" % int(state.championship_points[SeasonState.PLAYER_ID]))
	var result := state.close_season()
	_ok("시즌 챔피언 = 플레이어", String(result["champion"]) == SeasonState.PLAYER_ID, str(result["champion"]))
	_ok("챔피언십 1위", int(result["player_position"]) == 1, str(result["player_position"]))
	# 그리드 레벨은 챔피언 달성 시즌의 다음 시즌부터 +1
	_ok("챔피언 → 그리드 레벨 +1", int(result["grid_level_next"]) == 1, str(result["grid_level_next"]))
	_ok("1회 우승은 에필로그 아님", not bool(result["epilogue"]))
	# 2연속 챔피언 = 에필로그 (D05 §10 · D08 §8.9)
	state.begin_season(2)
	for tour in range(5):
		for race in range(4):
			state.record_gp(_gp_result(1))
		state.close_tour()
	var result2 := state.close_season()
	_ok("2연속 챔피언 = 에필로그", bool(result2["epilogue"]), str(result2))
	_ok("그리드 레벨 누적 +2", int(result2["grid_level_next"]) == 2, str(result2["grid_level_next"]))
	# 실패해도 그리드 레벨은 유지된다 (D13 §7.4)
	state.begin_season(3)
	for tour in range(5):
		for race in range(4):
			state.record_gp(_gp_result(9))
		state.close_tour()
	var result3 := state.close_season()
	_ok("챔피언 실패 시 그리드 레벨 유지", int(result3["grid_level_next"]) == 2,
		str(result3["grid_level_next"]))
	_ok("챔피언 실패 = 에필로그 아님", not bool(result3["epilogue"]))
	_ok("연속 기록 초기화", String(result3["champion"]) != SeasonState.PLAYER_ID)
	# ── 순위 밖 절상 (총괄 판정 IMPL-141 ① · 집행 IMPL-142) ──
	# 플레이어가 챔피언십 순위표에 없는 시즌(전 GP 미기록·이상 종료)에도 D06 §5.3 G-M1은
	# "성적 무관 최소 1슬롯"을 보장한다. 0을 흘리면 등급 표에 걸리는 행이 없어 빈 추첨이 된다.
	var outsider := _new_state(43)
	if outsider == null:
		return
	outsider.begin_season(1)
	var out_result := outsider.close_season()
	var grid_size := outsider.data.grid_int("filler_count") \
		+ outsider.data.grid_array("rivals").size() + 1
	_ok("순위 밖 플레이어는 순위표에 없다",
		not outsider.championship_standings().has(SeasonState.PLAYER_ID))
	_ok("순위 밖 → 0이 아니다 (0 오염 차단)", int(out_result["player_position"]) != 0,
		str(out_result["player_position"]))
	_ok("순위 밖 → 1이 아니다 (최상위 대우 차단)", int(out_result["player_position"]) != 1,
		str(out_result["player_position"]))
	_ok("순위 밖 → 최하위 순위로 절상", int(out_result["player_position"]) == grid_size,
		"actual=%d grid=%d" % [int(out_result["player_position"]), grid_size])
	# ── 투어 쪽 동형 절상 (총괄 판정 IMPL-166 ③ · 집행 IMPL-169) ──
	# 시즌 건과 나란히 둔다. 투어 쪽이 더 날카롭다 — 소비처 `record_tour_result()` 가
	# `position <= 1` 로 투어 우승을 세므로, 절상이 없으면 **무순위가 투어 우승으로 뒤집힌다**.
	var tour_outsider := _new_state(44)
	if tour_outsider == null:
		return
	tour_outsider.begin_season(1)
	var tour_result := tour_outsider.close_tour()
	_ok("투어 순위 밖 플레이어는 순위표에 없다",
		not Array(tour_result["standings"]).has(SeasonState.PLAYER_ID),
		str(tour_result["standings"]))
	_ok("투어 순위 밖 → 0이 아니다 (우승 오계상 차단)",
		int(tour_result["player_position"]) != 0, str(tour_result["player_position"]))
	_ok("투어 순위 밖 → 1이 아니다 (최상위 대우 차단)",
		int(tour_result["player_position"]) != 1, str(tour_result["player_position"]))
	_ok("투어 순위 밖 → 최하위 순위로 절상",
		int(tour_result["player_position"]) == grid_size,
		"actual=%d grid=%d" % [int(tour_result["player_position"]), grid_size])
	# 절상값이 소비처에서 실제로 우승으로 세어지지 않는지까지 본다 —
	# 값만 고치고 소비처가 다른 축을 보고 있으면 교정이 성립하지 않는다.
	_ok("투어 우승 누계 무증가", tour_outsider.season_tour_wins == 0,
		"actual=%d" % tour_outsider.season_tour_wins)


# ── 조기 확정 (D08 §5.5): 공표만 하고 시즌은 계속된다 ──
func _early_clinch() -> void:
	var state := _new_state(51)
	if state == null:
		return
	state.begin_season(1)
	_ok("개막 시점 조기 확정 없음", state.clinched_leader() == "")
	# 4투어 연속 종합 1위 → 잔여 1투어 최대 25점으로 뒤집을 수 없는 격차
	for tour in range(4):
		for race in range(4):
			state.record_gp(_gp_result(1))
		state.close_tour()
	var leader := state.clinched_leader()
	_ok("수학적 조기 확정 판정", leader == SeasonState.PLAYER_ID, "leader=%s" % leader)
	_ok("조기 확정에도 시즌은 계속된다 (5투어 소화)", not state.season_finished(),
		"tour_slot=%d" % state.tour_slot)
	# 격차가 잔여 최대 획득량 이내면 확정되지 않는다
	var close_state := _new_state(52)
	close_state.begin_season(1)
	close_state.championship_points = {"player": 30, "rival": 20}
	close_state.tour_slot = 5
	_ok("격차 ≤ 잔여 최대 → 미확정", close_state.clinched_leader() == "",
		"leader=%s" % close_state.clinched_leader())


# ── 캘린더 규칙 (D08 §2.1~§2.2) ──
func _calendar_rules() -> void:
	var state := _new_state(61)
	if state == null:
		return
	# 시즌 1 = 정순 고정 (D08 §4.1 확정: 메트로 → 아주르 → 알타 → 미라지 → 돔).
	# 캘린더 데이터가 문서 정순과 갈리면 여기서 깨진다 — 셔플 풀 순서 변조 검출.
	var season1 := state.build_calendar(1, [])
	var expected_season1: Array = ["stage_metro_night", "stage_azure_coast", "stage_alta_ridge",
		"stage_mirage_flat", "stage_pulse_dome"]
	_ok("D08 §4.1 시즌 1 정순 5무대", season1 == expected_season1, str(season1))
	_ok("D08 §5.1 최종 무대 고정 = 펄스 돔 (로렌츠 슬롯·무대 이중 고정)",
		String(state.data.season_calendar["fixed_final_stage"]) == "stage_pulse_dome",
		String(state.data.season_calendar["fixed_final_stage"]))
	# season1_tour_slot 필드가 정순 위치와 동기인지 (무대 데이터 ↔ 캘린더 이중 기입의 정합)
	for index in range(expected_season1.size()):
		var stage_row: Dictionary = state.data.stages.get(String(expected_season1[index]), {})
		_ok("무대 %s season1_tour_slot = %d" % [expected_season1[index], index + 1],
			int(stage_row.get("season1_tour_slot", -1)) == index + 1,
			"actual=%s" % str(stage_row.get("season1_tour_slot")))
	# 시즌 2+ = 투어 1·5 고정 + 투어 2~4 셔플 (실데이터 경로 — 셔플 결과도 경계 불변)
	var season2 := state.build_calendar(2, season1)
	_ok("시즌 2 개막전 고정 유지", season2.size() == 5 and String(season2[0]) == "stage_metro_night",
		str(season2))
	_ok("시즌 2 최종전 고정 유지", String(season2[4]) == "stage_pulse_dome", str(season2))
	_ok("시즌 2 중간 3무대 = 셔플 풀 구성",
		_same_multiset(season2.slice(1, 4), ["stage_azure_coast", "stage_alta_ridge", "stage_mirage_flat"]),
		str(season2))
	# 셔플 규칙 — 규칙 자체(직전 편성 재출현 금지·균등 추첨)는 콘텐츠와 무관하게 성립해야 한다.
	var pool: Array = ["a", "b", "c"]
	var previous: Array = ["a", "b", "c"]
	var seen: Dictionary = {}
	for attempt in range(200):
		var shuffled := state.shuffle_middle(pool, previous)
		_ok("셔플 결과가 풀과 동일 구성", _same_multiset(shuffled, pool), str(shuffled))
		_ok("직전 편성 재출현 금지", shuffled != previous, str(shuffled))
		seen[str(shuffled)] = true
	_ok("6조합 중 직전 제외 5개가 모두 등장", seen.size() == 5, "seen=%d" % seen.size())
	# 직전이 없으면 6조합 전부 허용
	var first_seen: Dictionary = {}
	for attempt in range(300):
		first_seen[str(state.shuffle_middle(pool, []))] = true
	_ok("직전 없으면 6조합 전부 가능", first_seen.size() == 6, "seen=%d" % first_seen.size())
	# 단일 원소 풀은 셔플 대상이 아니다
	_ok("단일 풀은 그대로", state.shuffle_middle(["x"], []) == ["x"])
	_start_grid_rule()


# ── 시작 그리드 산정 (D13 별첨A §6.3 — TL-5 러너가 적발한 미구현분) ──
# 선재 구멍: 엔진이 매 GP 디버그 고정값(P16)을 썼다. 순위 상승 경로가 구조적으로 없어
# 챔피언십 중앙값이 항상 최하위였고 D13 §4.3 도달률 발주가 성립 불가였다.
func _start_grid_rule() -> void:
	var state := _new_state(71)
	if state == null:
		return
	state.begin_season(1)
	var grid_size := state.data.grid_int("filler_count") + state.data.grid_array("rivals").size() + 1
	_ok("D08 §3.5 개막전 = P%d 고정" % grid_size, state.player_start_rank() == grid_size,
		"actual=%d" % state.player_start_rank())
	# 투어 내 2~4전 = 직전 그랑프리 결과 기반
	state.record_gp(_gp_result(6))
	_ok("투어 내 2전 = 직전 GP 결과 (P6)", state.player_start_rank() == 6,
		"actual=%d" % state.player_start_rank())
	state.record_gp(_gp_result(2))
	_ok("투어 내 3전 = 직전 GP 결과 (P2)", state.player_start_rank() == 2,
		"actual=%d" % state.player_start_rank())
	# 투어 첫 그랑프리 = 챔피언십 순위 기반
	state.record_gp(_gp_result(1))
	state.record_gp(_gp_result(1))
	state.close_tour()
	var championship_index := state.championship_standings().find(SeasonState.PLAYER_ID) + 1
	_ok("투어 2 개막 = 챔피언십 순위 기반", state.player_start_rank() == championship_index,
		"actual=%d championship=%d" % [state.player_start_rank(), championship_index])
	# 경로가 실제로 갈렸는지 — 개막전 고정값과 같으면 분기가 죽어 있어도 통과한다
	_ok("투어 2 개막 ≠ 개막전 고정값", state.player_start_rank() != grid_size,
		"actual=%d" % state.player_start_rank())
	# 챔피언십 무득점자는 최하위 기준 — 순위표에 없으면 그리드 최후미
	var fresh := _new_state(72)
	fresh.begin_season(2)
	_ok("시즌 2 개막 무득점 = 최후미", fresh.player_start_rank() == grid_size,
		"actual=%d" % fresh.player_start_rank())
	# 엔진 주입 경로 — 산정값이 실제 시작 포지션이 된다 (주입이 끊기면 여기서 깨진다)
	var engine := RaceEngine.new()
	engine.setup(state.data, state.rng)
	state.apply_to_engine(engine)
	_ok("엔진 주입 = 산정값", engine.player_start_rank == state.player_start_rank(),
		"engine=%d state=%d" % [engine.player_start_rank, state.player_start_rank()])
	state.data.select_circuit("circuit_mn1")
	engine.start_gp()
	_ok("실제 시작 포지션 = 산정값", engine.player_position() == state.player_start_rank(),
		"actual=%d expected=%d" % [engine.player_position(), state.player_start_rank()])


func _same_multiset(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var sorted_a := a.duplicate()
	var sorted_b := b.duplicate()
	sorted_a.sort()
	sorted_b.sort()
	return sorted_a == sorted_b


# ── 레조넌스 추첨 (D08 §3.7 R6: 투어 개막 1회 · 서킷 슬롯 × 섹터 슬롯 · 위치 비공개) ──
func _resonance_draw() -> void:
	var state := _new_state(71)
	if state == null:
		return
	state.begin_season(1)
	_ok("투어 개막 시 서킷 추첨", state.data.circuits.has(state.resonance_circuit_id),
		"circuit=%s" % state.resonance_circuit_id)
	var sectors := int(state.data.circuits[state.resonance_circuit_id]["sectors_per_lap"])
	_ok("섹터 슬롯이 해당 서킷 범위 내",
		state.resonance_sector_slot >= 1 and state.resonance_sector_slot <= sectors,
		"slot=%d sectors=%d" % [state.resonance_sector_slot, sectors])
	# 무대의 서킷 4종 전부가 추첨 대상이 된다 (서킷 축이 실제로 추첨된다)
	var picked_circuits: Dictionary = {}
	for seed_value in range(40):
		var probe := _new_state(1000 + seed_value)
		probe.begin_season(1)
		picked_circuits[probe.resonance_circuit_id] = true
	_ok("서킷 슬롯 추첨이 4종에 분포", picked_circuits.size() >= 3, str(picked_circuits.keys()))
	# 투어가 바뀌면 다시 추첨된다 (무대당 1회 — 투어 경계에서 재추첨)
	var before_state := str(state.rng.stream("resonance").state)
	state.tour_slot = 1
	state.begin_tour()
	var after_state := str(state.rng.stream("resonance").state)
	_ok("투어 개막마다 재추첨 수행",
		state.resonance_circuit_id != "" and state.resonance_sector_slot > 0,
		"circuit=%s slot=%d" % [state.resonance_circuit_id, state.resonance_sector_slot])
	# 값 변화 자체는 단언할 수 없다(같은 값이 다시 뽑힐 수 있다). 대신 재추첨이 실제로
	# resonance 스트림을 소비했는지를 본다 — 소비가 없으면 추첨이 일어나지 않은 것이다.
	_ok("재추첨이 resonance 스트림을 소비", after_state != before_state,
		"before=%s after=%s" % [before_state, after_state])


# ── 직렬화 (시즌 진행은 세이브의 핵심 축 — D12 §7.1) ──
func _serialization() -> void:
	var state := _new_state(81)
	if state == null:
		return
	state.begin_season(1)
	for race in range(3):
		state.record_gp(_gp_result(4))
	var payload := state.serialize()
	var restored := _new_state(9999)
	_ok("복원 성립", restored.restore(payload))
	_ok("시즌·투어·대회 슬롯 복원",
		restored.season == state.season and restored.tour_slot == state.tour_slot
		and restored.race_slot == state.race_slot,
		"season=%d tour=%d race=%d" % [restored.season, restored.tour_slot, restored.race_slot])
	_ok("투어 포인트 복원",
		int(restored.tour_points[SeasonState.PLAYER_ID]) == int(state.tour_points[SeasonState.PLAYER_ID]))
	_ok("레조넌스 추첨 결과 복원",
		restored.resonance_circuit_id == state.resonance_circuit_id
		and restored.resonance_sector_slot == state.resonance_sector_slot,
		"circuit=%s slot=%d" % [restored.resonance_circuit_id, restored.resonance_sector_slot])
	_ok("캘린더 복원", restored.calendar == state.calendar, str(restored.calendar))
	var broken := _new_state(9999)
	_ok("결손 payload 거부", not broken.restore({"season": 1}))
