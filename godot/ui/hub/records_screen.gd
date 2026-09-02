# HUB-05 기록실 — D09 §4.5 · 별첨A §A-15. 3탭: 라이벌 파일 / 통산 기록 / 아카이브.
#
# 라이벌 파일: 카드 = 초상(아트 유입 대상)·현재 관계 상태 명칭.
# **다음 전이 조건 비노출 (필수)** — 조건 힌트·진행 게이지류 일절 금지 (D09 §4.5).
# 축 비대상 라이벌은 관계 상태란 자체가 없다.
#
# 아카이브: **무상·상시 (절대 규격)** — 재화·시설·해금 게이트 표시 자체가 존재하지 않는다
# (P-1 ④ · D01 G2 조건 2). VN 재생 결선은 NAR-01 구현 후.
extends HubScreen

var _tabs: Dictionary = {}
var _active_tab := ""
# **재열람 페이로드를 얻지 못한 항목 id.** 아카이브에 실린 id 는 전부 되찾을 수 있어야
# 하므로(발화한 것만 실린다) 여기 값이 남으면 표와 발행 규칙이 갈렸다는 뜻이다.
# 사람에게는 `push_error`, 기계에는 이 배열이 관측 지점이다 (`vn_screen.choice_omissions` 전례).
var replay_omissions: Array = []


func _on_hub_ready(payload: Dictionary) -> void:
	var s := session.data.strings
	(%HeaderLabel as Label).text = s.text("ui.records.title")
	_tabs = {
		"rivals": {"button": %TabRivals, "panel": %PanelRivals},
		"career": {"button": %TabCareer, "panel": %PanelCareer},
		"archive": {"button": %TabArchive, "panel": %PanelArchive},
	}
	(%TabRivals as Button).text = s.text("ui.records.tabRivals")
	(%TabCareer as Button).text = s.text("ui.records.tabCareer")
	(%TabArchive as Button).text = s.text("ui.records.tabArchive")
	for tab_name in _tabs:
		var tab_button := _tabs[tab_name]["button"] as Button
		# 탭 전환음(SE-U04)은 결정음(SE-U02)과 다른 축이다 — 조작음 자동 결속이 이 메타를 읽어
		# 기본 결정음 대신 탭음을 붙인다. `_select_tab()` 은 진입 초기화에서도 불리므로
		# 거기서 울리면 화면에 들어서기만 해도 탭음이 난다.
		tab_button.set_meta(AUDIO_EVENT_META, "ui_tab")
		tab_button.pressed.connect(_select_tab.bind(String(tab_name)))
	_fill_rivals()
	_fill_career()
	_fill_archive()
	# 진입 탭은 페이로드가 정한다 (개선 2026-09-02 H9) — 재열람 복귀는 아카이브 탭으로
	# 돌아와야 한다(§A-19 "종료 시 아카이브 복귀"). 종전에는 항상 첫 탭이라 연속 재생마다
	# 라이벌 파일에서 아카이브까지 되걸어야 했다. 기본은 종전 그대로 첫 탭이다.
	var initial_tab := String(payload.get("tab", "rivals"))
	if not _tabs.has(initial_tab):
		initial_tab = "rivals"
	_select_tab(initial_tab)
	(_tabs[initial_tab]["button"] as Button).grab_focus()


func _select_tab(tab_name: String) -> void:
	_active_tab = tab_name
	for entry_name in _tabs:
		var active := String(entry_name) == tab_name
		(_tabs[entry_name]["panel"] as Control).visible = active
		# 활성 탭 색 표시 (개선 2026-09-02 H8) — 없으면 Q/E 순회가 내용만 바꿔 "안 먹는 것처럼"
		# 보인다. 문법·색 슬롯은 업적 화면 `_mark_active_tab` 그대로다(활성 = ACCENT_ACTIVE ·
		# 비활성 = TEXT_PRIMARY — 감광하면 잠긴 것으로 오독되므로 밝기가 아니라 색상으로 가른다).
		var tab_button := _tabs[entry_name]["button"] as Button
		tab_button.add_theme_color_override("font_color",
			UiPalette.ACCENT_ACTIVE if active else UiPalette.TEXT_PRIMARY)
		tab_button.add_theme_color_override("font_hover_color",
			UiPalette.ACCENT_ACTIVE if active else UiPalette.TEXT_PRIMARY)
		tab_button.add_theme_color_override("font_focus_color",
			UiPalette.ACCENT_ACTIVE if active else UiPalette.TEXT_PRIMARY)


