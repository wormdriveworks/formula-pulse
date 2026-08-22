# 실물 재생기 — `AudioOutput` 계약의 표현 층 구현 (D12 §10.1~10.3 · D11 §4.3·§6.3).
#
# **디스패처는 이 파일의 존재를 모른다.** 정책(봉인·게이트·상한·P1 보호)은 전부 코어에 있고
# 여기는 "무엇을 어떻게 들리게 하는가"만 한다 — 그 경계가 `AudioOutput` 을 둔 이유다.
#
# 버스 3계 = Master / BGM / SFX (D12 §10.1 · 앰비언스 = SFX 귀속 — D11 §5).
# **런타임 구성을 택했다** (`default_bus_layout.tres` 대신). 근거 3항:
#   ①`.tres` 는 에디터 산출물이고 그 소유권은 주력 머신이다 — 원격이 만든 리소스가 에디터에서
#     재정규화되면 디프가 튄다(`.tscn` 과 같은 계열의 문제).
#   ②`.tres` 경로 지정은 `project.godot` 손 편집을 요구한다(`ProjectSettings.save()` 가 주석을
#     지우는 것이 실측돼 손 편집 전속인 파일이다 — 회피가 싸다).
#   ③**검증이 되읽기로 성립한다** — 구성 코드가 곧 `AudioServer` 호출이므로 같은 API 로 되읽어
#     단언할 수 있다. 리소스 파일은 "선언이 증거가 아니다"라는 함정(IMPL-245·274)을 다시 만든다.
#
# **수치를 하나도 갖지 않는다.** 채널 상한·크로스페이드·덕킹은 전량 `core_params` 경유이고
# (불변규칙 2), 볼륨 커브는 D12 §10.1 명문("0 = 뮤트 · 100 = 0dB · 지각 선형 로그")을
# `linear_to_db()` 로 그대로 옮긴 것이라 상수가 끼어들 자리가 없다.
class_name GameAudioOutput
extends AudioOutput

const BUS_MASTER := "Master"
const BUS_BGM := "BGM"
const BUS_SFX := "SFX"

# 파일 경로 = 채널 + id 규칙. `sound_map.csv` 의 channel 열이 곧 디렉토리이고
# 파일명은 sfx_id 소문자·하이픈→밑줄이다 (AUDIO-A 스위트와 같은 규약).
const DIRS := {
	"sfx": "res://assets/audio/sfx/",
	"jingle": "res://assets/audio/jingle/",
	"bgm": "res://assets/audio/bgm/",
}
const EXT := {"sfx": "wav", "jingle": "wav", "bgm": "ogg"}

var _data: GameData
var _host: Node
var _pump: Node
var _dispatcher_ref: WeakRef

# SFX 풀 — 크기 = 가상 채널 상한(D13). 디스패처의 상한과 **같은 창구를 읽으므로** 풀이
# 마르는 상황은 구조적으로 생기지 않는다(상한을 넘긴 발화는 코어에서 이미 걸린다).
var _sfx_pool: Array = []
var _sfx_ids: Array = []          # 풀 인덱스 → 지금 물려 있는 sfx_id ("" = 유휴)
var _jingle_player: AudioStreamPlayer

# BGM 데크 2벌 — 크로스페이드는 **트랙 교체**이고 A/B 레이어는 **동시 재생 + B 볼륨**이다
# (D11 §4.4 · D12 §10.3). 그래서 데크마다 base·tension 두 플레이어를 갖는다.
var _decks: Array = []
var _active_deck := 0

var _tension_gain := 0.0
var _tension_target := 0.0

# 덕킹은 **버스** 감쇠다(D12 §10.3 "버스 볼륨 자동화"). 옵션 볼륨도 같은 버스를 쓰므로
# **둘을 더해서 쓴다** — 덕킹이 사용자 볼륨을 덮으면 복귀 시 설정이 사라진다.
var _bgm_option_db := 0.0
var _duck_db := 0.0
var _duck_return_sec := 0.0
var _duck_hold := false

