# 전용 CG 표시 컴포넌트 (D10 §7 · D09 §3.6 "L3 = L2 채널 + 전용 일러스트 컷인" · D11 §6.5).
#
# 두 자리에서 쓰인다. **표시 형태는 같고 지속 규칙만 갈린다** —
#   · 레이스 L3 컷인   : `hold_sec > 0` — D11 §6.5 "컷인 인 시점 = SE-L3 개시, **컷인 지속 ≤
#     스팅 길이**"(상한 2.5초 = `presentation_grades.sting_length_sec` 확정 기준값).
#   · VN 장면 일러스트 : `hold_sec <= 0` — 장면이 끝날 때까지 남는다(화면이 내린다).
#
# **페이드를 넣지 않았다.** 넣으면 인·아웃 길이가 필요한데 그 수치는 D13 대장에 없다
# (불변규칙 2 — 없는 값을 만들지 않는다). 정본이 준 값은 **지속 상한 하나**뿐이므로
# 그 하나만 쓴다. 하드 컷은 도트 연출과도 어긋나지 않으며, 완급이 필요하다는 판단이 서면
# 그때 대장에 값이 서야 한다.
#
# **감쇠 대상이 아니다.** 접근성 감쇠 3축은 O1 셰이크·O2 플래시·O3 진동이고(D09 §6.1),
# 정지 일러스트는 그 어느 채널도 아니다. 마스크를 임의로 걸면 정본에 없는 옵션 결속이 생긴다.
class_name CgCutIn
extends Control

const ILLUSTRATION_DIR := "res://assets/illustrations/"

# 실물 부재를 조용히 넘기지 않는다 — 기계 관측 지점 (`choice_omissions` 와 같은 규약).
var missing_asset := ""
# **지속을 관측 가능하게 둔다.** 값의 출처가 확정 기준값(`sting_length_sec`)이라는 사실은
# 밖에서 재지 못하면 증명되지 않는다 — 사적으로 숨기면 "2.5 를 손으로 적었다"와
# "표에서 받았다"가 검사에게 같은 그림이 된다.
var hold_sec := 0.0

# 실물 부재 시 이 자리에 서는 사람이 무엇을 찾아야 하는지 남긴다.
var asset_id := ""


func _init(asset: String, seconds: float = 0.0) -> void:
	asset_id = asset
	hold_sec = seconds
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 컷인은 연출이지 조작면이 아니다 — 입력을 먹으면 그 아래 화면이 2.5초 동안 멎는다.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := TextureRect.new()
	art.name = "Art"
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 원도 640×360 = 1× 캔버스 그대로다. 그래도 비율 보존을 명시해 두는 것은 모바일 세로
	# 캔버스에서 같은 컴포넌트가 서는 경로(D09-2)를 미리 막지 않기 위해서다.
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var texture := load(ILLUSTRATION_DIR + asset + ".png") as Texture2D
	if texture == null:
		missing_asset = asset
		push_error("CgCutIn: illustration '%s' not found" % asset)
	art.texture = texture
	add_child(art)


func _ready() -> void:
	if hold_sec <= 0.0:
		return
	# 스팅과 같은 시점에 서고 스팅 길이만큼 남는다 — 스팅 발화는 호출부가 이미 했다.
	get_tree().create_timer(hold_sec).timeout.connect(_dismiss)


func _dismiss() -> void:
	if is_inside_tree():
		queue_free()
