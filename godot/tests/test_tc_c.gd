# 코어 루프 검증 시나리오 TC-C (D14 §3) — 헤드리스 자동화분.
# 실행: godot --headless --path godot --script tests/test_tc_c.gd
#
# 판정 원칙: 각 항은 **D13 확정값을 직접 단언**한다. 값이 바뀌면 테스트가 깨져야 하며,
# 그것이 이 파일의 존재 이유다 (돌연변이 주입 반증 — impl_log IMPL-019).
# 값을 테스트에 복제하지 않는다: 기대값은 GameData 경유로 읽고, 검사 대상은
# "그 값이 실제로 그 자리에 적용됐는가"다. 단 D13 문면 자체와의 대조가 필요한
# 소수 항(듀얼 임계 산식 등)은 산식을 명시 재구성해 이중 기입 없이 대조한다.
extends SceneTree

var _failures := 0
var _checked := 0


func _init() -> void:
	_d13_anchor_values()
	_tc_c1_state_machine_closure()
	_tc_c2_turn_sequence()
	_tc_c3_settle_order_log()
	_tc_c4_interventions()
	_tc_c5_pulse_charge_ledger()
	_tc_c6_duel_thresholds()
	_tc_c7_gauge_coefficients()
	_tc_c9_chassis_retire()
	_tc_c11_seal()
	_tc_c12_scumming()
	_seal_across_many_spins()
	_neighbor_passive_runtime()
	_slot_progression_wired()
	_negative_guards()
	_result_and_ranking()
	_sector_attribute_weights()
	_resonance_runtime()
	_wall_rival_wired()
	_consumable_paths()
	_gp_summary_counters()
	_presentation_grade_caps()
	_momentum_interrupt_matrix()
	_check_global_postconditions()
	print("")
	# 검사 수 하한 — 클래스 로드 실패 등으로 스위트가 쪼그라들면 "통과"가 아니다.
	# 실행되지 않은 검사와 통과한 검사를 구분하는 유일한 수단이다.
	if _checked < 1990:
		print("TC_C_TEST_FAIL checks=%d < 하한 1990 (스위트 축소·로드 실패 의심)" % _checked)
		quit(1)
		return
	if _failures == 0:
		print("TC_C_TEST_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("TC_C_TEST_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


# ── 판정 보조 ──
func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if not condition:
		_failures += 1
		print("  [FAIL] %s %s" % [label, detail])


func _eq_float(label: String, actual: float, expected: float, tolerance: float = 0.001) -> void:
	_ok(label, absf(actual - expected) <= tolerance, "actual=%f expected=%f" % [actual, expected])


var _engines: Array = []


# register=false — **의도적으로** is_ok를 내리는 음성 프로브용. 전역 사후 조건에서 제외한다
# (그 프로브의 목적이 곧 is_ok 하강이므로 전역 검사에 넣으면 항상 실패한다).
func _new_engine(seed_value: int, circuit_id: String = "", register := true) -> RaceEngine:
	var data := GameData.new()
	if not data.load_all():
		_failures += 1
		print("  [FAIL] data load")
		return null
	if circuit_id != "" and not data.select_circuit(circuit_id):
		return null
	var rng := RngService.new()
	rng.setup(seed_value)
	var engine := RaceEngine.new()
	engine.setup(data, rng)
	if register:
		_engines.append(engine)
	return engine


# 전 엔진 인스턴스 공통 사후 조건: 비정의 전이 0 (TC-C1) · 침묵 기본값 0 (불변규칙 2).
# 개별 항이 아니라 스위트 전체에 걸어 둔다 — 어느 한 시나리오가 위반을 만들어도 잡힌다.
func _check_global_postconditions() -> void:
	for engine in _engines:
		_ok("전역 비정의 전이 0", engine.transition_errors == 0,
			"transition_errors=%d" % engine.transition_errors)
		_ok("전역 데이터 침묵 기본값 0", engine.data.is_ok(),
			"GameData.is_ok()=false — 참조된 값이 데이터에 없다")


# 플레이어를 지정 포지션에 두고 인접 상대의 주행 파라미터를 0으로 눕힌다 —
# 앞차 저항·뒤차 압박이 상수가 되어 게이지 산술을 정확히 단언할 수 있다.
func _flatten_neighbors(engine: RaceEngine) -> void:
	for id in engine.entrants:
		if id == RaceEngine.PLAYER_ID:
			continue
		engine.entrants[id]["pace"] = 0.0
		engine.entrants[id]["aggression"] = 0.0
		engine.entrants[id]["form"] = 0.0
		engine.entrants[id]["rush_roll"] = 0.0
		engine.entrants[id]["rush_lap1"] = 0.0
		engine.entrants[id]["rush_lap_final"] = 0.0
		engine.entrants[id]["pressure_mult"] = 1.0


func _expected_front_resist(engine: RaceEngine) -> float:
	return engine.data.param("param_gauge_front_resist_base")


func _expected_rear_pressure(engine: RaceEngine) -> float:
	return engine.data.param("param_gauge_rear_pressure_base")


# ── D13 확정값 대장 대조 ──
# 여기에만 D13 수치를 **문면 그대로 전사**한다. 다른 검사들은 기대값을 GameData에서
# 읽으므로 값이 바뀌면 기대값도 함께 바뀌어(자기 일관성) 표류를 잡지 못한다.
# 이 블록이 표류 탐지의 유일한 지점이며, 값 변경은 D13 조정 창구(총괄 경유)를 거쳐야 한다.
func _d13_anchor_values() -> void:
	var data := GameData.new()
	if not data.load_all():
		_failures += 1
		print("  [FAIL] data load")
		return
	# D13 별첨A §2.1 게이지 기본값
	_eq_float("D13 §2.1 만충 임계 100", data.param("param_gauge_full_threshold"), 100.0)
	_eq_float("D13 §2.1 모멘텀 보너스 +5", data.param("param_gauge_momentum_bonus"), 5.0)
	_eq_float("D13 §2.1 앞차 저항 기저 3.0", data.param("param_gauge_front_resist_base"), 3.0)
	_eq_float("D13 §2.1 앞차 저항 페이스 계수 1.5", data.param("param_gauge_front_resist_pace_coef"), 1.5)
	_eq_float("D13 §2.1 뒤차 압박 기저 2.0", data.param("param_gauge_rear_pressure_base"), 2.0)
	_eq_float("D13 §2.1 뒤차 압박 공격성 계수 2.2", data.param("param_gauge_rear_pressure_aggr_coef"), 2.2)
	# D13 별첨A §2.2 펄스 차지
	_eq_float("D13 §2.2 보유 상한 10", data.param("param_charge_cap"), 10.0)
	_eq_float("D13 §2.2 안정 완주 +1", data.param("param_charge_stable_sector"), 1.0)
	_eq_float("D13 §2.2 듀얼 승리 +3", data.param("param_charge_duel_win"), 3.0)
	_eq_float("D13 §2.2 홀드·리스핀 −1", data.param("param_charge_hold_cost"), 1.0)
	_eq_float("D13 §2.2 차지 개입 −2", data.param("param_charge_negate_cost"), 2.0)
	_eq_float("D13 §2.2 부스트 차지당 +10", data.param("param_charge_boost_per_judgment"), 10.0)
	_eq_float("D13 §2.2 부스트 1회 최대 4차지", data.param("param_charge_boost_max"), 4.0)
	# D13 별첨A §2.3 섀시 컨디션 (앵커 A5)
	_eq_float("D13 §2.3 섀시 최대 100", data.param("param_chassis_max"), 100.0)
	_eq_float("D13 §2.3 듀얼 실패 페널티 −5", data.param("param_chassis_duel_fail_penalty"), 5.0)
	_eq_float("D13 §2.3 해저드 턴당 소모 1.0", data.param("param_chassis_hazard_per_turn"), 1.0)
	# D13 별첨A §1.2 매치 강도별 효과
	var expected_effects := {
		RaceTypes.SYMBOL_SLIPSTREAM: {1: {"front_gauge": 24.0}, 2: {"front_gauge": 56.0}, 3: {"front_gauge": 95.0}},
		RaceTypes.SYMBOL_BRAKING: {1: {"rear_gauge": -24.0}, 2: {"rear_gauge": -56.0}, 3: {"rear_gauge": -95.0}},
		RaceTypes.SYMBOL_LINE: {1: {"front_gauge": 11.0, "rear_gauge": -11.0}, 2: {"front_gauge": 22.0, "rear_gauge": -22.0}, 3: {"front_gauge": 36.0, "rear_gauge": -36.0}},
		RaceTypes.SYMBOL_PULSE: {1: {"charge": 1.0}, 2: {"charge": 2.0}, 3: {"charge": 4.0}},
		RaceTypes.SYMBOL_TROUBLE: {1: {"chassis": -6.0, "rear_gauge": 12.0}, 2: {"chassis": -14.0, "rear_gauge": 28.0}, 3: {"chassis": -24.0, "rear_gauge": 48.0}},
		RaceTypes.SYMBOL_CHANCE: {1: {"front_gauge": 40.0}, 2: {"front_gauge": 80.0}},
	}
	for symbol_id in expected_effects:
		for match_count in expected_effects[symbol_id]:
			for column in expected_effects[symbol_id][match_count]:
				var actual := CsvTable.to_float(String(data.match_effects[symbol_id][match_count][column]))
				_eq_float("D13 §1.2 %s %d매치 %s" % [symbol_id, match_count, column],
					actual, float(expected_effects[symbol_id][match_count][column]))
	# '해당 없음(0)' 칸은 값이 아니라 **구조적 사실**이다 — 개별 0을 전사하는 대신
	# "그 심볼은 그 축에 관여하지 않는다"를 단언한다. 0이 다른 값으로 바뀌면 이 단언이 깨진다.
	var non_involvement := {
		RaceTypes.SYMBOL_SLIPSTREAM: ["rear_gauge", "charge", "chassis"],
		RaceTypes.SYMBOL_BRAKING: ["front_gauge", "charge", "chassis"],
		RaceTypes.SYMBOL_LINE: ["charge", "chassis"],
		RaceTypes.SYMBOL_PULSE: ["front_gauge", "rear_gauge", "chassis"],
		RaceTypes.SYMBOL_TROUBLE: ["front_gauge", "charge"],
		RaceTypes.SYMBOL_CHANCE: ["rear_gauge", "charge", "chassis"],
	}
	for symbol_id in non_involvement:
		for match_count in [1, 2, 3]:
			for column in non_involvement[symbol_id]:
				_eq_float("구조: %s는 %s에 관여하지 않음 (%d매치)" % [symbol_id, column, match_count],
					CsvTable.to_float(String(data.match_effects[symbol_id][match_count][column])), 0.0)
	_ok("D13 §1.2 찬스 3매치 = 즉시 듀얼",
		String(data.match_effects[RaceTypes.SYMBOL_CHANCE][3]["special"]).strip_edges() == "duel_trigger")
	# 구조: 듀얼 환산의 축 분리 — {슬립,브레이킹,라인}은 match1~3 축, {찬스,트러블}은 per_symbol 축.
	# 축 밖 값이 0이라는 사실을 고정한다 (찬스가 match 값을 얻거나 슬립이 per_symbol을 얻으면 위반).
	var match_axis := [RaceTypes.SYMBOL_SLIPSTREAM, RaceTypes.SYMBOL_BRAKING, RaceTypes.SYMBOL_LINE]
	var per_symbol_axis := [RaceTypes.SYMBOL_CHANCE, RaceTypes.SYMBOL_TROUBLE]
	for symbol_id in match_axis:
		_eq_float("구조: %s는 per_symbol 축 밖" % symbol_id,
			CsvTable.to_float(String(data.duel_conversion[symbol_id]["per_symbol"])), 0.0)
		var nonzero := false
		for match_count in [1, 2, 3]:
			if absf(CsvTable.to_float(String(data.duel_conversion[symbol_id]["match%d" % match_count]))) > 0.0001:
				nonzero = true
		_ok("구조: %s는 match 축에 값을 갖는다" % symbol_id, nonzero)
	for symbol_id in per_symbol_axis:
		for match_count in [1, 2, 3]:
			_eq_float("구조: %s는 match 축 밖 (%d)" % [symbol_id, match_count],
				CsvTable.to_float(String(data.duel_conversion[symbol_id]["match%d" % match_count])), 0.0)
		_ok("구조: %s는 per_symbol 축에 값을 갖는다" % symbol_id,
			absf(CsvTable.to_float(String(data.duel_conversion[symbol_id]["per_symbol"]))) > 0.0001)
	# D13 별첨A §1.1 기본 심볼 분포 (앵커 A4) — 합 1.0
	var expected_probability := {
		"symbol_slipstream": 0.22, "symbol_braking": 0.20, "symbol_line": 0.23,
		"symbol_pulse": 0.12, "symbol_trouble": 0.18, "symbol_chance": 0.05,
	}
	var probability_sum := 0.0
	for row in data.symbols:
		var symbol_id := String(row["id"])
		for reel in [1, 2, 3]:
			var probability := CsvTable.to_float(String(row["prob_reel%d" % reel]))
			_eq_float("D13 §1.1 %s 릴%d 확률" % [symbol_id, reel], probability,
				float(expected_probability.get(symbol_id, -1.0)))
		probability_sum += CsvTable.to_float(String(row["prob_reel1"]))
	_eq_float("D13 §1.1 릴 확률 합 1.0", probability_sum, 1.0)
	# D13 별첨A §1.3 속성 6축 심볼 가중 계수 — 36칸 전수 전사.
	# 여기 없으면 계수를 어떻게 바꿔도(부호 반전 포함) 검출되지 않는다: 다른 검사는
	# 기대값을 같은 CSV에서 읽어 자기 일관성에 걸린다 (독립 검증 G-1에서 44칸 미검출로 확인).
	var expected_attr_weights := {
		"attr_straight":      {"w_forward": 0.06, "w_defense": -0.03, "w_control": -0.03, "w_resource": 0.0, "w_hazard": 0.0, "w_rare": 0.0},
		"attr_technical":     {"w_forward": -0.05, "w_defense": 0.04, "w_control": 0.04, "w_resource": 0.0, "w_hazard": -0.03, "w_rare": 0.0},
		"attr_sweeper":       {"w_forward": -0.04, "w_defense": -0.03, "w_control": 0.05, "w_resource": 0.0, "w_hazard": 0.02, "w_rare": 0.0},
		"attr_hazard":        {"w_forward": -0.03, "w_defense": 0.0, "w_control": -0.04, "w_resource": 0.0, "w_hazard": 0.07, "w_rare": 0.0},
		"attr_battle_zone":   {"w_forward": 0.0, "w_defense": 0.0, "w_control": -0.04, "w_resource": 0.01, "w_hazard": 0.01, "w_rare": 0.03},
		"attr_pulse_section": {"w_forward": -0.04, "w_defense": -0.04, "w_control": 0.0, "w_resource": 0.08, "w_hazard": 0.0, "w_rare": 0.0},
	}
	for attr_id in expected_attr_weights:
		var attr_row := data.sector_attr(String(attr_id))
		for column in expected_attr_weights[attr_id]:
			_eq_float("D13 §1.3 %s.%s" % [attr_id, column],
				CsvTable.to_float(String(attr_row[column])),
				float(expected_attr_weights[attr_id][column]), 0.0001)
	# 규칙 계수: A4·A5만 1.0이 아니다 (나머지 4속성이 계수를 얻으면 설계 의미가 달라진다)
	for attr_id in expected_attr_weights:
		var attr_row2 := data.sector_attr(String(attr_id))
		var expected_gauge := 1.5 if attr_id == "attr_battle_zone" else 1.0
		var expected_wear := 1.15 if attr_id == "attr_hazard" else 1.0
		_eq_float("D13 §1.3 %s 게이지 계수" % attr_id,
			CsvTable.to_float(String(attr_row2["gauge_mult"])), expected_gauge)
		_eq_float("D13 §1.3 %s 섀시 소모 계수" % attr_id,
			CsvTable.to_float(String(attr_row2["chassis_wear_mult"])), expected_wear)
	_eq_float("D13 §1.3 배틀 존 게이지 ×1.5",
		CsvTable.to_float(String(data.sector_attr("attr_battle_zone")["gauge_mult"])), 1.5)
	_eq_float("D13 §1.3 해저드 섀시 소모 ×1.15",
		CsvTable.to_float(String(data.sector_attr("attr_hazard")["chassis_wear_mult"])), 1.15)
	_eq_float("D13 §1.3 최종 랩 게이지 ×1.2", data.param("param_gauge_final_lap_mult"), 1.2)
	# D13 별첨A §2.4 듀얼 심볼 환산
	_eq_float("D13 §2.4 슬립 1매치 환산 38",
		CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_SLIPSTREAM]["match1"])), 38.0)
	_eq_float("D13 §2.4 슬립 2매치 환산 64",
		CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_SLIPSTREAM]["match2"])), 64.0)
	_eq_float("D13 §2.4 슬립 3매치 환산 95",
		CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_SLIPSTREAM]["match3"])), 95.0)
	_eq_float("D13 §2.4 트러블 환산 −15 (개당)",
		CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_TROUBLE]["per_symbol"])), -15.0)
	_eq_float("D13 §2.4 찬스 환산 40 (개당)",
		CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_CHANCE]["per_symbol"])), 40.0)
	# D13 별첨A §6.6 레조넌스 — 무대별 보너스 5종 전사 대조 (수치의 유일 창구 = D13).
	# 펄스 돔 값 0 = "즉시 만충"이라 값 미소비 [가안 — impl_log] · 미라지 +30 = 필드 정비 회당 상한과 동치.
	var expected_resonance := {
		"stage_metro_night": ["charge", 2.0],
		"stage_azure_coast": ["front_gauge", 60.0],
		"stage_alta_ridge":  ["duel_judgment", 25.0],
		"stage_mirage_flat": ["chassis", 30.0],
		"stage_pulse_dome":  ["front_gauge_full", 0.0],
	}
	for stage_id in expected_resonance:
		var stage: Dictionary = data.stages.get(stage_id, {})
		var pair: Array = expected_resonance[stage_id]
		_ok("D13 §6.6 %s 보너스 유형 = %s" % [stage_id, pair[0]],
			String(stage.get("resonance_bonus_type", "")) == String(pair[0]), str(stage.get("resonance_bonus_type")))
		_eq_float("D13 §6.6 %s 보너스 값" % stage_id,
			float(stage.get("resonance_bonus_value", -1.0)), float(pair[1]))
	# D08 §5.1 벽 배치 전사 대조 — 무벽 메트로 포함 (벽 오배치 = 난이도 곡선 변조)
	var expected_walls := {
		"stage_metro_night": "", "stage_azure_coast": "ai_diaz", "stage_alta_ridge": "ai_sherwood",
		"stage_mirage_flat": "ai_holloway", "stage_pulse_dome": "ai_lorentz",
	}
	for stage_id2 in expected_walls:
		_ok("D08 §5.1 벽 배치: %s" % stage_id2,
			String(data.stages.get(stage_id2, {}).get("wall_rival", "?")) == String(expected_walls[stage_id2]),
			str(data.stages.get(stage_id2, {}).get("wall_rival")))
	# D13 별첨A §6.2 AI 파라미터 5층 — 네임드 8인 전수 전사.
	# 전사 없이는 라이벌 주행 파라미터 72칸이 자기 일관성에 걸려 부호 반전도 미검출이다
	# (독립 검증 G-1 실측: ai_rivals.csv 72칸 전량 미검출).
	var expected_rivals := {
		"ai_lorentz":  {"pace": 5.2, "aggression": 3.0, "stability": 5.0, "start_mod": 4.0, "form_var": 0.0, "wall_pace_add": 1.0},
		"ai_maro":     {"pace": 4.0, "aggression": 3.0, "stability": 4.0, "start_mod": 5.0, "rush_lap1": 0.5, "wall_pace_add": 0.0},
		"ai_diaz":     {"pace": 4.0, "aggression": 5.0, "stability": 2.0, "start_mod": 3.0, "wall_pace_add": 1.4},
		"ai_volkova":  {"pace": 3.0, "aggression": 4.0, "stability": 2.0, "start_mod": 4.0, "rush_lap1": 1.5, "rush_lap_final": -1.0, "wall_pace_add": 0.0},
		"ai_holloway": {"pace": 4.0, "aggression": 3.0, "stability": 4.0, "start_mod": 3.0, "rush_lap_final": 1.5, "wall_pace_add": 1.4},
		"ai_bianca":   {"pace": 4.0, "aggression": 2.0, "stability": 4.0, "start_mod": 4.0, "wall_pace_add": 0.0},
		"ai_sherwood": {"pace": 3.0, "aggression": 4.0, "stability": 3.0, "start_mod": 2.0, "rush_random": 1.0, "wall_pace_add": 1.9},
		"ai_jude":     {"pace": 3.0, "aggression": 3.0, "stability": 2.0, "start_mod": 2.0, "rush_random": 1.5, "wall_pace_add": 0.0},
	}
	var rival_rows: Dictionary = {}
	for row in data.rivals:
		rival_rows[String(row["id"])] = row
	for rival_id in expected_rivals:
		_ok("D13 §6.2 %s 등재" % rival_id, rival_rows.has(rival_id))
		if not rival_rows.has(rival_id):
			continue
		for column in expected_rivals[rival_id]:
			_eq_float("D13 §6.2 %s.%s" % [rival_id, column],
				CsvTable.to_float(String(rival_rows[rival_id][column])),
				float(expected_rivals[rival_id][column]), 0.0001)
	# 비앙카 압박 훅 (D13 §6.2 "안정성 4.0(압박 시 2.5)" · D08 §6.3 조건 분기 위임분).
	_eq_float("D13 §6.2 비앙카 압박 시 안정성 2.5",
		CsvTable.to_float(String(rival_rows["ai_bianca"]["stability_under_pressure"])), 2.5)
	# 조건 분기가 없는 라이벌은 공란 — 값 0이 아니라 "훅 없음"이다.
	for rival_id in ["ai_lorentz", "ai_diaz", "ai_sherwood"]:
		_ok("압박 훅 없음: %s" % rival_id,
			String(rival_rows[rival_id]["stability_under_pressure"]).strip_edges() == "",
			String(rival_rows[rival_id]["stability_under_pressure"]))
	_eq_float("D13 §6.2 로렌츠 폼 분산 0 (무결점 연산)",
		CsvTable.to_float(String(rival_rows["ai_lorentz"]["form_var"])), 0.0)
	_eq_float("D13 §2.4 로렌츠 방어 임계 55",
		CsvTable.to_float(String(rival_rows["ai_lorentz"]["duel_defense_override"])), 55.0)
	_eq_float("D13 §2.4 로렌츠 추월 가산 +70",
		CsvTable.to_float(String(rival_rows["ai_lorentz"]["duel_overtake_add"])), 70.0)
	# 구조: 비0 라이벌은 D13 §6.2가 명시한 그 라이벌뿐이다 (0 = "해당 없음"이라는 대장 사실)
	var exclusive_owners := {
		"duel_overtake_add": ["ai_lorentz"],
		"rush_lap1": ["ai_maro", "ai_volkova"],
		"rush_lap_final": ["ai_volkova", "ai_holloway"],
		"rush_random": ["ai_sherwood", "ai_jude"],
		"stability_under_pressure": ["ai_bianca"],
		"wall_pace_add": ["ai_lorentz", "ai_diaz", "ai_sherwood", "ai_holloway"],
	}
	for column in exclusive_owners:
		for rival_id in rival_rows:
			var raw := String(rival_rows[rival_id][column]).strip_edges()
			var is_zero := raw == "" or absf(raw.to_float()) < 0.0001
			var should_own: bool = Array(exclusive_owners[column]).has(rival_id)
			_ok("구조: %s.%s %s" % [rival_id, column, "비0" if should_own else "0"],
				is_zero != should_own, "raw=%s" % raw)
	# 팀 프로파일 가산 (D08 §6.2 · D13 별첨A §6.2)
	var expected_teams := {
		"team_axion":       {"pace_add": 0.0, "aggression_add": 0.0, "stability_add": 0.5, "rush_lap_final_add": 0.0, "pressure_mult": 1.0},
		"team_vulka":       {"pace_add": 0.0, "aggression_add": 0.5, "stability_add": -0.5, "rush_lap_final_add": 0.0, "pressure_mult": 1.3},
		"team_gryphon":     {"pace_add": 0.0, "aggression_add": 0.0, "stability_add": 0.3, "rush_lap_final_add": 0.3, "pressure_mult": 1.0},
		"team_silvertrail": {"pace_add": 0.0, "aggression_add": 0.0, "stability_add": 0.0, "rush_lap_final_add": 0.0, "pressure_mult": 1.0},
		"team_cometworks":  {"pace_add": 0.0, "aggression_add": 0.0, "stability_add": 0.0, "rush_lap_final_add": 0.0, "pressure_mult": 1.0},
	}
	for team_id in expected_teams:
		_ok("D08 §6.2 %s 등재" % team_id, data.teams.has(team_id))
		if not data.teams.has(team_id):
			continue
		for column in expected_teams[team_id]:
			_eq_float("D08 §6.2 %s.%s" % [team_id, column],
				CsvTable.to_float(String(data.teams[team_id][column]), 0.0),
				float(expected_teams[team_id][column]), 0.0001)
	# 변동 요소·AI 거동 (D13 별첨A §6.2)
	# 네임드 폼 분산은 개별 열(ai_rivals.form_var)이 소비 경로다. 클래스 단위 파라미터를
	# 따로 두면 단언이 죽은 쪽에 붙어 실제 값 7칸이 무방비가 된다(독립 감사 누락-1).
	for rival_id in expected_rivals:
		if not rival_rows.has(rival_id):
			continue
		var expected_form := 0.0 if rival_id == "ai_lorentz" else 0.3
		_eq_float("D13 §6.2 %s.form_var" % rival_id,
			CsvTable.to_float(String(rival_rows[rival_id]["form_var"])), expected_form)
	_eq_float("D13 §6.2 필러 폼 분산 0.3", data.param("param_form_var_filler"), 0.3)
	_eq_float("D13 §6.2 필러 스탯 편차 0.5", data.param("param_filler_stat_var"), 0.5)
	_eq_float("D13 §6.2 스왑 하한 0.010", data.param("param_ai_swap_min"), 0.010)
	_eq_float("D13 §6.2 스왑 기저 0.055", data.param("param_ai_swap_base"), 0.055)
	_eq_float("D13 §6.2 스왑 페이스 계수 0.045", data.param("param_ai_swap_pace_coef"), 0.045)
	_eq_float("D13 §6.2 리타이어 안정성 계수 0.025", data.param("param_ai_retire_stability_coef"), 0.025)
	_eq_float("D13 §6.2 리타이어 상수 0.002", data.param("param_ai_retire_const"), 0.002)
	_eq_float("D13 §6.2 리타이어 GP 상한 2", data.param("param_ai_retire_gp_cap"), 2.0)
	_eq_float("D13 §6.2 그리드 레벨 페이스 +0.4", data.param("param_grid_level_pace_add"), 0.4)
	_eq_float("D13 §6.2 그리드 레벨 듀얼 임계 +3", data.param("param_duel_grid_level_coef"), 3.0)
	_eq_float("D13 §6.3 시작 보정 계수 0.5", data.param("param_grid_start_mod_coef"), 0.5)
	# D13 별첨A §6.2 슬롯 진행 보정 — 사용자 판정(U-5·2026-08-12): 축 = **투어 내 GP 슬롯**(제1~4전)
	var expected_slot_mods := {1: 0.00, 2: 0.05, 3: 0.10, 4: 0.15}
	for race_slot in expected_slot_mods:
		_eq_float("D13 §6.2 GP 슬롯 %d 보정 +%.2f" % [race_slot, expected_slot_mods[race_slot]],
			data.tour_slot_pace_add(race_slot), float(expected_slot_mods[race_slot]))
	_ok("슬롯 보정은 후반 슬롯일수록 크다 (D08 §2.4)",
		data.tour_slot_pace_add(4) > data.tour_slot_pace_add(1))
	_ok("슬롯 보정 폭 < 무대 다이얼 (D08 §2.4 한 자릿수 작게)",
		data.tour_slot_pace_add(4) < 1.0, "slot4=%f" % data.tour_slot_pace_add(4))
	# D13 별첨A §2.4 방어 primary(브레이킹)·라인 환산 — 추월 축만 전사하면 방어 축이 새 나간다
	_eq_float("D13 §2.4 브레이킹 1매치 38",
		CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_BRAKING]["match1"])), 38.0)
	_eq_float("D13 §2.4 브레이킹 2매치 64",
		CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_BRAKING]["match2"])), 64.0)
	_eq_float("D13 §2.4 브레이킹 3매치 95",
		CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_BRAKING]["match3"])), 95.0)
	_eq_float("D13 §2.4 라인 1매치 15",
		CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_LINE]["match1"])), 15.0)
	_eq_float("D13 §2.4 라인 2매치 30",
		CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_LINE]["match2"])), 30.0)
	_eq_float("D13 §2.4 라인 3매치 50",
		CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_LINE]["match3"])), 50.0)
	# D13 별첨A §8.1 타이머·연출 값
	_eq_float("D13 §8.1 타이머 기본 10초", data.param("param_timer_base_sec"), 10.0)
	_eq_float("D13 §8.1 여유 구간 경계 0.6", data.param("param_timer_leeway_ratio"), 0.6)
	_eq_float("D13 §8.1 경고 구간 경계 0.3", data.param("param_timer_warning_ratio"), 0.3)
	_eq_float("D13 §8.1 릴 정지 간격 0.4초", data.param("param_reel_stop_interval_sec"), 0.4)
	# D13 별첨A §4.1 시간 모델 성분
	_eq_float("D13 §4.1 턴 21초", data.param("param_time_turn_sec"), 21.0)
	_eq_float("D13 §4.1 듀얼 45초", data.param("param_time_duel_sec"), 45.0)
	_eq_float("D13 §4.1 완급 비트 1초/턴", data.param("param_time_pacing_beat_sec"), 1.0)
	_eq_float("D13 §4.1 결산·이벤트 225초 (U-5 판정 반영)", data.param("param_time_wrapup_sec"), 225.0)
	# D13 별첨A §6.1 P9↓ = 0 (P10~P16 명시 행 — 침묵 대체가 아니라 데이터로)
	for position in range(9, 17):
		_ok("D13 §6.1 P%d = 0점" % position, int(data.points_tier1.get(position, -1)) == 0,
			"actual=%s" % str(data.points_tier1.get(position)))
	# D13 별첨A §2.1 앞차 저항·뒤차 압박 — **인쇄된 산출 예에 도달하는지** 대조.
	# 산식만 맞고 입력이 틀리면(팀 가산 포함 등) 정본에 인쇄된 값이 도달 불가능해진다.
	var resist_base := data.param("param_gauge_front_resist_base")
	var resist_coef := data.param("param_gauge_front_resist_pace_coef")
	_eq_float("D13 §2.1 필러 앞차 저항 7.5", resist_base + 3.0 * resist_coef, 7.5)
	_eq_float("D13 §2.1 로렌츠 앞차 저항 10.8", resist_base + 5.2 * resist_coef, 10.8)
	var pressure_base := data.param("param_gauge_rear_pressure_base")
	var pressure_coef := data.param("param_gauge_rear_pressure_aggr_coef")
	_eq_float("D13 §2.1 필러 뒤차 압박 8.6", pressure_base + 3.0 * pressure_coef, 8.6)
	var diaz_aggression := 0.0
	var vulka_pressure := 0.0
	for row in data.rivals:
		if String(row["id"]) == "ai_diaz":
			diaz_aggression = CsvTable.to_float(String(row["aggression"]))
	if data.teams.has("team_vulka"):
		vulka_pressure = CsvTable.to_float(String(data.teams["team_vulka"]["pressure_mult"]), 1.0)
	_eq_float("D13 §2.1 디아스 뒤차 압박 13.0", pressure_base + diaz_aggression * pressure_coef, 13.0)
	_eq_float("D13 §2.1 디아스 압박 ×1.3 = 16.9",
		(pressure_base + diaz_aggression * pressure_coef) * vulka_pressure, 16.9, 0.01)
	# D13 별첨A §6.1 1층 챔피언십 포인트
	var expected_points := {1: 10, 2: 8, 3: 6, 4: 5, 5: 4, 6: 3, 7: 2, 8: 1, 9: 0}
	for position in expected_points:
		_ok("D13 §6.1 P%d = %d점" % [position, expected_points[position]],
			int(data.points_tier1.get(position, -1)) == int(expected_points[position]),
			"actual=%s" % str(data.points_tier1.get(position)))


