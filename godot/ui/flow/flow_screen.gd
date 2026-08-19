# 화면 베이스 — D09 §8.1 대장의 각 화면이 공유하는 계약.
#
# 화면은 **전이를 스스로 수행하지 않고 요청만 한다**(`navigate`). 실제 교체는 라우터가 하며,
# 그래야 D09 §2.3 플로우맵에 없는 전이가 화면 안에서 몰래 생기지 않는다
# ("상태 머신에 없는 화면 전이를 추가하지 않는다" — D09 §2.3 전이 폐쇄성).
class_name FlowScreen
extends Control

signal navigate(target: String, payload: Dictionary)

var session: RunSession

# 폰트 계열 (D10 §5.7 확정단 — 값 창구 D13 `param_font_size_body`·`param_font_size_head`).
#
# **코드로 만든 Control 은 프로젝트 기본 폰트 크기를 상속하지 않는다** — 엔진 기본 테마의 16 으로
# 해석된다(실측). 640×360 캔버스에서 16 은 레이아웃을 깨뜨리는데, `.tscn` 노드는 멀쩡하고
# 코드 생성분만 새기 때문에 화면을 눈으로 훑어서는 잡히지 않는다(12화면 34지점 실측 — IMPL-147).
# 그래서 ①값을 베이스가 한 번만 조달하고 ②FONT 정적 검사가 누락을 기계로 잡는다.
var _body_font_size := 9
var _head_font_size := 14


func bind(run_session: RunSession, payload: Dictionary) -> void:
	session = run_session
	# **`_on_bound()` 보다 먼저 채운다** — 화면 초기화가 이 값으로 Control 을 만든다.
	if session != null and session.data != null:
		_body_font_size = session.data.param_int("param_font_size_body")
		_head_font_size = session.data.param_int("param_font_size_head")
	# O9 색각 대체 팔레트 — 폰트 계열과 같은 이유로 `_on_bound()` 보다 먼저다.
	# 화면 초기화가 이 색으로 컨트롤을 칠하기 때문에 순서가 규격이다.
	if session != null:
		UiPalette.apply_options(session.options)
	_on_bound(payload)
	# 진입음·조작음은 **`_on_bound()` 뒤**다 — 화면이 계산한 상태(무대 id·VN 정조)를
	# 진입 이벤트가 근거로 삼고, 초기화가 만든 동적 버튼까지 결속 대상에 들어온다.
	if _audio_auto_bind():
		audio_bind_controls()
	for event_id in _audio_enter_events():
		sfx(String(event_id))


# 화면별 초기화 지점 — 라우터가 세션을 넣어 준 뒤 불린다.
func _on_bound(_payload: Dictionary) -> void:
	pass


func go(target: String, payload: Dictionary = {}) -> void:
	navigate.emit(target, payload)


# ── 사운드 (D11 §1.4 이벤트 결속 · D12 §10.2) ──
#
# 화면은 **게임 이벤트 id 만 던진다.** 무엇이 울릴지는 `sound_map` 표가 정하므로 화면이
# SFX id 를 들고 있는 경로가 없다 — '이 화면 전용 SFX'가 구조적으로 생겨날 수 없다(C-A2).
# 봉인·재트리거·채널 상한은 디스패처가 강제하므로 호출 지점을 잘못 잡아도 결과가 새지 않는다.

# 조작음 지정 메타 — 기본(`ui_decide`) 대신 다른 이벤트를 울릴 버튼에 붙인다.
# 빈 문자열이면 일반 조작음을 붙이지 않는다(핸들러가 자기 게임 이벤트를 직접 울리는 경우).
const AUDIO_EVENT_META := "audio_event"
const AUDIO_BOUND_META := "audio_bound"


