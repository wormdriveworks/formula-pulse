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


func _init(strings: StringTable, summary: String, cost_text: String, irreversible: bool) -> void:
	_strings = strings
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 배후 감광 + 입력 차단 (모달)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(240, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.BG_PANEL
	style.border_color = UiPalette.FRAME_LINE
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var summary_label := Label.new()
	summary_label.text = summary
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(summary_label)

	if not cost_text.is_empty():
		var cost_label := Label.new()
		cost_label.text = cost_text
		cost_label.add_theme_color_override("font_color", UiPalette.CURRENCY_CREDIT)
		column.add_child(cost_label)

	if irreversible:
		var warn := Label.new()
		warn.text = _strings.text("ui.confirm.irreversible")
		warn.add_theme_color_override("font_color", UiPalette.TIMER_IMMINENT)
		column.add_child(warn)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)

	var cancel := Button.new()
	cancel.name = "CancelButton"
	cancel.text = _strings.text("ui.confirm.cancel")
	cancel.pressed.connect(_finish.bind(false))
	buttons.add_child(cancel)

	var ok := Button.new()
	ok.name = "OkButton"
	ok.text = _strings.text("ui.confirm.ok")
	ok.pressed.connect(_finish.bind(true))
	buttons.add_child(ok)

	cancel.call_deferred("grab_focus")  # 초기 포커스 = 취소 (오입력 방어)


func _finish(accepted: bool) -> void:
	resolved.emit(accepted)
	queue_free()


# 호출 편의 — 부모에 붙이고 결과 시그널을 돌려준다.
static func ask(host: Control, strings: StringTable, summary: String, cost_text: String, irreversible: bool) -> ConfirmDialog:
	var dialog := ConfirmDialog.new(strings, summary, cost_text, irreversible)
	host.add_child(dialog)
	return dialog