# ── 탭 순회 (D09 §1.3 '탭 전환 = Q·E | LB·RB' · 총괄 판정 IMPL-190 ②) ──
#
# 액션 청취를 **추가**한다 — 버튼 `pressed` 경로는 그대로다(마우스·포커스 조작 불변).
# **[가안] 경계에서 감긴다(wrap)** — D09 는 순환 방향·경계에 침묵한다.
# 탭 순서는 `_tabs` 의 삽입 순서 = 화면의 탭 배치 순서다(별도 순서 배열을 두지 않는다).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tab_prev"):
		get_viewport().set_input_as_handled()
		_cycle_tab(-1)
		return
	if event.is_action_pressed("tab_next"):
		get_viewport().set_input_as_handled()
		_cycle_tab(1)
		return
	# 오버라이드가 공통 층(H7 — Esc/B 뒤로)을 삼키지 않게 나머지는 베이스로 넘긴다
	super(event)


func _cycle_tab(step: int) -> void:
	var names := _tabs.keys()
	if names.is_empty():
		return
	var at := names.find(_active_tab)
	if at < 0:
		at = 0
	_select_tab(String(names[wrapi(at + step, 0, names.size())]))
	# 순회 뒤 포커스 = 활성 탭 버튼 (개선 회차 4 O1). 아카이브 재생 버튼에 포커스를 둔 채 Q/E 를 누르면
	# 패널이 숨겨지며 포커스가 `none` 이 되어 패드 십자키가 죽는다 — 옵션·업적과 같은 손.
	(_tabs[_active_tab]["button"] as Button).grab_focus()


func _fill_rivals() -> void:
	var s := session.data.strings
	var list := %PanelRivals as VBoxContainer
	for rival_row in session.data.rivals:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", _body_font_size)
		name_label.custom_minimum_size = Vector2(110, 0)
		name_label.text = s.text(String(rival_row["name_key"]))
		row.add_child(name_label)
		# 관계 상태 — 축 대상 라이벌만. 상태 명칭만 표시하고 전이 조건·게이지는 절대 금지.
		var axis := _relation_axis_for(String(rival_row["id"]))
		if not axis.is_empty():
			var stage := session.outgame.relation_stage(axis)
			var axis_row: Dictionary = session.data.relation_axes[axis]
			# 단계 명칭 (개선 2026-09-03 R2) — 숫자 "0단계" 대신 D04 §4.2 의 상태 명칭을 보인다
			# (D07 §6.1 "상태 명칭은 D04 §4.2 정의 그대로"). 명칭 키는 표의 `stage{n}_key` 열이 쥔다 —
			# 조립한 키는 V6 가 못 보므로 참조를 표 열(string_key)에 둔다. 열이 비면 종전 숫자로 물러난다.
			var stage_key := String(axis_row.get("stage%d_key" % stage, ""))
			var stage_label := Label.new()
			stage_label.add_theme_font_size_override("font_size", _body_font_size)
			var relation_text := s.text("ui.records.relationFormat", {
				"axis": s.text(String(axis_row["name_key"])),
				"stage": s.text(stage_key) if not stage_key.is_empty() else str(stage),
			})
			stage_label.text = relation_text
			stage_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
			row.add_child(stage_label)
		list.add_child(row)


func _relation_axis_for(rival_id: String) -> String:
	for relation_id in session.data.relation_axes:
		if String(session.data.relation_axes[relation_id]["rival_id"]) == rival_id:
			return String(relation_id)
	return ""


