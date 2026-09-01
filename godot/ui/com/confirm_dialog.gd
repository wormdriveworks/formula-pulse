# COM-01 공통 확인 다이얼로그 (D09 §1.4 · 별첨A §A-23).
#
# 유상·비가역 행동 **전속** — 그 외에는 인라인 피드백을 쓴다(모달 최소주의).
# 비가역 항목은 경고행 필수. **초기 포커스 = 취소** (비가역 오입력 방어 — §A-23 확정).
#
# 화면이 아니라 오버레이 컴포넌트다 — 라우터 경로에 넣지 않고 호출 화면이 띄운다.
class_name ConfirmDialog
extends Control

signal resolved(accepted: bool)

var _strings: StringTable
# 코드로 만든 Control 은 프로젝트 기본 폰트를 상속하지 않고 엔진 기본 16 으로 해석된다(실측).
# 640×360 캔버스에서 16 은 레이아웃을 깨뜨리므로 본문 계열 값을 데이터 창구에서 받아 명시 적용한다
# (불변규칙 2 — 코드 기입 금지 · FONT 정적 검사 대상 · IMPL-147).
var _body_font_size := 9
# 닫힐 때 포커스를 돌려줄 호출 지점 (개선 2026-09-02 H2 — 실기: 확정·취소 양 경로에서
# 포커스가 허공에 떨어져 패드가 잠겼다. 전 소비처가 이 창을 쓰므로 여기 한 곳이 전부를 받는다).
var _return_focus: Control


func _init(strings: StringTable, summary: String, cost_text: String, irreversible: bool, body_font_size: int) -> void:
	_strings = strings
	_body_font_size = body_font_size
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 배후 감광 + 입력 차단 (모달)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	# ── 화면 중앙 고정 ──
	# `set_anchors_preset(PRESET_CENTER)` 은 **앵커만 세우고 오프셋은 그대로 둔다.** 여기서는
	# 트리 밖 호출이라 오프셋이 0 으로 남는데, 기본 성장 방향이 END 라 패널의 **좌상단이
	# 화면 중앙에 놓이고 거기서 오른쪽·아래로 자란다** — 중앙이 아니라 우하단 사분면이다
	# (실측: 640×360 에서 pos=(320,180) size=(240,70) · 중앙이면 (200,145)).
	# 성장 방향을 양쪽으로 두어야 앵커가 뜻하는 대로 놓인다 — 온보딩 팁(`garage_screen.gd`)이
	# 이미 그 형태이고, 이쪽만 빠져 있었다. 전수 조사분 (총괄 배정 IMPL-229 ⑥).
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(240, 0)
	# COM-01 = `dialog_modal_9p` (A-FR-05 — D10 이 이 프레임의 용도를 *"모달 다이얼로그
	# (COM-01)"* 로 못박아 뒀다. 소비처가 하나뿐이라 배정에 판단이 없다).
	# **오버라이드를 걷고 타입 변형으로 간다** — 오버라이드가 남으면 테마가 무엇을 등록하든
	# 이 자리는 영원히 옛 박스다(테마 결선이 조용히 무효가 되는 형태).
	panel.theme_type_variation = &"ModalPanel"
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var summary_label := Label.new()
	summary_label.text = summary
	summary_label.add_theme_font_size_override("font_size", _body_font_size)
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(summary_label)

	if not cost_text.is_empty():
		var cost_label := Label.new()
		cost_label.text = cost_text
		cost_label.add_theme_font_size_override("font_size", _body_font_size)
		cost_label.add_theme_color_override("font_color", UiPalette.CURRENCY_CREDIT)
		column.add_child(cost_label)

	if irreversible:
		var warn := Label.new()
		warn.text = _strings.text("ui.confirm.irreversible")
		warn.add_theme_font_size_override("font_size", _body_font_size)
		warn.add_theme_color_override("font_color", UiPalette.gauge_danger())
		column.add_child(warn)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)

	var cancel := Button.new()
	cancel.name = "CancelButton"
	cancel.text = _strings.text("ui.confirm.cancel")
	cancel.add_theme_font_size_override("font_size", _body_font_size)
	cancel.set_meta(FlowScreen.AUDIO_EVENT_META, "ui_cancel")   # SE-U03 취소·닫기
	cancel.pressed.connect(_finish.bind(false))
	buttons.add_child(cancel)

	var ok := Button.new()
	ok.name = "OkButton"
	ok.text = _strings.text("ui.confirm.ok")
	ok.add_theme_font_size_override("font_size", _body_font_size)
	# 위험 프레임(A-FR-09)의 **유일한 소비처**다. 앱 안에서 '위험'인 버튼은
	# 비가역 확인의 수락 하나뿐이고(§A-23 = 비가역 항목에 경고행 필수), 그 자리에는 이미
	# 경고 문면이 `gauge_danger()` 색으로 서 있다 — 프레임은 그 사실을 되풀이할 뿐 새 개념을
	# 들이지 않는다. **가역 확인에는 붙이지 않는다** — 붙이면 '위험'이 '확인'의 동의어가 된다.
	#
	# **폐문 (37차 · 사용자 눈 판정 2026-08-28):** 실물 플레이 검증 회차 관측 = **적합**
	# (총괄 IMPL-481 §2 ① — 대장 16항 전항 적합·교정 없음). 비가역 수락이 가역 수락과
	# 갈려 읽힌다. 배정을 넓히지 않는 것(가역 불부착)도 그대로 확정된다.
	if irreversible:
		ok.theme_type_variation = &"DangerButton"
	ok.pressed.connect(_finish.bind(true))
	buttons.add_child(ok)

	cancel.call_deferred("grab_focus")  # 초기 포커스 = 취소 (오입력 방어)


