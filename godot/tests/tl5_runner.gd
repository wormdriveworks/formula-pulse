# TL-5 자동 러너 (D14 §8.2 — D13 §4.2 모델 사양 승계).
# 실행: godot --headless --path godot --script tests/tl5_runner.gd -- profile=standard runs=500 seed=42
#
# **실코드 경로 주행** (D14 §8.2 명문 — "시뮬 코드 재사용이 아닌"): RaceEngine·SeasonState·
# OutgameState·RunSession 을 실제로 돌린다. 러너는 정책(무엇을 누를지)만 갖고 규칙은 갖지 않는다.
# 규칙을 러너가 복제하면 그 순간 이 검증은 '모델 대 모델' 비교로 퇴화한다.
#
# 산출: 지표 12항 (D13 §4.3 표) → JSON. 판정(±15%·허용 범위)은 tl5_report.gd 소관.
extends SceneTree

const PROFILES := {
	# D13 §4.2 플레이어 정책 3종 — 개입 판단률 / 모멘텀 성공률
	"novice": {"intervention": 0.6, "momentum": 0.35},
	"standard": {"intervention": 1.0, "momentum": 0.55},
	"expert": {"intervention": 1.3, "momentum": 0.7},
}
# 구매 정책 그리디 (D13 §4.2): 튜닝은 T1·T2·T4·T3 순 · 축적형은 스킬 티어 개방 즉시 우선
const TUNING_ORDER := ["tuning_t1", "tuning_t2", "tuning_t4", "tuning_t3"]

var _data: GameData
var _profile := "standard"
var _runs := 20
var _base_seed := 42
var _out_path := "user://tl5_result.json"
var _policy: Dictionary = {}
# 정책 난수 — 게임 RNG 스트림과 분리한다. 러너의 조작 흔들림이 reel/ai 스트림을 소비하면
# 시드 재현성이 '플레이어 행동'에 오염된다 (D12 §6.1 스트림 분리 취지).
var _policy_rng := RandomNumberGenerator.new()


func _init() -> void:
	_parse_args()
	_data = GameData.new()
	if not _data.load_all():
		print("TL5_FAIL data load")
		quit(1)
		return
	_policy = PROFILES.get(_profile, PROFILES["standard"])
	var samples: Array = []
	for index in range(_runs):
		samples.append(_run_season(_base_seed + index))
	var summary := _summarize(samples)
	summary["profile"] = _profile
	summary["runs"] = _runs
	summary["base_seed"] = _base_seed
	var file := FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		print("TL5_FAIL cannot write %s" % _out_path)
		quit(1)
		return
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	print("TL5_RUN_DONE profile=%s runs=%d seed=%d out=%s" % [_profile, _runs, _base_seed, _out_path])
	quit(0)


func _parse_args() -> void:
	for argument in OS.get_cmdline_user_args():
		var parts := String(argument).split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"profile":
				_profile = parts[1]
			"runs":
				_runs = maxi(int(parts[1]), 1)
			"seed":
				_base_seed = int(parts[1])
			"out":
				_out_path = parts[1]


