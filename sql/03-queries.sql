-- ============================================================================
-- FMDS — 03. Core DML Queries
-- 1차 요구사항 4개 역할별 시나리오 대응.
-- 정정 사상 반영: 카테고리 JOIN, 발생일 단일화, 수립 fat 제거(예산·조직 JOIN),
--                 키 네이밍 통일, 자기참조·다중값(조직 전화번호)·기준관계 활용 쿼리.
-- 결합키 정정: 거래내역은 약한 개체 (조직명, 계좌ID, 거래ID) 결합키이므로
--             등록 시 부모 키(조직명·계좌ID) 명시 + 부분키(거래ID) 산출,
--             계좌 JOIN은 (조직명, 계좌ID) 결합키로 수행.
-- ============================================================================

USE fmds;

-- ============================================================================
-- 【역할 1】 회계 담당자 — 수입·지출 거래 등록
-- 요구: 일자, 금액, 카테고리, 담당자(계좌→조직→담당자), 결제수단(메모) 기록
-- ============================================================================

-- Q1-1. 거래 등록 (영업1팀 운영계좌에 식비 지출)
--   거래ID는 계좌 scope 부분키이므로 해당 계좌의 MAX(거래ID)+1 로 산출 (재실행 안전).
INSERT INTO `거래내역` (`조직명`, `계좌ID`, `거래ID`, `금액`, `메모`, `발생일`, `카테고리ID`)
SELECT '영업1팀', 1, COALESCE(MAX(`거래ID`), 0) + 1,
       -75000.00, '카드결제 / 거래처 미팅', '2026-05-11', 1
  FROM `거래내역`
 WHERE `조직명` = '영업1팀' AND `계좌ID` = 1;

-- Q1-2. 잘못 입력한 거래 수정 (메모만 수정)
--   방금 등록한 거래(해당 계좌의 최신 거래ID)를 결합키로 지정.
UPDATE `거래내역`
   SET `메모` = '카드결제 / 거래처 미팅 — 김동인'
 WHERE `조직명` = '영업1팀' AND `계좌ID` = 1
   AND `거래ID` = (
     SELECT m FROM (
       SELECT MAX(`거래ID`) AS m FROM `거래내역`
        WHERE `조직명` = '영업1팀' AND `계좌ID` = 1
     ) AS x
   );

-- Q1-3. 거래 취소 (삭제) — 결합키로 특정 거래 지정
-- DELETE FROM `거래내역`
--  WHERE `조직명` = '영업1팀' AND `계좌ID` = 1 AND `거래ID` = <대상 거래ID>;

-- ============================================================================
-- 【역할 2】 감사 담당자 — 조건별 조회 (수정 권한 없음)
-- ============================================================================

-- Q2-1. 기간별 거래 조회 (2026년 4월)
SELECT t.`거래ID`, t.`발생일`, t.`금액`, cat.`카테고리명`, t.`메모`,
       c.`계좌명`, c.`조직명`
  FROM `거래내역` t
  JOIN `계좌`       c   ON c.`조직명` = t.`조직명` AND c.`계좌ID` = t.`계좌ID`
  JOIN `카테고리`   cat ON cat.`카테고리ID` = t.`카테고리ID`
 WHERE t.`발생일` BETWEEN '2026-04-01' AND '2026-04-30'
 ORDER BY t.`발생일`;

-- Q2-2. 카테고리별 거래 조회 (인프라 비용)
SELECT t.`발생일`, t.`금액`, t.`메모`, c.`계좌명`, c.`조직명`
  FROM `거래내역` t
  JOIN `계좌`       c   ON c.`조직명` = t.`조직명` AND c.`계좌ID` = t.`계좌ID`
  JOIN `카테고리`   cat ON cat.`카테고리ID` = t.`카테고리ID`
 WHERE cat.`카테고리명` = '인프라'
 ORDER BY t.`발생일`;

-- Q2-3. 부서별 거래 조회 (개발1팀 전체)
SELECT t.`발생일`, cat.`카테고리명`, t.`금액`, c.`계좌명`
  FROM `거래내역` t
  JOIN `계좌`       c   ON c.`조직명` = t.`조직명` AND c.`계좌ID` = t.`계좌ID`
  JOIN `카테고리`   cat ON cat.`카테고리ID` = t.`카테고리ID`
 WHERE c.`조직명` = '개발1팀'
 ORDER BY t.`발생일` DESC;

