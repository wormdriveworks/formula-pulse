# MS-1 완료 판정 1·4 검증 — 1 GP 관통 (무개입 / 개입 양 경로) + GP 소요 분량 로그.
# 실행: godot --headless --path godot --script tests/test_core_loop.gd
extends SceneTree


func _init() -> void:
	var failures := 0
	failures += _run_gp(42, false)
	failures += _run_gp(42, true)
	failures += _run_gp(7, true)
	if failures == 0:
		print("CORE_LOOP_TEST_PASS")
		quit(0)
	else:
		print("CORE_LOOP_TEST_FAIL failures=", failures)
		quit(1)


func _run_gp(seed_value: int, intervene: bool) -> int:
	var data := GameData.new()
	if not data.load_all():
		print("FAIL data load")
		return 1
	var rng := RngService.new()
	rng.setup(seed_value)
	var engine := RaceEngine.new()
	engine.setup(data, rng)
	engine.start_gp()
	var guard := 200
	while not engine.finished and guard > 0:
		guard -= 1
		var info := engine.begin_turn()
		if String(info.get("type", "")) == "finished":
			break
		engine.spin()
		if intervene:
			_intervention_policy(engine, info)
			engine.confirm(1.0)  # 여유 구간 확정 = 모멘텀 경로
		else:
			engine.timeout()      # 무개입 = 타임아웃 자동 확정 경로
	if guard <= 0:
		print("FAIL guard exhausted (non-terminating GP)")
		return 1
	if not engine.finished or engine.result.is_empty():
		print("FAIL no result")
		return 1
	var standings: Array = engine.result["standings"]
	if standings.size() != 16:
		print("FAIL standings size=", standings.size())
		return 1
	var minutes := engine.estimated_minutes()
	print("GP_DONE seed=%d intervene=%s rank=P%d turns=%d duels=%d charge=%d chassis=%.0f est_minutes=%.1f" % [
		seed_value, str(intervene), int(engine.result["player_rank"]),
		int(engine.result["turns"]), int(engine.result["duels"]),
		engine.charge, engine.chassis, minutes])
	# D05 §2.2 기준 10~15분과 자릿수 정합 (완료 판정 4 — 단일 GP 모델值)
	if minutes < 3.0 or minutes > 30.0:
		print("FAIL gp length out of magnitude: ", minutes)
		return 1
	return 0


func _intervention_policy(engine: RaceEngine, info: Dictionary) -> void:
	if String(info.get("type", "")) == "duel":
		while engine.add_duel_boost().get("ok", false):
			pass
		return
	# 트러블 우선 무효화 → 여유 차지로 홀드/리스핀 (트러블 비고정 재회전)
	if engine.charge >= 2 and engine.get_provisional().has(RaceTypes.SYMBOL_TROUBLE):
		engine.negate_trouble()
	if engine.charge >= 3:
		var keep: Array = []
		var provisional := engine.get_provisional()
		for i in range(3):
			if provisional[i] != RaceTypes.SYMBOL_TROUBLE:
				keep.append(i)
		if keep.size() < 3:
			engine.hold_respin(keep)