# 취소 = Esc·패드 B (D09 §1.3 공통 층 "취소/뒤로"). 모달이 키 입력을 소비하지 않으면
# 같은 Esc 가 배후 화면의 뒤로가기(HubScreen)로 흘러 창을 띄운 채 화면이 전이된다.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_finish(false)


func _finish(accepted: bool) -> void:
	# **복원 대상은 emit 앞에 갈무리한다** — resolved 핸들러가 목록을 재구축하며 대상 버튼을
	# free 하거나 화면을 전이시킬 수 있다. 복원은 emit 뒤: 핸들러가 상태(비활성 전환 등)를
	# 끝낸 다음의 사실을 기준으로 되잡아야 한다. 대상이 죽었거나 포커스 불능이면 두지 않는다 —
	# 잘못된 자리에 세우는 것이 소실보다 나쁘다(허브 화면은 Tab 순회로 복구 가능).
	var target := _return_focus
	resolved.emit(accepted)
	if is_instance_valid(target) and target.is_inside_tree() \
		and target.focus_mode != Control.FOCUS_NONE:
		target.grab_focus()
	queue_free()


# 호출 편의 — 부모에 붙이고 결과 시그널을 돌려준다.
static func ask(host: Control, strings: StringTable, summary: String, cost_text: String, irreversible: bool, body_font_size: int) -> ConfirmDialog:
	var dialog := ConfirmDialog.new(strings, summary, cost_text, irreversible, body_font_size)
	# 여는 시점의 포커스 소유자 = 닫힐 때 돌아갈 자리 (H2). 호출부가 넘기게 하지 않는 이유:
	# 소비처가 넷이고 하나라도 빠뜨리면 그 화면만 옛 결함이 남는다 — 창구가 스스로 갈무리한다.
	dialog._return_focus = host.get_viewport().gui_get_focus_owner()
	host.add_child(dialog)
	# 다이얼로그는 화면 결속(`bind`) 이후에 태어나므로 조작음 자동 결속에 잡히지 않는다 —
	# 만든 자리에서 결속한다. 화면이 아닌 곳에서 띄운 경우(호스트가 FlowScreen 이 아님)는
	# 소리 없이 성립한다.
	var screen := host as FlowScreen
	if screen != null:
		screen.audio_bind_controls(dialog)
	return dialog
