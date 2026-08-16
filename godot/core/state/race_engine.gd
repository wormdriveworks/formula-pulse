# 레이스 엔진 — GP 상태 머신 + 턴 시퀀스 T1~T6 + 정산 8단계 (D05 §2~§5 · D12 §3).
# 순수 로직 계층: UI·플랫폼·프레임 무접촉 (혼입 0 / 프레임 의존 로직 금지 — 불변규칙 1·8).
# 전 수치는 GameData(D13) 경유 — 코드 내 수치 임의 기입 없음 (불변규칙 2).
#
# 봉인 규칙 (D12 §6.3 / 불변규칙 5): 스핀 결과는 T2 커밋 시점에 내부 확정되지만,
# 본 엔진은 어떤 출력 경로에도 자발 노출하지 않는다 — 노출 타이밍(릴 정지 연출 완료 후)은
# 표시 층이 get_provisional() 호출 시점으로 통제한다.
class_name RaceEngine
extends RefCounted

const PLAYER_ID := "player"

var data: GameData
var rng: RngService

var gp_state: int = RaceTypes.GpState.GP_START
var turn_phase: int = RaceTypes.TurnPhase.T1_SECTOR_OPEN

# 진행 카운터
# 투어 내 GP 슬롯 (제1~4전) — 슬롯 진행 보정의 입력. 투어 층이 주입한다.
# 사용자 판정(2026-08-12): 슬롯 진행 보정의 축 = 투어 내 GP 슬롯 (D08 §2.4 · D13 별첨A §6.2).
var race_slot: int = 1

var lap: int = 0
var sector: int = 0
var turn_number: int = 0
var duel_count: int = 0
var ai_retire_count: int = 0
var _retire_order: int = 0

# 참가자 — id -> 상태 사전 / positions[i] = P(i+1)의 id
var entrants: Dictionary = {}
var positions: Array = []

# 플레이어 자원 (D05 §6.2·§8 — 인게임 자원은 차지·섀시 이원이 전부)
var chassis: float = 0.0
# GP 간 이월 주입분 (D05 §8 — "그랑프리 간 자동 완전 회복은 없다"). 음수 = 미주입(최대치 개시).
# 이월 값의 소유는 아웃게임 층이고 엔진은 주입된 값을 소비만 한다 — 세션이 start_gp 전에 넣는다.
var chassis_carry_in: float = -1.0
var charge: int = 0
var front_gauge: float = 0.0
var rear_gauge: float = 0.0
var front_target: String = ""
var rear_target: String = ""

# 턴 시퀀스·정산 단계 추적 로그 (D14 TC-C2·TC-C10의 판정 근거 = '로그 대조').
# 결과·심볼을 담지 않는다 — 단계 식별자만 기록하므로 봉인 규칙과 무접촉.
var phase_log: Array = []
var settle_log: Array = []

# 턴 내부 상태
var provisional: Array = []          # 심볼 id 3개 (T3 전개 후보)
var hold_used: bool = false          # 홀드/리스핀 턴당 1회 (D05 §5.4)
var negated_troubles: int = 0
var duel_boost: int = 0
var pending_duel: int = RaceTypes.DuelType.NONE
var duel_opponent: String = ""
var current_turn_is_duel: bool = false
var _armed_duel: int = RaceTypes.DuelType.NONE

# 레조넌스 섹터 오버레이 (D08 §3.7 · D13 별첨A §6.6)
# 추첨은 투어 층 소관(투어 개막 1회 · resonance 스트림) — 엔진은 주입된 슬롯을 소비한다.
# 위치는 진입 전까지 어떤 출력 경로에도 노출하지 않는다 (R6 위치 비공개).
var resonance_circuit_id: String = ""  # 추첨된 서킷 (R6의 "서킷 슬롯 × 섹터 슬롯" 중 서킷 축)
var resonance_sector_slot: int = 0     # 0 = 오버레이 없음
var resonance_consumed: bool = false   # 무대당 1회 — 발동 후 재발동 차단
var resonance_announced: bool = false
var resonance_duel_bonus: float = 0.0  # 차기 듀얼 판정 보정 (D13 별첨A §2.4 '레조넌스 보정')

# 비정의 전이 시도 누계 (D14 TC-C1 판정 '비정의 전이 도달 0'의 기계 판정 근거)
var transition_errors: int = 0

var finished: bool = false
var result: Dictionary = {}


func setup(game_data: GameData, rng_service: RngService) -> void:
	data = game_data
	rng = rng_service


# ── 상태 전이 (전이 표 강제 — 미정의 전이 = 에러) ──
func _transition(next_state: int) -> void:
	var allowed: Array = RaceTypes.TRANSITIONS[gp_state]
	if not allowed.has(next_state):
		# 비정의 전이는 카운터로 남긴다 — push_error만으로는 테스트가 통과해버려서
		# "비정의 전이 도달 0"(D14 TC-C1)이 기계 판정 대상이 되지 않는다.
		transition_errors += 1
		push_error("RaceEngine: undefined transition %d -> %d" % [gp_state, next_state])
		return
	gp_state = next_state


# ── GP_START: 그리드 정렬·리소스 초기화 (D05 §3) ──
func start_gp() -> Array:
	var events: Array = []
	gp_state = RaceTypes.GpState.GP_START
	lap = 1
	sector = 0
	turn_number = 0
	duel_count = 0
	ai_retire_count = 0
	_retire_order = 0
	if chassis_carry_in >= 0.0:
		# 이월 개시 (D05 §8) — 주입 값은 [0, 최대치]로 절단한다 (세이브 조작·상한 초과 방어)
		chassis = clampf(chassis_carry_in, 0.0, data.param("param_chassis_max"))
	else:
		chassis = data.param("param_chassis_max")
	charge = 0
	front_gauge = 0.0
	rear_gauge = 0.0
	pending_duel = RaceTypes.DuelType.NONE
	resonance_announced = false
	resonance_duel_bonus = 0.0
	finished = false
	result = {}
	_build_entrants()
	_build_start_grid()
	_retarget(true, true)
	events.append(_ev("T5", "raceLog.gpStart01", {"circuit": data.circuit_str("name_key")}))
	_transition(RaceTypes.GpState.LAP_LOOP)
	return events


