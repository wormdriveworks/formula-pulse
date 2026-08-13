# UI 아이콘 플레이스홀더 생성기 (D10 §5.1·§5.2·§5.3·§5.5 — 사용자 확정: 플레이스홀더 자체 생성).
#
#   <console.exe> --headless --path godot --script tests/gen_placeholder_icons.gd
#
# **이것은 아트가 아니다.** D10이 확정한 **도상 어휘·셀 규격·이중 부호화**를 지켜 자리를 만드는
# 기하 도형이며, 도트 원도가 유입되면 같은 경로·같은 파일명으로 교체된다(참조부 무변경).
# 실물 유입 시 이 생성기는 폐기 대상이다.
#
# 지키는 것:
#   · 셀 32×32 (D10 §5.1) — 표시 96×96 (×3 정수 배율)
#   · 색 + 도상 이중 부호화 — 색을 제거해도 실루엣만으로 분류가 갈린다 (D10 §5.1 구속)
#   · 도상 어휘 = 텔레메트리·모터스포츠 기호계. 판타지·주화·보석류 금지 (ToF 비유사 — D10 §9)
#   · 단일 모티프·고대비 실루엣 (0.1초 판독 — D05 §5.2)
extends SceneTree

const OUT_DIR := "res://assets/ui/icons/"
const CELL := 32

var _written := 0


func _init() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUT_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# ── 심볼 6분류 (D10 §5.1) — G-2 판독 게이트의 대상 ──
	_emit("symbol_slipstream", UiPalette.SYMBOL_SLIPSTREAM, _draw_slipstream)
	_emit("symbol_braking", UiPalette.SYMBOL_BRAKING, _draw_braking)
	_emit("symbol_line", UiPalette.SYMBOL_LINE, _draw_line_symbol)
	_emit("symbol_trouble", UiPalette.SYMBOL_TROUBLE, _draw_trouble)
	_emit("symbol_chance", UiPalette.SYMBOL_CHANCE, _draw_chance)
	_emit("symbol_pulse", UiPalette.SYMBOL_PULSE, _draw_pulse)

	# ── 섹터 속성 6축 (D10 §5.3) ──
	_emit("attr_straight", UiPalette.TEXT_PRIMARY, _draw_attr_straight)
	_emit("attr_technical", UiPalette.TEXT_PRIMARY, _draw_attr_technical)
	_emit("attr_sweeper", UiPalette.TEXT_PRIMARY, _draw_attr_sweeper)
	_emit("attr_hazard", UiPalette.TEXT_PRIMARY, _draw_attr_hazard)
	_emit("attr_battle_zone", UiPalette.TEXT_PRIMARY, _draw_attr_battle)
	_emit("attr_pulse_section", UiPalette.TEXT_PRIMARY, _draw_attr_pulse)

	# ── 재화 2종 (D10 §5.2) — 실루엣 층위 구분: 원형 vs 사각 ──
	_emit("currency_credit", UiPalette.CURRENCY_CREDIT, _draw_credit)
	_emit("currency_data", UiPalette.CURRENCY_DATA, _draw_data)

	# ── 화자 2종 (D10 §5.5 · C-B1 비인물성 구속) ──
	_emit("speaker_relay", UiPalette.TEXT_DIM, _draw_mic)
	_emit("speaker_filler", UiPalette.TEXT_DIM, _draw_helmet)

	print("ICONS_OK written=%d dir=%s" % [_written, OUT_DIR])
	quit(0)


func _emit(base_name: String, color: Color, painter: Callable) -> void:
	var img := Image.create_empty(CELL, CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	painter.call(img, color)
	var path := ProjectSettings.globalize_path("%s%s.png" % [OUT_DIR, base_name])
	if img.save_png(path) != OK:
		printerr("ICONS_FAIL 저장 실패: %s" % path)
		quit(1)
		return
	_written += 1


# ── 픽셀 헬퍼 (32×32 격자 — 반픽셀·안티앨리어싱 없음. 믹셀 금지 D10 §2.2) ──
func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= CELL or y >= CELL:
		return
	img.set_pixel(x, y, c)


func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err := dx + dy
	var x := x0
	var y := y0
	while true:
		_px(img, x, y, c)
		if x == x1 and y == y1:
			break
		var e2 := err * 2
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy


func _rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color, filled: bool) -> void:
	if filled:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				_px(img, x, y, c)
		return
	_line(img, x0, y0, x1, y0, c)
	_line(img, x0, y1, x1, y1, c)
	_line(img, x0, y0, x0, y1, c)
	_line(img, x1, y0, x1, y1, c)


