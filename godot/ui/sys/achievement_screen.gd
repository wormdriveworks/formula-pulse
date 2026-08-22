# SYS-04 업적 화면 — D09 §5.5 · 별첨A §A-4.
#
# 5카테고리 탭 + 달성률 요약 헤더. 항목 행 = 상태 표기 · 명칭 · 조건 진척.
# **히든(발견형 4 + 관계 도달형 5 = 9종)은 달성 전 "???" 슬롯**으로만 존재한다 —
# 명칭·조건 전부 비노출이되 자리는 남겨 총수 가늠은 허용한다(§5.5 확정 규격).
# 무보상 명예형이므로 **보상 열 자체가 없다**(D07 §7.1 — Source 신설 금지).
#
# **탭 = `category` 열 그대로다.** 발견형 4종은 카테고리가 아니라 조건 유형이므로
# (D07 §7.1 · 총괄 판정 IMPL-121 ②) 데이터의 `category` 가 라이벌로 교정됐고
# (IMPL-128 §5) 화면은 흡수 매핑 없이 1:1로 읽는다.
#
# 두 진입 경로를 지원한다(SYS-03 전례): 라우터 경유(타이틀 — payload.return 으로 복귀) /
# 오버레이 인스턴스(일시정지 위 — `closed` 시그널로 호출자가 회수).
class_name AchievementScreen
extends FlowScreen

signal closed

# 탭 = D07 §7.1 5카테고리 (데이터 `category` 값과 1:1).
const TABS := [
	{"key": "ui.achievement.tabCareer", "category": "career"},
	{"key": "ui.achievement.tabRival", "category": "rival"},
	{"key": "ui.achievement.tabDriving", "category": "driving"},
	{"key": "ui.achievement.tabGarage", "category": "garage"},
	{"key": "ui.achievement.tabArchive", "category": "archive"},
]

const ICON_DIR := "res://assets/ui/icons/"

# 항목 행 아이콘 (§A-4 "항목 행 = 아이콘·명칭·조건·달성 일시").
# **카테고리 1:1 이고 업적별 도상은 없다** — 대장이 A-UI-22~26 을 카테고리 이름으로 배정했다
# (`achv_career`=①커리어 … `achv_archive`=⑤아카이브). 즉 아이콘은 업적의 정체가 아니라
# 소속 축의 표지이므로, 39행이 5종을 나눠 쓰는 것이 규격대로다.
const ICON_BY_CATEGORY := {
	"career": "achv_career_16",
	"rival": "achv_rival_16",
	"driving": "achv_driving_16",
	"garage": "achv_garage_16",
	"archive": "achv_archive_16",
}

# 히든 미달성 공용 도상 (A-UI-27 — 대장 문면 "업적 히든 (미달성 공용)").
# **이것이 §5.5 '아이콘 비노출'을 어기지 않는 이유:** 은닉의 대상은 *그 업적의 정체*이고,
# 공용 도상은 39행 중 어느 것인지에 대해 아무것도 말하지 않는다(카테고리조차 가린다 —
# 카테고리 아이콘을 그대로 쓰면 탭 위치와 합쳐 후보가 좁혀지므로 그쪽이 오히려 누출이다).
# [가안] — §5.5 문면은 "아이콘 전부 비노출"이라 공용 도상도 비우는 독법이 가능하다.
# 대장이 이 도상에 "미달성 공용" 용도를 명시해 둔 쪽을 택했고, 총괄 판정으로 뒤집을 수 있다.
const ICON_HIDDEN := "achv_hidden_16"

# **16px 원도 세트 등배** (대장 §4.1.1 · IMPL-215). 9px 텍스트 행에 32px 를 얹으면 행이
# 3배로 벌어져 목록 밀도가 무너진다(7차 §6-③ 보고분) — 그 해소로 16px 원도가 유입됐다.
# 축소가 아니라 **원도 교체**다: 32px 를 줄이면 비정수 배율이 되어 믹셀이 된다(D10 §2.2 · D12 §9.1).
const ICON_SLOT := 16

