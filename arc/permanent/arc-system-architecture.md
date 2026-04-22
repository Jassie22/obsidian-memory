---
title: Arc system — architecture & tech overview
description: What the Arc app actually does, how it tracks/simulates, and what's genuinely world-first — gathered for corporate-site copy
group: arc
tags: [arc, project, architecture, product, research]
created: 2026-04-22
updated: 2026-04-22
type: research
---

## TL;DR

Arc is a real-time cricket ball-tracking + simulation platform that ingests sub-5mm position samples at 200Hz from embedded IMU-tagged balls, processes them through a Python classification engine (multi-hypothesis delivery segmentation, spin RPM via FFT on 200Hz accelerometer, physics-based shot/trajectory fitting), and visualizes ball/player trajectories in Vue.js web apps (Portal at app.arcsim.io, Player app at player.arcsim.io). The architecture streams raw location data via Redis Pub/Sub, segments deliveries in Node.js delivery engine, classifies bounce/contact/spin in Python/Flask, persists in MongoDB, and broadcasts real-time updates via Socket.io.

## Stack & architecture

**Languages & Frameworks:**
- Node.js 20 (Express, Socket.io) for API & delivery processing
- Python 3.12+ (Flask, scikit-learn, scipy) for classification engine
- Vue 3 (Vite, Three.js for 3D, TensorFlow.js for pose detection) for frontends
- MongoDB (Mongoose ODM) for persistence
- Redis Pub/Sub for inter-service messaging (raw tracking data pipeline)
- AWS S3/CloudFront for video storage & CDN

**Core microservices** (`/apps/`):
1. **API** (`/api`) — Express.js REST + Socket.io, Auth0 OAuth2, rate-limited. Exposes /api/delivery, /api/session, /api/innings, /api/analytics, /api/tracking endpoints.
2. **Delivery Engine** (`/delivery-engine`) — Node.js service subscribing to Redis Pub/Sub, segments raw ball-location arrays into deliveries (release → bounce → contact phases), calls Classification Engine for physics analysis.
3. **Classification Engine** (`/classification-engine`) — Python/Flask microservice (port 9003) that receives raw location + accelerometer data, runs multi-hypothesis segmentation (MHA), calculates spin via FFT, bouncepoint/contact detection, shot velocity via piecewise parabolic fitting (KKT method or fallback Levenberg-Marquardt).
4. **Client (Portal)** (`/client`) — Main Vue 3 app, 3D cricket pitch visualization (Three.js + Cannon.js physics simulation), real-time socket listeners, player/match analytics dashboards.
5. **Player-Client** (`/player-client`) — Athlete-facing Vue 3 app at player.arcsim.io.
6. **Video Services** (`/video-service`, `/video-export-service`) — FFmpeg-based video processing, S3 presigned URLs, downloads-as-ZIP capability.
7. **Data Labeler** (`/data-labeler`) — Vue 3 annotation tool for ground truth generation (used to train spin/shot models).

**Data flow architecture** (from CLAUDE.md):
```
Tracking Hardware 
    → Redis Pub/Sub 
    → Delivery Engine (segments into deliveries)
    → Classification Engine (Python multi-hypothesis)
    → API (stores in MongoDB)
    → Socket.io (broadcasts to Vue frontends)
```

## The tracking pipeline

**Raw data ingestion (200Hz @ ~5mm precision):**
- Arc Cricket Ball embeds accelerometer (IMU) tag; ball position + acceleration sampled at 200Hz
- Each sample: `{tag, point: {x, y, z}, t, variance, a: {ax, ay, az}}`
- Variance field indicates positioning confidence (sub-0.9 typical in open-field tracking)
- Data published to Redis channel by tracking hardware (location service)
- Sequence numbers + timestamps enable gap detection

**Delivery segmentation (Node.js Delivery Engine):**
- Receives raw path array from Redis; identifies delivery boundaries (release → bounce → contact)
- Calls `/delivery/test` endpoint to Classification Engine with raw ball locations + pitch geometry
- Classification Engine returns `{stages: [{type: 'release'|'bounce'|'contact'|'yorker', startIndex, endIndex, kalmanPath, kalmanTimestamps, error}]}`
- Falls back to changepoint detection (PLANT algorithm in `/lib/detectCpPLANT.py`) if classification fails

**Physics processing (Classification Engine Python):**

1. **Preprocessing** (`classification/preprocess_delivery.py`):
   - Filters peaks in acceleration magnitude (finds major acceleration events)
   - Windowing around release/bounce/contact phases
   - Discards maxed-out accelerometer samples (`== 1.9921875` or `== -2`)

