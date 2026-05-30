-- ============================================================================
-- FMDS — 04. Views + GRANT (DCL)
-- 역할 기반 접근 제어 (1차 요구사항: 회계/감사/부서장 권한 분리)
-- 정정 사상 반영: 발생일/카테고리 JOIN/수립 정규화 + 신규 테이블 권한.
-- 결합키 정정: 거래내역↔계좌 JOIN을 (조직명, 계좌ID) 결합키로 수행.
--
-- ⚠️ README 참고: 본 파일의 비밀번호는 시연용. 실서비스 사용 금지.
-- ============================================================================

USE fmds;

-- ============================================================================
-- 1. VIEW 정의
-- ============================================================================

-- 감사용: 메모(개인 정보 가능성) 제외, 핵심 컬럼만 노출
DROP VIEW IF EXISTS `v_거래내역_감사용`;
CREATE VIEW `v_거래내역_감사용` AS
SELECT t.`거래ID`,
       t.`발생일`,
       t.`금액`,
       cat.`카테고리명`,
       c.`계좌명`,
       c.`조직명`
  FROM `거래내역` t
  JOIN `계좌`       c   ON c.`조직명` = t.`조직명` AND c.`계좌ID` = t.`계좌ID`
  JOIN `카테고리`   cat ON cat.`카테고리ID` = t.`카테고리ID`;

-- 부서장용: 예산 집행 현황 대시보드
--   수립 fat 정규화 후: 예산금액·기간 = 예산 JOIN, 조직책임자 = 조직 JOIN.
--   집행액은 예산 카테고리에 해당하는 거래만 합산 (기준 관계 활용).
DROP VIEW IF EXISTS `v_예산_집행현황`;
CREATE VIEW `v_예산_집행현황` AS
SELECT s.`조직명`,
       b.`기간`,
       cat.`카테고리명`                                                           AS 예산_카테고리,
       b.`예산금액`                                                                AS 예산,
       COALESCE(ABS(SUM(CASE WHEN t.`금액` < 0 THEN t.`금액` ELSE 0 END)), 0)     AS 집행액,
       ROUND(
         COALESCE(ABS(SUM(CASE WHEN t.`금액` < 0 THEN t.`금액` ELSE 0 END)), 0)
         / b.`예산금액` * 100, 1
       )                                                                          AS `집행률_퍼센트`,
       o.`조직책임자`
  FROM `수립`     s
  JOIN `예산`     b   ON b.`예산ID`     = s.`예산ID`
  JOIN `카테고리` cat ON cat.`카테고리ID` = b.`카테고리ID`
  JOIN `조직`     o   ON o.`조직명`     = s.`조직명`
  -- 집행액은 조직 단위 합산이므로 거래내역을 수립(조직명)에 직접 조인 (계좌 경유 불필요)
  LEFT JOIN `거래내역` t
         ON t.`조직명`     = s.`조직명`
        AND t.`카테고리ID` = b.`카테고리ID`
        AND (
          (b.`기간` = '2026-Q2' AND t.`발생일` BETWEEN '2026-04-01' AND '2026-06-30') OR
          (b.`기간` = '2026-Q3' AND t.`발생일` BETWEEN '2026-07-01' AND '2026-09-30')
        )
 GROUP BY s.`조직명`, b.`기간`, cat.`카테고리명`, b.`예산금액`, o.`조직책임자`;

-- 부서장용: 부서 거래 요약
DROP VIEW IF EXISTS `v_부서_거래요약`;
CREATE VIEW `v_부서_거래요약` AS
SELECT c.`조직명`,
       DATE_FORMAT(t.`발생일`, '%Y-%m')                              AS 월,
       SUM(CASE WHEN t.`금액` > 0 THEN t.`금액` ELSE 0 END)           AS 수입,
       SUM(CASE WHEN t.`금액` < 0 THEN t.`금액` ELSE 0 END)           AS 지출
  FROM `거래내역` t
  JOIN `계좌`     c ON c.`조직명` = t.`조직명` AND c.`계좌ID` = t.`계좌ID`
 GROUP BY c.`조직명`, DATE_FORMAT(t.`발생일`, '%Y-%m');

-- ============================================================================
-- 2. 역할별 사용자 생성
-- ⚠️ 시연용 비밀번호 — 실제 환경에서는 강력한 비밀번호 + IDENTIFIED WITH 인증 플러그인 사용
-- ============================================================================

-- 기존 사용자 정리 (재실행 안전성)
DROP USER IF EXISTS '회계자'@'localhost';
DROP USER IF EXISTS '감사자'@'localhost';
DROP USER IF EXISTS '부서장'@'localhost';

CREATE USER '회계자'@'localhost' IDENTIFIED BY 'DemoAcct!2026';
CREATE USER '감사자'@'localhost' IDENTIFIED BY 'DemoAudit!2026';
CREATE USER '부서장'@'localhost' IDENTIFIED BY 'DemoMgr!2026';

-- ============================================================================
-- 3. 권한 부여 (GRANT)
-- ============================================================================

-- 【회계자】 거래내역 등록·수정 + 카테고리/계좌 조회 (외래키 매핑·잔액 확인용)
GRANT SELECT, INSERT, UPDATE ON `fmds`.`거래내역`   TO '회계자'@'localhost';
GRANT SELECT                  ON `fmds`.`카테고리`   TO '회계자'@'localhost';
GRANT SELECT                  ON `fmds`.`계좌`       TO '회계자'@'localhost';
GRANT SELECT                  ON `fmds`.`조직`       TO '회계자'@'localhost';

-- 【감사자】 감사 뷰 + 원본 거래내역·계좌·카테고리·사원 정보 조회 (수정 불가)
GRANT SELECT ON `fmds`.`v_거래내역_감사용` TO '감사자'@'localhost';
GRANT SELECT ON `fmds`.`거래내역`           TO '감사자'@'localhost';
GRANT SELECT ON `fmds`.`계좌`               TO '감사자'@'localhost';
GRANT SELECT ON `fmds`.`조직`               TO '감사자'@'localhost';
GRANT SELECT ON `fmds`.`카테고리`           TO '감사자'@'localhost';
GRANT SELECT ON `fmds`.`사원`               TO '감사자'@'localhost';
GRANT SELECT ON `fmds`.`조직_전화번호`      TO '감사자'@'localhost';

-- 【부서장】 집행 현황 뷰 + 부서 요약 뷰만 (개별 거래 메모 등 미열람)
GRANT SELECT ON `fmds`.`v_예산_집행현황`   TO '부서장'@'localhost';
GRANT SELECT ON `fmds`.`v_부서_거래요약`   TO '부서장'@'localhost';
GRANT SELECT ON `fmds`.`수립`                TO '부서장'@'localhost';
GRANT SELECT ON `fmds`.`예산`                TO '부서장'@'localhost';
GRANT SELECT ON `fmds`.`카테고리`            TO '부서장'@'localhost';

FLUSH PRIVILEGES;

-- ============================================================================
-- 4. 권한 확인 쿼리
-- ============================================================================
SHOW GRANTS FOR '회계자'@'localhost';
SHOW GRANTS FOR '감사자'@'localhost';
SHOW GRANTS FOR '부서장'@'localhost';

-- ============================================================================
-- 5. REVOKE 예시 (필요 시 권한 회수)
-- ============================================================================
-- REVOKE INSERT, UPDATE ON `fmds`.`거래내역` FROM '회계자'@'localhost';
-- DROP USER '회계자'@'localhost';
