-- ============================================================================
-- FMDS — 04. Views + GRANT (DCL)
-- 역할 기반 접근 제어 (1차 요구사항: 회계/감사/부서장 권한 분리)
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
SELECT t.`거래_ID`,
       t.`거래일`,
       t.`기록일`,
       t.`금액`,
       t.`카테고리`,
       c.`계좌명`,
       c.`조직명`
  FROM `거래내역` t
  JOIN `계좌`     c ON c.`계좌_ID` = t.`계좌_ID`;

-- 부서장용: 예산 집행 현황 대시보드
DROP VIEW IF EXISTS `v_예산_집행현황`;
CREATE VIEW `v_예산_집행현황` AS
SELECT s.`조직명`,
       s.`기간`,
       s.`예산금액`                                                              AS 예산,
       COALESCE(ABS(SUM(CASE WHEN t.`금액` < 0 THEN t.`금액` ELSE 0 END)), 0)     AS 집행액,
       ROUND(
         COALESCE(ABS(SUM(CASE WHEN t.`금액` < 0 THEN t.`금액` ELSE 0 END)), 0)
         / s.`예산금액` * 100, 1
       )                                                                          AS `집행률_퍼센트`,
       s.`조직책임자`
  FROM `수립`    s
  JOIN `계좌`    c ON c.`조직명` = s.`조직명`
  LEFT JOIN `거래내역` t
         ON t.`계좌_ID` = c.`계좌_ID`
        AND (
          (s.`기간` = '2026-Q2' AND t.`거래일` BETWEEN '2026-04-01' AND '2026-06-30') OR
          (s.`기간` = '2026-Q3' AND t.`거래일` BETWEEN '2026-07-01' AND '2026-09-30')
        )
 GROUP BY s.`조직명`, s.`기간`, s.`예산금액`, s.`조직책임자`;

-- 부서장용: 부서 거래 요약
DROP VIEW IF EXISTS `v_부서_거래요약`;
CREATE VIEW `v_부서_거래요약` AS
SELECT c.`조직명`,
       DATE_FORMAT(t.`거래일`, '%Y-%m')                              AS 월,
       SUM(CASE WHEN t.`금액` > 0 THEN t.`금액` ELSE 0 END)           AS 수입,
       SUM(CASE WHEN t.`금액` < 0 THEN t.`금액` ELSE 0 END)           AS 지출
  FROM `거래내역` t
  JOIN `계좌`     c ON c.`계좌_ID` = t.`계좌_ID`
 GROUP BY c.`조직명`, DATE_FORMAT(t.`거래일`, '%Y-%m');

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

-- 【회계자】 거래내역 등록·수정 + 계좌 조회 (잔액 확인용)
GRANT SELECT, INSERT, UPDATE ON `fmds`.`거래내역` TO '회계자'@'localhost';
GRANT SELECT                  ON `fmds`.`계좌`     TO '회계자'@'localhost';
GRANT SELECT                  ON `fmds`.`조직`     TO '회계자'@'localhost';

-- 【감사자】 감사 뷰 + 원본 거래내역·계좌 조회만 (수정 불가)
GRANT SELECT ON `fmds`.`v_거래내역_감사용` TO '감사자'@'localhost';
GRANT SELECT ON `fmds`.`거래내역`           TO '감사자'@'localhost';
GRANT SELECT ON `fmds`.`계좌`               TO '감사자'@'localhost';
GRANT SELECT ON `fmds`.`조직`               TO '감사자'@'localhost';

-- 【부서장】 집행 현황 뷰 + 부서 요약 뷰만 (개별 거래 메모 등 미열람)
GRANT SELECT ON `fmds`.`v_예산_집행현황`   TO '부서장'@'localhost';
GRANT SELECT ON `fmds`.`v_부서_거래요약`   TO '부서장'@'localhost';
GRANT SELECT ON `fmds`.`수립`                TO '부서장'@'localhost';
GRANT SELECT ON `fmds`.`예산`                TO '부서장'@'localhost';

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
