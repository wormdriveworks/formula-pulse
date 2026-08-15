# TL-2 기능 체크리스트 기계 생성기 (D14 §2.2 — 생성 규칙 5축의 이행 · 인계 §3-1).
#
# 실행: godot --headless --path godot --script tests/gen_tl2_checklist.gd
# 산출: docs/qa/TL2_기능체크리스트.md  (재생성 = 같은 명령 — 산출물은 커밋한다)
#
# D14 §2.2: "정본 목록 = D09 별첨A 화면 전수. 화면당 체크 항목은 ①진입/이탈 경로(플로우맵 대조)
# ②표시 요소 전수(별첨A 명세 대조) ③옵션 반영 ④T-1 용어 표기(완칭) ⑤금지 구역 진입점 0 의
# 5축으로 기계 생성한다. 체크리스트 실본은 실행 단계 산출물이다."
#
# 기계가 채우는 것: 각 축의 **실측 증거**(경로 그래프·노드 목록·옵션 소비·사용 키 문면·광고 어휘 0).
# 사람이 채우는 것: 별첨A 명세와의 눈 대조 체크박스. 기계 검사가 이미 판정 가능한 축(⑤·T-1 기계분)은
# 생성 시점 판정을 병기한다 — 판정 불가면 생성 자체가 실패한다(침묵 통과 없음).
extends SceneTree

const APPENDIX_PATH := "res://../docs/design/D09_별첨A_화면상세_v1_2.md"
const OUTPUT_PATH := "res://../docs/qa/TL2_기능체크리스트.md"
const APP_ROOT_PATH := "res://ui/flow/app_root.gd"
const STRINGS_PATH := "res://data/strings/strings.csv"

# MS-2 화면 범위 = 대장 25종 − 2종 (IMPL-077 사용자 확정)
const EXCLUDED := {
	"SYS-04": "MS-2 범위 외 — 업적 데이터 테이블 부재 (IMPL-077)",
	"TUT-01": "MS-2 범위 외 — D04 텍스트 풀 트랙 의존 (IMPL-077)",
}

# 라우터 비경유 화면 — 소재 매핑 (오버레이·코드 생성 다이얼로그·전역 규격)
const NON_ROUTED := {
	"RACE-02": {"script": "res://ui/race/duel_overlay.gd",
		"scene": "res://ui/race/race_screen.tscn", "root": "DuelOverlay",
		"entry": "RACE-01 듀얼 삽입 (D05 §3 상태 머신 1:1 — 라우터 비경유)",
		"exit": "듀얼 결판 → RACE-01 복귀 (결과 프레임 내 표기 후 해제)"},
	"SYS-05": {"script": "res://ui/race/pause_overlay.gd",
		"scene": "res://ui/race/race_screen.tscn", "root": "PauseOverlay",
		"entry": "RACE-01 일시정지 (ESC — 개입 창 중 전면 가림막)",
		"exit": "재개(3-2-1 카운트인) / 옵션 오버레이 / 타이틀"},
	"NAR-02": {"script": "res://ui/nar/vn_screen.gd",
		"scene": "res://ui/nar/vn_screen.tscn", "root": "CalendarPanel",
		"entry": "NAR-01 내부 오버레이 (시즌 오프닝 캘린더 공개 — 신규 슬롯 불신설)",
		"exit": "확인 → NAR-01 진행 재개"},
	"COM-01": {"script": "res://ui/com/confirm_dialog.gd", "scene": "", "root": "",
		"entry": "코드 생성 다이얼로그 — 유상·비가역 확정 전속 (호출 화면 위)",
		"exit": "확정/취소 → 호출 화면 복귀 (초기 포커스 = 취소, §A-23)"},
	"COM-02": {"script": "", "scene": "", "root": "",
		"entry": "전역 툴팁 규격 (gui/timers/tooltip_delay_sec — project.godot)",
		"exit": "포인터 이탈 시 소멸"},
}

