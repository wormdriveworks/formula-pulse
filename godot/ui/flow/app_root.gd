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
	# 재생기의 트리 숙주 = 라우터. 화면은 교체되지만 오디오는 세션 수명을 살아야 하므로
	# 플레이어를 화면에 매달 수 없다 — 화면과 함께 사라지면 BGM 이 전이마다 끊긴다.
	session.setup(data, PlatformServices.create(), self)
	_mount_save_indicator(data)
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
	# 저장 표시를 매 전이마다 맨 뒤로 되돌린다 — **형제 순서가 곧 그리기 순서다.**
	# 표시는 `_ready()` 에서 한 번 붙고 화면은 전이마다 그 뒤에 붙으므로, 그대로 두면
	# 화면이 표시를 덮는다. 저장 지점 3곳(D09 §2.4 — RACE-03·투어 경계·시즌 경계)의 화면은
	# 전부 전면 불투명 `Background` 를 깔기 때문에 표시가 **한 번도 보인 적이 없다**
	# (12차 실측: 전이 후 형제 인덱스 표시 18 < 화면 19 — 즉 화면이 표시 위에 온다. IMPL-312).
	# `bind()` **앞**에 두는 것이 규칙이다: RACE-03 은 `_on_bound` 에서 저장하므로
	# 순서를 뒤집으면 2.0초 중 앞부분이 화면 밑에서 소모된다.
	if _save_indicator != null:
		move_child(_save_indicator, -1)
	_current.bind(session, payload)


func _on_navigate(target: String, payload: Dictionary) -> void:
	_show(target, payload)


# ── 저장 표시 (D09 본문 §181) ──
#
# 라우터가 든다 — 화면 위에 얹혀 있어야 저장이 화면 전환과 겹쳐도 사라지지 않는다.
# **화면 교체 대상이 아니다**: `_show()` 는 `_current` 만 갈아치우므로 이 노드는 남는다.
#
# **값 창구 결선 완료 (D13 v1.8 별첨A §8.1 +2행 — 사용자 승인 2026-08-18 · 결정 #17).**
# 8차 시점에는 D13 에 행이 없어 `configure()` 를 부르지 않고 표시를 잠재워 뒀다(불변규칙 2 —
# 없는 값을 임의 기입하지 않는다). 행이 서면서 그 유보가 풀린다: 표시 시간 2.0초 ·
# 회전 주기 1.0초/회전이며, **두 값 다 코드가 아니라 `param()` 창구에서 온다.**
# **주의 — 상단 `is_ok()` 가드는 여기까지 덮지 않는다.** 그 가드는 `load_all()` 직후에 서
# 있고 이 조회는 그 뒤라, 행이 사라져도 부팅은 거부되지 않는다(8차 주석의 "부팅을 거부한다"는
# 이 호출 지점에는 성립하지 않는다 — 돌연변이 M5 실측). 행이 없으면 `param()` 이 0.0 을
# 돌려주고 표시가 "구성됐는데 안 도는" 상태가 된다. 그래서 **표 행의 실재 자체를 회귀가
# 별도 축으로 본다**(UISCR ⑪ — 값 비교만으로는 0.0 == 0.0 이 되어 통과한다).
func _mount_save_indicator(data: GameData) -> void:
	_save_indicator = SaveIndicator.new()
	_save_indicator.name = "SaveIndicator"
	_save_indicator.configure(
		data.param("param_fx_save_hold_sec"), data.param("param_fx_save_spin_sec")
	)
	add_child(_save_indicator)
	session.progress_saved.connect(_on_progress_saved)


# 실패한 저장에는 표시를 띄우지 않는다 — §181 의 용도가 "저장 중 종료 경고의 근거"라
# 저장이 안 된 회차에 회전을 보여 주면 근거가 거짓이 된다.
func _on_progress_saved(ok: bool) -> void:
	if ok:
		_save_indicator.flash()
