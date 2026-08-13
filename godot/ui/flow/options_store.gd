# 옵션 상태 저장소 — D09 §6.1 O1~O15 (+O12) · §6.4 탭 구조.
#
# **기기별 구성이며 프로필 밖이다** (D12 §7.1 구성 분리) — 경로는 세이브 정책 층의
# `SaveManager.OPTIONS_PATH` 상수를 승계한다. 세이브 데이터가 아니므로 백업 회전·
# 마이그레이션 대상이 아니고, SaveService 를 경유하지 않는다.
#
# 저장하는 것은 **선택 인덱스**다 — 단계의 실효 수치(타이머 배율 등)는 core_params 경유로
# 소비부가 읽는다(불변규칙 2). 옵션 항목·단계 구조는 D09 §6.1 확정 구조라 코드 상수다.
#
# 원칙 (D09 §6.1): 전 옵션 즉시 반영·재시작 불요 — 소비부가 사용 시점마다 여기서 읽으므로
# 별도 적용 단계가 없다.
class_name OptionsStore
extends RefCounted

# 탭 배치 = D09 §6.4 (①게임플레이 ②연출·접근성 ③화면·사운드 ④조작 ⑤언어)
const TABS := [
	{"key": "ui.options.tabGameplay", "options": ["o4", "o5", "o6", "o10"]},
	{"key": "ui.options.tabAccessibility", "options": ["o1", "o2", "o3", "o9", "o12"]},
	{"key": "ui.options.tabAudioVideo", "options": ["o7", "o8", "o13", "o14", "o15"]},
	{"key": "ui.options.tabControls", "options": []},
	{"key": "ui.options.tabLanguage", "options": ["o11"]},
]

# 옵션 정의 — 단계는 D09 §6.1 확정 기준값 (라벨은 전량 스트링 키)
const OPTIONS := {
	"o1": {"label": "ui.options.o1", "steps": ["ui.options.stepStandard", "ui.options.stepReduced", "ui.options.stepOff"], "default": 0},
	"o2": {"label": "ui.options.o2", "steps": ["ui.options.stepStandard", "ui.options.stepReduced", "ui.options.stepOff"], "default": 0},
	"o3": {"label": "ui.options.o3", "steps": ["ui.options.stepStandard", "ui.options.stepReduced", "ui.options.stepOff"], "default": 0},
	"o4": {"label": "ui.options.o4", "steps": ["ui.options.stepStandard", "ui.options.stepFast", "ui.options.stepInstant"], "default": 0},
	"o5": {"label": "ui.options.o5", "steps": ["ui.options.stepTimerBase", "ui.options.stepTimer15", "ui.options.stepTimer20", "ui.options.stepTimerOff"], "default": 0, "notice": "ui.options.o5Notice"},
	"o6": {"label": "ui.options.o6", "steps": ["ui.options.stepOff", "ui.options.stepOn"], "default": 0},
	"o7": {"label": "ui.options.o7", "steps": ["ui.options.stepScale100", "ui.options.stepScale115", "ui.options.stepScale130"], "default": 0},
	"o8": {"label": "ui.options.o8", "steps": ["ui.options.stepScale100", "ui.options.stepScale110", "ui.options.stepScale125"], "default": 0},
	"o9": {"label": "ui.options.o9", "steps": ["ui.options.stepPaletteBase", "ui.options.stepPaletteAlt"], "default": 0},
	"o10": {"label": "ui.options.o10", "steps": ["ui.options.stepSlow", "ui.options.stepNormal", "ui.options.stepFastText"], "default": 1},
	"o11": {"label": "ui.options.o11", "steps": ["ui.options.stepKorean"], "default": 0},
	"o12": {"label": "ui.options.o12", "steps": ["ui.options.stepStandard", "ui.options.stepStillCut"], "default": 0},
	"o13": {"label": "ui.options.o13", "volume": true},
	"o14": {"label": "ui.options.o14", "volume": true},
	"o15": {"label": "ui.options.o15", "volume": true},
}

var _values: Dictionary = {}
var _volume_default := 80
var _volume_step := 10
var onboarding_seen: Dictionary = {}  # 1회성 온보딩 툴팁 기록 (COM-02 — 옵션에서 초기화 가능)


func setup(data: GameData) -> void:
	_volume_default = data.param_int("param_opt_volume_default")
	_volume_step = data.param_int("param_opt_volume_step")
	load_from_disk()


func index_of(option_id: String) -> int:
	return int(_values.get(option_id, _default_of(option_id)))


func set_index(option_id: String, index: int) -> void:
	_values[option_id] = index
	save_to_disk()


func _default_of(option_id: String) -> int:
	var option: Dictionary = OPTIONS[option_id]
	return _volume_default if option.get("volume", false) else int(option.get("default", 0))


func step_count(option_id: String) -> int:
	var option: Dictionary = OPTIONS[option_id]
	if option.get("volume", false):
		return 0  # 슬라이더 계열 — 0~100 연속
	return (option["steps"] as Array).size()


func volume_step() -> int:
	return _volume_step


func reset_defaults() -> void:
	_values.clear()
	save_to_disk()


func mark_onboarding(tip_id: String) -> void:
	onboarding_seen[tip_id] = true
	save_to_disk()


func reset_onboarding() -> void:
	onboarding_seen.clear()
	save_to_disk()


# ── 디스크 (기기별 — 프로필 밖) ──
func load_from_disk() -> void:
	if not FileAccess.file_exists(SaveManager.OPTIONS_PATH):
		return
	var file := FileAccess.open(SaveManager.OPTIONS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_values = parsed.get("values", {})
	onboarding_seen = parsed.get("onboarding_seen", {})


func save_to_disk() -> void:
	var file := FileAccess.open(SaveManager.OPTIONS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("OptionsStore: cannot write options file")
		return
	file.store_string(JSON.stringify({
		"values": _values,
		"onboarding_seen": onboarding_seen,
	}))