# 호스트 씬에서 다른 화면이 소유한 서브트리 — 호스트 인벤토리에서 제외한다
const CLAIMED_ROOTS := {
	"res://ui/race/race_screen.tscn": ["DuelOverlay", "PauseOverlay"],
	"res://ui/nar/vn_screen.tscn": ["CalendarPanel"],
}

# 표시·입력 요소로 집계하는 노드 타입 (레이아웃 컨테이너는 제외)
const DISPLAY_TYPES := ["Label", "RichTextLabel", "Button", "CheckButton", "OptionButton",
	"TextureRect", "TextureProgressBar", "ProgressBar", "HSlider", "LineEdit", "ItemList"]

# 금지 구역 어휘 (D09-2 §8.2 승계 — 데스크탑 화면 층에 광고 계층 어휘 진입점 0)
const AD_TERMS := ["IAdService", "AdMob", "show_ad", "ad_unit", "광고", "reward_ad", "interstitial"]

var _failures := 0


func _init() -> void:
	var roster := _parse_appendix()
	var routes := _parse_routes()
	if roster.is_empty() or routes.is_empty():
		print("TL2_GEN_FAIL inputs")
		quit(1)
		return
	var strings := _parse_strings()
	var go_graph := _build_go_graph(routes)
	var out := "# TL-2 기능 체크리스트 — 화면 23종 × 5축 (기계 생성)\n\n"
	out += "> 생성기: `godot/tests/gen_tl2_checklist.gd` (재생성 = 같은 명령 — 수기 편집 금지)\n"
	out += "> 생성 규칙 정본: D14 §2.2 · 화면 목록 정본: D09 별첨A v1.2 · 범위: IMPL-077 (25종 − SYS-04·TUT-01)\n"
	out += "> 기계가 채운 것 = 실측 증거 / 체크박스 = 실행 단계에서 별첨A 명세와 눈 대조 (TL-2 실행 시)\n\n"
	var generated := 0
	for screen in roster:
		var screen_id := String(screen["id"])
		if EXCLUDED.has(screen_id):
			out += "## %s %s — **생성 제외** (%s)\n\n" % [screen_id, screen["name"], EXCLUDED[screen_id]]
			continue
		out += _emit_screen(screen, routes, go_graph, strings)
		generated += 1
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		print("TL2_GEN_FAIL cannot write %s" % OUTPUT_PATH)
		quit(1)
		return
	file.store_string(out)
	file.close()
	if _failures > 0:
		print("TL2_GEN_FAIL screens=%d machine_failures=%d" % [generated, _failures])
		quit(1)
		return
	print("TL2_GEN_PASS screens=%d output=%s" % [generated, OUTPUT_PATH])
	quit(0)


# ── 정본 파싱 ──
func _parse_appendix() -> Array:
	var text := _read(APPENDIX_PATH)
	var roster: Array = []
	var regex := RegEx.new()
	regex.compile("^## §A-(\\d+)\\. ([A-Z]+-\\d+) ([^\\[]+)")
	for line in text.split("\n"):
		var found := regex.search(line)
		if found != null:
			roster.append({"section": "§A-" + found.get_string(1), "id": found.get_string(2),
				"name": found.get_string(3).strip_edges()})
	return roster


func _parse_routes() -> Dictionary:
	var routes: Dictionary = {}
	var regex := RegEx.new()
	regex.compile("\"([A-Z]+-\\d+)\":\\s*\"(res://[^\"]+)\"")
	for found in regex.search_all(_read(APP_ROOT_PATH)):
		routes[found.get_string(1)] = found.get_string(2)
	return routes


func _parse_strings() -> Dictionary:
	var strings: Dictionary = {}
	for line in _read(STRINGS_PATH).split("\n"):
		var comma := line.find(",")
		if comma > 0:
			strings[line.substr(0, comma)] = line.substr(comma + 1)
	return strings


