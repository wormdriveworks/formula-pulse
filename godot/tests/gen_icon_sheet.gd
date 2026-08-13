# 아이콘 대조 시트 생성 (눈 검증 · G-2 혼동쌍 사전 점검용).
#
#   <console.exe> --headless --path godot --script tests/gen_icon_sheet.gd -- <출력 절대경로> [배율]
#
# 32×32 셀은 육안 대조가 어렵다. 정수 배율로만 확대해(니어리스트 — D12 §9.1 · D10 §2.2 믹셀 금지)
# 한 장에 늘어놓는다. **확대는 검토용이며 게임은 ×3으로 표시한다** — G-2 실측은 실기 렌더 빌드에서
# 96×96 표시 상태로 해야 하고 이 시트로 대신할 수 없다.
extends SceneTree

const ICON_DIR := "res://assets/ui/icons/"
const CELL := 32
const GAP := 4

# 행 = 분류군. G-2는 심볼 6분류의 혼동 행렬을 요구하므로 첫 행에 6종을 나란히 둔다.
const ROWS := [
	["symbol_slipstream", "symbol_braking", "symbol_line", "symbol_trouble", "symbol_chance", "symbol_pulse"],
	["attr_straight", "attr_technical", "attr_sweeper", "attr_hazard", "attr_battle_zone", "attr_pulse_section"],
	["currency_credit", "currency_data", "speaker_relay", "speaker_filler"],
]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("SHEET_FAIL 출력 경로 미지정")
		quit(1)
		return
	var out_path := args[0]
	var scale := 6 if args.size() < 2 else int(args[1])

	var cols := 0
	for row in ROWS:
		cols = maxi(cols, row.size())
	var cell_px := CELL * scale
	var width := cols * cell_px + (cols + 1) * GAP
	var height := ROWS.size() * cell_px + (ROWS.size() + 1) * GAP

	var sheet := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	sheet.fill(UiPalette.BG_DEEP)

	for row_index in range(ROWS.size()):
		var row: Array = ROWS[row_index]
		for col_index in range(row.size()):
			var icon := _load_icon(String(row[col_index]))
			if icon == null:
				continue
			icon.resize(cell_px, cell_px, Image.INTERPOLATE_NEAREST)
			var at := Vector2i(
				GAP + col_index * (cell_px + GAP),
				GAP + row_index * (cell_px + GAP)
			)
			sheet.blend_rect(icon, Rect2i(Vector2i.ZERO, icon.get_size()), at)

	if sheet.save_png(out_path) != OK:
		printerr("SHEET_FAIL 저장 실패: %s" % out_path)
		quit(1)
		return
	print("SHEET_OK %dx%d %s" % [width, height, out_path])
	quit(0)


# 임포트 캐시(.godot/imported/)를 거치지 않고 원본 PNG를 직접 읽는다 —
# `load()`는 갱신 전 캐시를 돌려주므로 방금 다시 그린 아이콘이 시트에 반영되지 않는다(실측).
func _load_icon(base_name: String) -> Image:
	var path := ProjectSettings.globalize_path("%s%s.png" % [ICON_DIR, base_name])
	if not FileAccess.file_exists(path):
		printerr("SHEET_WARN 아이콘 없음: %s" % path)
		return null
	return Image.load_from_file(path)
