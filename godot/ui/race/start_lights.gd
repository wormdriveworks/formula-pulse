# 출발 신호등 — RACE-01 씬 패널 위에 얹는 F1 문법의 스타트 갠트리 (개선 회차 35 · 사용자 요청).
#
# 등 N 개가 한 줄로 서고, 화면(`RaceScreen`)이 정한 수만큼 왼쪽부터 붉게 켠다. **이 노드는 시간을 모른다** —
# 언제 몇 등을 켤지·언제 꺼서 출발할지는 화면이 `_process` 에서 정하고 `set_lit()` 로 넘긴다(정지 중 동결도
# 화면 몫). 그리기는 격자 정렬 사각(픽셀 아트 규격 — 반픽셀 없음)이고 색은 전부 팔레트 상수다(PAL — 코드 색
# 리터럴 0): 점등 = 위험색(색각 대체 시 대체색 · 타이머 임박과 같은 조달), 소등 = 게이지 트랙색, 함체 = 최심 바탕
# + 크롬선. 텍스트는 없다(V4·FONT 무접촉).
#
# 크기 상수는 조판 치수다(타이머 링의 두께 상수와 같은 성격 · D13 수치 대장 밖).
class_name StartLights
extends Control

const LAMP_PX := 10
const LAMP_GAP_PX := 4
const HOUSING_PAD_PX := 4
const TOP_MARGIN_PX := 6

var _count := 5
var _lit := 0


func setup(count: int) -> void:
	_count = maxi(1, count)
	_lit = 0
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 비인터랙티브 — 씬 패널과 같다
	queue_redraw()


# 왼쪽부터 `lit` 개를 붉게. 범위 밖은 자르고, 같은 값이면 다시 그리지 않는다.
func set_lit(lit: int) -> void:
	var clamped := clampi(lit, 0, _count)
	if clamped == _lit:
		return
	_lit = clamped
	queue_redraw()


func lit_count() -> int:
	return _lit


func lamp_count() -> int:
	return _count


func _draw() -> void:
	var housing_w := _count * LAMP_PX + (_count - 1) * LAMP_GAP_PX + 2 * HOUSING_PAD_PX
	var housing_h := LAMP_PX + 2 * HOUSING_PAD_PX
	var x0 := floorf((size.x - float(housing_w)) * 0.5)
	var y0 := float(TOP_MARGIN_PX)
	var housing := Rect2(x0, y0, float(housing_w), float(housing_h))
	draw_rect(housing, UiPalette.BG_DEEP, true)
	draw_rect(housing, UiPalette.FRAME_LINE, false, 1.0)
	for i in range(_count):
		var lx := x0 + float(HOUSING_PAD_PX + i * (LAMP_PX + LAMP_GAP_PX))
		var lamp := Rect2(lx, y0 + float(HOUSING_PAD_PX), float(LAMP_PX), float(LAMP_PX))
		draw_rect(lamp, UiPalette.gauge_danger() if i < _lit else UiPalette.GAUGE_TRACK, true)
