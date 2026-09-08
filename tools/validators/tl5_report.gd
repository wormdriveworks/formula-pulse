# TL-5 판정 리포트 — GDScript 판 (D14 §8.2 v1.1). `tl5_report.py` 의 자매 도구다.
#
# **왜 둘인가.** 주력 GUI 머신(Windows)에는 Python 이 없다(스토어 스텁만 있어 `python` 이 빈 줄을 낸다 —
# 개선 회차 12 실측). 러너가 GDScript 이므로 판정도 같은 런타임으로 두면 어느 머신에서도 한 벌로 돈다.
#
# **판정 규격 (D14 §8.2 v1.1 — 결정 #6):**
#   ⓐ 척도 구분 — ±15% 상대 괴리는 **규모 충분(연속) 지표 전속**. 소척도 지표(1단위가 수십 %인 서수·정수:
#      순위·투어 / 기대값 1 미만 희소 사건: 챔피언율·투어 리타이어)는 **허용 범위 판정 전속**.
#   ⓑ 대조 기준선 — 1차 = D13 §4.3 모델값 / **2차 이후 = TL-5 1차 실측값(회귀 감시)**. 기준선 갱신은 총괄 경유.
# 그래서 표에 두 기준을 다 싣고, **판정은 1차 실측 기준선**으로 낸다(모델값은 참고 열). 허용 범위는 D08 §8.3 승계분.
#
# 사용:
#   <console.exe> --headless --path . --script tools/validators/tl5_report.gd -- <standard.json> [novice.json] [expert.json]
# 종료코드: 0 = 이탈 0·괴리 0 (TL5_MODEL_VALID) / 1 = 이탈 또는 괴리 (TL5_MODEL_DEVIATION — 값 조정이 아니라 원인 분석·보고)
extends SceneTree

const TOLERANCE := 0.15   # D14 §8.2 확정 ±15%

# (지표 키, 표시명, D13 §4.3 모델값, TL-5 1차 실측(2026-08-16 표준 n=500), 허용 lo, 허용 hi, 척도)
# 척도: "continuous" = ±15% 괴리 판정 대상 / "small" = 허용 범위 판정 전속 (D14 v1.1 결정 #6-ⓐ)
# 1차 실측 = `docs/qa/TL5_실행기록_2026-08-16.md` §1 (D14 §8.5 기입값). null = 값 없음.
const METRICS := [
	["championship_rank_median", "S1 챔피언십 최종 순위 중앙값", 4.0, 5.0, 3.0, 5.0, "small"],
	["champion_rate", "S1 챔피언 달성률", 0.001, 0.018, 0.0, 0.02, "small"],
	["first_podium_tour_median", "첫 포디움 (투어)", 2.0, 3.0, 1.0, 5.0, "small"],
	["first_gp_win_tour_median", "첫 그랑프리 우승 (투어)", 5.0, 8.0, 2.0, 9.0, "small"],
	["first_tour_win_tour_median", "첫 투어 우승 (투어)", 7.0, 8.0, 2.0, 13.0, "small"],
	["lorentz_beat_rate", "로렌츠 S1 격파율", 0.37, 0.316, null, null, "continuous"],
	["drive_data_total_median", "E1 (S1 축적형 획득)", 821.0, 699.0, null, null, "continuous"],
	["duels_per_gp_mean", "듀얼 발생 (GP당)", 2.50, 2.23, 2.0, 4.0, "continuous"],
	["gp_minutes_median", "GP 모델 길이 (분)", 10.3, 10.4, 10.0, 15.0, "continuous"],
	["gp_minutes_p90", "GP 길이 P90 (분)", 10.5, 11.5, null, 15.0, "continuous"],
	["tour_retires_per_season_mean", "투어 리타이어 (시즌당)", 0.33, 0.20, 0.0, 1.0, "small"],
	["ai_retires_per_gp_mean", "AI 리타이어 (GP당)", 0.73, 0.74, 0.0, 1.0, "continuous"],
	["ai_retires_per_gp_max", "AI 리타이어 상한", 2.0, 2.0, 0.0, 2.0, "small"],
]


