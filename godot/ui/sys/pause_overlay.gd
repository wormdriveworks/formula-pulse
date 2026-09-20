# SYS-05 일시정지 메뉴 / 시스템 메뉴 — D09 §3.7 · 별첨A §A-5. 라우터 비경유 오버레이 · 공용 씬 `ui/sys/pause_overlay.tscn`.
#
# **두 호스트가 같은 실물을 인스턴스한다 (개선 회차 36 · 사용자 요청 "개러지에도 시스템 메뉴").** RACE-01 은 일시정지
# 메뉴로(재개 · 개입 창 가림막 · SFX 뮤트는 호스트 몫), HUB-01 은 시스템 메뉴로(닫기 · 가림막 없음 · 타이틀로 앞 저장은
# 호스트 몫) 쓴다. 첫 버튼 문면과 저장 지점 경고의 표시 여부만 `setup()` 인자로 갈리고 나머지(옵션·업적 오버레이 ·
# 포커스 트랩 · 즉시 닫힘)는 하나다. 정본 D09 §2 는 옵션·업적 진입을 "타이틀·일시정지 양측"으로만 적는다 — 개러지
# 진입은 그 확장이며 사용자 결정으로 기록한다(impl_log IMPL-535).
#
# **개입 창 중 호출 시: 릴·게이지 존 가림막 + 타이머 정지 (확정)** — 정지 상태에서 보드를
# 숙고하는 소프트 타임 리미트 우회를 차단한다 (F2 보호).
#
# **재개는 즉시다 (개선 회차 35 · 사용자 결정 — D09 §3.7 · 별첨A §A-5 · D13 별첨A "재개 시 3-2-1 카운트인" 폐지).**
# 카운트인은 실시간 조작 게임이 재개 직후의 조작 준비 시간을 주는 장치인데, 이 게임의 개입 창은 소프트 타임
# 리미트일 뿐 반사 조작을 요구하지 않는다. F2 보호는 그대로 선다 — 가림막은 재개와 **같은 호출**에서 내려가고
# 타이머는 그 순간부터 다시 흐르므로, 타이머가 멎은 채 보드가 보이는 프레임이 없다(카운트인 동안 가림막을
# 유지하던 이유가 곧 이것이었다). 값 `param_pause_countin_sec` · 문면 `ui.pause.countFormat` · 노드 `CountLabel` 도
# 함께 걷었다. 모바일(D09-2 §7.1)의 승계 문면은 MS-3 범위 밖이라 그 문서 몫으로 남는다.
#
# 메뉴: 재개 / 옵션 / 업적 / 타이틀로(최근 저장 지점 복귀 경고) — §A-5 확정 4항.
# 업적(SYS-04)은 MS-3 에서 서면서 들어왔다(IMPL-077 범위 제외 해소).
extends Control

signal resumed
signal quit_to_title

var _session: RunSession

@onready var _mask: ColorRect = %BoardMask
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


# resume_label_key = 첫 버튼 문면(레이스 '재개' · 개러지 '닫기') · title_warning = "최근 저장 지점 복귀" 경고 표시 여부
# (개러지는 타이틀로 앞에 저장하므로 끈다).
func setup(run_session: RunSession, resume_label_key: String = "ui.pause.resume",
		title_warning: bool = true) -> void:
	_session = run_session
	var s := _session.data.strings
	(%ResumeButton as Button).text = s.text(resume_label_key)
	(%OptionsButton as Button).text = s.text("ui.pause.options")
	(%AchievementsButton as Button).text = s.text("ui.pause.achievements")
	(%TitleButton as Button).text = s.text("ui.pause.toTitle")
	(%TitleWarning as Label).text = s.text("ui.pause.saveNotice")
	(%TitleWarning as Label).visible = title_warning
	(%ResumeButton as Button).pressed.connect(_resume)
	(%OptionsButton as Button).pressed.connect(_open_options)
	(%AchievementsButton as Button).pressed.connect(_open_achievements)
	(%TitleButton as Button).pressed.connect(func(): quit_to_title.emit())


# intervention = 개입 창 중 호출 여부 — 가림막은 이때만 필요하다 (D09 §3.7)
func open(intervention: bool) -> void:
	_mask.visible = intervention
	_menu.visible = true
	visible = true
	(%ResumeButton as Button).grab_focus()  # 초기 포커스 = 재개 (§A-5)


# 재개/닫기 = 즉시. 가림막·오버레이가 이 호출에서 내려가고 `resumed` 로 호스트가 뒤처리(정지 해제·포커스 복귀)를 한다 —
# 사이에 프레임이 없다. 호스트가 Esc·B 로 닫을 때도 여기로 온다.
func close() -> void:
	visible = false
	resumed.emit()


func _resume() -> void:
	close()


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
