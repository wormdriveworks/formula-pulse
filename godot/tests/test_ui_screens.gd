# UISCR — 화면 단독 인스턴스화 검사 (실화면을 실제로 세워 결속 계약을 본다).
#
# **왜 필요한가.** 화면 층 결함 중에는 데이터·코어 검사가 원리적으로 닿지 못하는 계열이 있다.
# 이번 축은 **문맥 결손**이다: 화면이 `session.outgame` 같은 "있을 때도 없을 때도 있는" 것을
# 무가드로 읽으면, 커리어를 연 경로에서는 멀쩡하고 **타이틀 직행 경로에서만** 죽는다.
# 실제로 SYS-04 가 그렇게 샜다(총괄 판정 IMPL-176 ① — 타이틀 첫 진입 100% 재현).
#
# 검사 축 7종:
#   ① 무커리어 문맥 성립 — SYS-01 → SYS-04 직행(D09 본문 145행·§A-1 규격 진입)
#   ② 패드 순회 폐쇄 — 초기 포커스 보유 (D09 §1.3 · 총괄 판정 IMPL-176 ②)
#   ③ 단독 경로 옵션 정합 — 라우터를 안 거치는 경로가 O9 를 적용하는가 (동 ③)
#   ④ 미구성 상태 차단 — 값 창구를 안 거친 폰트 크기가 렌더될 여지가 없는가 (동 ④)
#   ⑤ 입력맵 계약 — D09 §1.3 매핑표의 액션·기본 바인딩이 실재하는가 (IMPL-184 ①)
#   ⑥ 액션 경유 청취 — 같은 조작이 키보드·패드·액션 3경로에서 같은 결과인가 (IMPL-190 ①②)
#   ⑦ 표시 기구 — 툴팁 고정·감광 등채널 (동 ③④)
#
# **첫 프레임(`_process`)에서 돈다.** `_init()` 시점에는 `root` 가 없어 `add_child` 자체가
# 불가능하고, `_initialize()` 시점에는 `root` 가 있어도 **아직 트리 안이 아니다** — 그래서
# 화면이 `grab_focus()` 를 부르면 `!is_inside_tree()` 로 튕긴다(실측). 라우터가 화면을 세우는
# 실제 문맥은 "트리에 이미 들어와 있는 노드가 자식을 붙이는" 상황이므로, 첫 프레임이
# 그 문맥의 재현이다.
extends SceneTree

const ACHIEVEMENT_SCENE := "res://ui/sys/achievement_screen.tscn"
const OPTIONS_SCENE := "res://ui/sys/options_screen.tscn"
const RACE_SCENE := "res://ui/race/race_screen.tscn"
const LOG_FEED_SCRIPT := "res://ui/race/log_feed.gd"

var _checked := 0
var _failures := 0


func _process(_delta: float) -> bool:
	var data := GameData.new()
	if not data.load_all():
		print("UI_SCREENS_FAIL data load")
		quit(1)
		return true
	_achievement_without_career(data)
	_achievement_with_career(data)
	_initial_focus(data)
	_standalone_boot_applies_o9()
	_log_feed_requires_configure()
	_input_map_contract()
	_race_input_via_actions()
	_tab_cycle_actions(data)
	_detail_info_pin(data)
	_hold_dim_is_neutral()
	print("")
	# 검사 수 하한 — 씬 로드 실패로 스위트가 쪼그라들면 "통과"가 아니다.
	if _checked < 67:
		print("UI_SCREENS_FAIL checks=%d < 하한 67 (스위트 축소·씬 로드 실패 의심)" % _checked)
		quit(1)
		return true
	if _failures == 0:
		print("UI_SCREENS_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("UI_SCREENS_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)
	return true


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if condition:
		return
	_failures += 1
	print("  [FAIL] %s%s" % [label, (" — " + detail) if detail != "" else ""])


# 씬을 세워 세션을 물린다. 라우터가 하는 순서 그대로다 —
# `session` 주입 → `add_child`(여기서 `_ready()`) → `bind()`.
func _mount(scene_path: String, session: RunSession) -> Control:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_ok("씬 로드: %s" % scene_path, false)
		return null
	var screen := packed.instantiate() as Control
	screen.session = session
	root.add_child(screen)
	screen.bind(session, {})
	return screen


