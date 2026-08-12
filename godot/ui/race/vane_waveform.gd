# RACE-01 E07 — 베인 파형 아바타 (D10 §3.3 · G-5 판정 대상).
#
# 파라미터 구동형 런타임 렌더다: 진폭(A)·주파수(F)·안정도(S = 노이즈 혼입률)·상태색 4변수로
# 상태 4종(평상/경고/고양/손상)을 만든다. 상태별 스프라이트 시트를 두지 않으므로
# **성장 3단계 × 상태 4종의 조합 폭발이 구조적으로 발생하지 않는다** (D10 §3.3 — 단계별 신규 에셋 0).
#
# 난수를 쓰지 않고 사인 합성으로 노이즈를 만든다. RNG 6스트림(D12 §6)은 게임 로직 전속이며
# 연출이 소비하면 같은 시드에서 재현이 깨진다 — 연출은 스트림을 건드리지 않는다.
#
# **봉인 (불변규칙 5): 이 위젯은 스핀 결과를 입력으로 받지 않는다.** 상태 enum과 성장 단계만 안다.
extends Control

enum State { NORMAL, ALERT, ELATED, DAMAGED }

# [가안] 상태별 A·F·S: D10 §3.3은 상태를 정성으로만 확정했고(평상 = 완만 / 경고 = 스파이크 /
# 고양 = 고밀도 진폭 / 손상 = 끊기는 노이즈), 같은 절이 산출물로 지정한 '상태·단계 파라미터 표'는
# 아직 없다. D13 대장에도 상태별 수치 행이 없다. 아래 값은 그 정성 서술의 순서 관계
# (진폭 고양>경고>평상 · 주파수 경고>고양>평상 · 안정도 평상>고양>경고>손상)만 지킨 임시값이며,
# 파라미터 표 유입 시 교체 대상이다. — IMPL-071
const STATE_PARAMS := {
	State.NORMAL: {"amp": 0.34, "freq": 1.6, "stability": 1.00, "color": UiPalette.VANE_NORMAL},
	State.ALERT: {"amp": 0.72, "freq": 4.2, "stability": 0.55, "color": UiPalette.VANE_ALERT},
	State.ELATED: {"amp": 0.86, "freq": 3.0, "stability": 0.80, "color": UiPalette.VANE_ELATED},
	State.DAMAGED: {"amp": 0.50, "freq": 2.2, "stability": 0.15, "color": UiPalette.VANE_DAMAGED},
}

const SAMPLE_STEP_PX := 2.0   # 640×360 원도 기준 표본 간격 — ×3 표시에서 6px마다 1점
const LINE_WIDTH := 1.0
const DROPOUT_THRESHOLD := 0.62  # 안정도가 낮을수록 구간이 끊긴다 (손상 상태의 '끊김')

var _state: int = State.NORMAL
var _stage_amp_mult := 1.0
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# 성장 단계 진폭 계수는 D13 별첨A §8.2(1단계 1.0 / 2단계 0.7 / 3단계 0.4)의 값이며
# 호출 층이 데이터에서 읽어 넘긴다 — 코드에 기입하지 않는다(불변규칙 2).
func configure(stage_amp_mult: float) -> void:
	_stage_amp_mult = stage_amp_mult
	queue_redraw()


func set_state(state: int) -> void:
	if _state == state:
		return
	_state = state
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var params: Dictionary = STATE_PARAMS[_state]
	var mid := size.y * 0.5
	var amp: float = float(params["amp"]) * _stage_amp_mult * mid
	var freq: float = float(params["freq"])
	var stability: float = float(params["stability"])
	var color: Color = params["color"]

	# 기준선 — 파형이 끊겨도 아바타의 존재 자체는 유지된다
	draw_line(Vector2(0.0, mid), Vector2(size.x, mid), UiPalette.FRAME_LINE, 1.0)

	var run: PackedVector2Array = PackedVector2Array()
	var x := 0.0
	while x <= size.x:
		var t := x / maxf(size.x, 1.0)
		var carrier := sin((t * freq * TAU) + _time * TAU)
		# 무리수 배수의 사인 3개를 합쳐 반복 주기를 길게 만든다 (난수 없이 '노이즈'로 읽히게)
		var noise := sin(t * 37.7 + _time * 11.3) * 0.6 \
			+ sin(t * 71.3 - _time * 6.7) * 0.3 \
			+ sin(t * 133.1 + _time * 19.1) * 0.1
		var mix := lerpf(noise, carrier, stability)
		if stability < DROPOUT_THRESHOLD and absf(noise) > stability * 1.4:
			# 끊김 — 현재 런을 확정하고 새로 시작한다
			if run.size() >= 2:
				draw_polyline(run, color, LINE_WIDTH)
			run = PackedVector2Array()
			x += SAMPLE_STEP_PX
			continue
		run.append(Vector2(x, mid - mix * amp))
		x += SAMPLE_STEP_PX
	if run.size() >= 2:
		draw_polyline(run, color, LINE_WIDTH)
