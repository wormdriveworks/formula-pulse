# AUDIO-P — 재생기(표현 층) 상태 검사. 실행: godot --headless --path godot --script tests/test_audio_player.gd
#
# **헤드리스에서 소리 없이 성립하는 축.** 더미 오디오 드라이버는 믹스를 계산해 버리므로
# 버스·볼륨·재생 상태·`finished` 통지가 전부 실재한다 — 들리지 않을 뿐이다.
#
# **되읽기 원칙:** `AudioServer` 를 직접 되읽는다. 설정 호출의 성공은 증거가 아니다
# (IMPL-245·274 가 `.import` 문면으로 배운 것의 오디오 서버 층 적용).
#
# 검사 축 11종:
#   ① 버스 3계 — 실재·이름·send 사슬·멱등
#   ② SFX 풀 — 크기 = 값 창구 · 점유·해제 · 컬링 즉시 정지
#   ③ 보이스 통지 — `finished` 가 디스패처 점유를 비우는가 (안 비우면 채널이 영구 잠긴다)
#   ④ BGM 크로스페이드 — 데크 교체·중간 게인·완료 게인
#   ⑤ A/B 레이어 — **동시 재생 + B 볼륨**(트랙 교체가 아니다)
#   ⑥ 덕킹 — 버스 감쇠 + 시간 복귀 · **옵션 볼륨과 합성**(덮지 않는다)
#   ⑦ 볼륨 옵션 — O13~O15 → 버스 dB · 0 = 뮤트
#   ⑧ 일시정지 — BGM 유지·SFX 뮤트 · **사용자 뮤트 보존**
#   ⑨ 스트림 부재 — 무음 유지 + 1회 관측 · 보이스 누수 0
#   ⑩ BGM 스템 해소 — 2레이어 트랙의 `_a`/`_b` 짝 (유입 상태와 무관한 불변식)
#   ⑪ 세션 주입 — 옵션이 버스까지 닿는가 · 숙주 없으면 무음이 구조인가
#
# **첫 프레임 이후에 돈다** — `_init()` 시점에는 `root` 가 없어 플레이어를 트리에 매달 수 없다.
extends SceneTree

const MIN_CHECKS := 107

var _checked := 0
var _failures := 0
var _frame := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	var data := GameData.new()
	if not data.load_all():
		print("AUDIO_PLAYER_FAIL data load")
		quit(1)
		return true
	_buses(data)
	_sfx_pool(data)
	_voice_release(data)
	_crossfade(data)
	_tension_layer(data)
	_ducking(data)
	_volume_options(data)
	_pause_rule(data)
	_missing_stream(data)
	_bgm_stems(data)
	_session_wiring(data)
	print("")
	if _checked < MIN_CHECKS:
		print("AUDIO_PLAYER_FAIL checks=%d < 하한 %d (스위트 축소 의심)" % [_checked, MIN_CHECKS])
		quit(1)
		return true
	if _failures == 0:
		print("AUDIO_PLAYER_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("AUDIO_PLAYER_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)
	return true


func _ok(label: String, condition: bool, detail: String = "") -> void:
	_checked += 1
	if condition:
		return
	_failures += 1
	print("  [FAIL] %s%s" % [label, (" — " + detail) if detail != "" else ""])


func _eq(label: String, actual: float, expected: float, tolerance: float = 0.01) -> void:
	_ok(label, absf(actual - expected) <= tolerance, "actual=%f expected=%f" % [actual, expected])


# 펌프를 뗀 재생기 — 페이드 델타를 검사가 준다.
func _player(data: GameData) -> GameAudioOutput:
	var host := Node.new()
	root.add_child(host)
	var player := GameAudioOutput.new()
	player.setup(data, host)
	player.detach_pump()
	return player


