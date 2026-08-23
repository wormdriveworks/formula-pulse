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

# 턴 스코프 스킬 변조 키 (D13 별첨A §4.2 효과 수치의 적용 지점)
const MOD_ADVANCE_MULT := "advance_mult"                # SA1 전진 효과 배수
const MOD_PULSE_MULT := "pulse_mult"                    # SA2 펄스 차지 생산 배수
const MOD_DEFENSE_MULT := "defense_mult"                # SA3 방어 효과 배수
const MOD_DEFENSE_DUEL_ADD := "defense_duel_add"        # SA3 방어 듀얼 판정 가산
const MOD_BOOST_PER := "boost_per"                      # SA4 부스트 차지당 보정 대체
const MOD_DUEL_PENALTY_WAIVED := "duel_penalty_waived"  # SI1 듀얼 패배 페널티 면제
const MOD_TROUBLE_CHASSIS_ZERO := "trouble_chassis_zero"  # SI2
const MOD_TROUBLE_REAR_ZERO := "trouble_rear_zero"        # SI3
const MOD_CHASSIS_FLOOR := "chassis_floor"              # SI4 섀시 최저 잔존
const MOD_FREE_HOLD := "free_hold"                      # SH4 기본 홀드 비용 면제

# 엔진이 소비하는 effect 식별자 전량 — `skills.csv` effect 열과 **양방향** 대조 대상이다.
# 표에 있고 여기 없으면 죽은 스킬(눌러도 아무 일이 없다) · 여기 있고 표에 없으면 죽은 코드.
# 거부 사유 중 **문면을 두지 않는 것** (총괄 판정 · 증보 ④).
# 이 셋은 사유가 **잠정 결과의 내용에 의존**한다 — "무효화할 트러블이 없다"·"그 릴은 그 심볼이
# 아니다"·"두 릴이 이미 같다". 문면으로 말하는 순간 릴 정지 연출 전에 결과가 새므로
# (불변규칙 5) **소리 거부만 남기고 문면은 두지 않는 것이 최종형**이다.
# 20차가 `use_skill_check` 에서 인자 의존 조건을 일부러 보지 않은 것과 같은 근거다.
const SEAL_SILENT_ERRORS := ["no_trouble", "symbol", "same"]

const SKILL_EFFECT_IDS := [
	"precision_hold", "full_sweep", "snapshot", "warmup_spin",
	"trouble_to_line", "trouble_to_pulse", "symbol_clone", "line_to_slipstream",
	"advance_x15", "pulse_yield_x2", "defense_x15_duel12", "overtorque_boost16",
	"duel_penalty_waive", "trouble_chassis_zero", "trouble_rear_zero", "survival_cell",
]

var data: GameData
var rng: RngService

var gp_state: int = RaceTypes.GpState.GP_START
var turn_phase: int = RaceTypes.TurnPhase.T1_SECTOR_OPEN

# 진행 카운터
# 투어 내 GP 슬롯 (제1~4전) — 슬롯 진행 보정의 입력. 투어 층이 주입한다.
# 사용자 판정(2026-08-12): 슬롯 진행 보정의 축 = 투어 내 GP 슬롯 (D08 §2.4 · D13 별첨A §6.2).
var race_slot: int = 1
# 플레이어 시작 포지션 (D13 별첨A §6.3) — 투어 층이 산정해 주입한다. 0 = 미주입(고정값 사용).
# 기준 순위 산정(챔피언십 순위 / 직전 GP 결과)은 시즌 층 소관이며 엔진은 결과만 소비한다.
var player_start_rank: int = 0

var lap: int = 0
var sector: int = 0
var turn_number: int = 0
var duel_count: int = 0
# 이 GP 에서 듀얼을 벌인 상대 id 순차 기록 (관계 축 '듀얼 수행' 카운터의 판정 소재 —
# D13 별첨A §5.2 계승 행). 같은 상대와 두 번 붙으면 두 번 들어간다 — 회수가 곧 카운터다.
var duel_opponents: Array = []
# GP 요약 카운터 (D07 §6.2 통산 지표 · D08 §8.11 드라이빙 업적의 판정 소재).
# 엔진은 세기만 하고 판정·보존은 아웃게임 층이 한다 — 업적 규칙이 엔진에 들어오지 않는다.
var duel_wins: int = 0
var trouble_turns: int = 0        # 트러블이 발화한 섹터 턴 수 (0 = 무트러블 GP)
var hold_uses: int = 0            # 홀드/리스핀 사용 횟수 (0 = 무개입)
var chance_three_matches: int = 0 # 찬스 3매치 성립 횟수
var final_lap_entry_rank: int = 0 # 최종 랩 진입 시점 순위 (역전 우승 판정 소재)
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
# 소모품 (D06 §3.5 · D07 §3.1) — 반입분(R5)은 세션이 start_gp 전에 주입하고 종료 시 회수한다.
# 인벤토리 정본은 아웃게임 층(OutgameState.consumables)이고 엔진은 대회 중 사본만 소비한다.
var consumables_carry_in: Dictionary = {}
var consumables_held: Dictionary = {}
# P2/P3 지속 효과 — "이번 대회" 한정 (D07 §3.1)이라 start_gp 에서 리셋된다.
var trouble_shield_charges: int = 0    # P2: 다음 트러블 1회 섀시 소모 반감 — 사용 횟수만큼 적립 [가안]
var wear_reduction: float = 0.0        # P3: 잔여 구간 섀시 소모 경감 비율 (D13 §3.6 = 0.20)
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

