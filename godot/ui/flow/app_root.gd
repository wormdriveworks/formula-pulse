# 앱 루트 — 화면 라우터 (D09 §2.3 플로우맵의 실행 층). 메인 씬이다.
#
# 라우터가 세션·데이터를 쥐고 화면에 주입한다. **autoload를 쓰지 않는 이유**는 코어와 같다
# (IMPL-015 — 원격 헤드리스 작업 전체가 autoload 파손에 인질이 된다). 루트 노드가 그 역할을 한다.
#
# **전이 폐쇄성 (D09 §2.3):** 이동 가능한 대상은 아래 표가 전부다. 화면은 대상을 요청만 하고,
# 표에 없는 대상은 여기서 거부된다 — 플로우맵에 없는 전이가 화면 안에서 생기지 않게 하는 장치다.
extends Control

const ROUTES := {
	"SYS-01": "res://ui/sys/title_screen.tscn",
	"SYS-02": "res://ui/sys/save_slot_screen.tscn",
	"RACE-01": "res://ui/race/race_screen.tscn",
	"RACE-03": "res://ui/race/gp_result_screen.tscn",
	"RUN-01": "res://ui/run/run_recap_screen.tscn",
	"RUN-02": "res://ui/run/event_node_screen.tscn",
	"NAR-01": "res://ui/nar/vn_screen.tscn",
	"SET-01": "res://ui/settle/tour_report_screen.tscn",
	"SET-02": "res://ui/settle/season_result_screen.tscn",
	"HUB-01": "res://ui/hub/garage_screen.tscn",
	"HUB-02": "res://ui/hub/repair_bay_screen.tscn",
	"HUB-03": "res://ui/hub/tuning_bench_screen.tscn",
	"HUB-04": "res://ui/hub/strategy_screen.tscn",
	"HUB-05": "res://ui/hub/records_screen.tscn",
	"HUB-06": "res://ui/hub/sponsor_desk_screen.tscn",
	"HUB-07": "res://ui/hub/facility_screen.tscn",
	"HUB-08": "res://ui/hub/overhaul_screen.tscn",
}

const ENTRY_SCREEN := "SYS-01"

var session: RunSession
var _current: FlowScreen


func _ready() -> void:
	var data := GameData.new()
	data.load_all()
	if not data.is_ok():
		push_error("AppRoot: game data failed to load")
		return
	session = RunSession.new()
	session.setup(data)
	_show(ENTRY_SCREEN, {})


func _show(target: String, payload: Dictionary) -> void:
	if not ROUTES.has(target):
		push_error("AppRoot: undefined route '%s' (D09 flow map has no such screen)" % target)
		return
	var packed := load(String(ROUTES[target])) as PackedScene
	if packed == null:
		push_error("AppRoot: scene load failed for '%s'" % target)
		return
	if _current != null:
		_current.navigate.disconnect(_on_navigate)
		remove_child(_current)
		_current.queue_free()
	_current = packed.instantiate()
	_current.set_anchors_preset(Control.PRESET_FULL_RECT)
	_current.navigate.connect(_on_navigate)
	# **세션은 add_child 이전에 넣는다.** `_ready()` 가 `bind()` 보다 먼저 돌기 때문에,
	# 뒤에 넣으면 화면이 "세션 없음"으로 판단해 자체 세션을 열어 버린다 —
	# 실측: RACE-01 이 독립 세션으로 GP 를 돌아 결산 화면이 빈 엔진을 봤다.
	_current.session = session
	add_child(_current)
	_current.bind(session, payload)


func _on_navigate(target: String, payload: Dictionary) -> void:
	_show(target, payload)
