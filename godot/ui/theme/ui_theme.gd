# 화면 층 테마 창구 (15차 ① — 프레임 결선 ⓓ · 총괄 판정 IMPL-439 ②).
#
# **테마 자원은 값만 갖고, 옵션에 갈리는 부분은 여기가 민다.** `UiPalette` 가 정적 클래스라
# 옵션을 스스로 읽지 못하고 밀어 넣는 구조인 것과 같은 형태이며, 같은 이유로 창구가 하나다 —
# 두 곳에서 테마를 만지면 색각 모드와 상태 색이 서로를 덮는다.
#
# **ⓓ 방식의 계약** (판정 IMPL-439 ②):
#   · 프레임 텍스처 = **의미 전속** (default · primary · danger · disabled)
#   · `normal` · `hover` = **같은 텍스처** — 텍스처가 상태를 말하지 않는다. 마우스를 올려도
#     의장이 갈리지 않으므로 의미 축이 상태 축으로 바뀔 경로 자체가 닫힌다
#   · `hover` 의 표현 = `font_hover_color` **명도 상승** (폭 무관)
#   · `pressed` 의 표현 = `content_margin` **종방향 1px 이동 · 상하 합 불변** (최소 크기 불변)
class_name UiTheme
extends RefCounted

const MAIN_THEME := "res://ui/theme/main_theme.tres"

const BUTTON_TYPE := "Button"
const PRIMARY_TYPE := "PrimaryButton"
const DANGER_TYPE := "DangerButton"
const MODAL_TYPE := "ModalPanel"

# 상태 3종은 **한 묶음으로 다룬다** — 하나만 갈면 텍스처가 상태를 말하기 시작한다.
const STATE_STYLES := ["normal", "hover", "pressed"]

const DANGER_TEXTURE := "res://assets/ui/frames/button_danger_9p.png"
# 색각 대체는 **별도 파일**이다 — 런타임 틴트로는 정본 색을 재현할 수 없다(색상 회전은
# 곱으로 표현되지 않는다 · 에셋 기안 §3 · 심볼 `<id>_alt` 선례 `race_screen.gd`).
const DANGER_TEXTURE_ALT := "res://assets/ui/frames/button_danger_alt_9p.png"


static func main() -> Theme:
	return load(MAIN_THEME) as Theme


# 팔레트·옵션에 갈리는 부분을 테마에 민다. **멱등**이며, 테마 자원이 공유 캐시라
# 한 번 부르면 이미 세워진 화면까지 함께 따라온다(O9 를 화면 안에서 바꿔도 반영된다).
static func apply_palette(theme: Theme = null) -> void:
	var target := theme if theme != null else main()
	if target == null:
		return
	# hover = 라벨 명도 상승. **색은 조달 대장 안**이고 값의 소유는 `UiPalette` 다 —
	# `.tres` 에 적으면 PAL(색 리터럴 대장)이 `.gd`·`.tscn` 만 훑으므로 사각이 된다.
	target.set_color("font_color", BUTTON_TYPE, UiPalette.TEXT_PRIMARY)
	target.set_color("font_hover_color", BUTTON_TYPE, UiPalette.TEXT_HOVER)
	target.set_color("font_pressed_color", BUTTON_TYPE, UiPalette.TEXT_HOVER)
	target.set_color("font_disabled_color", BUTTON_TYPE, UiPalette.TEXT_DIM)
	var danger := load(DANGER_TEXTURE_ALT if UiPalette.colorblind else DANGER_TEXTURE) as Texture2D
	if danger == null:
		return
	for style_name in STATE_STYLES:
		var box := target.get_stylebox(String(style_name), DANGER_TYPE) as StyleBoxTexture
		if box != null:
			box.texture = danger
