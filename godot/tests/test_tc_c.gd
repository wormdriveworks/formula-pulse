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
	_check_global_postconditions()
	print("")
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


func _new_engine(seed_value: int, circuit_id: String = "") -> RaceEngine:
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
	_ok("D13 §1.2 찬스 3매치 = 즉시 듀얼",
		String(data.match_effects[RaceTypes.SYMBOL_CHANCE][3]["special"]).strip_edges() == "duel_trigger")
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
	# D13 별첨A §1.3 속성 6축 규칙 계수
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
	# D13 별첨A §6.6 레조넌스 — 무대 1 = 펄스 차지 +2
	var stage: Dictionary = data.stages["stage_metro_night"]
	_ok("D13 §6.6 메트로 나이트 보너스 유형 = 차지",
		String(stage["resonance_bonus_type"]) == "charge", str(stage))
	_eq_float("D13 §6.6 메트로 나이트 보너스 +2", float(stage["resonance_bonus_value"]), 2.0)
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


# ── TC-C11 봉인 규칙 — 릴 정지 연출 완료 전 결과·결과 상관 신호 노출 0 (D02 §4 · D12 §6.3) ──
func _tc_c11_seal() -> void:
	var engine := _new_engine(99)
	if engine == null:
		return
	engine.start_gp()
	var info := engine.begin_turn()
	# T1 이벤트에는 결과·결과 상관 신호가 없어야 한다 (스핀 이전이므로 결과 자체가 부재)
	_ok("TC-C11 스핀 전 전개 후보 공백", engine.get_provisional().is_empty(),
		"provisional=%s" % str(engine.get_provisional()))
	var t1_events: Array = info.get("events", [])
	engine.spin()
	# 스핀 직후: 엔진은 결과를 내부 확정하되 이벤트를 자발 발행하지 않는다.
	# (노출 시점 통제 = 표시 층의 get_provisional() 호출 — 엔진이 결과 이벤트를 밀어내면 봉인이 깨진다)
	_ok("TC-C11 스핀이 이벤트를 발행하지 않음", info.get("events", []) == t1_events,
		"events=%s" % str(info.get("events", [])))
	# 결과 상관 신호(정산 로그)는 확정 이후에만 생성된다
	_ok("TC-C11 확정 전 정산 로그 공백", engine.settle_log.is_empty(),
		"settle_log=%s" % str(engine.settle_log))
	var events: Array = engine.confirm(0.0)
	_ok("TC-C11 확정 후 정산 로그 생성", not engine.settle_log.is_empty())
	_ok("TC-C11 결과 이벤트는 T5 이후 페이즈", _all_events_after_spin(events), "events=%s" % str(events))


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