# ── TC-C1 그랑프리 상태 머신 — 폐쇄성: 비정의 전이 도달 0 · 고아 상태 0 ──
func _tc_c1_state_machine_closure() -> void:
	var states: Array = RaceTypes.GpState.values()
	for state in states:
		_ok("TC-C1 전이표 등재", RaceTypes.TRANSITIONS.has(state), "state=%d" % state)
	for state in RaceTypes.TRANSITIONS:
		for target in RaceTypes.TRANSITIONS[state]:
			_ok("TC-C1 전이 대상 유효", states.has(target), "%d -> %d" % [state, target])
	# 도달성: GP_START에서 폭 우선 탐색으로 전 상태 도달 (고아 0)
	var reached := {RaceTypes.GpState.GP_START: true}
	var frontier: Array = [RaceTypes.GpState.GP_START]
	while not frontier.is_empty():
		var current: int = frontier.pop_front()
		for target in RaceTypes.TRANSITIONS[current]:
			if not reached.has(target):
				reached[target] = true
				frontier.append(target)
	for state in states:
		_ok("TC-C1 고아 상태 0", reached.has(state), "unreachable state=%d" % state)
	# 종단: RESULT는 유출 전이 0
	_ok("TC-C1 RESULT 종단", Array(RaceTypes.TRANSITIONS[RaceTypes.GpState.RESULT]).is_empty())


# ── TC-C2 턴 시퀀스 — 1턴 내부 단계 순서 위반 0 (D05 §2.3 · D12 §3.3) ──
func _tc_c2_turn_sequence() -> void:
	var engine := _new_engine(11)
	if engine == null:
		return
	engine.start_gp()
	engine.begin_turn()
	engine.spin()
	engine.confirm(1.0)
	var expected := [
		RaceTypes.TurnPhase.T1_SECTOR_OPEN,
		RaceTypes.TurnPhase.T2_SPIN,
		RaceTypes.TurnPhase.T3_PROVISIONAL,
		RaceTypes.TurnPhase.T4_INTERVENTION,
		RaceTypes.TurnPhase.T5_TRANSLATE,
		RaceTypes.TurnPhase.T6_SETTLE,
	]
	_ok("TC-C2 T1~T6 전 단계 통과", engine.phase_log == expected, "log=%s" % str(engine.phase_log))
	# 단계 건너뛰기 금지: 스핀 전 확정 시도는 무효 (창 외 조작)
	var engine2 := _new_engine(11)
	engine2.start_gp()
	engine2.begin_turn()
	var events: Array = engine2.confirm(1.0)
	_ok("TC-C2 스핀 없는 확정 무효", events.is_empty() and engine2.turn_phase == RaceTypes.TurnPhase.T1_SECTOR_OPEN,
		"phase=%d" % engine2.turn_phase)


# ── TC-C3·TC-C10 정산 8단계 — 로그 열거가 코드 상수와 완전 일치 · 신규 판정 단계 0 ──
func _tc_c3_settle_order_log() -> void:
	var engine := _new_engine(5)
	if engine == null:
		return
	engine.start_gp()
	engine.begin_turn()
	engine.spin()
	engine.confirm(1.0)
	_ok("TC-C10 정산 로그 = SETTLE_ORDER", engine.settle_log == RaceTypes.SETTLE_ORDER,
		"log=%s" % str(engine.settle_log))
	_ok("TC-C10 단계 수 8", engine.settle_log.size() == 8, "size=%d" % engine.settle_log.size())
	# 듀얼 턴도 동일 8단계를 열거한다 (①~⑤ 무동작이어도 단계 자체는 통과 — IMPL-009)
	var engine2 := _new_engine(5)
	engine2.start_gp()
	_flatten_neighbors(engine2)
	_force_duel(engine2, RaceTypes.DuelType.OVERTAKE)
	engine2.begin_turn()
	engine2.spin()
	engine2.confirm(1.0)
	_ok("TC-C10 듀얼 턴도 8단계 열거", engine2.settle_log == RaceTypes.SETTLE_ORDER,
		"log=%s" % str(engine2.settle_log))