# ── 스킬 (D05 §6.1 "스킬은 개입 4타입의 데이터 인스턴스" · D07 §4.2 · D13 별첨A §4.2) ──
# 신규 개입 타입을 만들지 않는다. 효과 수치는 전량 D13 창구(core_params 전사)이며
# 심볼 치환·복제는 이미 서 있는 symbol_match_effects 를 그대로 타므로
# 별첨A 의 "게이지 부가 +11 G"(SC1)·"게이지 차 +13 G"(SC4)는 **치환의 귀결**이고 가산이 아니다.
var deck_carry_in: Array = []           # 세션 층 주입 — 정본은 아웃게임 상태
var skill_uses_carry_in: Dictionary = {}
var deck: Array = []                    # 이 GP 의 장착 덱 스냅숏
var skill_uses: Dictionary = {}         # skill id -> 이 **투어** 사용 횟수 (경계 리셋 = 아웃게임)
var respin_count: int = 0               # 턴당 재회전 총량 — 기본 홀드 + 홀드 계열 스킬 합산
var skill_mods: Dictionary = {}         # 턴 스코프 변조 (MOD_* 키) — 한 키로 리셋·직렬화
var snapshot_previous: Array = []       # SH3 — 재회전 직전 잠정 결과 (택1 대기 중에만 비지 않음)

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
	duel_opponents.clear()
	duel_wins = 0
	trouble_turns = 0
	hold_uses = 0
	chance_three_matches = 0
	final_lap_entry_rank = 0
	ai_retire_count = 0
	_retire_order = 0
	if chassis_carry_in >= 0.0:
		# 이월 개시 (D05 §8) — 주입 값은 [0, 최대치]로 절단한다 (세이브 조작·상한 초과 방어)
		chassis = clampf(chassis_carry_in, 0.0, data.param("param_chassis_max"))
	else:
		chassis = data.param("param_chassis_max")
	charge = 0
	consumables_held = consumables_carry_in.duplicate()
	deck = deck_carry_in.duplicate()
	skill_uses = skill_uses_carry_in.duplicate()   # 투어 스코프 — GP 개시가 리셋 지점이 아니다
	trouble_shield_charges = 0
	wear_reduction = 0.0
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
	# 플레이어 시작 포지션 (D13 별첨A §6.3): 기준 순위는 투어 층이 주입한다.
	# 미주입(단독 GP·디버그 주행) = 그리드 데이터의 고정값 — MS-1 단독 GP 계약을 보존한다.
	var player_pos := player_start_rank if player_start_rank > 0 else data.grid_int("player_start_position")
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
			# 최종 랩 진입 시점 순위 — '최종 랩 역전 우승'(D08 §8.11)의 판정 소재.
			# 엔진은 기록만 하고 업적 판정은 아웃게임 층이 한다.
			if lap >= data.circuit_int("laps"):
				final_lap_entry_rank = player_position()
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
	respin_count = 0
	skill_mods = {}
	snapshot_previous = []
	return info


# ── 소모품 사용 (D06 §3.5 R-B · D07 §3.1 · D13 §3.6) ──
# 사용 지점 = T1 섹터 개시 전속 — 개입 창(T4)을 침범하지 않아 D05 §5.4 확정 목록 불변.
# 듀얼 턴의 T1은 "섹터 개시"가 아니므로 제외한다 (R-B 문면 준거 — impl_log).
# 성공 = 로그 이벤트 반환 · 거부 = 빈 배열 + 상태 무변경 (효과는 회복·완화 전용 — R3).
func use_consumable(consumable_id: String) -> Array:
	if finished or current_turn_is_duel \
		or turn_phase != RaceTypes.TurnPhase.T1_SECTOR_OPEN \
		or gp_state != RaceTypes.GpState.SECTOR_TURN:
		return []
	if int(consumables_held.get(consumable_id, 0)) <= 0:
		return []
	if not data.consumables.has(consumable_id):
		push_error("RaceEngine: unknown consumable '%s'" % consumable_id)
		return []
	var row: Dictionary = data.consumables[consumable_id]
	var value := CsvTable.to_float(String(row["effect_value"]))
	match String(row["effect"]):
		"chassis_restore":
			chassis = minf(chassis + value, data.param("param_chassis_max"))
		"chassis_restore_and_shield":
			chassis = minf(chassis + value, data.param("param_chassis_max"))
			trouble_shield_charges += 1
		"chassis_wear_ratio":
			# 고정 계수라 누적하지 않는다 [가안] — 중복 사용은 허용하되 효과 동일 (UI 층이 안내)
			wear_reduction = absf(value)
		_:
			push_error("RaceEngine: unknown consumable effect '%s'" % row["effect"])
			return []
	consumables_held[consumable_id] = int(consumables_held[consumable_id]) - 1
	return [_ev("T1", "raceLog.consumableUse01", {"item": String(row["name_key"])})]


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