var _return_route := "SYS-01"
var _overlay_mode := false
var _tab_panels: Array = []
var _active_tab := 0


func open_as_overlay(run_session: RunSession) -> void:
	_overlay_mode = true
	bind(run_session, {})


func _on_bound(payload: Dictionary) -> void:
	var s := session.data.strings
	_return_route = String(payload.get("return", "SYS-01"))
	var header_text := s.text("ui.achievement.header")
	(%HeaderLabel as Label).text = header_text
	var close := %CloseButton as Button
	close.text = s.text("ui.achievement.close")
	close.set_meta(AUDIO_EVENT_META, "ui_cancel")   # SE-U03 취소·닫기
	close.pressed.connect(_on_close)
	_refresh_summary()
	_refresh_link_notice()
	_build_tabs()
	_select_tab(0)
	_focus_initial()


# ── 패드 순회 폐쇄 (D09 §1.3 89행 · 총괄 판정 IMPL-176 ②) ──
#
# 포커스를 가진 노드가 없으면 패드로는 아무것도 고를 수 없다 — 화면이 잠긴다.
# **[가안] 초기 포커스 = 첫 탭 버튼.** §A-4 는 초기 포커스를 명시하지 않는다(§A-3 은 명시).
# 본문 §1.3 의 일반 규칙 "초기 포커스는 화면별 주 행동 버튼"을 적용하되, 이 화면의 행동은
# 탐색(탭 전환)과 닫기뿐이고 닫기를 첫 포커스로 두면 "열자마자 나가기"가 되므로 탭을 잡는다.
# §A-4 에 명시가 서면 그쪽을 따른다.
func _focus_initial() -> void:
	var tab_row := %TabRow as Control
	if tab_row.get_child_count() > 0:
		(tab_row.get_child(0) as Control).grab_focus()
		return
	(%CloseButton as Button).grab_focus()


# 취소 / 뒤로 = Esc · 우클릭 · **패드 B** (D09 §1.3 공통 층 매핑표 — 정본 명시).
# 닫기 버튼까지 포커스를 옮겨야만 나갈 수 있으면 그것도 순회 폐쇄 위반이다.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tab_prev"):
		get_viewport().set_input_as_handled()
		_cycle_tab(-1)
		return
	if event.is_action_pressed("tab_next"):
		get_viewport().set_input_as_handled()
		_cycle_tab(1)
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_on_close()

# ── 탭 순회 (D09 §1.3 '탭 전환 = Q·E | LB·RB' · 총괄 판정 IMPL-190 ②) ──
#
# 액션 청취를 **추가**한다 — 버튼 `pressed` 경로는 그대로다(마우스·포커스 조작 불변).
# 액션이 없으면 탭을 바꾸려고 탭 버튼까지 포커스를 옮겨야 하는데, 그러면 본문에서
# 나갔다 들어오는 왕복이 매번 생긴다.
#
# **[가안] 경계에서 감긴다(wrap)** — D09 는 순환 방향·경계에 침묵한다. 탭이 3~5개로 적고
# 끝에서 막히면 반대 방향 키를 다시 찾아야 하므로 감는 편이 조작 비용이 낮다고 봤다.
func _cycle_tab(step: int) -> void:
	if _tab_panels.is_empty():
		return
	_select_tab(wrapi(_active_tab + step, 0, _tab_panels.size()))


# 플랫폼 도전과제 미연동 고지 (D09 §6.5 필수 항목 — 업적 1:1 매핑).
#
# **화면은 어댑터도 플랫폼도 모른다** — 세션의 조회 창구 하나만 읽는다(혼입 0).
# 연동 상태는 달성 판정에 관여하지 않으므로(판정은 코어가 끝냈다) 고지는 **표기 전용**이고,
# 연동돼 있으면 아무것도 띄우지 않는다 — 정상 상태에 배지를 다는 것은 소음이다.
# 문면은 "기록은 유지된다"를 함께 말한다: 미연동을 손실로 오독하면 잘못된 불안을 준다. [가안]
func _refresh_link_notice() -> void:
	var notice := %LinkNotice as Label
	notice.visible = not session.achievement_service_linked()
	if not notice.visible:
		return
	notice.add_theme_font_size_override("font_size", _body_font_size)
	notice.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.text = session.data.strings.text("ui.achievement.serviceUnlinked")


