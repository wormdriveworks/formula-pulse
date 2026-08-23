# AUDIO-W — 사운드 **호출 지점** 검사 (D11 §1.4 이벤트 결속의 화면 층 · 원격 인계 §4-3).
#
# AUDIO 스위트가 "표와 정책"을 보고, 여기서는 **표와 화면 사이의 공백**을 본다.
# 디스패처가 아무리 정확해도 부르는 쪽이 없으면 사운드 실물이 유입돼도 그 행은 영원히
# 울리지 않는다 — 그리고 무음 폴백 단계에서는 그 침묵이 정상 상태와 구분되지 않는다.
#
# 검사 축 4종:
#   ① 표 전수 대비 호출 지점 — 86행의 event_id 가 전부 (호출 / 파생 / 선언된 미결선) 중 하나
#   ② 역방향 — 화면이 부르는 이벤트 id 가 전부 표에 있다 (오타 = 영구 무음이라 기계로 잡는다)
#   ③ 파생 실증 — 무대 5종·베인 3단계·등급 3종의 파생 id 가 실제로 표 행에 닿는가
#   ④ 실주행 — RACE-01 을 실제로 세워 봉인 창과 발화를 관찰 (하네스 형)
#
# **미결선 대장(PENDING)이 이 검사의 핵심이다.** 부를 곳이 없는 행은 여기 이유와 함께
# 적어야 통과한다 — 목록에 없으면 실패하고, 목록에 있는데 실제로는 불리면 그것도 실패한다.
# 침묵이 조용히 늘어나는 경로를 없애는 장치다.
extends SceneTree

const SCENE_PATH := "res://ui/race/race_screen.tscn"
const MENU_SCENE_PATH := "res://ui/sys/title_screen.tscn"
const FIXTURE_DIR := "res://tests/fixtures/tables/"
const UI_DIR := "res://ui/"
const SPIN_ROUNDS := 6
const TIME_SCALE := 5.0
const WATCHDOG_MSEC := 120000

# 파생 호출 — 리터럴이 아니라 실행 시점에 만들어지는 이벤트 id. 소스 스캔으로 보이지 않으므로
# 여기 선언하되, **선언만으로는 결선의 증거가 되지 않는다**: 축 ③이 ①파생 결과가 실제 표 행에
# 닿는지와 ②선언한 파일에 그 서식이 `sfx()` 호출로 실재하는지를 함께 본다. 두 번째가 없으면
# 호출부를 지워도 선언이 남아 커버리지가 통과한다(대장이 코드를 대신 증언하는 구멍).
const DERIVED := [
	{"file": "res://ui/race/race_screen.gd", "form": "\"%s_enter\"", "what": "무대 BGM",
		"ids": ["stage_metro_night_enter", "stage_azure_coast_enter", "stage_alta_ridge_enter",
			"stage_mirage_flat_enter", "stage_pulse_dome_enter"]},
	{"file": "res://ui/race/race_screen.gd", "form": "\"vane_cue_stage%d\"", "what": "베인 큐음",
		"ids": ["vane_cue_stage1", "vane_cue_stage2", "vane_cue_stage3"]},
	{"file": "res://ui/nar/vn_screen.gd", "form": "\"vane_cue_stage%d\"", "what": "VN 베인 큐음",
		"ids": ["vane_cue_stage1", "vane_cue_stage2", "vane_cue_stage3"]},
	{"file": "res://ui/race/race_screen.gd", "form": "\"grade_%s\"", "what": "등급 스팅",
		"ids": ["grade_l1", "grade_l2", "grade_l3"]},
	{"file": "res://ui/nar/vn_screen.gd", "form": "\"vn_enter_%s\"", "what": "VN 트랙",
		"ids": ["vn_enter_calm", "vn_enter_tense"]},
	{"file": "res://ui/race/race_screen.gd", "form": "\"skill_%s\"", "what": "스킬 계열음",
		"ids": ["skill_hold", "skill_convert", "skill_amplify", "skill_insure"]},
]

const STAGE_BGM_ENTRY := 0   # DERIVED 중 무대 파생 항목 — 무대 전수 대조가 참조한다

