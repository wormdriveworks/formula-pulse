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
	"SYS-03": "res://ui/sys/options_screen.tscn",
	"SYS-04": "res://ui/sys/achievement_screen.tscn",
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
var _save_indicator: SaveIndicator


func _ready() -> void:
	var data := GameData.new()
	data.load_all()
	if not data.is_ok():
		push_error("AppRoot: game data failed to load")
		return
	session = RunSession.new()
	# 합성 지점 — 라우터도 구현체 이름을 모른다. 플랫폼 선택은 `PlatformServices.create()` 전속.
	session.setup(data, PlatformServices.create())
	_mount_save_indicator()
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


# ── 저장 표시 (D09 본문 §181) ──
#
# 라우터가 든다 — 화면 위에 얹혀 있어야 저장이 화면 전환과 겹쳐도 사라지지 않는다.
# **화면 교체 대상이 아니다**: `_show()` 는 `_current` 만 갈아치우므로 이 노드는 남는다.
#
# ⚠ **`configure()` 를 부르지 않는다 — D13 에 값이 없다.**
# §181 은 "2초 내외"를 *확정 기준값*이라 명시하지만 D13 확정 기준값 대장에 해당 행이 없다
# (`param_fx_*_sec` 계열 실측 — 저장 표시 행 0). 불변규칙 2 대로 임의 기입하지 않았고,
# 표시는 구성 전까지 잠들어 있다(호출 시 1회 보고). **행 2개가 서면 아래 두 줄이 살아난다:**
#
#   _save_indicator.configure(data.param("<표시 시간>"), data.param("<회전 주기>"))
#
# 지금 그 호출을 넣으면 `GameData.param()` 이 없는 키에서 `_load_ok` 를 내려 **앱이 부팅을
# 거부한다**(`app_root.gd` 상단 가드) — 그래서 이름만 정해 두고 호출은 판정 후로 넘긴다.
func _mount_save_indicator() -> void:
	_save_indicator = SaveIndicator.new()
	_save_indicator.name = "SaveIndicator"
	add_child(_save_indicator)
	session.progress_saved.connect(_on_progress_saved)


# 실패한 저장에는 표시를 띄우지 않는다 — §181 의 용도가 "저장 중 종료 경고의 근거"라
# 저장이 안 된 회차에 회전을 보여 주면 근거가 거짓이 된다.
func _on_progress_saved(ok: bool) -> void:
	if ok:
		_save_indicator.flash()