func _ring(img: Image, cx: int, cy: int, radius: int, c: Color, thickness: int = 1) -> void:
	var outer := radius * radius
	var inner := (radius - thickness) * (radius - thickness)
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var d := (x - cx) * (x - cx) + (y - cy) * (y - cy)
			if d <= outer and d >= inner:
				_px(img, x, y, c)


func _disc(img: Image, cx: int, cy: int, radius: int, c: Color) -> void:
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius:
				_px(img, x, y, c)


# 두께 있는 셰브론(> 모양) — 후류·대치 도상의 공통 요소
func _chevron(img: Image, tip_x: int, cy: int, half: int, thickness: int, c: Color, facing_right: bool) -> void:
	var dir := 1 if facing_right else -1
	for t in range(thickness):
		var tip := tip_x - dir * t
		_line(img, tip, cy, tip - dir * half, cy - half, c)
		_line(img, tip, cy, tip - dir * half, cy + half, c)


# ── 심볼 6분류 (도상 어휘 = D10 §5.1 확정) ──
# 슬립스트림 = 후류 화살표
func _draw_slipstream(img: Image, c: Color) -> void:
	_chevron(img, 26, 16, 9, 3, c, true)
	_chevron(img, 16, 16, 9, 3, c, true)
	_line(img, 4, 10, 10, 10, c)
	_line(img, 4, 22, 10, 22, c)


# 브레이킹 = 브레이크 디스크 (방사 슬롯)
func _draw_braking(img: Image, c: Color) -> void:
	_ring(img, 16, 16, 13, c, 3)
	_ring(img, 16, 16, 5, c, 2)
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		var x0 := 16 + int(round(cos(angle) * 7.0))
		var y0 := 16 + int(round(sin(angle) * 7.0))
		var x1 := 16 + int(round(cos(angle) * 10.0))
		var y1 := 16 + int(round(sin(angle) * 10.0))
		_line(img, x0, y0, x1, y1, c)


# 라인 = 레코드 라인 (코너 인·아웃 궤적). 셀 경계 안쪽(여백 3px)에 가둔다 — 잘리면 실루엣이 무너진다.
func _draw_line_symbol(img: Image, c: Color) -> void:
	var prev := Vector2i(3, 27)
	for step in range(1, 29):
		var t := float(step) / 28.0
		var x := int(round(3.0 + 25.0 * t))
		var y := int(round(27.0 - 22.0 * t * t * (3.0 - 2.0 * t)))
		_line(img, prev.x, prev.y, x, y, c)
		_line(img, prev.x, prev.y + 1, x, y + 1, c)
		prev = Vector2i(x, y)
	# 클리핑 포인트 표시 (점선)
	for i in range(3):
		_px(img, 14 + i * 2, 21 - i * 3, c)


# 트러블 = 경고 삼각
func _draw_trouble(img: Image, c: Color) -> void:
	for t in range(2):
		_line(img, 16, 3 + t, 29 - t, 27 - t, c)
		_line(img, 16, 3 + t, 3 + t, 27 - t, c)
		_line(img, 3 + t, 27 - t, 29 - t, 27 - t, c)
	_rect(img, 15, 12, 17, 20, c, true)
	_rect(img, 15, 22, 17, 24, c, true)


# 찬스 = 스파크
func _draw_chance(img: Image, c: Color) -> void:
	for t in range(2):
		_line(img, 16 + t, 2, 16 + t, 29, c)
		_line(img, 2, 16 + t, 29, 16 + t, c)
	_line(img, 7, 7, 12, 12, c)
	_line(img, 25, 7, 20, 12, c)
	_line(img, 7, 25, 12, 20, c)
	_line(img, 25, 25, 20, 20, c)
	_disc(img, 16, 16, 3, c)