# 미결선 대장 — **부를 곳이 아직 없는 이벤트와 그 이유.** 기능이 서면 여기서 빼고 결선한다.
const PENDING := {
	# **총괄 확정 = 미발화 유지** (IMPL-157 §1 · D11 종결 주석 = P-2 ㉚). 발주 목록에서는
	# 빼지 않는다 — 68식은 D11 확정 계수라 1식 제외가 정본 개정과 계수 연쇄를 부른다.
	# 발화 조건의 소관은 D05(정산 규칙)이므로 미래 개정이 무사건 턴을 만들면 되살아난다.
	"result_neutral": "무사건 확정 턴이 엔진에 없다 — 정산 ②가 트러블 부재 시 반드시 안정을"
		+ " 발행한다(섹터 턴 480건 전수 실측 0). 총괄 미발화 확정 · P-2 ㉚",
	"sell": "튜닝 재배분(환급) 경로 미결선 — HUB-03 골격이 구매만 연다",
	"crew_join": "크루 영입 스테이션(StRecruit) 미구현 — 라우트 자체가 빈 칸이다",
	# **스킬 계열음 4종은 13차에 결선됐다** — `skill_hold`·`skill_convert`·`skill_amplify`·
	# `skill_insure` 는 이 대장에서 빠지고 위 DERIVED 로 옮겼다(RACE-01 슬롯 렌더 + 투입).
	"duel_warning": "게이지 만충 임박 점멸 연출(D09 §3.4) 미결선 — 소리가 동기할 그림이 없다",
	"choice_shown": "VN 선택지 오버레이 미결선 (D04 문안 트랙 의존)",
	"true_ending_enter": "진엔딩 시퀀스(BGM-12) 미결선 — 전용 화면 부재",
	"epilogue_enter": "에필로그 계층(D05 §10.2 · BGM-13) 미결선 — 전용 화면 부재",
}

var _checked := 0
var _failures := 0
var _data: GameData
var _screen: Control
var _menu_screen: FlowScreen
var _round := 0
var _phase := "static"
var _settle := 0.0
var _done := false
var _started_msec := 0
var _seal_open_seen := false
var _seal_leaks := 0


func _initialize() -> void:
	_started_msec = Time.get_ticks_msec()
	_data = GameData.new()
	if not _data.load_all():
		_fail("데이터 적재 실패")
		_report()
		return
	var called := _scan_literal_calls()
	_coverage(called)
	_reverse(called)
	_derivations()
	_no_voice_jam()
	_haptic_ledger()
	Engine.time_scale = TIME_SCALE
	var menu_packed := load(MENU_SCENE_PATH) as PackedScene
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null or menu_packed == null:
		_fail("씬 로드 실패")
		_report()
		return
	# 메뉴 화면을 먼저 세워 조작음 결속을 확인하고, 그 뒤 레이스 화면으로 넘어간다.
	_menu_screen = menu_packed.instantiate() as FlowScreen
	root.add_child(_menu_screen)
	_screen = packed.instantiate()
	_phase = "menu"


# ── ⑤ 햅틱 값 창구 대장 (총괄 발주 IMPL-285 §2 — 결선 중단 사유의 기계화) ──
#
# **대장이 만료를 요구했고 만료했다.** 18차에 미충전 6항(강도 4 + micro·mid 지속 2)을 대장에
# 적어 두었고 D13 v1.11 §8.3(결정 #20)이 값을 충전했다 — 이 축은 그때 "충전되면 실패한다"로
# 세워졌고 실제로 그렇게 만료를 강제했다(미충전 계수 6 → 0).
#
# 여전히 두 방향을 잡는다:
#   · 표에 새 등급이 생기면 → 창구도 대장도 없으므로 실패
#   · 선언한 창구가 사라지면 → 실재 검사 실패
#
# `weak`·`strong` 지속이 `param_haptic_l1_sec`·`l2_sec` 인 것은 정본 명문이다
# ("weak·strong 지속은 위 L1/L2 항과 동일 값" — D13 v1.11). 값을 복제하지 않고 창구를 하나로 뒀다.
const HAPTIC_GRADES := ["none", "micro", "weak", "mid", "strong"]
const HAPTIC_PARAMS := {
	"none": {"strength": "-", "duration": "-"},      # 정의상 무진동 — 값이 필요 없다
	"micro": {"strength": "param_haptic_micro_amp", "duration": "param_haptic_micro_sec"},
	"weak": {"strength": "param_haptic_weak_amp", "duration": "param_haptic_l1_sec"},
	"mid": {"strength": "param_haptic_mid_amp", "duration": "param_haptic_mid_sec"},
	"strong": {"strength": "param_haptic_strong_amp", "duration": "param_haptic_l2_sec"},
}