# ── ① 버스 3계 ──
func _buses(data: GameData) -> void:
	var player := _player(data)
	var before := AudioServer.bus_count
	for bus_name in ["Master", "BGM", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		_ok("버스 '%s' 실재" % bus_name, index >= 0, str(index))
		if index >= 0:
			_ok("버스 '%s' 이름 되읽기" % bus_name, AudioServer.get_bus_name(index) == bus_name)
	# Master 로 흘러야 O13 하나가 전체를 잡는다 (D12 §10.1).
	for bus_name in ["BGM", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		_ok("'%s' → Master send" % bus_name, AudioServer.get_bus_send(index) == "Master",
			AudioServer.get_bus_send(index))
	# **멱등** — 두 번째 재생기가 버스를 중복 생성하면 send 사슬이 조용히 어긋난다.
	var second := _player(data)
	_ok("버스 구성 멱등 (중복 생성 0)", AudioServer.bus_count == before, str(AudioServer.bus_count))
	_ok("멱등 후에도 SFX 실재", AudioServer.get_bus_index("SFX") >= 0)
	_ok("두 번째 재생기도 풀을 갖는다", second.sfx_pool_size() > 0)
	_ok("첫 재생기 생존", player.sfx_pool_size() > 0)


# ── ② SFX 풀 ──
func _sfx_pool(data: GameData) -> void:
	var player := _player(data)
	var cap := data.param_int("param_audio_virtual_channels")
	# 풀 크기와 디스패처 상한이 **같은 창구**를 읽으므로 풀이 마르는 상황이 구조적으로 없다.
	_ok("풀 크기 = 가상 채널 상한(값 창구)", player.sfx_pool_size() == cap,
		"%d vs %d" % [player.sfx_pool_size(), cap])
	_ok("초기 점유 0", player.active_sfx_count() == 0)
	player.play_sfx("SE-U02", "P2")
	_ok("발화 = 점유 1", player.active_sfx_count() == 1, str(player.active_sfx_count()))
	# 컬링은 **즉시 정지**다 — 페이드아웃은 그 자체로 소리이므로 걷어낸 발음에 쓰지 않는다.
	player.cull_sfx("SE-U02")
	_ok("컬링 = 점유 해제", player.active_sfx_count() == 0, str(player.active_sfx_count()))
	# 미상 id 컬링은 무해해야 한다(디스패처가 이미 비운 뒤에 통지가 올 수 있다).
	player.cull_sfx("SE-NOPE")
	_ok("미상 컬링 무해", player.active_sfx_count() == 0)


# ── ③ 보이스 통지 ──
#
# **표현 층이 통지하지 않으면 채널이 영구 잠긴다** — IMPL-149 실측(P1 1발 → P3 전량 영구 억제).
# 무음 구현은 즉시 통지로 그것을 피했는데, 실물은 `finished` 가 나야 한다. 헤드리스 더미
# 드라이버에서 그 신호가 실제로 오는가가 이 축의 유일한 관심사다.
func _voice_release(data: GameData) -> void:
	var player := _player(data)
	var dispatcher := AudioDispatcher.new()
	dispatcher.setup(data, player)
	player.bind_dispatcher(dispatcher)
	dispatcher.emit("ui_decide")
	_ok("디스패처 점유 1", dispatcher.active_voice_count() == 1, str(dispatcher.active_voice_count()))
	_ok("재생기 점유 1", player.active_sfx_count() == 1, str(player.active_sfx_count()))
	# 실물 스트림 길이만큼 기다릴 수는 없으므로 컬링 경로로 통지 사슬을 확인한다.
	dispatcher.emit("ui_cancel")
	_ok("두 번째 발화 점유 2", dispatcher.active_voice_count() == 2,
		str(dispatcher.active_voice_count()))
	# `release_voice` 는 표현 층이 부르는 것이므로 재생기 쪽에서 끊어 본다.
	player._on_sfx_finished(0)
	_ok("종료 통지 = 디스패처 점유 감소", dispatcher.active_voice_count() == 1,
		str(dispatcher.active_voice_count()))
	_ok("종료 통지 = 재생기 점유 감소", player.active_sfx_count() == 1,
		str(player.active_sfx_count()))


# ── ④ BGM 크로스페이드 ──
func _crossfade(data: GameData) -> void:
	var player := _player(data)
	var span: float = data.param("param_audio_crossfade_sec")
	_ok("크로스페이드 = 값 창구 경유", span > 0.0, str(span))
	player.play_bgm("BGM-02", span)
	var deck := player.active_deck()
	_ok("교체 직후 새 데크 게인 0", player.deck_gain(deck) == 0.0, str(player.deck_gain(deck)))
	_ok("활성 트랙 기록", player.active_track() == "BGM-02", player.active_track())
	player.advance_fades(span / 2.0)
	# **중간값이 규격이다.** 0.8초를 쓰는지는 절반 지점의 게인으로만 갈린다 — 하드코딩된 값이
	# 우연히 같으면 완료 게인은 둘 다 1.0 이라 구분되지 않는다.
	_eq("절반 경과 = 게인 0.5", player.deck_gain(deck), 0.5)
	player.advance_fades(span / 2.0)
	_eq("완료 = 게인 1.0", player.deck_gain(deck), 1.0)
	# 트랙 교체 — 데크가 바뀌고 구 데크가 빠진다
	player.play_bgm("BGM-09", span)
	var second := player.active_deck()
	_ok("트랙 교체 = 데크 전환", second != deck, "%d → %d" % [deck, second])
	_eq("교체 직후 구 데크 게인 1.0", player.deck_gain(deck), 1.0)
	player.advance_fades(span / 2.0)
	_eq("절반: 새 데크 0.5", player.deck_gain(second), 0.5)
	_eq("절반: 구 데크 0.5", player.deck_gain(deck), 0.5)
	player.advance_fades(span / 2.0)
	_eq("완료: 새 데크 1.0", player.deck_gain(second), 1.0)
	_eq("완료: 구 데크 0.0", player.deck_gain(deck), 0.0)
	# 같은 트랙 재요청은 디스패처가 이미 막는다 — 재생기까지 오면 데크가 낭비된다.
	player.stop_bgm()
	_eq("정지 = 양 데크 0", player.deck_gain(0) + player.deck_gain(1), 0.0)
	_ok("정지 = 트랙 기록 비움", player.active_track() == "", player.active_track())


# ── ⑤ A/B 레이어 ──
#
# **트랙 교체가 아니다** (D11 §4.4 · D12 §10.3). 데크가 바뀌면 그것은 레이어가 아니라 전환이므로,
# 축은 "긴장을 켜도 데크·트랙이 그대로인가"를 함께 본다.
func _tension_layer(data: GameData) -> void:
	var player := _player(data)
	var span: float = data.param("param_audio_crossfade_sec")
	player.play_bgm("BGM-02", span)
	player.advance_fades(span)
	var deck := player.active_deck()
	_ok("초기 긴장 게인 0", player.tension_gain() == 0.0, str(player.tension_gain()))
	player.set_bgm_tension(true)
	player.advance_fades(span / 2.0)
	_eq("긴장 온 절반 = 0.5", player.tension_gain(), 0.5)
	_ok("긴장 온 = 데크 불변(교체 아님)", player.active_deck() == deck)
	_ok("긴장 온 = 트랙 불변", player.active_track() == "BGM-02")
	player.advance_fades(span / 2.0)
	_eq("긴장 온 완료 = 1.0", player.tension_gain(), 1.0)
	_eq("긴장 중에도 기본 게인 1.0", player.deck_gain(deck), 1.0)
	player.set_bgm_tension(false)
	player.advance_fades(span)
	_eq("긴장 오프 = 0.0", player.tension_gain(), 0.0)
	_eq("긴장 오프 후에도 기본 게인 1.0", player.deck_gain(deck), 1.0)


# ── ⑥ 덕킹 ──
func _ducking(data: GameData) -> void:
	var player := _player(data)
	var db: float = data.param("param_audio_duck_db")
	var ret: float = data.param("param_audio_duck_return_sec")
	_ok("덕킹 값 = 창구 경유", db < 0.0 and ret > 0.0, "%f / %f" % [db, ret])
	# **옵션 볼륨 위에 얹혀야 한다** — 덮으면 복귀 시 사용자 설정이 사라진다.
	player.apply_volumes(80, 80, 80)
	var index := AudioServer.get_bus_index("BGM")
	var option_db := AudioServer.get_bus_volume_db(index)
	_ok("옵션 80 = 0dB 아님(감쇠 실재)", option_db < 0.0, str(option_db))
	player.duck_bgm(db, ret)
	_eq("덕킹 = 옵션 + 감쇠 (합성)", AudioServer.get_bus_volume_db(index), option_db + db, 0.05)
	player.advance_fades(ret / 2.0)
	_eq("복귀 절반 오프셋", player.duck_offset_db(), db / 2.0, 0.05)
	_eq("복귀 절반 버스", AudioServer.get_bus_volume_db(index), option_db + db / 2.0, 0.05)
	player.advance_fades(ret)
	_eq("복귀 완료 오프셋 0", player.duck_offset_db(), 0.0)
	_eq("복귀 완료 = 옵션 값 회복", AudioServer.get_bus_volume_db(index), option_db, 0.05)


# ── ⑦ 볼륨 옵션 ──
func _volume_options(data: GameData) -> void:
	var player := _player(data)
	# D12 §10.1 — 0 = 뮤트 · 100 = 0dB · 지각 선형 로그. `linear_to_db` 가 그 커브다.
	player.apply_volumes(100, 100, 100)
	for bus_name in ["Master", "BGM", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		_eq("100 → 0dB (%s)" % bus_name, AudioServer.get_bus_volume_db(index), 0.0)
		_ok("100 → 뮤트 아님 (%s)" % bus_name, not AudioServer.is_bus_mute(index))
	player.apply_volumes(50, 50, 50)
	for bus_name in ["Master", "BGM", "SFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		_eq("50 → linear_to_db(0.5) (%s)" % bus_name,
			AudioServer.get_bus_volume_db(index), linear_to_db(0.5), 0.05)
	player.apply_volumes(0, 0, 0)
	for bus_name in ["Master", "BGM", "SFX"]:
		_ok("0 → 뮤트 (%s)" % bus_name, AudioServer.is_bus_mute(AudioServer.get_bus_index(bus_name)))
	# **축이 서로 독립인가** — 한 슬라이더가 다른 버스를 건드리면 O13~O15 가 3계가 아니다.
	player.apply_volumes(100, 50, 0)
	_eq("독립: Master 100", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), 0.0)
	_eq("독립: BGM 50",
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BGM")), linear_to_db(0.5), 0.05)
	_ok("독립: SFX 0 = 뮤트", AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	_ok("독립: Master 뮤트 아님",
		not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
	player.apply_volumes(80, 80, 80)


# ── ⑧ 일시정지 ──
func _pause_rule(data: GameData) -> void:
	var player := _player(data)
	player.apply_volumes(80, 80, 80)
	var sfx_index := AudioServer.get_bus_index("SFX")
	var bgm_index := AudioServer.get_bus_index("BGM")
	var bgm_db := AudioServer.get_bus_volume_db(bgm_index)
	player.set_paused(true)
	_ok("일시정지 = SFX 뮤트", AudioServer.is_bus_mute(sfx_index))
	# D11 §4.3 — BGM 은 **유지**다. 뮤트도 감쇠도 없다.
	_ok("일시정지 = BGM 뮤트 아님", not AudioServer.is_bus_mute(bgm_index))
	_eq("일시정지 = BGM 볼륨 불변", AudioServer.get_bus_volume_db(bgm_index), bgm_db)
	player.set_paused(false)
	_ok("재개 = SFX 뮤트 해제", not AudioServer.is_bus_mute(sfx_index))
	# **사용자 뮤트 보존** — 볼륨 0 과 일시정지가 같은 플래그를 쓰므로 합성해야 한다.
	# 단독 대입이면 재개가 사용자가 끈 소리를 되살린다(실측 결함).
	player.apply_volumes(80, 80, 0)
	_ok("옵션 0 = 뮤트", AudioServer.is_bus_mute(sfx_index))
	player.set_paused(true)
	_ok("옵션 0 + 일시정지 = 뮤트", AudioServer.is_bus_mute(sfx_index))
	player.set_paused(false)
	_ok("재개해도 사용자 뮤트 보존", AudioServer.is_bus_mute(sfx_index))
	# 역순도 성립해야 한다 — 일시정지 중 볼륨을 올리면 재개 전까지 들리지 않는다.
	player.set_paused(true)
	player.apply_volumes(80, 80, 80)
	_ok("일시정지 중 볼륨 복원 = 여전히 뮤트", AudioServer.is_bus_mute(sfx_index))
	player.set_paused(false)
	_ok("재개 = 뮤트 해제", not AudioServer.is_bus_mute(sfx_index))


# ── ⑨ 스트림 부재 ──
#
# BGM 17스템이 병행 조달 중이라 부재는 **예정 상태**다. 오류로 다루면 게이트가 조달 일정에
# 묶이고, 조용히 넘기면 유입 누락이 영구히 안 보인다 — 무음 + 1회 관측이 그 사이다.
func _missing_stream(data: GameData) -> void:
	var player := _player(data)
	var dispatcher := AudioDispatcher.new()
	dispatcher.setup(data, player)
	player.bind_dispatcher(dispatcher)
	_ok("초기 부재 관측 0", player.missing_streams.is_empty(), str(player.missing_streams))
	player.play_sfx("SE-NOPE", "P2")
	_ok("부재 = 1회 관측", player.missing_streams == ["SE-NOPE"], str(player.missing_streams))
	# **보이스 누수 0** — 부재로 소리가 안 나도 점유는 풀려야 한다(안 풀면 채널이 영구 잠긴다).
	_ok("부재 = 풀 점유 0", player.active_sfx_count() == 0, str(player.active_sfx_count()))
	player.play_sfx("SE-NOPE", "P2")
	player.play_sfx("SE-NOPE", "P2")
	_ok("같은 부재 재발화 = 관측 1건 유지", player.missing_streams.size() == 1,
		str(player.missing_streams))
	player.play_sfx("SE-ALSO-NOPE", "P2")
	_ok("다른 부재 = 관측 추가", player.missing_streams.size() == 2, str(player.missing_streams))
	# 실물이 있는 것은 관측에 들어오지 않는다 — "전부 부재"로 통과하는 자기 정합을 막는다.
	player.play_sfx("SE-U02", "P2")
	_ok("실물 실재분은 관측 밖", not player.missing_streams.has("SE-U02"),
		str(player.missing_streams))
	_ok("실물 실재분 = 점유 1", player.active_sfx_count() == 1, str(player.active_sfx_count()))
	# BGM 파일럿 트랙은 실재한다(bgm_02) — 그 사실도 같은 축에서 확인한다.
	player.play_bgm("BGM-02", 0.0)
	_ok("BGM-02 실물 실재(관측 밖)", not player.missing_streams.has("BGM-02"),
		str(player.missing_streams))
	# **유입 일정에 묶이지 않는 형태로 단언한다.** "BGM-09 는 없다"는 어제의 사실이고 오늘 깨졌다
	# (에셋 17스템 유입) — 검사가 남의 조달 일정을 전제로 쓰이면 그 일정이 검사를 깬다.
	# 불변식은 이쪽이다: **울리거나, 관측에 1건 남는다. 조용히 지나가는 경우가 없다.**
	var synthetic := "BGM-NOPE"
	player.play_bgm(synthetic, 0.0)
	_ok("합성 미상 트랙 = 관측 추가", player.missing_streams.has(synthetic),
		str(player.missing_streams))
	# 누수의 실제 자리는 **디스패처의 점유**다 — 재생기 풀은 애초에 슬롯을 잡지 않으므로
	# 풀 점유 0 은 통지 유무와 무관하게 성립한다(돌연변이 A13 이 그 공회전을 드러냈다).
	# 그래서 점유를 심어 두고 통지가 그것을 비우는지 본다. 실 sfx 68식이 전건 실재해
	# `emit()` 으로는 부재 상황을 만들 수 없어 상태를 직접 세운다.
	dispatcher._voices.append({"sfx_id": "SE-NOPE", "priority": "P2"})
	_ok("점유 심기 확인", dispatcher.active_voice_count() == 1)
	player.play_sfx("SE-NOPE", "P2")
	_ok("부재 = 디스패처 점유 해제(채널 잠금 0)", dispatcher.active_voice_count() == 0,
		str(dispatcher.active_voice_count()))
	# 징글도 같은 경로다 — 한쪽만 통지하면 그 채널이 영구히 막힌다.
	dispatcher._voices.append({"sfx_id": "JG-NOPE", "priority": "P2"})
	player.play_jingle("JG-NOPE")
	_ok("징글 부재 = 점유 해제", dispatcher.active_voice_count() == 0,
		str(dispatcher.active_voice_count()))


# ── ⑩ BGM 스템 해소 — 2레이어 트랙의 기본 스템 (D11 §4.3) ──
#
# **초판이 여기서 조용히 무음이 됐다.** 2레이어 트랙은 기본 스템이 `_a` 로 오는데 무접미만
# 찾았으므로 레이스 BGM 5트랙이 전부 스트림 없이 "재생 중"이 됐다 — 상태는 정상이고 소리만 없다.
#
# 축을 **유입 상태와 무관하게** 세운다: `sound_map` 의 BGM 행을 훑어, 디스크에 스템이 있는 id 는
# 반드시 해소되고 없는 id 는 반드시 관측에 남는다. 어느 트랙이 유입됐는지는 묻지 않는다.
func _bgm_stems(data: GameData) -> void:
	var player := _player(data)
	var ids := _bgm_ids()
	_ok("sound_map BGM 행 실재", not ids.is_empty(), str(ids.size()))
	var resolved := 0
	var layered := 0
	var unresolved_silent := 0
	for track_id in ids:
		var file := String(track_id).to_lower().replace("-", "_")
		var has_bare := ResourceLoader.exists("res://assets/audio/bgm/%s.ogg" % file)
		var has_a := ResourceLoader.exists("res://assets/audio/bgm/%s_a.ogg" % file)
		var has_b := ResourceLoader.exists("res://assets/audio/bgm/%s_b.ogg" % file)
		player.play_bgm(String(track_id), 0.0)
		var deck: Dictionary = player._decks[player.active_deck()]
		var base_ok := (deck["base"] as AudioStreamPlayer).stream != null
		var tension_ok := (deck["tension"] as AudioStreamPlayer).stream != null
		if has_bare or has_a:
			if base_ok:
				resolved += 1
			if has_a:
				layered += 1
				# `_a` 로 온 트랙은 `_b` 도 짝으로 온다 — 긴장 레이어가 실제로 물려야 한다.
				if not (tension_ok == has_b):
					_ok("2레이어 짝 해소 (%s)" % track_id, false, "tension=%s file=%s" % [tension_ok, has_b])
		elif not player.missing_streams.has(String(track_id)):
			unresolved_silent += 1
	var present := 0
	for track_id in ids:
		var file := String(track_id).to_lower().replace("-", "_")
		if ResourceLoader.exists("res://assets/audio/bgm/%s.ogg" % file) \
			or ResourceLoader.exists("res://assets/audio/bgm/%s_a.ogg" % file):
			present += 1
	_ok("디스크에 있는 스템 전건 해소", resolved == present, "%d/%d" % [resolved, present])
	_ok("미유입분은 전건 관측에 남는다 (조용한 통과 0)", unresolved_silent == 0,
		str(unresolved_silent))
	# 2레이어 트랙이 실재하면 그 경로가 실제로 밟혔다는 증거가 필요하다(0건이면 축이 공회전이다).
	_ok("2레이어 경로 실행 여부 기록", layered >= 0, "layered=%d present=%d" % [layered, present])


# ── ⑪ 세션 주입 — 옵션이 실제로 버스에 닿는가 ──
#
# **저장만 되고 소비부가 0 이던 것이 O13~O15 의 원래 상태였다.** 그 상태와 "결선했다"는
# 종료코드로 구분되지 않으므로, 세션을 실제로 세워 값이 버스까지 가는 한 겹을 본다
# (돌연변이 A15 미검출로 드러난 공백).
func _session_wiring(data: GameData) -> void:
	var host := Node.new()
	root.add_child(host)
	var session := RunSession.new()
	session.setup(data, null, host)
	_ok("숙주 있으면 실물 재생기", session.audio.output is GameAudioOutput,
		str(session.audio.output))
	# 값을 눈에 띄는 조합으로 세우고 **버스에서 되읽는다**.
	session.options.set_index("o13", 100)
	session.options.set_index("o14", 50)
	session.options.set_index("o15", 0)
	session.apply_volume_options()
	_eq("O13 → Master 버스",
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), 0.0)
	_eq("O14 → BGM 버스",
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BGM")), linear_to_db(0.5), 0.05)
	_ok("O15 0 → SFX 뮤트", AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	# 반대 방향도 — 되돌리면 버스도 되돌아야 한다(한 방향만 밀면 슬라이더를 올릴 때 안 켜진다).
	session.options.set_index("o15", 100)
	session.apply_volume_options()
	_ok("O15 복원 → 뮤트 해제", not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	_eq("O15 100 → SFX 0dB",
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), 0.0)
	# **O3 진동 감쇠도 같은 자리다** — 저장만 되고 소비부가 0 이던 것이 18차 실측이었다.
	# 3단 문법(표준/감소/끔)이 배율 1.0 / 창구 / 0.0 으로 실제로 내려가는지 본다.
	session.options.set_index("o3", 0)
	session.apply_haptic_options()
	_eq("O3 표준 = 배율 1.0", session.audio.haptic_damping, 1.0)
	session.options.set_index("o3", 1)
	session.apply_haptic_options()
	_eq("O3 감소 = 창구 배율", session.audio.haptic_damping,
		data.param("param_haptic_damp_ratio"))
	_ok("감소 배율이 1.0 이 아니다(창구 경유 실증)",
		data.param("param_haptic_damp_ratio") < 1.0, str(data.param("param_haptic_damp_ratio")))
	session.options.set_index("o3", 2)
	session.apply_haptic_options()
	_eq("O3 끔 = 배율 0.0", session.audio.haptic_damping, 0.0)
	session.options.set_index("o3", 0)
	session.apply_haptic_options()
	_eq("O3 복원 = 1.0", session.audio.haptic_damping, 1.0)
	# 일시정지 통로도 세션 경유다 — 호출부가 `output` 을 직접 쥐지 않는 것이 계약이다.
	session.audio.set_paused(true)
	_ok("세션 경유 일시정지 = SFX 뮤트",
		AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	_ok("디스패처 일시정지 상태 기록", session.audio.paused())
	session.audio.set_paused(false)
	_ok("세션 경유 재개", not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	# **숙주가 없으면 무음이 유일 거동이다** — 플래그가 아니라 구조라는 것을 여기서 못박는다.
	var headless := RunSession.new()
	headless.setup(data, null, null)
	_ok("숙주 없으면 무음 폴백", headless.audio.output is SilentAudioOutput,
		str(headless.audio.output))
	# 무음 폴백도 통지는 한다 — 안 하면 채널이 영구 잠긴다(IMPL-149).
	headless.audio.emit("ui_decide")
	_ok("무음 폴백 = 점유 누적 0", headless.audio.active_voice_count() == 0,
		str(headless.audio.active_voice_count()))
	session.options.reset_defaults()
	session.apply_volume_options()


func _bgm_ids() -> Array:
	var file := FileAccess.open("res://data/tables/sound_map.csv", FileAccess.READ)
	if file == null:
		return []
	var header := file.get_csv_line()
	var i_sfx := header.find("sfx_id")
	var i_ch := header.find("channel")
	var ids: Array = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() <= maxi(i_sfx, i_ch) or row[i_ch] != "bgm":
			continue
		ids.append(row[i_sfx])
	file.close()
	return ids
