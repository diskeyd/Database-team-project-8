# FMDS DBML Schema

> 시각화: https://dbdiagram.io/d/69be2a39fb2db18e3bcf8471
> 작성: 김동인 (AI 보조), 2026-03-21

## 테이블 구성 (6개)

| 테이블 | 역할 |
|--------|------|
| 사용자 | 시스템 사용자 계정 |
| 계좌 | 사용자별 계좌 (수입/지출 주체) |
| 거래내역 | 계좌 기준 수입·지출 기록 |
| 카테고리 | 거래 분류 (수입/지출 구분) |
| 목표 | 사용자별 저축 목표 |
| 예산 | 카테고리별 예산 설정 |

> **주의**: 본 DBML은 1차 과제 단계(개인/단체 가계부 관점) 기준 초안이다. 2차 과제 이후 회사 부서별 관리 시스템으로 피벗하면서 ER 다이어그램이 재설계되었으며, 그 결과는 [`../docs/02-2차과제-ERD.pdf`](../docs/02-2차과제-ERD.pdf) 및 [`../docs/03-3차과제-릴레이션스키마.pdf`](../docs/03-3차과제-릴레이션스키마.pdf)를 참조.

## DBML

```dbml
Table "사용자" {
  "사용자_ID" INT [pk, increment]
  "이름" VARCHAR(50)
  "이메일" VARCHAR(100)
  "가입일" DATETIME
}

Table "계좌" {
  "계좌_ID" INT [pk, increment]
  "사용자_ID" INT
  "계좌명" VARCHAR(50)
  "계좌종류" VARCHAR(20)
  "잔액" DECIMAL(12,2)
  "생성일" DATETIME
}

Table "카테고리" {
  "카테고리_ID" INT [pk, increment]
  "카테고리명" VARCHAR(50)
  "구분" VARCHAR(10) // 수입/지출
}

Table "거래내역" {
  "거래_ID" INT [pk, increment]
  "계좌_ID" INT
  "카테고리_ID" INT
  "금액" DECIMAL(12,2)
  "메모" VARCHAR(200)
  "거래일" DATE
  "기록일" DATETIME
}

Table "목표" {
  "목표_ID" INT [pk, increment]
  "사용자_ID" INT
  "목표명" VARCHAR(50)
  "목표금액" DECIMAL(12,2)
  "현재금액" DECIMAL(12,2)
  "달성예정일" DATE
}

Table "예산" {
  "예산_ID" INT [pk, increment]
  "사용자_ID" INT
  "카테고리_ID" INT
  "예산금액" DECIMAL(12,2)
  "시작일" DATE
  "종료일" DATE
}

Ref: "사용자"."사용자_ID" < "계좌"."사용자_ID"
Ref: "계좌"."계좌_ID" < "거래내역"."계좌_ID"
Ref: "카테고리"."카테고리_ID" < "거래내역"."카테고리_ID"
Ref: "사용자"."사용자_ID" < "목표"."사용자_ID"
Ref: "사용자"."사용자_ID" < "예산"."사용자_ID"
Ref: "카테고리"."카테고리_ID" < "예산"."카테고리_ID"
```
