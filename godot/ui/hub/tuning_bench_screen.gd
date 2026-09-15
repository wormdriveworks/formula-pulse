# HUB-03 튜닝 벤치 — D09 §4.3 · 별첨A §A-13.
#
# 기본 4계통(T1~T4) + 심화 2계통(T5·T6 — 오스카 합류 개방, 미개방 잠금 표기).
# 계통 행 = 명칭 · 단계 게이지(●●●○○) · 다음 단계 비용 · 구매.
# 릴 확률 관련 표기·암시 절대 금지 (§7.1 R1) — 효과 문면은 name_key 범위만 쓴다.
#
# 재배분 모드(환급 80% · 마르타 합류 시 90% + COM-01) = 개선 회차 24 결선. 토글이 같은 행을
# '강화'에서 '재배분'으로 바꾼다 — 화면을 새로 세우지 않는 근거는 D09 별첨A §A-13 이
# 이것을 **모드 토글**로 적었다는 것이다(화면 수 억제 · 크루 영입 카드와 같은 형태).
extends HubScreen

const DEEP_LINES := ["tuning_t5", "tuning_t6"]

var _rows: Dictionary = {}
var _locked_lines: Array = []
var _redistribute_mode := false


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
	redistribute.toggle_mode = true
	redistribute.set_meta(AUDIO_EVENT_META, "ui_tab")   # 모드 전환 — 결정음이 아니다
	redistribute.toggled.connect(_on_mode_toggled)
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

	# 효과 증분 (D09 §4.3 "단계 게이지 + 다음 단계 비용 + **효과 증분 표시**" — 개선 회차 18).
	# 종전에는 무엇을 사는지가 화면에 없었다. 효과가 실제로 성능에 닿게 되면서 이 자리가 필요해졌다.
	# 심볼 확률을 말하지 않는다 (§7.1 R1) — 표기는 계수·최대치·판정치의 크기뿐이다.
	var effect_label := Label.new()
	effect_label.add_theme_font_size_override("font_size", _body_font_size)
	effect_label.name = "Effect"
	effect_label.custom_minimum_size = Vector2(96, 0)
	effect_label.add_theme_color_override("font_color", UiPalette.TIMER_LEEWAY)
	row.add_child(effect_label)

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
		_locked_lines.append(tuning_id)
	else:
		buy.pressed.connect(_on_row_action.bind(tuning_id))

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
	# 효과 증분 — 비율 계통은 %p, 정액 계통은 그대로. 부호는 값이 지고 문면은 지지 않는다
	# (T6 은 −7%/단계라 문면에 '+' 를 굳히면 감소 계통이 증가로 읽힌다).
	var line_row: Dictionary = session.data.tuning_lines[tuning_id]
	var per_step := CsvTable.to_float(String(line_row["effect_per_step"]))
	var is_ratio := String(line_row["effect_unit"]) == "ratio"
	var scale := 100.0 if is_ratio else 1.0
	var effect_key := ""
	if step >= max_step:
		effect_key = "ui.tuningBench.effectRatioMaxFormat" if is_ratio else "ui.tuningBench.effectFlatMaxFormat"
	else:
		effect_key = "ui.tuningBench.effectRatioFormat" if is_ratio else "ui.tuningBench.effectFlatFormat"
	(row.get_node("Effect") as Label).text = s.text(effect_key, {
		"current": int(round(per_step * scale * float(step))),
		"next": int(round(per_step * scale * float(step + 1))),
	})
	var cost_label := row.get_node("Cost") as Label
	var buy := row.get_node("Buy") as Button
	if _locked_lines.has(tuning_id):
		return   # 심화 잠금 행 — 버튼이 개방 조건을 이고 있으므로 문면·상태를 건드리지 않는다
	if _redistribute_mode:
		# 재배분 모드 — 환급률·환급액을 **사전 표시**하고 같은 버튼이 되돌리기가 된다 (D09 §4.3).
		buy.text = s.text("ui.tuningBench.redistribute")
		if step <= 0:
			cost_label.text = s.text("ui.tuningBench.refundNone")
			buy.disabled = true
		else:
			cost_label.text = s.text("ui.tuningBench.refundFormat", {
				"ratio": int(round(session.outgame.tuning_refund_ratio() * 100.0)),
				"amount": session.outgame.redistribute_refund(tuning_id),
			})
			buy.disabled = false
		return
	buy.text = s.text("ui.tuningBench.buy")
	if step >= max_step:
		cost_label.text = s.text("ui.tuningBench.maxed")
		buy.disabled = true
	else:
		var cost := session.outgame.tuning_cost(tuning_id, step + 1)
		cost_label.text = s.text("ui.tuningBench.costFormat", {"amount": cost})
		# 통화 = **크레딧** (D13 별첨A §3.5 "단계별 비용 (Cr)" · 코어 `buy_tuning` 이 `_spend_credits`).
		# 개선 회차 4 T1 — 종전에는 DP 잔액으로 잠가서 Cr 2000 을 쥐고도 700 단계가 잠겼고, 표기도 'DP' 였다.
		# **대입으로 바꾼다** (회차 24) — 종전의 `if not buy.disabled` 는 잠금 행을 지키려던 것인데
		# 그 일은 위의 조기 반환이 맡았다. 그대로 두면 최대 단계에서 재배분한 행의 강화 버튼이
		# 죽은 채 남는다 — 한 번 켜진 disabled 를 아무도 끄지 않기 때문이다.
		buy.disabled = session.outgame.credits < cost


