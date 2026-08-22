# AUDIO — 오디오 디스패처·이벤트 결속 검사 (D12 §5.10·§10 · D11 §1.4·§2.11·§6.3).
#
# 축 4종:
#   ① 표 전수 대조 — D11 §2.11 집계(68식)·§4.1 트랙(13+징글 5)과 데이터가 어긋나면 실패
#   ② 이벤트 결속 — 턴 시퀀스 T1~T6·무대 5종 공백 0 (D11 §2.11 커버리지 명문)
#   ③ 정책 4종 — 봉인 / 재트리거 게이트 / 채널 상한·컬링 / P1 보호
#   ④ 값 출처 — 픽스처로 core_params 를 갈아 끼웠을 때 거동이 따라오는가
#      (따라오지 않으면 코드가 데이터 대신 현재 값과 같은 리터럴을 쓰고 있다는 뜻이다)
#
# 봉인 축은 SEAL 계열의 오디오 측 대응이다 — SEAL-E 가 화면 표면을 보고, 여기가 발화 경로를 본다.
extends SceneTree

const FIXTURE_DIR := "res://tests/fixtures/tables/"

# D11 §2.11 군별 식수 (확정 — 헤딩이 아니라 열거가 정본. U=19는 SE-U18/U19 병합 셀 실측분)
const GROUP_COUNTS := {"SE-R": 5, "SE-I": 14, "SE-T": 3, "SE-E": 6, "SE-L": 3,
	"SE-RS": 1, "SE-D": 7, "SE-U": 19, "SE-V": 5, "AMB-": 5}

var _checked := 0
var _failures := 0