# 예약 듀얼을 강제로 세운다 — 인접 상대를 상대로 다음 begin_turn()이 듀얼 턴이 되게.
# 듀얼 예약은 실제로는 섹터 턴 정산(단계 ⑥)에서만 발생하므로, GP 개시 직후의
# LAP_LOOP 상태에서 곧바로 듀얼로 넘기면 전이표에 없는 경로가 된다.
# 따라서 중립 섹터 턴 1회를 먼저 정상 주행해 상태를 SECTOR_TURN으로 옮긴다.
func _force_duel(engine: RaceEngine, duel_type: int) -> String:
	if engine.gp_state == RaceTypes.GpState.LAP_LOOP:
		engine.begin_turn()
		engine.spin()
		engine.provisional = _combo(RaceTypes.SYMBOL_PULSE, 3, RaceTypes.SYMBOL_PULSE)
		engine.confirm(0.0)
	var player_index := engine.positions.find(RaceEngine.PLAYER_ID)
	# 필요한 인접 슬롯이 없으면(선두는 앞차 없음·최하위는 뒤차 없음) 플레이어를 한 칸 안으로 옮긴다.
	# 시작 그리드는 P16이므로 방어 듀얼은 이 재배치 없이는 성립하지 않는다.
	if duel_type == RaceTypes.DuelType.OVERTAKE and player_index <= 0:
		engine.positions.erase(RaceEngine.PLAYER_ID)
		engine.positions.insert(1, RaceEngine.PLAYER_ID)
	elif duel_type == RaceTypes.DuelType.DEFENSE and player_index >= engine.positions.size() - 1:
		engine.positions.erase(RaceEngine.PLAYER_ID)
		engine.positions.insert(engine.positions.size() - 1, RaceEngine.PLAYER_ID)
	engine._retarget(true, true)
	player_index = engine.positions.find(RaceEngine.PLAYER_ID)
	var opponent_index := player_index - 1 if duel_type == RaceTypes.DuelType.OVERTAKE else player_index + 1
	var opponent_id := String(engine.positions[opponent_index])
	engine.pending_duel = duel_type
	engine.duel_opponent = opponent_id
	if duel_type == RaceTypes.DuelType.OVERTAKE:
		engine.front_target = opponent_id
	else:
		engine.rear_target = opponent_id
	return opponent_id


# ── TC-C4 개입 4타입·개입 창 — 창 외 개입 무효 · 타입별 효과 D13 정합 ──
func _tc_c4_interventions() -> void:
	var engine := _new_engine(3)
	if engine == null:
		return
	engine.start_gp()
	engine.begin_turn()
	# ① 창 외 개입 무효 (T4 진입 전)
	_ok("TC-C4 창 외 홀드 무효", not bool(engine.hold_respin([0]).get("ok", false)))
	_ok("TC-C4 창 외 트러블무효 무효", not bool(engine.negate_trouble().get("ok", false)))
	_ok("TC-C4 창 외 부스트 무효", not bool(engine.add_duel_boost().get("ok", false)))
	engine.spin()
	# ② 홀드 & 리스핀 — 비용 = D13 param_charge_hold_cost · 턴당 1회 한도
	engine.charge = engine.data.param_int("param_charge_cap")
	var before_charge := engine.charge
	var kept_symbol: String = engine.get_provisional()[0]
	var hold_result: Dictionary = engine.hold_respin([0])
	_ok("TC-C4 홀드 성립", bool(hold_result.get("ok", false)), str(hold_result))
	_eq_float("TC-C4 홀드 비용", float(before_charge - engine.charge),
		engine.data.param("param_charge_hold_cost"))
	_ok("TC-C4 홀드 릴 고정", engine.get_provisional()[0] == kept_symbol)
	_ok("TC-C4 홀드 턴당 1회", not bool(engine.hold_respin([0]).get("ok", false)))
	# ③ 차지 개입 (트러블 1개 무효) — 비용 = D13 · 트러블 부재 시 무효
	var engine2 := _new_engine(3)
	engine2.start_gp()
	engine2.begin_turn()
	engine2.spin()
	engine2.charge = engine2.data.param_int("param_charge_cap")
	engine2.provisional = [RaceTypes.SYMBOL_TROUBLE, RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_LINE]
	var before2 := engine2.charge
	_ok("TC-C4 트러블무효 성립", bool(engine2.negate_trouble().get("ok", false)))
	_eq_float("TC-C4 트러블무효 비용", float(before2 - engine2.charge),
		engine2.data.param("param_charge_negate_cost"))
	_ok("TC-C4 트러블 소진 후 재무효 거부", not bool(engine2.negate_trouble().get("ok", false)))
	# 무효화된 트러블은 섀시를 깎지 않는다
	var chassis_before := engine2.chassis
	engine2.confirm(0.0)
	_eq_float("TC-C4 무효화 트러블 섀시 무영향", engine2.chassis, chassis_before)
	# ④ 듀얼 부스트 — 차지당 1 소비 · 상한 = D13 param_charge_boost_max
	var engine3 := _new_engine(3)
	engine3.start_gp()
	_flatten_neighbors(engine3)
	_force_duel(engine3, RaceTypes.DuelType.OVERTAKE)
	engine3.begin_turn()
	engine3.spin()
	engine3.charge = engine3.data.param_int("param_charge_cap")
	var boost_cap := engine3.data.param_int("param_charge_boost_max")
	var before3 := engine3.charge
	var granted := 0
	while bool(engine3.add_duel_boost().get("ok", false)):
		granted += 1
		if granted > boost_cap + 5:
			break
	_ok("TC-C4 부스트 상한", granted == boost_cap, "granted=%d cap=%d" % [granted, boost_cap])
	_eq_float("TC-C4 부스트 차지 소비", float(before3 - engine3.charge), float(boost_cap))
	# ⑤ 섹터 턴에서는 부스트 불가 (듀얼 전속)
	var engine4 := _new_engine(3)
	engine4.start_gp()
	engine4.begin_turn()
	engine4.spin()
	engine4.charge = engine4.data.param_int("param_charge_cap")
	_ok("TC-C4 섹터 턴 부스트 거부", not bool(engine4.add_duel_boost().get("ok", false)))


# ── TC-C5 펄스 차지 수급·소비 — 수지 = D13 정합 · 음수 잔액 0 · 상한 준수 ──
func _tc_c5_pulse_charge_ledger() -> void:
	var engine := _new_engine(21)
	if engine == null:
		return
	engine.start_gp()
	_flatten_neighbors(engine)
	# 펄스 매치별 차지 = D13 별첨A §1.2 (테이블 값과 실적용 대조)
	for match_count in [1, 2, 3]:
		var probe := _new_engine(21)
		probe.start_gp()
		_flatten_neighbors(probe)
		probe.begin_turn()
		probe.spin()
		probe.charge = 0
		probe.provisional = _combo(RaceTypes.SYMBOL_PULSE, match_count, RaceTypes.SYMBOL_LINE)
		probe.confirm(0.0)
		var table_charge := CsvTable.to_int(String(probe.data.match_effects[RaceTypes.SYMBOL_PULSE][match_count]["charge"]))
		var stable_bonus := probe.data.param_int("param_charge_stable_sector")
		_ok("TC-C5 펄스 %d매치 차지" % match_count,
			probe.charge == table_charge + stable_bonus,
			"charge=%d expected=%d" % [probe.charge, table_charge + stable_bonus])
	# 안정 완주 섹터 +1: 트러블이 발생하면 미지급
	var probe2 := _new_engine(21)
	probe2.start_gp()
	_flatten_neighbors(probe2)
	probe2.begin_turn()
	probe2.spin()
	probe2.charge = 0
	probe2.provisional = [RaceTypes.SYMBOL_TROUBLE, RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_LINE]
	probe2.confirm(0.0)
	_ok("TC-C5 트러블 턴 안정 보너스 미지급", probe2.charge == 0, "charge=%d" % probe2.charge)
	# 보유 상한 = D13 param_charge_cap
	var probe3 := _new_engine(21)
	probe3.start_gp()
	_flatten_neighbors(probe3)
	probe3.begin_turn()
	probe3.spin()
	var cap := probe3.data.param_int("param_charge_cap")
	probe3.charge = cap
	probe3.provisional = _combo(RaceTypes.SYMBOL_PULSE, 3, RaceTypes.SYMBOL_LINE)
	probe3.confirm(0.0)
	_ok("TC-C5 차지 상한 준수", probe3.charge == cap, "charge=%d cap=%d" % [probe3.charge, cap])
	# 음수 잔액 0: 비용이 잔액을 넘는 개입은 거부된다
	var probe4 := _new_engine(21)
	probe4.start_gp()
	probe4.begin_turn()
	probe4.spin()
	probe4.charge = 0
	probe4.provisional = [RaceTypes.SYMBOL_TROUBLE, RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_LINE]
	_ok("TC-C5 잔액 부족 홀드 거부", not bool(probe4.hold_respin([0]).get("ok", false)))
	_ok("TC-C5 잔액 부족 트러블무효 거부", not bool(probe4.negate_trouble().get("ok", false)))
	_ok("TC-C5 음수 잔액 0", probe4.charge >= 0, "charge=%d" % probe4.charge)


func _combo(symbol_id: String, count: int, filler: String) -> Array:
	var result: Array = []
	for i in range(3):
		result.append(symbol_id if i < count else filler)
	return result


# ── TC-C6 듀얼 개시~종결 — 임계 산식 D13 별첨A §2.4 정합 ──
# 산식: 추월 임계 = param_duel_overtake_base + 안정성(시드) × coef + 개체 가산
#       필러 = 35 + 3.0 × 4.5 = 48.5 / 로렌츠 = 35 + 5.0 × 4.5 + 70 = 127.5
func _tc_c6_duel_thresholds() -> void:
	var engine := _new_engine(31)
	if engine == null:
		return
	engine.start_gp()
	var base := engine.data.param("param_duel_overtake_base")
	var coef := engine.data.param("param_duel_overtake_stability_coef")
	var filler_threshold := base + 3.0 * coef
	_eq_float("TC-C6 필러 추월 임계 48.5", filler_threshold, 48.5)
	var lorentz_add := 0.0
	for row in engine.data.rivals:
		if String(row["id"]) == "ai_lorentz":
			lorentz_add = CsvTable.to_float(String(row["duel_overtake_add"]))
	_eq_float("TC-C6 로렌츠 추월 임계 127.5", base + 5.0 * coef + lorentz_add, 127.5)
	var defense_base := engine.data.param("param_duel_defense_base")
	var defense_coef := engine.data.param("param_duel_defense_aggression_coef")
	_eq_float("TC-C6 필러 방어 임계 45", defense_base + 3.0 * defense_coef, 45.0)
	# 비앙카 압박 훅이 추월 임계에 실제로 작용하는가 (D13 §6.2 · IMPL-016 유보분 해소).
	# 훅 없는 동일 안정성 라이벌(홀로웨이 4.0)과 비교하면 차이가 훅에서만 온다.
	var bianca_threshold := engine._duel_threshold(RaceTypes.DuelType.OVERTAKE, "ai_bianca")
	var holloway_threshold := engine._duel_threshold(RaceTypes.DuelType.OVERTAKE, "ai_holloway")
	_eq_float("비앙카 추월 임계 = 35 + 2.5×4.5", bianca_threshold, base + 2.5 * coef)
	_eq_float("홀로웨이 추월 임계 = 35 + 4.0×4.5", holloway_threshold, base + 4.0 * coef)
	_ok("압박 훅이 임계를 낮춘다", bianca_threshold < holloway_threshold,
		"bianca=%f holloway=%f" % [bianca_threshold, holloway_threshold])
	# 부등식 검증 (D13 별첨A §2.4 V-1): 무개입 1매치 < 필러 임계 < 2매치 + 부스트
	var conversion: Dictionary = engine.data.duel_conversion[RaceTypes.SYMBOL_SLIPSTREAM]
	var one_match := CsvTable.to_float(String(conversion["match1"]))
	var two_match := CsvTable.to_float(String(conversion["match2"]))
	var boost_unit := engine.data.param("param_charge_boost_per_judgment")
	var boost_max := engine.data.param("param_charge_boost_max")
	_ok("TC-C6 V-1 무개입 1매치 < 필러 임계", one_match < filler_threshold,
		"%f vs %f" % [one_match, filler_threshold])
	_ok("TC-C6 V-1 개입 경로 > 필러 임계", two_match + boost_unit * boost_max > filler_threshold,
		"%f vs %f" % [two_match + boost_unit * boost_max, filler_threshold])
	# 실주행 대조: 필러 상대 3매치 슬립스트림 추월 듀얼은 승리(스왑) 해야 한다
	var probe := _new_engine(31)
	probe.start_gp()
	_flatten_neighbors(probe)
	var opponent_id := _force_duel(probe, RaceTypes.DuelType.OVERTAKE)
	var rank_before := probe.player_position()
	probe.begin_turn()
	probe.spin()
	probe.provisional = _combo(RaceTypes.SYMBOL_SLIPSTREAM, 3, RaceTypes.SYMBOL_SLIPSTREAM)
	probe.confirm(0.0)
	_ok("TC-C6 3매치 추월 듀얼 승리 = 스왑", probe.player_position() == rank_before - 1,
		"before=P%d after=P%d opponent=%s" % [rank_before, probe.player_position(), opponent_id])
	# 패배 경로: 라인 1매치만으로는 임계 미달 → 스왑 없음 + 섀시 페널티
	var probe2 := _new_engine(31)
	probe2.start_gp()
	_flatten_neighbors(probe2)
	_force_duel(probe2, RaceTypes.DuelType.OVERTAKE)
	var rank_before2 := probe2.player_position()
	probe2.begin_turn()
	probe2.spin()
	probe2.provisional = [RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_BRAKING, RaceTypes.SYMBOL_BRAKING]
	var chassis_before := probe2.chassis
	probe2.confirm(0.0)
	_ok("TC-C6 임계 미달 = 스왑 없음", probe2.player_position() == rank_before2,
		"before=P%d after=P%d" % [rank_before2, probe2.player_position()])
	_eq_float("TC-C6 추월 실패 섀시 페널티", chassis_before - probe2.chassis,
		probe2.data.param("param_chassis_duel_fail_penalty"))


# ── TC-C7 배틀 게이지 — 매치 효과 + 속성/최종 랩 계수의 곱 적용 (D13 별첨A §1.2·§1.3) ──
func _tc_c7_gauge_coefficients() -> void:
	# MN-1 S1 = 스트레이트(게이지 계수 1.0) — 기준 측정
	var probe := _new_engine(51, "circuit_mn1")
	if probe == null:
		return
	probe.start_gp()
	_flatten_neighbors(probe)
	probe.begin_turn()
	probe.spin()
	probe.front_gauge = 0.0
	probe.provisional = _combo(RaceTypes.SYMBOL_SLIPSTREAM, 1, RaceTypes.SYMBOL_BRAKING)
	probe.confirm(0.0)
	var base_effect := CsvTable.to_float(String(probe.data.match_effects[RaceTypes.SYMBOL_SLIPSTREAM][1]["front_gauge"]))
	var expected := base_effect - _expected_front_resist(probe)
	_eq_float("TC-C7 스트레이트 섹터 전방 게이지", probe.front_gauge, expected)

	# MN-1 S4 = 배틀 존(주) + 스트레이트(부) → 게이지 계수 1.5 × 부속성 보정
	var probe2 := _new_engine(51, "circuit_mn1")
	probe2.start_gp()
	_flatten_neighbors(probe2)
	probe2.sector = 3          # 다음 begin_turn()에서 S4 진입
	probe2.begin_turn()
	_ok("TC-C7 S4 진입", probe2.sector == 4, "sector=%d" % probe2.sector)
	probe2.spin()
	probe2.front_gauge = 0.0
	probe2.provisional = _combo(RaceTypes.SYMBOL_SLIPSTREAM, 1, RaceTypes.SYMBOL_BRAKING)
	probe2.confirm(0.0)
	var battle_mult := CsvTable.to_float(String(probe2.data.sector_attr("attr_battle_zone")["gauge_mult"]), 1.0)
	var expected2 := (base_effect - _expected_front_resist(probe2)) * battle_mult
	_ok("TC-C7 배틀 존 게이지 계수 적용", probe2.front_gauge > probe.front_gauge,
		"battle=%f straight=%f" % [probe2.front_gauge, probe.front_gauge])
	_eq_float("TC-C7 배틀 존 게이지 = 기준 × 계수", probe2.front_gauge, expected2, 0.01)

	# 만충 임계 도달 시 듀얼 예약 (단계 ⑤ → ⑥)
	var probe3 := _new_engine(51, "circuit_mn1")
	probe3.start_gp()
	_flatten_neighbors(probe3)
	probe3.begin_turn()
	probe3.spin()
	probe3.front_gauge = probe3.data.param("param_gauge_full_threshold") - 1.0
	probe3.provisional = _combo(RaceTypes.SYMBOL_SLIPSTREAM, 3, RaceTypes.SYMBOL_SLIPSTREAM)
	probe3.confirm(0.0)
	_ok("TC-C7 만충 = 추월 듀얼 예약", probe3.pending_duel == RaceTypes.DuelType.OVERTAKE,
		"pending=%d front=%f" % [probe3.pending_duel, probe3.front_gauge])
	# 찬스 3매치 = 즉시 만충 → 듀얼 (D13 별첨A §1.2)
	var probe4 := _new_engine(51, "circuit_mn1")
	probe4.start_gp()
	_flatten_neighbors(probe4)
	probe4.begin_turn()
	probe4.spin()
	probe4.front_gauge = 0.0
	probe4.provisional = _combo(RaceTypes.SYMBOL_CHANCE, 3, RaceTypes.SYMBOL_CHANCE)
	probe4.confirm(0.0)
	_ok("TC-C7 찬스 3매치 = 즉시 듀얼", probe4.pending_duel == RaceTypes.DuelType.OVERTAKE,
		"pending=%d" % probe4.pending_duel)


