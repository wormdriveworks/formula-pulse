# 런 세션 — 화면 사이를 건너는 진행 상태 (D09 §2.3 플로우맵의 데이터 축).
#
# 코어의 상태 층(SeasonState·RaceEngine·OutgameState)을 **소유만** 하고 규칙은 갖지 않는다.
# 판정·정산은 전부 코어에 있고 여기서는 "지금 어느 GP인가"만 관리한다 —
# 화면 층이 규칙을 갖기 시작하면 헤드리스 테스트가 닿지 못하는 곳에 로직이 생긴다.
#
# **autoload로 두지 않는다** (IMPL-015): 전 코어가 순수 클래스인 이유와 같다.
# 라우터가 인스턴스를 쥐고 화면에 주입한다.
class_name RunSession
extends RefCounted

# 저장 표시(D09 §181)의 관측 지점 — **표시 층이 코어를 보지 않게** 세션이 알린다.
# `SaveManager` 는 static 이라 시그널을 걸 자리가 없고, 코어에 시그널을 신설하면 표시 층
# 사정이 코어로 올라간다(혼입 0). 저장을 요청하는 곳이 세션 하나뿐이라 여기가 유일 관문이다.
signal progress_saved(ok: bool)

# 관계 축 트리거가 지목하는 고유 id — 데이터의 실키를 코드가 짚는 지점이라 한 곳에 모은다.
const MARO_ID := "ai_maro"
const KAI_ID := "ai_sherwood"
const ALTA_RIDGE_ID := "stage_alta_ridge"
# 계승 2축 보조 A — D08 §8.8 "지정 이벤트 1건(풀 태그)" 의 마로 축 지목분 (납품서 §6.2).
const MARO_EVENT_ID := "event_number_two_check"
# C3 = 관계·조우 카테고리 (`event_categories.csv` reward_type=relation)
const RELATION_CATEGORY := "category_c3"

var data: GameData
var rng: RngService
var season: SeasonState
var outgame: OutgameState
var events: EventService
var narrative: NarrativeService
var options: OptionsStore
var presentation: PresentationGrade
var profile_index := 1

# 현재 GP
var engine: RaceEngine
var last_gp_result: Dictionary = {}
var last_tour_report: Dictionary = {}
var last_season_report: Dictionary = {}
# 직전 경계에서 새로 달성된 업적 — 표시 층이 읽어 고지한다 (무보상 명예형이라 지급 없음)
var newly_achieved: Array = []
# 직전 경계에서 새로 열린 스킬 티어 — 성장 게이트 개방 고지(SE-U13)의 근거.
# 개방 자체는 마일스톤 파생이라 상태가 아니고, "방금 열렸다"는 **경계에서만** 알 수 있다.
# `newly_achieved` 와 같은 성격의 래치이며 세이브 대상이 아니다(경계 1회성 표시 신호).
var newly_opened_tiers: Array = []

# 투어 경계에서 발생시킬 막 VN id 목록 — 화면 층이 소비한다 (세이브 비대상: 경계 1회성).
var pending_act_vn: Array = []
# 같은 경계에서 공표된 관계 전이 축 id 목록 (D07 §5.5 대회 경계 스냅).
var committed_relations: Array = []
# 재회 축 체인의 투어당 전진량 상한 = 2비트 (D08 §8.7-3 "1~2비트씩 전진" · 납품서 §6.2).
# threshold1=2 도출의 전제이므로 상한이 풀리면 "시즌 1 내 대면 도달" 보장이 함께 흔들린다.
const REUNION_BEATS_PER_TOUR := 2
var _reunion_beats_this_tour := 0
# 플랫폼 서비스 — **인터페이스 타입으로만 쥔다**(혼입 0). 합성은 `PlatformServices.create()`
# 단일 지점이며, 미주입(null)도 정상 상태다: 헤드리스 테스트·러너는 플랫폼 없이 돈다.
var platform: PlatformServices

# 오디오 디스패처 — **사운드의 유일 발화 경로**. 화면은 게임 이벤트 id 만 던지고 무엇이
# 울릴지는 `sound_map` 이 정한다. 커리어가 아니라 세션에 매다는 이유: 타이틀·옵션 화면도
# 소리를 내며, 커리어 개시 전에 이미 BGM 이 돈다.
var audio: AudioDispatcher


