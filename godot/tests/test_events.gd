# 비전투 이벤트 시스템 (D08 §7 · D13 별첨A §6.5) + 제한 조건 DSL (D12 §5.4).
# 실행: godot --headless --path godot --script tests/test_events.gd
extends SceneTree

var _failures := 0
var _checked := 0


func _init() -> void:
	_d13_event_values()
	_condition_dsl()
	_occurrence_rate()
	_category_distribution()
	_cooldown()
	_stage_pool_scope()
	_reward_guards()
	_variant_selection()
	_serialization()
	print("")
	# 검사 수 하한 — 클래스 로드 실패 등으로 스위트가 쪼그라들면 "통과"가 아니다.
	# 실행되지 않은 검사와 통과한 검사를 구분하는 유일한 수단이다.
	if _checked < 7000:
		print("EVENTS_TEST_FAIL checks=%d < 하한 7000 (스위트 축소·로드 실패 의심)" % _checked)
		quit(1)
		return
	if _failures == 0:
		print("EVENTS_TEST_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("EVENTS_TEST_FAIL failures=%d checks=%d" % [_failures, _checked])
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


func _new_service(seed_value: int, data: GameData) -> EventService:
	var rng := RngService.new()
	rng.setup(seed_value)
	var service := EventService.new()
	service.setup(data, rng)
	return service


# ── D13 별첨A §6.5 확정값 전사 대조 ──
func _d13_event_values() -> void:
	var data := _new_data()
	if data == null:
		return
	_eq_float("D13 §6.5 발생 판정 80%", data.param("param_event_trigger_probability"), 0.80)
	_eq_float("D13 §6.5 재출현 쿨다운 3회", data.param("param_event_cooldown_judgments"), 3.0)
	_eq_float("D13 §6.5 주드 인접 판정 ±2", data.param("param_event_rank_adjacency"), 2.0)
	_eq_float("D13 §3.4 필드 정비 회당 상한 30", data.param("param_repair_field_cap"), 30.0)
	# 카테고리 배분 C1 20% / C2 25% / C3 20% / C4 15% / C5 20%
	var expected_weights := {
		"category_c1": 0.20, "category_c2": 0.25, "category_c3": 0.20,
		"category_c4": 0.15, "category_c5": 0.20,
	}
	var weight_sum := 0.0
	for category_id in expected_weights:
		var row := data.event_category(String(category_id))
		_eq_float("D13 §6.5 %s 배분" % category_id,
			CsvTable.to_float(String(row["weight"])), float(expected_weights[category_id]))
		weight_sum += CsvTable.to_float(String(row["weight"]))
	_eq_float("D13 §6.5 배분 합 1.00", weight_sum, 1.0)
	# C1 회복 10~20 CH / C2 120~250 Cr · 희소 10% → DP 12
	var c1 := data.event_category("category_c1")
	_eq_float("D13 §6.5 C1 회복 하한 10", CsvTable.to_float(String(c1["reward_min"])), 10.0)
	_eq_float("D13 §6.5 C1 회복 상한 20", CsvTable.to_float(String(c1["reward_max"])), 20.0)
	var c2 := data.event_category("category_c2")
	_eq_float("D13 §6.5 C2 금액 하한 120", CsvTable.to_float(String(c2["reward_min"])), 120.0)
	_eq_float("D13 §6.5 C2 금액 상한 250", CsvTable.to_float(String(c2["reward_max"])), 250.0)
	_eq_float("D13 §6.5 C2 희소 확률 10%", CsvTable.to_float(String(c2["rare_probability"])), 0.10)
	_eq_float("D13 §6.5 C2 희소 DP 12", CsvTable.to_float(String(c2["rare_dp"])), 12.0)
	# C1 회복 상한이 필드 정비 회당 상한을 넘지 않는다 (D08 §7.2 경제 가드 — 구조 단언)
	_ok("D08 §7.2 경제 가드: C1 상한 ≤ 필드 정비 상한",
		CsvTable.to_float(String(c1["reward_max"])) <= data.param("param_repair_field_cap"),
		"c1_max=%s cap=%f" % [c1["reward_max"], data.param("param_repair_field_cap")])
	# 풀 규모 (D08 별첨A §6 확정): 공통 28 + 무대 전용 20(무대 5 × 4) = 총 48종
	var common_by_category: Dictionary = {}
	var stage_count := 0
	for event_id in data.events:
		var row: Dictionary = data.events[event_id]
		if String(row["scope"]) == "stage":
			stage_count += 1
			continue
		var key := String(row["category_id"])
		common_by_category[key] = int(common_by_category.get(key, 0)) + 1
	var expected_common := {"category_c1": 6, "category_c2": 6, "category_c3": 8, "category_c4": 4, "category_c5": 4}
	for category_id in expected_common:
		_ok("D08 별첨A §6 공통 풀 %s = %d종" % [category_id, expected_common[category_id]],
			int(common_by_category.get(category_id, 0)) == int(expected_common[category_id]),
			"actual=%s" % str(common_by_category.get(category_id)))
	_ok("D08 별첨A §6 무대 전용 풀 20종", stage_count == 20, "actual=%d" % stage_count)
	_ok("D08 별첨A §6 총 48종 (목표 범위 44~52 내)", data.events.size() == 48, "actual=%d" % data.events.size())
	# 무대별 전용 풀 카테고리 구성 (별첨A 각 무대 총론 표 전사 — 순서 무관 다중집합 대조)
	var expected_stage_pools := {
		"stage_metro_night": ["category_c2", "category_c3", "category_c1", "category_c5"],
		"stage_azure_coast": ["category_c4", "category_c2", "category_c3", "category_c1"],
		"stage_alta_ridge":  ["category_c4", "category_c1", "category_c3", "category_c5"],
		"stage_mirage_flat": ["category_c4", "category_c1", "category_c2", "category_c5"],
		"stage_pulse_dome":  ["category_c3", "category_c3", "category_c5", "category_c1"],
	}
	for stage_id in expected_stage_pools:
		var pool: Array = data.stages.get(stage_id, {}).get("event_pool", [])
		var categories: Array = []
		for pooled_id in pool:
			categories.append(String(data.event(String(pooled_id))["category_id"]))
		categories.sort()
		var expected_cats: Array = Array(expected_stage_pools[stage_id]).duplicate()
		expected_cats.sort()
		_ok("D08 별첨A %s 전용 풀 카테고리 구성" % stage_id, categories == expected_cats, str(categories))


# ── 제한 조건 DSL (D12 §5.4: 필드 비교·AND/OR 한정 · 스크립트 임베드 금지) ──
func _condition_dsl() -> void:
	var dsl := ConditionDsl.new()
	var context := {"player_rank": 3, "act": 2, "jude_rank_delta": 1, "stage": "stage_metro_night"}
	_ok("DSL 빈 조건 = 항상 성립", dsl.evaluate({}, context))
	_ok("DSL 등호", dsl.evaluate({"field": "player_rank", "op": "==", "value": 3}, context))
	_ok("DSL 부등호 ≤", dsl.evaluate({"field": "player_rank", "op": "<=", "value": 5}, context))
	_ok("DSL 부등호 미성립", not dsl.evaluate({"field": "player_rank", "op": ">", "value": 5}, context))
	_ok("DSL 문자열 비교", dsl.evaluate({"field": "stage", "op": "==", "value": "stage_metro_night"}, context))
	_ok("DSL in", dsl.evaluate({"field": "act", "op": "in", "value": [2, 3]}, context))
	_ok("DSL all (전건 성립)", dsl.evaluate({"all": [
		{"field": "act", "op": ">=", "value": 2},
		{"field": "jude_rank_delta", "op": "<=", "value": 2}]}, context))
	_ok("DSL all (일부 미성립)", not dsl.evaluate({"all": [
		{"field": "act", "op": ">=", "value": 2},
		{"field": "player_rank", "op": ">", "value": 10}]}, context))
	_ok("DSL any", dsl.evaluate({"any": [
		{"field": "player_rank", "op": ">", "value": 10},
		{"field": "act", "op": "==", "value": 2}]}, context))
	_ok("DSL not", dsl.evaluate({"not": {"field": "player_rank", "op": ">", "value": 10}}, context))
	_ok("DSL 정상 경로에서 오류 없음", dsl.is_ok(), str(dsl.errors))
	# 미지 필드·미지 연산자는 조용한 false가 아니라 오류다 (오타 하나로 변형이 영구 미발동되는 것을 막는다)
	var strict := ConditionDsl.new()
	strict.evaluate({"field": "no_such_field", "op": "==", "value": 1}, context)
	_ok("DSL 미지 필드 = 오류", not strict.is_ok(), str(strict.errors))
	var strict2 := ConditionDsl.new()
	strict2.evaluate({"field": "player_rank", "op": "=~", "value": 1}, context)
	_ok("DSL 미지 연산자 = 오류", not strict2.is_ok(), str(strict2.errors))
	var strict3 := ConditionDsl.new()
	strict3.evaluate({"all": []}, context)
	_ok("DSL 빈 all = 오류", not strict3.is_ok(), str(strict3.errors))
	var strict4 := ConditionDsl.new()
	strict4.evaluate({"script": "engine.charge = 99"}, context)
	_ok("DSL 미지 표현식(스크립트 임베드 시도) = 오류", not strict4.is_ok(), str(strict4.errors))
	# 순서 비교는 수치 전용 — 문자열 순서 비교는 로케일 의존이라 허용하지 않는다
	var strict5 := ConditionDsl.new()
	strict5.evaluate({"field": "stage", "op": "<", "value": "z"}, context)
	_ok("DSL 문자열 순서 비교 = 오류", not strict5.is_ok(), str(strict5.errors))


# ── 발생률 (D13 §6.5 80% → 투어당 기대 2.4회 / 판정 4회) ──
func _occurrence_rate() -> void:
	var data := _new_data()
	if data == null:
		return
	var service := _new_service(1234, data)
	var trials := 4000
	for i in range(trials):
		service.judge("stage_metro_night", _context())
	var rate := float(service.occurrence_count) / float(service.judgment_count)
	# 쿨다운으로 후보가 비면 미발생이 되므로 실측률은 발생 확률의 하한을 밑돌 수 있다.
	# 상한은 발생 확률 자체다 — 그보다 높으면 판정이 확률을 무시하고 있다는 뜻이다.
	var probability := data.param("param_event_trigger_probability")
	_ok("발생률 ≤ 발생 확률", rate <= probability + 0.02, "rate=%f p=%f" % [rate, probability])
	_ok("발생률이 확률에 근접 (쿨다운 손실 10%p 이내)", rate >= probability - 0.10,
		"rate=%f p=%f" % [rate, probability])
	# 투어당 4대회 = 판정 4회 기준 기대 발생 2.4회 이상 (D13 §6.5 "투어당 기대 2.4회")
	_ok("판정 4회 기대 발생 ≥ 2.4", rate * 4.0 >= 2.4, "expected=%f" % (rate * 4.0))
	_ok("이벤트 판정 중 데이터 침묵 기본값 0", data.is_ok())


func _context() -> Dictionary:
	return {"player_rank": 8, "act": 1, "jude_rank_delta": 5, "season": 1, "vane_stage": 1}


# ── 카테고리 배분이 D13 비율을 따르는가 ──
func _category_distribution() -> void:
	var data := _new_data()
	if data == null:
		return
	var service := _new_service(555, data)
	var counts: Dictionary = {}
	var total := 0
	for i in range(6000):
		var result := service.judge("stage_metro_night", _context())
		if result.is_empty():
			continue
		var category_id := String(result["category_id"])
		counts[category_id] = int(counts.get(category_id, 0)) + 1
		total += 1
	_ok("발생 표본 확보", total > 3000, "total=%d" % total)
	for category_id in data.event_categories:
		var expected := CsvTable.to_float(String(data.event_categories[category_id]["weight"]))
		var observed := float(counts.get(category_id, 0)) / float(total)
		_ok("배분 실측 %s ≈ %.2f" % [category_id, expected], absf(observed - expected) < 0.03,
			"observed=%f expected=%f" % [observed, expected])


# ── 쿨다운 (D08 §7.3 확정: 동일 인스턴스 3회 판정 간격) ──
func _cooldown() -> void:
	var data := _new_data()
	if data == null:
		return
	var service := _new_service(777, data)
	var cooldown := data.param_int("param_event_cooldown_judgments")
	var first := {}
	for i in range(200):
		var result := service.judge("stage_metro_night", _context())
		if not result.is_empty():
			first = result
			break
	_ok("이벤트 1건 발생", not first.is_empty())
	if first.is_empty():
		return
	var event_id := String(first["event_id"])
	_ok("발생 직후 쿨다운 = %d" % cooldown, service.cooldown_of(event_id) == cooldown,
		"cooldown=%d" % service.cooldown_of(event_id))
	# 쿨다운 구간 안에서는 같은 인스턴스가 다시 나오지 않는다
	var reappeared_within := false
	for i in range(cooldown):
		var result := service.judge("stage_metro_night", _context())
		if not result.is_empty() and String(result["event_id"]) == event_id:
			reappeared_within = true
	_ok("쿨다운 구간 내 재출현 0", not reappeared_within)
	_ok("쿨다운 소진", service.cooldown_of(event_id) == 0, "cooldown=%d" % service.cooldown_of(event_id))


# ── 무대 전용 풀은 해당 무대에서만 (D08 §7.3 무대 결속) ──
func _stage_pool_scope() -> void:
	var data := _new_data()
	if data == null:
		return
	# 무대 5종 전수 — 발생하는 무대 전용 이벤트가 전부 자기 무대 풀 소속인지 (교차 유입 0)
	for stage_id in ["stage_metro_night", "stage_azure_coast", "stage_alta_ridge",
			"stage_mirage_flat", "stage_pulse_dome"]:
		var service := _new_service(888, data)
		var own_pool: Array = data.stages[stage_id].get("event_pool", [])
		var stage_events := 0
		var foreign := 0
		for i in range(3000):
			var result := service.judge(String(stage_id), _context())
			if result.is_empty():
				continue
			if String(data.event(String(result["event_id"]))["scope"]) != "stage":
				continue
			stage_events += 1
			if not own_pool.has(String(result["event_id"])):
				foreign += 1
		_ok("무대 전용 이벤트 발생 (%s)" % stage_id, stage_events > 0, "count=%d" % stage_events)
		_ok("타 무대 전용 풀 교차 유입 0 (%s)" % stage_id, foreign == 0, "foreign=%d" % foreign)
	# 무대를 지정하지 않으면 무대 전용은 후보에서 빠진다
	var service2 := _new_service(888, data)
	var leaked := 0
	for i in range(3000):
		var result := service2.judge("stage_nonexistent", _context())
		if not result.is_empty() and String(data.event(String(result["event_id"]))["scope"]) == "stage":
			leaked += 1
	_ok("다른 무대에서 무대 전용 풀 미유입", leaked == 0, "leaked=%d" % leaked)


# ── 보상 경제 가드 (D08 §7.2 · D06 §3.4) ──
func _reward_guards() -> void:
	var data := _new_data()
	if data == null:
		return
	var service := _new_service(999, data)
	var cap := data.param_int("param_repair_field_cap")
	var seen_types: Dictionary = {}
	var rare_seen := false
	for i in range(6000):
		var result := service.judge("stage_metro_night", _context())
		if result.is_empty():
			continue
		var reward: Dictionary = result["reward"]
		var reward_type := String(reward["type"])
		seen_types[reward_type] = true
		var amount := int(reward["amount"])
		_ok("보상 음수 0", amount >= 0, "type=%s amount=%d" % [reward_type, amount])
		if reward_type == "chassis":
			_ok("C1 회복 ≤ 필드 정비 회당 상한", amount <= cap, "amount=%d cap=%d" % [amount, cap])
		if reward_type == "credit":
			_ok("C2 금액 범위", amount >= 120 and amount <= 250, "amount=%d" % amount)
		if bool(reward.get("rare", false)):
			rare_seen = true
			_ok("희소 보상 = DP 12", reward_type == "dp" and amount == 12, str(reward))
	_ok("보상 유형이 데이터 enum 범위 안", not seen_types.has(""), str(seen_types.keys()))
	_ok("희소 분기 도달", rare_seen)
	# Source 신설 금지 (D06 §2.1 S1~S10 외) — 이벤트가 낼 수 있는 보상 유형은 데이터가 결정한다
	var allowed: Dictionary = {}
	for category_id in data.event_categories:
		allowed[String(data.event_categories[category_id]["reward_type"])] = true
	allowed["dp"] = true      # 희소 분기 (C2 rare_dp)
	for reward_type in seen_types:
		_ok("보상 유형 '%s' = 데이터 등재분" % reward_type, allowed.has(reward_type), str(allowed.keys()))


# ── 변형 4축 선택 (D08 §7.3) ──
func _variant_selection() -> void:
	var data := _new_data()
	if data == null:
		return
	var service := _new_service(2468, data)
	# 주드 인접 (±2) 성립 → 인접 변형 / 미성립 → 기본 변형
	var adjacent := service._select_variant("event_rank_friction",
		{"player_rank": 8, "act": 1, "jude_rank_delta": 1, "season": 1, "vane_stage": 1})
	_ok("주드 인접 변형 활성", String(adjacent["tag"]) == "jude_adjacent", str(adjacent))
	var distant := service._select_variant("event_rank_friction",
		{"player_rank": 8, "act": 1, "jude_rank_delta": 6, "season": 1, "vane_stage": 1})
	_ok("주드 비인접 = 기본 변형", String(distant["tag"]) == "default", str(distant))
	# 막 결속 (2막 진입 후)
	var act2 := service._select_variant("event_control_access",
		{"player_rank": 8, "act": 2, "jude_rank_delta": 6, "season": 1, "vane_stage": 1})
	_ok("2막 변형 활성", String(act2["tag"]) == "act2_clue_slot", str(act2))
	var act1 := service._select_variant("event_control_access",
		{"player_rank": 8, "act": 1, "jude_rank_delta": 6, "season": 1, "vane_stage": 1})
	_ok("1막 = 기본 변형", String(act1["tag"]) == "default", str(act1))
	# 성적 태그
	var front := service._select_variant("event_exposure_deal",
		{"player_rank": 2, "act": 1, "jude_rank_delta": 6, "season": 1, "vane_stage": 1})
	_ok("선두권 변형 활성", String(front["tag"]) == "front_runner", str(front))
	# 막 태그 (시즌 2+ 재개막)
	var returning := service._select_variant("event_mn_neon_festival",
		{"player_rank": 8, "act": 1, "jude_rank_delta": 6, "season": 2, "vane_stage": 1})
	_ok("시즌 2+ 재개막 변형", String(returning["tag"]) == "returning_opener", str(returning))
	# 변형이 없는 이벤트는 빈 태그 — 부재값이 아니라 '변형 없음'이라는 사실
	var none := service._select_variant("event_fan_letter", _context())
	_ok("변형 없는 이벤트 = 빈 태그", String(none["tag"]) == "", str(none))
	# 변형 텍스트 키가 스트링 테이블에 있다 (V2가 데이터 축을 보지만 런타임 축도 확인)
	for event_id in data.event_variants:
		for variant in data.event_variants_of(String(event_id)):
			var text_key := String(Dictionary(variant).get("text_key", ""))
			_ok("변형 텍스트 키 등재: %s" % text_key, data.strings.has_key(text_key), text_key)


# ── 직렬화 (쿨다운 카운터가 세이브에 남아야 재출현 간격이 유지된다 — D12 §5.4) ──
func _serialization() -> void:
	var data := _new_data()
	if data == null:
		return
	var service := _new_service(1357, data)
	var event_id := ""
	for i in range(200):
		var result := service.judge("stage_metro_night", _context())
		if not result.is_empty():
			event_id = String(result["event_id"])
			break
	_ok("직렬화 대상 이벤트 발생", event_id != "")
	var payload := service.serialize()
	var restored := _new_service(9999, data)
	_ok("복원 성립", restored.restore(payload))
	_ok("쿨다운 복원", restored.cooldown_of(event_id) == service.cooldown_of(event_id),
		"restored=%d original=%d" % [restored.cooldown_of(event_id), service.cooldown_of(event_id)])
	_ok("판정 누계 복원", restored.judgment_count == service.judgment_count)
	_ok("발생 누계 복원", restored.occurrence_count == service.occurrence_count)
	var broken := _new_service(9999, data)
	_ok("결손 payload 거부", not broken.restore({"judgment_count": 1}))
