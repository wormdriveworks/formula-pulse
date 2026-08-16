# tools/palette — 팔레트 스와치 생성기

> 소유: **에셋 트랙** (`tools/palette/` 배정 = 총괄 판정 2026-08-16 · IMPL-139 §1)
> 전례: **IMPL-097**(TL-2 체크리스트) — 생성기 커밋 · 산출물 **수기 편집 금지** · 재생성 = 같은 명령

## 무엇을 만드는가

`godot/assets/palettes/` 의 스와치 시트 2장.

| 산출 | 크기 |
|---|---|
| `master_56.png` | 288×874 — 마스터 4블록 + 기능 부속 13 |
| `colorblind_alt.png` | 288×930 — 위 + 기능 13(CB 적용) + 교체 4(분할 칩) |

**`.gpl` 2종은 산출물이 아니다.** 그쪽이 원천이고 이 도구는 읽기만 한다.

## 실행

```bash
node tools/palette/swatch_gen.js
```

검사만 (PNG 미기록):

```bash
node tools/palette/swatch_gen.js --check
```

Node 18+ 면 된다. **외부 의존 0** — PNG 인코더는 내장 `zlib` 로 직접 짰고, 라벨은 3×5 비트맵 폰트로 그린다(시트 자신도 도트 규격이라 ×3 정수 확대가 성립한다).

## 입력 — 이 파일은 색상값을 하나도 갖지 않는다

부대조건(총괄 §1 판정): *값을 생성기 안에 두 번 적으면 그것이 곧 두 벌이다.*

| 무엇 | 어디서 |
|---|---|
| 마스터 56색 | `godot/assets/palettes/master_56.gpl` ← 총괄이 지정한 입력 |
| 색각 교체 4색 | `godot/assets/palettes/colorblind_alt.gpl` (꼬리 4행) |
| 기능 부속 13색 | `docs/assets/팔레트_정본_v*.md` **§5** — `.gpl` 밖이라(대장 §4.9) 정본에서 읽는다 |
| 교체 대응관계 | 같은 정본 **§6** |

생성기가 가진 것은 **ASCII 라벨 매핑**뿐이다(`슬립스트림` → `SYM-SLIP`). 3×5 폰트가 한글을 못 그려서 필요한 표기 변환이며 색상값이 아니다.

## 매 실행이 검사하는 것

하나라도 어긋나면 **PNG 를 쓰지 않고 중단**한다.

- `.gpl` 형식 — 구분자가 **탭**인가 (공백이면 툴에 따라 이름이 깨진다)
- 마스터 56 · RGB 중복 0 · **구성 16+12+16+12** 가 ID 접두와 맞는가 (D10 §2.3)
- `colorblind_alt.gpl` 의 앞 56행이 마스터와 **완전 동일**한가 (D10 §2.4 — 마스터 본체 무접촉)
- 정본 §5 기능 13 · §6 교체 4 의 개수와 짝
- **교차:** 정본 §6 대체색 ⇔ `.gpl` 꼬리 4 · 정본 §6 기본색 ⇔ §5 해당 색

### ⚠ 검사가 덮지 못하는 것 (돌연변이 실측으로 확인 — IMPL-140)

**기능 13색 중 교차 검증되는 것은 §6 교체쌍 4건뿐이다.** 나머지 9건(`SYM-SLIP` `SYM-BRAKE` `SYM-CHANCE` `SYM-PULSE` `GAUGE-OK` `VANE-NORMAL` `VANE-ALERT` `VANE-ELATED` `VANE-DAMAGED`)은 **정본이 유일 출처**라 값을 바꿔도 잡히지 않는다 — 대조는 값이 두 곳에 있을 때만 성립한다. 실측: 정본 §5 의 `VANE-ELATED` hex 를 1자리 바꾼 돌연변이가 **검출되지 않았다**.

생성기가 매 실행에 커버리지(`4/13`)와 미검증 목록을 출력하는 이유다. **검증한 척하지 않기 위한 출력이다.**

> **해소 경로:** 구현 트랙이 `godot/ui/theme/ui_palette.gd` 를 정본 §9.2 매핑표대로 결선하면(현재 [가안] 21건 미종결) 13색 전건에 두 번째 출처가 생긴다. 그때 이 도구에 대조를 추가한다.

## 팔레트를 개정하려면

1. **정본 문서**(`docs/assets/팔레트_정본_v*.md`)를 고친다 — 색상값의 정본은 여기다.
2. `master_56.gpl` / `colorblind_alt.gpl` 을 맞춘다. **구분자는 탭.** 마스터 56색만 담고 기능 13색은 넣지 않는다(파일명 계약 `master_56`).
3. `node tools/palette/swatch_gen.js` — 검사가 통과해야 PNG 가 나온다.
4. 에디터가 켜져 있으면 `--headless --import` 가 죽는다(MCP 포트 3571 충돌 — CLAUDE.md). GDAI `execute_editor_script` 로 `EditorInterface.get_resource_filesystem().scan()` 1회.
5. PNG 는 **LFS + `.import` 커밋**(IMPL-003), `.gpl` 은 평문.

**산출된 PNG 를 손으로 고치지 않는다.** 고치면 원천과 갈리고, 다음 재생성이 조용히 되돌린다.