func setup(game_data: GameData, services: PlatformServices = null) -> void:
	data = game_data
	platform = services
	SaveManager.configure(data)
	options = OptionsStore.new()
	options.setup(data)  # 기기별 구성 — 프로필·커리어와 무관하게 세션 개시 시 적재
	# 재생기 주입 = 합성 지점. 실물 유입 시 여기 한 줄만 바뀐다(디스패처·호출부 무접촉).
	audio = AudioDispatcher.new()
	var sink := SilentAudioOutput.new()
	audio.setup(data, sink)
	sink.bind_dispatcher(audio)


# 새 커리어 — 마스터 시드를 뽑아 시즌·아웃게임 층을 연다 (D12 §6.1)
func begin_career(profile: int) -> void:
	profile_index = profile
	rng = RngService.new()
	var seeder := RandomNumberGenerator.new()
	seeder.randomize()
	rng.setup(seeder.randi())
	season = SeasonState.new()
	season.setup(data, rng)
	season.begin_season(1)
	season.begin_tour()
	outgame = OutgameState.new()
	outgame.setup(data)
	events = EventService.new()
	events.setup(data, rng)
	narrative = NarrativeService.new()
	narrative.setup(data)
	narrative.begin_season()
	presentation = PresentationGrade.new()
	presentation.setup(data)


# 이벤트 노드 판정 (D08 §7 — RACE-03 → RUN-01 사이 삽입 지점의 발생 판정)
func judge_event() -> Dictionary:
	var stage_id := season.current_stage_id()
	# 변형 조건 DSL 의 입력 문맥 — 성적·막 축 (D08 §7.3)
	# 변형 4축의 입력 (D08 §7.3). 필드가 빠지면 DSL 이 오류를 내고 그 변형은 영구 미발동한다
	# (IMPL-095 "미지 필드 = 오류" 처리 덕에 TL-5 러너가 vane_stage·jude_rank_delta 누락을 적발).
	var context := {
		"player_rank": int(last_gp_result.get("player_rank", 16)),
		# 서사 층 막 번호 — 투어 경계에서 래치된 값이다 (D08 §8.1 이층 처리).
		# 주행 중에는 바뀌지 않으므로 이벤트 변형이 한 투어 안에서 갈리지 않는다.
		"act": outgame.narrative_act,
		"season": season.season,
		"tour_slot": season.tour_slot,
		"vane_stage": outgame.vane_stage(),
		"jude_rank_delta": jude_rank_delta(),
	}
	var outcome := events.judge(stage_id, context)
	var event_id := String(outcome.get("event_id", ""))
	if event_id == MARO_EVENT_ID:
		# 보조 A — 지정 이벤트 발생 1건 (D08 §8.8 계승 행)
		outgame.add_relation("relation_succession_maro", 1)
	if event_id != "" and String(data.event(event_id).get("category_id", "")) == RELATION_CATEGORY:
		# 관계·조우(C3) 이벤트 = 재회 체인 비트 (알타 리지 투어 안에서만 — 함수가 가른다)
		record_reunion_beat("relation_event")
	return outcome


# 주드 인접 판정 (D13 별첨A §6.5): |플레이어 챔피언십 순위 − 주드 순위|.
# 순위표에 없으면(무득점 초반) 인접이 성립하지 않도록 큰 값을 낸다 — 0 은 '가장 인접'이라
# 조용히 항상 성립하는 반대 결함이 된다.
# **이벤트 변형(D08 §7.3)과 CG-03 조우(D10 §7)가 같은 축을 쓴다** — 두 소비부가 같은 값을 본다.
func jude_rank_delta() -> int:
	var order := season.championship_standings()
	var player_index := order.find(SeasonState.PLAYER_ID)
	var jude_index := order.find("ai_jude")
	if player_index < 0 or jude_index < 0:
		return 99
	return absi(player_index - jude_index)


