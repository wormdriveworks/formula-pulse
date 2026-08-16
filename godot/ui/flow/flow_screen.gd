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