func _build_entrants() -> void:
	entrants.clear()
	# 벽 무대 가중 (D08 §5.1 ① · D13 별첨A §6.2) — 해당 무대의 벽 라이벌만 페이스 가산.
	# MS-2(무벽 메트로)에서는 잠복 경로였다 — 무대 2~5 유입과 함께 결선.
	var wall_id := _wall_rival_id()
	entrants[PLAYER_ID] = {
		"id": PLAYER_ID, "name_key": "ui.race.playerName", "is_player": true, "is_filler": false,
		"pace": 0.0, "aggression": 0.0, "stability": 0.0,
		"rush_lap1": 0.0, "rush_lap_final": 0.0, "rush_roll": 0.0,
		"start_mod": 3.0, "form": 0.0, "pressure_mult": 1.0,
		"duel_overtake_add": 0.0, "duel_defense_override": -1.0,
		"retired": false, "retire_order": -1, "number": 13,
	}
	for row in data.rivals:
		if not data.grid_array("rivals").has(String(row["id"])):
			continue
		var team: Dictionary = data.teams.get(String(row["team_id"]), {})
		var form_var := CsvTable.to_float(String(row["form_var"]))
		var rush_random := CsvTable.to_float(String(row["rush_random"]))
		entrants[String(row["id"])] = {
			"id": String(row["id"]), "name_key": String(row["name_key"]), "is_player": false, "is_filler": false,
			"pace": CsvTable.to_float(String(row["pace"])) + CsvTable.to_float(String(team.get("pace_add", "0")))
				+ (CsvTable.to_float(String(row["wall_pace_add"])) if String(row["id"]) == wall_id else 0.0),
			"aggression": CsvTable.to_float(String(row["aggression"])) + CsvTable.to_float(String(team.get("aggression_add", "0"))),
			"stability": CsvTable.to_float(String(row["stability"])) + CsvTable.to_float(String(team.get("stability_add", "0"))),
			"seed_aggression": CsvTable.to_float(String(row["aggression"])),
			"seed_stability": CsvTable.to_float(String(row["stability"])),
			"stability_under_pressure": CsvTable.to_float(String(row["stability_under_pressure"]), -1.0),
			"rush_lap1": CsvTable.to_float(String(row["rush_lap1"])),
			"rush_lap_final": CsvTable.to_float(String(row["rush_lap_final"])) + CsvTable.to_float(String(team.get("rush_lap_final_add", "0"))),
			"rush_roll": rng.randf_range("ai", -rush_random, rush_random) if rush_random > 0.0 else 0.0,
			"start_mod": CsvTable.to_float(String(row["start_mod"])),
			"form": rng.randf_range("ai", -form_var, form_var) if form_var > 0.0 else 0.0,
			"pressure_mult": CsvTable.to_float(String(team.get("pressure_mult", "1")), 1.0),
			"duel_overtake_add": CsvTable.to_float(String(row["duel_overtake_add"])),
			"duel_defense_override": CsvTable.to_float(String(row["duel_defense_override"]), -1.0),
			# 카 넘버 = D03 결정 로그 #13-③ 확정 8인분의 데이터 전사 (임의 기입 아님)
			"retired": false, "retire_order": -1, "number": CsvTable.to_int(String(row["number"])),
		}
	var filler_var := data.param("param_filler_stat_var")
	var filler_form := data.param("param_form_var_filler")
	# 필러 넘버는 21부터 순차 [가안 — 정본 미규정]. 네임드·플레이어 실넘버(D03 확정)와
	# 겹치면 건너뛴다 — 그리드에 같은 카 넘버가 둘 나오면 표기 층이 오식별한다.
	var used_numbers: Dictionary = {}
	for entrant_id in entrants:
		used_numbers[int(entrants[entrant_id]["number"])] = true
	var next_number := 21
	for i in range(data.grid_int("filler_count")):
		while used_numbers.has(next_number):
			next_number += 1
		used_numbers[next_number] = true
		var filler_id := "filler_%02d" % (i + 1)
		entrants[filler_id] = {
			"id": filler_id, "name_key": "ui.race.fillerName", "is_player": false, "is_filler": true,
			"pace": 3.0 + rng.randf_range("ai", -filler_var, filler_var),
			"aggression": 3.0 + rng.randf_range("ai", -filler_var, filler_var),
			"stability": 3.0 + rng.randf_range("ai", -filler_var, filler_var),
			"seed_aggression": 3.0, "seed_stability": 3.0,
			"stability_under_pressure": -1.0,
			"rush_lap1": 0.0, "rush_lap_final": 0.0, "rush_roll": 0.0,
			"start_mod": 3.0,
			"form": rng.randf_range("ai", -filler_form, filler_form),
			"pressure_mult": 1.0,
			"duel_overtake_add": 0.0, "duel_defense_override": -1.0,
			"retired": false, "retire_order": -1, "number": next_number,
		}
	# 슬롯 진행 보정: 그리드 전체의 기저 강도에 가산 (D08 §2.4 — 무대 다이얼과 독립된 슬롯 다이얼).
	# 플레이어는 대상이 아니다 — 보정의 목적어가 "필러·경쟁 풀의 기본 파라미터"다.
	var slot_pace_add := data.tour_slot_pace_add(race_slot)
	if slot_pace_add != 0.0:
		for entrant_id in entrants:
			if entrant_id == PLAYER_ID:
				continue
			entrants[entrant_id]["pace"] = float(entrants[entrant_id]["pace"]) + slot_pace_add


# 시작 그리드 (D13 별첨A §6.3): 게임 최초 GP = 플레이어 P16 고정.
# AI 기준 순위 = 합성 페이스 내림차순 [가안 — MS-1 단독 GP: 챔피언십 순위 부재] + 개별 시작 보정.
func _build_start_grid() -> void:
	var mod_coef := data.param("param_grid_start_mod_coef")
	var ai_list: Array = []
	for id in entrants:
		if id == PLAYER_ID:
			continue
		ai_list.append(id)
	ai_list.sort_custom(func(a, b): return entrants[a]["pace"] > entrants[b]["pace"])
	var scored: Array = []
	for i in range(ai_list.size()):
		var id: String = ai_list[i]
		# 개별 시작 보정 = (시작 보정 − 3) × 0.5 포지션 전진 (마로 5.0 → 1칸 전진 — 별첨A §6.3)
		var score := float(i) - (float(entrants[id]["start_mod"]) - 3.0) * mod_coef
		scored.append({"id": id, "score": score, "tie": i})
	scored.sort_custom(func(a, b):
		if a["score"] == b["score"]:
			return a["tie"] < b["tie"]
		return a["score"] < b["score"])
	positions.clear()
	for entry in scored:
		positions.append(entry["id"])
	var player_pos := data.grid_int("player_start_position")
	positions.insert(clampi(player_pos - 1, 0, positions.size()), PLAYER_ID)