# ── 시즌 1 관통 (5투어 × 4GP) ─────────────────────────────────────────
func _run_season(seed_value: int) -> Dictionary:
	_policy_rng.seed = hash("tl5_policy_%d" % seed_value)
	var session := RunSession.new()
	session.setup(_data)
	session.begin_career(1)
	# 시드 고정 — begin_career 는 무작위 마스터 시드를 뽑으므로 재현성을 위해 덮어쓴다
	session.rng.setup(seed_value)
	var sample := {
		"gp_minutes": [], "gp_duels": [], "ai_retires": [],
		"first_podium": 0, "first_gp_win": 0, "first_tour_win": 0,
		"lorentz_beat": 0, "tour_retires": 0, "chassis_wear": [],
	}
	var gp_index := 0
	while not session.season.season_finished():
		while session.tour_has_remaining_gp():
			gp_index += 1
			if not session.begin_gp():
				break
			session.engine.start_gp()
			_drive_gp(session)
			session.close_gp()
			session.settle_gp()
			var result := session.last_gp_result
			sample["gp_minutes"].append(session.engine.estimated_minutes())
			sample["gp_duels"].append(int(result.get("duels", 0)))
			sample["ai_retires"].append(int(session.engine.ai_retire_count))
			# 마일스톤 도달 시점 = 전역 GP 인덱스 (1~20 → 투어 = (i-1)/4 + 1)
			_stamp(sample, "first_podium", session.outgame.milestones.has("milestone_first_podium"), gp_index)
			_stamp(sample, "first_gp_win", session.outgame.milestones.has("milestone_first_gp_win"), gp_index)
			_stamp(sample, "lorentz_beat", session.outgame.milestones.has("milestone_lorentz_beat"), gp_index)
			if bool(result.get("player_retired", false)):
				sample["tour_retires"] = int(sample["tour_retires"]) + 1
				session.season.mark_dropout()
				break
			# 이벤트 노드 (D08 §7 — RACE-03 → RUN-01 사이 삽입 지점). 실플레이가 반드시
			# 지나는 경로이므로 러너도 지난다 — 빼면 C1 회복·C2 수입이 통째로 누락된다.
			var event := session.judge_event()
			if not event.is_empty():
				session.apply_event_reward(event.get("reward", {}))
			# GP 사이 간이 정산 (D07 §1.2 — 필드 정비·소모품 보충). 이 경로가 없으면
			# 4GP 누적 소모가 복원선을 넘어 매 투어 리타이어한다 (실플레이와 다른 경로).
			_field_service(session)
		var remaining_charge := session.engine.charge if session.engine != null else 0
		session.close_tour()
		session.settle_tour(remaining_charge)
		_stamp(sample, "first_tour_win", session.outgame.milestones.has("milestone_first_tour_win"), gp_index)
		_shop(session)
	var report := session.close_season()
	sample["championship_rank"] = int(report.get("player_position", 16))
	sample["champion"] = String(report.get("champion", "")) == SeasonState.PLAYER_ID
	sample["credits_end"] = session.outgame.credits
	sample["drive_data_total"] = session.outgame.drive_data_earned_total
	sample["gps"] = gp_index
	return sample


func _stamp(sample: Dictionary, key: String, reached: bool, gp_index: int) -> void:
	if reached and int(sample[key]) == 0:
		sample[key] = gp_index


# ── 주행 정책 (규칙 아님 — '무엇을 누를지'만) ─────────────────────────
func _drive_gp(session: RunSession) -> void:
	var engine := session.engine
	var guard := 400
	while not engine.finished and guard > 0:
		guard -= 1
		var info := engine.begin_turn()
		if String(info.get("type", "")) == "finished":
			break
		# 소모품 = 패닉 버튼 (D06 §3.5 R4) — T1 에서만, 섀시가 위험선 아래일 때
		if String(info.get("type", "")) == "sector" and engine.chassis < _panic_line():
			for consumable_id in engine.consumables_held.keys():
				if not engine.use_consumable(String(consumable_id)).is_empty():
					break
		engine.spin()
		_intervene(engine, info)
		# 모멘텀 성공률 = 여유 구간 확정 비율 (D13 §4.2 정책 축)
		var momentum_hit: bool = _policy_rng.randf() < float(_policy["momentum"])
		engine.confirm(1.0 if momentum_hit else 0.0)


# 패닉 선 [러너 정책 — 정본 미규정]: 필드 정비 회당 상한만큼 남았을 때가 마지막 여유다
func _panic_line() -> float:
	return _data.param("param_repair_field_cap")


func _intervene(engine: RaceEngine, info: Dictionary) -> void:
	# 개입 판단률 — 1.0 초과는 '더 자주 시도'가 아니라 '판단 실패가 없다'로 읽는다.
	# 0.6 = 10회 중 4회는 개입 기회를 놓친다.
	if _policy_rng.randf() > float(_policy["intervention"]):
		return
	if String(info.get("type", "")) == "duel":
		while bool(engine.add_duel_boost().get("ok", false)):
			pass
		return
	var provisional := engine.get_provisional()
	if engine.charge >= 2 and provisional.has(RaceTypes.SYMBOL_TROUBLE):
		engine.negate_trouble()
	if engine.charge >= 3:
		var keep: Array = []
		var current := engine.get_provisional()
		for i in range(3):
			if current[i] != RaceTypes.SYMBOL_TROUBLE:
				keep.append(i)
		if keep.size() < 3:
			engine.hold_respin(keep)


# 간이 정산 정책 (GP 사이) — 생존 우선: 복원선까지 필드 정비 + 소모품 상한까지 보충.
# 판단은 정책이고 절단·상한·체증은 전부 코어가 쥔다.
func _field_service(session: RunSession) -> void:
	var outgame := session.outgame
	var cap := int(_data.param("param_repair_field_cap"))
	while outgame.chassis < float(outgame.free_restore_line()):
		if outgame.field_repair(cap) <= 0:
			break   # 크레딧 부족 또는 회복 여지 소진
	var carried := 0
	for held in outgame.consumables:
		carried += int(outgame.consumables[held])
	while carried < _data.param_int("param_consumable_carry_cap"):
		if not outgame.buy_consumable("consumable_p1"):
			break
		carried += 1


