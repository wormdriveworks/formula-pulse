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
# 플랫폼 서비스 — **인터페이스 타입으로만 쥔다**(혼입 0). 합성은 `PlatformServices.create()`
# 단일 지점이며, 미주입(null)도 정상 상태다: 헤드리스 테스트·러너는 플랫폼 없이 돈다.
var platform: PlatformServices


func setup(game_data: GameData, services: PlatformServices = null) -> void:
	data = game_data
	platform = services
	SaveManager.configure(data)
	options = OptionsStore.new()
	options.setup(data)  # 기기별 구성 — 프로필·커리어와 무관하게 세션 개시 시 적재


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
		# [가안] 막(act) 고정 1 — 막 전이는 마일스톤 래치 층(D08 §8.1 서사 층)이며 미결선.
		# 서사 트랙(T7) 유입 시 narrative 층에서 받아 채운다.
		"act": 1,
		"season": season.season,
		"tour_slot": season.tour_slot,
		"vane_stage": outgame.vane_stage(),
		"jude_rank_delta": jude_rank_delta(),
	}
	return events.judge(stage_id, context)


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
	season.record_gp(last_gp_result)
	outgame.record_gp_result(last_gp_result)
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
	last_tour_report = season.close_tour()
	outgame.record_tour_result(last_tour_report)
	newly_achieved = outgame.evaluate_achievements(season.season)
	_publish_achievements()
	if not season.season_finished():
		# 다음 투어 개시 — 체증 카운터 리셋 + 무상 복원선 (D06 §3.3 · D13 별첨A §3.4 R2).
		# 시즌 마지막 투어면 다음 투어가 없다 — 개시 처리는 begin_next_season()이 한다.
		outgame.begin_tour()
	return last_tour_report


# 시즌 결산 — 타이틀 판정·그리드 레벨은 코어가 한다 (D05 §9.4~§10)
func close_season() -> Dictionary:
	last_season_report = season.close_season()
	outgame.record_season_result(last_season_report)
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
	return SaveManager.save_progress(profile_index, serialize())


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
