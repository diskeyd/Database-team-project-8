-- ============================================================================
-- FMDS — 01. Schema (DDL)
-- 대상 DBMS: MySQL 8.x / MariaDB 10.x
-- 인코딩: utf8mb4 (한글 컬럼·식별자 지원)
--
-- 출처: docs/03-3차과제-릴레이션스키마.pdf
--
-- ★ 3차 PDF 보강 사항 (자세한 내용은 sql/README.md 참조)
--   1) `조직`, `예산` 테이블 — PDF 릴레이션 목록에 누락되어 있었으나,
--      `사원.조직명`, `계좌.조직명`, `수립.예산ID` 의 FK 정합성 보장을 위해 추가.
--   2) `거래내역.거래일` — ERD에는 존재하나 릴레이션 목록 누락(오타로 추정).
--      감사 쿼리(기간별 조회)의 필수 컬럼이므로 추가.
--   3) `수립` 테이블의 fat 컬럼(조직종류·조직전화번호·조직책임자·조직계좌번호)
--      은 PDF 그대로 유지 — 정규화(2NF) 위반이나 제출본 충실성 우선.
-- ============================================================================

DROP DATABASE IF EXISTS fmds;
CREATE DATABASE fmds DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE fmds;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. 조직 (PDF 보강)
--    부서·팀 등 회사 내 조직 단위. 사원·계좌·예산·목표의 상위 컨테이너.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `조직` (
	`조직명`         VARCHAR(50)  NOT NULL,
	`조직종류`       VARCHAR(20)  NOT NULL COMMENT '부서/팀/본부 등',
	`조직전화번호`   VARCHAR(20),
	`조직계좌번호`   VARCHAR(30),
	`조직책임자`     VARCHAR(50),
	PRIMARY KEY (`조직명`)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. 사원
--    조직에 소속된 구성원. (PDF의 '학생*' 명칭은 그대로 유지)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `사원` (
	`사원ID`         INT          NOT NULL AUTO_INCREMENT,
	`학생명`         VARCHAR(50)  NOT NULL,
	`학생전화번호`   VARCHAR(20),
	`조직명`         VARCHAR(50)  NOT NULL,
	PRIMARY KEY (`사원ID`),
	FOREIGN KEY (`조직명`) REFERENCES `조직`(`조직명`)
		ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. 목표
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `목표` (
	`목표_ID`        INT          NOT NULL AUTO_INCREMENT,
	`목표명`         VARCHAR(100) NOT NULL,
	`달성예정일`     DATE,
	PRIMARY KEY (`목표_ID`)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. 계좌
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `계좌` (
	`계좌_ID`        INT          NOT NULL AUTO_INCREMENT,
	`계좌번호`       VARCHAR(30)  NOT NULL UNIQUE,
	`계좌명`         VARCHAR(50)  NOT NULL,
	`잔액`           DECIMAL(15,2) NOT NULL DEFAULT 0,
	`조직명`         VARCHAR(50)  NOT NULL,
	PRIMARY KEY (`계좌_ID`),
	FOREIGN KEY (`조직명`) REFERENCES `조직`(`조직명`)
		ON UPDATE CASCADE ON DELETE RESTRICT,
	CONSTRAINT `chk_계좌_잔액` CHECK (`잔액` >= 0)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. 거래내역
--    ★ `거래일` 컬럼은 PDF 릴레이션 목록 누락분 보강 (ERD엔 존재)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `거래내역` (
	`거래_ID`        INT          NOT NULL AUTO_INCREMENT,
	`금액`           DECIMAL(15,2) NOT NULL,
	`카테고리`       VARCHAR(30)  NOT NULL COMMENT '식비/교통/회식/사무용품 등',
	`메모`           VARCHAR(200),
	`거래일`         DATE         NOT NULL,
	`기록일`         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
	`계좌_ID`        INT          NOT NULL,
	PRIMARY KEY (`거래_ID`),
	FOREIGN KEY (`계좌_ID`) REFERENCES `계좌`(`계좌_ID`)
		ON UPDATE CASCADE ON DELETE RESTRICT,
	INDEX `idx_거래내역_거래일` (`거래일`),
	INDEX `idx_거래내역_계좌_거래일` (`계좌_ID`, `거래일`),
	INDEX `idx_거래내역_카테고리` (`카테고리`)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. 예산 (PDF 보강)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `예산` (
	`예산ID`         INT          NOT NULL AUTO_INCREMENT,
	`예산금액`       DECIMAL(15,2) NOT NULL,
	`기간`           VARCHAR(20)  NOT NULL COMMENT '예: 2026-Q2, 2026-05 등',
	PRIMARY KEY (`예산ID`),
	CONSTRAINT `chk_예산_금액` CHECK (`예산금액` > 0)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. 설정 (조직 ↔ 목표 N:M)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `설정` (
	`조직명`         VARCHAR(50)  NOT NULL,
	`목표_ID`        INT          NOT NULL,
	PRIMARY KEY (`조직명`, `목표_ID`),
	FOREIGN KEY (`조직명`)  REFERENCES `조직`(`조직명`)
		ON UPDATE CASCADE ON DELETE CASCADE,
	FOREIGN KEY (`목표_ID`) REFERENCES `목표`(`목표_ID`)
		ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. 수립 (조직 ↔ 예산 N:M, fat 컬럼은 PDF 그대로)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `수립` (
	`조직명`         VARCHAR(50)  NOT NULL,
	`예산ID`         INT          NOT NULL,
	`조직종류`       VARCHAR(20)  COMMENT '※ 조직 테이블과 중복 — PDF 충실 구현',
	`예산금액`       DECIMAL(15,2) COMMENT '※ 예산 테이블과 중복',
	`조직전화번호`   VARCHAR(20)  COMMENT '※ 조직 테이블과 중복',
	`기간`           VARCHAR(20)  COMMENT '※ 예산 테이블과 중복',
	`조직계좌번호`   VARCHAR(30)  COMMENT '※ 조직 테이블과 중복',
	`조직책임자`     VARCHAR(50)  COMMENT '※ 조직 테이블과 중복',
	PRIMARY KEY (`조직명`, `예산ID`),
	FOREIGN KEY (`조직명`) REFERENCES `조직`(`조직명`)
		ON UPDATE CASCADE ON DELETE CASCADE,
	FOREIGN KEY (`예산ID`) REFERENCES `예산`(`예산ID`)
		ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 생성 확인
-- ─────────────────────────────────────────────────────────────────────────────
SHOW TABLES;
