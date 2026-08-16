# HUB-03 튜닝 벤치 — D09 §4.3 · 별첨A §A-13.
#
# 기본 4계통(T1~T4) + 심화 2계통(T5·T6 — 오스카 합류 개방, 미개방 잠금 표기).
# 계통 행 = 명칭 · 단계 게이지(●●●○○) · 다음 단계 비용 · 구매.
# 릴 확률 관련 표기·암시 절대 금지 (§7.1 R1) — 효과 문면은 name_key 범위만 쓴다.
#
# 재배분 모드(환급 80% + COM-01)는 이 골격에서 잠금 — 구매 경로가 먼저 선다.
extends HubScreen

const DEEP_LINES := ["tuning_t5", "tuning_t6"]

var _rows: Dictionary = {}


func _on_hub_ready(_payload: Dictionary) -> void:
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.tuningBench.title")
	var list := %LineList as VBoxContainer
	var oscar := session.outgame.crew.has("crew_oscar")
	for tuning_id in session.data.tuning_lines:
		var row := _build_row(String(tuning_id), oscar)
		list.add_child(row)
	var redistribute := %RedistributeButton as Button
	redistribute.text = s.text("ui.tuningBench.redistribute")
	redistribute.disabled = true  # 골격 단계 잠금 — 구매 경로 우선
	redistribute.focus_mode = Control.FOCUS_NONE
	(%BackButton as Button).grab_focus()


func _build_row(tuning_id: String, oscar: bool) -> Control:
	var s := session.data.strings
	var row := HBoxContainer.new()
	row.name = tuning_id.to_pascal_case()
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", _body_font_size)
	name_label.custom_minimum_size = Vector2(120, 0)
	name_label.text = s.text(String(session.data.tuning_lines[tuning_id]["name_key"]))
	row.add_child(name_label)

	var gauge := Label.new()
	gauge.add_theme_font_size_override("font_size", _body_font_size)
	gauge.name = "Gauge"
	gauge.add_theme_color_override("font_color", UiPalette.TIMER_LEEWAY)
	row.add_child(gauge)

	var cost_label := Label.new()
	cost_label.add_theme_font_size_override("font_size", _body_font_size)
	cost_label.name = "Cost"
	cost_label.custom_minimum_size = Vector2(90, 0)
	cost_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	row.add_child(cost_label)

	var buy := Button.new()
	buy.add_theme_font_size_override("font_size", _body_font_size)
	buy.name = "Buy"
	buy.text = s.text("ui.tuningBench.buy")
	row.add_child(buy)

	var deep_locked := DEEP_LINES.has(tuning_id) and not oscar
	if deep_locked:
		# 심화 계통 잠금 — 개방 조건(크루명) 표기 (D09 §4.3)
		var oscar_name := s.text(String(session.data.crew["crew_oscar"]["name_key"]))
		var locked_text := s.text("ui.hub.lockedByCrew", {"crew": oscar_name})
		buy.text = locked_text
		buy.disabled = true
		buy.focus_mode = Control.FOCUS_NONE
	else:
		buy.pressed.connect(_on_buy.bind(tuning_id))

	_rows[tuning_id] = row
	_refresh_row(tuning_id)
	return row


func _refresh_row(tuning_id: String) -> void:
	var s := session.data.strings
	var row: HBoxContainer = _rows[tuning_id]
	var step := session.outgame.tuning_step(tuning_id)
	var max_step := int(session.data.param("param_tuning_max_step"))
	# 단계 게이지 ●●●○○ (§A-13) — 텍스트 표기, 게이지 에셋 유입 시 교체.
	# ●/○ 도 스트링 키 경유다 (V4 — 전 표시 문자열 키 참조)
	var step_filled := s.text("ui.tuningBench.stepFilled")
	var step_empty := s.text("ui.tuningBench.stepEmpty")
	var filled := ""
	for i in range(max_step):
		filled += step_filled if i < step else step_empty
	(row.get_node("Gauge") as Label).text = filled
	var cost_label := row.get_node("Cost") as Label
	var buy := row.get_node("Buy") as Button
	if step >= max_step:
		cost_label.text = s.text("ui.tuningBench.maxed")
		buy.disabled = true
	else:
		var cost := session.outgame.tuning_cost(tuning_id, step + 1)
		var cost_text := s.text("ui.tuningBench.costFormat", {"amount": cost})
		cost_label.text = cost_text
		if not buy.disabled:
			buy.disabled = session.outgame.drive_data < cost


func _on_buy(tuning_id: String) -> void:
	# 튜닝 단계 구매는 재배분(환급 80%)이 존재해 가역이다 — COM-01 비대상 (D09 §1.4 모달 최소주의)
	if not session.outgame.buy_tuning(tuning_id):
		return
	sfx("tuning_install")
	_refresh_row(tuning_id)
	refresh_currency()