func _roll_reel(reel_index: int, exclude_trouble := false) -> String:
	var weights := reel_weights(reel_index)
	if exclude_trouble:
		# SH1 프리시전 홀드 — 트러블 가중 0 (별첨A §4.2 "0.18 → 0 재정규화").
		# pick_weighted 가 가중 합으로 나누므로 **0 대입 자체가 재정규화**다: 남은 5분류의
		# 비례는 유지되고 합만 0.82 가 된다. 확률 표를 따로 두면 그 표가 분포와 갈린다.
		for index in range(data.symbols.size()):
			if String(data.symbols[index]["id"]) == RaceTypes.SYMBOL_TROUBLE:
				weights[index] = 0.0
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
	# 홀드 계열 총량 가드 (D07 §4.2 · 별첨A §4.2) — 기본 홀드 + 스킬 홀드 **합산** 상한.
	# D05 §5.4 의 "턴당 1회"(기본 액션 자체의 한도)는 무개정이고, 그 취지(무한 리롤 방지)를
	# 스킬 층까지 넓힌 것이 이 상한이다. 두 카운터를 겹쳐 두는 이유: 스킬이 상한을 먼저
	# 소진했을 때 기본 홀드도 막혀야 하는데 hold_used 만으로는 그것이 표현되지 않는다.
	if respin_count >= data.param_int("param_hold_total_cap_per_turn"):
		return {"ok": false, "error": "respin_cap"}
	# SH4 웜업 스핀 — 이번 턴 기본 홀드의 차지 비용 0 (별첨A §4.2 "기본 홀드 비용 1 → 0")
	var cost := 0 if bool(skill_mods.get(MOD_FREE_HOLD, false)) \
		else data.param_int("param_charge_hold_cost")
	if charge < cost:
		return {"ok": false, "error": "charge"}
	charge -= cost
	hold_used = true
	hold_uses += 1
	respin_count += 1
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


# ── T4 개입 창 · 스킬 투입 (D05 §5.4 "스킬 사용" · §6.1 · D07 §4.2 · D13 별첨A §4.2) ──
#
# 진입로는 하나다. 기본 개입 3종(홀드·차지·부스트)이 각자 메서드를 갖는 것은 그것들이
# **고정 의미의 기본 액션**이기 때문이고, 스킬은 4타입의 데이터 인스턴스이므로
# 인스턴스 수만큼 메서드를 늘리면 표에 행을 더하는 일이 코드 개정을 부른다(데이터 드리븐 위반).
#
# 반환 계약 = 기본 개입과 동형: {"ok": bool, "error": String, "events": Array}.
# 거부 시 비용·횟수·상태는 **전부 무변경**이다 — 부분 소비가 남으면 UI 가 재시도할 수 없다.
#
# `args` 는 타입별로만 읽는다: 홀드 계열 = {"keep": [릴 인덱스]} · 변환 계열 = {"target": 릴}
# (SC3 은 {"target": 릴, "donor": 인접 릴}). 증폭·보험 계열은 인자를 쓰지 않는다.
func use_skill(skill_id: String, args: Dictionary = {}) -> Dictionary:
	var gate := use_skill_check(skill_id)
	if not bool(gate.get("ok", false)):
		return gate
	var row := data.skill(skill_id)
	var effect := String(row["effect"]).strip_edges()
	var applied := _apply_skill(effect, args)
	if not bool(applied.get("ok", false)):
		return applied
	charge -= CsvTable.to_int(String(row["charge_cost"]))
	skill_uses[skill_id] = int(skill_uses.get(skill_id, 0)) + 1
	# 발화 문면 = 20차에 요청하고 내러티브 5차가 유입한 키. 기본 개입 2종
	# (`holdRespin01`·`negate01`)과 같은 자리이며, 스킬 이름을 인자로 넘기지 않는다 —
	# 베인은 UI 용어를 발화하지 않는다(D05 §5.4 용어 이층: '등록 루틴 적용').
	return {"ok": true, "events": [_ev("T4", "vane.brief.skillUse01", {})],
		"family": String(row["family"]), "effect": effect}


# 인자와 무관한 성립 조건 조회 — 투입 없이 판정한다(버튼 활성 판정용).
# 관문을 조회와 투입이 각자 구현하면 "버튼은 켜지는데 눌리지 않는" 상태가 생기므로
# use_skill 도 이 함수를 통과한 뒤에만 효과를 적용한다 — 판정은 한 곳뿐이다.
func use_skill_check(skill_id: String) -> Dictionary:
	if turn_phase != RaceTypes.TurnPhase.T4_INTERVENTION:
		return {"ok": false, "error": "phase"}
	if not deck.has(skill_id):
		return {"ok": false, "error": "deck"}   # 해금만으로는 못 쓴다 — 장착이 조건 (D07 §4.1)
	var row := data.skill(skill_id)
	if row.is_empty():
		return {"ok": false, "error": "unknown"}
	var limit := CsvTable.to_int(String(row["uses_per_tour"]))
	if limit > 0 and int(skill_uses.get(skill_id, 0)) >= limit:
		return {"ok": false, "error": "uses"}
	if charge < CsvTable.to_int(String(row["charge_cost"])):
		return {"ok": false, "error": "charge"}
	var blocked := _skill_precondition(String(row["effect"]).strip_edges())
	if not blocked.is_empty():
		return {"ok": false, "error": blocked}
	return {"ok": true}