func _haptic_ledger() -> void:
	var used: Dictionary = {}
	for event_id in _data.sound_map:
		for row in Array(_data.sound_map[event_id]):
			used[String(Dictionary(row).get("haptic", "none"))] = true
	# 표가 쓰는 등급이 전부 대장에 있는가 — 6번째 등급이 조용히 생기는 경로를 막는다.
	for grade in used:
		_ok("햅틱 등급 '%s' 대장 등재" % grade, HAPTIC_PARAMS.has(String(grade)), str(used.keys()))
	_ok("대장 등급 = enum 5단", HAPTIC_GRADES.size() == HAPTIC_PARAMS.size())
	# 창구가 선언된 항은 **실제로 실재해야** 한다(선언만 남고 키가 사라지는 경로 차단).
	var declared := 0
	var unfilled := 0
	for grade in HAPTIC_PARAMS:
		for axis in ["strength", "duration"]:
			var key := String(Dictionary(HAPTIC_PARAMS[grade])[axis])
			if key == "" :
				unfilled += 1
				continue
			if key == "-":
				continue
			declared += 1
			_ok("창구 '%s' 실재 (%s.%s)" % [key, grade, axis], _data.params.has(key), key)
	# **미충전 수가 계약이다.** 줄면 D13 이 충전된 것이므로 대장을 갱신해야 하고,
	# 늘면 창구가 사라진 것이므로 둘 다 여기서 걸린다.
	# **미충전 0 이 계약이다** — 되돌아가면(공란이 생기면) 결선이 부분적으로 죽는다.
	_ok("미충전 항 = 0 (D13 v1.11 충전 완료)", unfilled == 0, str(unfilled))
	_ok("충전 항 = 8 (등급 4 × 강도·지속)", declared == 8, str(declared))
	# 감쇠 배율은 실재한다 — O3 소비부가 서는 날 곱해질 값이다(D12 §10.4 곱 순서).
	_ok("감쇠 배율 창구 실재", _data.params.has("param_haptic_damp_ratio"))
	# **봉인 이해관계 실측** — 진동도 출력 경로이므로(불변규칙 5) 봉인 행에 실린 등급이
	# 실재하는지가 결선 지점 선택의 근거가 된다. 0건이면 봉인 논의가 공회전이다.
	var sealed_haptic := 0
	for event_id in _data.sound_map:
		for row in Array(_data.sound_map[event_id]):
			var entry: Dictionary = row
			if CsvTable.to_int(String(entry.get("seal_gated", "0"))) == 1 \
				and String(entry.get("haptic", "none")) != "none":
				sealed_haptic += 1
	_ok("봉인 행 × 비-none 햅틱 = 4건(결선 지점이 봉인 뒤여야 하는 근거)",
		sealed_haptic == 4, str(sealed_haptic))


# ── ① 표 전수 대비 호출 지점 ──
func _coverage(called: Dictionary) -> void:
	var derived := _derived_ids()
	var missing: Array[String] = []
	var stale: Array[String] = []
	for event_id in _data.sound_map:
		var id := String(event_id)
		var wired := called.has(id) or derived.has(id)
		if PENDING.has(id):
			if wired:
				stale.append(id)   # 결선해 놓고 대장에 남겨 두면 대장이 거짓말을 한다
			continue
		if not wired:
			missing.append(id)
	_ok("표의 전 이벤트가 호출·파생·선언 중 하나에 닿는다",
		missing.is_empty(), "미결선 미선언: %s" % ", ".join(missing))
	_ok("미결선 대장에 결선된 항목이 남아 있지 않다",
		stale.is_empty(), "대장 정리 필요: %s" % ", ".join(stale))
	# 대장 자체가 표에 없는 행을 가리키면(오타·행 삭제) 그것도 거짓말이다.
	var ghosts: Array[String] = []
	for event_id in PENDING:
		if not _data.sound_map.has(String(event_id)):
			ghosts.append(String(event_id))
	_ok("미결선 대장의 이벤트가 전부 표에 실재한다",
		ghosts.is_empty(), "표에 없는 id: %s" % ", ".join(ghosts))


