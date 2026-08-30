# 익스포트 팩 검침 — **선언이 아니라 산출물을 읽는다.**
#
# `export_presets.cfg` 의 `exclude_filter` 는 *의도*이고, 팩에 무엇이 들어갔는지는 *결과*다.
# 이 둘은 갈릴 수 있다(필터 문법 오타·엔진 판정 변화). 그래서 검사기는 선언을 보고
# 이 검침기는 **엔진이 실제로 담은 것**을 본다 — 두 축이 짝이다.
#
# 사용: godot --headless --path tools/export/pck_probe --script probe.gd -- <pck> <출력경로>
extends SceneTree


func _init() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.size() < 2:
		print("PROBE_FAIL 인자 부족 — <pck> <출력경로>")
		quit(2)
		return
	var pck := String(argv[0])
	var out_path := String(argv[1])
	# **`replace_files=false`** — 이 프로젝트에는 겹칠 파일이 없지만, 덮어쓰기를 켜 두면
	# 언젠가 검침기 자신의 파일이 목록에 섞여 들어와도 알아채지 못한다.
	if not ProjectSettings.load_resource_pack(pck, false):
		print("PROBE_FAIL 팩 적재 실패 — %s" % pck)
		quit(2)
		return
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	if out == null:
		print("PROBE_FAIL 출력 열기 실패 — %s" % out_path)
		quit(2)
		return
	var count := 0
	var total := 0
	# 검침기 자신의 파일은 목록에서 뺀다 — 팩의 내용만 세야 한다.
	var own := {"res://project.godot": true, "res://probe.gd": true, "res://probe.gd.uid": true}
	var pending: Array = ["res://"]
	while not pending.is_empty():
		var dir_path := String(pending.pop_back())
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := dir_path + ("" if dir_path.ends_with("/") else "/") + entry
			if dir.current_is_dir():
				pending.append(full)
			elif not own.has(full):
				var f := FileAccess.open(full, FileAccess.READ)
				var size := int(f.get_length()) if f != null else -1
				out.store_line("%d\t%s" % [size, full])
				count += 1
				total += maxi(size, 0)
			entry = dir.get_next()
		dir.list_dir_end()
	out.close()
	print("PROBE_OK files=%d bytes=%d" % [count, total])
	quit(0)