# 타입별 성립 조건. **인자 의존 조건(대상 심볼·고정 릴 수)은 여기서 보지 않는다** —
# 미리 보려면 인자가 필요하고 인자는 UI 가 모으는 중이라는 실용적 이유가 하나,
# **봉인**(불변규칙 5)이 둘이다: "SC1 을 누를 수 있는가"가 트러블 유무로 갈리면
# 버튼 상태가 곧 결과 상관 신호가 되어 릴 정지 연출 전에 결과를 흘린다.
# 여기 조건들은 전부 잠정 결과의 **내용과 무관**하다(창·덱·차지·횟수·턴 종류·자릿수).
#
# **효과가 이번 턴에 도달할 수 없으면 거부한다** — 차지만 태우고
# 아무 일도 없는 투입을 허용하면 그것이 곧 무비용 통제의 반대편 결함이다.
# 듀얼 턴은 정산 ①~⑤ 를 돌지 않으므로(_settle_duel) 그 단계에 붙는 효과가 도달하지 않고,
# 섹터 턴에는 부스트·듀얼 판정이 존재하지 않는다.
func _skill_precondition(effect: String) -> String:
	match effect:
		"precision_hold", "full_sweep", "snapshot":
			if provisional.size() != 3:
				return "no_provisional"
			if respin_count >= data.param_int("param_hold_total_cap_per_turn"):
				return "respin_cap"
		"warmup_spin":
			if skill_mods.has(MOD_FREE_HOLD) or hold_used:
				# **`already_mod` 와 갈라 둔다 (총괄 증보 ③).** 이쪽은 "기본 홀드를 이미 썼다"이고
				# 저쪽은 "이 효과가 이미 걸려 있다"다 — 한 문면으로 둘을 말하면 한쪽이 거짓이 된다.
				return "already_hold"
		"trouble_to_line", "trouble_to_pulse", "line_to_slipstream", "symbol_clone":
			if provisional.size() != 3:
				return "no_provisional"
		"advance_x15":
			if current_turn_is_duel:
				return "duel_turn"
			if skill_mods.has(MOD_ADVANCE_MULT):
				return "already_mod"
		"pulse_yield_x2":
			if current_turn_is_duel:
				return "duel_turn"
			if skill_mods.has(MOD_PULSE_MULT):
				return "already_mod"
		"defense_x15_duel12":
			# 한 스킬이 두 턴 종류에서 각기 다른 절반을 쓴다 (별첨A §4.2 "방어 효과 ×1.5 +
			# 방어 듀얼 판정 +12") — 어느 쪽도 도달 불가가 아니므로 턴 종류로 거부하지 않는다.
			if current_turn_is_duel:
				if skill_mods.has(MOD_DEFENSE_DUEL_ADD):
					return "already_mod"
			elif skill_mods.has(MOD_DEFENSE_MULT):
				return "already_mod"
		"overtorque_boost16":
			if not current_turn_is_duel:
				return "sector_turn"
			if skill_mods.has(MOD_BOOST_PER):
				return "already_mod"
		"duel_penalty_waive":
			if not current_turn_is_duel:
				return "sector_turn"
			if skill_mods.has(MOD_DUEL_PENALTY_WAIVED):
				return "already_mod"
		"trouble_chassis_zero":
			if current_turn_is_duel:
				return "duel_turn"
			if skill_mods.has(MOD_TROUBLE_CHASSIS_ZERO):
				return "already_mod"
		"trouble_rear_zero":
			if current_turn_is_duel:
				return "duel_turn"
			if skill_mods.has(MOD_TROUBLE_REAR_ZERO):
				return "already_mod"
		"survival_cell":
			if skill_mods.has(MOD_CHASSIS_FLOOR):
				return "already_mod"
		_:
			return "effect"
	return ""


func _apply_skill(effect: String, args: Dictionary) -> Dictionary:
	match effect:
		"precision_hold":
			return _skill_respin(args, 2, true)
		"full_sweep":
			return _skill_respin({"keep": []}, 0, false)
		"snapshot":
			# 재회전과 택1 은 두 걸음이다 — 한 호출에 합치면 UI 가 두 후보를 나란히 놓을 자리가
			# 없고, "무엇과 무엇 중 고르는지"를 못 보여주면 SH3 의 효과 자체가 성립하지 않는다.
			var previous := provisional.duplicate()
			var outcome := _skill_respin(args, -1, false)
			if bool(outcome.get("ok", false)):
				snapshot_previous = previous
			return outcome
		"warmup_spin":
			skill_mods[MOD_FREE_HOLD] = true
			return {"ok": true}
		"trouble_to_line":
			return _convert_symbol(args, RaceTypes.SYMBOL_TROUBLE, RaceTypes.SYMBOL_LINE)
		"trouble_to_pulse":
			return _convert_symbol(args, RaceTypes.SYMBOL_TROUBLE, RaceTypes.SYMBOL_PULSE)
		"line_to_slipstream":
			return _convert_symbol(args, RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_SLIPSTREAM)
		"symbol_clone":
			return _clone_symbol(args)
		"advance_x15":
			skill_mods[MOD_ADVANCE_MULT] = data.param("param_skill_advance_mult")
			return {"ok": true}
		"pulse_yield_x2":
			skill_mods[MOD_PULSE_MULT] = data.param("param_skill_pulse_mult")
			return {"ok": true}
		"defense_x15_duel12":
			if current_turn_is_duel:
				skill_mods[MOD_DEFENSE_DUEL_ADD] = data.param("param_skill_defense_duel_add")
			else:
				skill_mods[MOD_DEFENSE_MULT] = data.param("param_skill_defense_mult")
			return {"ok": true}
		"overtorque_boost16":
			skill_mods[MOD_BOOST_PER] = data.param("param_skill_boost_per_judgment")
			return {"ok": true}
		"duel_penalty_waive":
			skill_mods[MOD_DUEL_PENALTY_WAIVED] = true
			return {"ok": true}
		"trouble_chassis_zero":
			skill_mods[MOD_TROUBLE_CHASSIS_ZERO] = true
			return {"ok": true}
		"trouble_rear_zero":
			skill_mods[MOD_TROUBLE_REAR_ZERO] = true
			return {"ok": true}
		"survival_cell":
			skill_mods[MOD_CHASSIS_FLOOR] = true
			return {"ok": true}
	push_error("RaceEngine: unknown skill effect '%s'" % effect)
	return {"ok": false, "error": "effect"}


