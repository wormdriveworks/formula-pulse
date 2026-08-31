# SYS-05 일시정지 메뉴 — D09 §3.7 · 별첨A §A-5. RACE-01 내부 오버레이 (라우터 비경유).
#
# **개입 창 중 호출 시: 릴·게이지 존 가림막 + 타이머 정지 (확정)** — 정지 상태에서 보드를
# 숙고하는 소프트 타임 리미트 우회를 차단한다 (F2 보호). 재개 시 3-2-1 카운트인.
#
# 메뉴: 재개 / 옵션 / 업적 / 타이틀로(최근 저장 지점 복귀 경고) — §A-5 확정 4항.
# 업적(SYS-04)은 MS-3 에서 서면서 들어왔다(IMPL-077 범위 제외 해소).
extends Control

signal resumed
signal quit_to_title

var _session: RunSession
var _counting := false
var _count_left := 0.0
var _countin_total := 3.0

@onready var _mask: ColorRect = %BoardMask
@onready var _count_label: Label = %CountLabel
@onready var _menu: Control = %MenuColumn


# ── 모달 포커스 트랩 (실기 결함 교정 — 2026-09-01) ──
#
# 정지 중 Tab(ui_focus_next)이 **배면 레이스 UI 로 포커스를 끌고 나갔다** — 그 상태의 확정
# 입력이 정지 중인 게임의 소모품을 실제로 소비했다(실측: 리페어 키트 소진·섀시 +15).
# `_unhandled_input` 차단(race_screen:398)은 액션 층만 막고 GUI 포커스 경로는 못 막는다.
# 오버레이가 떠 있는 동안 포커스가 밖으로 나가면 그 자리에서 되끌어온다 — 옵션·업적
# 오버레이는 이 노드의 자식이므로 트랩에 걸리지 않는다.
# 연결은 트리 재적 기간과 1:1 로 묶는다(_enter/_exit_tree 쌍) — _ready 단발 연결은 화면이
# 트리에서 내려간 뒤에도 뷰포트에 남아, 하네스가 다른 화면을 세울 때 트리 밖 grab_focus 를
# 쏘는 잔향이 됐다(UISCR 마운트 로그 실측).
func _enter_tree() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func _exit_tree() -> void:
	get_viewport().gui_focus_changed.disconnect(_on_focus_changed)


func _on_focus_changed(control: Control) -> void:
	if not is_inside_tree() or not visible or not _menu.visible or control == null:
		return
	if is_ancestor_of(control):
		return
	(%ResumeButton as Button).grab_focus()


func setup(run_session: RunSession) -> void:
	_session = run_session
	_countin_total = _session.data.param("param_pause_countin_sec")
	var s := _session.data.strings
	(%ResumeButton as Button).text = s.text("ui.pause.resume")
	(%OptionsButton as Button).text = s.text("ui.pause.options")
	(%AchievementsButton as Button).text = s.text("ui.pause.achievements")
	(%TitleButton as Button).text = s.text("ui.pause.toTitle")
	(%TitleWarning as Label).text = s.text("ui.pause.saveNotice")
	(%ResumeButton as Button).pressed.connect(_begin_countin)
	(%OptionsButton as Button).pressed.connect(_open_options)
	(%AchievementsButton as Button).pressed.connect(_open_achievements)
	(%TitleButton as Button).pressed.connect(func(): quit_to_title.emit())


# intervention = 개입 창 중 호출 여부 — 가림막은 이때만 필요하다 (D09 §3.7)
func open(intervention: bool) -> void:
	_mask.visible = intervention
	_count_label.visible = false
	_menu.visible = true
	_counting = false
	visible = true
	(%ResumeButton as Button).grab_focus()  # 초기 포커스 = 재개 (§A-5)


func _begin_countin() -> void:
	# 카운트인 중에도 가림막은 유지한다 — 카운트다운 동안 보드를 읽으면 우회가 성립한다
	_menu.visible = false
	_count_label.visible = true
	_count_left = _countin_total
	_counting = true


func _process(delta: float) -> void:
	if not _counting:
		return
	_count_left -= delta
	if _count_left <= 0.0:
		_counting = false
		visible = false
		resumed.emit()
		return
	var count_text := _session.data.strings.text("ui.pause.countFormat", {
		"count": int(ceil(_count_left)),
	})
	_count_label.text = count_text


func _open_options() -> void:
	var packed := load("res://ui/sys/options_screen.tscn") as PackedScene
	var options: Control = packed.instantiate()
	add_child(options)
	options.open_as_overlay(_session)
	# 닫힘은 options 쪽 closed 시그널 — 오버레이 회수는 options 가 스스로 한다 (queue_free).
	# **포커스는 돌려받아야 한다** (실기 결함 — 2026-09-01): 오버레이가 queue_free 되면
	# 그 안의 포커스가 허공에 떨어져, 메뉴가 떠 있는데 방향키·확인이 전부 무반응이 된다.
	# 패드에는 ui_focus_next 가 없어 복구 수단도 없다 — 닫힘 시그널에서 되잡는다.
	options.closed.connect(func(): (%OptionsButton as Button).grab_focus())


func _open_achievements() -> void:
	var packed := load("res://ui/sys/achievement_screen.tscn") as PackedScene
	var achievements: Control = packed.instantiate()
	add_child(achievements)
	achievements.open_as_overlay(_session)
	# 옵션과 같은 계열 — 닫힘 시 포커스 복원 (같은 결함·같은 교정)
	achievements.closed.connect(func(): (%AchievementsButton as Button).grab_focus())