func sfx(event_id: String) -> void:
	if session == null or session.audio == null:
		return
	# **이름을 잘못 적으면 영원히 조용하다** — 무음 폴백 단계에서는 그 침묵이 정상과 구분되지
	# 않으므로 침묵하지 않고 보고한다(IMPL-019 계열의 "없는 것은 조용히 넘기지 않는다").
	if session.data != null and not session.data.sound_map.has(event_id):
		push_error("FlowScreen: sound_map has no event '%s'" % event_id)
		return
	session.audio.emit(event_id)


# 화면 진입 시 울릴 이벤트 목록 (BGM·앰비언스·정거장음). 화면이 재정의한다.
func _audio_enter_events() -> Array:
	return []


# 조작음 자동 결속 여부. 레이스 HUD 처럼 버튼 하나하나가 고유 게임 행동인 화면은 끈다.
func _audio_auto_bind() -> bool:
	return true


# UI 조작음 결속 — 버튼마다 손으로 걸면 **나중에 만든 버튼에서 조용히 빠진다.**
# 화면이 동적으로 버튼을 만든 뒤 다시 부를 수 있다(중복 결속은 메타로 막는다).
func audio_bind_controls(root: Node = null) -> void:
	var scope: Node = root if root != null else self
	for node in scope.find_children("*", "BaseButton", true, false):
		_audio_bind_button(node as BaseButton)


func _audio_bind_button(button: BaseButton) -> void:
	if button == null or button.has_meta(AUDIO_BOUND_META):
		return
	button.set_meta(AUDIO_BOUND_META, true)
	button.focus_entered.connect(sfx.bind("ui_cursor"))
	if button.toggle_mode:
		button.toggled.connect(_on_audio_toggled)
		return
	var event_id := String(button.get_meta(AUDIO_EVENT_META, "ui_decide"))
	if event_id.is_empty():
		return
	button.pressed.connect(sfx.bind(event_id))


func _on_audio_toggled(_pressed: bool) -> void:
	sfx("ui_toggle")


# ── 상세 정보 고정 (D09 §1.3 '상세 정보(툴팁 고정) = T | Y (포커스 대상)') ──
#
# 엔진 기본 툴팁은 **마우스 호버 전속**이라 패드·키보드로는 띄울 방법이 없었다 —
# 매핑표에 행이 있는데 소비부가 0 이던 자리다(5차 실태 조사 · 총괄 판정 IMPL-190 ③).
#
# **`_shortcut_input` 에 둔 것은 의도다.** 화면들이 저마다 `_unhandled_input` 을 정의하는데
# GDScript 는 자동 super 호출이 없어, 베이스에 같은 이름을 두면 **정의한 화면에서만 조용히
# 죽는다**. `_shortcut_input` 은 아무 화면도 쓰지 않는 층이라 상속이 성립한다.
#
# 최소 기구다 — 씬·라우트를 신설하지 않고 화면 위 오버레이 1장을 코드로 만든다
# (씬 소유권 = 주력 · `.tscn` 무접촉).
#
# **[가안] 규격 3건 (D09 침묵분 — impl_log 등재):**
#   · 위치 = 화면 하단 중앙. 포커스 대상 옆에 붙이면 정작 그 대상을 가린다
#   · 해제 = 같은 액션 재입력 · 포커스 이동 · 화면 이탈
#   · 대상에 `tooltip_text` 가 비어 있으면 **아무것도 띄우지 않는다** (빈 상자를 띄우지 않는다)
const DETAIL_PANEL_NAME := "DetailInfoPanel"

var _detail_panel: PanelContainer = null


func _shortcut_input(event: InputEvent) -> void:
	if not event.is_action_pressed("detail_info"):
		return
	get_viewport().set_input_as_handled()
	_toggle_detail()


# 토글을 별도 함수로 뺀 것은 **컨텍스트 층이 재배치된 화면 때문**이다 (D09 v1.3 §1.3).
# RACE-01 은 패드 Y 를 차지 개입에 쓰고 상세 정보를 `LB 홀드 + Y` 로 옮겼으므로,
# 그 화면은 `_shortcut_input` 을 재정의해 Y 를 먼저 가로챈 뒤 이 토글만 불러야 한다.
func _toggle_detail() -> void:
	if _detail_panel != null:
		_hide_detail()
		return
	_show_detail()