# ── 턴 개시 (T1) — 듀얼 = 섹터 비소모 삽입 턴 (D05 §2.2 "+듀얼 삽입 시 가변" · D13 §4.1 산술 정합) ──
func begin_turn() -> Dictionary:
	if finished:
		return {"type": "finished"}
	var info := {}
	if pending_duel != RaceTypes.DuelType.NONE:
		_transition(RaceTypes.GpState.DUEL)
		current_turn_is_duel = true
		info = {
			"type": "duel",
			"duel_type": pending_duel,
			"opponent": duel_opponent,
			"lap": lap, "sector": sector,
			"events": [_ev("T1", "vane.brief.duel01", {})],
		}
	else:
		# 랩 경계 분기 (LAP_LOOP)
		if sector >= data.circuit_int("sectors_per_lap"):
			if lap >= data.circuit_int("laps"):
				_transition(RaceTypes.GpState.GP_FINISH)
				_finish_gp()
				return {"type": "finished"}
			lap += 1
			sector = 0
		sector += 1
		if gp_state == RaceTypes.GpState.LAP_LOOP or gp_state == RaceTypes.GpState.DUEL or gp_state == RaceTypes.GpState.SECTOR_TURN:
			_transition(RaceTypes.GpState.SECTOR_TURN)
		current_turn_is_duel = false
		info = {
			"type": "sector",
			"lap": lap, "sector": sector,
			"events": [
				_ev("T1", "raceLog.sectorStart01", {"lap": lap, "sector": sector}),
				_ev("T1", "vane.brief.sector01", {"sector": sector}),
			],
		}
		# 레조넌스 위치는 비공개이며 진입 시점에만 공표한다 (D08 §3.7 R6).
		if _is_resonance_sector() and not resonance_announced:
			resonance_announced = true
			info["events"].append(_ev("T1", "raceLog.resonanceEnter01", {}))
	turn_number += 1
	phase_log = []
	_enter_phase(RaceTypes.TurnPhase.T1_SECTOR_OPEN)
	provisional = []
	hold_used = false
	negated_troubles = 0
	duel_boost = 0
	return info


# ── T2 스핀: reel 스트림 소비 = 스핀 커밋 시점 (D12 §6.2) ──
func spin() -> void:
	if turn_phase != RaceTypes.TurnPhase.T1_SECTOR_OPEN:
		push_error("RaceEngine: spin out of phase")
		return
	_enter_phase(RaceTypes.TurnPhase.T2_SPIN)
	provisional = []
	for reel_index in range(3):
		provisional.append(_roll_reel(reel_index))
	# T3 전개 후보 — 내부 확정만 하고 노출은 표시 층의 get_provisional() 시점 (봉인 §6.3)
	_enter_phase(RaceTypes.TurnPhase.T3_PROVISIONAL)
	_enter_phase(RaceTypes.TurnPhase.T4_INTERVENTION)


# 턴 단계 진입 — 단계 전이를 한 곳으로 모아 로그와 상태가 갈라지지 않게 한다.
func _enter_phase(phase: int) -> void:
	turn_phase = phase
	phase_log.append(phase)


func _roll_reel(reel_index: int) -> String:
	var weights := reel_weights(reel_index)
	var picked := rng.pick_weighted("reel", weights)
	return String(data.symbols[picked]["id"])


# 섹터 속성 가중 (D13 별첨A §1.3): 기본 분포에 주속성 Δ 가산, 부속성은 ½ 적용.
# 음수는 0으로 절단 후 재정규화 — pick_weighted가 합으로 나누므로 비례는 유지된다.
# 공개 조회: 분포는 '결과'가 아니라 '규칙'이므로 봉인 규칙과 무접촉하다.
# (결과 = 어느 심볼이 나왔는가 = provisional. 이 함수는 확률만 돌려준다.)
func reel_weights(reel_index: int) -> Array:
	var column := "prob_reel%d" % (reel_index + 1)
	var main_attr := data.sector_attr(_sector_attr_id("main_attr"))
	var sub_attr := data.sector_attr(_sector_attr_id("sub_attr"))
	var weights: Array = []
	for row in data.symbols:
		var weight := CsvTable.to_float(String(row[column]))
		var column_name := "w_%s" % String(row["class"])
		if not main_attr.is_empty():
			weight += CsvTable.to_float(String(main_attr[column_name]))
		if not sub_attr.is_empty():
			weight += CsvTable.to_float(String(sub_attr[column_name])) * 0.5
		weights.append(maxf(weight, 0.0))
	return weights


# 듀얼 턴은 섹터 비소모 삽입 턴이므로 직전 섹터의 속성을 유지한다 (IMPL-008).
func _sector_attr_id(field: String) -> String:
	var entry := data.sector_entry(clampi(sector, 1, data.circuit_int("sectors_per_lap")))
	return String(entry.get(field, ""))


# 속성 규칙 계수 — 주속성 전액 · 부속성은 ½ 적용분을 1.0 기준으로 환산.
# [가안] D13 별첨A §1.3의 "부속성은 ½ 적용"은 심볼 분포 가산에 대한 문면이고
# 규칙 계수(섀시 ×1.15 · 게이지 ×1.5)의 부속성 처리는 정본이 침묵한다.
# 문서 자체의 ½ 관용을 배수에 동형 적용했다(1.5 → 1.25). impl_log 등재.
func _attr_rule_mult(column_name: String) -> float:
	var mult := 1.0
	var main_attr := data.sector_attr(_sector_attr_id("main_attr"))
	if not main_attr.is_empty():
		mult *= CsvTable.to_float(String(main_attr[column_name]), 1.0)
	var sub_attr := data.sector_attr(_sector_attr_id("sub_attr"))
	if not sub_attr.is_empty():
		mult *= 1.0 + (CsvTable.to_float(String(sub_attr[column_name]), 1.0) - 1.0) * 0.5
	return mult


# T3 전개 후보 — 표시 층이 릴 정지 연출 완료 후 조회 (봉인 규칙 §6.3)
func get_provisional() -> Array:
	return provisional.duplicate()