# 홀드 계열 공통 재회전. required_keep = 고정 릴 수 강제(-1 = 자유).
func _skill_respin(args: Dictionary, required_keep: int, exclude_trouble: bool) -> Dictionary:
	var keep: Array = []
	for value in args.get("keep", []):
		var index := int(value)
		if index < 0 or index > 2 or keep.has(index):
			return {"ok": false, "error": "keep"}
		keep.append(index)
	if required_keep >= 0 and keep.size() != required_keep:
		return {"ok": false, "error": "keep"}
	if keep.size() >= 3:
		return {"ok": false, "error": "keep"}   # 재회전 대상 0 = 무효과 투입
	for reel_index in range(3):
		if not keep.has(reel_index):
			provisional[reel_index] = _roll_reel(reel_index, exclude_trouble)
	respin_count += 1
	_resync_negated()
	return {"ok": true}


# 변환 계열 — 지정 릴의 심볼을 교체한다. 대상 심볼이 아니면 거부(무효과 투입 방지).
func _convert_symbol(args: Dictionary, from_symbol: String, to_symbol: String) -> Dictionary:
	var target := int(args.get("target", -1))
	if target < 0 or target > 2:
		return {"ok": false, "error": "target"}
	if String(provisional[target]) != from_symbol:
		return {"ok": false, "error": "symbol"}
	provisional[target] = to_symbol
	_resync_negated()
	return {"ok": true}


# SC3 슬립스트림 링크 — 인접 릴의 심볼을 복제한다 (별첨A §4.2 "인접 릴 심볼 복제").
func _clone_symbol(args: Dictionary) -> Dictionary:
	var target := int(args.get("target", -1))
	var donor := int(args.get("donor", -1))
	if target < 0 or target > 2 or donor < 0 or donor > 2:
		return {"ok": false, "error": "target"}
	if absi(target - donor) != 1:
		return {"ok": false, "error": "adjacent"}
	if String(provisional[target]) == String(provisional[donor]):
		return {"ok": false, "error": "same"}   # 이미 같다 = 무효과 투입
	provisional[target] = provisional[donor]
	_resync_negated()
	return {"ok": true}


# 차지 개입은 **개수**로 무효화를 적립한다(어느 릴인지 기억하지 않는다 — D05 §5.4 문면).
# 그 뒤 변환·재회전이 트러블 수를 줄이면 적립분이 실재 트러블보다 많아져 정산에서
# 음수 트러블이 나온다. 적립분을 잔존 트러블로 절단해 대장을 맞춘다 —
# 절단이 아니라 소거로 처리하면 이미 지불한 2차지가 조용히 사라진다.
func _resync_negated() -> void:
	negated_troubles = mini(negated_troubles, _count_symbol(RaceTypes.SYMBOL_TROUBLE))


# SH3 스냅샷 택1 — keep_new=false 면 재회전 직전 후보로 되돌린다.
func choose_snapshot(keep_new: bool) -> Dictionary:
	if turn_phase != RaceTypes.TurnPhase.T4_INTERVENTION:
		return {"ok": false, "error": "phase"}
	if snapshot_previous.is_empty():
		return {"ok": false, "error": "no_snapshot"}
	if not keep_new:
		provisional = snapshot_previous.duplicate()
		_resync_negated()
	snapshot_previous = []
	return {"ok": true}


