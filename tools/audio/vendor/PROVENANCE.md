# 벤더링 출처 — jsfxr · 외부 도구 대장

본 디렉토리의 `sfxr.js` · `riffwave.js` 는 **상류 배포본을 한 바이트도 고치지 않고 그대로 둔 사본**이다.
고치지 않는 것이 요점이다 — 아래 해시로 상류와 대조할 수 있고, 시드 주입 같은 우리 쪽 요구는
**호출 측(`../sfx_gen.js`)에서** 처리한다(§2).

## 1. 출처

| 항목 | 값 |
|---|---|
| 패키지 | `jsfxr` |
| 버전 | **1.4.1** |
| 배포처 | `https://registry.npmjs.org/jsfxr/-/jsfxr-1.4.1.tgz` |
| 저장소 | `https://github.com/chr15m/jsfxr` |
| npm `dist.shasum` | `b379c2d27172cf9579a417319f36c769e325c848` |
| npm `dist.integrity` | `sha512-Xbamo2dpLF5B+ssyv6TUEIoHJ/KRt4SRK2J3JOOmUG+45XBjkGKTjR/KOyQ9sqjrx/uea/UTWI0+p5pOVm1bUw==` |
| 취득 일자 | 2026-08-19 (IMPL-245) |
| 라이선스 | **UNLICENSE (퍼블릭 도메인)** — 사본 동봉 |

## 2. 사본 해시 (SHA-256) — 상류 대조용

```
6095a6358e654bc3ffd55d9ccecf694f187953d78b1391ee2823a6fcb92551c5  sfxr.js
ab3cea2bd157746d7b01b440a38d1eefc0c7b3bcb464b5aa80ccbd66be4daaec  riffwave.js
7b30c10d168b77d43ddaa3269e7bef3e1a9dd68a54a5f23f1630a653d7e2e2f4  UNLICENSE
```

재검 = `npm pack jsfxr@1.4.1` 후 `sha256sum` 대조. **불일치는 상류 변조이거나 우리 쪽 오염이며 둘 다 사고다.**

## 3. 왜 벤더링인가 (npm 의존이 아니라)

- **재생성이 네트워크에 걸리면 안 된다.** 이 저장소의 재현 계약은 *"재현 = 같은 명령"* 이고(IMPL-097·139 전례 · `swatch_gen.js`·`icon_draw.js` 동형), `npm install` 은 레지스트리 가용성·버전 해석·`node_modules` 미커밋이라는 세 변수를 재생성 경로에 끼워 넣는다.
- **라이선스가 그것을 허용한다** — UNLICENSE(퍼블릭 도메인)라 사본 배포에 조건이 없다. 출처 표기는 의무가 아니라 **우리 쪽 위생**으로 남긴다.
- **런타임 의존이 0 이다** — `package.json` 의 의존은 devDependencies 뿐이라 사본 2파일이 자족한다.

---

## 4. 시스템 도구 — `oggenc` (2026-08-20 · IMPL-274 · BGM 파일럿)

**벤더 사본이 아니라 시스템 설치분이다** — 성격이 위 사본과 다르므로 갈라 적는다. 사본은 리포 안에 있어 바이트가 고정되지만, 시스템 도구는 **머신마다 다를 수 있다.**

| 항목 | 값 |
|---|---|
| 도구 | `oggenc` (+ 검증용 `oggdec`·`ogginfo`) |
| 패키지 | `vorbis-tools` **1.4.3** (Debian/Ubuntu `1.4.3-1build1`, amd64) |
| 설치 | 사용자 승인·실행 (2026-08-20 — 총괄 기안 §5.2-1 선행 조건) |
| 호출 | `oggenc -Q -q <quality> --serial <serial> -o out.ogg in.wav` |

**`--serial` 고정이 재현 계약의 필수 조건이다 (실측).** 고정하지 않으면 **같은 입력·같은 설정이 매번 다른 바이트**를 낸다 — Ogg 스트림 시리얼과 그것에 딸린 페이지 CRC 32바이트가 달라진다(3회 실측: 미고정 전건 상이 · 고정 3/3 동일). 시리얼은 트랙별로 `bgm_params.json` 에 커밋한다.

**q 매핑:** D12 §10.1 의 "~q0.7" 은 libvorbis 정규화 품질(−0.1~1.0)이고 `oggenc -q` 는 그 10배 스케일(0~10)이므로 **q0.7 = `-q 7`** 이다. 실측 산출 = 122kbps(모노 117.6초).

**버전이 바뀌면 바이트가 바뀔 수 있다.** 인코더 갱신 회차는 `bgm_gen.js --check` 가 먼저 깨지므로 **조용히 지나가지 않는다** — 깨졌을 때 판단할 근거로 이 표를 둔다. (벤더 사본의 "갱신 시 공식 재대조" 조건과 같은 성격 — 대장 §7 조건 ⓑ 계열.)