# ── ② 역방향 (오타 = 영구 무음) ──
#
# 넓은 스캔은 커버리지용이라 역방향에 쓸 수 없다(딕셔너리 키까지 걸린다). 여기서는
# **발화 위치의 리터럴만** 본다 — `sfx(...)` 행과 조작음 메타 지정 행.
# 상수 표(`SOUND_BY_KEY`)는 정규식 대신 스크립트 상수를 직접 읽어 정확히 대조한다.
func _reverse(_called: Dictionary) -> void:
	var unknown: Array[String] = []
	_scan_dir_narrow(UI_DIR, unknown)
	_ok("발화 지점의 이벤트 id 가 전부 표에 있다",
		unknown.is_empty(), "표 밖 호출: %s" % ", ".join(unknown))
	var script := load("res://ui/race/race_screen.gd") as GDScript
	var constants := script.get_script_constant_map()
	_ok("RACE-01 이 로그 키 → 사운드 대응표를 보유", constants.has("SOUND_BY_KEY"))
	if not constants.has("SOUND_BY_KEY"):
		return
	var table: Dictionary = constants["SOUND_BY_KEY"]
	var bad: Array[String] = []
	for log_key in table:
		if not _data.sound_map.has(String(table[log_key])):
			bad.append("%s→%s" % [String(log_key), String(table[log_key])])
	_ok("대응표의 사운드 이벤트가 전부 표에 있다 (%d행)" % table.size(),
		bad.is_empty(), "표 밖: %s" % ", ".join(bad))
	# 등재된 로그 키가 실제로 엔진이 발행하는 키인지도 본다 — 오타 난 키는 영원히 안 맞는다.
	var engine_keys := _engine_log_keys()
	var ghosts: Array[String] = []
	for log_key in table:
		if not engine_keys.has(String(log_key)):
			ghosts.append(String(log_key))
	_ok("대응표의 로그 키가 전부 엔진 발행분이다",
		ghosts.is_empty(), "엔진에 없는 키: %s" % ", ".join(ghosts))


func _engine_log_keys() -> Dictionary:
	var keys: Dictionary = {}
	var file := FileAccess.open("res://core/state/race_engine.gd", FileAccess.READ)
	if file == null:
		_fail("엔진 소스 열기 실패 — 로그 키 대조 불가")
		return keys
	var regex := RegEx.new()
	regex.compile("\"(raceLog\\.[A-Za-z0-9]+)\"")
	for found_match in regex.search_all(file.get_as_text()):
		keys[found_match.get_string(1)] = true
	return keys