# UI 창구 (D09 §3.3 E09 스킬 슬롯) — 화면이 표를 다시 읽거나 가용 조건을 재구현하지 않도록
# 렌더링에 필요한 것을 한 번에 돌려준다. 조건이 두 곳에 있으면 언젠가 갈라진다.
# uses_left = -1 은 "투어 상한 없음"이다(0 은 '소진'이므로 무제한과 같은 값을 쓸 수 없다).
func skill_slots() -> Array:
	var slots: Array = []
	for entry in deck:
		var skill_id := String(entry)
		if not data.skills.has(skill_id):
			push_error("RaceEngine: deck holds unknown skill '%s'" % skill_id)
			continue
		var row: Dictionary = data.skills[skill_id]
		var limit := CsvTable.to_int(String(row["uses_per_tour"]))
		var used := int(skill_uses.get(skill_id, 0))
		var probe := use_skill_check(skill_id)
		slots.append({
			"id": skill_id,
			"name_key": String(row["name_key"]),
			"family": String(row["family"]),
			"effect": String(row["effect"]).strip_edges(),
			"charge_cost": CsvTable.to_int(String(row["charge_cost"])),
			"uses_per_tour": limit,
			"uses_left": -1 if limit <= 0 else maxi(limit - used, 0),
			"usable": bool(probe.get("ok", false)),
			"reason": String(probe.get("error", "")),
		})
	return slots


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
	# SI4 서바이벌 셀 — 이번 턴 섀시 최저 잔존 (별첨A §4.2 "섀시 최저 1").
	# 리타이어 판정(_after_settlement) **직전** 한 곳에 둔다: 섀시를 깎는 경로가
	# 단계 ①(트러블)과 단계 ⑥(듀얼 패배) 둘이므로 어느 한 단계 안에 넣으면 다른 쪽이 바닥을 뚫는다.
	if bool(skill_mods.get(MOD_CHASSIS_FLOOR, false)):
		chassis = maxf(chassis, data.param("param_skill_chassis_floor"))
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
					# P3 쿨런트 차지: 잔여 구간 섀시 소모 경감 (D07 §3.1 · D13 §3.6 −20%)
					chassis -= data.param("param_chassis_hazard_per_turn") * (1.0 - wear_reduction)
				if trouble_count > 0:
					trouble_fired = true
					trouble_turns += 1
					var effect := _match_effect(RaceTypes.SYMBOL_TROUBLE, trouble_count)
					var chassis_delta := CsvTable.to_float(String(effect["chassis"])) * hazard_wear
					if bool(skill_mods.get(MOD_TROUBLE_CHASSIS_ZERO, false)):
						# SI2 섀시 실드 — 섀시 소모 0 (별첨A §4.2 · 후방 게이지 가산은 유지).
						# 소모품 실드(반감)보다 **먼저** 0으로 만든다: 깎을 것이 없는데
						# 실드 적립분을 소비하면 다음 트러블용 보험이 조용히 사라진다.
						chassis_delta = 0.0
					if chassis_delta < 0.0 and trouble_shield_charges > 0:
						# P2 이머전시 실런트: 다음 트러블 1회 섀시 소모 반감 (D13 §3.6 −50%)
						trouble_shield_charges -= 1
						chassis_delta *= data.param("param_consumable_shield_mult")
					if chassis_delta < 0.0:
						chassis_delta *= (1.0 - wear_reduction)
					chassis += chassis_delta
					var trouble_rear := CsvTable.to_float(String(effect["rear_gauge"])) * gauge_mult
					if bool(skill_mods.get(MOD_TROUBLE_REAR_ZERO, false)):
						trouble_rear = 0.0   # SI3 카운터 스티어 (섀시 소모는 유지 — SI2 와 상보)
					rear_gauge += trouble_rear
					events.append(_ev("T5", "raceLog.troubleHit01", {"amount": chassis_delta}))
			RaceTypes.SettleStage.STAGE_2_RESOURCE:
				var pulse_count := _count_symbol(RaceTypes.SYMBOL_PULSE)
				if pulse_count > 0:
					# SA2 펄스 리커버 — **펄스 심볼의 생산**만 배수다(별첨A §4.2 문면).
					# 안정 완주 +1·듀얼 승리 보너스는 심볼 생산이 아니므로 곱하지 않는다.
					var pulse_charge := float(CsvTable.to_int(String(
						_match_effect(RaceTypes.SYMBOL_PULSE, pulse_count)["charge"])))
					_gain_charge(int(round(pulse_charge * float(skill_mods.get(MOD_PULSE_MULT, 1.0)))))
				if not trouble_fired:
					var stable_gain := data.param_int("param_charge_stable_sector")
					_gain_charge(stable_gain)
					events.append(_ev("T5", "raceLog.stableSector01", {"amount": stable_gain}))
				events.append_array(_apply_resonance_bonus(gauge_mult))
			RaceTypes.SettleStage.STAGE_3_DEFENSE:
				var braking_count := _count_symbol(RaceTypes.SYMBOL_BRAKING)
				if braking_count > 0:
					# SA3 하드 브레이킹 — 브레이킹 효과는 후방 게이지 **감산**이므로
					# 배수를 곱하면 감산이 커진다(방어 강화). 부호를 뒤집지 않는다.
					rear_gauge += CsvTable.to_float(String(_match_effect(RaceTypes.SYMBOL_BRAKING, braking_count)["rear_gauge"])) \
						* gauge_mult * float(skill_mods.get(MOD_DEFENSE_MULT, 1.0))
			RaceTypes.SettleStage.STAGE_4_ADVANCE:
				# SA1 풀 스로틀 — "이번 턴 전진 효과 ×1.5"(별첨A §4.2).
				# **[가안] 적용 범위 = 심볼 유래 전진분 전속**이며 모멘텀 보너스는 제외한다.
				# 근거: ⓐ별첨A 문면의 '전진 효과'는 정산 ④ 심볼 항이고 모멘텀은 D05 §7.3
				# 타이머 보너스로 소관이 다르다 ⓑD14 §8.3 ③ 매트릭스의 판정 기준이
				# "개입 후에도 모멘텀 델타 불변"이라 모멘텀을 곱하면 그 기준 자체가 깨진다.
				# 정본이 침묵하는 지점이므로 총괄 판정 대상으로 회신에 올린다.
				var advance_mult := float(skill_mods.get(MOD_ADVANCE_MULT, 1.0))
				var slip_count := _count_symbol(RaceTypes.SYMBOL_SLIPSTREAM)
				if slip_count > 0:
					front_gauge += CsvTable.to_float(String(_match_effect(RaceTypes.SYMBOL_SLIPSTREAM, slip_count)["front_gauge"])) * gauge_mult * advance_mult
				var line_count := _count_symbol(RaceTypes.SYMBOL_LINE)
				if line_count > 0:
					var line_effect := _match_effect(RaceTypes.SYMBOL_LINE, line_count)
					front_gauge += CsvTable.to_float(String(line_effect["front_gauge"])) * gauge_mult * advance_mult
					rear_gauge += CsvTable.to_float(String(line_effect["rear_gauge"])) * gauge_mult * advance_mult
				var chance_count := _count_symbol(RaceTypes.SYMBOL_CHANCE)
				if chance_count >= 3:
					chance_three_matches += 1
				if chance_count > 0:
					var chance_effect := _match_effect(RaceTypes.SYMBOL_CHANCE, chance_count)
					if String(chance_effect["special"]).strip_edges() == "duel_trigger":
						chance_full = true
						events.append(_ev("T5", "raceLog.chanceDuel01", {}))
					else:
						front_gauge += CsvTable.to_float(String(chance_effect["front_gauge"])) * gauge_mult * advance_mult
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
					duel_opponents.append(duel_opponent)
					var log_key := "raceLog.duelStartOvertake01" if _armed_duel == RaceTypes.DuelType.OVERTAKE else "raceLog.duelStartDefense01"
					events.append(_ev("T5", log_key, _entrant_params(duel_opponent)))
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
		duel_wins += 1
		var bonus := data.param_int("param_charge_duel_win")
		_gain_charge(bonus)
		events.append(_ev("T5", "raceLog.duelWin01", {"amount": bonus}))
		if duel_type == RaceTypes.DuelType.OVERTAKE:
			_swap_with(opponent_id)
			events.append(_ev("T5", "raceLog.overtakeSuccess01",
				_entrant_params(opponent_id, {"rank": player_position()})))
		else:
			events.append(_ev("T5", "raceLog.defendSuccess01", _entrant_params(opponent_id)))
	elif bool(skill_mods.get(MOD_DUEL_PENALTY_WAIVED, false)):
		# SI1 임팩트 가드 — 패배 페널티 면제 (별첨A §4.2 "섀시 −5 / 피추월 무효").
		# 기존 패배 문면 3종은 **전부 못 쓴다**: `duelLoseDefense01`("피추월")·
		# `defendFail01`("자리를 내줬다")·`duelLoseOvertake01`(감소량 인자)은 셋 다
		# 일어나지 않은 일을 말한다. 20차는 전용 키가 없어 무발화로 두고 보고했고,
		# 내러티브 5차가 `duelLoseWaived01` 을 유입해 여기서 결선한다 —
		# **패배는 말하고 페널티는 말하지 않는다**("충격을 받아냈다").
		events.append(_ev("T5", "raceLog.duelLoseWaived01", {}))
	else:
		if duel_type == RaceTypes.DuelType.OVERTAKE:
			# P3 경감 대상 [가안]: 문면 "잔여 구간 섀시 소모"가 소모원을 한정하지 않아
			# 인레이스 섀시 감소 전 경로(해저드·트러블·듀얼 실패)에 적용한다 — impl_log
			var penalty := -data.param("param_chassis_duel_fail_penalty") * (1.0 - wear_reduction)
			chassis += penalty
			events.append(_ev("T5", "raceLog.duelLoseOvertake01", {"amount": penalty}))
		else:
			_swap_with(opponent_id)
			events.append(_ev("T5", "raceLog.duelLoseDefense01", {}))
			events.append(_ev("T5", "raceLog.defendFail01", _entrant_params(opponent_id)))
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
	# SA4 오버토크 — 차지당 보정 10 → 16 (별첨A §4.2). 가산이 아니라 **대체**다:
	# 문면이 "10 → 16"이라 가산으로 읽으면 26이 된다.
	judgment += float(duel_boost) * float(skill_mods.get(MOD_BOOST_PER,
		data.param("param_charge_boost_per_judgment")))
	if duel_type == RaceTypes.DuelType.DEFENSE:
		# SA3 하드 브레이킹의 듀얼 절반 — **방어 듀얼 전속** 가산 (별첨A §4.2 문면)
		judgment += float(skill_mods.get(MOD_DEFENSE_DUEL_ADD, 0.0))
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
			events.append(_ev("T5", "raceLog.aiRetire01", _entrant_params(id)))
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
		# GP 요약 (D07 §6.2 통산 지표 · D08 §8.11 드라이빙 업적 판정 소재) — 계수만 넘긴다
		"duel_wins": duel_wins,
		"trouble_turns": trouble_turns,
		"hold_uses": hold_uses,
		"chance_three_matches": chance_three_matches,
		"final_lap_entry_rank": final_lap_entry_rank,
		"circuit_id": String(data.circuit.get("id", "")),
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


