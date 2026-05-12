# FMDS SQL 구현 (4차 과제)

3차 과제(`docs/03-3차과제-릴레이션스키마.pdf`)에서 작성한 관계 스키마를 **MySQL 8.x / MariaDB 10.x** 로 구현한 결과물. 11-1주차 강의 매핑 규칙 및 6-1주차 피드백을 모두 반영한 정정본입니다.

## 파일 구성

| 파일 | 내용 |
|---|---|
| `01-schema.sql` | DDL — 테이블 10개 생성, PK·FK 11개·CHECK·INDEX |
| `02-sample-data.sql` | INSERT — 시연용 더미 데이터 (조직 3, 카테고리 14, 사원 8 + 자기참조, 사원_전화번호 11, 계좌 6, 목표 4, 예산 6, 거래 29, 설정 5, 수립 6) |
| `03-queries.sql` | DML — 4개 역할 시나리오 + 자기참조·다중값·기준 활용 쿼리 |
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
INSERT INTO fmds.`거래내역` (`금액`, `메모`, `발생일`, `계좌ID`, `카테고리ID`)
  VALUES (-10000, '권한 테스트', CURDATE(), 1, 1);  -- ✅ 성공

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

## 11-1주차 강의 + 6-1주차 피드백 반영 사항

3차 제출 PDF의 결함 및 강의에서 권장한 추가 표기를 다음과 같이 반영했습니다.

| 항목 | 변경 | 근거 |
|---|---|---|
| **`카테고리` 테이블** | 신규 추가 | 거래내역.카테고리 VARCHAR 자유 입력 → 마스터 테이블 분리 (정규화) |
| **`사원_전화번호` 테이블** | 신규 추가 | 다중값 속성 분리 (매핑 규칙 5) |
| **`사원.상사ID`** | 자기참조 FK 추가 | 관리 관계 (상사 1 : 부하 N) |
| **`예산.카테고리ID`** | FK 추가 | 기준 관계(카테고리 1 : 예산 N) 흡수 |
| **`거래내역` 발생일** | `거래일`·`기록일` → `발생일` 단일화 | 발생 관계의 관계 속성으로 통합 (6-1 지적4) |
| **`수립` fat 컬럼 6개** | 제거 + `수립일` 추가 | 부분 함수종속 해소 (2NF), 관계 속성으로 수립일 신설 |
| **사원 명명** | `학생명`·`학생전화번호` → `사원명` + `사원_전화번호` 분리 | 도메인(회사 부서별 관리) 일관성 |
| **`사원성별`** | 컬럼 추가 | 정정본 일반 속성 반영 |
| **`조직` 테이블** | `조직계좌번호` 컬럼 제거 | 계좌 테이블에 책임 위임 |
| **키 네이밍** | `목표_ID`·`계좌_ID`·`거래_ID` → 무언더스코어 통일 | 정정본 표기 |

## 데이터 모델 요약

```
조직 ─┬─< 사원 ─< 사원_전화번호
      │       └─ (자기참조: 상사ID)
      ├─< 계좌 ─< 거래내역 >─ 카테고리
      ├─< 설정 >─ 목표                      └─< 예산 >── 카테고리 (기준)
      └─< 수립 ──< 예산
            └ 수립일 (관계 속성)
```

- **1:N 관계** (소속/소유/발생/분류/기준/관리): FK 컬럼 직접 보유
- **N:M 관계** (설정/수립): 관계 테이블 별도 + 수립일 관계 속성
- **다중값**: `사원_전화번호` 별도 릴레이션 (결합 PK: 사원ID + 전화번호)
- **자기참조**: `사원.상사ID` → `사원.사원ID`

## 명세 매핑 (1차 요구사항 ↔ SQL)

| 1차 요구사항 | 구현 파일 | 핵심 SQL |
|---|---|---|
| 회계 담당자 거래 등록 | `03-queries.sql` Q1 | `INSERT INTO 거래내역` |
| 감사 조건별 조회 | `03-queries.sql` Q2 | `SELECT ... WHERE 발생일 BETWEEN`, 카테고리·부서·금액 필터 |
| 부서장 예산 집행률 | `03-queries.sql` Q3 + `04-views-grants.sql` `v_예산_집행현황` | 수립 JOIN 예산 JOIN 카테고리, 카테고리별 집행 비교 |
| 동시 접근 정합성 | `05-transactions.sql` | `START TRANSACTION` / `COMMIT` / `FOR UPDATE` |
| 역할별 권한 제한 | `04-views-grants.sql` | `CREATE USER` + `GRANT` 분리 |
| 분석 쿼리 (자기참조·다중값·기준) | `03-queries.sql` Q5 | 부서장-부하 위계, 사원별 연락처, 카테고리별 예산 vs 집행 |

## 정합성 체크리스트

순차 실행 후 다음을 확인하세요:

- [ ] 테이블 10개 생성 (`SHOW TABLES`)
- [ ] FK 11개 정상 등록 (`information_schema.KEY_COLUMN_USAGE` 조회)
- [ ] 카테고리 마스터 14건
- [ ] 사원 8명 (부장 3명 상사ID NULL, 팀원 5명 부장ID 참조)
- [ ] 사원_전화번호 11건 (사원당 1~2건)
- [ ] 거래내역 29건, 발생일 컬럼만 존재
- [ ] 예산 6건, 카테고리ID FK 매핑
- [ ] 수립 6건, fat 컬럼 제거 + 수립일 채워짐
- [ ] 뷰 3개 SELECT 가능
- [ ] GRANT 시연: 회계자 INSERT 성공, 감사자 INSERT 실패, 부서장 거래내역 직접 조회 실패

## ⚠️ 보안 주의

- `04-views-grants.sql`의 비밀번호 (`DemoAcct!2026` 등) 는 **시연·평가용**. 실서비스 사용 금지
- 한글 식별자는 utf8mb4 인코딩 + 백틱(`` ` ``) 필수
- 실 환경 배포 시 별도 보안 검토 필요
