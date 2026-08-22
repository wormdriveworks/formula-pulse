# 오디오 디스패처 (D12 §10.2 · §5.10 — DoD #16·#28~#31).
#
# **사운드의 유일 발화 경로.** 호출부는 게임 이벤트 id만 던지고, 무엇이 울릴지는 `sound_map`
# 표가 정한다(D11 §1.4 이벤트 결속 원칙 — 씬 컷·화면에 결속하지 않는다). 코드가 SFX id를
# 직접 들고 재생하는 경로를 두지 않는 것이 C-A2(씬 컷 전용 SFX 신설 차단)의 구조적 보장이다.
#
# 정책 4종을 여기서 강제한다 — 호출부가 지키는 규약이 아니라 **호출부가 어겨도 통과 못 하는** 층:
#   ① 봉인 (불변규칙 5 · D11 §1.3 R-a) — 릴 정지 연출 완료 전 결과 상관 사운드 전면 차단
#   ② 재트리거 게이트 (D11 §6.3) — 동일 SFX 최소 간격
#   ③ 가상 채널 상한·컬링 (D11 §6.3) — 초과 시 P3부터
#   ④ P1 보호 (D11 §6.3) — 정보음 재생 중 P3 신규 발음 억제
#
# 값은 전량 D13 창구(core_params 경유) — 이 파일은 수치를 보유하지 않는다.
class_name AudioDispatcher
extends RefCounted

const CHANNEL_SFX := "sfx"
const CHANNEL_BGM := "bgm"
const CHANNEL_JINGLE := "jingle"

var data: GameData
var output: AudioOutput

# 테스트용 시계 주입 — 음수면 실시간을 쓴다. 재트리거 게이트는 시간 축 정책이라
# 주입 없이는 결정적으로 검사할 수 없다 (GameData.tables_override_dir 와 같은 성격의 구멍).
var clock_override_msec := -1

var _seal_open := false
# **봉인 차단 기록은 건수만 남긴다.** 어떤 사운드가 막혔는지를 남기면 그 자체가
# 결과 상관 신호의 디버그 노출 경로가 된다 (불변규칙 5는 디버그 오버레이를 명시 포함).
var _seal_refusals := 0
var _voices: Array = []            # 재생 중 보이스 [{sfx_id, priority}] — 표현 층이 release 로 비운다
var _last_fire_msec: Dictionary = {}   # sfx_id -> 마지막 발화 시각
var _bgm_track := ""
var _tension := false
var _paused := false
# 발화 기록 — 검사·회귀 전용. 봉인 창 중에는 결과 상관 사운드가 애초에 들어오지 못한다.
var fired: Array = []


func setup(game_data: GameData, audio_output: AudioOutput = null) -> void:
	data = game_data
	# 싱크 미지정 = 무음 폴백. 사운드 실물이 없는 단계의 정상 상태이며 에러가 아니다.
	output = audio_output if audio_output != null else AudioOutput.new()


# ── 봉인 창 (D12 §6.3 · D11 §1.3) ──
# 스핀 커밋(T2)에서 열고 릴 정지 연출 완료 시점에 닫는다. 열려 있는 동안
# `seal_gated` 행은 어떤 경로로도 발화하지 않는다 — 매치 예고음이 곧 결과 예고다.
func open_seal() -> void:
	_seal_open = true


func close_seal() -> void:
	_seal_open = false


func seal_open() -> bool:
	return _seal_open


func seal_refusal_count() -> int:
	return _seal_refusals


# 이벤트 발화 — 발화된 sound_* 행 id 배열을 돌려준다 (미등재 이벤트 = 빈 배열, 정상).
func emit(event_id: String) -> Array:
	if data == null:
		return []
	var result: Array = []
	for row in data.sounds_for(event_id):
		if _fire(row):
			result.append(String(row["id"]))
	return result