func _fill_career() -> void:
	var s := session.data.strings
	var panel := %PanelCareer as VBoxContainer
	# 주행 데이터 생애 누적 획득 총량 상시 표시 (D06 R7) — 아이콘 동반 (B-1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var icon := TextureRect.new()
	icon.texture = load(ICON_DIR + "currency_data_16.png")
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)
	var total := Label.new()
	total.add_theme_font_size_override("font_size", _body_font_size)
	var total_text := s.text("ui.records.dpTotalFormat", {
		"amount": session.outgame.drive_data_earned_total,
	})
	total.text = total_text
	row.add_child(total)
	panel.add_child(row)
	# ── 통산 지표 (개선 2026-09-02 R1) — 소재는 코어가 이미 세던 career_stats 전용, 신규 판정 0.
	# 값이 0 이어도 행은 선다: 커리어 초반에 목록의 모양이 바뀌면 "생기는 기록"이 아니라
	# "빠졌던 행"으로 읽힌다(업적 화면 무커리어 0 진척 표기와 같은 취지).
	var stats := session.outgame
	_career_row(panel, "ui.records.statGps", _count_text(stats.career_stat("gps")))
	_career_row(panel, "ui.records.statFinishes", _count_text(stats.career_stat("finishes")))
	_career_row(panel, "ui.records.statWins", _count_text(stats.career_stat("wins")))
	_career_row(panel, "ui.records.statPodiums", _count_text(stats.career_stat("podiums")))
	_career_row(panel, "ui.records.statDuels", session.data.strings.text(
		"ui.records.duelRecordFormat",
		{"wins": stats.career_stat("duel_wins"), "total": stats.career_stat("duels")}))
	_career_row(panel, "ui.records.statTourWins", _count_text(stats.career_stat("tour_wins")))
	_career_row(panel, "ui.records.statSeasons", _count_text(stats.career_stat("seasons")))
	var best_rank := stats.career_stat("best_championship_rank")
	_career_row(panel, "ui.records.statBestRank",
		session.data.strings.text("ui.records.bestRankFormat", {"rank": best_rank})
		if best_rank > 0 else session.data.strings.text("ui.records.statNone"))
	_career_row(panel, "ui.records.statCircuits", _count_text(stats.career_stat("circuits_won")))


func _count_text(value: int) -> String:
	return session.data.strings.text("ui.records.statCountFormat", {"value": value})


func _career_row(panel: VBoxContainer, label_key: String, value_text: String) -> void:
	var s := session.data.strings
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", _body_font_size)
	label.custom_minimum_size = Vector2(150, 0)
	label.text = s.text(label_key)
	label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	row.add_child(label)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", _body_font_size)
	value.text = value_text
	row.add_child(value)
	panel.add_child(row)


func _fill_archive() -> void:
	var s := session.data.strings
	var panel := %PanelArchive as VBoxContainer
	# 게이트 표시 요소 전무 (무상·상시 — D01 G2 조건 2). 발생분 전량 등재 — 스킵분 동일 취급.
	# 미발생 이벤트는 목록 비표시 (스포일러 방지).
	var entries := session.narrative.archive_entries()
	if entries.is_empty():
		var empty := Label.new()
		empty.add_theme_font_size_override("font_size", _body_font_size)
		empty.text = s.text("ui.records.archiveEmpty")
		empty.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		panel.add_child(empty)
		return
	for vn_id in entries:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", _body_font_size)
		name_label.text = _vn_title(String(vn_id))
		name_label.custom_minimum_size = Vector2(140, 0)
		row.add_child(name_label)
		var replay := Button.new()
		replay.add_theme_font_size_override("font_size", _body_font_size)
		replay.text = s.text("ui.records.replay")
		# 재생 모드 — 동일 화면 + 종료 시 아카이브 복귀 (§A-19). 전이 재발화 없음(멱등).
		#
		# **페이로드는 세션 창구가 조립한다** (㊹ — 22차 개막 경로와 같은 교정). 화면이
		# 직접 `{vn_id, replay, next}` 를 쥐여 주던 동안 문면·화자·정조가 통째로 빠져
		# 골격 폴백 1줄이 떴다. 조립기를 화면에 두지 않는 규칙이 여기에도 걸린다.
		# 복귀 페이로드에 탭 힌트 — 재생 종료가 아카이브 탭으로 돌아온다 (H9 · §A-19)
		var replay_payload := session.archive_replay_payload(String(vn_id), "HUB-05",
			{"tab": "archive"})
		if replay_payload.is_empty():
			# **되찾지 못하면 누르게 두지 않는다.** 빈 페이로드로 보내면 골격 화면이 서서
			# 이번 결함이 그대로 재현된다 — 조용한 폴백 대신 죽은 버튼과 관측 지점을 남긴다.
			replay.disabled = true
			replay_omissions.append(String(vn_id))
			push_error("RecordsScreen: replay payload unresolved — '%s'" % String(vn_id))
		else:
			replay.pressed.connect(func(): go("NAR-01", replay_payload))
		row.add_child(replay)
		panel.add_child(row)