-- Q2-4. 고액 거래 조회 (50만원 초과 지출)
SELECT t.`발생일`, c.`조직명`, c.`계좌명`, cat.`카테고리명`, t.`금액`, t.`메모`
  FROM `거래내역` t
  JOIN `계좌`       c   ON c.`조직명` = t.`조직명` AND c.`계좌ID` = t.`계좌ID`
  JOIN `카테고리`   cat ON cat.`카테고리ID` = t.`카테고리ID`
 WHERE t.`금액` < -500000
 ORDER BY t.`금액` ASC;

-- ============================================================================
-- 【역할 3】 부서장(관리자) — 예산 집행률 리포트
-- 수립 fat 정규화 후: 예산금액·기간은 예산 JOIN, 조직책임자는 조직 JOIN.
-- ============================================================================

-- Q3-1. 부서별 Q2 예산 집행률
--   집행액 = SUM(예산 카테고리에 해당하는 지출 거래, 음수 합계의 절대값)
--   집행률 = 집행액 / 예산금액 × 100
SELECT s.`조직명`,
       b.`기간`,
       cat.`카테고리명`,
       b.`예산금액`                                       AS 예산,
       COALESCE(ABS(SUM(CASE WHEN t.`금액` < 0 THEN t.`금액` ELSE 0 END)), 0) AS 집행액,
       ROUND(
         COALESCE(ABS(SUM(CASE WHEN t.`금액` < 0 THEN t.`금액` ELSE 0 END)), 0)
         / b.`예산금액` * 100, 1
       )                                                  AS `집행률(%)`
  FROM `수립`     s
  JOIN `예산`     b ON b.`예산ID` = s.`예산ID`
  JOIN `카테고리` cat ON cat.`카테고리ID` = b.`카테고리ID`
  -- 집행액은 조직 단위 합산이므로 거래내역을 수립(조직명)에 직접 조인 (계좌 경유 불필요)
  LEFT JOIN `거래내역` t
         ON t.`조직명`     = s.`조직명`
        AND t.`카테고리ID` = b.`카테고리ID`
        AND t.`발생일` BETWEEN '2026-04-01' AND '2026-06-30'  -- Q2 = 4~6월
 WHERE b.`기간` = '2026-Q2'
 GROUP BY s.`조직명`, b.`기간`, cat.`카테고리명`, b.`예산금액`
 ORDER BY `집행률(%)` DESC;

-- Q3-2. 예산 초과 위험 부서 (집행률 70% 이상)
--   서브쿼리 + HAVING
SELECT 조직명, `집행률(%)`
  FROM (
    SELECT s.`조직명`,
           ROUND(
             COALESCE(ABS(SUM(CASE WHEN t.`금액` < 0 THEN t.`금액` ELSE 0 END)), 0)
             / b.`예산금액` * 100, 1
           ) AS `집행률(%)`
      FROM `수립`     s
      JOIN `예산`     b ON b.`예산ID` = s.`예산ID`
      LEFT JOIN `거래내역` t
             ON t.`조직명`     = s.`조직명`
            AND t.`카테고리ID` = b.`카테고리ID`
            AND t.`발생일` BETWEEN '2026-04-01' AND '2026-06-30'
     WHERE b.`기간` = '2026-Q2'
     GROUP BY s.`조직명`, b.`카테고리ID`, b.`예산금액`
  ) AS x
 WHERE `집행률(%)` >= 70
 ORDER BY `집행률(%)` DESC;

-- ============================================================================
-- 【역할 4】 시스템 — 집계·분석 쿼리
-- ============================================================================

-- Q4-1. 부서별·카테고리별 지출 합계
SELECT c.`조직명`,
       cat.`카테고리명`,
       COUNT(*)                AS 건수,
       SUM(t.`금액`)            AS 합계,
       ROUND(AVG(t.`금액`), 0) AS 평균
  FROM `거래내역` t
  JOIN `계좌`       c   ON c.`조직명` = t.`조직명` AND c.`계좌ID` = t.`계좌ID`
  JOIN `카테고리`   cat ON cat.`카테고리ID` = t.`카테고리ID`
 WHERE t.`금액` < 0
 GROUP BY c.`조직명`, cat.`카테고리명`
 ORDER BY c.`조직명`, 합계 ASC;

-- Q4-2. 월별 수입·지출 추이
SELECT DATE_FORMAT(t.`발생일`, '%Y-%m') AS 월,
       SUM(CASE WHEN t.`금액` > 0 THEN t.`금액` ELSE 0 END) AS 수입,
       SUM(CASE WHEN t.`금액` < 0 THEN t.`금액` ELSE 0 END) AS 지출,
       SUM(t.`금액`)                                       AS 순증감
  FROM `거래내역` t
 GROUP BY DATE_FORMAT(t.`발생일`, '%Y-%m')
 ORDER BY 월;