# ── T4 개입 창 ──
# 홀드 & 리스핀: 지정 릴 고정 + 나머지 재회전. 비용 1차지, 턴당 1회 (D05 §5.4)
func hold_respin(keep_indices: Array) -> Dictionary:
	if turn_phase != RaceTypes.TurnPhase.T4_INTERVENTION:
		return {"ok": false, "error": "phase"}
	if hold_used:
		return {"ok": false, "error": "limit"}
	var cost := data.param_int("param_charge_hold_cost")
	if charge < cost:
		return {"ok": false, "error": "charge"}
	charge -= cost
	hold_used = true
	for reel_index in range(3):
		if not keep_indices.has(reel_index):
			provisional[reel_index] = _roll_reel(reel_index)
	return {"ok": true, "events": [_ev("T4", "vane.brief.holdRespin01", {})]}


# 차지 개입: 트러블 1개 무효화 = 2차지 (D05 §5.4)
func negate_trouble() -> Dictionary:
	if turn_phase != RaceTypes.TurnPhase.T4_INTERVENTION:
		return {"ok": false, "error": "phase"}
	var cost := data.param_int("param_charge_negate_cost")
	if charge < cost:
		return {"ok": false, "error": "charge"}
	if _count_symbol(RaceTypes.SYMBOL_TROUBLE) - negated_troubles <= 0:
		return {"ok": false, "error": "no_trouble"}
	charge -= cost
	negated_troubles += 1
	return {"ok": true, "events": [_ev("T4", "vane.brief.negate01", {})]}


# 듀얼 부스트: 차지당 판정 +10, 1회 최대 4차지 (D13 별첨A §2.2)
func add_duel_boost() -> Dictionary:
	if turn_phase != RaceTypes.TurnPhase.T4_INTERVENTION or not current_turn_is_duel:
		return {"ok": false, "error": "phase"}
	if duel_boost >= data.param_int("param_charge_boost_max"):
		return {"ok": false, "error": "limit"}
	if charge < 1:
		return {"ok": false, "error": "charge"}
	charge -= 1
	duel_boost += 1
	return {"ok": true}


# 확정 (T4 → T5 번역 → T6 정산). remaining_ratio = 잔여 시간 비율 (여유 구간 = 모멘텀)
func confirm(remaining_ratio: float) -> Array:
	if turn_phase != RaceTypes.TurnPhase.T4_INTERVENTION:
		push_error("RaceEngine: confirm out of phase")
		return []
	_enter_phase(RaceTypes.TurnPhase.T5_TRANSLATE)
	var events: Array = []
	var momentum := (not current_turn_is_duel) \
		and remaining_ratio >= data.param("param_timer_leeway_ratio")
	_enter_phase(RaceTypes.TurnPhase.T6_SETTLE)
	if current_turn_is_duel:
		events.append_array(_settle_duel())
	else:
		events.append_array(_settle_sector(momentum))
	_after_settlement(events)
	return events


# 타임아웃: 잠정 결과 그대로 자동 확정 — 추가 페널티 없음 (D05 §7.3)
func timeout() -> Array:
	var events: Array = [_ev("T5", "raceLog.timeout01", {}), _ev("T5", "vane.brief.timeout01", {})]
	events.append_array(confirm(0.0))
	return events


# ── T6 정산: 8단계 고정 순서 (C-2 — RaceTypes.SETTLE_ORDER 상수 전속) ──
func _settle_sector(momentum: bool) -> Array:
	var events: Array = []
	var trouble_count := _count_symbol(RaceTypes.SYMBOL_TROUBLE) - negated_troubles
	var trouble_fired := false
	var gauge_mult := _gauge_mult()
	var chance_full := false
	settle_log = []
	for stage in RaceTypes.SETTLE_ORDER:
		settle_log.append(stage)
		match stage:
			RaceTypes.SettleStage.STAGE_1_HAZARD:
				# 해저드 속성의 턴당 가산 소모 −1.0 (D13 별첨A §2.3 — ×1.15 계수와 별도).
				# 위험 단계에 둔다: 트러블 유무와 무관한 속성 소모이고 단계 ①이 위험 소관이다.
				var hazard_wear := _attr_rule_mult("chassis_wear_mult")
				if hazard_wear > 1.0:
					chassis -= data.param("param_chassis_hazard_per_turn")
				if trouble_count > 0:
					trouble_fired = true
					var effect := _match_effect(RaceTypes.SYMBOL_TROUBLE, trouble_count)
					var chassis_delta := CsvTable.to_float(String(effect["chassis"])) * hazard_wear
					chassis += chassis_delta
					rear_gauge += CsvTable.to_float(String(effect["rear_gauge"])) * gauge_mult
					events.append(_ev("T5", "raceLog.troubleHit01", {"amount": chassis_delta}))
			RaceTypes.SettleStage.STAGE_2_RESOURCE:
				var pulse_count := _count_symbol(RaceTypes.SYMBOL_PULSE)
				if pulse_count > 0:
					_gain_charge(CsvTable.to_int(String(_match_effect(RaceTypes.SYMBOL_PULSE, pulse_count)["charge"])))
				if not trouble_fired:
					var stable_gain := data.param_int("param_charge_stable_sector")
					_gain_charge(stable_gain)
					events.append(_ev("T5", "raceLog.stableSector01", {"amount": stable_gain}))
				events.append_array(_apply_resonance_bonus(gauge_mult))
			RaceTypes.SettleStage.STAGE_3_DEFENSE:
				var braking_count := _count_symbol(RaceTypes.SYMBOL_BRAKING)
				if braking_count > 0:
					rear_gauge += CsvTable.to_float(String(_match_effect(RaceTypes.SYMBOL_BRAKING, braking_count)["rear_gauge"])) * gauge_mult
			RaceTypes.SettleStage.STAGE_4_ADVANCE:
				var slip_count := _count_symbol(RaceTypes.SYMBOL_SLIPSTREAM)
				if slip_count > 0:
					front_gauge += CsvTable.to_float(String(_match_effect(RaceTypes.SYMBOL_SLIPSTREAM, slip_count)["front_gauge"])) * gauge_mult
				var line_count := _count_symbol(RaceTypes.SYMBOL_LINE)
				if line_count > 0:
					var line_effect := _match_effect(RaceTypes.SYMBOL_LINE, line_count)
					front_gauge += CsvTable.to_float(String(line_effect["front_gauge"])) * gauge_mult
					rear_gauge += CsvTable.to_float(String(line_effect["rear_gauge"])) * gauge_mult
				var chance_count := _count_symbol(RaceTypes.SYMBOL_CHANCE)
				if chance_count > 0:
					var chance_effect := _match_effect(RaceTypes.SYMBOL_CHANCE, chance_count)
					if String(chance_effect["special"]).strip_edges() == "duel_trigger":
						chance_full = true
						events.append(_ev("T5", "raceLog.chanceDuel01", {}))
					else:
						front_gauge += CsvTable.to_float(String(chance_effect["front_gauge"])) * gauge_mult
						events.append(_ev("T5", "raceLog.chanceProc01", {}))
				if momentum:
					var bonus := data.param("param_gauge_momentum_bonus")
					front_gauge += bonus * gauge_mult
					events.append(_ev("T5", "raceLog.momentum01", {"amount": int(bonus)}))
			RaceTypes.SettleStage.STAGE_5_GAUGE_CHECK:
				_apply_neighbor_passives(gauge_mult)
				if chance_full:
					front_gauge = data.param("param_gauge_full_threshold")
				front_gauge = clampf(front_gauge, 0.0, data.param("param_gauge_full_threshold"))
				rear_gauge = clampf(rear_gauge, 0.0, data.param("param_gauge_full_threshold"))
				var threshold := data.param("param_gauge_full_threshold")
				_armed_duel = RaceTypes.DuelType.NONE
				if front_gauge >= threshold and front_target != "":
					_armed_duel = RaceTypes.DuelType.OVERTAKE
				elif rear_gauge >= threshold and rear_target != "":
					_armed_duel = RaceTypes.DuelType.DEFENSE
			RaceTypes.SettleStage.STAGE_6_DUEL_TRIGGER:
				if _armed_duel != RaceTypes.DuelType.NONE:
					pending_duel = _armed_duel
					duel_opponent = front_target if _armed_duel == RaceTypes.DuelType.OVERTAKE else rear_target
					var log_key := "raceLog.duelStartOvertake01" if _armed_duel == RaceTypes.DuelType.OVERTAKE else "raceLog.duelStartDefense01"
					# number 는 필러 name_key(`No.{number} 머신`)의 표기 매개다 — 표기 층이
					# name_key 를 번역할 때 함께 치환한다 (네임드 문면에는 자리 자체가 없어 무해)
					events.append(_ev("T5", log_key, {
						"target": entrants[duel_opponent]["name_key"],
						"number": entrants[duel_opponent]["number"],
					}))
			RaceTypes.SettleStage.STAGE_7_RANK_UPDATE:
				pass  # 섹터 턴의 플레이어 순위 변동은 듀얼 전속 (D05 §4)
			RaceTypes.SettleStage.STAGE_8_BACKGROUND_AI:
				events.append_array(_background_ai())
	return events