# ── 무커리어 문맥 (SYS-01 → SYS-04 직행) ──
#
# **타이틀에서 바로 열리는 것이 규격이다** (D09 본문 145행·§A-1 — 총괄 판정 IMPL-176 ①).
# 그런데 `outgame` 은 `begin_career()` 에서만 생긴다 — 즉 커리어 미개시가 **정상 상태**이고
# 널은 예외가 아니다. 그래서 호출부마다 널 검사를 흩뿌리지 않고 조달 창구 하나로 닫는다:
# 진척은 `_progress_for()`, 달성 여부는 `_achieved()` 만 거친다. 창구가 하나면 새 소비부가
# 생겨도 같은 자리를 지나므로, 가드를 "기억해서 붙이는" 구조가 되지 않는다.
#
# **[가안] 무커리어 = 달성 0 표시.** 통산 업적 적재 층(플랫폼 도전과제 역방향 조회 —
# D12 §7.4 Steam 연동 결선 시 확정)이 서기 전까지의 잠정 표시 규칙이다. 그 층이 서면
# 커리어 없이도 "이 계정이 통산 달성한 것"을 보여줄 수 있고, 그때 이 규칙은 교체된다.
func _has_career() -> bool:
	return session != null and session.outgame != null


func _achieved(achievement_id: String) -> bool:
	return _has_career() and session.outgame.achievements.has(achievement_id)


# 진척 조회 — 무커리어에서도 **행이 서야 하므로** 형태가 같은 0 진척을 낸다.
# `threshold` 는 데이터에서 그대로 읽는다: 0 으로 뭉개면 "임계 2 이상만 진척 표기" 분기가
# 무커리어에서만 다르게 갈려, 커리어 유무로 목록의 모양이 바뀐다.
func _progress_for(achievement_id: String) -> Dictionary:
	if _has_career():
		return session.outgame.achievement_progress(achievement_id)
	var row: Dictionary = session.data.achievements[achievement_id]
	return {
		"current": 0,
		"threshold": CsvTable.to_int(String(row["threshold"])),
		"met": false,
		"pending": false,
		"season": 0,
	}


# 달성률 요약 헤더 (§A-4). 히든 미달성분도 분모에 든다 — 총수 가늠 허용이 §5.5 명문이다.
# 분모는 정적 데이터라 무커리어에서도 그대로 선다 — 목록 총수는 커리어와 무관한 사실이다.
func _refresh_summary() -> void:
	var total := session.data.achievements.size()
	var done := 0
	for achievement_id in session.data.achievements:
		if _achieved(String(achievement_id)):
			done += 1
	var percent := 0
	if total > 0:
		percent = int(round(float(done) * 100.0 / float(total)))
	var summary_text := session.data.strings.text("ui.achievement.summaryFormat", {
		"done": done,
		"total": total,
		"percent": percent,
	})
	(%SummaryLabel as Label).text = summary_text


func _build_tabs() -> void:
	var s := session.data.strings
	var tab_row := %TabRow as HBoxContainer
	var body := %TabBody as Control
	for index in range(TABS.size()):
		var tab: Dictionary = TABS[index]
		var button := Button.new()
		button.name = "Tab%d" % index
		button.text = s.text(String(tab["key"]))
		button.add_theme_font_size_override("font_size", _body_font_size)
		button.set_meta(AUDIO_EVENT_META, "ui_tab")   # SE-U04 — 결정음이 아니라 탭 전환음
		button.pressed.connect(_select_tab.bind(index))
		tab_row.add_child(button)

		# 라이벌 탭은 18행 — 캔버스 세로 360 에 들어가지 않으므로 탭마다 스크롤을 둔다.
		var scroll := ScrollContainer.new()
		scroll.name = "Scroll%d" % index
		scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
		scroll.visible = false
		body.add_child(scroll)

		var panel := VBoxContainer.new()
		panel.name = "Panel%d" % index
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_constant_override("separation", 2)
		scroll.add_child(panel)
		_tab_panels.append(scroll)

		for achievement_id in _ids_for(String(tab["category"])):
			panel.add_child(_build_row(String(achievement_id)))