# 챔피언십에서 플레이어가 주드보다 앞서 있는가 (순위표 인덱스가 작을수록 상위).
# 둘 중 하나라도 순위표에 없으면 성립하지 않는다 — 무득점 초반의 '앞섬'은 앞선 것이 아니다.
func _player_ahead_of_jude() -> bool:
	var order := season.championship_standings()
	var player_index := order.find(SeasonState.PLAYER_ID)
	var jude_index := order.find("ai_jude")
	if player_index < 0 or jude_index < 0:
		return false
	return player_index < jude_index


# 이벤트 보상 적용 — 화면은 표시만 하고 적용은 세션이 코어에 위임한다
func apply_event_reward(reward: Dictionary) -> void:
	match String(reward.get("type", "none")):
		"credit":
			outgame.gain_credits(int(reward.get("amount", 0)))
		"dp":
			outgame.gain_drive_data(int(reward.get("amount", 0)))
		"chassis":
			# 이벤트 회복 — 회당 상한 가드·최대치 절단은 코어가 한다 (D06 §3.4)
			outgame.event_chassis_recover(int(reward.get("amount", 0)))
		"relation", "info", "none":
			pass  # 관계 축·정보성은 별도 경로 (관계 카운터는 대회 경계 스냅)


# 다음 그랑프리 개시 — 서킷 선택과 슬롯 보정 주입은 시즌 층 소관이다
func begin_gp() -> bool:
	var circuit_id := season.current_circuit_id()
	if circuit_id.is_empty() or not data.select_circuit(circuit_id):
		return false
	engine = RaceEngine.new()
	engine.setup(data, rng)
	season.apply_to_engine(engine)
	engine.chassis_carry_in = outgame.chassis  # GP 간 이월 (D05 §8 — 자동 완전 회복 없음)
	engine.consumables_carry_in = outgame.consumables.duplicate()  # R5 반입 (D06 §3.5)
	presentation.reset_gp()  # L2/L3 상한 카운터 = GP 단위 (D08 §8.5)
	return true


# GP 종료 — 결과를 시즌 층에 기록한다 (투어 포인트·순위 갱신은 코어가 한다)
func close_gp() -> void:
	if engine == null or engine.result.is_empty():
		return
	last_gp_result = engine.result.duplicate(true)
	# 네임드 첫 선착 판정 소재 (D08 §8.2) — 이 GP에서 플레이어보다 뒤에 들어온 네임드 목록.
	# 완주자만 대상이다: 리타이어한 상대를 앞선 것은 '선착'이 아니다 [가안 — impl_log].
	last_gp_result["beaten_rivals"] = _beaten_rivals(engine)
	last_gp_result["scripted_loss"] = season.is_scripted_loss_gp()
	var tiers_before := _tier_open_snapshot()
	season.record_gp(last_gp_result)
	outgame.record_gp_result(last_gp_result)
	_latch_opened_tiers(tiers_before)
	# CG-03 전제 래치 — 챔피언십에서 주드를 처음 앞선 시점은 **GP 결과 확정 후**에만 알 수 있다
	# (총괄 판정 IMPL-128 B-2). 한 번 서면 되돌리지 않는다 — 이후 순위가 다시 밀려도 '첫 역전'은 있었다.
	if not outgame.jude_overtaken and _player_ahead_of_jude():
		outgame.jude_overtaken = true
	newly_achieved = outgame.evaluate_achievements(season.season)
	_publish_achievements()
	outgame.chassis = engine.chassis  # 잔여 섀시 회수 — GP 밖 정본은 아웃게임 층 (D05 §8)
	# R5 이월 회수 — 미사용분은 소멸하지 않는다 (D06 §3.5). 상한 가드는 구매 지점(K4) 전속:
	# 사용은 수량을 늘리지 못하므로 회수분이 상한을 넘을 경로가 없다.
	outgame.consumables = engine.consumables_held.duplicate()
	_advance_succession_maro(engine)
	# 카이 벽 조우 = 재회 체인 비트 (D08 §8.7-3 "브리핑·이벤트·벽 조우"의 세 번째 축).
	if engine.duel_opponents.has(KAI_ID):
		record_reunion_beat("wall_encounter")