# [가안] VN 인스턴스 id → 표제: 실문안 대장(D04 트랙) 유입 전까지 슬롯 유형으로 표기
#
# 막 VN 표제는 T7 3차로 유입됐다(IMPL-278 — 16차 [인계] 회수분).
#
# **규칙(`"ui.vnSlot." + id.trim_prefix("vn_")`) 대신 리터럴 표를 쓴 것은 검사 때문이다.**
# V6 는 코드 리터럴·표의 `string_key` 열·구조 값에서 참조를 모으므로 **조립한 키는 보이지
# 않는다** — 실측: 규칙판으로 붙였을 때 6키가 여전히 고아 경고로 남았다. 소비부가 있는데
# 없다고 보고하는 상태를 남기면 그 경고는 다음 사람에게 잡음이 된다.
#
# 표가 낡는 위험(7번째 막이 조용히 폴백으로 떨어짐)은 **검사가 받는다** — UISCR 축이
# `act_vn` 전 항목이 이 표에 있는지 본다. 표와 규칙 중 하나를 고르는 대신, 표를 쓰고
# 누락을 기계가 잡게 했다.
const ACT_VN_TITLES := {
	"vn_act1": "ui.vnSlot.act1",
	"vn_act2": "ui.vnSlot.act2",
	"vn_act3": "ui.vnSlot.act3",
	"vn_act4": "ui.vnSlot.act4",
	"vn_origin": "ui.vnSlot.origin",
	"vn_epilogue": "ui.vnSlot.epilogue",
}


func _vn_title(vn_id: String) -> String:
	var s := session.data.strings
	if ACT_VN_TITLES.has(vn_id):
		return s.text(String(ACT_VN_TITLES[vn_id]))
	if not session.data.act_vn_entry(vn_id).is_empty():
		# 표에 없는 막 — 원문 id 를 그리지는 않는다(표제 부재보다 표제 오류가 나쁘다).
		return s.text("ui.vnSlot.tourBrief")
	# 비트 id 는 **슬롯 표에서 표제를 얻는다** — 리터럴 매핑을 두지 않는다.
	# 비트 행이 이미 `slot_id` 를 선언하고 `vn_slots.name_key` 가 그 슬롯의 표제이므로
	# 매핑을 손으로 적으면 같은 사실이 두 곳에 살고, 비트가 늘 때마다 한쪽이 밀린다
	# (막 VN 은 표에 슬롯이 없어 리터럴 표가 남아 있는 것이다 — 성격이 다르다).
	# `name_key` 는 `string_key` 열이라 V2·V6 이 참조를 이미 본다.
	var beat := session.data.vn_beat(vn_id)
	# **비트가 선언한 표제가 먼저다** (26차 · 세 번째 형태). 한 슬롯을 여러 비트가 공유하면
	# 슬롯 표제로는 갈리지 않는다 — 마일스톤 슬롯 하나에 8건이 선다.
	var declared_title := session.data.vn_beat_title_key(vn_id)
	if not declared_title.is_empty():
		return s.text(declared_title)
	var beat_slot := String(beat.get("slot_id", ""))
	# 공란 검사가 요건이다 — `vn_slot()` 은 미등재 슬롯에 `_load_ok = false` 를 세운다.
	# 표시 함수가 적재 상태를 떨어뜨리면 그 다음 `param()` 부터 조용한 0 이 나온다.
	if not beat_slot.is_empty():
		var slot := session.data.vn_slot(beat_slot)
		if not slot.is_empty():
			return s.text(String(slot["name_key"]))
	if vn_id.begins_with("vn_season_open"):
		return s.text("ui.vnSlot.seasonOpen")
	if vn_id.begins_with("vn_season_close"):
		return s.text("ui.vnSlot.seasonClose")
	if vn_id.begins_with("vn_tour_brief"):
		return s.text("ui.vnSlot.tourBrief")
	return vn_id