func _init() -> void:
	_table_census()
	_event_binding()
	_seal_rule()
	_retrigger_gate()
	_channel_cap_and_culling()
	_p1_protection()
	_bgm_transitions()
	_ducking()
	_silent_fallback()
	_values_come_from_data()
	_haptic_wiring()
	print("")
	# 검사 수 하한 — 스위트가 쪼그라들면 "통과"가 아니다.
	if _checked < 90:
		print("AUDIO_TEST_FAIL checks=%d < 하한 90 (스위트 축소·로드 실패 의심)" % _checked)
		quit(1)
		return
	if _failures == 0:
		print("AUDIO_TEST_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("AUDIO_TEST_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if condition:
		return
	_failures += 1
	print("  [FAIL] %s%s" % [label, (" — " + detail) if detail != "" else ""])


func _eq(label: String, actual: float, expected: float, tolerance: float = 0.0001) -> void:
	_ok(label, absf(actual - expected) <= tolerance,
		"actual=%f expected=%f" % [actual, expected])


func _new_data(override_dir: String = "") -> GameData:
	var data := GameData.new()
	if override_dir != "":
		data.tables_override_dir = override_dir
	if not data.load_all():
		_failures += 1
		print("  [FAIL] data load (override=%s)" % override_dir)
		return null
	return data


func _new_dispatcher(data: GameData, output: AudioOutput = null) -> AudioDispatcher:
	var dispatcher := AudioDispatcher.new()
	dispatcher.setup(data, output)
	dispatcher.clock_override_msec = 0   # 시간 축 정책을 결정적으로 검사하기 위한 고정 시계
	return dispatcher


# ── ① 표 전수 대조 ──
func _table_census() -> void:
	var data := _new_data()
	if data == null:
		return
	var by_channel := {"sfx": 0, "bgm": 0, "jingle": 0}
	var sfx_ids: Dictionary = {}
	var groups: Dictionary = {}
	for row_id in data.sound_rows:
		var row: Dictionary = data.sound_rows[row_id]
		var channel := String(row["channel"])
		_ok("채널 값이 3계 안에 있다: %s" % row_id, by_channel.has(channel), channel)
		if by_channel.has(channel):
			by_channel[channel] += 1
		var sfx_id := String(row["sfx_id"])
		_ok("사운드 id 유일: %s" % sfx_id, not sfx_ids.has(sfx_id))
		sfx_ids[sfx_id] = true
		# 긴 접두부터 본다 — 'SE-R'은 'SE-RS1'의 접두이기도 하다 (짧은 쪽을 먼저 물면 오분류).
		var prefixes: Array = GROUP_COUNTS.keys()
		prefixes.sort_custom(func(a, b): return String(a).length() > String(b).length())
		for prefix in prefixes:
			if sfx_id.begins_with(String(prefix)):
				groups[prefix] = int(groups.get(prefix, 0)) + 1
				break
	# D11 §2.11 총계 68식 = SFX 소계 63 + 앰비언스 5. SFX 버스 귀속이 곧 채널 'sfx'다.
	_ok("D11 §2.11 총계 68식", by_channel["sfx"] == 68, "actual=%d" % by_channel["sfx"])
	# D11 §4.1 — 13트랙 (예비 1은 미배정 확정이라 행이 없다) + 징글 5식
	_ok("D11 §4.1 BGM 13트랙", by_channel["bgm"] == 13, "actual=%d" % by_channel["bgm"])
	_ok("D11 §4.1 징글 5식", by_channel["jingle"] == 5, "actual=%d" % by_channel["jingle"])
	for prefix in GROUP_COUNTS:
		_ok("D11 §2.11 %s군 %d식" % [prefix, int(GROUP_COUNTS[prefix])],
			int(groups.get(prefix, 0)) == int(GROUP_COUNTS[prefix]),
			"actual=%d" % int(groups.get(prefix, 0)))
	# 우선순위·햅틱·봉인 플래그의 값역
	for row_id2 in data.sound_rows:
		var row2: Dictionary = data.sound_rows[row_id2]
		_ok("우선순위 P1~P3: %s" % row_id2, ["P1", "P2", "P3"].has(String(row2["priority"])),
			String(row2["priority"]))


# ── ② 이벤트 결속 (D11 §1.4 · §2.11 커버리지) ──
func _event_binding() -> void:
	var data := _new_data()
	if data == null:
		return
	# 턴 시퀀스 T1~T6 공백 0 — D11 §2.11 명문의 매핑을 그대로 검사한다.
	var turn_events := {
		"T1 브리핑·레조넌스 공표": ["vane_cue_stage1", "resonance_announce"],
		"T2~T3 스핀·정지": ["reel_spin_start", "reel_stop"],
		"T4 개입": ["intervention_open", "timer_enter_warning"],
		"T5 번역": ["result_advance", "grade_l1"],
		"T6 정산": ["duel_enter", "rank_stamp"],
	}
	for phase in turn_events:
		for event_id in turn_events[phase]:
			_ok("%s — 이벤트 결속 실재: %s" % [phase, event_id],
				not data.sounds_for(String(event_id)).is_empty())
	# 무대 5종 전부 BGM 행을 갖는다 (D11 §4.2 — 무대 개성은 BGM 전담).
	# 무대 목록을 손으로 적지 않는다: 매니페스트에서 끌어와야 무대가 늘 때 같이 걸린다.
	var stage_ids: Variant = data.manifest.get("stages", [])
	_ok("무대 매니페스트 5종", typeof(stage_ids) == TYPE_ARRAY and Array(stage_ids).size() == 5,
		str(stage_ids))
	if typeof(stage_ids) == TYPE_ARRAY:
		for stage_id in Array(stage_ids):
			var event_id2 := "%s_enter" % String(stage_id)
			var bound := data.sounds_for(event_id2)
			var has_bgm := false
			for row in bound:
				if String(row["channel"]) == AudioDispatcher.CHANNEL_BGM:
					has_bgm = true
			_ok("무대 BGM 결속: %s" % event_id2, has_bgm, str(bound))
	# GP 종료는 SFX + 앰비언스 함성이 함께 걸린다 (D11 §2.8 SC-09 — 한 이벤트·복수 사운드)
	var finish := data.sounds_for("gp_finish")
	_ok("GP 종료 = SE-U19 + AMB-03", finish.size() == 2, str(finish.size()))
	# 미등재 이벤트는 오류가 아니라 무음 (규칙 U-a 저장 무음 등)
	_ok("미등재 이벤트 = 빈 배열", data.sounds_for("save_indicator").is_empty())


# ── ③-① 봉인 (불변규칙 5 · D11 §1.3 R-a) ──
func _seal_rule() -> void:
	var data := _new_data()
	if data == null:
		return
	var recorder := RecordingOutput.new()
	var dispatcher := _new_dispatcher(data, recorder)
	dispatcher.open_seal()
	_ok("봉인 창 개시", dispatcher.seal_open())
	# 릴 정지 연출 중 매치음·결과음·스팅은 어떤 경로로도 나가지 않는다
	for event_id in ["reel_match_two", "reel_match_three", "result_advance", "result_chance",
			"grade_l1", "grade_l2", "grade_l3"]:
		var emitted := dispatcher.emit(String(event_id))
		_ok("봉인 중 미발화: %s" % event_id, emitted.is_empty(), str(emitted))
	_ok("봉인 중 출력 싱크 무발화", recorder.sfx.is_empty(), str(recorder.sfx))
	_ok("봉인 중 발화 기록 공백", dispatcher.fired.is_empty(), str(dispatcher.fired))
	_ok("차단 건수만 남는다 (내용 미기록)", dispatcher.seal_refusal_count() > 0,
		"count=%d" % dispatcher.seal_refusal_count())
	# 봉인과 무관한 사운드는 봉인 중에도 정상 발화한다 — 전면 정지가 아니라 결과 상관만 막는다
	var timer_fired := dispatcher.emit("timer_enter_warning")
	_ok("봉인 중에도 비상관 사운드는 발화", timer_fired.size() == 1, str(timer_fired))
	# 정지 연출 완료 후 개방
	dispatcher.close_seal()
	_ok("봉인 창 종료", not dispatcher.seal_open())
	var after := dispatcher.emit("reel_match_three")
	_ok("정지 완료 후 매치음 발화", after.size() == 1, str(after))
	_ok("출력 싱크에 도달", recorder.sfx.has("SE-R05"), str(recorder.sfx))
	# **차단이 게이트 때문이 아니라 봉인 때문임을 분리 확인** — 봉인 창을 다시 열면
	# 시계를 아무리 전진시켜도 막힌다 (재트리거 게이트와 봉인의 혼동 차단).
	dispatcher.clock_override_msec = 999999
	dispatcher.open_seal()
	_ok("시간이 지나도 봉인은 뚫리지 않는다", dispatcher.emit("result_chance").is_empty())


# ── ③-② 재트리거 게이트 (D11 §6.3) ──
func _retrigger_gate() -> void:
	var data := _new_data()
	if data == null:
		return
	var dispatcher := _new_dispatcher(data)
	var gate_msec := int(round(data.param("param_audio_retrigger_gate_sec") * 1000.0))
	_ok("게이트 값 > 0 (데이터 실재)", gate_msec > 0, "msec=%d" % gate_msec)
	_ok("최초 발화", dispatcher.emit("ui_cursor").size() == 1)
	_ok("게이트 내 재발화 차단", dispatcher.emit("ui_cursor").is_empty())
	dispatcher.clock_override_msec = gate_msec - 1
	_ok("경계 직전은 여전히 차단", dispatcher.emit("ui_cursor").is_empty())
	dispatcher.clock_override_msec = gate_msec
	_ok("경계 도달 시 통과", dispatcher.emit("ui_cursor").size() == 1)
	# 함성(AMB-02)은 전용 간격을 갖는다 (D13 별첨A §8.3 '함성 재트리거 최소 간격')
	var cheer_msec := int(round(data.param("param_cheer_retrigger_sec") * 1000.0))
	_ok("함성 간격 > 기본 게이트", cheer_msec > gate_msec, "%d vs %d" % [cheer_msec, gate_msec])
	var cheer := _new_dispatcher(data)
	_ok("함성 최초 발화", cheer.emit("result_advance").size() == 2)   # SE-E01 + AMB-02
	cheer.clock_override_msec = gate_msec + 1
	# 기본 게이트는 지났으므로 SE-E01 은 다시 울리고 AMB-02 는 아직 막혀 있어야 한다
	var second := cheer.emit("result_advance")
	_ok("기본 게이트 경과분만 재발화", second.size() == 1, str(second))
	_ok("재발화분 = 결과음 쪽", second.has("sound_result_advance"), str(second))
	cheer.clock_override_msec = cheer_msec + 1
	_ok("함성 간격 경과 후 함성 재발화",
		cheer.emit("result_advance").has("sound_amb_cheer_advance"))


# ── ③-③ 가상 채널 상한·컬링 (D11 §6.3) ──
func _channel_cap_and_culling() -> void:
	var data := _new_data()
	if data == null:
		return
	var cap := data.param_int("param_audio_virtual_channels")
	_ok("채널 상한 = 데이터 값", cap > 0, "cap=%d" % cap)
	var recorder := RecordingOutput.new()
	var dispatcher := _new_dispatcher(data, recorder)
	# P3 를 상한까지 채운다 (게이트 회피를 위해 매번 서로 다른 이벤트를 쓴다)
	var p3_events := ["ui_cursor", "ui_decide", "ui_cancel", "ui_tab", "ui_toggle",
		"station_enter", "purchase", "sell", "tuning_install", "repair_execute",
		"crew_join", "skill_unlock", "growth_gate_open", "overhaul_install"]
	for index in range(cap):
		dispatcher.emit(String(p3_events[index % p3_events.size()]))
	_ok("상한까지 점유", dispatcher.active_voice_count() == cap,
		"actual=%d" % dispatcher.active_voice_count())
	# 초과 발음은 P3 를 걷어내고 들어간다 — 총량은 상한을 넘지 않는다
	dispatcher.emit("settle_rollup")
	_ok("컬링 후에도 상한 유지", dispatcher.active_voice_count() == cap,
		"actual=%d" % dispatcher.active_voice_count())
	_ok("컬링 통지 발생", not recorder.culled.is_empty(), str(recorder.culled))
	# 표현 층이 스트림 종료를 알리면 자리가 빈다
	var before := dispatcher.active_voice_count()
	dispatcher.release_voice("SE-U15")
	_ok("보이스 해제", dispatcher.active_voice_count() == before - 1)
	# **P1·P2 는 밀려나지 않는다** — 우선 3층의 방향이 뒤집히면 정보음이 먼저 죽는다
	var guarded := _new_dispatcher(data, RecordingOutput.new())
	var p1_events := ["timer_enter_warning", "timer_enter_imminent", "timer_imminent_tick",
		"duel_warning", "chassis_warning", "resonance_announce"]
	for event_id in p1_events:
		guarded.emit(String(event_id))
	var p1_count := guarded.active_voice_count()
	while guarded.active_voice_count() < cap:
		# P2 로 남은 자리를 채운다
		if guarded.emit("gp_start").is_empty() and guarded.emit("rank_stamp").is_empty() \
			and guarded.emit("achievement_get").is_empty() and guarded.emit("duel_win").is_empty() \
			and guarded.emit("duel_lose").is_empty() and guarded.emit("retire").is_empty():
			break
	_ok("P1 점유 유지", guarded.active_voice_count() >= p1_count)
	var overflow := guarded.emit("gp_finish")
	_ok("걷어낼 P3 가 없으면 신규 발음을 포기한다", overflow.is_empty(), str(overflow))
	_ok("P1·P2 는 상한 초과로도 밀려나지 않는다", guarded.active_voice_count() <= cap,
		"actual=%d cap=%d" % [guarded.active_voice_count(), cap])


# ── ③-④ P1 보호 (D11 §6.3 — 정보음 마스킹 방지) ──
func _p1_protection() -> void:
	var data := _new_data()
	if data == null:
		return
	var dispatcher := _new_dispatcher(data)
	_ok("P1 정보음 발화", dispatcher.emit("chassis_warning").size() == 1)
	_ok("P1 재생 중 P3 억제", dispatcher.emit("ui_cursor").is_empty())
	_ok("P1 재생 중 P2 는 통과", dispatcher.emit("rank_stamp").size() == 1)
	dispatcher.release_voice("SE-D06")
	_ok("P1 종료 후 P3 복귀", dispatcher.emit("ui_cursor").size() == 1)


# ── BGM 전이 (D11 §4.3 전이 규칙표) ──
func _bgm_transitions() -> void:
	var data := _new_data()
	if data == null:
		return
	var recorder := RecordingOutput.new()
	var dispatcher := _new_dispatcher(data, recorder)
	_ok("BGM 진입", dispatcher.emit("hub_enter").size() == 2)   # BGM-02 + AMB-04
	_ok("현재 트랙 기록", dispatcher.current_bgm() == "BGM-02", dispatcher.current_bgm())
	_ok("크로스페이드 값이 데이터에서 온다",
		recorder.bgm_fades.size() == 1
		and absf(float(recorder.bgm_fades[0]) - data.param("param_audio_crossfade_sec")) < 0.0001,
		str(recorder.bgm_fades))
	# 같은 트랙 재진입은 트랙을 다시 걸지 않는다 (개러지 화면 간 이동에서 BGM 이 끊기면 안 된다)
	dispatcher.clock_override_msec = 100000
	var again := dispatcher.emit("hub_enter")
	_ok("동일 트랙 재진입 = BGM 무재생", not again.has("sound_bgm_garage"), str(again))
	_ok("BGM 재생 호출 1회 유지", recorder.bgm.size() == 1, str(recorder.bgm))
	# 긴장 레이어 3종 트리거 (듀얼·타이머 임박·최종 랩) — 전부 상태 전이 동기.
	# 트랙 진입 시 레이어 초기화(false)가 이미 1건 기록돼 있으므로 그 뒤부터 센다.
	var tension_base := recorder.tension.size()
	_ok("트랙 진입이 레이어를 초기화한다", tension_base == 1 and not bool(recorder.tension[0]),
		str(recorder.tension))
	dispatcher.set_tension(true)
	_ok("긴장 레이어 온", dispatcher.tension_on()
		and recorder.tension.size() == tension_base + 1 and bool(recorder.tension[tension_base]),
		str(recorder.tension))
	dispatcher.set_tension(true)
	_ok("중복 전이 무시", recorder.tension.size() == tension_base + 1, str(recorder.tension))
	dispatcher.set_tension(false)
	_ok("긴장 레이어 오프",
		not dispatcher.tension_on() and recorder.tension.size() == tension_base + 2,
		str(recorder.tension))
	# 트랙 교체 시 레이어는 꺼진 상태로 시작한다 (레이어는 트랙 종속 — 상한 2레이어 봉인)
	dispatcher.set_tension(true)
	dispatcher.emit("stage_pulse_dome_enter")
	_ok("트랙 교체", dispatcher.current_bgm() == "BGM-07", dispatcher.current_bgm())
	_ok("트랙 교체 시 긴장 레이어 초기화", not dispatcher.tension_on())
	# 리타이어 = BGM 즉시 정지 → JG-03 (순서가 규칙)
	dispatcher.stop_bgm()
	_ok("BGM 정지", dispatcher.current_bgm() == "" and recorder.stopped == 1,
		"stopped=%d" % recorder.stopped)
	var retire := dispatcher.emit("retire")
	_ok("리타이어 = SE-D07 + JG-03", retire.size() == 2, str(retire))
	_ok("징글 경로", recorder.jingles.has("JG-03"), str(recorder.jingles))


# ── 덕킹 (D11 §6.3 — L2·L3 스팅·징글 재생 중) ──
func _ducking() -> void:
	var data := _new_data()
	if data == null:
		return
	var recorder := RecordingOutput.new()
	var dispatcher := _new_dispatcher(data, recorder)
	dispatcher.emit("grade_l1")
	_ok("L1 스팅은 덕킹 대상 아님", recorder.ducks.is_empty(), str(recorder.ducks))
	dispatcher.emit("grade_l2")
	_ok("L2 스팅 덕킹", recorder.ducks.size() == 1, str(recorder.ducks))
	_ok("덕킹 깊이가 데이터에서 온다",
		absf(float(recorder.ducks[0][0]) - data.param("param_audio_duck_db")) < 0.0001,
		str(recorder.ducks[0]))
	_ok("복귀 시간이 데이터에서 온다",
		absf(float(recorder.ducks[0][1]) - data.param("param_audio_duck_return_sec")) < 0.0001,
		str(recorder.ducks[0]))
	dispatcher.emit("grade_l3")
	_ok("L3 스팅 덕킹", recorder.ducks.size() == 2)
	dispatcher.emit("season_champion")
	_ok("징글 덕킹", recorder.ducks.size() == 3, str(recorder.ducks.size()))


# ── 무음 폴백 (D12 §10 — 실물 부재 상태에서 전 경로가 성립해야 한다) ──
func _silent_fallback() -> void:
	var data := _new_data()
	if data == null:
		return
	# 싱크를 주지 않는다 = 사운드 실물이 하나도 없는 현 단계 그대로
	var dispatcher := AudioDispatcher.new()
	dispatcher.setup(data)
	dispatcher.clock_override_msec = 0
	_ok("싱크 미지정에서도 발화 성립", dispatcher.emit("gp_start").size() == 1)
	_ok("싱크 미지정에서도 BGM 성립", dispatcher.emit("title_enter").size() == 1)
	dispatcher.set_tension(true)
	dispatcher.stop_bgm()
	_ok("무음 폴백에서 상태가 정상 전이", dispatcher.current_bgm() == "" and not dispatcher.tension_on())
	# 데이터 미설정 디스패처도 죽지 않는다 (초기화 순서에 의존하지 않는다)
	var bare := AudioDispatcher.new()
	_ok("데이터 미설정 = 무발화", bare.emit("gp_start").is_empty())


# ── ④ 값 출처 — 리터럴 회피 검사 ──
# 픽스처는 채널 상한·게이트를 기본과 다르게 담는다. 거동이 따라오지 않으면
# 코드가 데이터가 아니라 리터럴을 쓰고 있다는 뜻이며, 기본 데이터로는 그 결함이 보이지 않는다.
func _values_come_from_data() -> void:
	var fixture := _new_data(FIXTURE_DIR)
	var default_data := _new_data()
	if fixture == null or default_data == null:
		return
	var fixture_cap := fixture.param_int("param_audio_virtual_channels")
	var default_cap := default_data.param_int("param_audio_virtual_channels")
	_ok("픽스처가 실제로 다른 값을 담는다", fixture_cap != default_cap,
		"fixture=%d default=%d" % [fixture_cap, default_cap])
	var dispatcher := _new_dispatcher(fixture, RecordingOutput.new())
	var p3_events := ["ui_cursor", "ui_decide", "ui_cancel", "ui_tab", "ui_toggle",
		"station_enter", "purchase", "sell", "tuning_install", "repair_execute"]
	for event_id in p3_events:
		dispatcher.emit(String(event_id))
	_ok("채널 상한이 픽스처 값을 따른다", dispatcher.active_voice_count() == fixture_cap,
		"actual=%d fixture=%d" % [dispatcher.active_voice_count(), fixture_cap])
	# 게이트도 같은 축 — 기본 게이트로는 통과할 시각에서 픽스처 게이트는 아직 막는다
	var gate := _new_dispatcher(fixture)
	gate.emit("ui_cursor")
	gate.clock_override_msec = int(round(default_data.param("param_audio_retrigger_gate_sec") * 1000.0))
	_ok("게이트가 픽스처 값을 따른다", gate.emit("ui_cursor").is_empty(),
		"fixture_gate=%f" % fixture.param("param_audio_retrigger_gate_sec"))


# 검사용 출력 싱크 — 기본 구현(무음)을 상속해 호출만 기록한다.
class RecordingOutput extends AudioOutput:
	var sfx: Array = []
	var culled: Array = []
	var bgm: Array = []
	var bgm_fades: Array = []
	var tension: Array = []
	var jingles: Array = []
	var ducks: Array = []
	var stopped := 0

	func play_sfx(sfx_id: String, _priority: String) -> void:
		sfx.append(sfx_id)

	func cull_sfx(sfx_id: String) -> void:
		culled.append(sfx_id)

	func play_bgm(track_id: String, crossfade_sec: float) -> void:
		bgm.append(track_id)
		bgm_fades.append(crossfade_sec)

	func stop_bgm() -> void:
		stopped += 1

	func set_bgm_tension(on: bool) -> void:
		tension.append(on)

	func play_jingle(jingle_id: String) -> void:
		jingles.append(jingle_id)

	func duck_bgm(db: float, return_sec: float) -> void:
		ducks.append([db, return_sec])


# ── 햅틱 결선 (D11 §3.1 · D12 §10.4 · D13 v1.11 §8.3 결정 #20) ──
#
# **진동은 출력 경로다**(불변규칙 5). 그래서 이 축의 중심은 강도 값이 아니라 **호출 지점**이다 —
# 봉인 창 중에 손이 결과를 알면 릴 정지 연출 전 노출이고, 그것은 값이 맞아도 위반이다.
# `seal_gated` ∧ `haptic≠none` = 4건이 그 이해관계다(18차 실측).
class HapticSpy extends IHaptics:
	var calls: Array = []

	func vibrate(strength: float, duration_sec: float) -> void:
		calls.append({"strength": strength, "duration": duration_sec})


func _haptic_dispatcher(data: GameData, spy: HapticSpy) -> AudioDispatcher:
	var dispatcher := AudioDispatcher.new()
	dispatcher.setup(data, null, spy)
	return dispatcher


func _haptic_wiring() -> void:
	var data := _new_data()
	if data == null:
		return
	# ── 등급 4종 → 값 창구 (D13 v1.11 전사분) ──
	var spy := HapticSpy.new()
	var dispatcher := _haptic_dispatcher(data, spy)
	var expected := [
		{"event": "confirm", "grade": "micro",
			"amp": "param_haptic_micro_amp", "sec": "param_haptic_micro_sec"},
		{"event": "grade_l1", "grade": "weak",
			"amp": "param_haptic_weak_amp", "sec": "param_haptic_l1_sec"},
		{"event": "duel_enter", "grade": "mid",
			"amp": "param_haptic_mid_amp", "sec": "param_haptic_mid_sec"},
		{"event": "retire", "grade": "strong",
			"amp": "param_haptic_strong_amp", "sec": "param_haptic_l2_sec"},
	]
	for index in range(expected.size()):
		var row: Dictionary = expected[index]
		# 창구가 먼저다 — 없는 키를 `param()` 이 0 으로 돌려주면 아래 대조가 0 == 0 이 된다.
		_ok("창구 실재 %s.진폭" % row["grade"], data.params.has(String(row["amp"])), String(row["amp"]))
		_ok("창구 실재 %s.지속" % row["grade"], data.params.has(String(row["sec"])), String(row["sec"]))
	spy.calls.clear()
	for row in expected:
		dispatcher.emit(String(row["event"]))
	_ok("등급 4종 전건 발화", spy.calls.size() == expected.size(), str(spy.calls.size()))
	if spy.calls.size() == expected.size():
		for index in range(expected.size()):
			var row: Dictionary = expected[index]
			var call: Dictionary = spy.calls[index]
			_eq("%s 진폭 = 창구" % row["grade"], float(call["strength"]),
				data.param(String(row["amp"])))
			_eq("%s 지속 = 창구" % row["grade"], float(call["duration"]),
				data.param(String(row["sec"])))
	# **등급이 실제로 갈리는가** — 넷이 같은 값이면 위 대조는 전건 통과하면서 매핑이 죽는다.
	var amps: Dictionary = {}
	for call in spy.calls:
		amps[float(Dictionary(call)["strength"])] = true
	_ok("등급 4종 진폭이 전부 다르다", amps.size() == 4, str(amps.keys()))

	# ── `none` = 무진동 (사운드는 울린다) ──
	var none_spy := HapticSpy.new()
	var none_dispatcher := _haptic_dispatcher(data, none_spy)
	var fired: Array = none_dispatcher.emit("ui_decide")
	_ok("none 등급 = 사운드 발화", not fired.is_empty(), str(fired))
	_ok("none 등급 = 진동 0", none_spy.calls.is_empty(), str(none_spy.calls))

	# ── 봉인 (불변규칙 5) ──
	var seal_spy := HapticSpy.new()
	var seal_dispatcher := _haptic_dispatcher(data, seal_spy)
	seal_dispatcher.open_seal()
	for event_id in ["grade_l1", "grade_l2", "result_trouble"]:
		seal_dispatcher.emit(event_id)
	_ok("봉인 창 중 진동 0", seal_spy.calls.is_empty(), str(seal_spy.calls))
	_ok("봉인 거부 계수 3", seal_dispatcher.seal_refusal_count() == 3,
		str(seal_dispatcher.seal_refusal_count()))
	seal_dispatcher.close_seal()
	seal_dispatcher.emit("grade_l1")
	_ok("봉인 해제 후 진동 발화", seal_spy.calls.size() == 1, str(seal_spy.calls))

	# ── O3 감쇠 — **진폭에만** (D13 v1.11 명문 · D12 §10.4 곱 순서) ──
	var damp_spy := HapticSpy.new()
	var damp_dispatcher := _haptic_dispatcher(data, damp_spy)
	var ratio: float = data.param("param_haptic_damp_ratio")
	damp_dispatcher.haptic_damping = ratio
	damp_dispatcher.emit("retire")
	_ok("감쇠 = 1회 발화", damp_spy.calls.size() == 1, str(damp_spy.calls))
	if damp_spy.calls.size() == 1:
		var damped: Dictionary = damp_spy.calls[0]
		_eq("감쇠 진폭 = 원값 × 배율",
			float(damped["strength"]), data.param("param_haptic_strong_amp") * ratio)
		# 지속을 함께 줄이면 감소 설정이 정보 전달 길이를 바꾼다 — 그것은 감쇠가 아니다.
		_eq("감쇠 지속 = 불변", float(damped["duration"]), data.param("param_haptic_l2_sec"))
	# 끔(0.0) = 호출 자체가 없다. 진폭 0 으로 부르면 플랫폼별 거동이 갈린다.
	var off_spy := HapticSpy.new()
	var off_dispatcher := _haptic_dispatcher(data, off_spy)
	off_dispatcher.haptic_damping = 0.0
	off_dispatcher.emit("retire")
	_ok("끔 = 호출 0(진폭 0 호출 아님)", off_spy.calls.is_empty(), str(off_spy.calls))

	# ── 게이트 뒤 (한 이벤트의 두 출력이 갈리지 않는다) ──
	var gate_spy := HapticSpy.new()
	var gate_dispatcher := _haptic_dispatcher(data, gate_spy)
	gate_dispatcher.clock_override_msec = 0
	gate_dispatcher.emit("retire")
	gate_dispatcher.emit("retire")   # 재트리거 게이트에 걸린다
	_ok("재트리거 억제분 = 진동도 억제", gate_spy.calls.size() == 1, str(gate_spy.calls.size()))

	# ── 무햅틱 폴백 — 어댑터 미주입에서도 발화가 성립한다 ──
	var bare := AudioDispatcher.new()
	bare.setup(data)
	var bare_fired: Array = bare.emit("retire")
	_ok("무햅틱 폴백 = 사운드 발화 성립", not bare_fired.is_empty(), str(bare_fired))
	_ok("무햅틱 폴백 = 어댑터 null", bare.haptics == null)