# **뮤트도 합성해야 한다.** 볼륨 0(O15)과 일시정지가 같은 뮤트 플래그를 쓰므로, 한쪽이 단독으로
# 쓰면 다른 쪽을 지운다 — 실측: SFX 볼륨 0 인 상태로 일시정지 후 재개하면 재개가 **사용자가 끈
# 소리를 되살린다**. 덕킹과 옵션 볼륨을 더해 쓰는 것과 같은 이유다.
var _sfx_option_muted := false
var _paused := false

# 스트림 부재 관측 — **1회만** 남긴다. BGM 17스템이 병행 생성 중이라 부재는 예정 상태이고,
# 매 발화마다 짖으면 로그가 무용해진다. 배열은 기계 관측 지점이다(검사가 읽는다).
var missing_streams: Array = []


# `host` = 플레이어를 매달 트리 노드. **없으면 실물 재생기를 세울 수 없다** —
# 그 경로에서 무음 폴백이 서는 것은 플래그가 아니라 구조다(`RunSession.setup` 참조).
func setup(game_data: GameData, host: Node) -> void:
	_data = game_data
	_host = host
	_build_buses()
	_crossfade_sec()   # 값 창구 존재 확인을 적재 시점에 당긴다
	var channels := _data.param_int("param_audio_virtual_channels")
	for index in range(channels):
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		_host.add_child(player)
		player.finished.connect(_on_sfx_finished.bind(index))
		_sfx_pool.append(player)
		_sfx_ids.append("")
	_jingle_player = AudioStreamPlayer.new()
	_jingle_player.bus = BUS_SFX   # 징글 = SFX 버스 (D11 §4.1 — 트랙 계상 외·볼륨 계층 불증가)
	_host.add_child(_jingle_player)
	for deck in range(2):
		var base := AudioStreamPlayer.new()
		base.bus = BUS_BGM
		var tension := AudioStreamPlayer.new()
		tension.bus = BUS_BGM
		_host.add_child(base)
		_host.add_child(tension)
		_decks.append({"track": "", "base": base, "tension": tension, "gain": 0.0, "target": 0.0})
	_pump = load("res://ui/audio/audio_pump.gd").new()
	_pump.output = self
	_host.add_child(_pump)


# **검사 이음매.** 페이드를 결정적으로 재려면 엔진이 같은 프레임에 델타를 또 주면 안 된다 —
# 펌프를 떼면 `advance_fades()` 가 검사가 주는 값만 받는다(디스패처 `clock_override_msec` 동형).
func detach_pump() -> void:
	if _pump != null and _pump.get_parent() != null:
		_pump.get_parent().remove_child(_pump)


func bind_dispatcher(target: AudioDispatcher) -> void:
	_dispatcher_ref = weakref(target)


