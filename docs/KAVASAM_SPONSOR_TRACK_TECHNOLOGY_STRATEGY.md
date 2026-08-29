# KAVASAM Sponsor Technology Utilization & Hackathon Track Strategy

> Implementation truth source: see `ANDROID_BUILD_AND_SPONSOR_STATUS.md`. Sponsor features must be described as integrated, credential-required, deployed, or future exactly as recorded there. Do not present planned MongoDB/Render work as already live.

## Purpose

This document defines the efficient use of PEC Hacks 4.0 sponsor
technologies and special tracks for KAVASAM.

The goal is NOT to integrate every sponsor tool.

The goal is to selectively use technologies that improve: - Product
quality - Demo impact - Technical credibility - Sponsor track
opportunities - Real-world scalability

PEC Hacks 4.0 includes FinTech, AI, Open Innovation and other domains.
KAVASAM should primarily compete as a FinTech solution while using AI
and innovation capabilities as supporting strengths. citeturn0search0

------------------------------------------------------------------------

# Final Technology Selection

## 1. Google Gemini API

Priority: CORE

Usage:

Gemini becomes the intelligence engine of KAVASAM.

Use cases:

-   Scam SMS detection
-   WhatsApp screenshot analysis
-   QR/payment fraud reasoning
-   Scam call transcript analysis
-   Regional language explanation

Architecture:

Flutter App

↓

FastAPI Backend

↓

Gemini API

↓

Fraud Risk Engine

↓

Warning + Action

Why use:

-   Directly supports AI fraud detection
-   Multimodal capability
-   Strong sponsor alignment

Possible sponsor recognition: Best Use of Gemini API.
citeturn0search2

------------------------------------------------------------------------

# 2. ElevenLabs

Priority: CORE FOR USER EXPERIENCE

Purpose:

Voice-based fraud protection.

Problem:

Many elderly users cannot understand text warnings.

Usage:

Convert AI warnings into natural speech.

Example:

"இந்த அழைப்பு மோசடி ஆக இருக்கலாம். பணம் அனுப்ப வேண்டாம்."

Benefits:

-   Elderly accessibility
-   Regional language experience
-   Strong live demo impact

Possible sponsor recognition: Best Use of ElevenLabs.
citeturn0search2

------------------------------------------------------------------------

# 3. Render

Priority: CORE INFRASTRUCTURE

Purpose:

Deploy KAVASAM backend.

Host:

-   FastAPI APIs
-   Guardian dashboard
-   AI services

Reason:

A working cloud application is stronger than a local demo.

Possible sponsor recognition: Best Use of Render. citeturn0search2

------------------------------------------------------------------------

# 4. n8n

Priority: HIGH

Purpose:

Fraud response automation.

Use cases:

When scam detected:

AI confirms fraud

↓

n8n workflow starts

↓

Create evidence package

↓

Notify guardian

↓

Prepare cybercrime report

This creates a complete prevention-to-response workflow.

Possible sponsor recognition: Best Use of n8n. citeturn0search1

------------------------------------------------------------------------

# 5. MongoDB Atlas

Priority: OPTIONAL BUT VALUABLE

Use only if it improves the product.

Recommended usage:

Fraud intelligence database.

Store:

-   Scam patterns
-   Reported UPI IDs
-   Fraud categories
-   Threat intelligence

Do NOT replace Firebase everywhere.

Strategy:

Firebase: User application data

MongoDB: Fraud intelligence engine

Possible sponsor recognition: Best Use of MongoDB Atlas.
citeturn0search2

------------------------------------------------------------------------

# 6. Snowflake

Priority: FUTURE / NOT MVP

Do not integrate in the first version.

Possible future use:

Fraud analytics platform.

Example:

Anonymous fraud trends:

-   Scam categories by region
-   Attack patterns
-   Time-based analysis

Reason not immediate:

Adds complexity without improving hackathon demo.

Possible sponsor recognition: Best Use of Snowflake API.
citeturn0search2

------------------------------------------------------------------------

# 7. Solana

Priority: NOT REQUIRED

Do not force blockchain into KAVASAM.

Reason:

KAVASAM solves fraud prevention.

Adding blockchain without a real requirement weakens the product.

Possible future:

Immutable fraud evidence verification.

Not part of MVP.

------------------------------------------------------------------------

# 8. Vultr

Priority: OPTIONAL CLOUD ALTERNATIVE

Current choice:

Render.

Use Vultr only if:

-   GPU inference is required
-   Custom AI models are deployed

Not required for MVP.

------------------------------------------------------------------------

# 9. Other Sponsor Tools

## Trace AI

Potential use:

AI workflow monitoring.

Not required initially.

------------------------------------------------------------------------

## Actian

Potential use:

Large-scale financial data analytics.

Not required for hackathon MVP.

------------------------------------------------------------------------

# Recommended Final Architecture

## User Layer

Flutter

-   Paatti Mode
-   Voice warnings
-   QR scanner
-   Fraud reporting

## Application Layer

FastAPI

-   Authentication
-   Fraud APIs
-   Guardian APIs

## AI Layer

Gemini

-   Multimodal fraud analysis

## Voice Layer

ElevenLabs

-   Human-like warnings

## Database Layer

Firebase

-   Users
-   Events
-   Notifications

MongoDB Atlas

-   Fraud intelligence

## Automation Layer

n8n

-   Alerts
-   Reporting workflows

## Deployment

Render

-   Backend hosting

------------------------------------------------------------------------

# What NOT To Do

Avoid:

-   Adding blockchain just for sponsor points
-   Using every API
-   Building unnecessary dashboards
-   Replacing working systems with sponsor tools

Judges value:

A complete working solution \> many disconnected integrations.

------------------------------------------------------------------------

# Final Sponsor Strategy

Mandatory integrations:

1.  Gemini API
2.  ElevenLabs
3.  Render
4.  n8n

Recommended:

5.  MongoDB Atlas

Future only:

6.  Snowflake
7.  Vultr
8.  Solana

------------------------------------------------------------------------

# Winning Position

KAVASAM becomes:

"An AI-powered multilingual financial safety guardian that detects
fraud, explains danger through voice, protects payments, alerts families
and automates response."

This creates a strong FinTech + AI + Accessibility story without
unnecessary complexity.