-- Q4-3. 계좌별 잔액 + 거래건수 (대시보드)
SELECT c.`계좌명`, c.`조직명`, c.`잔액`,
       COUNT(t.`거래ID`)              AS 거래건수,
       MAX(t.`발생일`)                AS 최근거래일
  FROM `계좌`     c
  LEFT JOIN `거래내역` t ON t.`조직명` = c.`조직명` AND t.`계좌ID` = c.`계좌ID`
 GROUP BY c.`조직명`, c.`계좌ID`, c.`계좌명`, c.`잔액`
 ORDER BY c.`잔액` DESC;

-- Q4-4. 조직별 목표 + 예산 종합 뷰
--   목표(설정 N:M)와 예산(수립 N:M)을 한 쿼리에서 JOIN하면 카티전 곱으로
--   예산금액이 목표 수만큼 중복 집계됨 → 예산 합계는 상관 서브쿼리로 분리 집계.
SELECT o.`조직명`, o.`조직책임자`,
       GROUP_CONCAT(DISTINCT g.`목표명` SEPARATOR ', ')   AS 목표목록,
       COALESCE((
         SELECT SUM(b.`예산금액`)
           FROM `수립` sb
           JOIN `예산` b ON b.`예산ID` = sb.`예산ID`
          WHERE sb.`조직명` = o.`조직명`
       ), 0)                                              AS Q2_Q3_예산합계
  FROM `조직` o
  LEFT JOIN `설정` sg ON sg.`조직명` = o.`조직명`
  LEFT JOIN `목표` g  ON g.`목표ID` = sg.`목표ID`
 GROUP BY o.`조직명`, o.`조직책임자`;

-- ============================================================================
-- 정정 신규 쿼리 (자기참조 / 다중값 / 기준 관계 활용)
-- ============================================================================

-- Q5-1. 부서장(상사ID=NULL)별 직속 부하 목록 (자기참조)
SELECT boss.`사원명` AS 부서장,
       boss.`조직명`,
       COUNT(sub.`사원ID`)                    AS 직속부하수,
       GROUP_CONCAT(sub.`사원명` SEPARATOR ', ') AS 부하목록
  FROM `사원` boss
  LEFT JOIN `사원` sub ON sub.`상사ID` = boss.`사원ID`
 WHERE boss.`상사ID` IS NULL
 GROUP BY boss.`사원ID`, boss.`사원명`, boss.`조직명`
 ORDER BY boss.`조직명`;

-- Q5-2. 조직별 등록 전화번호 수 + 목록 (다중값 분리)
SELECT o.`조직명`,
       o.`조직종류`,
       COUNT(p.`전화번호`)                                AS 연락처수,
       GROUP_CONCAT(CONCAT(p.`종류`, ':', p.`전화번호`) SEPARATOR ' / ') AS 연락처목록
  FROM `조직` o
  LEFT JOIN `조직_전화번호` p ON p.`조직명` = o.`조직명`
 GROUP BY o.`조직명`, o.`조직종류`
 ORDER BY 연락처수 DESC, o.`조직명`;

-- Q5-3. 카테고리별 예산 vs 실제 집행 비교 (기준 관계)
--   예산(1:N)과 거래(1:N)를 카테고리에 동시 JOIN하면 양쪽이 서로를 곱해
--   총지출이 예산 건수만큼 중복 집계됨 → 예산·거래를 각각 선집계 후 결합.
SELECT cat.`카테고리명`,
       cat.`구분`,
       COALESCE(bud.`총예산`, 0) AS 총예산,
       COALESCE(txn.`총지출`, 0) AS 총지출,
       COALESCE(txn.`거래수`, 0) AS 거래수
  FROM `카테고리` cat
  LEFT JOIN (
        SELECT `카테고리ID`, SUM(`예산금액`) AS `총예산`
          FROM `예산`
         GROUP BY `카테고리ID`
       ) bud ON bud.`카테고리ID` = cat.`카테고리ID`
  LEFT JOIN (
        SELECT `카테고리ID`,
               ABS(SUM(CASE WHEN `금액` < 0 THEN `금액` ELSE 0 END)) AS `총지출`,
               COUNT(*)                                              AS `거래수`
          FROM `거래내역`
         GROUP BY `카테고리ID`
       ) txn ON txn.`카테고리ID` = cat.`카테고리ID`
 ORDER BY cat.`구분`, cat.`카테고리명`;