# 레조넌스 보너스 (D08 §3.7 R3 · D13 별첨A §6.6) — 임의 분류 3매치 성립 시 무대별 보너스 추가.
# 통상 정산은 그대로 유지하며 여기서 '추가'만 한다 (트러블 3매치도 성공 인정 — R3 명문).
# C-2 구속: 신규 단계·신규 타이밍 창 없이 단계 ②의 파라미터 가산으로만 소비한다.
func _apply_resonance_bonus(gauge_mult: float) -> Array:
	if not _is_resonance_sector():
		return []
	if not _has_any_three_match():
		return []
	if resonance_consumed:
		return []   # 무대당 1회 (R6) — 같은 섹터를 랩마다 다시 지나도 재지급하지 않는다
	resonance_consumed = true
	var stage := data.stage_of_active_circuit()
	var bonus_type := String(stage.get("resonance_bonus_type", ""))
	var bonus_value := float(stage.get("resonance_bonus_value", 0.0))
	var events: Array = [_ev("T5", "raceLog.resonanceProc01", {})]
	match bonus_type:
		"charge":
			_gain_charge(int(bonus_value))
		"front_gauge":
			# [가안] 보너스는 명시 절대값으로 가산 — 게이지 계수(×1.5·×1.2)를 곱하지 않는다.
			# (무대 1 보너스는 차지이므로 MS-2 범위에서는 비활성 경로. impl_log 등재)
			front_gauge += bonus_value
		"front_gauge_full":
			front_gauge = data.param("param_gauge_full_threshold")
		"duel_judgment":
			resonance_duel_bonus += bonus_value
		"chassis":
			chassis = minf(chassis + bonus_value, data.param("param_chassis_max"))
		_:
			push_error("RaceEngine: unknown resonance bonus type '%s'" % bonus_type)
	return events


# 플레이어 전용 · 섹터 릴 정산 전속 (R7) — 듀얼 정산은 단계 ②를 돌지 않으므로 구조적으로 무관여.
func _is_resonance_sector() -> bool:
	if resonance_sector_slot <= 0 or current_turn_is_duel:
		return false
	# 추첨은 (서킷 슬롯 × 섹터 슬롯) 두 축이다 (D08 §3.7 R6). 섹터 슬롯만 보면
	# 같은 무대의 서킷 4종 전부에서 발동해 '무대당 1회'가 성립하지 않는다.
	if resonance_circuit_id != String(data.circuit.get("id", "")):
		return false
	return sector == resonance_sector_slot


func _has_any_three_match() -> bool:
	if provisional.size() < 3:
		return false
	return provisional[0] == provisional[1] and provisional[1] == provisional[2]


# 활성 무대의 벽 라이벌 (D08 §5.1 — 무벽 무대는 ""). 페이스 가중·듀얼 임계·리타이어 면제의 공용 창구.
func _wall_rival_id() -> String:
	return String(data.stage_of_active_circuit().get("wall_rival", ""))


# 듀얼 턴 정산 — 전용 스핀: 심볼은 판정 환산 전속, 통상 효과 미적용 [가안 — impl_log]
func _settle_duel() -> Array:
	var events: Array = []
	settle_log = []
	for stage in RaceTypes.SETTLE_ORDER:
		settle_log.append(stage)
		match stage:
			RaceTypes.SettleStage.STAGE_6_DUEL_TRIGGER:
				events.append_array(_resolve_duel())
			RaceTypes.SettleStage.STAGE_7_RANK_UPDATE:
				pass  # 스왑은 _resolve_duel 내부에서 확정 (동일 단계 처리)
			RaceTypes.SettleStage.STAGE_8_BACKGROUND_AI:
				events.append_array(_background_ai())
			_:
				pass  # ①~⑤ 미적용 (듀얼 전용 스핀)
	return events


