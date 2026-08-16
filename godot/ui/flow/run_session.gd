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


func setup(game_data: GameData) -> void:
	data = game_data
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
	var context := {
		"player_rank": int(last_gp_result.get("player_rank", 16)),
		"act": 1,
		"season": season.season,
		"tour_slot": season.tour_slot,
	}
	return events.judge(stage_id, context)


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
	season.record_gp(engine.result)
	outgame.chassis = engine.chassis  # 잔여 섀시 회수 — GP 밖 정본은 아웃게임 층 (D05 §8)
	# R5 이월 회수 — 미사용분은 소멸하지 않는다 (D06 §3.5). 상한 가드는 구매 지점(K4) 전속:
	# 사용은 수량을 늘리지 못하므로 회수분이 상한을 넘을 경로가 없다.
	outgame.consumables = engine.consumables_held.duplicate()


func tour_has_remaining_gp() -> bool:
	return season.race_slot <= season.races_per_tour() and not season.tour_dropped_out


func close_tour() -> Dictionary:
	last_tour_report = season.close_tour()
	if not season.season_finished():
		# 다음 투어 개시 — 체증 카운터 리셋 + 무상 복원선 (D06 §3.3 · D13 별첨A §3.4 R2).
		# 시즌 마지막 투어면 다음 투어가 없다 — 개시 처리는 begin_next_season()이 한다.
		outgame.begin_tour()
	return last_tour_report


# 시즌 결산 — 타이틀 판정·그리드 레벨은 코어가 한다 (D05 §9.4~§10)
func close_season() -> Dictionary:
	last_season_report = season.close_season()
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
