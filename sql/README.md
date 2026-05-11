# FMDS SQL 구현 (4차 과제)

3차 과제(`docs/03-3차과제-릴레이션스키마.pdf`)에서 작성한 관계 스키마를 **MySQL 8.x / MariaDB 10.x** 로 구현한 결과물.

## 파일 구성

| 파일 | 내용 |
|---|---|
| `01-schema.sql` | DDL — 테이블 8개 생성, PK·FK·CHECK·INDEX |
| `02-sample-data.sql` | INSERT — 시연용 더미 데이터 (조직 3, 사원 8, 계좌 6, 거래 28+, 목표 4, 예산 6) |
| `03-queries.sql` | DML — 4개 역할 시나리오 대응 SELECT/INSERT/UPDATE |
| `04-views-grants.sql` | DCL — VIEW 3개 + USER 3명 + GRANT (회계/감사/부서장 권한 분리) |
| `05-transactions.sql` | 트랜잭션 — 계좌 이체, ROLLBACK, FOR UPDATE 락, 격리수준, 트리거 |

## 실행 방법

### 1. MySQL 접속

```bash
mysql -u root -p
```

### 2. 순차 실행

```bash
mysql -u root -p < 01-schema.sql
mysql -u root -p < 02-sample-data.sql
mysql -u root -p < 03-queries.sql
mysql -u root -p < 04-views-grants.sql
mysql -u root -p < 05-transactions.sql
```

또는 MySQL 셸 안에서:

```sql
SOURCE 01-schema.sql;
SOURCE 02-sample-data.sql;
SOURCE 03-queries.sql;
SOURCE 04-views-grants.sql;
SOURCE 05-transactions.sql;
```

### 3. 역할별 접속 테스트 (권한 시연)

```bash
# 회계자: INSERT 가능
mysql -u 회계자 -p
# 비밀번호: DemoAcct!2026
INSERT INTO fmds.`거래내역` (`금액`, `카테고리`, `메모`, `거래일`, `계좌_ID`)
  VALUES (-10000, '식비', '권한 테스트', CURDATE(), 1);  -- ✅ 성공

# 감사자: SELECT만 가능
mysql -u 감사자 -p
# 비밀번호: DemoAudit!2026
SELECT * FROM fmds.v_거래내역_감사용 LIMIT 5;            -- ✅ 성공
INSERT INTO fmds.`거래내역` ... ;                        -- ❌ ERROR 1142

# 부서장: 집행현황 뷰만
mysql -u 부서장 -p
# 비밀번호: DemoMgr!2026
SELECT * FROM fmds.v_예산_집행현황;                       -- ✅ 성공
SELECT * FROM fmds.`거래내역`;                            -- ❌ ERROR 1142
```

## 3차 스키마 보강 사항

PDF 제출본의 누락·오타를 보강했음. 모든 변경은 SQL 코멘트로 명시.

| 항목 | 변경 | 사유 |
|---|---|---|
| **`조직` 테이블** | 신규 추가 | `사원.조직명`, `계좌.조직명` FK 참조 대상. ERD엔 있으나 릴레이션 목록 누락 |
| **`예산` 테이블** | 신규 추가 | `수립.예산ID` FK 참조 대상. 동일 이유 |
| **`거래내역.거래일`** | 컬럼 추가 | ERD엔 존재. 감사 쿼리(기간 조회)에 필수. 릴레이션 목록 오타로 추정 |
| **`수립`의 fat 컬럼** | PDF 그대로 유지 | `조직종류`·`조직전화번호`·`조직책임자`·`조직계좌번호`·`예산금액`·`기간` 모두 중복 저장 |

### 정규화 한계

`수립` 테이블은 `조직`·`예산` 속성을 중복 저장 → **2NF 위반** (부분 함수 종속). 3차 제출본을 충실히 구현하기 위해 그대로 유지했으나, 운영 환경에서는 다음 정규화 권장:

```sql
-- 정규화된 형태 (참고)
CREATE TABLE `수립_정규화` (
	`조직명` VARCHAR(50),
	`예산ID` INT,
	PRIMARY KEY (`조직명`, `예산ID`),
	FOREIGN KEY (`조직명`) REFERENCES `조직`(`조직명`),
	FOREIGN KEY (`예산ID`) REFERENCES `예산`(`예산ID`)
);
```

## 데이터 모델 요약

```
조직 ─┬─< 사원
      ├─< 계좌 ─< 거래내역
      ├─< 설정 >─ 목표
      └─< 수립 >─ 예산
```

- **1:N 관계** (소속/소유/발생): FK 컬럼 직접 보유
- **N:M 관계** (설정/수립): 관계 테이블 별도

## 명세 매핑 (1차 요구사항 ↔ SQL)

| 1차 요구사항 | 구현 파일 | 핵심 SQL |
|---|---|---|
| 회계 담당자 거래 등록 | `03-queries.sql` Q1 | `INSERT INTO 거래내역` |
| 감사 조건별 조회 | `03-queries.sql` Q2 | `SELECT ... WHERE 거래일 BETWEEN`, 카테고리·부서·금액 필터 |
| 부서장 예산 집행률 | `03-queries.sql` Q3 + `04-views-grants.sql` `v_예산_집행현황` | `JOIN ... GROUP BY` + 백분율 |
| 동시 접근 정합성 | `05-transactions.sql` | `START TRANSACTION` / `COMMIT` / `FOR UPDATE` |
| 역할별 권한 제한 | `04-views-grants.sql` | `CREATE USER` + `GRANT` 분리 |

## ⚠️ 보안 주의

- `04-views-grants.sql`의 비밀번호 (`DemoAcct!2026` 등) 는 **시연·평가용**. 실서비스 사용 금지
- 한글 식별자는 utf8mb4 인코딩 + 백틱(`` ` ``) 필수
- 실 환경 배포 시 별도 보안 검토 필요

## 향후 개선 (5차 이후)

- 수립 fat 컬럼 정규화 (`수립_정규화`로 분리)
- 사원의 "학생*" 명칭 → 회사 도메인 명칭으로 정리 (예: `사원명`, `사원전화번호`)
- 사원에 `역할` 컬럼 추가 (회계/감사/부서장/일반) — 권한 매핑 일관화
- 카테고리를 별도 테이블로 분리 (현재 `거래내역.카테고리`는 free-text)