func _resolve_duel() -> Array:
	var events: Array = []
	duel_count += 1
	var duel_type := pending_duel
	var opponent_id := duel_opponent
	pending_duel = RaceTypes.DuelType.NONE
	duel_opponent = ""
	if not entrants.has(opponent_id) or entrants[opponent_id]["retired"]:
		return events  # 상대 소멸 — 듀얼 무산
	var opponent_index := positions.find(opponent_id)
	var player_index := positions.find(PLAYER_ID)
	if absi(opponent_index - player_index) != 1:
		return events  # 배경 스왑으로 비인접화 — 듀얼 무산 [가안 — impl_log]
	var judgment := _duel_judgment(duel_type)
	var threshold := _duel_threshold(duel_type, opponent_id)
	var won := judgment >= threshold
	if won:
		var bonus := data.param_int("param_charge_duel_win")
		_gain_charge(bonus)
		events.append(_ev("T5", "raceLog.duelWin01", {"amount": bonus}))
		if duel_type == RaceTypes.DuelType.OVERTAKE:
			_swap_with(opponent_id)
			events.append(_ev("T5", "raceLog.overtakeSuccess01",
				{"target": entrants[opponent_id]["name_key"], "rank": player_position()}))
		else:
			events.append(_ev("T5", "raceLog.defendSuccess01", {"target": entrants[opponent_id]["name_key"]}))
	else:
		if duel_type == RaceTypes.DuelType.OVERTAKE:
			var penalty := -data.param("param_chassis_duel_fail_penalty")
			chassis += penalty
			events.append(_ev("T5", "raceLog.duelLoseOvertake01", {"amount": penalty}))
		else:
			_swap_with(opponent_id)
			events.append(_ev("T5", "raceLog.duelLoseDefense01", {}))
			events.append(_ev("T5", "raceLog.defendFail01", {"target": entrants[opponent_id]["name_key"]}))
	resonance_duel_bonus = 0.0  # 차기 듀얼 1회 소비 (D13 별첨A §6.6 '차기 듀얼 판정')
	front_gauge = 0.0
	rear_gauge = 0.0
	_retarget(true, true)
	return events


# 듀얼 판정치 J (D13 별첨A §2.4): 심볼 환산 + 부스트 (튜닝·오버홀·레조넌스 = MS-1 범위 외 → 0)
func _duel_judgment(duel_type: int) -> float:
	var judgment := 0.0
	var primary_symbol := RaceTypes.SYMBOL_SLIPSTREAM if duel_type == RaceTypes.DuelType.OVERTAKE else RaceTypes.SYMBOL_BRAKING
	var primary_count := _count_symbol(primary_symbol)
	if primary_count > 0:
		judgment += CsvTable.to_float(String(data.duel_conversion[primary_symbol]["match%d" % primary_count]))
	var line_count := _count_symbol(RaceTypes.SYMBOL_LINE)
	if line_count > 0:
		judgment += CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_LINE]["match%d" % line_count]))
	judgment += CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_CHANCE]["per_symbol"])) * _count_symbol(RaceTypes.SYMBOL_CHANCE)
	var trouble_count := _count_symbol(RaceTypes.SYMBOL_TROUBLE) - negated_troubles
	judgment += CsvTable.to_float(String(data.duel_conversion[RaceTypes.SYMBOL_TROUBLE]["per_symbol"])) * maxi(trouble_count, 0)
	judgment += float(duel_boost) * data.param("param_charge_boost_per_judgment")
	judgment += resonance_duel_bonus
	return judgment


# 저항 임계 (D13 별첨A §2.4) — 시드 파라미터 기준 (팀 가산 미적용: 별첨A 명시값 정합 [가안])
func _duel_threshold(duel_type: int, opponent_id: String) -> float:
	var opponent: Dictionary = entrants[opponent_id]
	# 벽 라이벌 임계 가산 (D13 별첨A §2.4 "벽 라이벌 (해당 무대) +6" — 추월·방어 공통 행).
	# [가안] 방어 override(로렌츠 55)에도 가산한다 — §2.4의 벽 행은 필러/네임드/로렌츠 행과
	# 독립된 조건부 가산 행이고 면제 문면이 없다 (그리드 레벨 +3 행과 동형 구조).
	var wall_add := data.param("param_duel_wall_threshold_add") \
		if opponent_id == _wall_rival_id() else 0.0
	if duel_type == RaceTypes.DuelType.OVERTAKE:
		# 압박 훅 (D13 별첨A §6.2 비앙카 "안정성 4.0(압박 시 2.5)" · D08 §6.3 조건 분기 위임).
		# [가안] '압박 시'의 판정 = **추월 듀얼 상황** — 플레이어가 뒤차로서 앞차를 밀어붙이는
		# 국면이 압박의 정의에 부합한다. 정본이 '압박'을 별도로 정의하지 않아 해석이다.
		# 훅이 없는 라이벌은 공란(−1)이므로 시드 안정성을 그대로 쓴다 (침묵 대체가 아니다).
		var stability := float(opponent["seed_stability"])
		var under_pressure := float(opponent["stability_under_pressure"])
		if under_pressure >= 0.0:
			stability = under_pressure
		return data.param("param_duel_overtake_base") \
			+ stability * data.param("param_duel_overtake_stability_coef") \
			+ float(opponent["duel_overtake_add"]) + wall_add
	var override_value := float(opponent["duel_defense_override"])
	if override_value >= 0.0:
		return override_value + wall_add
	return data.param("param_duel_defense_base") \
		+ float(opponent["seed_aggression"]) * data.param("param_duel_defense_aggression_coef") \
		+ wall_add


# ── 게이지 보조 ──
# 최종 랩 계수 ×1.2 전역 (D13 별첨A §1.3) — 게이지 증감 전체에 곱 적용 [가안]
# 배틀 존 ×1.5와는 곱 적용 (별첨A §1.3 명문 — 최대 ×1.8)
func _gauge_mult() -> float:
	var mult := _attr_rule_mult("gauge_mult")
	if lap >= data.circuit_int("laps"):
		mult *= data.param("param_gauge_final_lap_mult")
	return mult


