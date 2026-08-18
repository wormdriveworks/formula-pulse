# COM — 저장 표시 (D09 본문 §181 명문: "화면 우상단 저장 아이콘 + 회전 애니메이션").
#
# **화면이 아니라 라우터에 붙는다.** 저장 지점은 D09 §2.4가 확정한 3곳(RACE-03 진입·투어
# 경계·시즌 경계)이고 그 순간의 화면이 무엇인지는 정해져 있지 않다. 화면마다 표시를 두면
# 저장이 화면 전환과 겹치는 회차에 표시가 함께 사라진다 — 라우터가 화면 위에 얹어 둔다.
#
# **정보 채널이지 장식이 아니다** — §181 이 용도를 *"저장 중 종료 경고의 근거 표시"* 로
# 규정한다. 즉 이 표시가 떠 있는 동안 종료하면 안 된다는 것을 사람이 알 수 있어야 한다.
# 그래서 회전은 감쇠 옵션(O1 화면 셰이크 등)의 대상이 아니다: 감쇠는 연출을 줄이되
# 정보 채널은 보존한다(D09 §6.3 정보 보존 의무).
class_name SaveIndicator
extends TextureRect

const ICON := "res://assets/ui/icons/sys_save.png"

# 표시 시간·회전 주기는 **값 창구를 거친다** (불변규칙 2). 구성 전에는 값이 없다 —
# 리터럴 초기값을 두면 `configure()` 미호출 경로에서 D13 밖의 수치가 조용히 실렌더된다
# (`log_feed.gd` 의 UNCONFIGURED 와 같은 축 — 총괄 판정 IMPL-176 ④).
const UNCONFIGURED := -1.0

var _hold_sec := UNCONFIGURED
var _spin_sec := UNCONFIGURED
var _left := 0.0
var _reported := false


func configure(hold_sec: float, spin_sec: float) -> void:
	_hold_sec = hold_sec
	_spin_sec = spin_sec


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	if ResourceLoader.exists(ICON):
		texture = load(ICON) as Texture2D
	else:
		# 진단 문자열은 영문 — V4 는 한글 리터럴을 경로 불문 차단한다
		push_error("SaveIndicator: icon asset missing - %s" % ICON)
	if texture != null:
		var box := texture.get_size()
		custom_minimum_size = box
		# 회전이 중심을 기준으로 돌게 피벗을 가운데 둔다.
		pivot_offset = box * 0.5
		# ── 우상단 고정 (§181) ──
		# **오프셋을 직접 적는다.** `set_anchors_preset()` 은 기본값(`keep_offsets=false`)에서
		# **현재 rect 를 보존하도록 오프셋을 역산**하는데, `_ready()` 시점의 rect 는 아직
		# (0,0,0,0) 이다. 그러면 우측 앵커에 0폭 rect 가 보존돼 `offset_left = -부모폭` 이 되고,
		# 아이콘이 **좌상단에 뜬다**(실측: 640 캔버스에서 rect P=(0,0) · 우측 여백 608).
		# 앵커만 세우고 오프셋은 도상 크기로 직접 적는 편이 순서에 의존하지 않는다.
		anchor_left = 1.0
		anchor_right = 1.0
		anchor_top = 0.0
		anchor_bottom = 0.0
		offset_left = -box.x
		offset_right = 0.0
		offset_top = 0.0
		offset_bottom = box.y
	visible = false
	set_process(false)


# 저장 개시 — 세션의 `progress_saved` 에 물린다.
func flash() -> void:
	if _hold_sec == UNCONFIGURED or _spin_sec == UNCONFIGURED:
		# 값 누락은 "중단·보고" 사안이다 — 임의 대체값으로 그리지 않는다(불변규칙 2).
		# **한 번만 보고한다** — 저장은 회차마다 일어나므로 매번 짖으면 로그가 묻힌다.
		if not _reported:
			_reported = true
			push_error("SaveIndicator: unconfigured - D13 has no hold/spin duration row")
		return
	_left = _hold_sec
	rotation = 0.0
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		visible = false
		set_process(false)
		return
	# 등속 회전 — 주기는 값 창구가 준다. 프레임 수가 아니라 초로 도는 것이 규격이다.
	rotation += TAU * (delta / _spin_sec)