func _scan_dir_narrow(dir_path: String, unknown: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + entry
		if dir.current_is_dir():
			_scan_dir_narrow(full + "/", unknown)
		elif entry.ends_with(".gd"):
			_scan_file_narrow(full, unknown)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_file_narrow(path: String, unknown: Array[String]) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var literal := RegEx.new()
	literal.compile("\"([a-z0-9_]*)\"")
	for raw_line in file.get_as_text().split("\n"):
		var line := _strip_comment(String(raw_line))
		if not (line.contains("sfx(") or line.contains("AUDIO_EVENT_META")):
			continue
		# 서식 파생 호출(`sfx("%s_enter" % ...)`)의 리터럴은 이벤트 id 가 아니다 —
		# 파생분은 DERIVED 선언과 축 ③ 이 따로 검증한다. 메타 상수 선언 자체도 제외.
		if line.contains("%") or line.contains("const AUDIO_EVENT_META"):
			continue
		for found_match in literal.search_all(line):
			var event_id := found_match.get_string(1)
			# 빈 문자열 = "일반 조작음 없음" 지정이며 표 대조 대상이 아니다.
			if event_id.is_empty() or _data.sound_map.has(event_id):
				continue
			unknown.append("%s (%s)" % [event_id, path.get_file()])


# ── ③ 파생 실증 ──
func _derivations() -> void:
	for entry in DERIVED:
		var unresolved: Array[String] = []
		for event_id in entry["ids"]:
			if not _data.sound_map.has(String(event_id)):
				unresolved.append(String(event_id))
		_ok("파생 id 가 표 행에 닿는다 — %s (%s)" % [String(entry["what"]), String(entry["form"])],
			unresolved.is_empty(), "미해결: %s" % ", ".join(unresolved))
		_ok("파생 호출이 소스에 실재한다 — %s (%s)"
			% [String(entry["what"]), String(entry["file"]).get_file()],
			_has_sfx_form(String(entry["file"]), String(entry["form"])))
	# 무대 파생은 적재된 무대 목록이 정본이다 — 무대가 늘면 이 검사가 먼저 걸린다.
	var declared: Array = DERIVED[STAGE_BGM_ENTRY]["ids"]
	var uncovered: Array[String] = []
	for stage_id in _data.stages:
		if not declared.has("%s_enter" % String(stage_id)):
			uncovered.append(String(stage_id))
	_ok("적재된 전 무대가 BGM 파생 대상이다",
		uncovered.is_empty() and _data.stages.size() > 0,
		"무대 %d종 · 누락 %s" % [_data.stages.size(), ", ".join(uncovered)])


# ── 보이스 점유 회귀 (IMPL-149) ──
# 표현 층이 스트림 종료를 알리지 않으면 점유가 영구 누적돼 **정보음이 장식음을 영구 억제**하고
# (P1 보호가 안 풀린다) 상한 포화 뒤에는 섀시 경고까지 거부된다. 실측으로 3시간짜리
# 사고를 낸 적은 없지만, 무음 단계에서는 이 고장이 정상 침묵과 구분되지 않아 조용히 산다.
func _no_voice_jam() -> void:
	var session := RunSession.new()
	session.setup(_data)
	_ok("세션이 디스패처를 배선한다", session.audio != null)
	if session.audio == null:
		return
	_growth_gate_latch(session)
	session.audio.emit("timer_enter_warning")   # P1
	_ok("P1 발화 후에도 P3 가 울린다 (보호가 풀린다)",
		not session.audio.emit("ui_cursor").is_empty())
	var cap := _data.param_int("param_audio_virtual_channels")
	for i in range(cap * 3):
		session.audio.clock_override_msec = 1000 * (i + 1)   # 재트리거 게이트 회피
		session.audio.emit("rank_stamp")
	_ok("반복 발화가 채널을 잠그지 않는다",
		session.audio.active_voice_count() < cap,
		"점유=%d 상한=%d" % [session.audio.active_voice_count(), cap])
	session.audio.clock_override_msec = 9999999
	_ok("포화 시도 후에도 P1 경고가 발화한다",
		not session.audio.emit("chassis_warning").is_empty())


# 조작음은 버튼마다 손으로 걸지 않고 `bind()` 가 일괄 결속한다 — 그 결속이 꺼지면
# 커서·결정·취소·토글이 **전 화면에서 동시에** 사라지는데, 소스에는 리터럴이 그대로 남아
# 커버리지 검사가 통과한다(돌연변이 ⑱ 미검출로 실측). 실제로 신호를 때려 확인한다.
# 성장 게이트 개방음(SE-U13)은 "방금 열린 스킬 티어"가 있을 때만 난다. 그 판정은 경계
# 전후 스냅숏 대조인데, 스냅숏이 조용히 비면 **개방음이 영영 안 울리고도 검사가 통과**한다
# (실주행에서 `data.skills` 딕셔너리를 키로 순회하는 결함이 실제로 났다).
func _growth_gate_latch(session: RunSession) -> void:
	session.begin_career(1)
	var snapshot: Dictionary = session._tier_open_snapshot()
	_ok("스킬 티어 스냅숏이 전 티어를 담는다", snapshot.size() >= 3,
		"티어 %d종: %s" % [snapshot.size(), str(snapshot.keys())])
	_ok("티어 1은 시작 개방·2는 미개방으로 잡힌다",
		bool(snapshot.get(1, false)) and not bool(snapshot.get(2, true)), str(snapshot))
	# 첫 포디움 마일스톤이 서면 티어 2가 '방금 열린 것'으로 걸려야 한다.
	session.outgame.milestones["milestone_first_podium"] = true
	session._latch_opened_tiers(snapshot)
	_ok("새로 열린 티어가 래치에 잡힌다", session.newly_opened_tiers.has(2),
		"래치: %s" % str(session.newly_opened_tiers))


# **`bind()` 는 첫 `_process` 프레임에서 부른다** — `_initialize()` 안의 add_child 직후에
# 부르면 `@onready` 가 아직 비어 있어 화면이 자기 노드를 못 찾는다(기록된 하네스 함정).
func _menu_controls_bound() -> void:
	var session := RunSession.new()   # 재트리거 게이트가 겹치지 않게 전용 세션을 쓴다
	session.setup(_data)
	_menu_screen.session = session
	_menu_screen.bind(session, {})
	var button := _menu_screen.get_node_or_null("%OptionsButton") as Button
	if button == null:
		_fail("타이틀 버튼 부재 — 조작음 결속 확인 불가")
		return
	session.audio.fired.clear()
	button.focus_entered.emit()
	_ok("메뉴 버튼 포커스가 커서음(SE-U01)을 낸다",
		_as_strings(session.audio.fired).has("SE-U01"),
		"발화: %s" % ", ".join(_as_strings(session.audio.fired)))
	session.audio.fired.clear()
	button.pressed.emit()   # 핸들러는 `go()` 로 전이를 요청만 한다 — 라우터가 없으므로 무해
	_ok("메뉴 버튼 입력이 결정음(SE-U02)을 낸다",
		_as_strings(session.audio.fired).has("SE-U02"),
		"발화: %s" % ", ".join(_as_strings(session.audio.fired)))
	session.audio.fired.clear()
	root.remove_child(_menu_screen)
	_menu_screen.queue_free()
	_menu_screen = null


# ── ④ 실주행 하네스 ──
func _process(delta: float) -> bool:
	if _done:
		return true
	if Time.get_ticks_msec() - _started_msec > WATCHDOG_MSEC:
		_fail("하네스 예산 초과 %dms (round=%d phase=%s)" % [WATCHDOG_MSEC, _round, _phase])
		_report()
		return true
	# 초기화가 중단됐으면 상주하지 않고 나간다 (IMPL-146 하네스 탈출 규약).
	if _screen == null:
		_fail("화면 인스턴스 부재 — 초기화 중단")
		_report()
		return true
	if _phase == "menu":
		_menu_controls_bound()
		root.add_child(_screen)   # 레이스 화면은 여기서 세운다 — `_ready()` 는 다음 프레임
		_phase = "idle"
		return false
	var audio: AudioDispatcher = _screen.session.audio
	match _phase:
		"idle":
			if _screen._revealing or _screen.engine.turn_phase != RaceTypes.TurnPhase.T1_SECTOR_OPEN:
				return false
			if _round == 0:
				_assert_gp_open(audio)
				_assert_chassis_threshold()
			audio.fired.clear()
			_seal_open_seen = false
			_seal_leaks = 0
			_screen._on_primary_action()   # 스핀 = T2 커밋
			_phase = "revealing"
		"revealing":
			# 봉인은 **정지 연출이 도는 동안** 열려 있어야 한다. 열리지 않았다면
			# 결과 상관 사운드가 연출 중에 지나갈 수 있다는 뜻이다.
			if _screen._revealing:
				if audio.seal_open():
					_seal_open_seen = true
				else:
					_seal_leaks += 1
				return false
			_ok("정지 연출 중 봉인 개방 (라운드 %d)" % _round, _seal_open_seen and _seal_leaks == 0,
				"열린 프레임 %s · 닫힌 프레임 %d" % [_seal_open_seen, _seal_leaks])
			_ok("정지 연출 종료 시 봉인 해제 (라운드 %d)" % _round, not audio.seal_open())
			_assert_spin_sounds(audio)
			_phase = "open"
			_settle = 0.0
		"open":
			_settle += delta
			if _settle < 0.1:
				return false
			audio.fired.clear()
			# 확정이 끝나면 엔진은 다음 턴으로 넘어가 있다 — 듀얼 여부는 **미리** 잡는다.
			var was_duel: bool = _screen.engine.current_turn_is_duel
			_screen._confirm_lockout = 0.0
			_screen._on_primary_action()   # 확정
			# 섹터 턴은 결과 6종 중 하나(정산 ②가 안정 또는 트러블을 반드시 낸다),
			# 듀얼 턴은 결판 2종 중 하나. 어느 쪽도 없으면 그 턴은 소리 없이 지나간 것이다.
			var expected: Array = DUEL_SFX if was_duel else RESULT_SFX
			_ok("확정이 %s 계열을 낸다 (라운드 %d)" % ["결판" if was_duel else "결과", _round],
				_fired_any(audio, expected), "발화: %s" % ", ".join(_as_strings(audio.fired)))
			_round += 1
			if _round >= SPIN_ROUNDS or _screen.engine.finished:
				_report()
				return true
			_phase = "idle"
	return false


func _assert_gp_open(audio: AudioDispatcher) -> void:
	var fired := _as_strings(audio.fired)
	# 무대 BGM 은 트랙 id 로 기록된다 — 어느 무대든 BGM- 접두다(D11 §4.1 5종 1:1).
	var has_bgm := false
	for sound_id in fired:
		if sound_id.begins_with("BGM-"):
			has_bgm = true
	_ok("GP 개시에 무대 BGM 이 든다", has_bgm, "발화: %s" % ", ".join(fired))
	_ok("GP 개시 시그널(SE-U18)", fired.has("SE-U18"), "발화: %s" % ", ".join(fired))
	_ok("관중 베드(AMB-01)", fired.has("AMB-01"), "발화: %s" % ", ".join(fired))


# SE-D06 섀시 경고는 위험 임계 **진입 시 1회** 울린다. 임계는 D13 v1.6 §8.1 확정값이고
# **데이터 경유**여야 한다 — 코드에 비율이 남으면 값 창구 밖에서 거동이 정해지고, 기본
# 데이터로만 보면 그 결함이 보이지 않는다. 픽스처로 갈아 끼워 거동이 따라오는지 본다.
func _assert_chassis_threshold() -> void:
	var fixture := GameData.new()
	fixture.tables_override_dir = FIXTURE_DIR
	if not fixture.load_all():
		_fail("픽스처 적재 실패 — 섀시 임계 값 출처 확인 불가")
		return
	var default_line := _data.param("param_chassis_max") * _data.param("param_chassis_warn_ratio")
	var fixture_line := fixture.param("param_chassis_max") * fixture.param("param_chassis_warn_ratio")
	_ok("픽스처가 더 높은 임계를 담는다", fixture_line > default_line + 1.0,
		"fixture=%.1f default=%.1f" % [fixture_line, default_line])
	var saved_data: GameData = _screen.data
	var saved_chassis: float = _screen.engine.chassis
	# 두 임계 사이의 섀시 — 어느 데이터를 보는지가 여기서 갈린다.
	_screen.engine.chassis = (default_line + fixture_line) * 0.5
	_ok("기본 데이터에서는 임계 밖", not _screen._chassis_critical(),
		"chassis=%.1f line=%.1f" % [_screen.engine.chassis, default_line])
	_screen.data = fixture
	_ok("픽스처 데이터에서는 임계 안 — 임계가 데이터 경유다", _screen._chassis_critical(),
		"chassis=%.1f line=%.1f" % [_screen.engine.chassis, fixture_line])
	_screen.data = saved_data
	_screen.engine.chassis = saved_chassis


func _assert_spin_sounds(audio: AudioDispatcher) -> void:
	var fired := _as_strings(audio.fired)
	_ok("스핀 개시음(SE-R01) — 라운드 %d" % _round, fired.has("SE-R01"),
		"발화: %s" % ", ".join(fired))
	_ok("릴 정지음(SE-R03) — 라운드 %d" % _round, fired.has("SE-R03"),
		"발화: %s" % ", ".join(fired))
	_ok("개입 창 오픈음(SE-I01) — 라운드 %d" % _round, fired.has("SE-I01"),
		"발화: %s" % ", ".join(fired))
	# 베인 콜아웃 갱신에 큐음이 붙는다 — 파생 호출(단계 연동)의 실주행 증거다.
	_ok("베인 큐음(SE-V01a) — 라운드 %d" % _round, fired.has("SE-V01a"),
		"발화: %s" % ", ".join(fired))
	# 매치 고지음(R-a)은 정지 완료 **후**에만 존재할 수 있다. 매치 성립 여부는 난수라
	# 조건부로 세면 검사 수가 라운드마다 흔들린다 — 라운드당 1건으로 고정한다(SEAL-E 전례).
	var gated_ok := true
	for gated in ["SE-R04", "SE-R05"]:
		if fired.has(gated) and audio.seal_open():
			gated_ok = false
	_ok("매치 고지음은 봉인 해제 후에만 있다 — 라운드 %d" % _round, gated_ok)


const RESULT_SFX := ["SE-E01", "SE-E02", "SE-E03", "SE-E04", "SE-E06"]
const DUEL_SFX := ["SE-D04", "SE-D05"]


func _fired_any(audio: AudioDispatcher, wanted: Array) -> bool:
	for sound_id in _as_strings(audio.fired):
		if wanted.has(sound_id):
			return true
	return false


# ── 소스 스캔 ──
# 화면 층 소스의 **문자열 리터럴 전량**을 뜬다. `sfx("...")` 형태만 보면 삼항식·상수 표·
# 메타 지정·진입 목록 같은 실제 결선 형태를 전부 놓친다(실측: 86행 중 25행 오검출).
# 잡으려는 고장은 "표에 있는데 화면 어디에서도 **이름조차 나오지 않는 행**"이므로
# 리터럴 등장 여부로 충분하다 — 대장을 손으로 적으면 코드와 갈라진다.
# 주석은 걷어낸다: 주석에 적힌 id 가 결선의 증거로 둔갑하면 안 된다.
func _scan_literal_calls() -> Dictionary:
	var found: Dictionary = {}
	_scan_dir(UI_DIR, found)
	return found


func _scan_dir(dir_path: String, found: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path + entry
		if dir.current_is_dir():
			_scan_dir(full + "/", found)
		elif entry.ends_with(".gd"):
			_scan_file(full, found)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_file(path: String, found: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var name_only := path.get_file()
	# 딕셔너리 키(`"x":`)는 제외한다 — 우연히 이름이 같은 키가 '결선했다'는 증거로 둔갑한다.
	var regex := RegEx.new()
	regex.compile("\"([a-z0-9_]+)\"(?!\\s*:)")
	for line in file.get_as_text().split("\n"):
		for found_match in regex.search_all(_strip_comment(String(line))):
			found[found_match.get_string(1)] = name_only


# 따옴표 밖의 첫 `#` 부터가 주석이다 (문자열 안의 `#` 를 주석 시작으로 오인하지 않는다).
func _strip_comment(line: String) -> String:
	var in_quote := false
	for index in range(line.length()):
		var glyph := line[index]
		if glyph == "\"":
			in_quote = not in_quote
		elif glyph == "#" and not in_quote:
			return line.substr(0, index)
	return line


func _derived_ids() -> Dictionary:
	var ids: Dictionary = {}
	for entry in DERIVED:
		for event_id in entry["ids"]:
			ids[String(event_id)] = String(entry["what"])
	return ids


# 선언한 서식이 그 파일에서 실제로 `sfx()` 인자로 쓰이는가 (주석 속 언급은 증거가 아니다).
func _has_sfx_form(path: String, form: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	for raw_line in file.get_as_text().split("\n"):
		var line := _strip_comment(String(raw_line))
		if line.contains("sfx(") and line.contains(form):
			return true
	return false


func _as_strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(String(value))
	return out


# ── 판정 ──
func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if condition:
		return
	_failures += 1
	print("  [FAIL] %s%s" % [label, (" — " + detail) if detail != "" else ""])


func _fail(label: String) -> void:
	_checked += 1
	_failures += 1
	print("  [FAIL] %s" % label)


func _report() -> void:
	_done = true
	Engine.time_scale = 1.0
	if _failures == 0:
		print("AUDIO_WIRING_PASS checks=%d rounds=%d" % [_checked, _round])
		quit(0)
	else:
		print("AUDIO_WIRING_FAIL checks=%d failures=%d" % [_checked, _failures])
		quit(1)