# ── TC-C9 섀시 컨디션·리타이어 — 0 도달 = 리타이어 · 런 결과 반영 ──
func _tc_c9_chassis_retire() -> void:
	var engine := _new_engine(77)
	if engine == null:
		return
	engine.start_gp()
	_flatten_neighbors(engine)
	engine.begin_turn()
	engine.spin()
	engine.chassis = 1.0
	engine.provisional = _combo(RaceTypes.SYMBOL_TROUBLE, 3, RaceTypes.SYMBOL_TROUBLE)
	engine.confirm(0.0)
	_ok("TC-C9 섀시 0 = 리타이어", engine.finished and bool(engine.result.get("player_retired", false)),
		"finished=%s result=%s" % [str(engine.finished), str(engine.result)])
	_eq_float("TC-C9 섀시 하한 0", engine.chassis, 0.0)
	_ok("TC-C9 리타이어 시 포인트 0", int(engine.result.get("tour_points", -1)) == 0,
		"points=%s" % str(engine.result.get("tour_points")))
	_ok("TC-C9 상태 = RESULT", engine.gp_state == RaceTypes.GpState.RESULT, "state=%d" % engine.gp_state)
	# 해저드 속성 섹터는 트러블 소모를 가중한다 (MN-3 S2 = 해저드 · D13 별첨A §1.3 ×1.15)
	var flat := _new_engine(77, "circuit_mn1")
	flat.start_gp()
	_flatten_neighbors(flat)
	flat.begin_turn()
	flat.spin()
	flat.chassis = 100.0
	flat.provisional = _combo(RaceTypes.SYMBOL_TROUBLE, 1, RaceTypes.SYMBOL_LINE)
	flat.confirm(0.0)
	var hazard := _new_engine(77, "circuit_mn3")
	hazard.start_gp()
	_flatten_neighbors(hazard)
	hazard.sector = 1          # 다음 begin_turn()에서 S2(해저드) 진입
	hazard.begin_turn()
	hazard.spin()
	hazard.chassis = 100.0
	hazard.provisional = _combo(RaceTypes.SYMBOL_TROUBLE, 1, RaceTypes.SYMBOL_LINE)
	hazard.confirm(0.0)
	_ok("TC-C9 해저드 섹터 섀시 소모 가중", hazard.chassis < flat.chassis,
		"hazard=%f flat=%f" % [hazard.chassis, flat.chassis])
	# GP 간 이월 주입 (D05 §8 "자동 완전 회복 없다" — IMPL-078 해소).
	# 엔진은 주입 값을 소비만 한다 — 미주입(음수) = 최대치 개시로 기존 계약 불변.
	var carried := _new_engine(77)
	carried.chassis_carry_in = 55.0
	carried.start_gp()
	_eq_float("이월 주입 = 개시 섀시", carried.chassis, 55.0)
	var over := _new_engine(77)
	over.chassis_carry_in = 250.0
	over.start_gp()
	_eq_float("이월 상한 절단 (250→최대치)", over.chassis, over.data.param("param_chassis_max"))
	var fresh := _new_engine(77)
	fresh.start_gp()
	_eq_float("미주입 = 최대치 개시 (기존 계약)", fresh.chassis, fresh.data.param("param_chassis_max"))
	# 카 넘버 — D03 결정 로그 #13-③ 확정 8인분의 전사 대조 (총괄 회신 E-2)
	var expected_numbers := {"ai_lorentz": 1, "ai_maro": 2, "ai_diaz": 18, "ai_volkova": 81,
		"ai_holloway": 5, "ai_bianca": 51, "ai_sherwood": 24, "ai_jude": 77}
	for row in fresh.data.rivals:
		var rival_id := String(row["id"])
		_ok("D03 카 넘버 전사: %s" % rival_id,
			CsvTable.to_int(String(row["number"])) == int(expected_numbers.get(rival_id, -1)),
			"number=%s" % String(row["number"]))
	# 그리드 카 넘버 유일성 — 필러가 네임드 실넘버(24 등)와 겹치면 표기 층이 오식별한다
	var seen_numbers := {}
	var duplicate_numbers := 0
	for entrant_id in fresh.entrants:
		var entrant_number := int(fresh.entrants[entrant_id]["number"])
		if seen_numbers.has(entrant_number):
			duplicate_numbers += 1
		seen_numbers[entrant_number] = true
	_ok("그리드 카 넘버 유일", duplicate_numbers == 0, "dupes=%d" % duplicate_numbers)


# ── TC-C11 봉인 규칙 — 릴 정지 연출 완료 전 결과·결과 상관 신호 노출 0 (D02 §4 · D12 §6.3) ──
# 앞선 판정식은 항진명제였다: `info.get("events")`가 같은 배열의 **참조**를 돌려주므로
# 스핀이 events에 결과를 append해도 비교가 항상 true였다. 사본을 떠서 비교한다.
# 그리고 5경로(UI·로그·사운드·햅틱·디버그 오버레이) 중 엔진이 책임지는 축 —
# "결과가 어떤 공개 표면으로도 새지 않는가" — 를 속성 전수 스캔으로 검사한다.
func _tc_c11_seal() -> void:
	var engine := _new_engine(99)
	if engine == null:
		return
	engine.start_gp()
	var info := engine.begin_turn()
	_ok("TC-C11 스핀 전 전개 후보 공백", engine.get_provisional().is_empty(),
		"provisional=%s" % str(engine.get_provisional()))
	var events_before: Array = Array(info.get("events", [])).duplicate(true)
	_surface_before = _public_surface(engine)
	engine.spin()
	var events_after: Array = info.get("events", [])
	_ok("TC-C11 스핀이 이벤트를 발행하지 않음", events_after.size() == events_before.size(),
		"before=%d after=%d %s" % [events_before.size(), events_after.size(), str(events_after)])
	_ok("TC-C11 T1 이벤트에 결과 없음", not _leaks_symbol(events_before),
		str(events_before))
	_ok("TC-C11 스핀 후에도 T1 이벤트에 결과 없음", not _leaks_symbol(events_after),
		str(events_after))
	# 결과는 get_provisional() 단일 창구로만 나간다 — 다른 공개 표면에 실려 있으면 봉인 위반.
	var leaked := _leaking_properties(engine)
	_ok("TC-C11 결과가 실린 공개 표면 = provisional 단독", leaked.is_empty(),
		"leaked=%s" % str(leaked))
	# 스핀이 바꾼 공개 표면을 전수 비교한다. '심볼 id를 담았는가'만 보면 결과 상관 신호를
	# 다른 표기(연출 트리거 id 등)로 실어 보내는 경로가 통과한다 — 변경 자체를 화이트리스트로 막는다.
	var allowed_changes := ["provisional", "turn_phase", "phase_log"]
	var unexpected := _unexpected_surface_changes(engine, _surface_before, allowed_changes)
	_ok("TC-C11 스핀이 바꾼 공개 표면 = 화이트리스트 한정", unexpected.is_empty(),
		"changed=%s" % str(unexpected))
	_ok("TC-C11 확정 전 정산 로그 공백", engine.settle_log.is_empty(),
		"settle_log=%s" % str(engine.settle_log))
	var events: Array = engine.confirm(0.0)
	_ok("TC-C11 확정 후 정산 로그 생성", not engine.settle_log.is_empty())
	_ok("TC-C11 결과 이벤트는 T5 이후 페이즈", _all_events_after_spin(events), "events=%s" % str(events))
	# 릴 정지 전 구간에서 연출 등급(사운드·햅틱 축)이 발화하지 않는다
	var engine2 := _new_engine(99)
	engine2.start_gp()
	var info2 := engine2.begin_turn()
	engine2.spin()
	var all_events: Array = Array(info2.get("events", []))
	for event in all_events:
		_ok("TC-C11 정지 전 연출 채널 무발화",
			not String(event.get("key", "")).begins_with("grade."), str(event))


# 다수 스핀에 걸친 봉인 검사 (SEAL-C 계열). 단발 스핀 diff는 **희귀 분기에 숨은 누출**을
# 놓친다 — 3매치처럼 드문 결과에만 걸린 누출은 그 스핀에서 값이 변하지 않기 때문이다.
# 수백 회 돌려 "스핀이 바꾼 공개 표면 집합 ⊆ 화이트리스트"를 누적 판정한다.
func _seal_across_many_spins() -> void:
	var engine := _new_engine(4242)
	if engine == null:
		return
	engine.start_gp()
	_flatten_neighbors(engine)
	var allowed := ["provisional", "turn_phase", "phase_log"]
	var offenders: Dictionary = {}
	var three_match_seen := 0
	for attempt in range(400):
		if engine.finished:
			engine = _new_engine(4242 + attempt)
			engine.start_gp()
			_flatten_neighbors(engine)
		var info := engine.begin_turn()
		if String(info.get("type", "")) == "finished":
			continue
		var before := _public_surface(engine)
		engine.spin()
		var provisional := engine.get_provisional()
		if provisional.size() == 3 and provisional[0] == provisional[1] and provisional[1] == provisional[2]:
			three_match_seen += 1
		for name in _unexpected_surface_changes(engine, before, allowed):
			offenders[name] = int(offenders.get(name, 0)) + 1
		# 화이트리스트 **안**에 숨기는 경로도 막는다 — 허용 속성의 값 도메인까지 단언한다.
		# phase_log에 임의 값을 밀어 넣으면 변경 자체는 허용되므로 도메인 검사가 유일한 방어다.
		if engine.phase_log != [RaceTypes.TurnPhase.T1_SECTOR_OPEN,
			RaceTypes.TurnPhase.T2_SPIN, RaceTypes.TurnPhase.T3_PROVISIONAL,
			RaceTypes.TurnPhase.T4_INTERVENTION]:
			offenders["phase_log_domain"] = int(offenders.get("phase_log_domain", 0)) + 1
		for stage in engine.settle_log:
			if not RaceTypes.SETTLE_ORDER.has(stage):
				offenders["settle_log_domain"] = int(offenders.get("settle_log_domain", 0)) + 1
		engine.confirm(0.0)
	_ok("봉인: 3매치 분기 도달 (희귀 분기 표본 확보)", three_match_seen > 0,
		"three_match=%d" % three_match_seen)
	_ok("봉인: 다수 스핀에서도 화이트리스트 밖 변화 0", offenders.is_empty(),
		"offenders=%s" % str(offenders))


# 심볼 id가 이벤트 어딘가(키·파라미터)에 실려 있으면 결과 누출이다.
func _leaks_symbol(events: Array) -> bool:
	for event in events:
		if _contains_symbol_id(event):
			return true
	return false


# 엔진의 공개 표면 전수 스캔 — provisional 외의 속성에 심볼 id가 실려 있는지.
# 개별 필드를 열거하지 않는다: 새 필드가 추가될 때 검사가 자동으로 따라붙어야 한다.
func _leaking_properties(engine: RaceEngine) -> Array:
	var leaked: Array = []
	for property in engine.get_property_list():
		var name := String(property.get("name", ""))
		if name == "provisional" or name.begins_with("_") or name == "script":
			continue
		if int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		if _contains_symbol_id(engine.get(name)):
			leaked.append(name)
	return leaked


var _surface_before: Dictionary = {}


# 엔진의 공개 스크립트 변수 전체를 문자열 스냅샷으로 뜬다 (비교 목적 — 값 자체는 쓰지 않는다).
func _public_surface(engine: RaceEngine) -> Dictionary:
	var surface: Dictionary = {}
	for property in engine.get_property_list():
		var name := String(property.get("name", ""))
		# 밑줄 접두 필드도 본다 — 누출을 `_leak` 같은 이름에 담으면 검사가 비켜 간다.
		# GDScript의 밑줄은 관례이고 접근 제한이 아니므로 누출 경로로 성립한다.
		if name == "script":
			continue
		if int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		surface[name] = str(engine.get(name))
	return surface


func _unexpected_surface_changes(engine: RaceEngine, before: Dictionary, allowed: Array) -> Array:
	var changed: Array = []
	var after := _public_surface(engine)
	for name in after:
		if allowed.has(name):
			continue
		if not before.has(name) or String(before[name]) != String(after[name]):
			changed.append(name)
	return changed


func _contains_symbol_id(value: Variant) -> bool:
	match typeof(value):
		TYPE_STRING:
			var text := String(value)
			for symbol_id in [RaceTypes.SYMBOL_SLIPSTREAM, RaceTypes.SYMBOL_BRAKING,
					RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_PULSE,
					RaceTypes.SYMBOL_TROUBLE, RaceTypes.SYMBOL_CHANCE]:
				if text.contains(symbol_id):
					return true
			return false
		TYPE_ARRAY:
			for item in Array(value):
				if _contains_symbol_id(item):
					return true
			return false
		TYPE_DICTIONARY:
			for key in Dictionary(value):
				if _contains_symbol_id(key) or _contains_symbol_id(Dictionary(value)[key]):
					return true
			return false
	return false


func _all_events_after_spin(events: Array) -> bool:
	for event in events:
		var phase := String(event.get("phase", ""))
		if phase == "T1" or phase == "T2" or phase == "T3":
			return false
	return true


# ── TC-C12 RNG 스트림·스커밍 무효 — 릴 정지 직전 세이브 → 재로드 반복 시 결과 동일 ──
func _tc_c12_scumming() -> void:
	var engine := _new_engine(123)
	if engine == null:
		return
	engine.start_gp()
	# reel 스트림을 먼저 소비해 둔다. GP 개시 직후에 스냅샷을 뜨면 스트림이 시드 초기
	# 상태에 있어 "시드만 복원"해도 같은 결과가 나오고, 내부 상태 직렬화 누락을 놓친다.
	for warmup in range(3):
		engine.begin_turn()
		engine.spin()
		engine.provisional = _combo(RaceTypes.SYMBOL_PULSE, 3, RaceTypes.SYMBOL_PULSE)
		engine.confirm(0.0)
	engine.begin_turn()
	var snapshot := engine.serialize()      # 릴 정지 직전(스핀 전) 스냅샷
	engine.spin()
	var first_result := engine.get_provisional()
	for attempt in range(5):
		var replay := _new_engine(999)      # 다른 마스터 시드로 생성 후 스냅샷 복원
		if replay == null:
			return
		_ok("TC-C12 복원 성립", replay.restore(snapshot))
		replay.spin()
		_ok("TC-C12 재로드 결과 동일 (시도 %d)" % (attempt + 1),
			replay.get_provisional() == first_result,
			"replay=%s first=%s" % [str(replay.get_provisional()), str(first_result)])
	# 전 스트림이 직렬화 대상인지 (reserve 포함 — D12 §6.1)
	var payload := engine.serialize()
	var streams: Dictionary = payload["rng"]["streams"]
	for stream_name in RngService.STREAM_NAMES:
		_ok("TC-C12 스트림 직렬화 %s" % stream_name, streams.has(stream_name))