# ── 관계 축 카운터 트리거 (총괄 발주 IMPL-249 ⑤⑥ · 납품서 §6.2 확정 문장) ──
#
# **행과 트리거는 같은 회차에 들어간다.** 행만 먼저 넣으면 `_achievement_source_missing()` 이
# 축 행의 실재만 보므로 두 업적이 `pending_achievements()` 계수에서 빠지는데, 트리거가 없으니
# 여전히 영원히 안 켜진다 — "안 켜지는 업적을 계수로 드러낸다"는 설계가 무력화된다(납품서 §3.4).
#
# 공표는 여기서 하지 않는다 — `add_relation()` 은 `_relation_pending` 에만 쌓고
# `commit_relation_transitions()`(투어 경계)이 공표한다. D07 §5.5 대회 경계 스냅.

# 계승 2축(마로) 주축 B — **선착 1회 또는 마로와의 듀얼 수행 1회마다 +1**
# (D13 별첨A §5.2 계승 행 카운터 = "선착 + 듀얼 수행" · `counter_source=beat_and_duel`).
func _advance_succession_maro(source: RaceEngine) -> void:
	var gained := 0
	if Array(last_gp_result.get("beaten_rivals", [])).has(MARO_ID):
		gained += 1
	for opponent in source.duel_opponents:
		if String(opponent) == MARO_ID:
			gained += 1
	if gained > 0:
		outgame.add_relation("relation_succession_maro", gained)


# 재회 축(카이) 형식 A — **알타 리지 투어 안에서 체인 비트가 발생할 때마다 +1.**
#
# **발생 = 도달**이다 — 열람했는지 스킵했는지 보지 않는다(D08 §10.3 R-D07-VN: 스킵이
# 페널티가 되면 비강제성이 역전된다). **아카이브 재열람은 올리지 않는다** — 재열람 경로는
# 이 함수를 부르지 않는다(전진형 정합).
func record_reunion_beat(source: String) -> bool:
	if not _is_alta_ridge_tour():
		return false
	if _reunion_beats_this_tour >= REUNION_BEATS_PER_TOUR:
		return false
	_reunion_beats_this_tour += 1
	outgame.add_relation("relation_reunion", 1)
	return true


# 알타 리지 결속 — 체인은 그 무대의 투어 안에서만 전진한다 (D08 §8.7-2 구조 가드 3).
func _is_alta_ridge_tour() -> bool:
	return season.current_stage_id() == ALTA_RIDGE_ID


# 스킬 티어 개방 = 마일스톤 연동이라 별도 반환값이 없다 (D07 §4.3). 경계 전후를 대조해
# **새로 열린 티어**만 뽑는다 — 티어 구성은 데이터가 정하므로 개수를 코드에 적지 않는다.
func _tier_open_snapshot() -> Dictionary:
	var open: Dictionary = {}
	# `data.skills` 는 id → 행 딕셔너리다 — 키를 돌면 문자열을 행으로 착각한다(실주행 적발).
	for skill_id in data.skills:
		var row: Dictionary = data.skills[skill_id]
		var skill_tier := CsvTable.to_int(String(row["skill_tier"]))
		open[skill_tier] = outgame.skill_tier_open(skill_tier)
	return open


func _latch_opened_tiers(before: Dictionary) -> void:
	newly_opened_tiers = []
	for skill_tier in before:
		if not bool(before[skill_tier]) and outgame.skill_tier_open(int(skill_tier)):
			newly_opened_tiers.append(int(skill_tier))


# 플랫폼 업적 발행 (D12 §2.2 IAchievement · 총괄 판정 IMPL-128 ③).
# **판정은 코어가 끝냈고 여기서는 발행만 한다** — 어댑터가 판정에 관여할 경로를 두지 않는다
# (연동 실패·미연동이 게임 내 달성 상태를 바꾸면 안 된다).
# 미연동 스텁도 같은 호출을 받아 이력을 쌓아 둔다 — 실 SDK 결선 시 소급 발행의 근거가 된다.
func _publish_achievements() -> void:
	if platform == null or platform.achievement == null:
		return
	for achievement_id in newly_achieved:
		platform.achievement.unlock(String(achievement_id))