# ── 버스 3계 ──
#
# **멱등이다.** 이미 서 있으면 다시 만들지 않는다 — 세션이 두 번 열리는 경로(테스트·타이틀 복귀)
# 에서 버스가 중복 생성되면 send 사슬이 어긋나고, 그 어긋남은 조용하다.
func _build_buses() -> void:
	for bus_name in [BUS_BGM, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		# 두 버스는 Master 로 흘러야 한다 — O13 이 마스터 하나로 전체를 잡는 근거다.
		AudioServer.set_bus_send(index, BUS_MASTER)


# ── SFX ──
func play_sfx(sfx_id: String, _priority: String) -> void:
	_start(sfx_id, "sfx")


func play_jingle(jingle_id: String) -> void:
	var stream := _stream(jingle_id, "jingle")
	if stream == null:
		_release(jingle_id)
		return
	_jingle_player.stream = stream
	_jingle_player.play()


# 컬링 = 즉시 정지 (D11 §6.3 — 걷어낸 발음은 페이드하지 않는다. 페이드는 그 자체로 소리다).
func cull_sfx(sfx_id: String) -> void:
	for index in range(_sfx_pool.size()):
		if String(_sfx_ids[index]) != sfx_id:
			continue
		_sfx_ids[index] = ""
		(_sfx_pool[index] as AudioStreamPlayer).stop()
		return


func _start(sfx_id: String, channel: String) -> void:
	var stream := _stream(sfx_id, channel)
	if stream == null:
		# 실물 부재 = 무음. 다만 보이스 점유는 풀어 준다 — 안 풀면 채널이 영구 잠긴다
		# (무음 폴백이 `release_voice` 를 부르는 것과 같은 이유 — IMPL-149 실측).
		_release(sfx_id)
		return
	var slot := _free_slot()
	if slot < 0:
		# 상한은 코어가 이미 걸었으므로 여기 오는 것은 계약 위반이다 — 조용히 흘리지 않는다.
		push_error("GameAudioOutput: sfx pool exhausted for '%s' (pool %d)" % [sfx_id, _sfx_pool.size()])
		_release(sfx_id)
		return
	_sfx_ids[slot] = sfx_id
	var player := _sfx_pool[slot] as AudioStreamPlayer
	player.stream = stream
	player.play()


func _free_slot() -> int:
	for index in range(_sfx_pool.size()):
		if String(_sfx_ids[index]) == "":
			return index
	return -1


func _on_sfx_finished(index: int) -> void:
	var sfx_id := String(_sfx_ids[index])
	if sfx_id == "":
		return
	_sfx_ids[index] = ""
	_release(sfx_id)


# ── BGM ──
func play_bgm(track_id: String, crossfade_sec: float) -> void:
	var incoming := 1 - _active_deck
	var stream := _bgm_base_stream(track_id)
	var deck: Dictionary = _decks[incoming]
	deck["track"] = track_id
	(deck["base"] as AudioStreamPlayer).stream = stream
	# 긴장 스템은 있으면 쓰고 없으면 base 만 돈다 — 2레이어는 BGM-03~07 전속이다(D11 §4.3).
	(deck["tension"] as AudioStreamPlayer).stream = _stream_optional(track_id + "-b", "bgm")
	deck["gain"] = 0.0
	deck["target"] = 1.0
	if stream != null:
		(deck["base"] as AudioStreamPlayer).play()
		var tension_stream: Variant = (deck["tension"] as AudioStreamPlayer).stream
		if tension_stream != null:
			(deck["tension"] as AudioStreamPlayer).play()
	_decks[_active_deck]["target"] = 0.0
	_active_deck = incoming
	_apply_bgm_gains()
	# 크로스페이드 시간이 0 이면 즉시 전이다 — 프레임을 기다리지 않고 여기서 접는다.
	if crossfade_sec <= 0.0:
		advance_fades(0.0)


func stop_bgm() -> void:
	for deck in _decks:
		var row: Dictionary = deck
		row["gain"] = 0.0
		row["target"] = 0.0
		row["track"] = ""
		(row["base"] as AudioStreamPlayer).stop()
		(row["tension"] as AudioStreamPlayer).stop()
	_tension_gain = 0.0
	_tension_target = 0.0


# 긴장 레이어 = **볼륨 온오프**다 (D11 §4.4 · D12 §10.3 — 트랙 교체가 아니다).
# 동일 길이·박 동기를 전제하므로 동시 재생 중인 스템의 게인만 움직인다.
func set_bgm_tension(on: bool) -> void:
	_tension_target = 1.0 if on else 0.0


func duck_bgm(db: float, return_sec: float) -> void:
	_duck_db = db
	_duck_return_sec = return_sec
	_duck_hold = true
	_apply_bgm_bus()


# ── 일시정지·볼륨 ──
func set_paused(on: bool) -> void:
	_paused = on
	_apply_sfx_mute()


func _apply_sfx_mute() -> void:
	var index := AudioServer.get_bus_index(BUS_SFX)
	if index >= 0:
		AudioServer.set_bus_mute(index, _sfx_option_muted or _paused)


func apply_volumes(master: int, bgm: int, sfx: int) -> void:
	_apply_bus_volume(BUS_MASTER, master)
	_sfx_option_muted = sfx <= 0
	_apply_bus_volume(BUS_SFX, sfx)
	# BGM 버스는 옵션과 덕킹이 함께 쓰므로 옵션분을 기억해 두고 합으로 쓴다.
	_bgm_option_db = _volume_db(bgm)
	_apply_bus_volume(BUS_BGM, bgm)


# 0 = 뮤트 · 100 = 0dB · 지각 선형 로그 커브 (D12 §10.1 명문). `linear_to_db()` 가 그 커브이고
# **0 은 −inf 라 dB 로 표현되지 않는다** — 그래서 0 만 뮤트 플래그로 가른다(문면 그대로).
func _apply_bus_volume(bus_name: String, value: int) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	# SFX 는 일시정지와 뮤트를 공유하므로 합성 지점을 거친다(단독 대입 금지).
	if bus_name == BUS_SFX:
		_apply_sfx_mute()
	else:
		AudioServer.set_bus_mute(index, value <= 0)
	if value <= 0:
		return
	var db := _volume_db(value)
	if bus_name == BUS_BGM:
		db += _duck_db if _duck_hold else 0.0
	AudioServer.set_bus_volume_db(index, db)


func _volume_db(value: int) -> float:
	return linear_to_db(float(value) / 100.0)


func _apply_bgm_bus() -> void:
	var index := AudioServer.get_bus_index(BUS_BGM)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, _bgm_option_db + (_duck_db if _duck_hold else 0.0))