# 항목 행 아이콘 1칸. **도상이 없어도 칸은 남긴다** — 폭이 사라지면 명칭 열이 밀려
# 행끼리 어긋나고, 그 어긋남은 "이 업적만 다르다"로 오독된다(§A-4 "자리만 존재"와 같은 취지).
#
# **달성/미달성으로 아이콘을 감광하지 않는다.** 상태는 표기 열(달성/미달성)과 명칭 색이
# 이미 지고 있고, 아이콘은 카테고리 표지라 상태 축이 아니다. 감광이 필요하다는 판단이 서면
# 그것은 배율 신설이므로 총괄 경유다(IMPL-195 감광 등채널 전례).
func _build_icon(asset_id: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(ICON_SLOT, ICON_SLOT)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	if asset_id.is_empty():
		return icon
	var path := "%s%s.png" % [ICON_DIR, asset_id]
	if not ResourceLoader.exists(path):
		# 진단 문자열은 영문 — 표시 문자열이 아니지만 V4 는 한글 리터럴을 경로 불문 차단한다
		push_error("AchievementScreen: icon asset missing - %s" % path)
		return icon
	icon.texture = load(path) as Texture2D
	return icon


# 탭에 드는 업적 id — 데이터 적재 순서를 따른다(D08 §8.11 열거 순 = CSV 행 순).
func _ids_for(category: String) -> Array:
	var ids: Array = []
	for achievement_id in session.data.achievements:
		if String(session.data.achievements[achievement_id]["category"]) == category:
			ids.append(String(achievement_id))
	return ids


func _build_row(achievement_id: String) -> Control:
	var s := session.data.strings
	var row_data: Dictionary = session.data.achievements[achievement_id]
	var progress: Dictionary = _progress_for(achievement_id)
	var met := bool(progress["met"])
	var hidden := CsvTable.to_int(String(row_data["hidden"])) == 1

	var row := HBoxContainer.new()
	row.name = achievement_id.to_pascal_case() + "Row"
	row.add_theme_constant_override("separation", 6)

	# 히든 미달성 = "???" 슬롯 (명칭·조건 비노출 · 아이콘은 공용 도상 — §5.5 · ICON_HIDDEN 주석)
	if hidden and not met:
		row.add_child(_build_icon(ICON_HIDDEN))
		var masked := Label.new()
		masked.name = "Masked"
		var masked_text := s.text("ui.achievement.hiddenSlot")
		masked.text = masked_text
		masked.add_theme_font_size_override("font_size", _body_font_size)
		masked.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		row.add_child(masked)
		return row

	row.add_child(_build_icon(String(ICON_BY_CATEGORY.get(String(row_data["category"]), ""))))

	var mark := Label.new()
	mark.name = "Mark"
	mark.custom_minimum_size = Vector2(44, 0)
	var mark_text := s.text("ui.achievement.markDone") if met else s.text("ui.achievement.markPending")
	mark.text = mark_text
	mark.add_theme_font_size_override("font_size", _body_font_size)
	mark.add_theme_color_override("font_color",
		UiPalette.TEXT_PRIMARY if met else UiPalette.TEXT_DIM)
	row.add_child(mark)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.custom_minimum_size = Vector2(190, 0)
	var name_text := s.text(String(row_data["name_key"]))
	name_label.text = name_text
	name_label.add_theme_font_size_override("font_size", _body_font_size)
	if not met:
		name_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	row.add_child(name_label)

	# 조건 축 — **임계가 2 이상인 축적형에만 진척을 적는다** [가안].
	# 임계 1 인 도달형은 명칭 자체가 조건 문면이라("첫 포디움") "0 / 1" 이 정보를 더하지 않는다.
	# 조건 전용 문면은 정본에 없다 — 별도 문안이 서면 이 자리에 든다.
	var progress_label := Label.new()
	progress_label.name = "Progress"
	progress_label.custom_minimum_size = Vector2(60, 0)
	var threshold := int(progress["threshold"])
	var progress_text := ""
	if threshold > 1:
		progress_text = s.text("ui.achievement.progressFormat", {
			"current": mini(int(progress["current"]), threshold),
			"threshold": threshold,
		})
	progress_label.text = progress_text
	progress_label.add_theme_font_size_override("font_size", _body_font_size)
	progress_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	row.add_child(progress_label)

	# 달성 일시 — 시각 축 = **인게임 시즌**(총괄 판정 IMPL-128 A-1 · §5.5 칭호 이력 `(시즌 N)` 전례).
	# 달성분인데 시즌이 없으면 구세이브 소급분이다 — 없는 값을 지어내지 않고 '—' 로 적는다.
	if met:
		var season_label := Label.new()
		season_label.name = "Season"
		var achieved_season := int(progress["season"])
		var season_text := s.text("ui.achievement.seasonUnknown")
		if achieved_season > 0:
			season_text = s.text("ui.achievement.seasonFormat", {"season": achieved_season})
		season_label.text = season_text
		season_label.add_theme_font_size_override("font_size", _body_font_size)
		season_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		row.add_child(season_label)
	return row


# 활성 탭 표시 — **[가안] 신설** (총괄 회신 §4-③ · 7차 §6-① 이월분).
#
# D09 는 활성 탭의 시각 표시에 침묵한다(§1.3 은 입력만, §A-3·§A-4 는 탭 구성만).
# 그런데 표시가 없으면 **LB/RB 가 먹지 않는 것처럼 보인다** — 마우스·키보드로는 눌린 탭에
# 포커스 링이 남아 우연히 활성 표시처럼 보이지만, 액션으로 돌리면 내용만 바뀌고
# 탭 줄에서는 아무것도 움직이지 않는다(7차 실측).
#
# **포커스와 활성은 다른 축이다** — 포커스는 "지금 어디를 조작하려는가", 활성은
# "지금 무엇을 보고 있는가"다. 그래서 포커스 링에 얹지 않고 색으로 따로 표시한다.
#
# 색은 **기확정 슬롯 2종**이다(신규 색 0): 활성 = `ACCENT_ACTIVE` C3(정본 증보 2 의
# '활성 강조' 역할) · 비활성 = `TEXT_PRIMARY` N16. **비활성을 감광하지 않는 이유** —
# 탭 5종은 전부 도달 가능하므로 흐리게 두면 잠긴 것으로 오독된다. 활성은 밝기가 아니라
# 색상으로 갈린다.
func _mark_active_tab() -> void:
	var tab_row := %TabRow as Control
	for index in range(tab_row.get_child_count()):
		var button := tab_row.get_child(index) as Button
		if button == null:
			continue
		button.add_theme_color_override("font_color",
			UiPalette.ACCENT_ACTIVE if index == _active_tab else UiPalette.TEXT_PRIMARY)
		# 포커스가 옮겨 가도 활성 표시는 유지돼야 한다 — 세 상태 전부 같은 색으로 고정한다.
		button.add_theme_color_override("font_hover_color",
			UiPalette.ACCENT_ACTIVE if index == _active_tab else UiPalette.TEXT_PRIMARY)
		button.add_theme_color_override("font_focus_color",
			UiPalette.ACCENT_ACTIVE if index == _active_tab else UiPalette.TEXT_PRIMARY)

func _select_tab(index: int) -> void:
	_active_tab = index
	for panel_index in range(_tab_panels.size()):
		(_tab_panels[panel_index] as Control).visible = panel_index == index
	_mark_active_tab()


func _on_close() -> void:
	if _overlay_mode:
		closed.emit()
		queue_free()
		return
	go(_return_route, {})