# 앞차 저항·뒤차 압박 (D13 별첨A §2.1) — 만충 판정 직전 적용 [가안 — 8단계 내 배치]
func _apply_neighbor_passives(gauge_mult: float) -> void:
	if front_target != "":
		var front: Dictionary = entrants[front_target]
		var resist := data.param("param_gauge_front_resist_base") \
			+ _effective_pace(front) * data.param("param_gauge_front_resist_pace_coef")
		front_gauge -= resist * gauge_mult
	if rear_target != "":
		var rear: Dictionary = entrants[rear_target]
		# 압박 산식의 공격성은 **시드값** 기준이다 (D13 별첨A §2.1 산출 예: 필러 8.6 =
		# 2.0+3.0×2.2 / 디아스 13.0 = 2.0+5.0×2.2 → ×1.3 = 16.9). 팀 스탯 가산을 넣으면
		# 디아스가 5.5가 되어 18.33이 나오고 정본에 인쇄된 16.9가 도달 불가능해진다.
		# 소속 계수(pressure_mult ×1.3)는 그 예시 안에 이미 포함돼 있으므로 그대로 곱한다.
		var pressure := (data.param("param_gauge_rear_pressure_base") \
			+ float(rear["seed_aggression"]) * data.param("param_gauge_rear_pressure_aggr_coef")) \
			* float(rear["pressure_mult"])
		rear_gauge += pressure * gauge_mult


func _effective_pace(entrant: Dictionary) -> float:
	var pace := float(entrant["pace"]) + float(entrant["form"]) + float(entrant["rush_roll"])
	if lap == 1:
		pace += float(entrant["rush_lap1"])
	if lap >= data.circuit_int("laps"):
		pace += float(entrant["rush_lap_final"])
	return pace


# ── ⑧ 백그라운드 AI (D05 §4.4 · D13 별첨A §6.2) ──
func _background_ai() -> Array:
	var events: Array = []
	var swap_min := data.param("param_ai_swap_min")
	var swap_base := data.param("param_ai_swap_base")
	var swap_coef := data.param("param_ai_swap_pace_coef")
	var player_index := positions.find(PLAYER_ID)
	var i := 0
	while i < positions.size() - 1:
		if i == player_index or i + 1 == player_index:
			i += 1
			continue  # 플레이어 포함 쌍 제외 — 플레이어 순위 변동은 듀얼 전속
		var front_id: String = positions[i]
		var rear_id: String = positions[i + 1]
		var pace_diff := _effective_pace(entrants[rear_id]) - _effective_pace(entrants[front_id])
		var probability := maxf(swap_min, swap_base + swap_coef * pace_diff)
		if rng.randf("ai") < probability:
			positions[i] = rear_id
			positions[i + 1] = front_id
			player_index = positions.find(PLAYER_ID)
		i += 1
	events.append_array(_ai_retire_check())
	_retarget_if_changed()
	return events


func _ai_retire_check() -> Array:
	var events: Array = []
	var cap := data.param_int("param_ai_retire_gp_cap")
	if ai_retire_count >= cap:
		return events
	var total_turns := data.circuit_int("laps") * data.circuit_int("sectors_per_lap")
	var coef := data.param("param_ai_retire_stability_coef")
	var constant := data.param("param_ai_retire_const")
	var wall_id := _wall_rival_id()
	for id in positions.duplicate():
		if id == PLAYER_ID or ai_retire_count >= cap:
			continue
		if id == wall_id:
			continue   # 벽 라이벌 제외 (D13 별첨A §6.2 AI 리타이어 행 명문)
		var probability := (coef * (5.0 - float(entrants[id]["stability"])) + constant) / float(total_turns)
		if rng.randf("ai") < probability:
			_retire_entrant(id)
			ai_retire_count += 1
			events.append(_ev("T5", "raceLog.aiRetire01", {"target": entrants[id]["name_key"]}))
	return events


func _retire_entrant(id: String) -> void:
	entrants[id]["retired"] = true
	entrants[id]["retire_order"] = _retire_order
	_retire_order += 1
	positions.erase(id)


# ── 정산 후 공통 처리: 리타이어·타깃 갱신 ──
func _after_settlement(events: Array) -> void:
	if chassis <= 0.0:
		chassis = 0.0
		events.append(_ev("T5", "raceLog.playerRetire01", {}))
		_retire_entrant(PLAYER_ID)
		_transition(RaceTypes.GpState.RETIRE)
		_finish_gp()
		return
	# 최종 섹터 정산 후 듀얼이 남아 있으면 폐기 — 다음 섹터 부재 (D05 §4.3 [가안])
	if pending_duel != RaceTypes.DuelType.NONE \
		and lap >= data.circuit_int("laps") \
		and sector >= data.circuit_int("sectors_per_lap"):
		pending_duel = RaceTypes.DuelType.NONE
		duel_opponent = ""
	if gp_state == RaceTypes.GpState.SECTOR_TURN \
		and pending_duel == RaceTypes.DuelType.NONE \
		and sector >= data.circuit_int("sectors_per_lap"):
		_transition(RaceTypes.GpState.LAP_LOOP)
	elif gp_state == RaceTypes.GpState.DUEL:
		if sector >= data.circuit_int("sectors_per_lap"):
			_transition(RaceTypes.GpState.LAP_LOOP)
		else:
			_transition(RaceTypes.GpState.SECTOR_TURN)


func _swap_with(opponent_id: String) -> void:
	var player_index := positions.find(PLAYER_ID)
	var opponent_index := positions.find(opponent_id)
	if player_index < 0 or opponent_index < 0:
		return
	positions[player_index] = opponent_id
	positions[opponent_index] = PLAYER_ID


func _retarget(reset_front: bool, reset_rear: bool) -> void:
	var player_index := positions.find(PLAYER_ID)
	var new_front := String(positions[player_index - 1]) if player_index > 0 else ""
	var new_rear := String(positions[player_index + 1]) if player_index < positions.size() - 1 else ""
	if reset_front or new_front != front_target:
		front_target = new_front
		if reset_front:
			front_gauge = 0.0
	if reset_rear or new_rear != rear_target:
		rear_target = new_rear
		if reset_rear:
			rear_gauge = 0.0