# go() 호출 그래프: 화면 id -> 이탈 대상 목록. 진입은 역방향으로 얻는다.
func _build_go_graph(routes: Dictionary) -> Dictionary:
	var graph: Dictionary = {}
	var regex := RegEx.new()
	regex.compile("go\\(\"([A-Z]+-\\d+)\"")
	for screen_id in routes:
		var script_path := String(routes[screen_id]).replace(".tscn", ".gd")
		var targets: Array = []
		for found in regex.search_all(_read(script_path)):
			if not targets.has(found.get_string(1)):
				targets.append(found.get_string(1))
		# HUB 공통 베이스의 뒤로 가기(HUB-01)는 상속 화면 전부에 걸린다
		if screen_id.begins_with("HUB-") and screen_id != "HUB-01" and not targets.has("HUB-01"):
			targets.append("HUB-01")
		graph[screen_id] = targets
	return graph


# ── 화면 1종 출력 (5축) ──
func _emit_screen(screen: Dictionary, routes: Dictionary, go_graph: Dictionary,
		strings: Dictionary) -> String:
	var screen_id := String(screen["id"])
	var routed := routes.has(screen_id)
	var script_path := ""
	var scene_path := ""
	var subtree_root := ""
	if routed:
		scene_path = String(routes[screen_id])
		script_path = scene_path.replace(".tscn", ".gd")
	else:
		var spec: Dictionary = NON_ROUTED.get(screen_id, {})
		script_path = String(spec.get("script", ""))
		scene_path = String(spec.get("scene", ""))
		subtree_root = String(spec.get("root", ""))
	var body := "## %s %s (%s)\n" % [screen_id, screen["name"], screen["section"]]
	body += "- 구현: %s\n" % (script_path if script_path != "" else "project.godot 전역 설정")

	# ① 진입/이탈 (플로우맵 대조 — ROUTES + go() 실측)
	if routed:
		var entries: Array = []
		if screen_id == "SYS-01":
			entries.append("앱 기동(ENTRY_SCREEN)")
		for other_id in go_graph:
			if other_id != screen_id and (go_graph[other_id] as Array).has(screen_id):
				entries.append(String(other_id))
		var exits: Array = go_graph.get(screen_id, [])
		for target in exits:
			if not routes.has(String(target)):
				_failures += 1
				body += "- **[기계 FAIL]** 이탈 대상 %s 가 라우터 경로 표에 없다\n" % target
		body += "- [ ] ①진입/이탈 — 진입: %s / 이탈: %s (실측 — 별첨A 플로우와 대조)\n" % [
			"·".join(PackedStringArray(entries)) if not entries.is_empty() else "(역참조 없음 — 세션 전이 확인)",
			"·".join(PackedStringArray(exits)) if not exits.is_empty() else "(go 호출 없음 — 전이 주체 확인)"]
	else:
		var spec: Dictionary = NON_ROUTED.get(screen_id, {})
		body += "- [ ] ①진입/이탈 — 진입: %s / 이탈: %s\n" % [spec.get("entry", "?"), spec.get("exit", "?")]

	# ② 표시 요소 전수 (씬 실측 노드 목록 — 별첨A E## 명세와 눈 대조)
	if scene_path != "":
		var nodes := _scene_display_nodes(scene_path, subtree_root)
		body += "- [ ] ②표시 요소 전수 (%d개 실측): %s\n" % [nodes.size(), "·".join(PackedStringArray(nodes))]
	elif script_path != "":
		body += "- [ ] ②표시 요소 전수 — 코드 생성 노드 (스크립트에서 New 되는 Label·Button 확인)\n"
	else:
		body += "- [ ] ②표시 요소 전수 — 전역 규격 (툴팁 지연·1회성 온보딩 기록)\n"

	# ③ 옵션 반영 (O1~O15 소비 실측)
	var option_hits := _option_consumers(script_path)
	body += "- [ ] ③옵션 반영 — 소비 실측: %s\n" % (
		"·".join(PackedStringArray(option_hits)) if not option_hits.is_empty()
		else "(직접 소비 없음 — 공통 채널 경유 여부 확인)")

	# ④ T-1 완칭 (사용 스트링 키 문면 — '티어' 단독 표기 기계 검사)
	var keys := _string_keys(script_path)
	var t1_violations := 0
	for key in keys:
		var phrase := String(strings.get(key, ""))
		if phrase.contains("티어") and not phrase.contains("스킬 티어"):
			t1_violations += 1
			_failures += 1
			body += "- **[기계 FAIL]** T-1: %s = \"%s\" — '티어' 단독 표기\n" % [key, phrase]
	body += "- [ ] ④T-1 완칭 — 사용 키 %d종 · '티어' 단독 표기 기계 검사 %s (문면 눈 대조는 실행 시)\n" % [
		keys.size(), "통과" if t1_violations == 0 else "실패 %d건" % t1_violations]

	# ⑤ 금지 구역 진입점 0 (광고 계층 어휘 — D09-2 승계)
	var ad_hits := _ad_terms(script_path)
	if not ad_hits.is_empty():
		_failures += 1
		body += "- **[기계 FAIL]** ⑤금지 구역: 광고 어휘 검출 — %s\n" % "·".join(PackedStringArray(ad_hits))
	body += "- [x] ⑤금지 구역 진입점 0 — 광고 계층 어휘 0건 (기계 판정 %s)\n" % (
		"통과" if ad_hits.is_empty() else "실패")
	return body + "\n"