# ── 연출 등급 L0~L3 + GP당 상한 (D04 §5.5 · D08 §8.5 · D13 별첨A §8.1 · D12 §5.8) ──
# MS-1 유보분(IMPL-016)의 결선 검증. 상한 초과 = L1 강등 · 우선순위 소진 순서 고정.
func _presentation_grade_caps() -> void:
	var data := GameData.new()
	if not data.load_all():
		_failures += 1
		print("  [FAIL] data load")
		return
	# D08 §8.5 확정값 대조 (L2 = 2회 · L3 = 1회)
	_eq_float("D08 §8.5 L2 GP당 상한 2",
		CsvTable.to_float(String(data.presentation_grade("grade_l2")["gp_cap"])), 2.0)
	# "상한 0 = 무제한" 규약 — L0·L1이 0이 아니면 무제한 등급이 조용히 제한된다
	_eq_float("규약: L0 상한 0(무제한)",
		CsvTable.to_float(String(data.presentation_grade("grade_l0")["gp_cap"])), 0.0)
	_eq_float("규약: L1 상한 0(무제한)",
		CsvTable.to_float(String(data.presentation_grade("grade_l1")["gp_cap"])), 0.0)
	_eq_float("D08 §8.5 L3 GP당 상한 1",
		CsvTable.to_float(String(data.presentation_grade("grade_l3")["gp_cap"])), 1.0)
	# D13 별첨A §8.3 등급 스팅 길이
	_eq_float("D13 §8.3 L1 스팅 0.8초",
		CsvTable.to_float(String(data.presentation_grade("grade_l1")["sting_length_sec"])), 0.8)
	_eq_float("D13 §8.3 L2 스팅 1.5초",
		CsvTable.to_float(String(data.presentation_grade("grade_l2")["sting_length_sec"])), 1.5)
	_eq_float("D13 §8.3 L3 스팅 2.5초",
		CsvTable.to_float(String(data.presentation_grade("grade_l3")["sting_length_sec"])), 2.5)
	# 채널 구성 (D04 §5.5 · D11 §2.5): L0 로그만 → L1 +SFX·약햅틱 → L2 +강햅틱·플래시 → L3 +일러스트
	var l0 := PresentationGrade.new()
	l0.setup(data)
	var c0 := l0.channels("grade_l0")
	_ok("L0 = 로그만", bool(c0["log"]) and not bool(c0["sfx_sting"])
		and String(c0["haptic_level"]) == "none" and not bool(c0["flash_slow"]), str(c0))
	var c1 := l0.channels("grade_l1")
	_ok("L1 = 로그+SFX+약햅틱", bool(c1["sfx_sting"]) and String(c1["haptic_level"]) == "weak"
		and not bool(c1["flash_slow"]), str(c1))
	var c2 := l0.channels("grade_l2")
	_ok("L2 = +강햅틱·플래시", String(c2["haptic_level"]) == "strong" and bool(c2["flash_slow"])
		and not bool(c2["illustration"]), str(c2))
	var c3 := l0.channels("grade_l3")
	_ok("L3 = L2 + 전용 일러스트", bool(c3["illustration"]) and bool(c3["flash_slow"]), str(c3))
	# L2 상한 소진 후 3번째 후보는 L1로 강등된다
	var grade := PresentationGrade.new()
	grade.setup(data)
	for attempt in range(2):
		var granted := grade.resolve(["trigger_duel_decision"])
		_ok("L2 %d회차 발동" % (attempt + 1), String(granted[0]["grade"]) == "grade_l2", str(granted))
	var overflow := grade.resolve(["trigger_duel_decision"])
	_ok("L2 상한 초과 = L1 강등", String(overflow[0]["grade"]) == "grade_l1"
		and bool(overflow[0]["demoted"]), str(overflow))
	# L3는 독립 상한 1회 — L2 소진과 무관하게 1회는 성립한다
	var signature := grade.resolve(["trigger_signature_event"])
	_ok("L3 독립 상한 1회 성립", String(signature[0]["grade"]) == "grade_l3", str(signature))
	_ok("L3 상한 초과 = L1 강등",
		String(grade.resolve(["trigger_signature_event"])[0]["grade"]) == "grade_l1")
	# GP 경계에서 카운터가 되돌아간다 (상한은 '그랑프리당')
	grade.reset_gp()
	_ok("GP 경계 카운터 리셋", String(grade.resolve(["trigger_duel_decision"])[0]["grade"]) == "grade_l2")
	# 우선순위 소진 (D08 §8.5): 듀얼 결판 > 벽 라이벌 비트 > 찬스 3매치.
	# 후보 3건이 같은 턴에 서고 슬롯이 2개면, 찬스 3매치가 강등돼야 한다.
	var priority := PresentationGrade.new()
	priority.setup(data)
	var resolved := priority.resolve([
		"trigger_chance_three_match", "trigger_wall_rival_beat", "trigger_duel_decision",
	])
	_ok("우선순위 정렬 = 듀얼 결판 우선", String(resolved[0]["trigger"]) == "trigger_duel_decision",
		str(resolved))
	_ok("우선순위 2번째 = 벽 라이벌", String(resolved[1]["trigger"]) == "trigger_wall_rival_beat")
	_ok("슬롯 2개 소진 후 찬스 3매치 강등",
		String(resolved[2]["trigger"]) == "trigger_chance_three_match"
		and String(resolved[2]["grade"]) == "grade_l1" and bool(resolved[2]["demoted"]), str(resolved))
	_ok("연출 등급 조회 중 데이터 침묵 기본값 0", data.is_ok())
	# L3 조우 판정 (D10 §7 결정 #6 — CG-01 왕좌/로렌츠). 시즌 최종 무대(펄스 돔)의 벽 라이벌
	# 듀얼 결판에서만 선다. 무대 5는 실기로 밟기 어려운 경로라 조건식 자체를 못박는다.
	var race_screen_script: GDScript = load("res://ui/race/race_screen.gd")
	var final_stage_id := String(data.season_calendar.get("fixed_final_stage", ""))
	var final_stage: Dictionary = data.stages[final_stage_id]
	var wall_rival := String(final_stage.get("wall_rival", ""))
	_ok("시즌 최종 무대 벽 = 로렌츠 (D08 §5.1 이중 고정)", wall_rival == "ai_lorentz", wall_rival)
	_ok("CG-01 = 최종 무대 벽 듀얼 결판",
		String(race_screen_script.l3_encounter_for(final_stage, final_stage_id, wall_rival, true))
		== "cg_01_throne")
	_ok("듀얼 결판 아니면 미성립",
		String(race_screen_script.l3_encounter_for(final_stage, final_stage_id, wall_rival, false)).is_empty())
	_ok("벽 아닌 상대면 미성립",
		String(race_screen_script.l3_encounter_for(final_stage, final_stage_id, "ai_jude", true)).is_empty())
	# **비공허성 확보:** 무벽 무대(메트로)로 대조하면 `wall.is_empty()` 가드가 먼저 걸려
	# 최종 무대 조건이 무검증으로 남는다(돌연변이 실측 — 조건 삭제가 통과했다).
	# 벽이 **있는** 비최종 무대 + 그 무대의 벽을 상대로 둬야 최종 무대 축만 갈린다.
	var mid_stage: Dictionary = data.stages["stage_azure_coast"]
	var mid_wall := String(mid_stage.get("wall_rival", ""))
	_ok("대조 무대에 벽 존재 (검사 비공허)", not mid_wall.is_empty() and mid_wall != wall_rival, mid_wall)
	_ok("최종 무대 아니면 미성립 (벽 듀얼이어도)",
		String(race_screen_script.l3_encounter_for(mid_stage, final_stage_id, mid_wall, true)).is_empty())
	# CG-03(동기 — 주드): 역전 래치 성립 후 최초의 인접 듀얼 (총괄 판정 IMPL-128 B-2).
	# 인접 임계는 D13 별첨A §6.5 확정값의 데이터 전사 — 코드에 2를 적지 않는다(불변규칙 2).
	var adjacent_max := int(data.param("param_jude_adjacent_max"))
	_ok("D13 §6.5 주드 인접 임계 = 2", adjacent_max == 2, str(adjacent_max))
	_ok("CG-03 = 래치 + 주드 + 인접",
		String(race_screen_script.l3_kinship_for("ai_jude", true, adjacent_max, adjacent_max))
		== "cg_03_kinship")
	_ok("인접 초과면 미성립",
		String(race_screen_script.l3_kinship_for("ai_jude", true, adjacent_max + 1, adjacent_max)).is_empty())
	_ok("역전 래치 전이면 미성립 (인접이어도)",
		String(race_screen_script.l3_kinship_for("ai_jude", false, 0, adjacent_max)).is_empty())
	_ok("상대가 주드가 아니면 미성립",
		String(race_screen_script.l3_kinship_for("ai_lorentz", true, 0, adjacent_max)).is_empty())
	# 순위표 미등재(무득점 초반)의 99 가 인접으로 새지 않는가 — `_jude_rank_delta` 의 큰 값 규약
	_ok("순위표 미등재(99)는 인접 아님",
		String(race_screen_script.l3_kinship_for("ai_jude", true, 99, adjacent_max)).is_empty())


# ── TL-5 ③ 모멘텀 × 개입 4타입 상호작용 매트릭스 (D14 §8.3 ③) ──
#
# 판정 = **정의 외 상호작용(의도치 않은 중첩·소거) 0.** 개입을 썼다는 이유로 모멘텀 보너스가
# 사라지거나 두 번 붙으면 안 된다. 개입 4타입 = D05 §6.1 확정(홀드·변환·증폭·보험).
#
# 방법: 같은 시드·같은 행동열로 엔진 두 대를 몰고 **`confirm()`의 잔여 비율만** 다르게 준다.
# 개입이 소비하는 난수도 양쪽이 동일하므로, 두 결과의 차이는 모멘텀 항 하나뿐이어야 한다.
func _momentum_interrupt_matrix() -> void:
	var bonus := 0.0
	# ① 무개입 기준선 — 이후 전 타입이 이 델타와 같아야 한다
	var base_delta := _momentum_delta("none")
	var probe := _new_engine(4242)
	if probe == null:
		return
	bonus = probe.data.param("param_gauge_momentum_bonus")
	_eq_float("무개입 모멘텀 델타 = D13 §2.1 기준값", base_delta, bonus)
	# ② 홀드 (Hold — 릴 고정 + 재회전. 기본 개입·상시 가용)
	_eq_float("홀드 개입 후에도 모멘텀 델타 불변", _momentum_delta("hold"), bonus)
	# ③ 보험 (Insure — 차지 개입 트러블 무효화)
	_eq_float("보험 개입 후에도 모멘텀 델타 불변", _momentum_delta("negate"), bonus)
	# ④ 홀드+보험 동시 — 개입을 겹쳐도 보너스는 한 번이다 (중첩 0)
	_eq_float("홀드+보험 중첩에도 모멘텀 1회분", _momentum_delta("hold_negate"), bonus)
	# ⑤ 발화 계수 — 모멘텀 로그는 성립 턴에 정확히 1회, 미성립 턴에 0회
	_ok("모멘텀 로그 성립 시 1회", _momentum_event_count("hold", 1.0) == 1)
	_ok("모멘텀 로그 미성립 시 0회", _momentum_event_count("hold", 0.0) == 0)
	# ⑥ 증폭 (Amplify — 듀얼 부스트): **모멘텀과 구조적으로 배타**다.
	# 모멘텀은 `not current_turn_is_duel` 전속이고 부스트는 듀얼 턴 전속이라 같은 턴에 설 수 없다.
	# 배타는 '정의 외 상호작용'이 아니라 정의된 비상호작용이므로, 그 사실 자체를 못박는다.
	var duel := _new_engine(4343)
	if duel == null:
		return
	duel.start_gp()
	_flatten_neighbors(duel)
	duel.begin_turn()
	duel.current_turn_is_duel = true
	duel.spin()
	duel.charge = 4
	var boost_result: Dictionary = duel.add_duel_boost()
	_ok("듀얼 턴에서 증폭 개입 성립", bool(boost_result.get("ok", false)), str(boost_result))
	var duel_events: Array = duel.confirm(1.0)
	var duel_momentum := 0
	for event in duel_events:
		if String(event.get("key", "")) == "raceLog.momentum01":
			duel_momentum += 1
	_ok("듀얼 턴은 여유 확정이어도 모멘텀 0 (구조적 배타)", duel_momentum == 0, str(duel_momentum))
	var sector_probe := _new_engine(4343)
	if sector_probe != null:
		sector_probe.start_gp()
		sector_probe.begin_turn()
		sector_probe.spin()
		sector_probe.charge = 4
		# 비듀얼 턴에서는 증폭 개입 자체가 거부된다 — 배타의 반대 방향
		_ok("비듀얼 턴에서 증폭 개입 거부",
			not bool(sector_probe.add_duel_boost().get("ok", false)))
	# ⑦ 변환 (Convert — 심볼 교체·승급): **인게임 소비부가 없다.**
	# D05 §6.1은 변환을 스킬 데이터 인스턴스로 규정하는데 RACE-01 스킬 슬롯이 전 슬롯 잠금이라
	# (IMPL-071) 주입할 개입이 존재하지 않는다 — 매트릭스 4행 중 1행은 **미측정**이며 보고 대상이다.
	_ok("변환 개입 = 엔진 API 부재 (매트릭스 미측정 행)",
		not probe.has_method("convert_symbol"))


# 지정 개입을 넣고 여유 확정 / 즉시 확정의 전방 게이지 차를 낸다.
func _momentum_delta(interrupt: String) -> float:
	var on := _momentum_run(interrupt, 1.0)
	var off := _momentum_run(interrupt, 0.0)
	return on - off


func _momentum_run(interrupt: String, remaining_ratio: float) -> float:
	var engine := _momentum_engine(interrupt)
	if engine == null:
		return 0.0
	engine.confirm(remaining_ratio)
	return engine.front_gauge


func _momentum_event_count(interrupt: String, remaining_ratio: float) -> int:
	var engine := _momentum_engine(interrupt)
	if engine == null:
		return -1
	var count := 0
	for event in engine.confirm(remaining_ratio):
		if String(event.get("key", "")) == "raceLog.momentum01":
			count += 1
	return count


# 개입까지 마친 T4 상태의 엔진 — 시드·행동열이 같으므로 난수 소비도 같다.
func _momentum_engine(interrupt: String) -> RaceEngine:
	var engine := _new_engine(4242)
	if engine == null:
		return null
	engine.start_gp()
	_flatten_neighbors(engine)
	engine.begin_turn()
	engine.spin()
	engine.front_gauge = 0.0
	engine.charge = 9
	# 보험은 트러블이 있어야 성립한다 — 라인 2 + 트러블 1 조합으로 고정
	engine.provisional = [RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_TROUBLE]
	match interrupt:
		"hold":
			engine.hold_respin([0, 1])
		"negate":
			engine.negate_trouble()
		"hold_negate":
			engine.hold_respin([0, 1, 2])   # 전 릴 고정 = 재회전 0 (조합 보존)
			engine.negate_trouble()
	return engine


# ── 섹터 속성 6축 가중 — 릴 분포 대조 (D13 별첨A §1.3 · D08 별첨A §1) ──
# 독립 검증에서 이 축이 전량 무검증으로 드러났다: 주속성 Δ를 통째로 빼도, 계수 부호를
# 반전해도, 섹터 속성 배정을 바꿔도 4스위트가 통과했다. 여기서 닫는다.
func _sector_attribute_weights() -> void:
	var engine := _new_engine(101, "circuit_mn1")
	if engine == null:
		return
	var data := engine.data
	# 기대 가중 = 기본 분포 + 주속성 Δ + 부속성 Δ/2 (음수 절단). 재정규화는 추첨 시점 소관.
	for circuit_id in _d08_expected_layout():
		var probe := _new_engine(101, circuit_id)
		if probe == null:
			return
		for slot in range(1, probe.data.circuit_int("sectors_per_lap") + 1):
			probe.sector = slot
			var entry := probe.data.sector_entry(slot)
			var main_attr := probe.data.sector_attr(String(entry["main_attr"]))
			var sub_attr := probe.data.sector_attr(String(entry.get("sub_attr", "")))
			var actual: Array = probe.reel_weights(0)
			for index in range(probe.data.symbols.size()):
				var row: Dictionary = probe.data.symbols[index]
				var column := "w_%s" % String(row["class"])
				var expected := CsvTable.to_float(String(row["prob_reel1"]))
				if not main_attr.is_empty():
					expected += CsvTable.to_float(String(main_attr[column]))
				if not sub_attr.is_empty():
					expected += CsvTable.to_float(String(sub_attr[column])) * 0.5
				_eq_float("%s s%d %s 가중" % [circuit_id, slot, String(row["id"])],
					float(actual[index]), maxf(expected, 0.0), 0.0001)
	# 속성 배정이 D08 별첨A §1~§5 표와 일치하는지 (배정 변조 = 서킷 정체성 변조)
	var expected_layout := _d08_expected_layout()
	for circuit_id in expected_layout:
		var probe2 := _new_engine(101, circuit_id)
		if probe2 == null:
			return
		var expected_sectors: Array = expected_layout[circuit_id]
		_ok("D08 별첨A %s 섹터 수" % circuit_id,
			probe2.data.circuit_int("sectors_per_lap") == expected_sectors.size(),
			"actual=%d" % probe2.data.circuit_int("sectors_per_lap"))
		for slot in range(1, expected_sectors.size() + 1):
			var entry2 := probe2.data.sector_entry(slot)
			var expected_pair: Array = expected_sectors[slot - 1]
			_ok("D08 별첨A %s s%d 주속성" % [circuit_id, slot],
				String(entry2["main_attr"]) == String(expected_pair[0]),
				"actual=%s expected=%s" % [entry2["main_attr"], expected_pair[0]])
			_ok("D08 별첨A %s s%d 부속성" % [circuit_id, slot],
				String(entry2.get("sub_attr", "")) == String(expected_pair[1]),
				"actual=%s expected=%s" % [entry2.get("sub_attr", ""), expected_pair[1]])
		# 펄스 섹션은 무대 제3전(빌드B)에만 (D08 별첨A §0 공통 규칙 ④)
		var build_b_circuits := ["circuit_mn3", "circuit_ac3", "circuit_ar3", "circuit_mf3", "circuit_pd3"]
		var has_pulse := false
		for slot2 in range(1, probe2.data.circuit_int("sectors_per_lap") + 1):
			if String(probe2.data.sector_entry(slot2)["main_attr"]) == "attr_pulse_section":
				has_pulse = true
		_ok("D08 별첨A 펄스 섹션 배치 = 제3전 전속 (%s)" % circuit_id,
			has_pulse == build_b_circuits.has(circuit_id), "has_pulse=%s" % str(has_pulse))
		# 서킷당 배틀 존 최소 1 (D08 별첨A §0 공통 규칙 ③)
		var battle_zones := 0
		for slot3 in range(1, probe2.data.circuit_int("sectors_per_lap") + 1):
			var entry3 := probe2.data.sector_entry(slot3)
			if String(entry3["main_attr"]) == "attr_battle_zone" \
				or String(entry3.get("sub_attr", "")) == "attr_battle_zone":
				battle_zones += 1
		_ok("D08 별첨A 배틀 존 최소 1 (%s)" % circuit_id, battle_zones >= 1,
			"count=%d" % battle_zones)
	# ×1.8 상한 (D13 별첨A §1.3 명문) — 전 서킷 전 섹터 × 최종 랩
	for circuit_id in expected_layout:
		var probe3 := _new_engine(101, circuit_id)
		if probe3 == null:
			return
		probe3.start_gp()
		probe3.lap = probe3.data.circuit_int("laps")   # 최종 랩 = 계수 최대
		for slot4 in range(1, probe3.data.circuit_int("sectors_per_lap") + 1):
			probe3.sector = slot4
			_ok("%s s%d 게이지 계수 ≤ 1.8" % [circuit_id, slot4], probe3._gauge_mult() <= 1.8 + 0.0001,
				"mult=%f" % probe3._gauge_mult())
	# 슬롯 구성 (D08 §4.3): 무대별 4서킷 = 오프너(4)/빌드A(5)/빌드B(4)/피니셔(5) + 무대 결속 (§2.3)
	var role_order := ["opener", "build_a", "build_b", "finisher"]
	var role_sectors := {"opener": 4, "build_a": 5, "build_b": 4, "finisher": 5}
	for stage_id in data.stages:
		var stage_circuits: Array = data.stages[stage_id].get("circuits", [])
		_ok("D08 §4.3 %s 서킷 4종" % stage_id, stage_circuits.size() == 4, str(stage_circuits))
		for index in range(stage_circuits.size()):
			var circuit_id2 := String(stage_circuits[index])
			var member: Dictionary = data.circuits.get(circuit_id2, {})
			_ok("D08 §4.3 %s 슬롯 역할" % circuit_id2,
				String(member.get("tour_slot_role", "")) == String(role_order[index]),
				"actual=%s expected=%s" % [member.get("tour_slot_role"), role_order[index]])
			_ok("D08 §4.3 %s 섹터 수(역할 표준)" % circuit_id2,
				int(member.get("sectors_per_lap", -1)) == int(role_sectors[role_order[index]]),
				"actual=%d" % int(member.get("sectors_per_lap", -1)))
			_ok("D08 §2.3 무대 결속: %s.stage_id" % circuit_id2,
				String(member.get("stage_id", "")) == stage_id, str(member.get("stage_id")))


