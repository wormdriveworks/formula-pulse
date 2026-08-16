# 시즌·투어 층 (D05 §9.3~§9.5·§10 · D08 §2·§5.5·§5.6 · D13 별첨A §3.2·§6.1·§7.4).
#
# 계층: 그랑프리 → 투어(4대회) → 시즌(5투어) → 챔피언십.
# 포인트는 2계층이다 (D05 §9.4): ①GP 순위 → 투어 포인트 ②투어 종합 순위 → 챔피언십 포인트.
# 2계층의 요점은 투어당 그랑프리 수가 바뀌어도 챔피언십 층 밸런스가 불변이라는 것이므로,
# 여기서도 두 층을 섞지 않는다.
#
# 시즌은 항상 5투어를 소화한다 (D05 §9.5 · D08 §5.5 — 조기 종료 없음).
# 투어 탈락도 시즌을 중단시키지 않으며 같은 투어의 재도전은 없다 (D05 §9.3).
class_name SeasonState
extends RefCounted

const PLAYER_ID := "player"

var data: GameData
var rng: RngService

var season: int = 1
var tour_slot: int = 1                 # 1~5 (시즌 내 투어 인덱스)
var race_slot: int = 1                 # 1~4 (투어 내 그랑프리 인덱스)
var grid_level: int = 0

var calendar: Array = []               # tour_slot 순서의 stage id 배열
var tour_points: Dictionary = {}       # entrant id -> 현 투어 누계 투어 포인트
var championship_points: Dictionary = {}  # entrant id -> 시즌 누계 챔피언십 포인트
var last_gp_standings: Array = []      # 동률 처리용 (직전 그랑프리 결과 순)
var tour_dropped_out: bool = false     # 현 투어 탈락 여부 (D05 §9.3)
var tour_gp_wins: int = 0              # 현 투어 내 플레이어 GP 우승 수 (전승 업적 계수 — D08 §8.11)
var season_tour_wins: int = 0          # 현 시즌 내 투어 종합 우승 수 (동상)
var champion_history: Array = []       # 시즌별 챔피언 id (에필로그 판정용 — D05 §10)

# 레조넌스 추첨 결과 (D08 §3.7 R6 — 투어 개막 1회 · 서킷 슬롯 × 섹터 슬롯)
var resonance_circuit_id: String = ""
var resonance_sector_slot: int = 0


func setup(game_data: GameData, rng_service: RngService) -> void:
	data = game_data
	rng = rng_service


func tours_per_season() -> int:
	return _calendar_int("tours_per_season")


func races_per_tour() -> int:
	return _calendar_int("races_per_tour")


func _calendar_int(key: String) -> int:
	var value: Variant = data.season_calendar.get(key, null)
	if value == null:
		push_error("SeasonState: missing '%s' in season_calendar.json" % key)
		return 0
	return int(value)


# ── 시즌 개막 ──
func begin_season(season_number: int) -> void:
	season = season_number
	tour_slot = 1
	race_slot = 1
	season_tour_wins = 0
	championship_points.clear()
	calendar = build_calendar(season_number, calendar)
	begin_tour()


# 캘린더 (D08 §2.1): 시즌 1 = 정순 고정 / 시즌 2+ = 투어 1·5 고정 + 투어 2~4 셔플.
# 셔플은 shuffle 스트림 전속이며 릴과 무관하다 (D08 §2.2 · D12 §6.1).
func build_calendar(season_number: int, previous: Array) -> Array:
	var opening := String(data.season_calendar.get("fixed_opening_stage", ""))
	var final_stage := String(data.season_calendar.get("fixed_final_stage", ""))
	var pool: Variant = data.season_calendar.get("shuffle_pool", [])
	var middle: Array = pool if typeof(pool) == TYPE_ARRAY else []
	if season_number <= 1:
		return _assemble(opening, middle, final_stage)
	var previous_middle: Array = []
	for index in range(previous.size()):
		if index > 0 and index < previous.size() - 1:
			previous_middle.append(previous[index])
	return _assemble(opening, shuffle_middle(middle, previous_middle), final_stage)


