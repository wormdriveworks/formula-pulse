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
	# 닫힘은 options 쪽 closed 시그널 — 오버레이 회수는 options 가 스스로 한다 (queue_free)


func _open_achievements() -> void:
	var packed := load("res://ui/sys/achievement_screen.tscn") as PackedScene
	var achievements: Control = packed.instantiate()
	add_child(achievements)
	achievements.open_as_overlay(_session)
