# 비전투 이벤트 (D08 §7 · D13 별첨A §6.5) — 발생 판정 · 카테고리 배분 · 쿨다운 · 변형 4축.
#
# 발생 지점 = 그랑프리 간 노드 (투어 내부). 릴 RNG와 별개 채널인 event 스트림을 쓴다
# (D12 §6.1) — 이벤트 추첨이 릴 결과에 영향을 주지 않는다는 것이 스트림 분리의 요점이다.
#
# 경제 가드 (D08 §7.2 구속): C1 회복량은 필드 정비 회당 상한을 초과할 수 없고,
# 보상은 D06 Source 범위(S9) 안에서만 나온다 — Source 신설 금지.
class_name EventService
extends RefCounted

var data: GameData
var rng: RngService

# 인스턴스별 쿨다운 잔여 판정 횟수 (D08 §7.3 확정: 동일 인스턴스 3회 판정 간격)
var _cooldowns: Dictionary = {}
# 발생 판정 누계 — 투어당 기대 발생 검증(D13 §6.5 2.4회)에 쓰인다
var judgment_count: int = 0
var occurrence_count: int = 0


func setup(game_data: GameData, rng_service: RngService) -> void:
	data = game_data
	rng = rng_service


# 그랑프리 간 노드 1회 판정. 반환: {} = 미발생 / 이벤트 사전 = 발생.
# context = 조건 DSL이 참조하는 값 사전 (순위·막·무대·관계 상태 등 — 호출 층이 채운다).
func judge(stage_id: String, context: Dictionary) -> Dictionary:
	judgment_count += 1
	_tick_cooldowns()
	if rng.randf("event") >= data.param("param_event_trigger_probability"):
		return {}
	var category_id := _pick_category()
	if category_id == "":
		return {}
	var candidates := _candidates(category_id, stage_id)
	if candidates.is_empty():
		# 카테고리가 뽑혔는데 후보가 전부 쿨다운이면 미발생으로 둔다 —
		# 다른 카테고리로 옮겨 뽑으면 D13 §6.5의 배분 비율이 조용히 왜곡된다.
		return {}
	var picked := String(candidates[rng.stream("event").randi_range(0, candidates.size() - 1)])
	_cooldowns[picked] = data.param_int("param_event_cooldown_judgments")
	occurrence_count += 1
	var event_row := data.event(picked)
	var reward := _roll_reward(category_id)
	return {
		"event_id": picked,
		"category_id": category_id,
		"name_key": String(event_row["name_key"]),
		# 기본 본문 키 (개선 2026-09-03 E1 — `events.csv body_key` 열). 화면이 표를 다시 찾지 않게
		# 판정 결과에 함께 싣는다 — 화면의 재조회는 미등재 id 에서 적재 상태(`_load_ok`)를 떨어뜨린다.
		"body_key": String(event_row.get("body_key", "")),
		"variant": _select_variant(picked, context),
		"reward": reward,
	}


# 카테고리 배분 (D13 별첨A §6.5) — 가중 추첨. 가중치는 데이터에만 있다.
func _pick_category() -> String:
	var ids: Array = []
	var weights: Array = []
	for category_id in data.event_categories:
		ids.append(category_id)
		weights.append(CsvTable.to_float(String(data.event_categories[category_id]["weight"])))
	if ids.is_empty():
		push_error("EventService: no event categories loaded")
		return ""
	return String(ids[rng.pick_weighted("event", weights)])


# 후보 = 해당 카테고리 · 쿨다운 아님 · (공통 풀 또는 현 무대 전용 풀)
func _candidates(category_id: String, stage_id: String) -> Array:
	var stage_pool: Array = []
	if data.stages.has(stage_id):
		var pool: Variant = data.stages[stage_id].get("event_pool", [])
		if typeof(pool) == TYPE_ARRAY:
			stage_pool = pool
	var candidates: Array = []
	for event_id in data.events:
		var row: Dictionary = data.events[event_id]
		if String(row["category_id"]) != category_id:
			continue
		if int(_cooldowns.get(event_id, 0)) > 0:
			continue
		if String(row["scope"]) == "stage" and not stage_pool.has(event_id):
			continue
		candidates.append(event_id)
	return candidates


func _tick_cooldowns() -> void:
	for event_id in _cooldowns.keys():
		var remaining := int(_cooldowns[event_id]) - 1
		if remaining <= 0:
			_cooldowns.erase(event_id)
		else:
			_cooldowns[event_id] = remaining


func cooldown_of(event_id: String) -> int:
	return int(_cooldowns.get(event_id, 0))


# 보상 (D13 별첨A §6.5 · D08 §7.2 경제 가드). 범위는 카테고리 단위 값이다.
func _roll_reward(category_id: String) -> Dictionary:
	var category := data.event_category(category_id)
	if category.is_empty():
		return {"type": "none", "amount": 0}
	var reward_type := String(category["reward_type"])
	var rare_probability := CsvTable.to_float(String(category["rare_probability"]))
	if rare_probability > 0.0 and rng.randf("event") < rare_probability:
		return {"type": "dp", "amount": CsvTable.to_int(String(category["rare_dp"])), "rare": true}
	var minimum := CsvTable.to_int(String(category["reward_min"]))
	var maximum := CsvTable.to_int(String(category["reward_max"]))
	if maximum <= 0:
		return {"type": reward_type, "amount": 0, "rare": false}
	var amount := rng.stream("event").randi_range(minimum, maximum)
	if reward_type == "chassis":
		# 경제 가드: 필드 정비 회당 상한 초과 금지 (D08 §7.2 · D06 §3.4 구속)
		amount = mini(amount, data.param_int("param_repair_field_cap"))
	return {"type": reward_type, "amount": amount, "rare": false}


# 변형 4축 (D08 §7.3): 성적 / 관계 / 무대 / 막. 조건이 성립한 첫 변형을 쓴다 —
# 우선순위는 데이터 등재 순서이고, 동시 성립 시 결정적으로 첫 항이 선택된다.
func _select_variant(event_id: String, context: Dictionary) -> Dictionary:
	var variants: Array = data.event_variants_of(event_id)
	var dsl := ConditionDsl.new()
	for variant in variants:
		if typeof(variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = variant
		if dsl.evaluate(entry.get("condition", {}), context):
			return {"tag": String(entry.get("tag", "")), "text_key": String(entry.get("text_key", ""))}
	if not dsl.is_ok():
		push_error("EventService: condition DSL errors on '%s': %s" % [event_id, str(dsl.errors)])
	return {"tag": "", "text_key": ""}


func serialize() -> Dictionary:
	return {
		"cooldowns": _cooldowns.duplicate(),
		"judgment_count": judgment_count,
		"occurrence_count": occurrence_count,
	}


func restore(payload: Dictionary) -> bool:
	if not payload.has("cooldowns"):
		push_error("EventService: malformed payload")
		return false
	_cooldowns = payload["cooldowns"]
	judgment_count = int(payload["judgment_count"])
	occurrence_count = int(payload["occurrence_count"])
	return true