# ── 구매 정책 그리디 (D13 §4.2) ───────────────────────────────────────
func _shop(session: RunSession) -> void:
	var outgame := session.outgame
	# 축적형 우선: 티어 개방 즉시 스킬 해금
	var bought := true
	while bought:
		bought = false
		for skill_id in _data.skills:
			if outgame.unlocked_skills.has(skill_id):
				continue
			if outgame.unlock_skill(String(skill_id)):
				bought = true
	# 회전형: 섀시 회복 우선(생존). 복원선 초과 구간의 유일 수단 = 전면 정비 (D07 §3.3)
	if outgame.chassis < data_chassis_target():
		outgame.full_repair()
	bought = true
	while bought:
		bought = false
		for tuning_id in TUNING_ORDER:
			if outgame.buy_tuning(String(tuning_id)):
				bought = true


# 개러지 정비 목표선 [러너 정책]: 최대치 — 투어 개시 전 완전 회복이 그리디 정책의 귀결
func data_chassis_target() -> float:
	return _data.param("param_chassis_max")


# ── 집계 (D13 §4.3 지표) ──────────────────────────────────────────────
func _summarize(samples: Array) -> Dictionary:
	var ranks: Array = []
	var minutes: Array = []
	var duels: Array = []
	var ai_retires: Array = []
	var tour_retires: Array = []
	var drive_totals: Array = []
	var credits: Array = []
	var champions := 0
	var podium_tours: Array = []
	var gp_win_tours: Array = []
	var tour_win_tours: Array = []
	var lorentz_tours: Array = []
	for entry in samples:
		var sample: Dictionary = entry
		ranks.append(float(sample["championship_rank"]))
		tour_retires.append(float(sample["tour_retires"]))
		drive_totals.append(float(sample["drive_data_total"]))
		credits.append(float(sample["credits_end"]))
		if bool(sample["champion"]):
			champions += 1
		for value in sample["gp_minutes"]:
			minutes.append(float(value))
		for value in sample["gp_duels"]:
			duels.append(float(value))
		for value in sample["ai_retires"]:
			ai_retires.append(float(value))
		_collect_tour(podium_tours, int(sample["first_podium"]))
		_collect_tour(gp_win_tours, int(sample["first_gp_win"]))
		_collect_tour(tour_win_tours, int(sample["first_tour_win"]))
		_collect_tour(lorentz_tours, int(sample["lorentz_beat"]))
	return {
		"championship_rank_median": _median(ranks),
		"championship_rank_p25": _percentile(ranks, 0.25),
		"championship_rank_p75": _percentile(ranks, 0.75),
		"champion_rate": float(champions) / float(maxi(samples.size(), 1)),
		"first_podium_tour_median": _median(podium_tours),
		"first_podium_rate": float(podium_tours.size()) / float(maxi(samples.size(), 1)),
		"first_gp_win_tour_median": _median(gp_win_tours),
		"first_gp_win_rate": float(gp_win_tours.size()) / float(maxi(samples.size(), 1)),
		"first_tour_win_tour_median": _median(tour_win_tours),
		"first_tour_win_rate": float(tour_win_tours.size()) / float(maxi(samples.size(), 1)),
		"lorentz_beat_rate": float(lorentz_tours.size()) / float(maxi(samples.size(), 1)),
		"gp_minutes_median": _median(minutes),
		"gp_minutes_p90": _percentile(minutes, 0.90),
		"duels_per_gp_mean": _mean(duels),
		"ai_retires_per_gp_mean": _mean(ai_retires),
		"ai_retires_per_gp_max": _max(ai_retires),
		"tour_retires_per_season_mean": _mean(tour_retires),
		"drive_data_total_median": _median(drive_totals),
		"credits_end_median": _median(credits),
	}


# 도달 GP 인덱스 → 투어 번호 (1~20 GP · 투어당 4GP). 미도달(0)은 표본에서 제외한다 —
# 미도달을 0으로 섞으면 중앙값이 도달 시점이 아니라 도달률의 함수가 된다.
func _collect_tour(target: Array, gp_index: int) -> void:
	if gp_index <= 0:
		return
	target.append(float((gp_index - 1) / 4 + 1))


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


func _max(values: Array) -> float:
	var maximum := 0.0
	for value in values:
		maximum = maxf(maximum, float(value))
	return maximum


func _median(values: Array) -> float:
	return _percentile(values, 0.5)


func _percentile(values: Array, ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := int(floor(ratio * float(sorted.size() - 1)))
	return float(sorted[clampi(index, 0, sorted.size() - 1)])