# 같은 버튼이 모드에 따라 두 일을 한다 — 행을 두 벌 세우지 않는다 (D09 별첨A §A-13 모드 토글).
func _on_row_action(tuning_id: String) -> void:
	if _redistribute_mode:
		_on_redistribute(tuning_id)
	else:
		_on_buy(tuning_id)


func _on_mode_toggled(pressed: bool) -> void:
	_redistribute_mode = pressed
	# 활성 모드는 **색으로** 표시한다 — 토글의 눌림 상태만으로는 지금 어느 모드인지 읽기 어렵다.
	# 전략실 덱 프리셋·기록실 탭과 같은 방식이다 (개선 회차 20 전례).
	# **`font_pressed_color` 까지 덮어야 보인다** — 눌린 토글은 그 색을 쓰므로 `font_color` 만
	# 덮으면 실기에서 아무 변화가 없다(실렌더로 잡았다). 둘을 함께 건다.
	var toggle := %RedistributeButton as Button
	if pressed:
		toggle.add_theme_color_override("font_color", UiPalette.TIMER_LEEWAY)
		toggle.add_theme_color_override("font_pressed_color", UiPalette.TIMER_LEEWAY)
		toggle.add_theme_color_override("font_hover_pressed_color", UiPalette.TIMER_LEEWAY)
	else:
		toggle.remove_theme_color_override("font_color")
		toggle.remove_theme_color_override("font_pressed_color")
		toggle.remove_theme_color_override("font_hover_pressed_color")
	_refresh_all_rows()


func _on_buy(tuning_id: String) -> void:
	# 튜닝 단계 구매는 재배분(환급 80%)이 존재해 가역이다 — COM-01 비대상 (D09 §1.4 모달 최소주의)
	if not session.outgame.buy_tuning(tuning_id):
		return
	sfx("tuning_install")
	# **전 행을 갱신한다** (개선 2026-09-02 H3) — 자기 행만 갱신하면 잔액이 부족해진 타 계통의
	# 강화 버튼이 산 채로 남아, 누르면 코어 거부로 소리 없이 무반응이 된다.
	_refresh_all_rows()
	refresh_currency()


# 재배분 = **유상이되 가역**이라 COM-01 은 띄우되 비가역 문구는 붙이지 않는다. D09 §1.4 의
# 두 행이 갈려 있다 — "확인 다이얼로그는 비가역·유상 행동에만" / "비가역 행동은 … 비가역 문구 표시".
# 되돌린 단계는 다시 살 수 있고, 영구히 잃는 것은 수수료분뿐이다.
func _on_redistribute(tuning_id: String) -> void:
	var s := session.data.strings
	var line_name := s.text(String(session.data.tuning_lines[tuning_id]["name_key"]))
	var refund := session.outgame.redistribute_refund(tuning_id)
	if refund <= 0:
		return
	var dialog := ConfirmDialog.ask(self, s,
		s.text("ui.tuningBench.redistributeConfirm", {"line": line_name}),
		s.text("ui.tuningBench.costFormat", {"amount": refund}), false, _body_font_size)
	dialog.resolved.connect(func(accepted: bool) -> void:
		if not accepted:
			return
		if session.outgame.redistribute_tuning(tuning_id) <= 0:
			return
		sfx("sell")   # SE-U08 판매 — 환급이 곧 되파는 축이다
		# 크레딧이 늘면 타 계통의 강화 가능성도 함께 바뀐다 (H3 계열 — 전 행 갱신)
		_refresh_all_rows()
		refresh_currency())


func _refresh_all_rows() -> void:
	for row_id in _rows:
		_refresh_row(String(row_id))