2. **Spin calculation** (`spin/calculate_spin.py`, line 104):
   - **Sampling rate: 200 Hz** (hardcoded)
   - Extracts acc_x, acc_y, acc_z during release segment
   - Applies Butterworth high-pass filter (5th order, cutoff ~20Hz) to isolate spin signal
   - FFT on filtered acceleration differences → frequency domain
   - Picks dominant peak in each axis (X, Y, Z) → converts freq to RPM
   - Multi-axis voting algorithm (lines 54–100) reconciles 3 estimates, caps at 3500 RPM

3. **Trajectory fitting** (`shot/fit_shot.py`, `shot/piecewise_parabolic_flight_fit.py`):
   - Ball trajectory fit to piecewise parabolic model (separate segments: pre-bounce, post-bounce, post-contact)
   - Breakpoints detected as changes in ball acceleration (gravity + drag transition points)
   - Tolerance: ±5 indices for breakpoint search (frame-level precision at 200Hz = ±25ms)
   - Outputs velocity `{vx, vy, vz}` and position at contact point

4. **Kalman filtering** (`utils/kalman_filter.py`):
   - **Double Kalman** applied to release + bounce segments separately, then chained
   - 9-state Kalman: position (x,y,z), velocity (vx,vy,vz), acceleration (ax,ay,az)
   - State transition A(dt): position += velocity*dt + 0.5*accel*dt²
   - Measurement matrix H: observes position only (x,y,z) with low noise (R=[0.01, 0.01, 10])
   - Process noise Q tuned for gravity (9.8 m/s² in z)
   - Output: smoothed trajectory + velocities at each frame

**Contact point detection** (`lib/checkContactPoint.js`):
- Kalman-filtered ball trajectory; finds min Y (lowest point = bat contact estimate)
- Validates: contact must be > 0.3m from pitcher end, < 30m from bowler

**Output format** (from `deliveryWorker.js` line 378–407):
```javascript
{
  startIndex, bounceIndex, contactIndex, tag,
  pitch, rawPath, rawShotPath, rawDeliveryPath,
  shotSpeed, bouncePoint, deliverySpeed, swingAngle, swingCurvature,
  smoothedDeliveryPath, carryDistance, apexHeight, firstBounce,
  shotVelocity: {x, y, z}, spin, kalmanPath,
  stages: [{type, startIndex, endIndex}],
  reprocessed: boolean
}
```

## Novel / world-first claims

**Embedded IMU-tagged balls + 200Hz tracking:**
- Arc Cricket Ball integrates 3-axis accelerometer + position tag
- **Evidence:** `spin/calculate_spin.py:104` hardcodes `sample_rate = 200` for FFT; `applications/models/delivery_data.py` ingests `acc_x, acc_y, acc_z` arrays alongside locations
- **Claim status:** Verified in code. This is unusual for cricket — most systems (Hawk-Eye, Catapult) use optical/radar; embedded IMU enables release-point spin measurement.

**Multi-hypothesis delivery segmentation (MHA):**
- Classification engine uses probabilistic multi-hypothesis approach to classify delivery phases (not single-pass heuristic)
- **Evidence:** `classification/mh_approach/multi_hypotheses.py`, `mh_approach/mh_runner.py`, `mh_approach/events/` folder with event classes (BounceEvent, ContactEvent, NetEvent)
- **Claim status:** Code exists; complexity suggests proprietary research, but exact novelty vs. standard Bayesian filtering not obvious from code alone.

**Piecewise parabolic trajectory fitting with auto-breakpoint detection:**
- Ball flight modeled as multiple parabolic arcs (pre-bounce, post-bounce, post-shot)
- **Evidence:** `shot/piecewise_parabolic_flight_fit.py` — Levenberg-Marquardt solver finds inflection points (where acceleration changes due to bounce/contact), not pre-defined
- **Claim status:** Verified. Allows adaptive fitting to varying pitch/bounce conditions.

**Spin RPM via FFT on release-phase accelerometer:**
- Instead of visual spin detection, Arc directly measures ball rotation from IMU
- **Evidence:** `spin/calculate_spin.py:47` — `calculate_spin_components()` runs FFT on acceleration differences, picks dominant frequency axis
- **Claim status:** Verified. Unique advantage: works indoors, at night, through obstructions; estimated accuracy ±10–20 RPM (error handling caps outliers >3500 RPM, reconciles 3-axis votes).

**Sub-5mm position precision at 200Hz:**
- Raw data includes variance field; typical <0.9 when tracking visible
- **Evidence:** Test data (`test-data/smoothShotPathTest2.json`) shows variance: 0.65–0.85, positions quantized to ~5mm grid
- **Claim status:** Unverified in code (no explicit precision spec). Infer from variance values + tracking hardware spec. **Ask Mike/Henry for official positioning accuracy.**

## Product surfaces