func _assemble(opening: String, middle: Array, final_stage: String) -> Array:
	var result: Array = []
	if opening != "":
		result.append(opening)
	result.append_array(middle)
	if final_stage != "":
		result.append(final_stage)
	return result


# 직전 시즌과 동일한 편성의 재출현을 금지한다 (D08 §2.2 확정 — 6조합 중 직전 제외 5개 균등).
# 순열을 전개해 직전 조합을 뺀 뒤 균등 추첨한다 — "다시 뽑기" 루프를 쓰지 않는 이유는
# 루프가 이론상 종료를 보장하지 않고 추첨 횟수가 스트림 상태를 오염시키기 때문이다.
func shuffle_middle(pool: Array, previous: Array) -> Array:
	if pool.size() <= 1:
		return pool.duplicate()
	var permutations := _permutations(pool)
	var allowed: Array = []
	for candidate in permutations:
		if not previous.is_empty() and Array(candidate) == previous:
			continue
		allowed.append(candidate)
	if allowed.is_empty():
		allowed = permutations
	return Array(allowed[rng.stream("shuffle").randi_range(0, allowed.size() - 1)]).duplicate()


func _permutations(items: Array) -> Array:
	if items.size() <= 1:
		return [items.duplicate()]
	var result: Array = []
	for index in range(items.size()):
		var rest := items.duplicate()
		var head: Variant = rest[index]
		rest.remove_at(index)
		for tail in _permutations(rest):
			var permutation: Array = [head]
			permutation.append_array(tail)
			result.append(permutation)
	return result


# ── 투어 개막 ──
# 레조넌스 추첨을 여기서 1회 수행한다 (D08 §3.7 R6). 위치는 저장되지만 UI에 노출되지 않는다.
func begin_tour() -> void:
	race_slot = 1
	tour_points.clear()
	tour_gp_wins = 0
	tour_dropped_out = false
	_draw_resonance()


func _draw_resonance() -> void:
	resonance_circuit_id = ""
	resonance_sector_slot = 0
	var stage_id := current_stage_id()
	if not data.stages.has(stage_id):
		return
	var circuits: Variant = data.stages[stage_id].get("circuits", [])
	if typeof(circuits) != TYPE_ARRAY or Array(circuits).is_empty():
		return
	var circuit_list: Array = circuits
	var picked_circuit := String(circuit_list[rng.stream("resonance").randi_range(0, circuit_list.size() - 1)])
	if not data.circuits.has(picked_circuit):
		push_error("SeasonState: unknown circuit '%s' in stage pool" % picked_circuit)
		return
	var sectors := int(data.circuits[picked_circuit].get("sectors_per_lap", 0))
	if sectors <= 0:
		push_error("SeasonState: circuit '%s' has no sectors_per_lap" % picked_circuit)
		return
	resonance_circuit_id = picked_circuit
	resonance_sector_slot = rng.stream("resonance").randi_range(1, sectors)


func current_stage_id() -> String:
	if tour_slot - 1 < 0 or tour_slot - 1 >= calendar.size():
		return ""
	return String(calendar[tour_slot - 1])


# 엔진에 GP 슬롯을 넘긴다 — 슬롯 진행 보정의 입력 (사용자 판정: 투어 내 GP 슬롯 축).
func apply_to_engine(engine: RaceEngine) -> void:
	engine.race_slot = race_slot
	engine.resonance_circuit_id = resonance_circuit_id
	engine.resonance_sector_slot = resonance_sector_slot
	engine.player_start_rank = player_start_rank()