# 인접 상대가 바뀌면 해당 게이지 리셋 후 새 상대와 개시 (D05 §4.2)
func _retarget_if_changed() -> void:
	if positions.find(PLAYER_ID) < 0:
		return
	var player_index := positions.find(PLAYER_ID)
	var new_front := String(positions[player_index - 1]) if player_index > 0 else ""
	var new_rear := String(positions[player_index + 1]) if player_index < positions.size() - 1 else ""
	if new_front != front_target:
		front_target = new_front
		front_gauge = 0.0
		if pending_duel == RaceTypes.DuelType.OVERTAKE:
			pending_duel = RaceTypes.DuelType.NONE  # 상대 교체 — 예약 듀얼 해제 [가안]
			duel_opponent = ""
	if new_rear != rear_target:
		rear_target = new_rear
		rear_gauge = 0.0
		if pending_duel == RaceTypes.DuelType.DEFENSE:
			pending_duel = RaceTypes.DuelType.NONE
			duel_opponent = ""


# ── GP 종료 → RESULT (D05 §9.1~9.2) ──
func _finish_gp() -> void:
	_transition(RaceTypes.GpState.RESULT)
	finished = true
	var standings: Array = []
	for id in positions:
		standings.append(id)
	# 리타이어 머신: 리타이어 시점 역순으로 최하위부터 (가장 이른 리타이어 = 최하위)
	var retired_list: Array = []
	for id in entrants:
		if entrants[id]["retired"]:
			retired_list.append(id)
	retired_list.sort_custom(func(a, b): return entrants[a]["retire_order"] > entrants[b]["retire_order"])
	standings.append_array(retired_list)
	var player_rank := standings.find(PLAYER_ID) + 1
	var player_retired: bool = entrants[PLAYER_ID]["retired"]
	# 포인트는 P1~P16 전 순위가 테이블에 명시돼 있다 (D13 별첨A §6.1 'P9↓ 0' 포함).
	# .get(rank, 0) 류의 침묵 대체를 두지 않는다 — 표가 비면 조용히 0이 되어 표류를 숨긴다.
	var points := 0
	if not player_retired:
		if data.points_tier1.has(player_rank):
			points = int(data.points_tier1[player_rank])
		else:
			push_error("RaceEngine: points_tier1 has no position %d" % player_rank)
	result = {
		"standings": standings,
		"player_rank": player_rank,
		"player_retired": player_retired,
		"tour_points": points,
		"turns": turn_number,
		"duels": duel_count,
	}


# GP 소요 분량 모델 (D13 §4.1 A1 파생 — 완료 판정 4 로그용)
func estimated_minutes() -> float:
	var sector_turns := turn_number - duel_count
	# D13 §4.1 산식: 턴×21초 + 듀얼×45초 + **완급 비트 턴×1초** + 결산·이벤트 210초.
	# 완급 비트 항이 빠져 있어 모델이 정본 산출(12턴 = 10.0분)보다 짧게 나왔다.
	var seconds := float(sector_turns) * data.param("param_time_turn_sec") \
		+ float(duel_count) * data.param("param_time_duel_sec") \
		+ float(sector_turns) * data.param("param_time_pacing_beat_sec") \
		+ data.param("param_time_wrapup_sec")
	return seconds / 60.0


# ── 조회 ──
func player_position() -> int:
	var index := positions.find(PLAYER_ID)
	return index + 1 if index >= 0 else -1


func _count_symbol(symbol_id: String) -> int:
	var count := 0
	for s in provisional:
		if s == symbol_id:
			count += 1
	return count


func _match_effect(symbol_id: String, match_count: int) -> Dictionary:
	return data.match_effects[symbol_id][clampi(match_count, 1, 3)]


func _gain_charge(amount: int) -> void:
	charge = clampi(charge + amount, 0, data.param_int("param_charge_cap"))


func _ev(phase: String, key: String, params: Dictionary) -> Dictionary:
	return {"phase": phase, "key": key, "params": params}


# ── 직렬화 (서스펜드 스냅샷 §7.2 — RNG 포함, 재로드 리롤 무효 §6.2) ──
func serialize() -> Dictionary:
	return {
		"gp_state": gp_state,
		"turn_phase": turn_phase,
		"lap": lap, "sector": sector,
		"turn_number": turn_number, "duel_count": duel_count,
		"ai_retire_count": ai_retire_count, "retire_order_counter": _retire_order,
		"entrants": entrants.duplicate(true),
		"positions": positions.duplicate(),
		"chassis": chassis, "charge": charge,
		"front_gauge": front_gauge, "rear_gauge": rear_gauge,
		"front_target": front_target, "rear_target": rear_target,
		"provisional": provisional.duplicate(),
		"hold_used": hold_used, "negated_troubles": negated_troubles,
		"duel_boost": duel_boost,
		"pending_duel": pending_duel, "duel_opponent": duel_opponent,
		"current_turn_is_duel": current_turn_is_duel,
		"resonance_circuit_id": resonance_circuit_id,
		"resonance_sector_slot": resonance_sector_slot,
		"resonance_consumed": resonance_consumed,
		"resonance_announced": resonance_announced,
		"resonance_duel_bonus": resonance_duel_bonus,
		"finished": finished, "result": result.duplicate(true),
		"rng": rng.serialize(),
	}


func restore(payload: Dictionary) -> bool:
	if not payload.has("rng") or not rng.deserialize(payload["rng"]):
		return false
	gp_state = int(payload["gp_state"])
	turn_phase = int(payload["turn_phase"])
	lap = int(payload["lap"])
	sector = int(payload["sector"])
	turn_number = int(payload["turn_number"])
	duel_count = int(payload["duel_count"])
	ai_retire_count = int(payload["ai_retire_count"])
	_retire_order = int(payload["retire_order_counter"])
	entrants = payload["entrants"]
	positions = payload["positions"]
	chassis = float(payload["chassis"])
	charge = int(payload["charge"])
	front_gauge = float(payload["front_gauge"])
	rear_gauge = float(payload["rear_gauge"])
	front_target = String(payload["front_target"])
	rear_target = String(payload["rear_target"])
	provisional = payload["provisional"]
	hold_used = bool(payload["hold_used"])
	negated_troubles = int(payload["negated_troubles"])
	duel_boost = int(payload["duel_boost"])
	pending_duel = int(payload["pending_duel"])
	duel_opponent = String(payload["duel_opponent"])
	current_turn_is_duel = bool(payload["current_turn_is_duel"])
	resonance_circuit_id = String(payload["resonance_circuit_id"])
	resonance_sector_slot = int(payload["resonance_sector_slot"])
	resonance_consumed = bool(payload["resonance_consumed"])
	resonance_announced = bool(payload["resonance_announced"])
	resonance_duel_bonus = float(payload["resonance_duel_bonus"])
	finished = bool(payload["finished"])
	result = payload.get("result", {})
	return true