func _unmount(screen: Control) -> void:
	if screen == null:
		return
	root.remove_child(screen)
	screen.queue_free()


# 표시된 업적 행 수 — 탭 패널을 전부 훑는다. 탭 하나가 통째로 비어도 잡히게 합계로 센다.
func _row_count(screen: Control) -> int:
	var total := 0
	var body := screen.get_node("%TabBody") as Control
	for scroll in body.get_children():
		for panel in scroll.get_children():
			total += panel.get_child_count()
	return total


# ── ① 무커리어 문맥 (SYS-01 → SYS-04 직행) ──
# `setup()` 만 하고 `begin_career()` 를 부르지 않는다 = 타이틀 화면의 세션 상태 그대로.
func _achievement_without_career(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	_ok("전제: 무커리어 세션은 outgame 을 갖지 않는다", session.outgame == null)
	var screen := _mount(ACHIEVEMENT_SCENE, session)
	if screen == null:
		return
	# 널 역참조가 나면 `_on_bound()` 가 중간에 끊긴다 — 아래 세 축이 그 중단을 잡는다.
	# (요약 문면은 `_build_tabs()` 앞이고 행 생성은 뒤라, 어디서 끊겼는지도 갈린다.)
	_ok("헤더 문면 세팅", not (screen.get_node("%HeaderLabel") as Label).text.is_empty())
	_ok("요약 문면 세팅", not (screen.get_node("%SummaryLabel") as Label).text.is_empty(),
		(screen.get_node("%SummaryLabel") as Label).text)
	_ok("탭 5개 생성", (screen.get_node("%TabRow") as Control).get_child_count() == 5,
		"actual=%d" % (screen.get_node("%TabRow") as Control).get_child_count())
	# **행 전수 생성** — 무커리어라고 목록이 줄면 안 된다. 총수 가늠 허용이 §5.5 명문이다.
	_ok("업적 행 전수 생성", _row_count(screen) == data.achievements.size(),
		"actual=%d expected=%d" % [_row_count(screen), data.achievements.size()])
	# [가안] 무커리어 = 달성 0. 요약 문면에 달성 수가 들어가므로 0 이 실제로 실렸는지 본다.
	_ok("무커리어 달성 표시 0",
		(screen.get_node("%SummaryLabel") as Label).text.contains("0"),
		(screen.get_node("%SummaryLabel") as Label).text)
	_unmount(screen)


# ── 커리어 적재 후 거동 무변경 ──
# 가드를 넣느라 정상 경로가 상해 있으면 여기서 갈린다 (달성분이 사라지는 반대 결함).
func _achievement_with_career(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	session.begin_career(2)
	var first_id := String(data.achievements.keys()[0])
	session.outgame.achievements[first_id] = 1
	var screen := _mount(ACHIEVEMENT_SCENE, session)
	if screen == null:
		return
	_ok("커리어 적재 시에도 행 전수 생성", _row_count(screen) == data.achievements.size(),
		"actual=%d expected=%d" % [_row_count(screen), data.achievements.size()])
	# 달성 1건이 요약에 반영되는가 — 무커리어(0)와 **다른 문면**이어야 한다.
	var summary := (screen.get_node("%SummaryLabel") as Label).text
	_ok("커리어 달성분이 요약에 반영", summary.contains("1"), summary)
	_unmount(screen)


# ── ② 초기 포커스 (D09 §1.3 패드 순회 폐쇄) ──
# 포커스를 가진 노드가 없으면 패드로는 아무것도 고를 수 없다 — 화면이 잠긴다.
func _initial_focus(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	for entry in [["SYS-04 업적", ACHIEVEMENT_SCENE], ["SYS-03 옵션", OPTIONS_SCENE]]:
		var screen := _mount(String(entry[1]), session)
		if screen == null:
			continue
		var focused := root.gui_get_focus_owner()
		_ok("%s — 초기 포커스 보유" % String(entry[0]), focused != null)
		_ok("%s — 포커스가 화면 안에 있다" % String(entry[0]),
			focused != null and screen.is_ancestor_of(focused),
			str(focused))
		_unmount(screen)


# ── ③ 단독 인스턴스화 경로도 O9 를 적용하는가 (총괄 판정 IMPL-176 ③) ──
#
# `race_screen` 은 세션이 없으면 **스스로 세션을 세우는 단독 경로**(`_boot()`)를 갖는다
# (디버그 씬·캡처 하네스가 그 경로로 뜬다). 팔레트는 정적 클래스라 옵션을 밀어 넣는 구조인데
# 그 밀어 넣기가 `FlowScreen.bind()` 에만 있으면, 단독 경로에서만 화면이 옛 색으로 뜬다.
# UIOPT 는 `bind()` 경로만 보므로 이 축은 원리적으로 그쪽 사각이다.
func _standalone_boot_applies_o9() -> void:
	var packed := load(RACE_SCENE) as PackedScene
	_ok("레이스 씬 로드", packed != null)
	if packed == null:
		return
	var screen := packed.instantiate() as Control
	# **세션을 주지 않는다** = 단독 경로. 반대 상태에서 출발해야 `_boot()` 이 덮는지 갈린다.
	UiPalette.colorblind = true
	root.add_child(screen)
	_ok("단독 경로가 세션을 세운다", screen.session != null)
	var expects_alt: bool = screen.session != null \
		and screen.session.options.index_of("o9") == 1
	_ok("단독 경로가 O9 를 팔레트에 적용한다", UiPalette.colorblind == expects_alt,
		"palette=%s session_o9=%s" % [str(UiPalette.colorblind), str(expects_alt)])
	UiPalette.colorblind = false
	_unmount(screen)


# ── ④ 미구성 상태가 유효한 폰트 크기를 갖지 않는가 (총괄 판정 IMPL-176 ④) ──
#
# `configure()` 미호출 경로가 생기면 D13 창구 밖의 수치가 **조용히 실렌더된다** — 화면은 뜨고
# 글자만 미묘하게 다르므로 눈으로는 잡히지 않고, FONT-B 도 못 잡는다(리터럴이 오버라이드
# 인자가 아니라 멤버 초기값이라 정적 검사의 사정거리 밖이다). 그래서 검사를 여기 둔다.
func _log_feed_requires_configure() -> void:
	var feed := load(LOG_FEED_SCRIPT).new() as VBoxContainer
	_ok("미구성 폰트 크기 = 센티넬 (리터럴 기본값 부재)",
		feed._font_size == feed.UNCONFIGURED, "actual=%d" % feed._font_size)
	# 센티넬이 실제 폰트 크기 범위 밖인지도 본다 — 8 같은 값이 센티넬로 둔갑하면 무의미하다.
	_ok("센티넬은 렌더 가능한 크기가 아니다", feed.UNCONFIGURED <= 0,
		"sentinel=%d" % feed.UNCONFIGURED)
	feed.configure(4, 9)
	_ok("구성 후에는 D13 값을 보유", feed._font_size == 9, "actual=%d" % feed._font_size)
	feed.free()


# ── ⑤ 입력맵 계약 (D09 §1.3 공통 층 매핑표 · 총괄 판정 IMPL-184 ①) ──
#
# **액션의 존재와 기본 바인딩은 리매핑 탭(§6.4)의 전제 골격이다** — 재바인딩 UI 는 액션이
# 이미 있을 때만 성립한다. 그래서 "나중에 기본값이 바뀌어도 액션 자체는 있다"를 계약으로 고정한다.
#
# 패드 바인딩은 **버튼 인덱스로 단언한다**(as_text 는 표기 문구라 엔진 판올림에 흔들린다).
# 인덱스는 엔진에서 실측한 값이다 — A=0 · B=1 · Y=3 · Start=6 · LB=9 · RB=10 · D패드 11~14.
const INPUT_CONTRACT := {
	"ui_accept": 0,     # 확인 / 선택 = A
	"ui_cancel": 1,     # 취소 / 뒤로 = B
	"tab_prev": 9,      # 탭 전환 = LB
	"tab_next": 10,     # 탭 전환 = RB
	"pause_menu": 6,    # 일시정지 메뉴 = Start
	"detail_info": 3,   # 상세 정보 = Y
}
# 포커스 이동 — D패드. 좌스틱 축은 별도로 본다(버튼이 아니라 모션 이벤트다).
const FOCUS_CONTRACT := {"ui_up": 11, "ui_down": 12, "ui_left": 13, "ui_right": 14}


func _input_map_contract() -> void:
	for action in INPUT_CONTRACT:
		_assert_pad_button(String(action), int(INPUT_CONTRACT[action]))
	for action in FOCUS_CONTRACT:
		_assert_pad_button(String(action), int(FOCUS_CONTRACT[action]))
		_assert_stick_axis(String(action))
	# **키보드 열이 살아 있는가.** `[input]` 에 액션을 적으면 엔진 기본 이벤트를 대체하므로,
	# 패드만 적고 키보드를 빠뜨리면 조용히 키보드 조작이 죽는다 — 실제 위험이라 축을 둔다.
	for action in ["ui_accept", "ui_cancel", "tab_prev", "tab_next", "pause_menu", "detail_info"]:
		var has_key := false
		for event in InputMap.action_get_events(String(action)):
			if event is InputEventKey:
				has_key = true
		_ok("%s — 키보드 바인딩 보존" % String(action), has_key)


func _assert_pad_button(action: String, button_index: int) -> void:
	if not InputMap.has_action(action):
		_ok("액션 실재: %s" % action, false)
		return
	var found := false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton \
			and (event as InputEventJoypadButton).button_index == button_index:
			found = true
	_ok("%s — 패드 버튼 %d 바인딩" % [action, button_index], found)


func _assert_stick_axis(action: String) -> void:
	var found := false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			found = true
	_ok("%s — 좌스틱 축 바인딩" % action, found)


# 액션 이벤트 1건을 만들어 준다. `InputEventAction` 은 `is_action_pressed()` 에 그대로 걸리므로
# 키맵·뷰포트 배관을 타지 않고 **청취 층만** 검사할 수 있다.
func _action_event(action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _key_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _pad_event(button_index: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = true
	return event


# ── ⑥ RACE-01 액션 경유 전환 (총괄 판정 IMPL-190 ①) ──
#
# 원시 키코드 직독은 `InputEventKey` 만 보므로 **패드가 아예 도달하지 못한다**.
# 세 입력(키보드·패드·액션)이 같은 결과를 내는지를 본다 — 키보드 거동 보존이 전환의 계약이다.
func _race_input_via_actions() -> void:
	for entry in [["액션", "ui_accept"], ["키보드 Space", ""], ["패드 A", ""]]:
		var packed := load(RACE_SCENE) as PackedScene
		if packed == null:
			_ok("레이스 씬 로드", false)
			return
		var screen := packed.instantiate() as Control
		root.add_child(screen)
		var label := String(entry[0])
		var before: int = screen.engine.turn_phase
		_ok("%s — 전제: T1 대기" % label, before == RaceTypes.TurnPhase.T1_SECTOR_OPEN,
			"phase=%d" % before)
		var event: InputEvent
		match label:
			"액션": event = _action_event("ui_accept")
			"키보드 Space": event = _key_event(KEY_SPACE)
			_: event = _pad_event(0)
		screen._unhandled_input(event)
		# 스핀 커밋 = 봉인 개시. 국면이 T1 을 벗어났는지로 본다 (결과는 보지 않는다 — 불변규칙 5).
		_ok("%s — 스핀 커밋 도달" % label,
			screen.engine.turn_phase != RaceTypes.TurnPhase.T1_SECTOR_OPEN,
			"phase=%d" % screen.engine.turn_phase)
		_unmount(screen)
	# 일시정지도 같은 축 — 액션·키보드·패드 3경로
	for entry2 in [["액션", "pause_menu"], ["키보드 Esc", ""], ["패드 Start", ""]]:
		var packed2 := load(RACE_SCENE) as PackedScene
		var screen2 := packed2.instantiate() as Control
		root.add_child(screen2)
		var label2 := String(entry2[0])
		_ok("%s — 전제: 정지 아님" % label2, not screen2._paused)
		var event2: InputEvent
		match label2:
			"액션": event2 = _action_event("pause_menu")
			"키보드 Esc": event2 = _key_event(KEY_ESCAPE)
			_: event2 = _pad_event(6)
		screen2._unhandled_input(event2)
		_ok("%s — 일시정지 열림" % label2, screen2._paused)
		_unmount(screen2)


# ── ⑦ 탭 순회 액션 (총괄 판정 IMPL-190 ②) ──
func _tab_cycle_actions(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	for entry in [["SYS-03 옵션", OPTIONS_SCENE, 5], ["SYS-04 업적", ACHIEVEMENT_SCENE, 5]]:
		var screen := _mount(String(entry[1]), session)
		if screen == null:
			continue
		var label := String(entry[0])
		_ok("%s — 전제: 탭 %d개·첫 탭 활성" % [label, int(entry[2])],
			screen._tab_panels.size() == int(entry[2]) and screen._active_tab == 0,
			"tabs=%d active=%d" % [screen._tab_panels.size(), screen._active_tab])
		screen._unhandled_input(_action_event("tab_next"))
		_ok("%s — tab_next 로 다음 탭" % label, screen._active_tab == 1,
			"active=%d" % screen._active_tab)
		_ok("%s — 패널 가시성이 따라온다" % label,
			(screen._tab_panels[1] as Control).visible
				and not (screen._tab_panels[0] as Control).visible)
		screen._unhandled_input(_action_event("tab_prev"))
		_ok("%s — tab_prev 로 되돌아온다" % label, screen._active_tab == 0)
		# [가안] 경계 감김 — 첫 탭에서 prev 는 마지막으로
		screen._unhandled_input(_action_event("tab_prev"))
		_ok("%s — 경계에서 감긴다(wrap)" % label,
			screen._active_tab == int(entry[2]) - 1, "active=%d" % screen._active_tab)
		_unmount(screen)


# ── ⑧ 상세 정보 고정 (총괄 판정 IMPL-190 ③) ──
func _detail_info_pin(data: GameData) -> void:
	var session := RunSession.new()
	session.setup(data)
	var screen := _mount(ACHIEVEMENT_SCENE, session)
	if screen == null:
		return
	var focused := root.gui_get_focus_owner()
	_ok("전제: 포커스 대상 존재", focused != null)
	if focused == null:
		_unmount(screen)
		return
	# 툴팁이 비어 있으면 아무것도 띄우지 않는다 — 빈 상자 금지
	focused.tooltip_text = ""
	screen._shortcut_input(_action_event("detail_info"))
	_ok("툴팁 없음 → 미표출", screen.detail_text().is_empty(), screen.detail_text())
	focused.tooltip_text = "detail probe"
	screen._shortcut_input(_action_event("detail_info"))
	_ok("툴팁 고정 표출", screen.detail_text() == "detail probe", screen.detail_text())
	# 코드 생성 Control 이므로 폰트 창구를 거쳐야 한다 (FONT · 불변규칙 2)
	var pinned := screen.get_node("%s/DetailText" % FlowScreen.DETAIL_PANEL_NAME) as Label
	_ok("고정 라벨이 D13 폰트 크기 보유",
		pinned.get_theme_font_size("font_size") == data.param_int("param_font_size_body"),
		"actual=%d" % pinned.get_theme_font_size("font_size"))
	# 같은 액션 재입력 = 해제
	screen._shortcut_input(_action_event("detail_info"))
	_ok("재입력으로 해제", screen.detail_text().is_empty())
	_unmount(screen)


# ── ⑨ 홀드 감광 등채널 (총괄 판정 IMPL-190 ④) ──
# 감광은 상태 표시이지 색 정보가 아니다 — 채널이 갈리면 비홀드 릴에 색상 편이가 생기고,
# 그것은 심볼 판독(색+도상 이중 부호화)에 잡음이 된다.
func _hold_dim_is_neutral() -> void:
	var packed := load(RACE_SCENE) as PackedScene
	if packed == null:
		_ok("레이스 씬 로드", false)
		return
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	var dim: Color = (screen._reel_panels[0] as Control).modulate
	_ok("전제: 비홀드 릴은 감광 상태", dim.r < 1.0, str(dim))
	_ok("감광이 등채널 (색상 편이 0)",
		is_equal_approx(dim.r, dim.g) and is_equal_approx(dim.g, dim.b), str(dim))
	_unmount(screen)
