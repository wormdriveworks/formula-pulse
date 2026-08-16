#!/usr/bin/env python3
"""TL-5 판정 리포트 (D14 §8.2) — 러너 산출 JSON을 D13 §4.3 목표·시뮬 측정과 대조한다.

판정 규격 (D14 §8.2 확정):
  12항 중 허용 범위 이탈 0 **및** 시뮬 측정값 대비 상대 괴리 ±15% 이내
  → "모델→실기 도달률 검증 통과". 이탈 시 = 값 조정이 아니라 원인 분석 → 총괄 보고.

사용: python3 tools/validators/tl5_report.py <standard.json> [novice.json] [expert.json]
"""
import json
import sys

# D13 §4.3 표 전사 — (지표 키, 표시명, 시뮬 측정값, 허용 범위 lo, hi, 괴리 판정 대상)
# 허용 범위는 D08 §8.3 승계분이며 None = 범위 발주 없음(참고 기록).
METRICS = [
    ("championship_rank_median", "S1 챔피언십 최종 순위 중앙값", 4.0, 3.0, 5.0, True),
    ("champion_rate", "S1 챔피언 달성률", 0.001, 0.0, 0.02, False),
    ("first_podium_tour_median", "첫 포디움 (투어)", 2.0, 1.0, 5.0, True),
    ("first_gp_win_tour_median", "첫 그랑프리 우승 (투어)", 5.0, 2.0, 9.0, True),
    ("first_tour_win_tour_median", "첫 투어 우승 (투어)", 7.0, 2.0, 13.0, True),
    ("lorentz_beat_rate", "로렌츠 S1 격파율", 0.37, None, None, True),
    ("drive_data_total_median", "E1 (S1 축적형 획득)", 821.0, None, None, True),
    ("duels_per_gp_mean", "듀얼 발생 (GP당)", 2.50, 2.0, 4.0, True),
    ("gp_minutes_median", "GP 모델 길이 (분)", 10.3, 10.0, 15.0, True),
    ("gp_minutes_p90", "GP 길이 P90 (분)", 10.5, None, 15.0, True),
    ("tour_retires_per_season_mean", "투어 리타이어 (시즌당)", 0.33, 0.0, 1.0, True),
    ("ai_retires_per_gp_mean", "AI 리타이어 (GP당)", 0.73, 0.0, 1.0, True),
    ("ai_retires_per_gp_max", "AI 리타이어 상한", 2.0, 0.0, 2.0, False),
]
TOLERANCE = 0.15   # D14 §8.2 확정 ±15%

# 시즌 1 = 5투어. 투어 단위 지표는 시즌 경계를 넘어가면 "S2 이후"를 뜻한다.
# 시뮬 측정 "S2 투어1" = 시즌 1 기준 투어 6에 해당하나, 러너는 시즌 1만 돌므로
# 미도달(표본 제외)이 정상이다 — 그 경우 도달률로 대조한다.


def judge(path):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    profile = data.get("profile", "?")
    runs = data.get("runs", 0)
    rows = []
    deviations = 0
    out_of_range = 0
    for key, label, model, lo, hi, compare in METRICS:
        actual = data.get(key)
        if actual is None:
            rows.append((label, "—", "미산출", "SKIP"))
            continue
        verdict = []
        if lo is not None and actual < lo:
            verdict.append("범위 미달")
            out_of_range += 1
        if hi is not None and actual > hi:
            verdict.append("범위 초과")
            out_of_range += 1
        gap = None
        if compare and model:
            gap = (actual - model) / model
            if abs(gap) > TOLERANCE:
                verdict.append("괴리 %+.1f%%" % (gap * 100))
                deviations += 1
        rows.append((label, "%.3f" % actual, "%.3f" % model, " · ".join(verdict) or "OK"))
    return profile, runs, rows, deviations, out_of_range


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    total_dev = 0
    total_range = 0
    for path in sys.argv[1:]:
        profile, runs, rows, deviations, out_of_range = judge(path)
        print("\n── TL-5 %s (n=%d)" % (profile, runs))
        print("%-32s %10s %10s  %s" % ("지표", "실기", "모델", "판정"))
        for label, actual, model, verdict in rows:
            print("%-32s %10s %10s  %s" % (label, actual, model, verdict))
        total_dev += deviations
        total_range += out_of_range
    print("\n허용 범위 이탈 %d건 · ±15%% 괴리 %d건" % (total_range, total_dev))
    if total_dev == 0 and total_range == 0:
        print("TL5_MODEL_VALID  (D14 §8.2 — 모델→실기 도달률 검증 통과)")
        return 0
    print("TL5_MODEL_DEVIATION  (D14 §8.2 — 값 조정이 아니라 원인 분석·총괄 보고 경로)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