func _scene_display_nodes(scene_path: String, subtree_root: String) -> Array:
	var nodes: Array = []
	var regex := RegEx.new()
	regex.compile("\\[node name=\"([^\"]+)\" type=\"([^\"]+)\"(?: parent=\"([^\"]+)\")?")
	var claimed: Array = CLAIMED_ROOTS.get(scene_path, [])
	for found in regex.search_all(_read(scene_path)):
		var node_name := found.get_string(1)
		var node_type := found.get_string(2)
		var parent := found.get_string(3)
		var in_subtree := subtree_root == "" or parent == subtree_root \
			or parent.begins_with(subtree_root + "/")
		if subtree_root == "":
			for claimed_root in claimed:   # 호스트 화면은 타 화면 소유 서브트리를 뺀다
				if node_name == String(claimed_root) or parent == String(claimed_root) \
					or parent.begins_with(String(claimed_root) + "/"):
					in_subtree = false
		if in_subtree and DISPLAY_TYPES.has(node_type):
			nodes.append("%s(%s)" % [node_name, node_type])
	return nodes


func _option_consumers(script_path: String) -> Array:
	if script_path == "":
		return []
	var hits: Array = []
	var source := _read(script_path)
	var regex := RegEx.new()
	regex.compile("param_opt_[a-z0-9_]+|options\\.index_of\\(\"(o\\d+)\"\\)|param_fx_[a-z0-9_]+|param_pause_countin_sec")
	for found in regex.search_all(source):
		var hit := found.get_string(0)
		if found.get_string(1) != "":
			hit = "O" + found.get_string(1).substr(1)
		if not hits.has(hit):
			hits.append(hit)
	return hits


func _string_keys(script_path: String) -> Array:
	if script_path == "":
		return []
	var keys: Array = []
	var regex := RegEx.new()
	regex.compile("\"((?:ui|raceLog|vane)\\.[A-Za-z0-9_.]+)\"")
	for found in regex.search_all(_read(script_path)):
		if not keys.has(found.get_string(1)):
			keys.append(found.get_string(1))
	return keys


func _ad_terms(script_path: String) -> Array:
	if script_path == "":
		return []
	var hits: Array = []
	var source := _read(script_path)
	for term in AD_TERMS:
		if source.contains(String(term)):
			hits.append(String(term))
	return hits


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