# 플레이어 시작 포지션 (D13 별첨A §6.3 산정식):
#   · 시즌 1 투어 1 제1전 = P16 고정
#   · 투어 첫 그랑프리    = 챔피언십 순위 기반 (동률 = 직전 GP 결과 순 — V-2 등반 서사 보존)
#   · 투어 내 2~4전       = 직전 그랑프리 결과 기반
# 개별 시작 보정은 엔진의 AI 정렬 소관이며 여기서는 **플레이어 기준 순위**만 낸다.
func player_start_rank() -> int:
	var grid_size := _grid_size()
	if season <= 1 and tour_slot <= 1 and race_slot <= 1:
		return grid_size   # 개막전 P16 고정 (D08 §3.5)
	if race_slot > 1:
		var previous := last_gp_standings.find(PLAYER_ID)
		if previous >= 0:
			return clampi(previous + 1, 1, grid_size)
		return grid_size
	var standing := championship_standings().find(PLAYER_ID)
	if standing >= 0:
		return clampi(standing + 1, 1, grid_size)
	return grid_size


# 그리드 규모 = 필러 + 네임드 라이벌 + 플레이어 (D08 §3.5 16대 그리드의 구조적 산출).
# 순위 밖 절상값의 유일 출처 — 상수 기입 금지(불변규칙 2).
func _grid_size() -> int:
	return data.grid_int("filler_count") + data.grid_array("rivals").size() + 1


func current_circuit_id() -> String:
	var stage_id := current_stage_id()
	if not data.stages.has(stage_id):
		return ""
	var circuits: Variant = data.stages[stage_id].get("circuits", [])
	if typeof(circuits) != TYPE_ARRAY:
		return ""
	var circuit_list: Array = circuits
	if race_slot - 1 < 0 or race_slot - 1 >= circuit_list.size():
		return ""
	return String(circuit_list[race_slot - 1])


# ── 그랑프리 결과 반영 (1층: GP 순위 → 투어 포인트) ──
func record_gp(result: Dictionary) -> void:
	var standings: Variant = result.get("standings", [])
	if typeof(standings) != TYPE_ARRAY:
		push_error("SeasonState: gp result has no standings")
		return
	last_gp_standings = Array(standings).duplicate()
	# 전승 업적(그랜드 슬램·퍼펙트 시즌 — D08 §8.11)의 계수. 판정은 아웃게임 층 소관이고
	# 여기서는 "이 투어에서 몇 번 이겼는가"만 센다.
	if int(result.get("player_rank", 0)) == 1 and not bool(result.get("player_retired", false)):
		tour_gp_wins += 1
	for index in range(last_gp_standings.size()):
		var entrant_id := String(last_gp_standings[index])
		var position := index + 1
		# 리타이어한 플레이어는 포인트 0 (엔진이 result에서 이미 판정 — 여기서는 순위만 환산)
		var points := 0
		if data.points_tier1.has(position):
			points = int(data.points_tier1[position])
		else:
			push_error("SeasonState: points_tier1 has no position %d" % position)
		if entrant_id == PLAYER_ID and bool(result.get("player_retired", false)):
			points = 0
		tour_points[entrant_id] = int(tour_points.get(entrant_id, 0)) + points
	race_slot += 1


# 투어 종합 순위 — 투어 포인트 내림차순.
# [가안] 동점 처리 = 직전 그랑프리 결과 순. D13 §6.3이 챔피언십 동률에 같은 규칙을 쓰므로
# (등반 서사 보존 — V-2) 투어 층에도 동형 적용했다. 정본은 투어 동률을 명시하지 않는다.
func tour_standings() -> Array:
	var entries: Array = []
	for entrant_id in tour_points:
		entries.append({
			"id": entrant_id,
			"points": int(tour_points[entrant_id]),
			"tie": last_gp_standings.find(entrant_id),
		})
	entries.sort_custom(func(a, b):
		if int(a["points"]) == int(b["points"]):
			var a_tie := int(a["tie"])
			var b_tie := int(b["tie"])
			if a_tie < 0:
				return false
			if b_tie < 0:
				return true
			return a_tie < b_tie
		return int(a["points"]) > int(b["points"]))
	var order: Array = []
	for entry in entries:
		order.append(String(entry["id"]))
	return order