# 대상 참가자 표기 매개 한 벌 — `name_key` 와 `number` 는 **반드시 함께 간다.**
# 필러의 name_key 는 그 자체가 문면(`No.{number} 머신`)이라, 표기 층이 그것을 번역할 때
# `number` 를 **같은 params 에서** 찾는다. 짝을 호출부마다 손으로 적으면 한쪽이 빠지고,
# 네임드 문면에는 `{number}` 자리가 아예 없어 **그 누락이 화면에 드러나지도 않는다** —
# 실제로 5지점 중 4지점이 빠진 채 통과했다(주력 실기 관측 `No.{number} 머신 리타이어.`
# — IMPL-210). 그래서 손 규약이 아니라 창구 하나로 짝을 구조에 고정한다.
#
# **`number` 를 `target` 앞에 둔 것은 의도다** (IMPL-211 돌연변이 M3 실측). `StringTable.text()`
# 는 params 를 **삽입 순서대로 1회 훑으며** 치환하므로, `target` 이 먼저면 `{target}` 자리에
# 들어온 `No.{number} 머신` 의 `{number}` 가 **같은 훑기에서 뒤이어 우연히 치환된다** —
# 그러면 표기 층의 중첩 키 선해결(`race_screen._push_events`)이 있으나 마나가 되고, 그것을
# 지워도 아무 검사도 울리지 않는다(실측 미검출 1건). 순서를 뒤집어 **선해결만이 유일한
# 성립 경로**가 되게 두면, 그 한 줄이 사라지는 순간 8축이 동시에 실패한다.
func _entrant_params(id: String, extra: Dictionary = {}) -> Dictionary:
	var params: Dictionary = {
		"number": entrants[id]["number"],
		"target": entrants[id]["name_key"],
	}
	for extra_key in extra:
		params[extra_key] = extra[extra_key]
	return params