# ── GP 요약 계수 (D07 §6.2 통산 지표 · D08 §8.11 업적 판정 소재 — T4 결선) ──
# 엔진은 세기만 한다. 업적 규칙은 아웃게임 층 소관이며 여기서는 계수의 정확성만 본다.
func _gp_summary_counters() -> void:
	var engine := _new_engine(505, "circuit_mn1")
	if engine == null:
		return
	engine.start_gp()
	_flatten_neighbors(engine)
	_ok("GP 개시 = 요약 계수 0", engine.duel_wins == 0 and engine.trouble_turns == 0
		and engine.hold_uses == 0 and engine.chance_three_matches == 0
		and engine.final_lap_entry_rank == 0)
	# 트러블 발화 턴 계수 — 발화한 턴만 센다 (심볼 수가 아니라 턴 수)
	engine.begin_turn()
	engine.spin()
	engine.provisional = _combo(RaceTypes.SYMBOL_TROUBLE, 2, RaceTypes.SYMBOL_LINE)
	engine.confirm(0.0)
	_ok("트러블 턴 1 (2심볼 = 1턴)", engine.trouble_turns == 1, "actual=%d" % engine.trouble_turns)
	engine.begin_turn()
	engine.spin()
	engine.provisional = _combo(RaceTypes.SYMBOL_LINE, 3, RaceTypes.SYMBOL_LINE)
	engine.confirm(0.0)
	_ok("무트러블 턴은 계수 불변", engine.trouble_turns == 1, "actual=%d" % engine.trouble_turns)
	# 찬스 3매치 계수
	var chancer := _new_engine(506, "circuit_mn1")
	chancer.start_gp()
	_flatten_neighbors(chancer)
	chancer.begin_turn()
	chancer.spin()
	chancer.provisional = _combo(RaceTypes.SYMBOL_CHANCE, 3, RaceTypes.SYMBOL_CHANCE)
	chancer.confirm(0.0)
	_ok("찬스 3매치 계수 1", chancer.chance_three_matches == 1,
		"actual=%d" % chancer.chance_three_matches)
	# 홀드 사용 계수 — 개입 창에서만 성립하므로 차지를 채워 실행한다
	var holder := _new_engine(507, "circuit_mn1")
	holder.start_gp()
	_flatten_neighbors(holder)
	holder.begin_turn()
	holder.spin()
	holder.charge = holder.data.param_int("param_charge_cap")
	var hold_result := holder.hold_respin([0])
	_ok("홀드 실행 성립", bool(hold_result.get("ok", false)), str(hold_result))
	_ok("홀드 사용 계수 1", holder.hold_uses == 1, "actual=%d" % holder.hold_uses)
	# 듀얼 승수 계수 — 확정 승리 조합으로 1회 성립시킨다
	var duelist := _new_engine(508, "circuit_mn1")
	duelist.start_gp()
	_flatten_neighbors(duelist)
	_force_duel(duelist, RaceTypes.DuelType.OVERTAKE)
	duelist.begin_turn()
	duelist.spin()
	duelist.provisional = _combo(RaceTypes.SYMBOL_CHANCE, 3, RaceTypes.SYMBOL_CHANCE)
	duelist.confirm(0.0)
	_ok("듀얼 승수 계수 1", duelist.duel_wins == 1, "actual=%d" % duelist.duel_wins)
	# 최종 랩 진입 순위 — 랩 경계에서 1회 기록 (역전 우승 판정 소재)
	var runner := _new_engine(509, "circuit_mn1")
	runner.start_gp()
	_flatten_neighbors(runner)
	var laps := runner.data.circuit_int("laps")
	var sectors := runner.data.circuit_int("sectors_per_lap")
	# 듀얼 삽입으로 턴 수가 늘 수 있어 종료 신호까지 돈다 (상한은 무한 루프 방지용)
	var guard := (laps * sectors) * 3 + 4
	while not runner.finished and guard > 0:
		guard -= 1
		var info := runner.begin_turn()
		if String(info.get("type", "")) == "finished":
			break
		if runner.lap < laps:
			_ok("최종 랩 이전 = 미기록", runner.final_lap_entry_rank == 0,
				"lap=%d rank=%d" % [runner.lap, runner.final_lap_entry_rank])
		runner.spin()
		runner.provisional = _combo(RaceTypes.SYMBOL_LINE, 3, RaceTypes.SYMBOL_LINE)
		runner.confirm(0.0)
	_ok("GP 종료 도달", runner.finished, "guard=%d state=%d" % [guard, runner.gp_state])
	_ok("최종 랩 진입 순위 기록", runner.final_lap_entry_rank > 0,
		"actual=%d" % runner.final_lap_entry_rank)
	# GP 결과에 요약이 실린다 (아웃게임 판정의 입력)
	_ok("결과에 요약 편입", runner.result.has("duel_wins") and runner.result.has("trouble_turns")
		and runner.result.has("hold_uses") and runner.result.has("chance_three_matches")
		and runner.result.has("final_lap_entry_rank") and runner.result.has("circuit_id"),
		str(runner.result.keys()))
	_ok("결과 서킷 id = 활성 서킷", String(runner.result.get("circuit_id", "")) == "circuit_mn1",
		str(runner.result.get("circuit_id")))
	# 직렬화 왕복 — 요약 계수 보존 (GP 도중 재로드가 업적 판정을 갉아먹으면 안 된다)
	var snapshot := chancer.serialize()
	var revived := _new_engine(510, "circuit_mn1")
	_ok("요약 계수 복원 성립", revived.restore(snapshot))
	_ok("복원: 찬스 3매치 계수", revived.chance_three_matches == chancer.chance_three_matches,
		"actual=%d" % revived.chance_three_matches)
	snapshot.erase("chance_three_matches")
	snapshot.erase("hold_uses")
	var legacy := _new_engine(511, "circuit_mn1")
	_ok("구스냅샷 복원 성립", legacy.restore(snapshot))
	_ok("구스냅샷 = 계수 0", legacy.chance_three_matches == 0 and legacy.hold_uses == 0)


# D08 별첨A §1~§5 섹터 배치표 전사 (서킷 20종 전수) — 검사 기대값의 유일 정본.
# 자기 일관성 금지 (검증 프로토콜 §2-①): 여기 값은 데이터가 아니라 문서에서 옮겼다.
func _d08_expected_layout() -> Dictionary:
	return {
		"circuit_mn1": [["attr_straight", ""], ["attr_technical", ""], ["attr_sweeper", ""],
			["attr_battle_zone", "attr_straight"]],
		"circuit_mn2": [["attr_straight", ""], ["attr_sweeper", ""], ["attr_technical", ""],
			["attr_straight", "attr_battle_zone"], ["attr_battle_zone", ""]],
		"circuit_mn3": [["attr_technical", ""], ["attr_hazard", "attr_technical"],
			["attr_pulse_section", ""], ["attr_technical", "attr_battle_zone"]],
		"circuit_mn4": [["attr_straight", ""], ["attr_sweeper", ""], ["attr_technical", ""],
			["attr_hazard", "attr_technical"], ["attr_battle_zone", "attr_straight"]],
		"circuit_ac1": [["attr_straight", ""], ["attr_sweeper", ""],
			["attr_straight", "attr_battle_zone"], ["attr_battle_zone", ""]],
		"circuit_ac2": [["attr_straight", ""], ["attr_sweeper", ""], ["attr_hazard", ""],
			["attr_straight", ""], ["attr_battle_zone", "attr_sweeper"]],
		"circuit_ac3": [["attr_technical", ""], ["attr_straight", ""],
			["attr_pulse_section", ""], ["attr_sweeper", "attr_battle_zone"]],
		"circuit_ac4": [["attr_straight", ""], ["attr_sweeper", ""], ["attr_technical", ""],
			["attr_hazard", "attr_straight"], ["attr_battle_zone", ""]],
		"circuit_ar1": [["attr_sweeper", ""], ["attr_technical", ""],
			["attr_technical", "attr_hazard"], ["attr_battle_zone", ""]],
		"circuit_ar2": [["attr_technical", ""], ["attr_technical", ""], ["attr_hazard", ""],
			["attr_sweeper", ""], ["attr_battle_zone", "attr_technical"]],
		"circuit_ar3": [["attr_sweeper", ""], ["attr_hazard", ""],
			["attr_pulse_section", ""], ["attr_technical", "attr_battle_zone"]],
		"circuit_ar4": [["attr_technical", ""], ["attr_sweeper", ""], ["attr_hazard", ""],
			["attr_technical", ""], ["attr_battle_zone", "attr_hazard"]],
		"circuit_mf1": [["attr_straight", ""], ["attr_hazard", ""], ["attr_sweeper", ""],
			["attr_battle_zone", ""]],
		"circuit_mf2": [["attr_straight", ""], ["attr_straight", "attr_battle_zone"],
			["attr_hazard", ""], ["attr_sweeper", ""], ["attr_battle_zone", ""]],
		"circuit_mf3": [["attr_technical", ""], ["attr_hazard", "attr_technical"],
			["attr_pulse_section", ""], ["attr_sweeper", "attr_battle_zone"]],
		"circuit_mf4": [["attr_straight", ""], ["attr_hazard", ""], ["attr_technical", ""],
			["attr_sweeper", "attr_hazard"], ["attr_battle_zone", ""]],
		"circuit_pd1": [["attr_straight", ""], ["attr_battle_zone", ""], ["attr_sweeper", ""],
			["attr_battle_zone", "attr_straight"]],
		"circuit_pd2": [["attr_straight", ""], ["attr_sweeper", ""],
			["attr_straight", "attr_battle_zone"], ["attr_sweeper", ""], ["attr_battle_zone", ""]],
		"circuit_pd3": [["attr_technical", ""], ["attr_hazard", ""],
			["attr_pulse_section", ""], ["attr_technical", "attr_battle_zone"]],
		"circuit_pd4": [["attr_straight", ""], ["attr_technical", ""], ["attr_sweeper", ""],
			["attr_hazard", "attr_technical"], ["attr_battle_zone", ""]],
	}


# ── 벽 라이벌 결선 (D08 §5.1 ① · D13 별첨A §2.4·§6.2) ──
# MS-2(무벽 메트로)에서는 전 경로 잠복이었다 — 무대 2~5 유입과 함께 소비부 3종을 검증한다.
func _wall_rival_wired() -> void:
	# 페이스 가중 (D13 §6.2 벽 무대 가중 행 전사): 벽 서킷 vs 무벽 서킷(mn1)의 pace 차 = 가중치.
	# form은 pace에 합산되지 않는 별도 필드라 시드 차이의 영향이 없다.
	var wall_adds := {
		"circuit_ac1": ["ai_diaz", 1.4], "circuit_ar1": ["ai_sherwood", 1.9],
		"circuit_mf1": ["ai_holloway", 1.4], "circuit_pd1": ["ai_lorentz", 1.0],
	}
	var off_wall := _new_engine(303, "circuit_mn1")
	if off_wall == null:
		return
	off_wall.start_gp()
	for circuit_id in wall_adds:
		var rival_id := String(Array(wall_adds[circuit_id])[0])
		var expected_add := float(Array(wall_adds[circuit_id])[1])
		var on_wall := _new_engine(303, circuit_id)
		on_wall.start_gp()
		_eq_float("D13 §6.2 벽 페이스 가중: %s(%s) +%.1f" % [rival_id, circuit_id, expected_add],
			float(on_wall.entrants[rival_id]["pace"]) - float(off_wall.entrants[rival_id]["pace"]),
			expected_add)
		# 가중은 벽 전속 — 비벽 라이벌(마로)은 무대가 바뀌어도 페이스 불변
		_eq_float("벽 가중은 벽 전속 (%s에서 마로 Δ0)" % circuit_id,
			float(on_wall.entrants["ai_maro"]["pace"]) - float(off_wall.entrants["ai_maro"]["pace"]), 0.0)
		# 듀얼 임계 +6 (D13 §2.4 "벽 라이벌 (해당 무대) +6" — 추월·방어 공통)
		_eq_float("D13 §2.4 벽 추월 임계 +6 (%s)" % rival_id,
			on_wall._duel_threshold(RaceTypes.DuelType.OVERTAKE, rival_id)
				- off_wall._duel_threshold(RaceTypes.DuelType.OVERTAKE, rival_id), 6.0)
		_eq_float("D13 §2.4 벽 방어 임계 +6 (%s)" % rival_id,
			on_wall._duel_threshold(RaceTypes.DuelType.DEFENSE, rival_id)
				- off_wall._duel_threshold(RaceTypes.DuelType.DEFENSE, rival_id), 6.0)
	# 무벽 무대에서는 가산 없음 — 임계가 §2.4 기본 산식 그대로인지 대조 (디아스 방어 45+무벽0)
	var base_defense := off_wall.data.param("param_duel_defense_base") \
		+ float(off_wall.entrants["ai_diaz"]["seed_aggression"]) \
		* off_wall.data.param("param_duel_defense_aggression_coef")
	_eq_float("무벽 무대 임계 = 기본 산식 (디아스)",
		off_wall._duel_threshold(RaceTypes.DuelType.DEFENSE, "ai_diaz"), base_defense)
	# 로렌츠 방어 override(55)에도 +6 [가안 — §2.4 벽 행은 독립 가산 행, 면제 문면 없음]
	var dome := _new_engine(303, "circuit_pd1")
	dome.start_gp()
	_eq_float("D13 §2.4 로렌츠 방어 55 + 벽 6 (펄스 돔)",
		dome._duel_threshold(RaceTypes.DuelType.DEFENSE, "ai_lorentz"), 61.0)
	# AI 리타이어 벽 면제 (D13 §6.2 "벽 라이벌 제외") — 확률 경로라 표본을 강제 확보한다
	# (검증 프로토콜 §1-5: 단발 시행 금지 · 표본 확보 자체를 별도 단언으로).
	var probe := _new_engine(304, "circuit_ac1")
	probe.start_gp()
	var trials := 3000
	for i in range(trials):
		probe.ai_retire_count = 0   # GP 상한을 매 회 초기화 — 순수 개체 판정만 표본화
		probe._ai_retire_check()
	var retired_others := 0
	for entrant_id in probe.entrants:
		if entrant_id != RaceEngine.PLAYER_ID and bool(probe.entrants[entrant_id]["retired"]):
			retired_others += 1
	_ok("리타이어 표본 확보 (%d회 시행)" % trials, retired_others >= 5, "retired=%d" % retired_others)
	_ok("D13 §6.2 벽 라이벌 리타이어 면제 (디아스·아주르)",
		not bool(probe.entrants["ai_diaz"]["retired"]), str(probe.entrants["ai_diaz"]["retired"]))


