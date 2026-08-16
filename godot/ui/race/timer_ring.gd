# RACE-01 E04 — 개입 창 타이머 프레임 링 게이지 (D09 §3.2).
#
# 별도 시계 요소를 두지 않는다: 릴 존 전체를 감싸는 테두리가 시간 잔량에 비례해 소진한다
# ("시선 분산 0" — D09 §3.2). 수치는 기본 비표시이며 O6로만 켠다(D04 §8.2 "압박을 설명하지 않는다").
#
# 삼중 부호화 (색 + 두께 + 점멸): 색각 대응이 한 축에만 걸리지 않게 한다.
# 구간 경계는 D13 §8.1(여유 100~60% · 경고 60~30% · 임박 30~0%)이며 값은 core_params 경유로 받는다 —
# 코드에 비율을 기입하지 않는다(불변규칙 2).
#
# **봉인 (불변규칙 5): 이 위젯은 스핀 결과를 입력으로 받지 않는다.** 잔량 비율만 안다.
extends Control

# 두께 1/2/3px · 점멸 2/5Hz = D13 별첨A §8.1(v1.4) 확정 기준값 (총괄 회신 C항 —
# 임시값의 초기 기준선 편입, 2026-08-15). 640×360 도트 원도 기준·×3 표시에서 3·6·9px
# (정수 배율 유지 — D12 §9.1). 조정 창구 = D13 §1.3.
const WIDTH_LEEWAY := 1.0
const WIDTH_WARNING := 2.0
const WIDTH_IMMINENT := 3.0
const BLINK_HZ_WARNING := 2.0
const BLINK_HZ_IMMINENT := 5.0
const BLINK_FLOOR := 0.35  # 점멸 시 최저 알파 — 완전 소등하면 잔량 판독이 끊긴다

var leeway_ratio := 0.6
var warning_ratio := 0.3

var _ratio := 1.0
var _active := false
var _phase := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


# 구간 경계를 데이터에서 주입한다 (호출 층이 core_params를 읽어 넘긴다).
func configure(leeway: float, warning: float) -> void:
	leeway_ratio = leeway
	warning_ratio = warning


# 임박 구간 점멸 주파수 — SE-T03 임박 틱이 **점멸과 동기**이므로(D11 §2.3) 사운드 층이
# 자기 주기를 따로 갖지 않고 여기서 받아 간다. 값이 바뀌면 소리와 그림이 함께 움직인다.
func imminent_blink_hz() -> float:
	return BLINK_HZ_IMMINENT


func set_active(active: bool) -> void:
	_active = active
	set_process(active)
	if not active:
		_phase = 0.0
	queue_redraw()


func set_ratio(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _draw() -> void:
	# 프레임 자체는 상시 존재한다 — 소등 상태에서도 릴 존의 경계가 사라지면 레이아웃이 무너진다.
	var box := Rect2(Vector2.ZERO, size)
	draw_rect(box, UiPalette.FRAME_LINE, false, 1.0)
	if not _active or _ratio <= 0.0:
		return

	var band := _band()
	var color: Color = band["color"]
	color.a = _blink_alpha(band["blink_hz"])
	_draw_perimeter(box, band["width"], color)


# 구간 판정 — 경계값은 주입받은 데이터 값이다.
func _band() -> Dictionary:
	if _ratio > leeway_ratio:
		return {"color": UiPalette.TIMER_LEEWAY, "width": WIDTH_LEEWAY, "blink_hz": 0.0}
	if _ratio > warning_ratio:
		return {"color": UiPalette.gauge_caution(), "width": WIDTH_WARNING, "blink_hz": BLINK_HZ_WARNING}
	return {"color": UiPalette.gauge_danger(), "width": WIDTH_IMMINENT, "blink_hz": BLINK_HZ_IMMINENT}


func _blink_alpha(hz: float) -> float:
	if hz <= 0.0:
		return 1.0
	var wave := (sin(_phase * hz * TAU) + 1.0) * 0.5
	return BLINK_FLOOR + (1.0 - BLINK_FLOOR) * wave


# 상단 중앙에서 시계 방향으로 둘레를 그린다 — 남은 비율만큼만 그려 '소진'을 표현한다.
func _draw_perimeter(box: Rect2, width: float, color: Color) -> void:
	var half := width * 0.5
	var inner := Rect2(box.position + Vector2(half, half), box.size - Vector2(width, width))
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var top_mid := Vector2(inner.position.x + inner.size.x * 0.5, inner.position.y)
	var corner_tr := Vector2(inner.end.x, inner.position.y)
	var corner_br := inner.end
	var corner_bl := Vector2(inner.position.x, inner.end.y)
	var corner_tl := inner.position
	var path: Array[Vector2] = [top_mid, corner_tr, corner_br, corner_bl, corner_tl, top_mid]

	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	var budget := total * _ratio

	for i in range(path.size() - 1):
		if budget <= 0.0:
			return
		var from := path[i]
		var to := path[i + 1]
		var seg := from.distance_to(to)
		if seg <= 0.0:
			continue
		if budget < seg:
			to = from + (to - from).normalized() * budget
		draw_line(from, to, color, width)
		budget -= seg
