extends SceneTree

# 임포트 결과 실측 — WAV 임포트 설정이 실제 AudioStreamWAV 에 반영됐는지 본다.
# **파일럿 전용 일회 프로브(IMPL-243)이지 항구 검사가 아니다** — 오디오 기계 검사는
# 표본 8식이 아니라 전량 유입 개시 회차에 설계한다(총괄 기안 §7.3 · ANCH 표본 확대 전례).
func _init() -> void:
	var ids := ["se_r01", "se_r02", "se_r03", "se_r04", "se_r05", "se_i01", "se_i10", "se_u01"]
	var fmt_name := {0: "PCM8", 1: "PCM16", 2: "IMA_ADPCM", 3: "QOA"}
	var loop_name := {0: "DISABLED", 1: "FORWARD", 2: "PINGPONG", 3: "BACKWARD"}
	var fails := 0
	for id in ids:
		var path := "res://assets/audio/sfx/%s.wav" % id
		var s := load(path) as AudioStreamWAV
		if s == null:
			print("FAIL %s: 적재 실패" % id)
			fails += 1
			continue
		print("%s format=%s mix_rate=%d stereo=%s loop=%s begin=%d end=%d len=%.3fs" % [
			id, String(fmt_name.get(s.format, "?")), s.mix_rate, str(s.stereo),
			String(loop_name.get(s.loop_mode, "?")), s.loop_begin, s.loop_end, s.get_length()])
		if s.format != AudioStreamWAV.FORMAT_16_BITS:
			print("  FAIL %s: format != PCM16" % id)
			fails += 1
		if s.mix_rate != 44100:
			print("  FAIL %s: mix_rate != 44100" % id)
			fails += 1
		if s.stereo:
			print("  FAIL %s: 스테레오 — 모노여야 한다" % id)
			fails += 1
		var want_loop: int = AudioStreamWAV.LOOP_FORWARD if id == "se_r02" else AudioStreamWAV.LOOP_DISABLED
		if s.loop_mode != want_loop:
			print("  FAIL %s: loop_mode %d != 기대 %d" % [id, s.loop_mode, want_loop])
			fails += 1
		if id == "se_r02" and s.loop_end <= s.loop_begin:
			print("  FAIL se_r02: 루프 구간이 비었다")
			fails += 1
	print("SFX_IMPORT_PROBE %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