# ── 소모품 사용 경로 (D06 §3.5 · D07 §3.1 · D13 §3.6 — T2 결선) ──
# 효과 = 회복·완화 전용 (R3) · 사용 지점 = T1 섹터 개시 전속 (R-B) · 반입/이월 = R5.
func _consumable_paths() -> void:
	var probe := _new_engine(404, "circuit_mn1")
	if probe == null:
		return
	var data := probe.data
	# D13 §3.6 전사 대조 — 단가·효과·값 (수치의 유일 창구 = D13)
	var expected_items := {
		"consumable_p1": ["chassis_restore", 250.0, 15.0],
		"consumable_p2": ["chassis_restore_and_shield", 320.0, 8.0],
		"consumable_p3": ["chassis_wear_ratio", 400.0, -0.20],
	}
	for item_id in expected_items:
		var row: Dictionary = data.consumables.get(item_id, {})
		var spec: Array = expected_items[item_id]
		_ok("D13 §3.6 %s 효과 축" % item_id, String(row.get("effect", "")) == String(spec[0]),
			str(row.get("effect")))
		_eq_float("D13 §3.6 %s 단가" % item_id, CsvTable.to_float(String(row.get("cost_cr", "-1"))), float(spec[1]))
		_eq_float("D13 §3.6 %s 효과값" % item_id, CsvTable.to_float(String(row.get("effect_value", "0"))), float(spec[2]))
	_eq_float("D13 §3.6 P2 트러블 반감 계수 0.5", data.param("param_consumable_shield_mult"), 0.5)
	# R4 프리미엄 검증 (D13 §3.6 문면: P1 16.7 Cr/CH vs 필드 정비 1회차 6.7 Cr/CH = 2.5배)
	var p1_rate := 250.0 / 15.0
	var repair_rate := data.param("param_repair_base_cr") / data.param("param_repair_field_cap")
	_eq_float("D13 §3.6 R4 프리미엄 2.5배", p1_rate / repair_rate, 2.5, 0.01)
	_eq_float("D06 §3.5 휴대 상한 2", data.param("param_consumable_carry_cap"), 2.0)
	# P1: T1 사용 성공 — 회복·재고 감소·반입분 불변 (held 는 사본이다)
	probe.consumables_carry_in = {"consumable_p1": 2, "consumable_p2": 2, "consumable_p3": 2}
	probe.start_gp()
	_flatten_neighbors(probe)
	probe.begin_turn()
	probe.chassis = 50.0
	var used := probe.use_consumable("consumable_p1")
	_ok("P1 사용 성공 = 로그 이벤트", used.size() == 1, str(used))
	_eq_float("P1 회복 +15", probe.chassis, 65.0)
	_ok("P1 재고 감소 2→1", int(probe.consumables_held["consumable_p1"]) == 1,
		str(probe.consumables_held))
	_ok("반입분(carry_in)은 소비되지 않는다", int(probe.consumables_carry_in["consumable_p1"]) == 2,
		str(probe.consumables_carry_in))
	# 최대치 절단
	probe.chassis = data.param("param_chassis_max") - 5.0
	probe.use_consumable("consumable_p1")
	_eq_float("P1 회복 = 최대치 절단", probe.chassis, data.param("param_chassis_max"))
	_ok("P1 재고 소진", int(probe.consumables_held["consumable_p1"]) == 0, str(probe.consumables_held))
	_ok("재고 0 = 거부", probe.use_consumable("consumable_p1").is_empty())
	# T1 밖 사용 거부 — 스핀 이후에는 상태 무변경으로 거부된다 (R-B)
	probe.spin()
	var before_chassis := probe.chassis
	_ok("T1 밖 사용 거부", probe.use_consumable("consumable_p2").is_empty())
	_eq_float("거부 시 섀시 무변경", probe.chassis, before_chassis)
	_ok("거부 시 재고 무변경", int(probe.consumables_held["consumable_p2"]) == 2,
		str(probe.consumables_held))
	# P2: 다음 트러블 1회 반감 — 1회째 ×0.5, 2회째 정상 (지속 효과의 소진)
	var trouble_hit := CsvTable.to_float(String(data.match_effects[RaceTypes.SYMBOL_TROUBLE][1]["chassis"]))
	probe.provisional = _combo(RaceTypes.SYMBOL_LINE, 3, RaceTypes.SYMBOL_LINE)
	probe.confirm(0.0)
	probe.begin_turn()
	probe.use_consumable("consumable_p2")
	var after_restore := probe.chassis
	probe.spin()
	probe.provisional = _combo(RaceTypes.SYMBOL_TROUBLE, 1, RaceTypes.SYMBOL_LINE)
	probe.confirm(0.0)
	_eq_float("P2 트러블 1회째 = 반감 (mn1 s2 계수 1.0)", probe.chassis,
		after_restore + trouble_hit * 0.5)
	var after_first := probe.chassis
	probe.begin_turn()
	probe.spin()
	probe.provisional = _combo(RaceTypes.SYMBOL_TROUBLE, 1, RaceTypes.SYMBOL_LINE)
	probe.confirm(0.0)
	_eq_float("P2 소진 후 트러블 2회째 = 정상 소모", probe.chassis, after_first + trouble_hit)
	# P3: 잔여 구간 섀시 소모 −20% — 트러블·해저드 턴당 소모·듀얼 실패 페널티 3경로 [가안]
	var reduced := _new_engine(405, "circuit_mn3")   # mn3 s2 = 해저드 (주속성)
	var plain := _new_engine(405, "circuit_mn3")
	for pair in [[reduced, true], [plain, false]]:
		var engine2: RaceEngine = pair[0]
		engine2.consumables_carry_in = {"consumable_p3": 1}
		engine2.start_gp()
		_flatten_neighbors(engine2)
		engine2.begin_turn()   # s1
		if bool(pair[1]):
			engine2.use_consumable("consumable_p3")
		engine2.spin()
		engine2.provisional = _combo(RaceTypes.SYMBOL_LINE, 3, RaceTypes.SYMBOL_LINE)
		engine2.confirm(0.0)
		engine2.begin_turn()   # s2 = 해저드
		engine2.chassis = 80.0
		engine2.spin()
		engine2.provisional = _combo(RaceTypes.SYMBOL_TROUBLE, 1, RaceTypes.SYMBOL_LINE)
		engine2.confirm(0.0)
	var hazard_per_turn := data.param("param_chassis_hazard_per_turn")
	var wear_mult := CsvTable.to_float(String(data.sector_attr("attr_hazard")["chassis_wear_mult"]))
	var plain_loss := 80.0 - plain.chassis
	var reduced_loss := 80.0 - reduced.chassis
	_eq_float("P3 무효과 기준선 (해저드 턴당 + 트러블 ×1.15)", plain_loss,
		hazard_per_turn - trouble_hit * wear_mult)
	_eq_float("P3 = 해저드·트러블 소모 −20%", reduced_loss, plain_loss * 0.8)
	# P3: 듀얼 실패 페널티도 경감 대상 [가안 — 문면 "잔여 구간 섀시 소모" 무한정]
	var duelist := _new_engine(406, "circuit_mn1")
	duelist.consumables_carry_in = {"consumable_p3": 1}
	duelist.start_gp()
	_flatten_neighbors(duelist)
	duelist.begin_turn()
	duelist.use_consumable("consumable_p3")
	duelist.spin()
	duelist.provisional = _combo(RaceTypes.SYMBOL_LINE, 3, RaceTypes.SYMBOL_LINE)
	duelist.confirm(0.0)
	_force_duel(duelist, RaceTypes.DuelType.OVERTAKE)
	duelist.begin_turn()
	# 듀얼 턴의 T1은 "섹터 개시"가 아니다 — 사용 거부 (R-B 문면 준거)
	_ok("듀얼 턴 T1 사용 거부", duelist.use_consumable("consumable_p1").is_empty())
	duelist.chassis = 60.0
	duelist.spin()
	duelist.provisional = _combo(RaceTypes.SYMBOL_TROUBLE, 3, RaceTypes.SYMBOL_TROUBLE)  # 판정 최저 = 확정 패배
	duelist.confirm(0.0)
	_eq_float("P3 = 듀얼 실패 페널티 −20%", duelist.chassis,
		60.0 - data.param("param_chassis_duel_fail_penalty") * 0.8)
	# 직렬화 왕복 — 지속 효과·잔여 인벤토리 보존 (재로드로 실런트·쿨런트가 증발하면 안 된다)
	var carrier := _new_engine(407, "circuit_mn1")
	carrier.consumables_carry_in = {"consumable_p2": 2, "consumable_p3": 1}
	carrier.start_gp()
	_flatten_neighbors(carrier)
	carrier.begin_turn()
	carrier.use_consumable("consumable_p2")
	carrier.use_consumable("consumable_p3")
	var snapshot := carrier.serialize()
	var revived := _new_engine(408, "circuit_mn1")
	_ok("소모품 상태 복원 성립", revived.restore(snapshot))
	_ok("복원: 잔여 인벤토리", int(revived.consumables_held.get("consumable_p2", -1)) == 1
		and int(revived.consumables_held.get("consumable_p3", -1)) == 0,
		str(revived.consumables_held))
	_ok("복원: P2 실드 적립", revived.trouble_shield_charges == 1,
		str(revived.trouble_shield_charges))
	_eq_float("복원: P3 경감 비율", revived.wear_reduction, 0.20)
	# 구스냅샷(키 부재) = 소모품 이전 세계 — 빈 인벤토리·무효과 (IMPL-090 전례)
	snapshot.erase("consumables_held")
	snapshot.erase("trouble_shield_charges")
	snapshot.erase("wear_reduction")
	var legacy := _new_engine(409, "circuit_mn1")
	_ok("구스냅샷 복원 성립", legacy.restore(snapshot))
	_ok("구스냅샷 = 빈 인벤토리·무효과", legacy.consumables_held.is_empty()
		and legacy.trouble_shield_charges == 0 and legacy.wear_reduction == 0.0,
		str(legacy.consumables_held))


# ── 레조넌스 오버레이 런타임 (D08 §3.7 R3·R6·R7 · D13 별첨A §6.6) ──
# 독립 검증에서 런타임 전체가 무검증으로 드러났다 — 슬롯에 0 이외를 넣는 코드가 0건이었다.
func _resonance_runtime() -> void:
	var stage_bonus := 0.0
	# R3: 임의 분류 3매치 성립 시 통상 정산 유지 + 보너스 추가 (트러블 3매치 포함)
	var probe := _new_engine(202, "circuit_mn1")
	if probe == null:
		return
	stage_bonus = float(probe.data.stages["stage_metro_night"]["resonance_bonus_value"])
	probe.start_gp()
	_flatten_neighbors(probe)
	probe.resonance_circuit_id = "circuit_mn1"
	probe.resonance_sector_slot = 1
	probe.begin_turn()
	probe.spin()
	probe.charge = 0
	probe.chassis = 100.0
	probe.provisional = _combo(RaceTypes.SYMBOL_TROUBLE, 3, RaceTypes.SYMBOL_TROUBLE)
	probe.confirm(0.0)
	var trouble_chassis := CsvTable.to_float(String(probe.data.match_effects[RaceTypes.SYMBOL_TROUBLE][3]["chassis"]))
	_eq_float("R3 트러블 3매치 통상 정산 유지", probe.chassis, 100.0 + trouble_chassis)
	_eq_float("R3 트러블 3매치도 보너스 성립", float(probe.charge), stage_bonus)
	# 비3매치는 보너스 없음
	var probe2 := _new_engine(202, "circuit_mn1")
	probe2.start_gp()
	_flatten_neighbors(probe2)
	probe2.resonance_circuit_id = "circuit_mn1"
	probe2.resonance_sector_slot = 1
	probe2.begin_turn()
	probe2.spin()
	probe2.charge = 0
	probe2.provisional = [RaceTypes.SYMBOL_PULSE, RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_BRAKING]
	probe2.confirm(0.0)
	var pulse_charge := CsvTable.to_int(String(probe2.data.match_effects[RaceTypes.SYMBOL_PULSE][1]["charge"]))
	var stable := probe2.data.param_int("param_charge_stable_sector")
	_ok("R3 비3매치 = 보너스 없음", probe2.charge == pulse_charge + stable,
		"charge=%d expected=%d" % [probe2.charge, pulse_charge + stable])
	# 오버레이 없는 섹터는 무지급
	var probe3 := _new_engine(202, "circuit_mn1")
	probe3.start_gp()
	_flatten_neighbors(probe3)
	probe3.resonance_circuit_id = "circuit_mn1"
	probe3.resonance_sector_slot = 3          # 현재 진입은 s1
	probe3.begin_turn()
	probe3.spin()
	probe3.charge = 0
	probe3.provisional = _combo(RaceTypes.SYMBOL_LINE, 3, RaceTypes.SYMBOL_LINE)
	probe3.confirm(0.0)
	_ok("R6 오버레이 없는 섹터 무지급", probe3.charge == probe3.data.param_int("param_charge_stable_sector"),
		"charge=%d" % probe3.charge)
	# R6 서킷 축: 다른 서킷에서는 발동하지 않는다 (무대당 1회의 서킷 축)
	var probe4 := _new_engine(202, "circuit_mn3")
	probe4.start_gp()
	_flatten_neighbors(probe4)
	probe4.resonance_circuit_id = "circuit_mn1"   # 추첨은 mn1이었다
	probe4.resonance_sector_slot = 1
	probe4.begin_turn()
	probe4.spin()
	probe4.charge = 0
	probe4.provisional = _combo(RaceTypes.SYMBOL_LINE, 3, RaceTypes.SYMBOL_LINE)
	probe4.confirm(0.0)
	_ok("R6 다른 서킷에서 미발동", probe4.charge == probe4.data.param_int("param_charge_stable_sector"),
		"charge=%d" % probe4.charge)
	# R6 무대당 1회: 같은 섹터를 랩마다 다시 지나도 재지급하지 않는다
	var probe5 := _new_engine(202, "circuit_mn1")
	probe5.start_gp()
	_flatten_neighbors(probe5)
	probe5.resonance_circuit_id = "circuit_mn1"
	probe5.resonance_sector_slot = 1
	probe5.begin_turn()
	probe5.spin()
	probe5.charge = 0
	probe5.provisional = _combo(RaceTypes.SYMBOL_LINE, 3, RaceTypes.SYMBOL_LINE)
	probe5.confirm(0.0)
	var after_first := probe5.charge
	_ok("R6 1회차 지급", after_first > probe5.data.param_int("param_charge_stable_sector"),
		"charge=%d" % after_first)
	# 다음 랩 같은 슬롯으로 강제 진입
	probe5.lap = 2
	probe5.sector = 0
	probe5.begin_turn()
	probe5.spin()
	probe5.provisional = _combo(RaceTypes.SYMBOL_LINE, 3, RaceTypes.SYMBOL_LINE)
	probe5.confirm(0.0)
	_ok("R6 무대당 1회 — 재지급 없음",
		probe5.charge == after_first + probe5.data.param_int("param_charge_stable_sector"),
		"charge=%d after_first=%d" % [probe5.charge, after_first])
	# R7 듀얼 무관여: 듀얼 턴에서는 3매치여도 보너스가 없다
	var probe6 := _new_engine(202, "circuit_mn1")
	probe6.start_gp()
	_flatten_neighbors(probe6)
	probe6.resonance_circuit_id = "circuit_mn1"
	_force_duel(probe6, RaceTypes.DuelType.OVERTAKE)
	probe6.resonance_sector_slot = probe6.sector
	probe6.begin_turn()
	_ok("R7 듀얼 턴 진입", probe6.current_turn_is_duel)
	probe6.spin()
	probe6.charge = 0
	probe6.provisional = _combo(RaceTypes.SYMBOL_LINE, 3, RaceTypes.SYMBOL_LINE)
	probe6.confirm(0.0)
	_ok("R7 듀얼 턴 레조넌스 무관여", probe6.charge <= probe6.data.param_int("param_charge_duel_win"),
		"charge=%d" % probe6.charge)
	# R6 위치 비공개: 진입 전 턴의 이벤트에 레조넌스 공표가 없다
	var probe7 := _new_engine(202, "circuit_mn1")
	probe7.start_gp()
	_flatten_neighbors(probe7)
	probe7.resonance_circuit_id = "circuit_mn1"
	probe7.resonance_sector_slot = 3
	var info := probe7.begin_turn()     # s1 진입 — 오버레이는 s3
	_ok("R6 진입 전 공표 없음", not _events_contain(info.get("events", []), "raceLog.resonanceEnter01"),
		str(info.get("events", [])))
	probe7.spin()
	probe7.provisional = _combo(RaceTypes.SYMBOL_PULSE, 1, RaceTypes.SYMBOL_LINE)
	probe7.confirm(0.0)
	probe7.begin_turn()                 # s2
	probe7.spin()
	probe7.provisional = _combo(RaceTypes.SYMBOL_PULSE, 1, RaceTypes.SYMBOL_LINE)
	probe7.confirm(0.0)
	var enter_info := probe7.begin_turn()   # s3 = 오버레이 섹터
	_ok("R6 진입 시 공표", _events_contain(enter_info.get("events", []), "raceLog.resonanceEnter01"),
		str(enter_info.get("events", [])))


func _events_contain(events: Array, key: String) -> bool:
	for event in events:
		if String(event.get("key", "")) == key:
			return true
	return false


# ── 압박·저항 런타임 대조 (D13 별첨A §2.1 인쇄값 도달성) ──
# 산식 대조만으로는 엔진이 어떤 입력을 먹이는지 알 수 없다. 실제 주행에서 인쇄값이 나오는지 본다.
func _neighbor_passive_runtime() -> void:
	var engine := _new_engine(1313, "circuit_mn1")
	if engine == null:
		return
	engine.start_gp()
	# 디아스를 플레이어 뒤차로 강제 배치 (다른 인접 영향 제거)
	var player_index := engine.positions.find(RaceEngine.PLAYER_ID)
	if player_index >= engine.positions.size() - 1:
		player_index = engine.positions.size() - 2
		engine.positions.erase(RaceEngine.PLAYER_ID)
		engine.positions.insert(player_index, RaceEngine.PLAYER_ID)
	engine.positions.erase("ai_diaz")
	engine.positions.insert(engine.positions.find(RaceEngine.PLAYER_ID) + 1, "ai_diaz")
	engine._retarget(true, true)
	_ok("디아스 뒤차 배치", engine.rear_target == "ai_diaz", "rear=%s" % engine.rear_target)
	engine.begin_turn()
	engine.spin()
	engine.rear_gauge = 0.0
	engine.provisional = _combo(RaceTypes.SYMBOL_PULSE, 3, RaceTypes.SYMBOL_PULSE)
	engine.confirm(0.0)
	# 펄스 3매치는 후방 게이지에 영향이 없으므로 남는 것은 압박 가산뿐 (s1 = 스트레이트, 계수 1.0)
	_eq_float("D13 §2.1 디아스 압박 실측 = 16.9", engine.rear_gauge, 16.9, 0.05)


# ── 음성 검사 — "강제가 살아 있는가" (독립 검증 G-3) ──
# 사후 조건 `transition_errors == 0`은 강제 코드가 살아 있을 때만 의미가 있다.
# 전이 검사를 무력화하면 카운터가 0을 읽어 초록이 되므로, 위반을 실제로 시도해 거부를 단언한다.
func _negative_guards() -> void:
	var engine := _new_engine(303)
	if engine == null:
		return
	engine.start_gp()          # → LAP_LOOP
	var before_state := engine.gp_state
	var before_errors := engine.transition_errors
	engine._transition(RaceTypes.GpState.RESULT)   # LAP_LOOP → RESULT = 전이표에 없음
	_ok("음성 검사: 비정의 전이 거부", engine.gp_state == before_state,
		"state=%d expected=%d" % [engine.gp_state, before_state])
	_ok("음성 검사: 비정의 전이 계수", engine.transition_errors == before_errors + 1,
		"errors=%d" % engine.transition_errors)
	engine.transition_errors = 0   # 의도된 위반이므로 전역 사후 조건에서 제외
	# 침묵 기본값 금지 가드 자체를 검사한다 — 미등재 param 조회가 is_ok()를 내려야 한다
	var data := GameData.new()
	if not data.load_all():
		_failures += 1
		print("  [FAIL] data load")
		return
	_ok("음성 검사: 로드 직후 is_ok", data.is_ok())
	data.param("param_this_key_does_not_exist")
	_ok("음성 검사: 미등재 param 조회가 is_ok를 내린다", not data.is_ok())
	var data2 := GameData.new()
	data2.load_all()
	data2.sector_attr("attr_this_does_not_exist")
	_ok("음성 검사: 미등재 속성 조회가 is_ok를 내린다", not data2.is_ok())
	var data3 := GameData.new()
	data3.load_all()
	data3.presentation_grade("grade_nope")
	_ok("음성 검사: 미등재 등급 조회가 is_ok를 내린다", not data3.is_ok())
	# T4 개입 창 게이트 — 잔액을 충분히 준 상태에서 창 밖 개입이 거부돼야 한다.
	# (잔액 0으로 시험하면 게이트가 없어도 '잔액 부족'으로 거부되어 게이트를 검증하지 못한다)
	var gated := _new_engine(303)
	gated.start_gp()
	gated.begin_turn()
	gated.charge = gated.data.param_int("param_charge_cap")
	gated.provisional = [RaceTypes.SYMBOL_TROUBLE, RaceTypes.SYMBOL_TROUBLE, RaceTypes.SYMBOL_TROUBLE]
	var hold_result: Dictionary = gated.hold_respin([0])
	_ok("음성 검사: 창 외 홀드 거부 이유 = phase",
		not bool(hold_result.get("ok", false)) and String(hold_result.get("error", "")) == "phase",
		str(hold_result))
	var negate_result: Dictionary = gated.negate_trouble()
	_ok("음성 검사: 창 외 트러블무효 거부 이유 = phase",
		not bool(negate_result.get("ok", false)) and String(negate_result.get("error", "")) == "phase",
		str(negate_result))
	var boost_result: Dictionary = gated.add_duel_boost()
	_ok("음성 검사: 창 외 부스트 거부 이유 = phase",
		not bool(boost_result.get("ok", false)) and String(boost_result.get("error", "")) == "phase",
		str(boost_result))