func _show_detail() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null:
		return
	var text := focused.tooltip_text.strip_edges()
	if text.is_empty():
		return   # 띄울 내용이 없으면 상자도 없다
	_detail_panel = PanelContainer.new()
	_detail_panel.name = DETAIL_PANEL_NAME
	_detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.BG_PANEL
	style.border_color = UiPalette.FRAME_LINE
	style.set_border_width_all(1)
	style.set_content_margin_all(4)
	_detail_panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.name = "DetailText"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(220, 0)
	# 코드 생성 Control 은 프로젝트 기본 폰트를 상속하지 않는다 — 값 창구 경유 (FONT · 불변규칙 2)
	label.add_theme_font_size_override("font_size", _body_font_size)
	label.add_theme_color_override("font_color", UiPalette.TEXT_PRIMARY)
	_detail_panel.add_child(label)

	add_child(_detail_panel)
	# ── 하단 중앙 고정 ([가안] 1 — IMPL-194) ──
	# **`set_anchors_preset()` 을 쓰지 않는다.** 그 호출은 기본값(`keep_offsets=false`)에서
	# **현재 rect 를 보존하도록 오프셋을 역산**하는데, 이 시점의 패널은 컨테이너 정렬 전이라
	# rect 가 (0,0,0,0) 이다. 그러면 하단·중앙 앵커에 0크기 rect 가 보존돼
	# `offset_left = -부모폭` · `offset_top = -부모높이` 가 박히고 — **패널이 좌상단에 뜬다**
	# (실측: 640×360 에서 offsets L=-320 T=-360 · rect P=(0,0)). 저장 표시와 같은 함정이다
	# (주력 9차 실증 IMPL-228 · 총괄 배정 IMPL-229 ⑥).
	#
	# **크기를 모르는 컨트롤이라 오프셋에 치수를 적을 수도 없다** — 패널은 내용이 정하는
	# 크기이고 그 값은 다음 프레임에야 선다. 그래서 오프셋은 0 으로 두고 **성장 방향**으로
	# 배치한다: 가로 BOTH = 중앙에서 양쪽으로 · 세로 BEGIN = 하단에서 위로.
	# 이러면 배치가 호출 순서에도, 그 시점의 크기에도 의존하지 않는다.
	_detail_panel.anchor_left = 0.5
	_detail_panel.anchor_right = 0.5
	_detail_panel.anchor_top = 1.0
	_detail_panel.anchor_bottom = 1.0
	_detail_panel.offset_left = 0.0
	_detail_panel.offset_right = 0.0
	_detail_panel.offset_top = 0.0
	_detail_panel.offset_bottom = 0.0
	_detail_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_detail_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# 포커스가 옮겨가면 내용이 어긋나므로 함께 내린다. 화면이 사라질 때는 자식이라 같이 간다.
	if not get_viewport().gui_focus_changed.is_connected(_on_detail_focus_changed):
		get_viewport().gui_focus_changed.connect(_on_detail_focus_changed)


func _hide_detail() -> void:
	if get_viewport() != null and get_viewport().gui_focus_changed.is_connected(_on_detail_focus_changed):
		get_viewport().gui_focus_changed.disconnect(_on_detail_focus_changed)
	if _detail_panel == null:
		return
	remove_child(_detail_panel)
	_detail_panel.queue_free()
	_detail_panel = null


func _on_detail_focus_changed(_node: Control) -> void:
	_hide_detail()


# 검사·호출부 조회용 — 고정 상태와 내용은 화면 밖에서 볼 수 있어야 회귀가 성립한다.
func detail_text() -> String:
	if _detail_panel == null:
		return ""
	return (_detail_panel.get_node("DetailText") as Label).text
