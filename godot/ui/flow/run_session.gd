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
var profile_index := 1

# 현재 GP
var engine: RaceEngine
var last_gp_result: Dictionary = {}
var last_tour_report: Dictionary = {}
var last_season_report: Dictionary = {}


func setup(game_data: GameData) -> void:
	data = game_data
	SaveManager.configure(data)


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


# 다음 그랑프리 개시 — 서킷 선택과 슬롯 보정 주입은 시즌 층 소관이다
func begin_gp() -> bool:
	var circuit_id := season.current_circuit_id()
	if circuit_id.is_empty() or not data.select_circuit(circuit_id):
		return false
	engine = RaceEngine.new()
	engine.setup(data, rng)
	season.apply_to_engine(engine)
	return true


# GP 종료 — 결과를 시즌 층에 기록한다 (투어 포인트·순위 갱신은 코어가 한다)
func close_gp() -> void:
	if engine == null or engine.result.is_empty():
		return
	last_gp_result = engine.result.duplicate(true)
	season.record_gp(engine.result)


func tour_has_remaining_gp() -> bool:
	return season.race_slot <= season.races_per_tour() and not season.tour_dropped_out


func close_tour() -> Dictionary:
	last_tour_report = season.close_tour()
	return last_tour_report


# 시즌 결산 — 타이틀 판정·그리드 레벨은 코어가 한다 (D05 §9.4~§10)
func close_season() -> Dictionary:
	last_season_report = season.close_season()
	return last_season_report


# 다음 시즌 개막 — 캘린더 셔플·챔피언십 리셋은 코어 소관 (D08 §2.1~2.2)
func begin_next_season() -> void:
	var next := season.season + 1
	season.begin_season(next)


# 자동 저장 — 저장 지점은 D09 §2.4가 확정한다(RACE-03 진입·투어 경계·시즌 경계).
# **SaveManager 경유 전속** — SaveService 직접 호출은 ARCH 정적 규칙이 빌드를 막는다(IMPL-037).
func save_progress() -> Dictionary:
	return SaveManager.save_progress(profile_index, serialize())


func serialize() -> Dictionary:
	return {
		"season": season.serialize() if season != null else {},
		"rng": rng.serialize() if rng != null else {},
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
	return true