# ── 페이드 진행 ──
#
# 트랙 게인·레이어 게인·덕킹 복귀가 같은 지점에서 움직인다. 갈라 두면 한 프레임 안에서
# 서로 다른 시각의 값이 섞인다(트랙은 새 값, 레이어는 헌 값).
func advance_fades(delta: float) -> void:
	var span := _crossfade_sec()
	var step := 1.0 if span <= 0.0 else delta / span
	for deck in _decks:
		var row: Dictionary = deck
		var gain := float(row["gain"])
		var target := float(row["target"])
		if gain < target:
			gain = minf(target, gain + step)
		elif gain > target:
			gain = maxf(target, gain - step)
		row["gain"] = gain
		if gain <= 0.0 and target <= 0.0 and String(row["track"]) != "":
			# 다 빠진 데크는 멈춘다 — 0 게인으로 계속 돌면 보이스와 디코더를 붙잡는다.
			(row["base"] as AudioStreamPlayer).stop()
			(row["tension"] as AudioStreamPlayer).stop()
			row["track"] = ""
	if _tension_gain < _tension_target:
		_tension_gain = minf(_tension_target, _tension_gain + step)
	elif _tension_gain > _tension_target:
		_tension_gain = maxf(_tension_target, _tension_gain - step)
	_apply_bgm_gains()
	if _duck_hold and _duck_return_sec > 0.0 and delta > 0.0:
		# 복귀는 즉시가 아니라 시간이다(D13 "복귀 0.3초"). 경과분만 되돌린다.
		_duck_db += absf(_duck_db) * (delta / _duck_return_sec)
		if _duck_db >= 0.0:
			_duck_db = 0.0
			_duck_hold = false
		_apply_bgm_bus()


func _apply_bgm_gains() -> void:
	for deck in _decks:
		var row: Dictionary = deck
		var gain := float(row["gain"])
		_set_player_gain(row["base"] as AudioStreamPlayer, gain)
		_set_player_gain(row["tension"] as AudioStreamPlayer, gain * _tension_gain)