func _fire(row: Dictionary) -> bool:
	var sfx_id := String(row["sfx_id"])
	var channel := String(row["channel"])
	var priority := String(row["priority"])
	# ① 봉인 — 최우선. 다른 어떤 판정보다 먼저 걸러야 "게이트에 걸려서 안 울렸다"가
	#    봉인 준수의 근거로 오인되지 않는다.
	if _seal_open and CsvTable.to_int(String(row["seal_gated"])) == 1:
		_seal_refusals += 1
		return false
	if channel == CHANNEL_BGM:
		return _play_bgm(sfx_id)
	# ② 재트리거 게이트
	var now := _now_msec()
	var gate_sec := _gate_sec(row)
	if _last_fire_msec.has(sfx_id) and now - int(_last_fire_msec[sfx_id]) < int(round(gate_sec * 1000.0)):
		return false
	# ④ P1 보호 — 정보음 재생 중 장식성 신규 발음 억제 (마스킹 방지)
	if priority == "P3" and _has_active_priority("P1"):
		return false
	# ③ 가상 채널 상한 — 초과 시 P3부터 컬링. 걷어낼 P3가 없으면 신규 발음을 포기한다
	#    (P1·P2를 밀어내지 않는다 — 우선 3층의 방향이 뒤집히면 안 된다).
	var cap := data.param_int("param_audio_virtual_channels")
	if _voices.size() >= cap and not _cull_one():
		return false
	_last_fire_msec[sfx_id] = now
	_voices.append({"sfx_id": sfx_id, "priority": priority})
	fired.append(sfx_id)
	if channel == CHANNEL_JINGLE:
		output.play_jingle(sfx_id)
	else:
		output.play_sfx(sfx_id, priority)
	# 덕킹 — L2·L3 스팅과 징글 (D11 §6.3). 값은 D13 별첨A §8.3.
	if channel == CHANNEL_JINGLE or sfx_id == "SE-L2" or sfx_id == "SE-L3":
		output.duck_bgm(data.param("param_audio_duck_db"), data.param("param_audio_duck_return_sec"))
	return true


func _play_bgm(track_id: String) -> bool:
	if _bgm_track == track_id:
		return false
	_bgm_track = track_id
	fired.append(track_id)
	output.play_bgm(track_id, data.param("param_audio_crossfade_sec"))
	# 트랙이 바뀌면 긴장 레이어는 꺼진 상태에서 시작한다 (레이어는 트랙에 종속).
	_tension = false
	output.set_bgm_tension(false)
	return true


# 표현 층이 스트림 종료를 알린다. 지속 시간을 코드가 추정하지 않는 이유 —
# SFX 길이는 에셋의 성질이고 D13에 없다 (임의 기입 금지).
func release_voice(sfx_id: String) -> void:
	for index in range(_voices.size()):
		if String(_voices[index]["sfx_id"]) == sfx_id:
			_voices.remove_at(index)
			return


func active_voice_count() -> int:
	return _voices.size()


func current_bgm() -> String:
	return _bgm_track


func tension_on() -> bool:
	return _tension


# 긴장 레이어 (D11 §4.3 — 트리거 3종: 듀얼 중 / 타이머 임박 구간 / 최종 랩).
# 전부 상태 전이 동기다 — 실시간 오디오 추적을 두지 않는다(불변규칙 8 정합).
func set_tension(on: bool) -> void:
	if _tension == on:
		return
	_tension = on
	output.set_bgm_tension(on)


# 일시정지 (D11 §4.3 — BGM 유지·SFX 뮤트). **정책이 아니라 통로다** — 뮤트는 표현 층이 하고
# 디스패처는 그 호출이 통과하는 유일한 창구를 유지한다(호출부가 `output` 을 직접 쥐지 않는다).
func set_paused(on: bool) -> void:
	if _paused == on:
		return
	_paused = on
	output.set_paused(on)


func paused() -> bool:
	return _paused


# 볼륨 옵션 → 버스 (D12 §10.1 O13~O15 직결). 값 해석은 표현 층 소관이다.
func apply_volume_options(master: int, bgm: int, sfx: int) -> void:
	output.apply_volumes(master, bgm, sfx)


# 리타이어 = BGM 즉시 정지 → JG-03 (D11 §4.3 전이 규칙표). 순서가 규칙이므로 코드가 갖는다.
func stop_bgm() -> void:
	if _bgm_track == "":
		return
	_bgm_track = ""
	_tension = false
	output.stop_bgm()


func _gate_sec(row: Dictionary) -> float:
	var override_id := String(row.get("retrigger_param", "")).strip_edges()
	if override_id != "":
		return data.param(override_id)
	return data.param("param_audio_retrigger_gate_sec")


func _has_active_priority(priority: String) -> bool:
	for voice in _voices:
		if String(voice["priority"]) == priority:
			return true
	return false


# 가장 오래된 P3 1건을 걷어낸다 (D11 §6.3 "초과 시 P3부터 컬링").
func _cull_one() -> bool:
	for index in range(_voices.size()):
		if String(_voices[index]["priority"]) == "P3":
			output.cull_sfx(String(_voices[index]["sfx_id"]))
			_voices.remove_at(index)
			return true
	return false


func _now_msec() -> int:
	return clock_override_msec if clock_override_msec >= 0 else Time.get_ticks_msec()
