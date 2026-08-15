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
	if _checked < 245:
		print("TC_O_TEST_FAIL checks=%d < 하한 245 (스위트 축소·로드 실패 의심)" % _checked)
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
		"overhaul_slots", "install_overhaul", "parts_stat_bonus",
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