# 게인 0 = 정지. `linear_to_db(0)` 은 −inf 이고 그것을 볼륨에 쓰면 플랫폼별 거동이 갈린다 —
# 코드에 −80 같은 바닥값을 적지 않기 위해서도 정지가 정확하다(무음의 유일 정의).
func _set_player_gain(player: AudioStreamPlayer, gain: float) -> void:
	if gain <= 0.0:
		if player.playing:
			player.stop()
		return
	player.volume_db = linear_to_db(gain)
	if not player.playing and player.stream != null:
		player.play()


# ── 스트림 조회 ──
#
# 부재는 오류가 아니다 — BGM 17스템이 병행 조달 중이고, 유입되면 **코드 무변경으로** 켜진다.
# 다만 조용히 넘기지 않는다: 사람에게 1회 `push_error`(ARCH 가 `godot/ui` 에서 `push_warning`·
# `print` 를 금칙에 두고 `push_error` 만 값 누락 보고 용도로 남겼다 — IMPL-268 과 같은 자리),
# 기계에 `missing_streams`.
func _stream(sfx_id: String, channel: String) -> AudioStream:
	var path := _path_of(sfx_id, channel)
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	if not missing_streams.has(sfx_id):
		missing_streams.append(sfx_id)
		# 문면은 ASCII 전속 — V4 는 코드 내 한글 리터럴을 금칙에 둔다(표시 문자열과 구분하지 않는다).
		push_error("GameAudioOutput: stream not found '%s' (%s) — silent" % [sfx_id, path])
	return null


# 긴장 스템처럼 **있으면 쓰고 없으면 안 쓰는** 것 — 부재가 보고 대상이 아니다.
func _stream_optional(sfx_id: String, channel: String) -> AudioStream:
	var path := _path_of(sfx_id, channel)
	return load(path) as AudioStream if ResourceLoader.exists(path) else null


# **BGM 은 파일 하나가 아닐 수 있다.** 2레이어 트랙(D11 §4.3 — 레이스 BGM-03~07)은 기본 스템이
# `_a` 로 오고 긴장 스템이 `_b` 로 온다. 단층 트랙은 접미사 없이 온다. 실측(18스템 유입분):
# BGM-01·02·08~13 = 무접미 8건 / BGM-03~07 = `_a`/`_b` 짝 5건 — D11 §4.3 의 2레이어 집합과 정확히 같다.
#
# 그래서 **둘 다 받는다.** 무접미를 먼저 보고 없으면 `_a` 를 본다 — 어느 관례로 와도 성립하며,
# 무접미만 보면 레이스 트랙 5개가 조용히 무음이 된다(초판이 그랬다).
func _bgm_base_stream(track_id: String) -> AudioStream:
	var layered := _stream_optional(track_id + "-a", "bgm")
	if layered != null:
		return layered
	return _stream(track_id, "bgm")


func _path_of(sfx_id: String, channel: String) -> String:
	return "%s%s.%s" % [DIRS[channel], sfx_id.to_lower().replace("-", "_"), EXT[channel]]


func _crossfade_sec() -> float:
	return _data.param("param_audio_crossfade_sec")


func _release(sfx_id: String) -> void:
	if _dispatcher_ref == null:
		return
	var dispatcher := _dispatcher_ref.get_ref() as AudioDispatcher
	if dispatcher != null:
		dispatcher.release_voice(sfx_id)


# ── 검사용 되읽기 ──
#
# **설정 호출의 성공은 증거가 아니다.** 버스·볼륨은 `AudioServer` 에서 직접 되읽고, 여기 있는
# 것은 서버가 갖지 않는 것(풀 점유·데크 게인)뿐이다.
func sfx_pool_size() -> int:
	return _sfx_pool.size()


func active_sfx_count() -> int:
	var total := 0
	for id in _sfx_ids:
		if String(id) != "":
			total += 1
	return total


func deck_gain(index: int) -> float:
	return float(_decks[index]["gain"])


func active_deck() -> int:
	return _active_deck


func active_track() -> String:
	return String(_decks[_active_deck]["track"])


func tension_gain() -> float:
	return _tension_gain


func duck_offset_db() -> float:
	return _duck_db