# ── 투어 결산 (2층: 투어 종합 순위 → 챔피언십 포인트) ──
# 탈락 투어도 그 시점까지의 성적으로 마감한다 (D05 §9.3).
func close_tour() -> Dictionary:
	var order := tour_standings()
	for index in range(order.size()):
		var entrant_id := String(order[index])
		var position := index + 1
		var points := 0
		if data.points_tier2.has(position):
			points = int(data.points_tier2[position])
		else:
			push_error("SeasonState: points_tier2 has no position %d" % position)
		championship_points[entrant_id] = int(championship_points.get(entrant_id, 0)) + points
	var player_position := order.find(PLAYER_ID) + 1
	var summary := {
		"tour_slot": tour_slot,
		"standings": order,
		"player_position": player_position,
		"dropped_out": tour_dropped_out,
		# 탈락 시 S4는 50% 축소 지급 · S3·S10 미지급 (D13 별첨A §3.2 · D06 §2.4)
		"s4_ratio": data.param("param_tour_dropout_s4_ratio") if tour_dropped_out else 1.0,
		"s3_paid": not tour_dropped_out,
		"s10_paid": not tour_dropped_out,
		"gp_wins": tour_gp_wins,
	}
	if player_position == 1:
		season_tour_wins += 1
	tour_slot += 1
	if tour_slot <= tours_per_season():
		begin_tour()
	return summary


# 현 그랑프리가 필패 스크립트 지정 대회인가 (D08 §5.2 — 시즌·투어 슬롯·서킷 3축 대조).
# 필패 파라미터 적용 자체는 별개 트랙이며, 여기서는 '그 대회인가'만 답한다 —
# 발견형 업적 '왕좌의 코앞'(D08 §8.11)의 판정 소재다.
func is_scripted_loss_gp() -> bool:
	var circuit_id := current_circuit_id()
	for loss_id in data.scripted_losses:
		var row: Dictionary = data.scripted_losses[loss_id]
		if int(row.get("season", -1)) != season:
			continue
		if int(row.get("tour_slot", -1)) != tour_slot:
			continue
		if String(row.get("circuit_id", "")) == circuit_id:
			return true
	return false


func mark_dropout() -> void:
	tour_dropped_out = true


# ── 시즌 결산 (D05 §9.4~§9.5 · §10) ──
func season_finished() -> bool:
	return tour_slot > tours_per_season()


func championship_standings() -> Array:
	var entries: Array = []
	for entrant_id in championship_points:
		entries.append({"id": entrant_id, "points": int(championship_points[entrant_id]),
			"tie": last_gp_standings.find(entrant_id)})
	entries.sort_custom(func(a, b):
		if int(a["points"]) == int(b["points"]):
			var a_tie := int(a["tie"])
			var b_tie := int(b["tie"])
			if a_tie < 0:
				return false
			if b_tie < 0:
				return true
			return a_tie < b_tie
		return int(a["points"]) > int(b["points"]))
	var order: Array = []
	for entry in entries:
		order.append(String(entry["id"]))
	return order


# 수학적 조기 확정 판정 (D08 §5.5): 잔여 투어에서 얻을 수 있는 최대 포인트로도
# 선두를 넘을 수 없는 상태. **타이틀 부여·시즌 결산은 시즌 종료 시점에 수행**하며
# 여기서는 공표 여부만 돌려준다 — 조기 종료가 아니다.
func clinched_leader() -> String:
	var order := championship_standings()
	if order.size() < 2:
		return ""
	var remaining_tours := tours_per_season() - tour_slot + 1
	if remaining_tours <= 0:
		return ""
	var max_gain := remaining_tours * _max_tier2_points()
	var leader := String(order[0])
	var runner_up := String(order[1])
	var lead := int(championship_points[leader]) - int(championship_points[runner_up])
	return leader if lead > max_gain else ""


func _max_tier2_points() -> int:
	var maximum := 0
	for position in data.points_tier2:
		maximum = maxi(maximum, int(data.points_tier2[position]))
	return maximum


