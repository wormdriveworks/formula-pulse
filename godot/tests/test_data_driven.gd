# 데이터 드리븐 검증 (불변규칙 2의 **코드 측** 가드) — 값을 갈아 끼웠을 때 거동이 따라오는가.
# 실행: godot --headless --path godot --script tests/test_data_driven.gd
#
# 왜 이 스위트가 따로 필요한가:
# 다른 스위트는 기대값을 같은 데이터에서 읽으므로, 코드가 데이터 대신 **현재 값과 같은 리터럴**을
# 써도 구분하지 못한다(자기 일관성). "비용 == data.param(...)" 형태의 단언은 `charge -= 1`처럼
# 하드코딩된 구현을 그대로 통과시킨다. 유일한 판별법은 데이터를 바꿔 보는 것이다.
#
# 픽스처(`tests/fixtures/tables/`)는 기본 데이터와 **의도적으로 다른 값**을 담는다.
# 파일 단위 대체이므로 갈아 끼우지 않은 표는 기본 디렉토리에서 읽힌다.
extends SceneTree

const FIXTURE_DIR := "res://tests/fixtures/tables/"
const MIN_CHECKS := 34

var _failures := 0
var _checked := 0


func _init() -> void:
	_fixture_actually_differs()
	_engine_reads_data()
	_outgame_reads_data()
	_reel_columns_are_distinct()
	print("")
	if _checked < MIN_CHECKS:
		print("DATA_DRIVEN_TEST_FAIL checks=%d < 하한 %d (스위트 축소·로드 실패 의심)" % [_checked, MIN_CHECKS])
		quit(1)
		return
	if _failures == 0:
		print("DATA_DRIVEN_TEST_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("DATA_DRIVEN_TEST_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if not condition:
		_failures += 1
		print("  [FAIL] %s %s" % [label, detail])


func _eq_float(label: String, actual: float, expected: float, tolerance: float = 0.001) -> void:
	_ok(label, absf(actual - expected) <= tolerance, "actual=%f expected=%f" % [actual, expected])


# RngService는 setup() 없이 쓰면 스트림이 비어 있다 — 헬퍼로 통일해 누락을 막는다.
func _rng(seed_value: int) -> RngService:
	var rng := RngService.new()
	rng.setup(seed_value)
	return rng


func _fixture_data() -> GameData:
	var data := GameData.new()
	data.tables_override_dir = FIXTURE_DIR
	if not data.load_all():
		_failures += 1
		print("  [FAIL] fixture data load")
		return null
	return data


func _default_data() -> GameData:
	var data := GameData.new()
	if not data.load_all():
		_failures += 1
		print("  [FAIL] default data load")
		return null
	return data


# 픽스처가 실제로 다른 값을 담고 있어야 이 스위트가 의미를 갖는다.
# (픽스처가 기본과 같아지면 전 검사가 조용히 무의미해진다 — 그 상태를 먼저 배제한다.)
func _fixture_actually_differs() -> void:
	var fixture := _fixture_data()
	var default_data := _default_data()
	if fixture == null or default_data == null:
		return
	var differing := 0
	for key in ["param_charge_hold_cost", "param_charge_cap", "param_gauge_full_threshold",
			"param_chassis_max", "param_charge_exchange_cr"]:
		if absf(fixture.param(key) - default_data.param(key)) > 0.0001:
			differing += 1
	_ok("픽스처가 기본 데이터와 다르다", differing == 5, "differing=%d/5" % differing)
	_ok("갈아 끼우지 않은 표는 기본에서 읽힌다",
		fixture.points_tier1.size() == default_data.points_tier1.size()
		and int(fixture.points_tier1[1]) == int(default_data.points_tier1[1]),
		"fixture=%s default=%s" % [str(fixture.points_tier1.get(1)), str(default_data.points_tier1.get(1))])
	_ok("픽스처 로드에서 침묵 기본값 0", fixture.is_ok())


# ── 엔진이 값을 데이터에서 읽는가 (리터럴이면 픽스처 값을 따라오지 않는다) ──
func _engine_reads_data() -> void:
	var data := _fixture_data()
	if data == null:
		return
	var rng := RngService.new()
	rng.setup(1111)
	var engine := RaceEngine.new()
	engine.setup(data, rng)
	engine.start_gp()
	# 섀시 최대치 (픽스처 80 · 기본 100)
	_eq_float("GP 개시 섀시 = 데이터 값", engine.chassis, data.param("param_chassis_max"))
	_ok("섀시가 기본값 100을 쓰지 않는다", absf(engine.chassis - 100.0) > 0.0001,
		"chassis=%f" % engine.chassis)
	engine.begin_turn()
	engine.spin()
	# 홀드 비용 (픽스처 3 · 기본 1)
	engine.charge = data.param_int("param_charge_cap")
	var before := engine.charge
	engine.hold_respin([0])
	_eq_float("홀드 비용 = 데이터 값", float(before - engine.charge),
		data.param("param_charge_hold_cost"))
	_ok("홀드 비용이 리터럴 1이 아니다", before - engine.charge != 1,
		"deducted=%d" % (before - engine.charge))
	# 트러블 무효화 비용 (픽스처 5 · 기본 2)
	var probe := RaceEngine.new()
	probe.setup(data, _rng(2001))
	probe.start_gp()
	probe.begin_turn()
	probe.spin()
	probe.charge = data.param_int("param_charge_cap")   # 픽스처 상한 12 > 비용 5
	probe.provisional = [RaceTypes.SYMBOL_TROUBLE, RaceTypes.SYMBOL_LINE, RaceTypes.SYMBOL_LINE]
	var before2 := probe.charge
	probe.negate_trouble()
	_eq_float("트러블 무효 비용 = 데이터 값", float(before2 - probe.charge),
		data.param("param_charge_negate_cost"))
	_ok("트러블 무효 비용이 리터럴 2가 아니다", before2 - probe.charge != 2,
		"deducted=%d" % (before2 - probe.charge))
	# 차지 보유 상한 (픽스처 4 · 기본 10)
	var cap_probe := RaceEngine.new()
	cap_probe.setup(data, _rng(2002))
	cap_probe.start_gp()
	cap_probe.begin_turn()
	cap_probe.spin()
	cap_probe.charge = 0
	cap_probe.provisional = [RaceTypes.SYMBOL_PULSE, RaceTypes.SYMBOL_PULSE, RaceTypes.SYMBOL_PULSE]
	cap_probe.confirm(0.0)
	_ok("차지 상한 = 데이터 값", cap_probe.charge <= data.param_int("param_charge_cap"),
		"charge=%d cap=%d" % [cap_probe.charge, data.param_int("param_charge_cap")])
	# 상한에 **실제로 부딪히게** 누적한다 — 한 번의 획득으로는 상한이 리터럴이든 데이터든
	# 결과가 같아 판별되지 않는다. 상한까지 채운 뒤 그 값이 데이터 값인지 본다.
	for extra_turn in range(12):
		cap_probe.begin_turn()
		cap_probe.spin()
		cap_probe.provisional = [RaceTypes.SYMBOL_PULSE, RaceTypes.SYMBOL_PULSE, RaceTypes.SYMBOL_PULSE]
		cap_probe.confirm(0.0)
		if cap_probe.finished:
			break
	_ok("차지가 데이터 상한까지 찬다", cap_probe.charge == data.param_int("param_charge_cap"),
		"charge=%d cap=%d" % [cap_probe.charge, data.param_int("param_charge_cap")])
	_ok("차지 상한이 리터럴 10이 아니다", cap_probe.charge != 10, "charge=%d" % cap_probe.charge)
	# 만충 임계 (픽스처 60 · 기본 100)
	var gauge_probe := RaceEngine.new()
	gauge_probe.setup(data, _rng(2003))
	gauge_probe.start_gp()
	for entrant_id in gauge_probe.entrants:
		if entrant_id == RaceEngine.PLAYER_ID:
			continue
		gauge_probe.entrants[entrant_id]["pace"] = 0.0
		gauge_probe.entrants[entrant_id]["seed_aggression"] = 0.0
		gauge_probe.entrants[entrant_id]["form"] = 0.0
		gauge_probe.entrants[entrant_id]["rush_roll"] = 0.0
		gauge_probe.entrants[entrant_id]["rush_lap1"] = 0.0
	gauge_probe.begin_turn()
	gauge_probe.spin()
	gauge_probe.front_gauge = data.param("param_gauge_full_threshold") - 1.0
	gauge_probe.provisional = [RaceTypes.SYMBOL_SLIPSTREAM, RaceTypes.SYMBOL_SLIPSTREAM,
		RaceTypes.SYMBOL_SLIPSTREAM]
	gauge_probe.confirm(0.0)
	_ok("만충 임계 = 데이터 값 (60에서 듀얼 예약)",
		gauge_probe.pending_duel == RaceTypes.DuelType.OVERTAKE,
		"pending=%d front=%f" % [gauge_probe.pending_duel, gauge_probe.front_gauge])
	_ok("게이지가 기본 임계 100을 넘지 않고 만충 처리",
		gauge_probe.front_gauge <= data.param("param_gauge_full_threshold") + 0.001,
		"front=%f" % gauge_probe.front_gauge)
	_ok("데이터 주도 주행에서 침묵 기본값 0", data.is_ok())


# ── 아웃게임이 값을 데이터에서 읽는가 ──
func _outgame_reads_data() -> void:
	var data := _fixture_data()
	if data == null:
		return
	var state := OutgameState.new()
	state.setup(data)
	# 덱 시작 슬롯 (픽스처 1 · 기본 2)
	_ok("덱 시작 슬롯 = 데이터 값", state.deck_slots == data.param_int("param_deck_slots_start"),
		"slots=%d" % state.deck_slots)
	_ok("덱 슬롯이 리터럴 2가 아니다", state.deck_slots != 2, "slots=%d" % state.deck_slots)
	# 환전 상한·환전율 (픽스처 2차지 · 7 Cr)
	var payout := state.exchange_charge(10, true)
	_ok("환전 = 데이터 상한 × 데이터 환전율",
		payout == data.param_int("param_charge_exchange_cap") * data.param_int("param_charge_exchange_cr"),
		"payout=%d" % payout)
	_ok("환전이 기본값(5 × 20 = 100)이 아니다", payout != 100, "payout=%d" % payout)
	# 테오 패시브 (픽스처 −50% · 기본 −10%) — 리터럴 0.9 구현을 판별한다
	var expected_cost := int(round(data.param("param_repair_base_cr") * 0.5))
	_ok("정비비에 크루 패시브가 데이터대로 반영", state.field_repair_cost() == expected_cost,
		"actual=%d expected=%d" % [state.field_repair_cost(), expected_cost])
	_ok("정비비가 리터럴 0.9 계수를 쓰지 않는다",
		state.field_repair_cost() != int(round(data.param("param_repair_base_cr") * 0.9)),
		"actual=%d" % state.field_repair_cost())
	# 필드 정비 회당 상한 (픽스처 7 · 기본 30)
	state.gain_credits(100000)
	_ok("필드 정비 상한 = 데이터 값", state.field_repair(999) == data.param_int("param_repair_field_cap"),
		"restored=%d" % state.field_repair(0))
	# 회차 체증 (픽스처 ×2.0 · 기본 ×1.5)
	var first := state.field_repair_cost()
	state.field_repair(1)
	var second := state.field_repair_cost()
	_eq_float("회차 체증 = 데이터 값", float(second) / float(first),
		data.param("param_repair_escalation"), 0.05)
	# 튜닝 단계 상한 (픽스처 2 · 기본 5)
	var tuning_state := OutgameState.new()
	tuning_state.setup(data)
	tuning_state.gain_credits(100000)
	var bought := 0
	while tuning_state.buy_tuning("tuning_t1"):
		bought += 1
		if bought > 9:
			break
	_ok("튜닝 단계 상한 = 데이터 값", bought == data.param_int("param_tuning_max_step"),
		"bought=%d cap=%d" % [bought, data.param_int("param_tuning_max_step")])
	# 사샤 패시브 (픽스처 −50%)
	tuning_state.gain_drive_data(1000)
	tuning_state.recruit_crew("crew_sasha")
	_ok("해금 비용 경감 = 데이터 값", tuning_state.unlock_cost(100) == 50,
		"actual=%d" % tuning_state.unlock_cost(100))
	# 소모품 휴대 상한 (픽스처 1 · 기본 2)
	var shop := OutgameState.new()
	shop.setup(data)
	shop.gain_credits(100000)
	_ok("소모품 1개", shop.buy_consumable("consumable_p1"))
	_ok("휴대 상한 = 데이터 값 (2번째 거부)", not shop.buy_consumable("consumable_p2"))
	_ok("아웃게임 데이터 주도 경로에서 침묵 기본값 0", data.is_ok())


# ── 릴 열이 실제로 릴별로 읽히는가 (E12: 항상 릴1 열을 쓰는 구현 판별) ──
# 픽스처는 릴1=슬립 100% / 릴2=브레이킹 100% / 릴3=라인 100%로 열을 완전히 분리한다.
func _reel_columns_are_distinct() -> void:
	var data := _fixture_data()
	if data == null:
		return
	# 섹터 속성 Δ가 열에 가산되므로(스트레이트 = 슬립 +0.06) 단발 스핀으로는 판정할 수 없다.
	# 다수 표본의 **최빈값**으로 본다 — 열이 릴별로 읽히면 각 릴의 최빈값이 그 열의 심볼이다.
	var counts := [{}, {}, {}]
	var spins := 300
	for attempt in range(spins):
		var engine := RaceEngine.new()
		engine.setup(data, _rng(3000 + attempt))
		engine.start_gp()
		engine.begin_turn()
		engine.spin()
		var provisional := engine.get_provisional()
		if provisional.size() != 3:
			continue
		for index in range(3):
			var symbol_id := String(provisional[index])
			counts[index][symbol_id] = int(counts[index].get(symbol_id, 0)) + 1
	var expected := [RaceTypes.SYMBOL_SLIPSTREAM, RaceTypes.SYMBOL_BRAKING, RaceTypes.SYMBOL_LINE]
	for index in range(3):
		var top_symbol := ""
		var top_count := 0
		for symbol_id in counts[index]:
			if int(counts[index][symbol_id]) > top_count:
				top_count = int(counts[index][symbol_id])
				top_symbol = String(symbol_id)
		_ok("릴%d 최빈 심볼 = 릴%d 열" % [index + 1, index + 1], top_symbol == String(expected[index]),
			"top=%s (%d/%d) counts=%s" % [top_symbol, top_count, spins, str(counts[index])])
		_ok("릴%d 열이 지배적 (≥80%%)" % (index + 1), float(top_count) / float(spins) >= 0.8,
			"ratio=%f" % (float(top_count) / float(spins)))
