# AUDIO-A — 오디오 **실물** 검사 (D11 §2.11·§5 · D12 §10.1 · 대장 §5.1).
#
# 왜 별도 스위트인가 (거처 판단 — 발주 §4 "run_validators.gd 편입" 에 대한 가감 근거):
#   `run_validators.gd` 는 **프로젝트리스 실행**이 설계 전제다(자기 완결형 · `--path .` = 리포 루트).
#   그 문맥에서는 `res://` 가 godot 프로젝트가 아니어서 **임포트된 리소스를 적재할 수 없다.**
#   그런데 파일럿이 밟은 함정의 교훈은 *".import 문면은 증거가 아니다 — 런타임 되읽기만이 증거"* 였다.
#   그래서 축을 둘로 갈랐다:
#     · 파일·선언 축(파일명 실재 · WAV 헤더 3항 · compress/loop 선언 · 길이 상한) = `run_validators.gd` AUD
#     · **런타임 되읽기 축(실제 AudioStreamWAV 값) = 이 스위트** — 프로젝트 문맥이 필요하다
#   둘 다 상시 게이트다(AUD = TL-1 검증기 · 여기 = TL-3 `run_tests.sh` 등록·검사 수 하한).
#
# 파일럿 일회 프로브(`sfx_import_probe.gd` · IMPL-245)를 대체한다 — 표본 8식이 아니라 전량 68식이다.
extends SceneTree

const SFX_DIR := "res://assets/audio/sfx/"

# 루프 6식 (대장 §5.1 명시) — 이 목록 밖은 전부 LOOP_DISABLED 여야 한다.
# "루프여야 하는데 아닌 것"과 "루프면 안 되는데 루프인 것"을 같은 검사가 본다.
const LOOP_IDS := ["se_r02", "se_t03", "se_u15", "amb_01", "amb_04", "amb_05"]

# L군 길이 상한 (D13 확정 기준값 — D11 §2.5 ② 스팅 3식)
const LENGTH_CAP := {"se_l1": 0.8, "se_l2": 1.5, "se_l3": 2.5}

var _checked := 0
var _failures := 0


func _init() -> void:
	var ids := _expected_ids()
	if ids.is_empty():
		print("AUDIO_ASSET_FAIL sound_map.csv 에서 sfx 행을 읽지 못했다")
		quit(1)
		return
	var fmt_name := {0: "PCM8", 1: "PCM16", 2: "IMA_ADPCM", 3: "QOA"}
	var loop_name := {0: "DISABLED", 1: "FORWARD", 2: "PINGPONG", 3: "BACKWARD"}
	for id in ids:
		var stream := load(SFX_DIR + id + ".wav") as AudioStreamWAV
		if stream == null:
			_fail("%s: AudioStreamWAV 적재 실패 (파일 부재·임포트 실패·타입 불일치)" % id)
			continue
		# ① 포맷 3항 — 임포터 설정이 아니라 **적재된 리소스**의 값이다.
		#    compress/mode=0(무압축) 이 실효했는지는 format 이 PCM16 인지로만 알 수 있다
		#    (QOA 로 임포트되면 여기서 format 이 3 으로 나온다).
		_ok("%s format=%s" % [id, String(fmt_name.get(stream.format, "?"))],
			stream.format == AudioStreamWAV.FORMAT_16_BITS)
		_ok("%s mix_rate=%d" % [id, stream.mix_rate], stream.mix_rate == 44100)
		_ok("%s mono" % id, not stream.stereo)
		# ② 루프 — 임포터 열거가 런타임 상수와 한 칸 어긋나므로(IMPL-245 등재 함정)
		#    선언을 읽는 것으로는 판정이 성립하지 않는다.
		var want_loop: int = AudioStreamWAV.LOOP_FORWARD if id in LOOP_IDS else AudioStreamWAV.LOOP_DISABLED
		_ok("%s loop=%s (기대 %s)" % [id, String(loop_name.get(stream.loop_mode, "?")),
			String(loop_name.get(want_loop, "?"))], stream.loop_mode == want_loop)
		if id in LOOP_IDS:
			_ok("%s 루프 구간 비지 않음 (begin=%d end=%d)" % [id, stream.loop_begin, stream.loop_end],
				stream.loop_end > stream.loop_begin)
			# 루프 6식은 되읽기 값을 **통과해도 찍는다** — 함정을 밟은 자리라
			# "검사가 있었다"가 로그로 남아야 한다(경고형 검사가 죽는 것과 같은 축).
			print("  [LOOP] %s loop=%s begin=%d end=%d len=%.3fs" % [id,
				String(loop_name.get(stream.loop_mode, "?")), stream.loop_begin,
				stream.loop_end, stream.get_length()])
		# ③ 길이 상한 — 선언된 항목만.
		if LENGTH_CAP.has(id):
			var cap: float = float(LENGTH_CAP[id])
			_ok("%s 길이 %.3fs <= 상한 %.1fs" % [id, stream.get_length(), cap],
				stream.get_length() <= cap)
		# ④ 무음 아님 — 임포트가 성공해도 데이터가 비면 소리가 없다.
		_ok("%s 데이터 비지 않음 (%d B)" % [id, stream.data.size()], stream.data.size() > 0)
	print("")
	# 검사 수 하한 — 68식 × 5축 + 루프 6 + 길이 3 = 349. 스위트가 쪼그라들면 통과가 아니다.
	if _checked < 340:
		print("AUDIO_ASSET_FAIL checks=%d < 하한 340 (목록 축소·적재 실패 의심)" % _checked)
		quit(1)
		return
	if _failures == 0:
		print("AUDIO_ASSET_PASS checks=%d" % _checked)
		quit(0)
	else:
		print("AUDIO_ASSET_FAIL failures=%d checks=%d" % [_failures, _checked])
		quit(1)


# 목록을 손으로 적지 않는다 — `sound_map.csv` 의 channel=sfx 행에서 파일명을 도출한다.
# 손으로 적은 목록은 표와 갈릴 수 있고, 갈리면 검사가 표를 지키지 못한다.
# 계수 68 은 D11 §2.11 확정 기준값이므로 **상수로 대조**한다(표만 보면 행이 지워진 것을 못 본다).
func _expected_ids() -> Array:
	var file := FileAccess.open("res://data/tables/sound_map.csv", FileAccess.READ)
	if file == null:
		return []
	var header := file.get_csv_line()
	var i_sfx := header.find("sfx_id")
	var i_ch := header.find("channel")
	if i_sfx < 0 or i_ch < 0:
		return []
	var ids: Array = []
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() <= maxi(i_sfx, i_ch):
			continue
		if row[i_ch] != "sfx":
			continue
		ids.append(row[i_sfx].to_lower().replace("-", "_"))
	file.close()
	_ok("sound_map channel=sfx 행 %d = D11 §2.11 확정 68식" % ids.size(), ids.size() == 68)
	return ids


func _ok(label: String, condition: bool) -> void:
	_checked += 1
	if not condition:
		_failures += 1
		print("  [FAIL] %s" % label)


func _fail(message: String) -> void:
	_checked += 1
	_failures += 1
	print("  [FAIL] %s" % message)