func _initialize() -> void:
	var paths := OS.get_cmdline_user_args()
	if paths.is_empty():
		print("usage: --script tools/validators/tl5_report.gd -- <standard.json> [novice.json] [expert.json]")
		quit(2)
		return
	var total_range := 0
	var total_dev := 0
	var loaded := 0
	for path in paths:
		var judged := _judge(String(path))
		if judged.is_empty():
			continue
		loaded += 1
		total_range += int(judged["out_of_range"])
		total_dev += int(judged["deviations"])
	if loaded == 0:
		print("TL5_REPORT_FAIL no readable json")
		quit(2)
		return
	print("\n허용 범위 이탈 %d건 · ±15%% 괴리(1차 기준선 · 연속 지표) %d건" % [total_range, total_dev])
	if total_dev == 0 and total_range == 0:
		print("TL5_MODEL_VALID  (D14 §8.2 — 회귀 감시 통과)")
		quit(0)
		return
	print("TL5_MODEL_DEVIATION  (D14 §8.2 — 값 조정이 아니라 원인 분석·보고 경로)")
	quit(1)


# 한 산출 JSON 을 판정한다 — 표를 찍고 {out_of_range, deviations} 를 돌려준다. 읽기 실패 = 빈 사전.
func _judge(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("TL5_REPORT_FAIL cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		print("TL5_REPORT_FAIL not a json object: %s" % path)
		return {}
	var data: Dictionary = parsed
	var profile := String(data.get("profile", "?"))
	var runs := int(data.get("runs", 0))
	var deviations := 0
	var out_of_range := 0
	print("\n── TL-5 %s (n=%d) — %s" % [profile, runs, path.get_file()])
	print("%-30s %9s %9s %9s  %s" % ["지표", "실기", "1차기준", "모델", "판정"])
	for row in METRICS:
		var key := String(row[0])
		var label := String(row[1])
		var model: Variant = row[2]
		var baseline: Variant = row[3]
		var lo: Variant = row[4]
		var hi: Variant = row[5]
		var scale := String(row[6])
		if not data.has(key):
			print("%-30s %9s %9s %9s  SKIP (미산출)" % [label, "—", _fmt(baseline), _fmt(model)])
			continue
		var actual := float(data[key])
		var verdict: Array[String] = []
		# 허용 범위(D08 §8.3)는 **표준 프로파일 기준**이다 — 총괄 판정 IMPL-121 ⑦("0~2% = 표준 프로파일 기준" ·
		# 숙련 2.4% 는 이탈 아님). 저숙련·숙련의 범위 밖은 서열 정합 소재로 찍되 이탈로 세지 않는다.
		var judged_profile := profile == "standard"
		if lo != null and actual < float(lo):
			verdict.append("범위 미달" if judged_profile else "(비표준 · 범위 미달 참고)")
			if judged_profile:
				out_of_range += 1
		if hi != null and actual > float(hi):
			verdict.append("범위 초과" if judged_profile else "(비표준 · 범위 초과 참고)")
			if judged_profile:
				out_of_range += 1
		# 괴리는 **1차 실측 기준선** 대비 · 연속 지표에만 (D14 v1.1 결정 #6-ⓐⓑ). 소척도는 참고 표기.
		# 기준선은 **표준 프로파일 n=500** 의 실측이므로 ±15% 계수도 표준에서만 — 저숙련·숙련은 서열 정합
		# 대조(D13 §4.3 확인 항목)와 허용 범위만 보고 괴리는 참고로 찍는다.
		if baseline != null and float(baseline) != 0.0:
			var gap := (actual - float(baseline)) / float(baseline)
			if scale == "continuous" and profile == "standard":
				if absf(gap) > TOLERANCE:
					verdict.append("괴리 %+.1f%%" % (gap * 100.0))
					deviations += 1
				else:
					verdict.append("Δ1차 %+.1f%%" % (gap * 100.0))
			elif scale == "continuous":
				verdict.append("(비표준 프로파일 · Δ1차 %+.1f%% 참고)" % (gap * 100.0))
			else:
				verdict.append("(소척도 · Δ1차 %+.1f%% 참고)" % (gap * 100.0))
		var text := " · ".join(verdict) if not verdict.is_empty() else "OK"
		print("%-30s %9s %9s %9s  %s" % [label, _fmt(actual), _fmt(baseline), _fmt(model), text])
	return {"out_of_range": out_of_range, "deviations": deviations}


func _fmt(value: Variant) -> String:
	if value == null:
		return "—"
	return "%.3f" % float(value)