# ── 결과·순위·시간 모델 (독립 검증 G-4) ──
func _result_and_ranking() -> void:
	# 완주 순위 → 포인트가 D13 별첨A §6.1 표와 1:1 (순위 오프바이원이면 포인트가 밀린다)
	var engine := _new_engine(404)
	if engine == null:
		return
	engine.start_gp()
	_flatten_neighbors(engine)
	# 플레이어를 P8로 강제 배치한 뒤 GP를 끝까지 돌린다
	var guard := 300
	while not engine.finished and guard > 0:
		guard -= 1
		var info := engine.begin_turn()
		if String(info.get("type", "")) == "finished":
			break
		engine.spin()
		engine.provisional = _combo(RaceTypes.SYMBOL_PULSE, 3, RaceTypes.SYMBOL_PULSE)
		engine.confirm(0.0)
	_ok("결과 성립", engine.finished and not engine.result.is_empty())
	var rank := int(engine.result["player_rank"])
	var expected_points := int(engine.data.points_tier1.get(rank, -1))
	_ok("순위 → 포인트 = D13 §6.1 표", int(engine.result["tour_points"]) == expected_points,
		"rank=P%d points=%s expected=%d" % [rank, str(engine.result["tour_points"]), expected_points])
	_ok("순위 범위 P1~P16", rank >= 1 and rank <= 16, "rank=%d" % rank)
	# standings에서의 위치와 player_rank가 일치 (오프바이원 검출)
	var standings: Array = engine.result["standings"]
	_ok("player_rank = standings 인덱스 + 1", standings.find(RaceEngine.PLAYER_ID) + 1 == rank,
		"index=%d rank=%d" % [standings.find(RaceEngine.PLAYER_ID), rank])
	# 리타이어 순서: 가장 이른 리타이어가 최하위
	var retire := _new_engine(505)
	retire.start_gp()
	_flatten_neighbors(retire)
	var first_out := String(retire.positions[0])
	var second_out := String(retire.positions[1])
	retire._retire_entrant(first_out)
	retire._retire_entrant(second_out)
	# 합법 경로로 종료 상태에 들어간다 — LAP_LOOP에서 _finish_gp를 직접 부르면
	# RESULT가 전이표에 없어 테스트가 스스로 비정의 전이를 만든다.
	retire._transition(RaceTypes.GpState.GP_FINISH)
	retire._finish_gp()
	var final_order: Array = retire.result["standings"]
	_ok("리타이어 정렬 = 이른 리타이어가 최하위",
		final_order[final_order.size() - 1] == first_out
		and final_order[final_order.size() - 2] == second_out,
		"tail=%s" % str(final_order.slice(final_order.size() - 2)))
	# 시간 모델: 섹터 턴 × 턴 시간 + 듀얼 × 듀얼 시간 + 마무리 (계수 교환 검출)
	var timing := _new_engine(606)
	timing.start_gp()
	timing.turn_number = 12
	timing.duel_count = 2
	var expected_seconds := 10.0 * timing.data.param("param_time_turn_sec") \
		+ 2.0 * timing.data.param("param_time_duel_sec") \
		+ 10.0 * timing.data.param("param_time_pacing_beat_sec") \
		+ timing.data.param("param_time_wrapup_sec")
	_eq_float("GP 소요 모델 = D13 §4.1 산식", timing.estimated_minutes(), expected_seconds / 60.0, 0.01)
	# D13 §4.1 성분 산술을 **정확히** 단언한다. 인쇄 총계(12턴 10.0분)와는 0.225분 차이가
	# 있는데 이는 반올림이 아니다(9.775 → 9.8). 허용 오차로 흡수하면 그 불일치가
	# 테스트 뒤에 숨고, 더 중요하게는 **성분 산술이 GP 목표 하한 10분을 밑도는 사실**이
	# 가려진다 (D05 §2.2 목표 10~15분). impl_log 보고 항목 — 총괄 판정 대기.
	var turn_sec := timing.data.param("param_time_turn_sec")
	var duel_sec := timing.data.param("param_time_duel_sec")
	var beat_sec := timing.data.param("param_time_pacing_beat_sec")
	var wrapup_sec := timing.data.param("param_time_wrapup_sec")
	# 사용자 판정(2026-08-12 · U-5): 결산·이벤트 210 → 225초로 상향해 GP 목표 하한 10분을 충족.
	# 성분 산술 = 252 + 112.5 + 12 + 225 = 601.5초 = 10.025분.
	_eq_float("D13 §4.1 12턴 성분 산술 = 601.5초",
		12.0 * turn_sec + 2.5 * duel_sec + 12.0 * beat_sec + wrapup_sec, 601.5, 0.01)
	_ok("D05 §2.2 GP 목표 하한 10분 충족",
		(12.0 * turn_sec + 2.5 * duel_sec + 12.0 * beat_sec + wrapup_sec) / 60.0 >= 10.0,
		"minutes=%f" % ((12.0 * turn_sec + 2.5 * duel_sec + 12.0 * beat_sec + wrapup_sec) / 60.0))
	# 15턴 총계 11.3분은 문면에 성분이 없다 — 듀얼 수는 12턴의 2.5를 턴 비례로 파생한
	# 3.125다([가안], impl_log 등재). 라벨에 파생임을 명시해 정본 전사와 구분한다.
	_eq_float("[파생] 15턴 총계 = 11.6분 (듀얼 비례 3.125 가정 · U-5 반영)",
		(15.0 * turn_sec + 3.125 * duel_sec + 15.0 * beat_sec + wrapup_sec) / 60.0, 11.59, 0.06)
	# 완급 비트 평균 1.0초는 성분 2쌍의 곱이다 (2.5초 상한 × 발동 40% — D13 §8.1).
	# 성분을 두지 않으면 상한·빈도가 바뀌어도 평균만 손으로 맞춰 검사를 통과시킬 수 있다.
	_eq_float("D13 §8.1 완급 비트 재생 상한 2.5초",
		timing.data.param("param_pacing_beat_max_sec"), 2.5)
	_eq_float("D13 §8.1 완급 비트 발동 빈도 40%",
		timing.data.param("param_pacing_beat_probability"), 0.40)
	_eq_float("D13 §8.1 완급 비트 평균 = 상한 × 빈도",
		timing.data.param("param_pacing_beat_max_sec")
			* timing.data.param("param_pacing_beat_probability"), beat_sec)
	_eq_float("D13 §8.1 접전 판정 임계 70 G",
		timing.data.param("param_closerace_gauge_threshold"), 70.0)
	# 타임아웃에 추가 페널티가 없다 (D05 §7.3 확정)
	var timeout_probe := _new_engine(707)
	timeout_probe.start_gp()
	_flatten_neighbors(timeout_probe)
	timeout_probe.begin_turn()
	timeout_probe.spin()
	timeout_probe.provisional = _combo(RaceTypes.SYMBOL_LINE, 1, RaceTypes.SYMBOL_LINE)
	timeout_probe.chassis = 80.0
	timeout_probe.charge = 5
	var confirm_probe := _new_engine(707)
	confirm_probe.start_gp()
	_flatten_neighbors(confirm_probe)
	confirm_probe.begin_turn()
	confirm_probe.spin()
	confirm_probe.provisional = _combo(RaceTypes.SYMBOL_LINE, 1, RaceTypes.SYMBOL_LINE)
	confirm_probe.chassis = 80.0
	confirm_probe.charge = 5
	timeout_probe.timeout()
	confirm_probe.confirm(0.0)     # 동일 잔여 비율(모멘텀 없음)로 확정
	_eq_float("타임아웃 추가 페널티 0 (섀시)", timeout_probe.chassis, confirm_probe.chassis)
	_ok("타임아웃 추가 페널티 0 (차지)", timeout_probe.charge == confirm_probe.charge,
		"timeout=%d confirm=%d" % [timeout_probe.charge, confirm_probe.charge])
	# 모멘텀 보너스: 여유 구간 확정이 전방 게이지를 D13 값만큼 더한다
	var momentum_on := _new_engine(808)
	momentum_on.start_gp()
	_flatten_neighbors(momentum_on)
	momentum_on.begin_turn()
	momentum_on.spin()
	momentum_on.front_gauge = 0.0
	momentum_on.provisional = _combo(RaceTypes.SYMBOL_LINE, 1, RaceTypes.SYMBOL_LINE)
	momentum_on.confirm(1.0)
	var momentum_off := _new_engine(808)
	momentum_off.start_gp()
	_flatten_neighbors(momentum_off)
	momentum_off.begin_turn()
	momentum_off.spin()
	momentum_off.front_gauge = 0.0
	momentum_off.provisional = _combo(RaceTypes.SYMBOL_LINE, 1, RaceTypes.SYMBOL_LINE)
	momentum_off.confirm(0.0)
	_eq_float("모멘텀 보너스 = D13 §2.1 +5G",
		momentum_on.front_gauge - momentum_off.front_gauge,
		momentum_on.data.param("param_gauge_momentum_bonus"))
	# 최종 랩 계수 ×1.2: 같은 조합이 최종 랩에서 더 큰 게이지를 만든다
	var final_lap := _new_engine(909, "circuit_mn1")
	final_lap.start_gp()
	_flatten_neighbors(final_lap)
	final_lap.lap = final_lap.data.circuit_int("laps")
	final_lap.begin_turn()
	final_lap.spin()
	final_lap.front_gauge = 0.0
	final_lap.provisional = _combo(RaceTypes.SYMBOL_SLIPSTREAM, 1, RaceTypes.SYMBOL_BRAKING)
	final_lap.confirm(0.0)
	var first_lap := _new_engine(909, "circuit_mn1")
	first_lap.start_gp()
	_flatten_neighbors(first_lap)
	first_lap.begin_turn()
	first_lap.spin()
	first_lap.front_gauge = 0.0
	first_lap.provisional = _combo(RaceTypes.SYMBOL_SLIPSTREAM, 1, RaceTypes.SYMBOL_BRAKING)
	first_lap.confirm(0.0)
	var effect := CsvTable.to_float(String(first_lap.data.match_effects[RaceTypes.SYMBOL_SLIPSTREAM][1]["front_gauge"]))
	var resist := first_lap.data.param("param_gauge_front_resist_base")
	var final_mult := first_lap.data.param("param_gauge_final_lap_mult")
	_eq_float("최종 랩 게이지 계수 ×1.2 적용", final_lap.front_gauge, (effect - resist) * final_mult, 0.01)
	# 듀얼 부스트가 판정치에 실제로 작용한다 (차지만 소비되고 무효면 개입 문법이 무너진다)
	var boosted := _new_engine(111)
	boosted.start_gp()
	_flatten_neighbors(boosted)
	_force_duel(boosted, RaceTypes.DuelType.OVERTAKE)
	var rank_before := boosted.player_position()
	boosted.begin_turn()
	boosted.spin()
	boosted.charge = boosted.data.param_int("param_charge_cap")
	while bool(boosted.add_duel_boost().get("ok", false)):
		pass
	boosted.provisional = [RaceTypes.SYMBOL_SLIPSTREAM, RaceTypes.SYMBOL_BRAKING, RaceTypes.SYMBOL_BRAKING]
	boosted.confirm(0.0)
	var unboosted := _new_engine(111)
	unboosted.start_gp()
	_flatten_neighbors(unboosted)
	_force_duel(unboosted, RaceTypes.DuelType.OVERTAKE)
	unboosted.begin_turn()
	unboosted.spin()
	unboosted.charge = 0
	unboosted.provisional = [RaceTypes.SYMBOL_SLIPSTREAM, RaceTypes.SYMBOL_BRAKING, RaceTypes.SYMBOL_BRAKING]
	unboosted.confirm(0.0)
	_ok("듀얼 부스트가 판정치에 작용 (부스트 승 / 무부스트 패)",
		boosted.player_position() == rank_before - 1 and unboosted.player_position() == rank_before,
		"boosted=P%d unboosted=P%d before=P%d" % [boosted.player_position(), unboosted.player_position(), rank_before])
	# 방어 듀얼 패배의 귀결 = 피추월. 순위 절대값이 아니라 **상대와의 순서**로 단언한다 —
	# 같은 턴의 배경 AI 리타이어가 앞자리를 비우면 절대 순위가 상쇄되어 검사가 무의미해진다.
	var defense_loss := _new_engine(333)
	defense_loss.start_gp()
	_flatten_neighbors(defense_loss)
	var loss_opponent := _force_duel(defense_loss, RaceTypes.DuelType.DEFENSE)
	_ok("방어 듀얼 상대가 뒤차", defense_loss.positions.find(loss_opponent) > defense_loss.positions.find(RaceEngine.PLAYER_ID))
	defense_loss.begin_turn()
	defense_loss.spin()
	defense_loss.charge = 0
	# 방어 primary(브레이킹) 없이 라인 1매치만 → 임계 미달
	defense_loss.provisional = [RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_PULSE, RaceTypes.SYMBOL_PULSE]
	defense_loss.confirm(0.0)
	_ok("방어 듀얼 패배 = 상대가 앞으로 (피추월)",
		defense_loss.positions.find(loss_opponent) < defense_loss.positions.find(RaceEngine.PLAYER_ID),
		"opponent_index=%d player_index=%d" % [defense_loss.positions.find(loss_opponent),
			defense_loss.positions.find(RaceEngine.PLAYER_ID)])
	var defense_win := _new_engine(333)
	defense_win.start_gp()
	_flatten_neighbors(defense_win)
	var win_opponent := _force_duel(defense_win, RaceTypes.DuelType.DEFENSE)
	defense_win.begin_turn()
	defense_win.spin()
	defense_win.provisional = _combo(RaceTypes.SYMBOL_BRAKING, 3, RaceTypes.SYMBOL_BRAKING)
	defense_win.confirm(0.0)
	_ok("방어 듀얼 승리 = 상대가 여전히 뒤",
		defense_win.positions.find(win_opponent) > defense_win.positions.find(RaceEngine.PLAYER_ID),
		"opponent_index=%d player_index=%d" % [defense_win.positions.find(win_opponent),
			defense_win.positions.find(RaceEngine.PLAYER_ID)])
	# 게이지 계수가 심볼별로 빠지지 않는지 — 방어(브레이킹)·공략(라인) 경로도 확인
	var battle := _new_engine(222, "circuit_mn1")
	battle.start_gp()
	_flatten_neighbors(battle)
	battle.sector = 3
	battle.begin_turn()
	battle.spin()
	battle.rear_gauge = 90.0
	battle.provisional = _combo(RaceTypes.SYMBOL_BRAKING, 1, RaceTypes.SYMBOL_PULSE)
	battle.confirm(0.0)
	var plain := _new_engine(222, "circuit_mn1")
	plain.start_gp()
	_flatten_neighbors(plain)
	plain.begin_turn()
	plain.spin()
	plain.rear_gauge = 90.0
	plain.provisional = _combo(RaceTypes.SYMBOL_BRAKING, 1, RaceTypes.SYMBOL_PULSE)
	plain.confirm(0.0)
	_ok("배틀 존 계수가 방어(브레이킹) 경로에도 적용", battle.rear_gauge < plain.rear_gauge,
		"battle=%f plain=%f" % [battle.rear_gauge, plain.rear_gauge])


# ── U-4 결선: 슬롯 진행 보정이 AI 기저 강도에 작용하는가 (D08 §2.4 · D13 별첨A §6.2) ──
# 사용자 판정(2026-08-12): 축 = 투어 내 GP 슬롯(제1~4전).
func _slot_progression_wired() -> void:
	var slot1 := _new_engine(4711)
	var slot4 := _new_engine(4711)
	if slot1 == null or slot4 == null:
		return
	slot1.race_slot = 1
	slot4.race_slot = 4
	slot1.start_gp()
	slot4.start_gp()
	var expected_delta := slot4.data.tour_slot_pace_add(4) - slot1.data.tour_slot_pace_add(1)
	var checked_any := false
	for entrant_id in slot1.entrants:
		if entrant_id == RaceEngine.PLAYER_ID:
			continue
		if not slot4.entrants.has(entrant_id):
			continue
		checked_any = true
		_eq_float("슬롯 4 AI 페이스 = 슬롯 1 + 보정 차 (%s)" % entrant_id,
			float(slot4.entrants[entrant_id]["pace"]) - float(slot1.entrants[entrant_id]["pace"]),
			expected_delta, 0.0001)
	_ok("AI 참가자 대조 표본 확보", checked_any)
	# 플레이어는 보정 대상이 아니다 (D08 §2.4 — 목적어가 '필러·경쟁 풀의 기본 파라미터')
	_eq_float("플레이어는 슬롯 보정 미적용",
		float(slot4.entrants[RaceEngine.PLAYER_ID]["pace"]),
		float(slot1.entrants[RaceEngine.PLAYER_ID]["pace"]))
	# 미등재 슬롯은 조용히 0이 되지 않는다
	var strict := _new_engine(4712, "", false)
	strict.race_slot = 9
	strict.start_gp()
	_ok("미등재 GP 슬롯 조회가 is_ok를 내린다", not strict.data.is_ok())
	strict.transition_errors = 0