# 펄스 = 펄스 파형 (구형파)
func _draw_pulse(img: Image, c: Color) -> void:
	var pts := [
		Vector2i(3, 22), Vector2i(9, 22), Vector2i(9, 9), Vector2i(16, 9),
		Vector2i(16, 22), Vector2i(22, 22), Vector2i(22, 13), Vector2i(28, 13),
	]
	for t in range(2):
		for i in range(pts.size() - 1):
			_line(img, pts[i].x, pts[i].y + t, pts[i + 1].x, pts[i + 1].y + t, c)


# ── 섹터 속성 6축 (도상 = D10 §5.3 확정) ──
func _draw_attr_straight(img: Image, c: Color) -> void:
	_rect(img, 4, 12, 27, 14, c, true)
	_rect(img, 4, 18, 27, 20, c, true)


func _draw_attr_technical(img: Image, c: Color) -> void:
	var pts := [Vector2i(4, 6), Vector2i(14, 6), Vector2i(14, 16), Vector2i(24, 16), Vector2i(24, 26)]
	for t in range(2):
		for i in range(pts.size() - 1):
			_line(img, pts[i].x + t, pts[i].y, pts[i + 1].x + t, pts[i + 1].y, c)


# 고속 커브 — 동심 호 3줄. 중심을 셀 밖 좌상단에 두되 반경은 셀 안에서 닫히게 잡는다.
func _draw_attr_sweeper(img: Image, c: Color) -> void:
	for t in range(3):
		_ring(img, 2, 2, 26 - t * 7, c, 1)


func _draw_attr_hazard(img: Image, c: Color) -> void:
	for i in range(4):
		_line(img, 3 + i * 7, 27, 10 + i * 7, 10, c)
	_rect(img, 3, 5, 28, 7, c, true)


func _draw_attr_battle(img: Image, c: Color) -> void:
	_chevron(img, 14, 16, 8, 2, c, true)
	_chevron(img, 18, 16, 8, 2, c, false)


func _draw_attr_pulse(img: Image, c: Color) -> void:
	for x in range(3, 29):
		var t := float(x - 3) / 25.0
		var y := 16 - int(round(sin(t * TAU * 1.5) * (3.0 + t * 6.0)))
		_px(img, x, y, c)
		_px(img, x, y + 1, c)


# ── 재화 2종 — 실루엣 층위 구분 (원형 vs 사각. D10 §5.2 구속) ──
func _draw_credit(img: Image, c: Color) -> void:
	_ring(img, 16, 16, 13, c, 3)
	_ring(img, 16, 16, 8, c, 1)
	_rect(img, 14, 8, 18, 24, c, true)


func _draw_data(img: Image, c: Color) -> void:
	_rect(img, 5, 4, 27, 28, c, false)
	_rect(img, 5, 4, 27, 5, c, true)
	_rect(img, 9, 9, 23, 11, c, true)
	_rect(img, 9, 14, 23, 16, c, true)
	_rect(img, 9, 19, 18, 21, c, true)


# ── 화자 2종 (C-B1 비인물성: 얼굴·신체·개성 요소 0) ──
func _draw_mic(img: Image, c: Color) -> void:
	# 캡슐(마이크 헤드) + 그릴 2줄 + 크래들 + 스탠드 — 인물 요소 0 (C-B1)
	_rect(img, 12, 4, 20, 18, c, false)
	_line(img, 13, 3, 19, 3, c)
	_line(img, 13, 19, 19, 19, c)
	_rect(img, 14, 8, 18, 9, c, true)
	_rect(img, 14, 12, 18, 13, c, true)
	_line(img, 8, 17, 8, 21, c)
	_line(img, 24, 17, 24, 21, c)
	_line(img, 8, 21, 24, 21, c)
	_rect(img, 15, 22, 17, 27, c, true)
	_rect(img, 10, 28, 22, 29, c, true)


# 제네릭 헬멧 — 발광 없음·색 미부여·주인공 풀페이스와 실루엣 구분 (D10 §3.2)
func _draw_helmet(img: Image, c: Color) -> void:
	_ring(img, 16, 17, 12, c, 2)
	_rect(img, 4, 22, 28, 29, Color(0, 0, 0, 0), true)
	_line(img, 5, 22, 27, 22, c)
	_rect(img, 9, 13, 24, 18, c, true)
	_rect(img, 11, 15, 22, 16, Color(0, 0, 0, 0), true)