# SYS-04 '미연동' 표기의 조회 창구 — 화면은 어댑터도 플랫폼도 모른 채 이 값만 읽는다.
func achievement_service_linked() -> bool:
	if platform == null or platform.achievement == null:
		return false
	return platform.achievement.is_linked()


func tour_has_remaining_gp() -> bool:
	return season.race_slot <= season.races_per_tour() and not season.tour_dropped_out


# 이 GP에서 플레이어가 앞선 네임드 목록 — 완주자 한정 (리타이어 상대는 선착 대상 아님)
func _beaten_rivals(source: RaceEngine) -> Array:
	var beaten: Array = []
	var standings: Array = source.result.get("standings", [])
	var player_index := standings.find(RaceEngine.PLAYER_ID)
	if player_index < 0 or bool(source.entrants[RaceEngine.PLAYER_ID]["retired"]):
		return beaten
	var named_ids: Dictionary = {}
	for row in data.rivals:
		named_ids[String(row["id"])] = true
	for index in range(player_index + 1, standings.size()):
		var entrant_id := String(standings[index])
		if not named_ids.has(entrant_id):
			continue   # 필러는 라이벌 파일·마일스톤 대상이 아니다 (D07 §6.1)
		if bool(source.entrants[entrant_id]["retired"]):
			continue
		beaten.append(entrant_id)
	return beaten


# GP 정산 지급 (D13 별첨A §3.1 S1 상금 + S2 완주 보너스) — **지급의 유일 경로**.
# 화면이 직접 gain_credits 를 부르면 그 규칙이 화면 층에 갇혀 러너·테스트가 닿지 못한다
# (TL-5 자동 러너는 "실코드 경로 주행"이 규격 — D14 §8.2). 표시는 반환값을 읽는다.
func settle_gp() -> Dictionary:
	var tour_points := int(last_gp_result.get("tour_points", 0))
	var finished := not bool(last_gp_result.get("player_retired", false))
	var prize := outgame.gp_prize(tour_points, finished)
	var bonus := outgame.finish_bonus(finished)
	outgame.gain_credits(prize + bonus)
	return {"prize": prize, "bonus": bonus, "tour_points": tour_points, "finished": finished}


# 투어 결산 지급 (D13 별첨A §3.2 S3·S4 + D06 §4.1 잔여 차지 환전) — 동상.
func settle_tour(remaining_charge: int) -> Dictionary:
	var position := int(last_tour_report.get("player_position", 16))
	var dropped := bool(last_tour_report.get("dropped_out", false))
	var reward := outgame.settlement_reward("tour", maxi(position, 1))
	var ratio := float(last_tour_report.get("s4_ratio", 1.0))
	var credits := int(round(float(int(reward.get("credits", 0))) * ratio))
	var drive_points := int(reward.get("dp", 0))
	if bool(last_tour_report.get("s3_paid", true)):
		credits += data.param_int("param_tour_finish_bonus_cr")
		drive_points += data.param_int("param_tour_finish_bonus_dp")
	outgame.gain_credits(credits)
	outgame.gain_drive_data(drive_points)
	# 탈락 시 환전 미성립 (D06 §4.1 G4) — 코어가 조건을 쥐지만 호출 자체를 걸지 않는다
	var exchanged := outgame.exchange_charge(remaining_charge, not dropped)
	return {"credits": credits, "dp": drive_points, "exchanged": exchanged, "dropped": dropped}


# 시즌 결산 지급 (D06 §2.1 S6 — 챔피언십 순위 비례). 선재 공백이었다:
# settlement_rewards.csv 의 season 행 6개를 부르는 코드가 어디에도 없었다 (TL-5 적발).
func settle_season() -> Dictionary:
	var position := int(last_season_report.get("player_position", 16))
	var reward := outgame.settlement_reward("season", maxi(position, 1))
	var credits := int(reward.get("credits", 0))
	var drive_points := int(reward.get("dp", 0))
	outgame.gain_credits(credits)
	outgame.gain_drive_data(drive_points)
	return {"credits": credits, "dp": drive_points, "position": position}


