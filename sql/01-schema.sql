-- ============================================================================
-- FMDS — 01. Schema (DDL)
-- 대상 DBMS: MySQL 8.x / MariaDB 10.x
-- 인코딩: utf8mb4 (한글 컬럼·식별자 지원)
--
-- 출처: docs/03-3차과제-릴레이션스키마.pdf (11-1주차 매핑 강의 정정본 반영)
-- 정정 사상: 카테고리 정규화, 사원 자기참조, 조직 전화번호 다중값 분리,
--           수립 fat 정규화, 발생일/수립일 관계 속성, 키 네이밍 통일
-- ============================================================================

DROP DATABASE IF EXISTS fmds;
CREATE DATABASE fmds DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE fmds;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. 조직
--    부서·팀 등 회사 내 조직 단위. 사원·계좌·예산·목표의 상위 컨테이너.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `조직` (
	`조직명`         VARCHAR(50)  NOT NULL,
	`조직종류`       VARCHAR(20)  NOT NULL COMMENT '부서/팀/본부 등',
	`조직책임자`     VARCHAR(50),
	PRIMARY KEY (`조직명`)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. 카테고리 (정규화 결과)
--    거래내역·예산의 분류 기준. 기존 거래내역.카테고리 VARCHAR(30) 자유 입력을
--    별 릴레이션으로 분리하여 마스터 데이터화 (1NF 강화 + 기준 관계 외래키 정합).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `카테고리` (
	`카테고리ID`     INT          NOT NULL AUTO_INCREMENT,
	`카테고리명`     VARCHAR(50)  NOT NULL UNIQUE,
	`구분`           VARCHAR(20)  NOT NULL COMMENT '수입/지출/이체',
	PRIMARY KEY (`카테고리ID`)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. 목표
--    조직별 목표. N:M 설정 관계로 조직과 연결.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `목표` (
	`목표ID`         INT          NOT NULL AUTO_INCREMENT,
	`목표명`         VARCHAR(100) NOT NULL,
	`달성예정일`     DATE,
	PRIMARY KEY (`목표ID`)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. 사원
--    조직 소속 구성원. 자기참조 외래키(상사ID)로 사원 내부 관리 위계 표현
--    (상사 1 : 부하 N).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `사원` (
	`사원ID`         INT          NOT NULL AUTO_INCREMENT,
	`사원명`         VARCHAR(50)  NOT NULL,
	`조직명`         VARCHAR(50)  NOT NULL,
	`상사ID`         INT          NULL COMMENT '직속 상사. 부장(최상위)은 NULL',
	PRIMARY KEY (`사원ID`),
	FOREIGN KEY (`조직명`) REFERENCES `조직`(`조직명`)
		ON UPDATE CASCADE ON DELETE RESTRICT,
	FOREIGN KEY (`상사ID`) REFERENCES `사원`(`사원ID`)
		ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. 조직_전화번호 (다중값 속성 분리)
--    조직(부서)당 N개 대표 연락처 허용 (대표/직통/팩스 등).
--    조직 기본키 + 전화번호 자체를 결합 기본키로.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `조직_전화번호` (
	`조직명`         VARCHAR(50)  NOT NULL,
	`전화번호`       VARCHAR(20)  NOT NULL,
	`종류`           VARCHAR(20)  COMMENT '대표/직통/팩스 등',
	PRIMARY KEY (`조직명`, `전화번호`),
	FOREIGN KEY (`조직명`) REFERENCES `조직`(`조직명`)
		ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. 계좌
--    조직 소유 계좌. 약한 개체(소유 식별 관계)이나 MySQL 구현 편의상
--    대리 기본키(계좌ID) 채택. 조직명 외래키로 식별 관계 의미 보존.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `계좌` (
	`계좌ID`         INT          NOT NULL AUTO_INCREMENT,
	`계좌번호`       VARCHAR(30)  NOT NULL UNIQUE,
	`계좌명`         VARCHAR(50)  NOT NULL,
	`잔액`           DECIMAL(15,2) NOT NULL DEFAULT 0,
	`생성일`         DATE         NOT NULL,
	`조직명`         VARCHAR(50)  NOT NULL,
	PRIMARY KEY (`계좌ID`),
	FOREIGN KEY (`조직명`) REFERENCES `조직`(`조직명`)
		ON UPDATE CASCADE ON DELETE RESTRICT,
	CONSTRAINT `chk_계좌_잔액` CHECK (`잔액` >= 0)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. 예산
--    조직별·카테고리별 예산. 기준 관계(카테고리 1 : 예산 N) 흡수 — 카테고리ID 외래키.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `예산` (
	`예산ID`         INT          NOT NULL AUTO_INCREMENT,
	`카테고리ID`     INT          NOT NULL,
	`예산금액`       DECIMAL(15,2) NOT NULL,
	`기간`           VARCHAR(20)  NOT NULL COMMENT '예: 2026-Q2, 2026-05 등',
	PRIMARY KEY (`예산ID`),
	FOREIGN KEY (`카테고리ID`) REFERENCES `카테고리`(`카테고리ID`)
		ON UPDATE CASCADE ON DELETE RESTRICT,
	CONSTRAINT `chk_예산_금액` CHECK (`예산금액` > 0)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. 거래내역
--    계좌별 거래. 발생일은 발생 관계 속성(기존 거래일·기록일 통합),
--    카테고리ID는 분류 관계 외래키.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `거래내역` (
	`거래ID`         INT          NOT NULL AUTO_INCREMENT,
	`금액`           DECIMAL(15,2) NOT NULL,
	`메모`           VARCHAR(200),
	`발생일`         DATE         NOT NULL COMMENT '관계 속성: 계좌-거래내역 발생일',
	`계좌ID`         INT          NOT NULL,
	`카테고리ID`     INT          NOT NULL,
	PRIMARY KEY (`거래ID`),
	FOREIGN KEY (`계좌ID`)     REFERENCES `계좌`(`계좌ID`)
		ON UPDATE CASCADE ON DELETE RESTRICT,
	FOREIGN KEY (`카테고리ID`) REFERENCES `카테고리`(`카테고리ID`)
		ON UPDATE CASCADE ON DELETE RESTRICT,
	INDEX `idx_거래내역_발생일` (`발생일`),
	INDEX `idx_거래내역_계좌_발생일` (`계좌ID`, `발생일`),
	INDEX `idx_거래내역_카테고리` (`카테고리ID`)
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. 설정 (조직 ↔ 목표 N:M)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `설정` (
	`조직명`         VARCHAR(50)  NOT NULL,
	`목표ID`         INT          NOT NULL,
	PRIMARY KEY (`조직명`, `목표ID`),
	FOREIGN KEY (`조직명`) REFERENCES `조직`(`조직명`)
		ON UPDATE CASCADE ON DELETE CASCADE,
	FOREIGN KEY (`목표ID`) REFERENCES `목표`(`목표ID`)
		ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. 수립 (조직 ↔ 예산 N:M, 관계 속성 수립일 포함)
--     fat 컬럼 6개(조직종류·예산금액·조직전화번호·기간·조직계좌번호·조직책임자)
--     제거 — 부분 함수종속에 의한 2NF 위반 정정.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE `수립` (
	`조직명`         VARCHAR(50)  NOT NULL,
	`예산ID`         INT          NOT NULL,
	`수립일`         DATE         COMMENT '관계 속성: 예산 수립 일자',
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