# ── 직렬화 (서스펜드 스냅샷 §7.2 — RNG 포함, 재로드 리롤 무효 §6.2) ──
func serialize() -> Dictionary:
	return {
		"gp_state": gp_state,
		"turn_phase": turn_phase,
		"lap": lap, "sector": sector,
		"turn_number": turn_number, "duel_count": duel_count,
		"duel_opponents": duel_opponents.duplicate(),
		"duel_wins": duel_wins, "trouble_turns": trouble_turns, "hold_uses": hold_uses,
		"chance_three_matches": chance_three_matches, "final_lap_entry_rank": final_lap_entry_rank,
		"ai_retire_count": ai_retire_count, "retire_order_counter": _retire_order,
		"entrants": entrants.duplicate(true),
		"positions": positions.duplicate(),
		"chassis": chassis, "charge": charge,
		"consumables_held": consumables_held.duplicate(),
		"trouble_shield_charges": trouble_shield_charges,
		"wear_reduction": wear_reduction,
		"front_gauge": front_gauge, "rear_gauge": rear_gauge,
		"front_target": front_target, "rear_target": rear_target,
		"provisional": provisional.duplicate(),
		"hold_used": hold_used, "negated_troubles": negated_troubles,
		"duel_boost": duel_boost,
		"deck": deck.duplicate(), "skill_uses": skill_uses.duplicate(),
		"respin_count": respin_count, "skill_mods": skill_mods.duplicate(),
		"snapshot_previous": snapshot_previous.duplicate(),
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
	# 구세이브 관용 — 없으면 빈 목록 (IMPL-090 전례)
	duel_opponents = payload.get("duel_opponents", [])
	# GP 요약 도입(T4) 전 스냅샷에는 없다 — 0 = "그 GP에서 아직 세지 않았다"가 충실값
	duel_wins = int(payload.get("duel_wins", 0))
	trouble_turns = int(payload.get("trouble_turns", 0))
	hold_uses = int(payload.get("hold_uses", 0))
	chance_three_matches = int(payload.get("chance_three_matches", 0))
	final_lap_entry_rank = int(payload.get("final_lap_entry_rank", 0))
	ai_retire_count = int(payload["ai_retire_count"])
	_retire_order = int(payload["retire_order_counter"])
	entrants = payload["entrants"]
	positions = payload["positions"]
	chassis = float(payload["chassis"])
	charge = int(payload["charge"])
	# 구스냅샷(키 부재) = 소모품 이전 세계 — 빈 인벤토리·무효과가 충실값 (IMPL-090 전례)
	consumables_held = payload.get("consumables_held", {})
	trouble_shield_charges = int(payload.get("trouble_shield_charges", 0))
	wear_reduction = float(payload.get("wear_reduction", 0.0))
	front_gauge = float(payload["front_gauge"])
	rear_gauge = float(payload["rear_gauge"])
	front_target = String(payload["front_target"])
	rear_target = String(payload["rear_target"])
	provisional = payload["provisional"]
	hold_used = bool(payload["hold_used"])
	negated_troubles = int(payload["negated_troubles"])
	duel_boost = int(payload["duel_boost"])
	# 스킬 도입 전 스냅샷 = 빈 덱·무사용·무변조가 충실값 (구세이브 관용 — IMPL-090 전례).
	# 변조는 턴 스코프라 재개 지점의 값을 그대로 실어야 한다: 재로드로 보험이 풀리면
	# 이미 지불한 차지가 사라지고, 반대로 남으면 재로드 리롤이 이득이 된다(D12 §6.3).
	deck = payload.get("deck", [])
	skill_uses = payload.get("skill_uses", {})
	respin_count = int(payload.get("respin_count", 0))
	skill_mods = payload.get("skill_mods", {})
	snapshot_previous = payload.get("snapshot_previous", [])
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