func close_tour() -> Dictionary:
	var tiers_before := _tier_open_snapshot()
	last_tour_report = season.close_tour()
	outgame.record_tour_result(last_tour_report)
	_latch_opened_tiers(tiers_before)
	newly_achieved = outgame.evaluate_achievements(season.season)
	_publish_achievements()
	# ── 투어 경계 = 서사 층 발효 지점 (D08 §8.1 · D07 §5.5) ──
	# 막 래치와 관계 전이 공표가 **같은 경계**에 선다. 둘을 갈라 두면 "막은 넘어갔는데
	# 관계 단계는 다음 경계에 공표되는" 어긋남이 생긴다.
	pending_act_vn = outgame.latch_narrative_act()
	committed_relations = outgame.commit_relation_transitions()
	_reunion_beats_this_tour = 0
	if not season.season_finished():
		# 다음 투어 개시 — 체증 카운터 리셋 + 무상 복원선 (D06 §3.3 · D13 별첨A §3.4 R2).
		# 시즌 마지막 투어면 다음 투어가 없다 — 개시 처리는 begin_next_season()이 한다.
		outgame.begin_tour()
	return last_tour_report


# 시즌 결산 — 타이틀 판정·그리드 레벨은 코어가 한다 (D05 §9.4~§10)
func close_season() -> Dictionary:
	var tiers_before := _tier_open_snapshot()
	last_season_report = season.close_season()
	outgame.record_season_result(last_season_report)
	_latch_opened_tiers(tiers_before)
	newly_achieved = outgame.evaluate_achievements(season.season)
	_publish_achievements()
	# 시즌 오버홀 후보 추첨 — 결산 직후 1회 (D06 §5.3). 결과는 아웃게임 층에 보존되어
	# HUB-08 진입·재로드 어디서도 다시 추첨되지 않는다 (재로드 리롤 무효).
	outgame.draw_overhaul_candidates(int(last_season_report.get("player_position", 16)), rng)
	return last_season_report


# 다음 시즌 개막 — 캘린더 셔플·챔피언십 리셋은 코어 소관 (D08 §2.1~2.2)
func begin_next_season() -> void:
	var next := season.season + 1
	season.begin_season(next)
	outgame.begin_tour()  # 시즌 첫 투어 개시 — 체증 리셋 + 무상 복원선 (D06 §3.3 "시즌 간 = 동일")


# 자동 저장 — 저장 지점은 D09 §2.4가 확정한다(RACE-03 진입·투어 경계·시즌 경계).
# **SaveManager 경유 전속** — SaveService 직접 호출은 ARCH 정적 규칙이 빌드를 막는다(IMPL-037).
func save_progress() -> Dictionary:
	var result := SaveManager.save_progress(profile_index, serialize())
	progress_saved.emit(bool(result.get("ok", true)))
	return result


func serialize() -> Dictionary:
	return {
		"season": season.serialize() if season != null else {},
		"rng": rng.serialize() if rng != null else {},
		"events": events.serialize() if events != null else {},
		"narrative": narrative.serialize() if narrative != null else {},
		"outgame": outgame.serialize() if outgame != null else {},
	}


func restore(payload: Dictionary) -> bool:
	rng = RngService.new()
	if payload.has("rng"):
		rng.deserialize(payload["rng"])
	season = SeasonState.new()
	season.setup(data, rng)
	if payload.has("season") and not season.restore(payload["season"]):
		return false
	outgame = OutgameState.new()
	outgame.setup(data)
	if payload.has("outgame") and not outgame.restore(payload["outgame"]):
		return false
	events = EventService.new()
	events.setup(data, rng)
	# 복원 실패는 전파한다 — 무시하면 손상 payload가 조용히 초기 상태로 리셋되어
	# 백업 복구 경로(TC-P8) 대신 "멀쩡히 로드된 척"이 된다 (season·outgame과 동일 취급)
	if payload.has("events") and not events.restore(payload["events"]):
		return false
	narrative = NarrativeService.new()
	narrative.setup(data)
	if payload.has("narrative") and not narrative.restore(payload["narrative"]):
		return false
	presentation = PresentationGrade.new()
	presentation.setup(data)
	return true