# 시즌 챔피언 = 5투어 챔피언십 포인트 총합 1위 (D05 §9.4 확정)
func close_season() -> Dictionary:
	var order := championship_standings()
	var champion := String(order[0]) if not order.is_empty() else ""
	champion_history.append(champion)
	# 순위 밖(챔피언십 미등재) = **최하위 순위로 절상** — 총괄 판정 IMPL-141 ①.
	# 근거 = D06 §5.3 G-M1 구속(성적 무관 최소 1슬롯 보장 · 시즌 완주 시 오버홀 발생 예외 없음):
	# 0을 그대로 흘리면 등급 표(순위 1~16)에 걸리는 행이 없어 빈 추첨이 되고, 1로 절상하면
	# 최상위 대우가 된다. 둘 다 정본 위반이므로 원천에서 최하위로 절상한다.
	# **절상은 이 단일 지점 전속** — 하류(HUB-08 진입·결산 화면·통산 기록)는 받은 값을 그대로 쓴다.
	var player_index := order.find(PLAYER_ID)
	var player_position := player_index + 1 if player_index >= 0 else _grid_size()
	# 그리드 레벨: 챔피언 달성 시즌의 **다음 시즌부터** +1, 실패해도 유지 (D13 별첨A §7.4)
	if champion == PLAYER_ID:
		grid_level += data.param_int("param_grid_level_step")
	return {
		"season": season,
		"standings": order,
		"champion": champion,
		"player_position": player_position,
		"grid_level_next": grid_level,
		"tour_wins": season_tour_wins,
		# 에필로그 = 2연속 시즌 챔피언 (D05 §10 · D08 §8.9 — 판정 시점 = 시즌 결산)
		"epilogue": _consecutive_player_titles() >= 2,
	}


func _consecutive_player_titles() -> int:
	var streak := 0
	for index in range(champion_history.size() - 1, -1, -1):
		if String(champion_history[index]) != PLAYER_ID:
			break
		streak += 1
	return streak


func serialize() -> Dictionary:
	return {
		"season": season, "tour_slot": tour_slot, "race_slot": race_slot,
		"grid_level": grid_level,
		"calendar": calendar.duplicate(),
		"tour_points": tour_points.duplicate(),
		"championship_points": championship_points.duplicate(),
		"last_gp_standings": last_gp_standings.duplicate(),
		"tour_dropped_out": tour_dropped_out,
		"tour_gp_wins": tour_gp_wins, "season_tour_wins": season_tour_wins,
		"champion_history": champion_history.duplicate(),
		"resonance_circuit_id": resonance_circuit_id,
		"resonance_sector_slot": resonance_sector_slot,
	}


func restore(payload: Dictionary) -> bool:
	for key in ["season", "tour_slot", "race_slot", "grid_level", "calendar",
			"tour_points", "championship_points", "resonance_circuit_id", "resonance_sector_slot"]:
		if not payload.has(key):
			push_error("SeasonState: malformed payload (missing '%s')" % key)
			return false
	season = int(payload["season"])
	tour_slot = int(payload["tour_slot"])
	race_slot = int(payload["race_slot"])
	grid_level = int(payload["grid_level"])
	calendar = payload["calendar"]
	tour_points = payload["tour_points"]
	championship_points = payload["championship_points"]
	last_gp_standings = payload.get("last_gp_standings", [])
	tour_dropped_out = bool(payload.get("tour_dropped_out", false))
	# 전승 계수 도입(T4) 전 세이브에는 없다 — 0 = "아직 세지 않았다"가 충실값
	tour_gp_wins = int(payload.get("tour_gp_wins", 0))
	season_tour_wins = int(payload.get("season_tour_wins", 0))
	champion_history = payload.get("champion_history", [])
	resonance_circuit_id = String(payload["resonance_circuit_id"])
	resonance_sector_slot = int(payload["resonance_sector_slot"])
	return true