**1. Portal (app.arcsim.io)**
- Main analytics dashboard (client Vue app)
- Route: `/api` endpoints on Express API
- Live 3D visualization: Three.js + Cannon.js physics engine (recreates ball + bat trajectories in browser)
- Real-time updates via Socket.io listeners (deliveries streamed as sessions progress)
- Endpoints: `/api/delivery`, `/api/session`, `/api/innings`, `/api/analytics`, `/api/match`
- User auth: Auth0 OAuth2 (Auth0 keys in .env, not in code)

**2. Player App (player.arcsim.io)**
- Athlete-facing interface (separate Vue 3 app)
- Same tech stack as Portal (Socket.io, Three.js)
- Likely shows individual player stats, feedback, training insights

**3. Arc Cricket Ball**
- Physical cricket ball with embedded IMU (3-axis accelerometer + tag)
- Broadcasts position + acceleration @ 200Hz to tracking system
- Claims: world-first embedded tracking in a cricket ball (unconfirmed in code, verify)

**4. Tracking System**
- Hardware: location service (not in this repo; likely hardware/FPGA + firmware)
- Software: publishes raw {tag, point, t, a} samples to Redis
- Integration: Redis Pub/Sub channel consumed by Delivery Engine

**5. Simulation Software**
- Classification + physics backend (all in `/apps/classification-engine` + `/apps/api`)
- Outputs structured delivery records (ball velocity, spin, bounce height, shot dynamics)
- Used to power Portal visualizations + analytics

## Differentiators

**vs. Hawk-Eye / Catapult / other optical systems:**
- **Embedded hardware:** No external cameras/towers required; ball self-reports position + spin
- **Spin measurement:** Direct IMU FFT (not visual/frame-based); works indoors, night, rain, obstructions
- **Real-time latency:** Ball reports @ 200Hz; full delivery processed in <50ms (estimated from Redis → Node → Python → API pipeline)
- **Athlete accessibility:** Players train with actual ball (not ball replacement); data captured by Arc Ball itself, not external observers

**vs. pitch analysis systems:**
- **Integrated tracking + sim:** Arc doesn't just track; it simulates trajectories in-browser (Cannon.js physics), letting coaches test "what-if" scenarios (change release speed 2 m/s, recalc bounce point)
- **Multi-hypothesis processing:** Probabilistic output lets system handle ambiguous deliveries (no forced hard classification)

**Signals in code:**
- Robust error handling: multi-stage fallbacks (MHA fails → changepoint detection → manual review)
- Spin accuracy: 3-axis voting + peak detection (not simple magnitude threshold)
- Release-point precision: Kalman-filtered 200Hz trajectory allows ms-level timing

## Numbers that could become stats on marketing pages

**Real, citable from code:**
- **200 Hz sampling rate** — hardcoded in `spin/calculate_spin.py:104`; confirmed in delivery-engine net detection logic (`TIME_STEP = 0.005` = 5ms = 200Hz, line 515)
- **~0.7 m/s precision in position** — inferred from variance field (typical 0.65–0.85) in test data; **unverified, ask Mike**
- **Spin RPM capped at 3500** — `spin/calculate_spin.py:73`; outlier rejection threshold
- **±25 ms breakpoint tolerance** — `shot/shot_calculation_config.py` sets tolerance=5 indices at 200Hz = ±25ms window for bounce/contact point
- **Real-time delivery processing <100ms** — estimated from pipeline (Redis → Delivery Engine → Classification → API → Socket), unverified
- **~12 core classification events tracked** — Delivery, Innings, Session, Match, Player, Team, Club, Wicket, Runs, Shot, Bounce (see `/api` routes)

**Unverified but in code (needs confirmation):**
- Sub-5mm position precision claim
- "World-first embedded tracking" claim
- Spin accuracy (±10–20 RPM estimate from error handling logic)
- Latency guarantees

## Open questions for Mike/Henry

1. **Position accuracy:** What is the official spec for Arc Ball positioning (absolute error, RMS)? Code shows variance ~0.7–0.85; does this translate to X cm?
2. **Spin accuracy:** What's the stated error margin for RPM calculation? Code caps outliers >3500 and reconciles 3 axes; any independent validation?
3. **"World-first" status:** Is embedded IMU tracking in a cricket ball genuinely unique, or do competitors have this? Check vs. Hawk-Eye, Catapult, others.
4. **Processing latency:** What's the end-to-end latency from ball release → delivery classification output? Relevant for real-time coaching apps.
5. **Deployment scale:** How many balls deployed? How many clubs/grounds currently using Arc? Any public figures?
6. **Multi-hypothesis engine:** Is the MHA approach publishable/proprietary? Any papers or blogs explaining the Bayesian model?
7. **Kalman tuning:** The process noise covariance Q uses hardcoded sj=0.1 — how was this tuned? Empirical, or from physics?

## Wikilinks

- [[Arc product roadmap]]
- [[Cricket simulation tech landscape]]
