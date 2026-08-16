# 아웃게임 검증 시나리오 TC-O (D14 §4) — 헤드리스 자동화분.
# 실행: godot --headless --path godot --script tests/test_tc_o.gd
#
# 범위 (사용자 확정 — IMPL-021): 아웃게임 **시스템은 전량** · 콘텐츠만 무대 1 한정.
extends SceneTree

var _failures := 0
var _checked := 0


func _init() -> void:
	_d13_outgame_values()
	_tc_o1_facilities()
	_tc_o2_tuning_and_overhaul()
	_overhaul_candidate_draw()
	_milestones_and_achievements()
	_tc_o3_sponsors()
	_tc_o5_archive()
	_tc_o6_exchange_guards()
	_tc_o7_skill_tiers_and_crew()
	_tc_o8_relation_counters()
	_repair_and_consumables()
	_serialization()
	print("")
	# 검사 수 하한 — 클래스 로드 실패 등으로 스위트가 쪼그라들면 "통과"가 아니다.
	# 실행되지 않은 검사와 통과한 검사를 구분하는 유일한 수단이다.
	if _checked < 378:
		print("TC_O_TEST_FAIL checks=%d < 하한 378 (스위트 축소·로드 실패 의심)" % _checked)
		quit(1)
		return
	if _failures == 0:
		print("TC_O_TEST_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("TC_O_TEST_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if not condition:
		_failures += 1
		print("  [FAIL] %s %s" % [label, detail])


func _eq_float(label: String, actual: float, expected: float, tolerance: float = 0.001) -> void:
	_ok(label, absf(actual - expected) <= tolerance, "actual=%f expected=%f" % [actual, expected])


func _new_state() -> OutgameState:
	var data := GameData.new()
	if not data.load_all():
		_failures += 1
		print("  [FAIL] data load")
		return null
	var state := OutgameState.new()
	state.setup(data)
	return state


# 그리드 규모 = 순위 밖 절상값 (SeasonState._grid_size()와 동일 구조 산출 — 상수 기입 금지)
func _grid_size_of(state: OutgameState) -> int:
	return state.data.grid_int("filler_count") + state.data.grid_array("rivals").size() + 1


# ── D13 확정값 전사 (§3~§5·§7) ──
func _d13_outgame_values() -> void:
	var state := _new_state()
	if state == null:
		return
	var data := state.data
	# §4.1 축적형 단가
	var expected_skill_dp := {1: 30, 2: 55, 3: 75}
	for skill_id in data.skills:
		var row: Dictionary = data.skills[skill_id]
		var skill_tier := CsvTable.to_int(String(row["skill_tier"]))
		_ok("D13 §4.1 %s 해금 단가 = 티어 %d 단가" % [skill_id, skill_tier],
			CsvTable.to_int(String(row["unlock_dp"])) == int(expected_skill_dp[skill_tier]),
			"actual=%s" % String(row["unlock_dp"]))
	_ok("D07 §4.3 스킬 16종", data.skills.size() == 16, "actual=%d" % data.skills.size())
	# 티어 구성 6/6/4 (D07 §4.3)
	var tier_counts := {1: 0, 2: 0, 3: 0}
	for skill_id in data.skills:
		var skill_tier := CsvTable.to_int(String(data.skills[skill_id]["skill_tier"]))
		tier_counts[skill_tier] = int(tier_counts[skill_tier]) + 1
	_ok("D07 §4.3 티어 구성 6/6/4",
		int(tier_counts[1]) == 6 and int(tier_counts[2]) == 6 and int(tier_counts[3]) == 4,
		str(tier_counts))
	# §4.1 덱 슬롯 확장 70/110/160 · 크루 65/80/100 · 시설 45/55/65/75
	_eq_float("D13 §4.1 덱 확장 1단 70", data.param("param_deck_expand_dp1"), 70.0)
	_eq_float("D13 §4.1 덱 확장 2단 110", data.param("param_deck_expand_dp2"), 110.0)
	_eq_float("D13 §4.1 덱 확장 3단 160", data.param("param_deck_expand_dp3"), 160.0)
	var expected_crew := {"crew_nadia": 65, "crew_oscar": 80, "crew_sasha": 100}
	for crew_id in expected_crew:
		_ok("D13 §4.1 %s 영입 %d DP" % [crew_id, expected_crew[crew_id]],
			CsvTable.to_int(String(data.crew[crew_id]["recruit_dp"])) == int(expected_crew[crew_id]),
			String(data.crew[crew_id]["recruit_dp"]))
	var expected_facility := {"facility_g1": 45, "facility_g2": 55, "facility_g3": 65, "facility_g4": 75}
	for facility_id in expected_facility:
		_ok("D13 §4.1 %s %d DP" % [facility_id, expected_facility[facility_id]],
			CsvTable.to_int(String(data.facility(facility_id)["cost_dp"])) == int(expected_facility[facility_id]),
			String(data.facility(facility_id)["cost_dp"]))
	# §4.1 축적형 합계 = 1,635 DP (스킬 180+330+300 · 덱 340 · 크루 245 · 시설 240)
	var total := 0
	for skill_id in data.skills:
		total += CsvTable.to_int(String(data.skills[skill_id]["unlock_dp"]))
	total += data.param_int("param_deck_expand_dp1") + data.param_int("param_deck_expand_dp2") \
		+ data.param_int("param_deck_expand_dp3")
	for crew_id in data.crew:
		total += CsvTable.to_int(String(data.crew[crew_id]["recruit_dp"]))
	for facility_id in data.facilities:
		total += CsvTable.to_int(String(data.facilities[facility_id]["cost_dp"]))
	_ok("D13 §4.1 축적형 총 소요 1,635 DP", total == 1635, "actual=%d" % total)
	# §3.5 튜닝 비용 (기본 4계통 · 심화 2계통 ×1.4)
	var basic_costs := [400, 700, 1100, 1700, 2600]
	for tuning_id in ["tuning_t1", "tuning_t2", "tuning_t3", "tuning_t4"]:
		for step in range(1, 6):
			_ok("D13 §3.5 %s 단계 %d = %d Cr" % [tuning_id, step, basic_costs[step - 1]],
				state.tuning_cost(tuning_id, step) == int(basic_costs[step - 1]),
				"actual=%d" % state.tuning_cost(tuning_id, step))
	var advanced_costs := [560, 980, 1540, 2380, 3640]
	for tuning_id in ["tuning_t5", "tuning_t6"]:
		for step in range(1, 6):
			_ok("D13 §3.5 %s 단계 %d = %d Cr" % [tuning_id, step, advanced_costs[step - 1]],
				state.tuning_cost(tuning_id, step) == int(advanced_costs[step - 1]),
				"actual=%d" % state.tuning_cost(tuning_id, step))
	# 심화 = 기본 × 1.4 (D13 §3.5 명문)
	for step in range(1, 6):
		_eq_float("D13 §3.5 심화 = 기본 × 1.4 (단계 %d)" % step,
			float(advanced_costs[step - 1]), float(basic_costs[step - 1]) * 1.4, 1.0)
	# §3.5 효과: 기본 3계통 +7% · T4 +5 CH · T5 +4 판정 · T6 −7%
	_eq_float("D13 §3.5 T1 단계당 +7%",
		CsvTable.to_float(String(data.tuning_line("tuning_t1")["effect_per_step"])), 0.07)
	_eq_float("D13 §3.5 T4 단계당 +5 CH",
		CsvTable.to_float(String(data.tuning_line("tuning_t4")["effect_per_step"])), 5.0)
	_eq_float("D13 §3.5 T5 단계당 +4 판정",
		CsvTable.to_float(String(data.tuning_line("tuning_t5")["effect_per_step"])), 4.0)
	_eq_float("D13 §3.5 T6 단계당 −7%",
		CsvTable.to_float(String(data.tuning_line("tuning_t6")["effect_per_step"])), -0.07)
	_eq_float("D13 §3.5 환급률 80%", data.param("param_tuning_refund_ratio"), 0.80)
	# §3.6 소모품 단가
	var expected_consumable := {"consumable_p1": 250, "consumable_p2": 320, "consumable_p3": 400}
	for consumable_id in expected_consumable:
		_ok("D13 §3.6 %s %d Cr" % [consumable_id, expected_consumable[consumable_id]],
			CsvTable.to_int(String(data.consumable(consumable_id)["cost_cr"])) == int(expected_consumable[consumable_id]),
			String(data.consumable(consumable_id)["cost_cr"]))
	_eq_float("D13 §3.6 휴대 상한 2", data.param("param_consumable_carry_cap"), 2.0)
	# §3.4 정비
	_eq_float("D13 §3.4 정비 기준액 200", data.param("param_repair_base_cr"), 200.0)
	_eq_float("D13 §3.4 회차 체증 1.5", data.param("param_repair_escalation"), 1.5)
	_eq_float("D13 §3.4 전면 정비 20 Cr/CH", data.param("param_repair_full_cr_per_ch"), 20.0)
	_eq_float("D13 §3.4 무상 복원선 70", data.param("param_repair_free_restore_line"), 70.0)
	# §5.1 크루 패시브
	_eq_float("D13 §5.1 마르타 환급 90%",
		CsvTable.to_float(String(data.crew["crew_marta"]["passive_value"])), 0.90)
	_eq_float("D13 §5.1 테오 정비 −10%",
		CsvTable.to_float(String(data.crew["crew_theo"]["passive_value"])), -0.10)
	_eq_float("D13 §5.1 사샤 해금 −10%",
		CsvTable.to_float(String(data.crew["crew_sasha"]["passive_value"])), -0.10)
	_eq_float("D13 §5.1 나디아 후보 4종",
		CsvTable.to_float(String(data.crew["crew_nadia"]["passive_value"])), 4.0)
	# §5.3 스폰서
	var expected_sponsor := {
		"sponsor_sp1": [500, 200], "sponsor_sp2": [250, 300],
		"sponsor_sp3": [250, 350], "sponsor_sp4": [500, 400],
	}
	for sponsor_id in expected_sponsor:
		var row: Dictionary = data.sponsors[sponsor_id]
		_ok("D13 §5.3 %s 정기 %d Cr" % [sponsor_id, expected_sponsor[sponsor_id][0]],
			CsvTable.to_int(String(row["regular_cr"])) == int(expected_sponsor[sponsor_id][0]),
			String(row["regular_cr"]))
		_ok("D13 §5.3 %s 보너스 %d Cr" % [sponsor_id, expected_sponsor[sponsor_id][1]],
			CsvTable.to_int(String(row["bonus_cr"])) == int(expected_sponsor[sponsor_id][1]),
			String(row["bonus_cr"]))
	# §5.4 베인 임계
	_eq_float("D13 §5.4 베인 2단계 290 DP", data.param("param_vane_stage2_dp"), 290.0)
	_eq_float("D13 §5.4 베인 3단계 820 DP", data.param("param_vane_stage3_dp"), 820.0)
	# §7.2 오버홀 12종 · §7.3 캡
	_ok("D13 §7.2 오버홀 12종", data.overhauls.size() == 12, "actual=%d" % data.overhauls.size())
	_eq_float("D13 §7.3 파츠 계통당 캡 +10%p", data.param("param_parts_cap_per_line"), 0.10)
	_eq_float("D13 §7.3 파츠 합산 캡 +20%p", data.param("param_parts_cap_total"), 0.20)
	# §7.2 사이드그레이드 4종은 전부 양수 효과 + 음수 대가 쌍 (순수 상향 아님 — 결정 #9 근거)
	var sidegrades := 0
	for overhaul_id in data.overhauls:
		var row: Dictionary = data.overhauls[overhaul_id]
		if String(row["kind"]) != "sidegrade":
			continue
		sidegrades += 1
		_ok("D13 §7.2 %s 대가 존재" % overhaul_id, String(row["drawback"]).strip_edges() != "",
			String(row["drawback"]))
	_ok("D13 §7.2 사이드그레이드 4종", sidegrades == 4, "actual=%d" % sidegrades)
	# §2.2 환전
	_eq_float("D13 §2.2 환전 상한 5차지", data.param("param_charge_exchange_cap"), 5.0)
	_eq_float("D13 §2.2 환전율 20 Cr/차지", data.param("param_charge_exchange_cr"), 20.0)
	# §3.1~3.2 결산 보상
	_eq_float("D13 §3.1 상금 기저 300", data.param("param_prize_base_cr"), 300.0)
	_eq_float("D13 §3.1 투어 포인트당 100", data.param("param_prize_per_tour_point_cr"), 100.0)
	_eq_float("D13 §3.1 완주 보너스 200", data.param("param_finish_bonus_cr"), 200.0)
	# S1과 S2는 별개 Source다 (D06 §2.1) — 표의 값도 각각 대조한다
	_ok("D13 §3.1 S1 P1 = 1,300 Cr", state.gp_prize(10, true) == 1300,
		"actual=%d" % state.gp_prize(10, true))
	_ok("D13 §3.1 S1 P9↓ = 300 Cr", state.gp_prize(0, true) == 300,
		"actual=%d" % state.gp_prize(0, true))
	_ok("D13 §3.1 S2 완주 보너스 200 Cr", state.finish_bonus(true) == 200,
		"actual=%d" % state.finish_bonus(true))
	_ok("D13 §3.1 리타이어 시 S1 = 0", state.gp_prize(10, false) == 0,
		"actual=%d" % state.gp_prize(10, false))
	_ok("D13 §3.1 리타이어 시 S2 = 0", state.finish_bonus(false) == 0,
		"actual=%d" % state.finish_bonus(false))
	# P2 상금 1,100 = 300 + 8×100 (표의 다른 행도 산식으로 재구성되는지)
	_ok("D13 §3.1 S1 P2 = 1,100 Cr", state.gp_prize(8, true) == 1100,
		"actual=%d" % state.gp_prize(8, true))
	var s4_p1 := state.settlement_reward("tour", 1)
	_ok("D13 §3.2 S4 1위 1,200 Cr / 70 DP",
		int(s4_p1["credits"]) == 1200 and int(s4_p1["dp"]) == 70, str(s4_p1))
	var s6_p1 := state.settlement_reward("season", 1)
	_ok("D13 §3.2 S6 1위 4,000 Cr / 120 DP",
		int(s6_p1["credits"]) == 4000 and int(s6_p1["dp"]) == 120, str(s6_p1))
	var s4_p9 := state.settlement_reward("tour", 12)
	_ok("D13 §3.2 S4 9위 이하 200 Cr / 22 DP",
		int(s4_p9["credits"]) == 200 and int(s4_p9["dp"]) == 22, str(s4_p9))


# ── TC-O1 개러지 시설 (D07 §2.2) — 해금·비용·G4 선행 조건 ──
func _tc_o1_facilities() -> void:
	var state := _new_state()
	if state == null:
		return
	_ok("초기 시설 0", state.facilities.is_empty())
	_ok("DP 부족 시 해금 실패", not state.unlock_facility("facility_g1"))
	state.gain_drive_data(45)
	_ok("G1 해금 성립", state.unlock_facility("facility_g1"))
	_ok("G1 해금 후 DP 소진", state.drive_data == 0, "dp=%d" % state.drive_data)
	_ok("중복 해금 거부", not state.unlock_facility("facility_g1"))
	# G4는 나디아 합류가 선행 조건 (D07 §2.2)
	state.gain_drive_data(1000)
	_ok("나디아 미합류 시 G4 거부", not state.unlock_facility("facility_g4"))
	_ok("나디아 영입", state.recruit_crew("crew_nadia"))
	_ok("나디아 합류 후 G4 해금", state.unlock_facility("facility_g4"))
	# 시설은 스탯에 관여하지 않는다 (D07 §2.2 · D06 §3.2 비중첩) — 구조 단언
	for facility_id in state.data.facilities:
		var effect := String(state.data.facilities[facility_id]["effect"])
		_ok("시설 %s 효과가 편의·선택지 축" % facility_id,
			["archive_deep_tab", "recall_playback", "deck_preset_slot", "sponsor_slot_plus"].has(effect),
			effect)


# ── TC-O2 튜닝 곡선·오버홀 12종 (D07 §3.2·§3.4 · D13 별첨A §3.5·§7) ──
func _tc_o2_tuning_and_overhaul() -> void:
	var state := _new_state()
	if state == null:
		return
	# 체증 곡선: 단계를 순차로만 살 수 있고 비용이 단계별로 오른다
	state.gain_credits(400 + 700 + 1100)
	_ok("튜닝 1단계", state.buy_tuning("tuning_t1"))
	_ok("튜닝 2단계", state.buy_tuning("tuning_t1"))
	_ok("튜닝 3단계", state.buy_tuning("tuning_t1"))
	_ok("단계 누계 = 3", state.tuning_step("tuning_t1") == 3, "step=%d" % state.tuning_step("tuning_t1"))
	_ok("잔액 소진 후 4단계 실패", not state.buy_tuning("tuning_t1"))
	# 5단계 상한
	state.gain_credits(1700 + 2600 + 5000)
	_ok("4단계", state.buy_tuning("tuning_t1"))
	_ok("5단계", state.buy_tuning("tuning_t1"))
	_ok("5단계 상한 초과 거부", not state.buy_tuning("tuning_t1"))
	_ok("상한 = D13 5단계", state.tuning_step("tuning_t1") == state.data.param_int("param_tuning_max_step"))
	# 재배분 환급 — 마르타 합류 상태이므로 90%
	var spent := 400 + 700 + 1100 + 1700 + 2600
	var before := state.credits
	var refund := state.redistribute_tuning("tuning_t1")
	_eq_float("마르타 패시브 환급 90%", float(refund), float(spent) * 0.90, 1.0)
	_ok("환급 후 단계 0", state.tuning_step("tuning_t1") == 0)
	_ok("환급이 크레딧에 반영", state.credits == before + refund)
	# 오버홀 슬롯 구조 (D13 별첨A §7.1)
	var top := state.overhaul_slots(1)
	_ok("1~3위 = 2슬롯 5후보", int(top["slots"]) == 2 and int(top["candidates"]) == 5, str(top))
	var mid := state.overhaul_slots(5)
	_ok("4~8위 = 1슬롯 4후보", int(mid["slots"]) == 1 and int(mid["candidates"]) == 4, str(mid))
	var low := state.overhaul_slots(12)
	_ok("9위 이하 = 1슬롯 2후보 (G-M1 바닥 보장)",
		int(low["slots"]) == 1 and int(low["candidates"]) == 2, str(low))
	# **순위 밖 = 최하위 등급** — 총괄 판정 IMPL-141 ① 집행 (IMPL-142).
	# 절상은 `close_season()` 원천 전속이므로 등급 표 자체는 여전히 순위 1~16 전속이다.
	# 이 두 검사가 짝을 이뤄 "표에 0 행이 없다 + 절상값이 최하위 등급을 문다"를 못박는다.
	_ok("등급 표 = 순위 1~16 전속 (0 행 없음 — 절상은 원천 전속)",
		state.overhaul_slots(0).is_empty())
	var out_of_order := state.overhaul_slots(_grid_size_of(state))
	_ok("순위 밖 절상값 → 최하위 등급 1슬롯·2후보 (G-M1 바닥 보장)",
		int(out_of_order["slots"]) == 1 and int(out_of_order["candidates"]) == 2, str(out_of_order))
	# 슬롯 초과 장착 거부
	_ok("1슬롯 장착", state.install_overhaul("overhaul_ov_p1", 5))
	_ok("1슬롯 초과 거부", not state.install_overhaul("overhaul_ov_p2", 5))
	# G-M2 캡: 파츠 계통당 +10%p · 합산 +20%p (D13 별첨A §7.3 구속)
	var capped := _new_state()
	capped.install_overhaul("overhaul_ov_p1", 1)
	capped.install_overhaul("overhaul_ov_p2", 1)
	_eq_float("파츠 계통당 캡 +10%p", capped.parts_stat_bonus("slipstream_coef"), 0.10)
	_eq_float("파츠 합산 캡 준수", capped.parts_stat_bonus("slipstream_coef")
		+ capped.parts_stat_bonus("braking_coef"), 0.20, 0.0001)
	# OV-S4는 무상 복원선을 70 → 80으로 올린다
	var restore_state := _new_state()
	_ok("기본 무상 복원선 70", restore_state.free_restore_line() == 70,
		"actual=%d" % restore_state.free_restore_line())
	restore_state.install_overhaul("overhaul_ov_s4", 1)
	_ok("OV-S4 장착 시 80", restore_state.free_restore_line() == 80,
		"actual=%d" % restore_state.free_restore_line())


# ── 시즌 오버홀 후보 추첨 (D06 §5.3 · D13 §7.1 — T3 결선) ──
# 추첨 스트림 = reserve [가안 — D12 §6.1 예비 스트림의 첫 소비처] · 결과는 상태 보존 (재로드 리롤 무효).
func _overhaul_candidate_draw() -> void:
	var state := _new_state()
	if state == null:
		return
	var rng := RngService.new()
	rng.setup(777)
	# 등급별 후보 수 (D13 §7.1): 1~3위 5종 / 4~8위 4종 / 9위↓ 2종 (G-M1 바닥 보장)
	for spec in [[1, 5], [3, 5], [4, 4], [8, 4], [9, 2], [16, 2]]:
		var drawn := state.draw_overhaul_candidates(int(Array(spec)[0]), rng)
		_ok("D13 §7.1 순위 %d = 후보 %d종" % [Array(spec)[0], Array(spec)[1]],
			drawn.size() == int(Array(spec)[1]), str(drawn))
	# 중복 없음·전건 실재
	var candidates := state.draw_overhaul_candidates(1, rng)
	var seen: Dictionary = {}
	for drawn_id in candidates:
		seen[drawn_id] = true
		_ok("후보 실재: %s" % drawn_id, not state.data.overhaul(String(drawn_id)).is_empty())
	_ok("후보 중복 없음", seen.size() == candidates.size(), str(candidates))
	# 기장착 제외 (풀 = 전 인스턴스 − 기장착 — D06 §5.3 재등장 규칙의 여집합)
	state.overhauls = ["overhaul_ov_p1", "overhaul_ov_p2"]
	var filtered := state.draw_overhaul_candidates(1, rng)
	_ok("기장착 제외", not filtered.has("overhaul_ov_p1") and not filtered.has("overhaul_ov_p2"),
		str(filtered))
	# 풀 고갈: 잔여 2종이면 후보 5 요청에도 2종, 전량 장착 = 후보 0 (G-M1은 '슬롯' 보장이지 후보 생성이 아니다)
	state.overhauls = state.data.overhauls.keys().slice(0, 10)
	_ok("풀 고갈 시 잔여분만", state.draw_overhaul_candidates(1, rng).size() == 2,
		str(state.overhaul_candidates))
	state.overhauls = state.data.overhauls.keys()
	_ok("전량 장착 = 후보 0", state.draw_overhaul_candidates(1, rng).is_empty())
	# 스트림 분리 (D12 §6.1) — 추첨은 reserve 전속: reel 무소비·reserve 소비
	var probe := _new_state()
	var rng2 := RngService.new()
	rng2.setup(778)
	var before: Dictionary = rng2.serialize()
	probe.draw_overhaul_candidates(1, rng2)
	var after: Dictionary = rng2.serialize()
	_ok("추첨은 reel 스트림 무소비", str(before["streams"]["reel"]) == str(after["streams"]["reel"]))
	_ok("추첨은 reserve 스트림 소비", str(before["streams"]["reserve"]) != str(after["streams"]["reserve"]))
	# 후보 가드·슬롯 한도 = 결산 단위 (누적 장착으로 슬롯이 영구 소진되면 안 된다 — 회귀 가드)
	var guarded := _new_state()
	var rng3 := RngService.new()
	rng3.setup(779)
	var top_candidates := guarded.draw_overhaul_candidates(1, rng3)   # 슬롯 2 · 후보 5
	var outside := ""
	for overhaul_id in guarded.data.overhauls:
		if not top_candidates.has(String(overhaul_id)):
			outside = String(overhaul_id)
			break
	_ok("후보 밖 장착 거부", not guarded.install_overhaul(outside, 1), outside)
	_ok("후보 장착 1/2", guarded.install_overhaul(String(top_candidates[0]), 1))
	_ok("후보 장착 2/2", guarded.install_overhaul(String(top_candidates[1]), 1))
	_ok("슬롯 소진 거부", not guarded.install_overhaul(String(top_candidates[2]), 1))
	var next_candidates := guarded.draw_overhaul_candidates(5, rng3)   # 차기 결산: 슬롯 1 · 후보 4
	_ok("차기 결산 재장착 가능 (슬롯 축 = 결산 단위)",
		guarded.install_overhaul(String(next_candidates[0]), 5), str(next_candidates))
	_ok("차기 결산 슬롯 1 소진", not guarded.install_overhaul(String(next_candidates[1]), 5))
	_ok("누적 장착 3 성립", guarded.overhauls.size() == 3, str(guarded.overhauls))
	# 직렬화 왕복 — 후보·결산 장착 수 보존 (보존이 없으면 재로드가 재추첨 창구가 된다)
	var payload := guarded.serialize()
	var restored := _new_state()
	_ok("복원 성립", restored.restore(payload))
	_ok("후보 보존", str(restored.overhaul_candidates) == str(guarded.overhaul_candidates),
		str(restored.overhaul_candidates))
	_ok("결산 장착 수 보존",
		restored.overhaul_installs_this_season == guarded.overhaul_installs_this_season)
	# 구세이브(필드 부재) — 복원 성립 + 후보 가드 비활성 (관용 경로)
	payload.erase("overhaul_candidates")
	payload.erase("overhaul_installs_this_season")
	var legacy := _new_state()
	_ok("구세이브 복원 성립", legacy.restore(payload))
	_ok("구세이브 = 후보 빈 상태 (가드 비활성)", legacy.overhaul_candidates.is_empty(),
		str(legacy.overhaul_candidates))


# ── 마일스톤·업적 (D08 §8.2·§8.11 · D07 §6.2·§7.1 — T4 결선) ──
func _milestones_and_achievements() -> void:
	var state := _new_state()
	if state == null:
		return
	var data := state.data
	# D08 §8.11 전수 대장 — 카테고리 구성 대조 (열거 실측)
	var by_category: Dictionary = {}
	var hidden_count := 0
	for achievement_id in data.achievements:
		var row: Dictionary = data.achievements[achievement_id]
		var key := String(row["category"])
		by_category[key] = int(by_category.get(key, 0)) + 1
		if CsvTable.to_int(String(row["hidden"])) == 1:
			hidden_count += 1
	# **카테고리는 D07 §7.1 의 5종이 전부다** — 발견형은 카테고리가 아니라 조건 유형이며
	# `condition_type` 열이 그 축을 담는다 (총괄 판정 IMPL-121 ② · 데이터 교정 IMPL-128 §5).
	var expected_categories := {"career": 10, "rival": 18, "driving": 6, "garage": 4, "archive": 1}
	for category in expected_categories:
		_ok("D08 §8.11 %s 카테고리 %d종" % [category, expected_categories[category]],
			int(by_category.get(category, 0)) == int(expected_categories[category]),
			"actual=%s" % str(by_category.get(category)))
	_ok("카테고리 축 = 5종 전속 (6번째 값 유입 차단)", by_category.size() == 5, str(by_category.keys()))
	# 조건 유형 3형식 (D07 §7.1) — 발견형 4종은 여기에 산다
	var by_condition: Dictionary = {}
	for achievement_id2 in data.achievements:
		var condition := String(data.achievements[achievement_id2]["condition_type"])
		by_condition[condition] = int(by_condition.get(condition, 0)) + 1
	_ok("조건 3형식 = reach 31 · cumulative 4 · discovery 4",
		int(by_condition.get("reach", 0)) == 31 and int(by_condition.get("cumulative", 0)) == 4
		and int(by_condition.get("discovery", 0)) == 4, str(by_condition))
	# 총계: 정본 헤딩은 "총 35종"이나 열거 실측은 39종 — 총괄 판정 ①이 **열거 준거로 확정**했다
	# (헤딩의 35는 발견형 4종 미계상 — IMPL-121 ①).
	_ok("업적 열거 실측 39종", data.achievements.size() == 39, "actual=%d" % data.achievements.size())
	# 비노출(H) = 관계 최종 상태 5종 + 발견형 4종 (D07 §7.1 비노출 규칙 · D08 §8.11)
	_ok("히든 업적 9종 (관계 5 + 발견형 4)", hidden_count == 9, "actual=%d" % hidden_count)
	for achievement_id in data.achievements:
		var row2: Dictionary = data.achievements[achievement_id]
		if String(row2["source"]) == "relation" or String(row2["condition_type"]) == "discovery":
			_ok("D07 §7.1 비노출: %s" % achievement_id,
				CsvTable.to_int(String(row2["hidden"])) == 1, String(row2["hidden"]))
	# 무보상 명예형 (D07 §7.1) — 업적 테이블에 보상 열 자체가 없다 (Source 신설 0)
	var first_row: Dictionary = data.achievements[data.achievements.keys()[0]]
	for forbidden in ["reward", "credits", "dp", "reward_type"]:
		_ok("D07 §7.1 무보상: 보상 열 부재 (%s)" % forbidden, not first_row.has(forbidden))
	# 마일스톤 판정 (D08 §8.2) — GP 결과가 임계 '이내'일 때만 달성
	var pointless := _new_state()
	pointless.record_gp_result({"player_rank": 12, "player_retired": false, "circuit_id": "circuit_mn1"})
	_ok("첫 완주 달성 (P12 완주)", pointless.milestones.has("milestone_first_finish"))
	_ok("첫 포인트 미달성 (P12 > P8)", not pointless.milestones.has("milestone_first_point"))
	_ok("첫 포디움 미달성 (P12 > P3)", not pointless.milestones.has("milestone_first_podium"))
	var podium := _new_state()
	podium.record_gp_result({"player_rank": 3, "player_retired": false, "circuit_id": "circuit_mn1"})
	_ok("D08 §8.2 첫 포디움 = P3 이내", podium.milestones.has("milestone_first_podium"))
	_ok("첫 포인트 동반 달성 (P3 ≤ P8)", podium.milestones.has("milestone_first_point"))
	_ok("첫 우승 미달성 (P3 > P1)", not podium.milestones.has("milestone_first_gp_win"))
	# 스킬 티어 개방이 마일스톤으로 살아난다 (선재 구멍 — 기록 경로 부재로 티어 2·3 영구 잠김이었다)
	_ok("D13 §4.1 스킬 티어 2 개방 (첫 포디움)", podium.skill_tier_open(2))
	_ok("스킬 티어 3 미개방 (첫 우승 전)", not podium.skill_tier_open(3))
	# S5 마일스톤 보상 (D06 §2.1 축적형 주 수입 · D13 별첨A §3.3) — 달성 즉시 지급.
	# 선재 공백: 마일스톤 기록이 없어 S5 자체가 죽어 있었고, E1(시즌 1 축적형 기대 총량 820)의
	# 620 DP 분이 통째로 누락돼 TL-5 실측이 모델의 54%로 나왔다.
	var expected_dp := {
		"milestone_first_finish": 10, "milestone_first_point": 20, "milestone_first_podium": 60,
		"milestone_first_gp_win": 80, "milestone_first_tour_win": 80, "milestone_lorentz_beat": 100,
	}
	for milestone_id in expected_dp:
		_ok("D13 §3.3 %s = %d DP" % [milestone_id, expected_dp[milestone_id]],
			CsvTable.to_int(String(data.milestones[milestone_id]["reward_dp"])) == int(expected_dp[milestone_id]),
			String(data.milestones[milestone_id]["reward_dp"]))
	for rival_id in ["ai_maro", "ai_diaz", "ai_jude"]:
		var suffix2 := String(rival_id).trim_prefix("ai_")
		_ok("D13 §3.3 네임드 첫 선착 = 15 DP (%s)" % rival_id,
			CsvTable.to_int(String(data.milestones["milestone_beat_%s" % suffix2]["reward_dp"])) == 15)
	_ok("D13 §3.3 시즌 챔피언 = 0 DP (보상은 S6·오버홀)",
		CsvTable.to_int(String(data.milestones["milestone_season_champion"]["reward_dp"])) == 0)
	var rewarded := _new_state()
	_ok("지급 전 DP 0", rewarded.drive_data == 0)
	rewarded.record_gp_result({"player_rank": 3, "player_retired": false, "circuit_id": "circuit_mn1"})
	# 첫 완주 10 + 첫 포인트 20 + 첫 포디움 60 = 90 (동시 달성분 전량 지급)
	_ok("S5 동시 달성 3종 지급 = 90 DP", rewarded.drive_data == 90, "actual=%d" % rewarded.drive_data)
	_ok("S5 누적 획득에도 반영", rewarded.drive_data_earned_total == 90,
		"actual=%d" % rewarded.drive_data_earned_total)
	rewarded.record_gp_result({"player_rank": 3, "player_retired": false, "circuit_id": "circuit_mn1"})
	_ok("S5 재지급 없음 (1회성)", rewarded.drive_data == 90, "actual=%d" % rewarded.drive_data)
	# S6 시즌 결산 보상 — settlement_rewards.csv season 행이 실제로 소비된다
	var season_reward := rewarded.settlement_reward("season", 4)
	_ok("D13 §3.2 S6 4~5위 = 1800 Cr / 60 DP",
		int(season_reward.get("credits", 0)) == 1800 and int(season_reward.get("dp", 0)) == 60,
		str(season_reward))
	# 리타이어는 완주가 아니다 — 순위가 좋아도 마일스톤 0
	var retired := _new_state()
	retired.record_gp_result({"player_rank": 1, "player_retired": true, "circuit_id": "circuit_mn1"})
	_ok("리타이어 = 첫 완주 미달성", not retired.milestones.has("milestone_first_finish"))
	_ok("리타이어 = 첫 우승 미달성", not retired.milestones.has("milestone_first_gp_win"))
	# 네임드 첫 선착 8종 + 라이벌 파일 개방 (D07 §6.1 축)
	var beater := _new_state()
	var all_named: Array = []
	for row3 in beater.data.rivals:
		all_named.append(String(row3["id"]))
	_ok("네임드 8인", all_named.size() == 8, str(all_named))
	beater.record_gp_result({"player_rank": 1, "player_retired": false, "circuit_id": "circuit_mn1",
		"beaten_rivals": all_named})
	for rival_id in all_named:
		var suffix := String(rival_id).trim_prefix("ai_")
		_ok("네임드 첫 선착: %s" % rival_id, beater.milestones.has("milestone_beat_%s" % suffix))
	_ok("로렌츠 첫 격파 마일스톤", beater.milestones.has("milestone_lorentz_beat"))
	_ok("네임드 선착 누계 8", beater.career_stat("named_beats") == 8,
		"actual=%d" % beater.career_stat("named_beats"))
	var beat_achievements := beater.evaluate_achievements()
	_ok("라이벌 파일 완성 업적 (8인 선착)", beat_achievements.has("achievement_rival_files"),
		str(beat_achievements))
	_ok("첫 우승 업적 동반", beat_achievements.has("achievement_first_gp_win"))
	# 통산 지표 (D07 §6.2 확정 6종) — 누계가 GP마다 쌓인다
	var stats := _new_state()
	for i in range(3):
		stats.record_gp_result({"player_rank": 1, "player_retired": false, "duels": 2, "duel_wins": 2,
			"trouble_turns": 0, "hold_uses": 0, "final_lap_entry_rank": 4,
			"circuit_id": "circuit_mn%d" % (i + 1)})
	_ok("통산 완주 3", stats.career_stat("finishes") == 3, "actual=%d" % stats.career_stat("finishes"))
	_ok("통산 우승 3", stats.career_stat("wins") == 3, "actual=%d" % stats.career_stat("wins"))
	_ok("통산 포디움 3", stats.career_stat("podiums") == 3, "actual=%d" % stats.career_stat("podiums"))
	_ok("통산 듀얼 승 6", stats.career_stat("duel_wins") == 6, "actual=%d" % stats.career_stat("duel_wins"))
	_ok("서킷 제패 누계 3 (서킷별 유일)", stats.career_stat("circuits_won") == 3,
		"actual=%d" % stats.career_stat("circuits_won"))
	_ok("무트러블 GP 3", stats.career_stat("clean_gps") == 3, "actual=%d" % stats.career_stat("clean_gps"))
	_ok("무개입 우승 3", stats.career_stat("no_intervention_wins") == 3,
		"actual=%d" % stats.career_stat("no_intervention_wins"))
	_ok("최종 랩 역전 우승 3 (진입 P4 → P1)", stats.career_stat("final_lap_comebacks") == 3,
		"actual=%d" % stats.career_stat("final_lap_comebacks"))
	# 최고 챔피언십 순위 — 0 오염 회귀 검사 (총괄 판정 IMPL-141 ① 부대 · IMPL-142).
	# `best == 0 or position < best`는 0이 들어오면 0을 최고 기록으로 굳혀 이후 갱신을 막는다.
	# 원천 절상(close_season)이 0을 차단하므로 여기서는 정상 입력의 갱신 방향만 못박는다.
	var ranker := _new_state()
	ranker.record_season_result({"player_position": 16, "champion": "ai_lorentz", "tour_wins": 0})
	_ok("최고 순위 초기 기록 = 최하위 절상값", ranker.career_stat("best_championship_rank") == 16,
		"actual=%d" % ranker.career_stat("best_championship_rank"))
	ranker.record_season_result({"player_position": 4, "champion": "ai_lorentz", "tour_wins": 0})
	_ok("더 좋은 순위로 갱신", ranker.career_stat("best_championship_rank") == 4,
		"actual=%d" % ranker.career_stat("best_championship_rank"))
	ranker.record_season_result({"player_position": 9, "champion": "ai_lorentz", "tour_wins": 0})
	_ok("나쁜 순위는 최고 기록을 덮지 않는다", ranker.career_stat("best_championship_rank") == 4,
		"actual=%d" % ranker.career_stat("best_championship_rank"))
	# 같은 서킷 재우승은 제패 수를 늘리지 않는다 (전 서킷 제패 20의 성립 조건)
	stats.record_gp_result({"player_rank": 1, "player_retired": false, "circuit_id": "circuit_mn1"})
	_ok("동일 서킷 재우승 = 제패 누계 불변", stats.career_stat("circuits_won") == 3,
		"actual=%d" % stats.career_stat("circuits_won"))
	# 누적형 업적 임계 (듀얼 통산 10승)
	var duelist := _new_state()
	for i in range(4):
		duelist.record_gp_result({"player_rank": 5, "player_retired": false, "duels": 3, "duel_wins": 2,
			"trouble_turns": 1, "circuit_id": "circuit_mn1"})
	duelist.evaluate_achievements()
	_ok("듀얼 8승 = 10승 업적 미달성", not duelist.achievements.has("achievement_duel_10_wins"),
		"duel_wins=%d" % duelist.career_stat("duel_wins"))
	duelist.record_gp_result({"player_rank": 5, "player_retired": false, "duels": 3, "duel_wins": 2,
		"trouble_turns": 1, "circuit_id": "circuit_mn1"})
	_ok("듀얼 10승 = 업적 달성", duelist.evaluate_achievements().has("achievement_duel_10_wins"),
		"duel_wins=%d" % duelist.career_stat("duel_wins"))
	_ok("업적은 1회만 발화", not duelist.evaluate_achievements().has("achievement_duel_10_wins"))
	# 발견형 — 표현 층 통지로만 달성 (L3 조우)
	var finder := _new_state()
	finder.evaluate_achievements()
	_ok("발견형 미통지 = 미달성", not finder.achievements.has("achievement_l3_throne"))
	finder.record_discovery("cg_01_throne")
	_ok("발견형 통지 = 달성", finder.evaluate_achievements().has("achievement_l3_throne"))
	# 판정 소스 미결선 계수 — 관계 축 2종(재회·계승 셀린)이 데이터에 없다 (T7 서사 유입 의존).
	# 조용한 영구 미달성이 아니라 명시적 계수로 드러낸다.
	var pending := state.pending_achievements()
	_ok("판정 소스 미결선 = 관계 2종", pending.size() == 2, str(pending))
	_ok("미결선 = 재회·계승(셀린) 축",
		pending.has("achievement_relation_reunion") and pending.has("achievement_relation_succession_maro"),
		str(pending))
	# ── SYS-04 조건 진척 조회 (표시 전용) ──
	# 표시가 판정과 다른 계산을 쓰면 화면이 거짓을 그린다 — 같은 소스를 보는지 전수로 못박는다
	# (IMPL-100 `field_repair_preview` 패리티 검사와 같은 구조).
	var viewer := _new_state()
	for i2 in range(4):
		viewer.record_gp_result({"player_rank": 5, "player_retired": false, "duels": 3, "duel_wins": 2,
			"trouble_turns": 1, "circuit_id": "circuit_mn1"})
	viewer.evaluate_achievements()
	var mid: Dictionary = viewer.achievement_progress("achievement_duel_10_wins")
	_ok("진척 조회 = 판정 소스 실값 (8/10 미달성)",
		int(mid["current"]) == 8 and int(mid["threshold"]) == 10 and not bool(mid["met"]), str(mid))
	_ok("발견형 미통지 진척 0",
		int(viewer.achievement_progress("achievement_l3_throne")["current"]) == 0)
	viewer.record_discovery("cg_01_throne")
	viewer.evaluate_achievements()
	var found: Dictionary = viewer.achievement_progress("achievement_l3_throne")
	_ok("발견형 통지 진척 1 · 달성", int(found["current"]) == 1 and bool(found["met"]), str(found))
	_ok("미결선 축 = pending 표식 (SYS-04 는 히든 슬롯으로 가린다)",
		bool(viewer.achievement_progress("achievement_relation_reunion")["pending"]))
	_ok("미지 업적 id = 빈 진척 가드",
		int(viewer.achievement_progress("achievement_nope")["threshold"]) == 0)
	beater.evaluate_achievements()
	var parity_ok := true
	var parity_detail := ""
	for progress_id in data.achievements:
		var view: Dictionary = beater.achievement_progress(String(progress_id))
		if bool(view["met"]) != beater.achievements.has(progress_id):
			parity_ok = false
			parity_detail = String(progress_id)
		if bool(view["pending"]):
			continue   # 판정 소스 미결선 — 임계 비교 자체가 성립하지 않는다
		if (int(view["current"]) >= int(view["threshold"])) != bool(view["met"]):
			parity_ok = false
			parity_detail = String(progress_id)
	_ok("진척 조회-판정 패리티 39종 전수", parity_ok, parity_detail)
	# ── 달성 시즌 래치 (총괄 판정 IMPL-128 A-1) ──
	# 시각 축 = 인게임 시즌. **최초 성립 시점 1회만** 적는다 — 재판정마다 갱신되면 래치가 아니고,
	# 소급 달성(재로드 후 재판정)에서 시즌이 뒤로 밀리는 거짓 표기가 된다.
	var stamper := _new_state()
	for i3 in range(4):
		stamper.record_gp_result({"player_rank": 5, "player_retired": false, "duels": 3, "duel_wins": 2,
			"trouble_turns": 1, "circuit_id": "circuit_mn1"})
	stamper.evaluate_achievements(1)
	var stamped: Dictionary = stamper.achievement_progress("achievement_first_duel_win")
	_ok("달성 시즌 = 성립 시점 시즌", int(stamped["season"]) == 1, str(stamped))
	# 시즌 3에서 재판정해도 이미 달성한 항목의 시즌은 움직이지 않는다
	stamper.evaluate_achievements(3)
	_ok("재판정해도 시즌 불변 (래치)",
		int(stamper.achievement_progress("achievement_first_duel_win")["season"]) == 1)
	# 같은 재판정에서 **새로** 달성한 항목은 그 시점 시즌을 받는다
	for i4 in range(3):
		stamper.record_gp_result({"player_rank": 5, "player_retired": false, "duels": 3, "duel_wins": 2,
			"trouble_turns": 1, "circuit_id": "circuit_mn1"})
	stamper.evaluate_achievements(3)
	_ok("신규 달성분은 당시 시즌",
		int(stamper.achievement_progress("achievement_duel_10_wins")["season"]) == 3,
		str(stamper.achievement_seasons))
	# 시즌 문맥 없는 호출(0)은 아예 적지 않는다 — '시즌 0' 표기 방지
	var unstamped := _new_state()
	unstamped.record_gp_result({"player_rank": 5, "player_retired": false, "duels": 3, "duel_wins": 2,
		"trouble_turns": 1, "circuit_id": "circuit_mn1"})
	unstamped.evaluate_achievements()
	_ok("시즌 문맥 없으면 미기록 (0 표기 방지)",
		unstamped.achievements.has("achievement_first_duel_win")
		and int(unstamped.achievement_progress("achievement_first_duel_win")["season"]) == 0)
	# 왕복 보존 + 구세이브(필드 부재) 관용 — 소급분은 시즌을 지어내지 않는다
	var stamp_payload := stamper.serialize()
	var stamp_reloaded := _new_state()
	stamp_reloaded.restore(stamp_payload)
	_ok("달성 시즌 왕복 보존",
		int(stamp_reloaded.achievement_progress("achievement_first_duel_win")["season"]) == 1)
	stamp_payload.erase("achievement_seasons")
	var legacy_stamp := _new_state()
	legacy_stamp.restore(stamp_payload)
	_ok("구세이브 = 시즌 부재 (표시 층이 '—')",
		legacy_stamp.achievements.has("achievement_first_duel_win")
		and int(legacy_stamp.achievement_progress("achievement_first_duel_win")["season"]) == 0)
	# 직렬화 왕복 — 통산·업적·제패·발견 4축 보존
	var payload := beater.serialize()
	var restored := _new_state()
	_ok("복원 성립", restored.restore(payload))
	_ok("마일스톤 보존", restored.milestones.size() == beater.milestones.size(), str(restored.milestones))
	_ok("통산 지표 보존", restored.career_stat("named_beats") == 8)
	_ok("업적 보존", restored.achievements.size() == beater.achievements.size())
	_ok("서킷 제패 보존", restored.circuits_won.size() == beater.circuits_won.size())
	# 구세이브(필드 부재) — 복원 성립 + 빈 집계 (그 세계는 집계가 없었다)
	for key in ["career_stats", "achievements", "circuits_won", "discoveries"]:
		payload.erase(key)
	var legacy := _new_state()
	_ok("구세이브 복원 성립", legacy.restore(payload))
	_ok("구세이브 = 빈 집계", legacy.career_stats.is_empty() and legacy.achievements.is_empty())


# ── TC-O3 스폰서 계약 (D07 §5.4 · D13 별첨A §5.3) ──
func _tc_o3_sponsors() -> void:
	var state := _new_state()
	if state == null:
		return
	_ok("기본 계약 슬롯 1", state.sponsor_slots() == 1, "slots=%d" % state.sponsor_slots())
	_ok("기본 후보 3종", state.sponsor_candidate_count() == 3)
	_ok("SP1 계약", state.sign_sponsor("sponsor_sp1"))
	_ok("슬롯 초과 계약 거부", not state.sign_sponsor("sponsor_sp2"))
	# 조건 미충족 → 정기 수입만
	var regular := state.settle_sponsors({})
	_ok("조건 미충족 = 정기 수입만 (500 Cr)", regular == 500, "payout=%d" % regular)
	# 조건 충족 → 보너스 가산
	var with_bonus := state.settle_sponsors({"tour_all_finish": true})
	_ok("조건 충족 = 정기 + 보너스 (700 Cr)", with_bonus == 700, "payout=%d" % with_bonus)
	# 나디아 합류 → 후보 4종 / G4 해금 → 슬롯 2
	state.gain_drive_data(1000)
	state.recruit_crew("crew_nadia")
	_ok("나디아 합류 → 후보 4종", state.sponsor_candidate_count() == 4)
	state.unlock_facility("facility_g4")
	_ok("G4 해금 → 슬롯 2", state.sponsor_slots() == 2, "slots=%d" % state.sponsor_slots())
	_ok("슬롯 2에서 2번째 계약 성립", state.sign_sponsor("sponsor_sp2"))
	# 보상은 Source 범위 안 — 이벤트처럼 신설 Source를 만들지 않는다 (D06 §2.1)
	_ok("계약 수입은 크레딧 축 전속", state.credits > 0)


# ── TC-O5 아카이브 (D07 §6.3 · D09 §4.5 — 무상·상시·게이트 표시 부재) ──
func _tc_o5_archive() -> void:
	var state := _new_state()
	if state == null:
		return
	_ok("아카이브 무상·상시 (시설 해금 전)", state.archive_available())
	_ok("아카이브 접근에 재화 소모 없음", state.credits == 0 and state.drive_data == 0)
	# G2(크루 라운지)는 '연출 강화형 회상'이며 기본 열람의 게이트가 아니다 (R-D07-VN)
	state.gain_drive_data(55)
	state.unlock_facility("facility_g2")
	_ok("G2 해금 후에도 아카이브 상시", state.archive_available())
	var fresh := _new_state()
	_ok("G2 미해금 상태에서도 아카이브 상시", fresh.archive_available())


# ── TC-O6 환전 가드 G1~G4 (D06 §4.3) — 가드 4건 전건 차단 ──
func _tc_o6_exchange_guards() -> void:
	var state := _new_state()
	if state == null:
		return
	# G1 역방향 환전 절대 금지 — **경로 부재**로 검사한다.
	# 조건문으로 막았다면 그 조건문을 지우면 열린다. 함수가 없으면 지울 것이 없다.
	#
	# 금지 이름 열거(블랙리스트)는 **닫힘 성질이 아니다** — 이름만 바꾸면 우회된다.
	# 공개 메서드 집합 전체를 커밋된 기대 집합과 대조해, 새 메서드가 기대 집합을
	# 함께 고치지 않는 한 통과하지 못하게 한다 (검사 수 하한과 같은 "의도적 변경만 통과" 구조).
	var expected_methods := [
		"setup", "gain_credits", "gain_drive_data", "exchange_charge",
		# `field_repair_cost_next` 는 D07 §3.3·D09 §4.3이 **사전 표시를 필수**로 요구하는
		# 다음 회차 비용의 조회 경로다 (표시 전용 · 체증 카운터 무변경 — IMPL-079).
		# `field_repair_preview` 는 §A-9 E02 회복 고스트 게이지의 도달값 조회 (표시 전용 —
		# field_repair와 절단 계산 공유, 패리티 검사로 담보).
		"field_repair_cost", "field_repair_cost_next", "field_repair_preview", "field_repair", "begin_tour",
		# `full_repair_cost` 는 D09 §4.3 비용 표시의 조회 경로 (IMPL-079와 같은 구조 — 표시 전용).
		# `event_chassis_recover` 는 D06 §3.4 이벤트 회복의 유일 진입로 (회당 상한 가드 내장).
		"full_repair", "full_repair_cost", "free_restore_line", "event_chassis_recover",
		"tuning_step", "tuning_cost", "buy_tuning", "tuning_refund_ratio", "redistribute_tuning",
		"overhaul_slots", "install_overhaul", "draw_overhaul_candidates", "parts_stat_bonus",
		"career_stat", "record_gp_result", "record_tour_result", "record_season_result",
		# `achievement_progress` 는 SYS-04 업적 화면의 조건 진척 조회 경로다
		# (표시 전용 · 판정과 계산 공유 — IMPL-079·100과 같은 구조).
		"record_discovery", "evaluate_achievements", "pending_achievements", "achievement_progress",
		"skill_tier_open", "unlock_cost", "unlock_skill", "expand_deck", "set_deck",
		"recruit_crew",
		"sponsor_slots", "sponsor_candidate_count", "sign_sponsor", "settle_sponsors",
		"add_relation", "pending_relation_transitions", "commit_relation_transitions",
		"relation_stage",
		"unlock_facility", "archive_available", "buy_consumable",
		"gp_prize", "finish_bonus", "settlement_reward", "vane_stage",
		"serialize", "restore",
	]
	var baseline := RefCounted.new()
	var actual_methods: Array = []
	for method in state.get_method_list():
		var method_name := String(method.get("name", ""))
		if method_name.begins_with("_") or method_name.begins_with("@"):
			continue
		if baseline.has_method(method_name):
			continue   # 상속분 제외 — 우리 계약이 아니다
		if not actual_methods.has(method_name):
			actual_methods.append(method_name)
	actual_methods.sort()
	var expected_sorted := expected_methods.duplicate()
	expected_sorted.sort()
	_ok("G1 공개 메서드 집합 = 커밋된 기대 집합", actual_methods == expected_sorted,
		"신설=%s 소멸=%s" % [str(_missing_from(actual_methods, expected_sorted)),
			str(_missing_from(expected_sorted, actual_methods))])
	# 블랙리스트도 유지한다 — 화이트리스트가 놓칠 수 없는 이름을 이중으로 못박는다
	for forbidden in ["buy_charge", "buy_chassis", "purchase_charge", "credits_to_charge",
		"exchange_credits_for_charge", "restore_charge", "top_up_pulse"]:
		_ok("G1 역방향 환전 경로 부재: %s" % forbidden, not state.has_method(forbidden))
	# G2 환전 상한 = 5차지
	var cap := state.data.param_int("param_charge_exchange_cap")
	var rate := state.data.param_int("param_charge_exchange_cr")
	_ok("G2 상한 이내 환전", state.exchange_charge(3, true) == 3 * rate,
		"payout=%d" % state.exchange_charge(0, true))
	var over := _new_state()
	_ok("G2 상한 초과분 절단", over.exchange_charge(10, true) == cap * rate,
		"payout=%d expected=%d" % [over.exchange_charge(0, true), cap * rate])
	# G3 환전율은 데이터 값 전속 (코드가 임의로 올리지 않는다)
	var probe := _new_state()
	_ok("G3 환전율 = 데이터 값", probe.exchange_charge(1, true) == rate,
		"payout=%d rate=%d" % [probe.exchange_charge(0, true), rate])
	# G4 완주 조건 — 탈락 시 미지급
	var dropout := _new_state()
	_ok("G4 탈락 시 환전 미지급", dropout.exchange_charge(5, false) == 0)
	_ok("G4 탈락 시 크레딧 무변동", dropout.credits == 0, "credits=%d" % dropout.credits)


# ── TC-O7 스킬 티어 개방·크루 패시브 (D07 §4.3 · D13 별첨A §4.1~4.3·§5.1) ──
func _tc_o7_skill_tiers_and_crew() -> void:
	var state := _new_state()
	if state == null:
		return
	_ok("티어 1은 시작 개방", state.skill_tier_open(1))
	_ok("티어 2는 첫 포디움 전 미개방", not state.skill_tier_open(2))
	_ok("티어 3은 첫 GP 우승 전 미개방", not state.skill_tier_open(3))
	state.gain_drive_data(1000)
	_ok("티어 1 스킬 해금", state.unlock_skill("skill_sh1"))
	_ok("미개방 티어 2 스킬 해금 거부", not state.unlock_skill("skill_sh2"))
	# 마일스톤 연동 = 무비용 개방 (D07 §4.3)
	var before_dp := state.drive_data
	state.milestones["milestone_first_podium"] = true
	_ok("첫 포디움 → 티어 2 개방", state.skill_tier_open(2))
	_ok("티어 개방 자체는 무비용", state.drive_data == before_dp)
	_ok("티어 2 스킬 해금", state.unlock_skill("skill_sh2"))
	state.milestones["milestone_first_gp_win"] = true
	_ok("첫 우승 → 티어 3 개방", state.skill_tier_open(3))
	_ok("티어 3 스킬 해금", state.unlock_skill("skill_sh3"))
	# 티어 내 순서 강제 없음 (선행 스킬 의존 사슬 부재 — D07 §4.3)
	var free_order := _new_state()
	free_order.gain_drive_data(1000)
	free_order.milestones["milestone_first_podium"] = true
	_ok("티어 내 임의 순서 해금 (SC2 먼저)", free_order.unlock_skill("skill_sc2"))
	_ok("티어 내 임의 순서 해금 (SI3 나중)", free_order.unlock_skill("skill_si3"))
	# 사샤 패시브 −10% (해금·슬롯 확장)
	var sasha := _new_state()
	sasha.gain_drive_data(1000)
	var base_cost := CsvTable.to_int(String(sasha.data.skill("skill_sh1")["unlock_dp"]))
	_ok("사샤 미합류 시 정가", sasha.unlock_cost(base_cost) == base_cost)
	sasha.recruit_crew("crew_sasha")
	_ok("사샤 합류 시 −10%", sasha.unlock_cost(base_cost) == int(round(float(base_cost) * 0.9)),
		"actual=%d" % sasha.unlock_cost(base_cost))
	# 덱 슬롯 2 → 5
	var deck_state := _new_state()
	_ok("시작 덱 슬롯 2", deck_state.deck_slots == 2, "slots=%d" % deck_state.deck_slots)
	deck_state.gain_drive_data(70 + 110 + 160)
	_ok("덱 확장 1단", deck_state.expand_deck())
	_ok("덱 확장 2단", deck_state.expand_deck())
	_ok("덱 확장 3단", deck_state.expand_deck())
	_ok("덱 슬롯 상한 5", deck_state.deck_slots == 5, "slots=%d" % deck_state.deck_slots)
	_ok("상한 초과 확장 거부", not deck_state.expand_deck())
	# 덱은 해금된 스킬만 · 슬롯 수 이내
	deck_state.gain_drive_data(1000)
	deck_state.unlock_skill("skill_sh1")
	_ok("미해금 스킬 편성 거부", not deck_state.set_deck(["skill_sh2"]))
	_ok("해금 스킬 편성 성립", deck_state.set_deck(["skill_sh1"]))
	var overflow: Array = []
	for skill_id in deck_state.data.skills:
		overflow.append(skill_id)
	_ok("슬롯 초과 편성 거부", not deck_state.set_deck(overflow))


# ── TC-O8 관계 카운터 (D07 §5.5 · D12 §5.2 형식 B · D13 별첨A §5.2) ──
func _tc_o8_relation_counters() -> void:
	var state := _new_state()
	if state == null:
		return
	# 임계 (D13 §5.2): 동기 4/9/15 · 계승 3/8/14 · 왕좌 2/6/12
	var expected := {
		"relation_kinship": [4, 9, 15],
		"relation_succession": [3, 8, 14],
		"relation_throne": [2, 6, 12],
	}
	for relation_id in expected:
		var row: Dictionary = state.data.relation_axes[relation_id]
		for index in [1, 2, 3]:
			_ok("D13 §5.2 %s 임계 %d = %d" % [relation_id, index, expected[relation_id][index - 1]],
				CsvTable.to_int(String(row["threshold%d" % index])) == int(expected[relation_id][index - 1]),
				String(row["threshold%d" % index]))
	# 카운터 감소 없음 — 감산 API가 존재하지 않는 것이 구조 보장이다 (D12 §5.2)
	for forbidden in ["subtract_relation", "decrease_relation", "reset_relation", "set_relation"]:
		_ok("감산 API 부재: %s" % forbidden, not state.has_method(forbidden))
	state.add_relation("relation_throne", 1)
	_ok("카운터 증가", int(state.relation_counters["relation_throne"]) == 1)
	state.add_relation("relation_throne", -5)
	_ok("음수 인자는 무효 (감소 불가)", int(state.relation_counters["relation_throne"]) == 1,
		"counter=%s" % str(state.relation_counters["relation_throne"]))
	# 임계 도달은 상시 판정하되 공표는 대회 경계 스냅 (D07 §5.5)
	state.add_relation("relation_throne", 1)   # 카운터 2 = 1단계 임계
	_ok("도달 즉시 단계 공표 안 됨", state.relation_stage("relation_throne") == 0,
		"stage=%d" % state.relation_stage("relation_throne"))
	_ok("펜딩 큐에 등재", state.pending_relation_transitions().has("relation_throne"),
		str(state.pending_relation_transitions()))
	var committed := state.commit_relation_transitions()
	_ok("경계 스냅에서 공표", state.relation_stage("relation_throne") == 1,
		"stage=%d" % state.relation_stage("relation_throne"))
	_ok("공표 목록 반환", committed.has("relation_throne"), str(committed))
	_ok("공표 후 펜딩 비움", state.pending_relation_transitions().is_empty())
	# 3단계까지 전이
	state.add_relation("relation_throne", 10)  # 카운터 12 = 3단계
	state.commit_relation_transitions()
	_ok("3단계 전이", state.relation_stage("relation_throne") == 3,
		"stage=%d" % state.relation_stage("relation_throne"))
	# 미등재 축은 조용히 무시되지 않는다
	var strict := _new_state()
	strict.add_relation("relation_nope", 1)
	_ok("미등재 관계 축 = 오류", not strict.data.is_ok())
	# 사샤 영입 데드락 부재 (D07 §5.3) — 영입이 관계 단계에 막히지 않는다
	var sasha_state := _new_state()
	sasha_state.gain_drive_data(100)
	_ok("사샤 영입에 관계 단계 선행 조건 없음 (데드락 부재)",
		sasha_state.recruit_crew("crew_sasha"))


# ── 정비·소모품 (D06 §3.3·§3.5 · D13 별첨A §3.4·§3.6) ──
func _repair_and_consumables() -> void:
	var state := _new_state()
	if state == null:
		return
	# 섀시 이월분의 아웃게임 정본 (D05 §8 이월 결선 — IMPL-078 해소)
	var maximum := state.data.param("param_chassis_max")
	_ok("새 커리어 섀시 = 최대치 [가안]", state.chassis == maximum, "chassis=%f" % state.chassis)
	# 회차 체증: 200 → 300 → 450 (기준액 × 1.5^(n−1)) · 테오 −10% 반영
	var expected_first := int(round(200.0 * 0.9))
	_ok("1회차 정비비 = 200 × (테오 −10%)", state.field_repair_cost() == expected_first,
		"actual=%d expected=%d" % [state.field_repair_cost(), expected_first])
	state.gain_credits(10000)
	# 회복 여지 없음 = 무동작 — 지불·체증 카운터 무변경 (헛돈이 나가지 않는다)
	var credits_before := state.credits
	_ok("만충 시 필드 정비 무동작", state.field_repair(30) == 0
		and state.credits == credits_before and state.field_repair_cost() == expected_first)
	# 프리뷰 = 실행 패리티 (§A-9 E02 고스트 게이지의 정직성 — 절단 계산 공유 검증)
	_ok("프리뷰: 만충 시 도달값 = 현재", state.field_repair_preview(30) == maximum)
	# 회복 적용 + 회당 상한 30 CH 절단 (D06 §3.4 경제 가드)
	state.chassis = 10.0
	var previewed := state.field_repair_preview(100)
	_ok("프리뷰는 상태 무변경 (표시 전용)", state.chassis == 10.0
		and state.field_repair_cost() == expected_first)
	_ok("회당 상한 절단·적용 (10→40)", state.field_repair(100) == 30 and state.chassis == 40.0,
		"chassis=%f" % state.chassis)
	_ok("프리뷰 = 실행 도달값 (10→40)", previewed == state.chassis,
		"previewed=%f chassis=%f" % [previewed, state.chassis])
	var expected_second := int(round(200.0 * 1.5 * 0.9))
	_ok("2회차 정비비 = ×1.5", state.field_repair_cost() == expected_second,
		"actual=%d expected=%d" % [state.field_repair_cost(), expected_second])
	# 복원선 절단 — 초과 구간(70~100)의 유일 수단은 전면 정비 (D07 §3.3 명문)
	previewed = state.field_repair_preview(100)
	_ok("복원선 절단 (40→70)", state.field_repair(100) == 30 and state.chassis == 70.0,
		"chassis=%f" % state.chassis)
	_ok("프리뷰 = 실행 도달값 (40→70 복원선)", previewed == state.chassis,
		"previewed=%f chassis=%f" % [previewed, state.chassis])
	_ok("복원선 도달 후 필드 정비 무동작", state.field_repair(100) == 0 and state.chassis == 70.0)
	# 복원선이 상한보다 먼저 걸리는 지점의 패리티 — 40→70 지점은 두 절단이 동치(40+30=70)라
	# 프리뷰가 복원선을 무시해도 못 가른다. 여기(55→70)가 실제로 가르는 지점이다.
	state.chassis = 55.0
	previewed = state.field_repair_preview(100)
	_ok("프리뷰 = 실행 도달값 (55→70 복원선 우선)", state.field_repair(100) == 15
		and previewed == state.chassis, "previewed=%f chassis=%f" % [previewed, state.chassis])
	# 체증 카운터는 투어 개시에 리셋
	state.begin_tour()
	_ok("투어 개시 시 체증 리셋", state.field_repair_cost() == expected_first,
		"actual=%d" % state.field_repair_cost())
	# 투어 개시 무상 복원선 = 하한 (D06 §3.3 결정 #12 — 위면 유지·아래면 끌어올림)
	state.chassis = 10.0
	state.begin_tour()
	_ok("투어 개시 무상 복원선 (10→70)", state.chassis == 70.0, "chassis=%f" % state.chassis)
	state.chassis = 85.0
	state.begin_tour()
	_ok("복원선 위는 유지 (85)", state.chassis == 85.0, "chassis=%f" % state.chassis)
	# 전면 정비 = 20 Cr/CH · 상한 없음 · 완전 회복 (테오 −10%)
	var full := _new_state()
	full.gain_credits(10000)
	full.chassis = 50.0
	var expected_full_cost := int(round(50.0 * 20.0 * 0.9))
	_ok("전면 정비 비용 조회 (표시 전용)", full.full_repair_cost() == expected_full_cost,
		"actual=%d expected=%d" % [full.full_repair_cost(), expected_full_cost])
	var full_credits := full.credits
	var restored := full.full_repair()
	_ok("전면 정비 상한 없음·완전 회복 (50 CH)", restored == 50 and full.chassis == maximum,
		"restored=%d chassis=%f" % [restored, full.chassis])
	_ok("전면 정비 지불", full.credits == full_credits - expected_full_cost,
		"credits=%d" % full.credits)
	_ok("만충 시 전면 정비 무동작", full.full_repair() == 0
		and full.credits == full_credits - expected_full_cost)
	# 이벤트 회복 — 회당 상한 가드 (D06 §3.4 "필드 정비의 회당 상한을 초과할 수 없다")
	var ev := _new_state()
	ev.chassis = 20.0
	_ok("이벤트 회복 상한 가드 (50 요청→30 적용)",
		ev.event_chassis_recover(50) == 30 and ev.chassis == 50.0, "chassis=%f" % ev.chassis)
	ev.chassis = 95.0
	_ok("이벤트 회복 최대치 절단 (95→100)",
		ev.event_chassis_recover(10) == 5 and ev.chassis == maximum, "chassis=%f" % ev.chassis)
	# 직렬화 왕복 — 섀시 이월분 보존 (세이브를 건너면 이월이 사라지는 회귀 방지)
	var trip := _new_state()
	trip.chassis = 33.0
	var back := _new_state()
	_ok("직렬화 왕복 섀시 보존", back.restore(trip.serialize()) and back.chassis == 33.0,
		"chassis=%f" % back.chassis)
	# 이월 도입 전 세이브(chassis 키 부재) = 최대치 복원 (그 세계의 충실한 기본값)
	var legacy := trip.serialize()
	legacy.erase("chassis")
	var legacy_state := _new_state()
	_ok("구세이브 복원 = 최대치", legacy_state.restore(legacy) and legacy_state.chassis == maximum,
		"chassis=%f" % legacy_state.chassis)
	# 소모품 휴대 상한 2
	var shop := _new_state()
	shop.gain_credits(10000)
	_ok("소모품 1개", shop.buy_consumable("consumable_p1"))
	_ok("소모품 2개", shop.buy_consumable("consumable_p2"))
	_ok("휴대 상한 초과 거부", not shop.buy_consumable("consumable_p3"))
	# P1 프리미엄 검증 (D13 §3.6 R4): 소모품 단가/회복량이 필드 정비보다 비싸다
	var p1_rate := 250.0 / 15.0
	var field_rate := 200.0 / 30.0
	_ok("R4 소모품 프리미엄 성립 (P1 > 필드 정비 단가)", p1_rate > field_rate,
		"p1=%f field=%f" % [p1_rate, field_rate])
	# 베인 단계는 누적 획득 총량 기준 — 소비해도 내려가지 않는다 (D13 §5.4)
	var vane := _new_state()
	_ok("초기 베인 1단계", vane.vane_stage() == 1)
	vane.gain_drive_data(290)
	_ok("290 DP → 2단계", vane.vane_stage() == 2, "stage=%d" % vane.vane_stage())
	vane.unlock_skill("skill_sh1")   # 소비
	_ok("소비 후에도 2단계 유지 (누적 기준)", vane.vane_stage() == 2, "stage=%d" % vane.vane_stage())
	vane.gain_drive_data(530)
	_ok("820 DP → 3단계", vane.vane_stage() == 3, "stage=%d" % vane.vane_stage())


func _serialization() -> void:
	var state := _new_state()
	if state == null:
		return
	state.gain_credits(5000)
	state.gain_drive_data(500)
	state.buy_tuning("tuning_t1")
	state.unlock_skill("skill_sh1")
	state.add_relation("relation_kinship", 5)
	state.commit_relation_transitions()
	var payload := state.serialize()
	var restored := _new_state()
	_ok("복원 성립", restored.restore(payload))
	_ok("재화 복원", restored.credits == state.credits and restored.drive_data == state.drive_data)
	_ok("튜닝 단계 복원", restored.tuning_step("tuning_t1") == state.tuning_step("tuning_t1"))
	_ok("스킬 해금 복원", restored.unlocked_skills.has("skill_sh1"))
	_ok("관계 카운터·단계 복원",
		int(restored.relation_counters["relation_kinship"]) == 5
		and restored.relation_stage("relation_kinship") == state.relation_stage("relation_kinship"))
	_ok("누적 획득 총량 복원", restored.drive_data_earned_total == state.drive_data_earned_total)
	var broken := _new_state()
	_ok("결손 payload 거부", not broken.restore({"credits": 1}))


func _missing_from(source: Array, reference: Array) -> Array:
	var missing: Array = []
	for item in source:
		if not reference.has(item):
			missing.append(item)
	return missing
