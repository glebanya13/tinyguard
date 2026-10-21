# Bimbleguard — Phase 2 Functionality & Placeholder Audit

**Audit Date:** 2026-10-21  
**Auditor Role:** Codebase & Systems Auditor (Phase 1 & Phase 2)  
**Target Repository:** Bimbleguard  
**Scope:** Comprehensive inventory of all elements, mechanics, screens, buttons, tabs, modals, currencies, and abstractions, with full evidence, evaluation, and actionable recommendations.

---

## 1. Audit Framework & Evaluation Criteria

Every inventory element is evaluated against the following classification schema:

### 1.1 Status Classifications
* **`WORKING`**: Fully implemented, verified by headless tests or engine execution, meets design goals without regressions.
* **`PARTIAL`**: Partially implemented, functional in basic cases, but lacks planned depth, polish, edge-case handling, or complete subsystem integration.
* **`PLACEHOLDER`**: Stubbed out, UI present without functional backend logic, or hardcoded mock responses.
* **`BROKEN`**: Causes crashes, script errors, game-breaking state desyncs, or test failures.
* **`UNUSED`**: Asset, script, or resource exists in the repository, compiles cleanly, but is never instantiated, called, or referenced in actual gameplay.
* **`UNKNOWN`**: Behavior cannot be determined from code/tests without live external services (e.g. live Google Play billing or proprietary native plugins).

### 1.2 Actionable Recommendations
* **`KEEP`**: Retain as-is; stable, high quality, and core to product identity.
* **`IMPROVE`**: Functional but needs tuning, bug fixes, visual feedback, or quality-of-life polish.
* **`REWORK`**: Flawed architecture, disconnected mechanics, or misleading abstractions requiring redesign.
* **`REMOVE`**: Redundant, duplicate, dead code, or obsolete placeholders that add maintenance overhead.
* **`INVESTIGATE`**: Requires product owner decision or live device validation.

### 1.3 Priority Levels
* **`P0`**: Critical / Blocker — Must resolve before public release or store submission.
* **`P1`**: High Priority — Major player experience issue, severe design disconnect, or incomplete primary loop.
* **`P2`**: Medium Priority — Polish, secondary feature completion, cleanup of dead code.
* **`P3`**: Low Priority — Minor cosmetic improvement, optimization, or long-term roadmap refinement.

---

## 2. Comprehensive Systems & Elements Inventory

---

### Category A: Entry, Flow & Onboarding Screens

#### `SCR-01`: Boot Scene
* **Element ID:** `SCR-01`
* **Name:** Application Bootstrapper
* **Scene / File Location:** `scenes/boot.tscn`, `scripts/boot.gd`
* **Intended Purpose:** Initial application entry point; initializes language settings, Crashlytics, exit reason logs; starts Firebase auth in the background; routes player to Welcome, Nickname, Tutorial, or World Map.
* **Actual Observed Behavior:** Correctly starts offline or online. Waits up to 3.0s for guest auth on first launch; immediately loads cached profile for returning players. Routes via `Onboarding.route()`.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `project.godot:run/main_scene="res://scenes/boot.tscn"`; verified by `tests/test_signup_flow.gd`, `tests/test_onboarding.gd`.
* **Dependencies & Side Effects:** `Online`, `GameSettings`, `CrashReporter`, `ExitReasons`, `PlayerProfile`, `Onboarding`.
* **Player-Facing Value:** Instant startup without blocking when offline.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `SCR-02`: Welcome Screen
* **Element ID:** `SCR-02`
* **Name:** Welcome Dialog
* **Scene / File Location:** `scenes/welcome.tscn`, `scripts/welcome_screen.gd`
* **Intended Purpose:** Clean first-launch screen offering "Play as Guest", "Sign In" (existing account), or starting the introductory tutorial.
* **Actual Observed Behavior:** Displays game title and options. Disables guest button during active network requests. Correctly routes to nickname selection or tutorial.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `scripts/welcome_screen.gd`, tested in `tests/test_signup_flow.gd`.
* **Dependencies & Side Effects:** `Online`, `Onboarding`, `DialogFrame`, `UiKit`.
* **Player-Facing Value:** Frictionless onboarding conforming to Google Play guidelines.
* **Recommendation:** `KEEP`
* **Priority:** `P2`

#### `SCR-03`: Nickname Screen
* **Element ID:** `SCR-03`
* **Name:** Nickname Creation Screen
* **Scene / File Location:** `scenes/nickname.tscn`, `scripts/nickname_screen.gd`, `scripts/nickname_rules.gd`
* **Intended Purpose:** Prompts new players for a nickname; supports renaming for existing accounts; enforces strict rules (3–16 chars, no mixed scripts, no profanity, single script).
* **Actual Observed Behavior:** Live validation on text changes; shows error labels ("too short", "mixed letters", "forbidden name"); virtual keyboard safe areas respected; commits atomic nickname reservation via Firestore REST.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Tested in `tests/test_accounts.gd`, `tests/nickname_cases.json`, and `firestore.rules`.
* **Dependencies & Side Effects:** `OnlineNicknames`, `NicknameRules`, `SafeArea`.
* **Player-Facing Value:** Prevents impersonation and inappropriate handles in leaderboards and co-op.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `SCR-04`: Interactive Tutorial Scene
* **Element ID:** `SCR-04`
* **Name:** First-Session Tutorial
* **Scene / File Location:** `scenes/tutorial.tscn`, `scripts/tutorial.gd`
* **Intended Purpose:** Guided match on Level 1 teaching camera pan, movement, tree chopping, slot selection, and tower construction.
* **Actual Observed Behavior:** Sequential tutorial steps (STEPS 1..6) triggered by game events. Disables free-roaming actions until requested step completes. Sets `tutorialVersionCompleted` in profile upon finish.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_tutorial.gd` passes 100% in headless mode.
* **Dependencies & Side Effects:** `main.tscn`, `GuideHints`, `PlayerProfile`.
* **Player-Facing Value:** Essential for mobile TD accessibility.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

---

### Category B: World Map Navigation, Tabs & Modals

#### `NAV-01`: Level Badge Nodes
* **Element ID:** `NAV-01`
* **Name:** World Map Level Badges (Sites 1–6)
* **Scene / File Location:** `scenes/level_select.tscn`, `scripts/level_select.gd:227`
* **Intended Purpose:** Display 3D world map island (`worldmap.glb`) with interactive level nodes projected onto canvas screen space; shows stars earned, lock status, and difficulty crowns.
* **Actual Observed Behavior:** Dynamically projects 3D spatial points `Site1..Site6` to 2D UI button badges; draws star rows and crown textures; updates variations (`NodeBlue`, `NodeGreen`, `NodeGold`). Selected level smoothly enlarges ($\times 1.14$).
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_map_layout.gd`, `tests/test_strategic_view.gd`.
* **Dependencies & Side Effects:** `Camera3D.unproject_position`, `LevelCatalog`, `Perks`.
* **Player-Facing Value:** Core campaign progression visualization.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `NAV-02`: Level Card & Mode Selectors
* **Element ID:** `NAV-02`
* **Name:** Level Information Card
* **Scene / File Location:** `scenes/level_select.tscn`, `scripts/level_select.gd:719`
* **Intended Purpose:** Right pane displaying level biome emblem, name, subtitle, stars, endless record, difficulty segments (Normal, Hard, Nightmare), and "Play" / "Record Run" launch buttons.
* **Actual Observed Behavior:** Displays all level statistics accurately. Segments lock if previous difficulty was not cleared. Continues saved checkpoint if present (`CHECKPOINT_CONTINUE % wave`).
* **Status:** `WORKING`
* **Evidence Supporting Status:** Tested in `tests/test_difficulty.gd`, `tests/test_checkpoint.gd`.
* **Dependencies & Side Effects:** `Balance.difficulty`, `BattleCheckpoint`, `LevelCatalog`.
* **Player-Facing Value:** Main launch interface for battles.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `NAV-03`: Rewards Tab
* **Element ID:** `NAV-03`
* **Name:** Rewards / Streak Tab Button
* **Scene / File Location:** `scenes/level_select.tscn:312`, `scripts/streak_panel.gd`
* **Intended Purpose:** Bottom tab bar button (Flame icon) providing unified access to daily retention rewards: Login Streak, Daily Quests, Camp offline accumulation, and 28-Day Calendar.
* **Actual Observed Behavior:** Opens `StreakPanel`. Shows red alert dot (`_rewards_dot`) if pending Camp coins $> 0$ or Calendar claim is available.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `level_select.gd:465-486`, verified by layout tests.
* **Dependencies & Side Effects:** `StreakPanel`, `Camp`, `Calendar28`.
* **Player-Facing Value:** Primary retention portal.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `NAV-04`: Treasury Tab
* **Element ID:** `NAV-04`
* **Name:** Treasury / Perk Tree Tab Button
* **Scene / File Location:** `scenes/level_select.tscn:316`, `scripts/level_select.gd:488`
* **Intended Purpose:** Bottom tab bar button (Chest icon) opening the Treasury dialog where earned stars are permanently invested in hero, tower, and castle perks.
* **Actual Observed Behavior:** Opens `_treasury` modal within `DialogFrame`. Displays available free stars, 7 perk cards with current/next stats, and a full refund "Reset" button. Shows notification dot when any perk is affordable.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_meta.gd`, `scripts/perks.gd`.
* **Dependencies & Side Effects:** `Perks`, `PerkData`, `DialogFrame`.
* **Player-Facing Value:** Core permanent campaign progression loop.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `NAV-05`: Game Modes Tab
* **Element ID:** `NAV-05`
* **Name:** Modes Launcher Tab Button
* **Scene / File Location:** `scenes/level_select.tscn:321`, `scripts/modes_panel.gd`
* **Intended Purpose:** Bottom tab bar button (Hourglass icon) opening a launcher modal with options for Daily Trial, 2-Player Co-op, and Global Leaderboards.
* **Actual Observed Behavior:** Opens `ModesPanel`. Shows notification dot if today's Daily Trial has not been completed.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_dialog_layout.gd`.
* **Dependencies & Side Effects:** `ModesPanel`, `Daily`, `CoopRun`, `OnlineRecords`.
* **Player-Facing Value:** Consolidates non-campaign modes into a single clean modal.
* **Recommendation:** `KEEP`
* **Priority:** `P2`

#### `NAV-06`: Shop Tab
* **Element ID:** `NAV-06`
* **Name:** Cosmetic Shop Tab Button
* **Scene / File Location:** `scenes/level_select.tscn:327`, `scenes/shop.tscn`, `scripts/shop.gd`
* **Intended Purpose:** Bottom tab bar button (Shop icon) transitioning to the cosmetic customization shop.
* **Actual Observed Behavior:** Transitions to `scenes/shop.tscn`. Shows owned and equipable cosmetics purchased with gems.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_shop_ui.gd`, `tests/test_shop.gd`.
* **Dependencies & Side Effects:** `Shop`, `Cosmetics`, `Wallet`.
* **Player-Facing Value:** Player personalization sink for earned gems.
* **Recommendation:** `KEEP`
* **Priority:** `P2`

#### `NAV-07`: Top Bar Utility Buttons
* **Element ID:** `NAV-07`
* **Name:** World Map Top Bar Controls
* **Scene / File Location:** `scenes/level_select.tscn`, `scripts/level_select.gd:630`
* **Intended Purpose:** Displays player resources (Gems pill, Coins pill, Stars pill), cloud sync status icon (`SyncButton`), Sound toggle, Profile button, Achievements button, Encyclopedia button, and Settings button.
* **Actual Observed Behavior:** All buttons function. Tapping Gems pill opens transaction dropdown; tapping Cloud icon opens Account modal; Sound toggles audio; Profile opens Account modal; Achievements opens achievements list; Encyclopedia opens 3-tab guide; Settings opens settings panel.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Tested in `tests/test_map_layout.gd`, `tests/test_i18n.gd`.
* **Dependencies & Side Effects:** `GemsHud`, `SettingsPanel`, `EncyclopediaPanel`, `AccountPanel`.
* **Player-Facing Value:** Standard mobile game navigation header.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

---

### Category C: Modals & Panels

#### `MOD-01`: Treasury Modal
* **Element ID:** `MOD-01`
* **Name:** Star Treasury Dialog
* **Scene / File Location:** `scripts/level_select.gd:488`, `scripts/dialog_frame.gd`
* **Intended Purpose:** Full-screen dialog displaying 7 perk cards (`axe`, `sword`, `walls`, `towers`, `gold_start`, `wood_start`, `swift`).
* **Actual Observed Behavior:** Shows cost in stars (1..5), current stat effect, and next tier effect. Purchasing deducts free stars immediately and commits to `user://progress.cfg`. "Reset" refunds 100% of invested stars.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Tested in `tests/test_meta.gd`.
* **Dependencies & Side Effects:** `Perks`, `resources/perks/*.tres`.
* **Player-Facing Value:** Allows players to tailor build strategies for difficult levels.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MOD-02`: Streak & Quests Panel
* **Element ID:** `MOD-02`
* **Name:** Daily Streak & Quests Dialog
* **Scene / File Location:** `scripts/streak_panel.gd`, `scripts/streak.gd`, `scripts/quests.gd`
* **Intended Purpose:** 7-day login streak visualization (5 to 100 gems), active seasonal event banner, and 3 daily quests (e.g. survive waves, fell trees, build towers).
* **Actual Observed Behavior:** Renders streak progress; grants weekly forgiveness on single missed day; tracks quest progress from battle; awards gems directly to `Wallet` upon completion. Contains shortcut buttons to Camp and Calendar.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Tested in `tests/test_streak.gd`, `tests/test_quests.gd`.
* **Dependencies & Side Effects:** `Streak`, `Quests`, `Wallet`, `Events`.
* **Player-Facing Value:** Standard daily engagement driver.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MOD-03`: Camp Panel (Offline Treasury Generator)
* **Element ID:** `MOD-03`
* **Name:** Camp Generator Dialog
* **Scene / File Location:** `scripts/camp_panel.gd`, `scripts/camp.gd`
* **Intended Purpose:** Displays offline accumulation of "treasury coins", current production rate (10..30 coins/h), accumulation cap (8..16 h), a progress bar, a "Collect" button, and an "Upgrade" button.
* **Actual Observed Behavior:** Accurately accumulates coins based on timestamp difference; caps at max hours; protects against clock rollbacks. "Collect" transfers coins to `camp["coins"]`. "Upgrade" deducts coins and increases rate/cap up to Level 5.
* **Status:** `PARTIAL` / `REWORK`
* **Evidence Supporting Status:** `tests/test_retention.gd` passes 100%. **CRITICAL FLAW:** Once upgraded to Level 5, coins have literally NO other sink in the game. Coins cannot be spent in battle, cannot buy perks, cannot buy cosmetics.
* **Dependencies & Side Effects:** `PlayerProfile`, `Wallet`, `Toast`.
* **Player-Facing Value:** High perceived value initially, but degrades into confusion once the player realizes coins cannot be spent on anything else.
* **Recommendation:** `REWORK` (Connect coins to a real progression sink, e.g. tower mastery or campaign power, or merge currency).
* **Priority:** `P1`

#### `MOD-04`: 28-Day Calendar Panel
* **Element ID:** `MOD-04`
* **Name:** Cumulative Monthly Calendar Dialog
* **Scene / File Location:** `scripts/calendar_panel.gd`, `scripts/calendar28.gd`
* **Intended Purpose:** 4×7 grid of 28 cumulative visit days awarding treasury coins and gems. Missing a day does not reset progress.
* **Actual Observed Behavior:** Displays all 28 day cells with reward icons; highlights current claimable day; awards coins to `Camp` and gems to `Wallet`; marks claimed with checkmark icon; wraps around after day 28.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_retention.gd` passes 100%.
* **Dependencies & Side Effects:** `Calendar28`, `Camp`, `Wallet`.
* **Player-Facing Value:** Generous, forgiving retention reward system.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MOD-05`: Game Modes Panel
* **Element ID:** `MOD-05`
* **Name:** Modes Selector Dialog
* **Scene / File Location:** `scripts/modes_panel.gd`
* **Intended Purpose:** Selection dialog offering Daily Challenge, 2-Player Co-op, and Global Leaderboards.
* **Actual Observed Behavior:** Renders 3 large buttons with icons; checks network availability; routes cleanly to Daily, Co-op Lobby, or Records.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Tested in `tests/test_dialog_layout.gd`.
* **Dependencies & Side Effects:** `DailyPanel`, `RecordsPanel`, `CoopLobby`.
* **Player-Facing Value:** Clear mode differentiation.
* **Recommendation:** `KEEP`
* **Priority:** `P2`

#### `MOD-06`: Daily Challenge Panel
* **Element ID:** `MOD-06`
* **Name:** Daily Trial Dialog
* **Scene / File Location:** `scripts/daily_panel.gd`, `scripts/daily.gd`, `scripts/daily_run.gd`
* **Intended Purpose:** Shows today's daily trial: deterministic seed, 3 random modifiers (e.g. faster creeps, restricted towers, cheaper wood), personal best wave, and global leaderboard.
* **Actual Observed Behavior:** Generates daily trial deterministically from date string; applies daily modifiers to `WavePlan` and `BuildManager`; saves daily record to cloud.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_daily.gd`, `tests/test_daily_online.gd`.
* **Dependencies & Side Effects:** `DailyRun`, `Daily`, `OnlineDaily`, `resources/daily_modifiers.json`.
* **Player-Facing Value:** High replayability for veteran players.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MOD-07`: Global Records Panel
* **Element ID:** `MOD-07`
* **Name:** Endless Siege Leaderboards Dialog
* **Scene / File Location:** `scripts/records_panel.gd`, `scripts/online_records.gd`
* **Intended Purpose:** Displays top scores (waves survived) for Endless Siege mode across levels 1–6.
* **Actual Observed Behavior:** Fetches leaderboard documents from Firestore via REST; displays ranked list with player nicknames, scores, and personal rank; handles offline state gracefully.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_records_panel.gd`, `tests/test_records.gd`.
* **Dependencies & Side Effects:** `OnlineRecords`, `FirestoreClient`.
* **Player-Facing Value:** Competitive motivation for endless mode.
* **Recommendation:** `KEEP`
* **Priority:** `P2`

#### `MOD-08`: Achievements Panel
* **Element ID:** `MOD-08`
* **Name:** Achievements Dialog
* **Scene / File Location:** `scripts/achievements_panel.gd`, `scripts/achievements.gd`
* **Intended Purpose:** Scrollable list of 16 distinct achievements (e.g. "First Blood", "Lumberjack", "Master Builder", "Flawless Defense").
* **Actual Observed Behavior:** Tracks completion via bitmask in profile; shows achievement icon, title, description, and claim button; awards gems to `Wallet` upon claim.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_achievements.gd`.
* **Dependencies & Side Effects:** `AchievementTracker`, `Wallet`, `resources/achievements.json`.
* **Player-Facing Value:** Long-term player goals.
* **Recommendation:** `KEEP`
* **Priority:** `P2`

#### `MOD-09`: Encyclopedia Panel
* **Element ID:** `MOD-09`
* **Name:** In-Game Codex & Encyclopedia
* **Scene / File Location:** `scripts/encyclopedia_panel.gd`
* **Intended Purpose:** 3-tab reference guide: Towers (stats, upgrade costs, roles), Bestiary (creeps, HP, abilities, resistances), and Village (wood trade ratios, lumberjacks, mercenaries).
* **Actual Observed Behavior:** All 3 tabs function cleanly with proper icons, stats, and localized descriptions.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_encyclopedia.gd` passes 100%.
* **Dependencies & Side Effects:** `TowerData`, `EnemyData`, `CampStructures`.
* **Player-Facing Value:** Excellent reference for strategic planning.
* **Recommendation:** `KEEP`
* **Priority:** `P2`

#### `MOD-10`: Settings Panel
* **Element ID:** `MOD-10`
* **Name:** Game Settings Dialog
* **Scene / File Location:** `scripts/settings_panel.gd`, `scripts/game_settings.gd`
* **Intended Purpose:** User settings: Language selection (12 languages), Sound volume toggle, Crash reporting opt-out, HUD layout preview, Credits, and hidden diagnostics toggle (5 taps on version).
* **Actual Observed Behavior:** Modifies `GameSettings` and updates config; language changes trigger live scene reload; diagnostics mode toggles `DiagOverlay`.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Tested in `tests/test_dialog_layout.gd`, `tests/test_i18n.gd`.
* **Dependencies & Side Effects:** `GameSettings`, `LayoutPreview`, `CrashReporter`.
* **Player-Facing Value:** Essential accessibility and customization.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MOD-11`: Account Panel
* **Element ID:** `MOD-11`
* **Name:** Account Management Dialog
* **Scene / File Location:** `scripts/account_panel.gd`, `scripts/online_accounts.gd`
* **Intended Purpose:** Shows account status (Guest vs Linked Email), nickname, cloud sync state; allows linking email, switching accounts, renaming, replaying tutorial, or deleting account.
* **Actual Observed Behavior:** All account operations execute cleanly against Firebase Auth REST. Account deletion deletes Firestore documents and local files.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_accounts.gd`, `tests/test_email_accounts.gd`.
* **Dependencies & Side Effects:** `OnlineAccounts`, `EmailAuthDialog`, `GameInfo`.
* **Player-Facing Value:** Full GDPR and Google Play compliance.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MOD-12`: Email Auth Dialog
* **Element ID:** `MOD-12`
* **Name:** Email & Password Input Modal
* **Scene / File Location:** `scripts/email_auth_dialog.gd`, `scripts/email_rules.gd`
* **Intended Purpose:** Form for email sign-up, sign-in, linking guest account, or requesting password reset email.
* **Actual Observed Behavior:** Validates email syntax and minimum 6-character password; communicates error codes (`EMAIL_EXISTS`, `WRONG_PASSWORD`, `INVALID_EMAIL`).
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_email_errors.gd`.
* **Dependencies & Side Effects:** `AuthService`, `AuthErrors`.
* **Player-Facing Value:** Account security and cross-device sync.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MOD-13`: Account Reminder
* **Element ID:** `MOD-13`
* **Name:** Guest Account Protection Banner
* **Scene / File Location:** `scripts/account_reminder.gd`
* **Intended Purpose:** Non-intrusive reminder banner appearing on the map after reaching milestones (e.g. 10 stars or buying a cosmetic) encouraging guest players to link an email.
* **Actual Observed Behavior:** Appears only when conditions met (`Online.account_reminder_due()`); dismissible; opens email linking directly.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `level_select.gd:588`, `tests/test_accounts.gd`.
* **Dependencies & Side Effects:** `OnlineSession`, `PlayerProfile`.
* **Player-Facing Value:** Prevents accidental loss of progress upon device replacement.
* **Recommendation:** `KEEP`
* **Priority:** `P2`

#### `MOD-14`: Gems HUD Dropdown
* **Element ID:** `MOD-14`
* **Name:** Gems Transaction History Modal
* **Scene / File Location:** `scripts/gems_hud.gd`
* **Intended Purpose:** Top-bar drop-down dialog showing total earned gems, total spent gems, and recent transaction log (claims and purchases).
* **Actual Observed Behavior:** Displays derived balance and operation history; mounts cleanly to canvas without obscuring game actions.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Tested in `tests/test_wallet.gd`.
* **Dependencies & Side Effects:** `Wallet`, `Economy`.
* **Player-Facing Value:** Transparency into ledger transactions.
* **Recommendation:** `KEEP`
* **Priority:** `P2`

#### `MOD-15`: Battle EndScreen & Pause Modal
* **Element ID:** `MOD-15`
* **Name:** Match End & Pause Modal
* **Scene / File Location:** `ui/hud.tscn:EndScreen`, `scripts/hud.gd:427`, `scripts/battle_end.gd`
* **Intended Purpose:** Single unified modal serving 3 states: Pause (Resume, Sound, Restart, Map), Victory (Stars, Kills, Wood, Towers, First Win bonus, Next/Map), and Defeat (Waves survived, Stats, Restart, Map).
* **Actual Observed Behavior:** Operates under `PROCESS_MODE_ALWAYS` so buttons work while `SceneTree.paused = true`. Awards battle victory coins (+40/+80) and gems (+5).
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_pause.gd`, `tests/test_endgame.gd`, `tests/test_end_to_map.gd`.
* **Dependencies & Side Effects:** `SceneTree.paused`, `BattleEnd`, `Economy`.
* **Player-Facing Value:** Core match resolution interface.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

---

### Category D: Combat Entities & World Objects

#### `ENT-01`: Hero Knight
* **Element ID:** `ENT-01`
* **Name:** Player Hero (Knight)
* **Scene / File Location:** `scenes/hero.tscn`, `scripts/hero.gd`, `assets/models/hero_knight.glb`
* **Intended Purpose:** Player avatar; moves via joystick or tap; auto-chops trees; attacks creeps with sword; unleashes 360° whirlwind; target pursuit; sword upgrade progression.
* **Actual Observed Behavior:** Responsive physics movement; smooth puppet animations (idle, walk, swing, spin, hurt); sword upgrades increase melee damage; damage flash and sound effects on hit.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_combat.gd`, `tests/test_hero_fixes.gd`, `tests/test_hero_target.gd`.
* **Dependencies & Side Effects:** `Puppet`, `GameCommands`, `Sim`, `WalkGrid`.
* **Player-Facing Value:** Core tactical action mechanic differentiating Bimbleguard from passive TDs.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `ENT-02`: Archer Tower
* **Element ID:** `ENT-02`
* **Name:** Archer Guard Tower
* **Scene / File Location:** `scenes/towers/tower_archer.tscn`, `resources/towers/archer.tres`
* **Intended Purpose:** Fast single-target physical ranged tower. Primary counter against fast runners and flying bats.
* **Actual Observed Behavior:** Fires ballistic arrow projectiles (`projectile_arrow.tscn`); leads moving targets; cannot hit shielded enemies effectively (deals reduced damage).
* **Status:** `WORKING`
* **Evidence Supporting Status:** Verified in all 6 levels in `tests/test_gameplay.gd`.
* **Dependencies & Side Effects:** `Tower`, `Projectile`, `Sim`.
* **Player-Facing Value:** Essential early-game foundation tower.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `ENT-03`: Cannon Tower
* **Element ID:** `ENT-03`
* **Name:** Cannon Artillery Tower
* **Scene / File Location:** `scenes/towers/tower_cannon.tscn`, `resources/towers/cannon.tres`
* **Intended Purpose:** Slow, heavy area-of-effect artillery. High burst physical damage to dense swarms; cannot target flying enemies.
* **Actual Observed Behavior:** Fires arcing cannonballs (`projectile_cannon.tscn`); deals radial splash damage upon impact; emits screen shake and dust FX.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_combat.gd`, `tests/test_camps_and_sfx.gd`.
* **Dependencies & Side Effects:** `Tower`, `Projectile`, `Sim`.
* **Player-Facing Value:** Vital swarm clearing and choke-point defense.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `ENT-04`: Frost Tower
* **Element ID:** `ENT-04`
* **Name:** Frost Tower
* **Scene / File Location:** `scenes/towers/tower_frost.tscn`, `resources/towers/frost.tres`
* **Intended Purpose:** Magic support tower that slows enemy movement speed by 40%–60% and chills them.
* **Actual Observed Behavior:** Fires homing frost shards (`projectile_frost.tscn`); applies slow status effect; tints enemy material icy blue. Sets up massive bonus damage synergy with Lightning towers.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_combat.gd`.
* **Dependencies & Side Effects:** `Tower`, `Enemy.apply_slow`.
* **Player-Facing Value:** Core tactical synergy enabler.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `ENT-05`: Lightning Tower
* **Element ID:** `ENT-05`
* **Name:** Lightning Tesla Tower
* **Scene / File Location:** `scenes/towers/tower_lightning.tscn`, `resources/towers/lightning.tres`
* **Intended Purpose:** Advanced magic tower that discharges instant chain lightning arcing between up to 4 targets. Deals $\times 2.5$ critical damage to chilled enemies.
* **Actual Observed Behavior:** Emits procedural 3D electric bolt meshes (`scenes/fx/lightning_fx.tscn`); chains between nearby enemies; shatters chilled enemies with huge damage numbers.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_combat.gd`, `tests/test_fx.gd`.
* **Dependencies & Side Effects:** `LightningFx`, `Tower`.
* **Player-Facing Value:** High-tier reward tower for strategic placement.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `ENT-06` to `ENT-13`: Standard Enemy Roster
* **Element ID:** `ENT-06` to `ENT-13`
* **Names:** Standard Slime, Fast Scout, Slime Bat (Flyer), Shield Slime (Armored), Healer Slime, Tank Slime, Stone Golem, King Slime Boss.
* **Scene / File Location:** `scenes/enemy.tscn`, `resources/enemies/*.tres`
* **Intended Purpose:** Diverse enemy wave composition forcing varied tower defense strategies (anti-air, anti-armor, target priority).
* **Actual Observed Behavior:** All 8 enemy variants spawn according to `WavePlan`; PathFollow3D navigation functions reliably; healers pulse radial heals; shield bearers reduce arrow damage; bats fly at high elevation and bypass ground artillery; bosses trigger roar and HUD banners.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_waves.gd`, `tests/test_units.gd`, `tests/test_gameplay.gd`.
* **Dependencies & Side Effects:** `Enemy`, `Sim`, `WaveManager`.
* **Player-Facing Value:** Rich enemy variety.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `ENT-14`: Splitting Slime & Mini Slime (Unused Mechanic)
* **Element ID:** `ENT-14`
* **Name:** Slime Splitter & Slime Mini
* **Scene / File Location:** `resources/enemies/slime_splitter.tres`, `resources/enemies/slime_mini.tres`, `assets/models/slime_splitter.glb`, `assets/models/slime_mini.glb`
* **Intended Purpose:** Creep that splits into 2 smaller child slimes upon death.
* **Actual Observed Behavior:** Splitting logic is fully implemented in `scripts/enemy.gd:175` (`split.emit()`) and connected to `WaveManager`, **BUT `slime_splitter` is NEVER included in any wave plan in `resources/levels.json` and is completely missing from the Encyclopedia bestiary.**
* **Status:** `UNUSED` (Code and assets exist, but never spawned in the game).
* **Evidence Supporting Status:** `grep -rn "slime_splitter" resources/levels.json` returns 0 results. `grep -rn "slime_splitter" scripts/` returns 0 results.
* **Dependencies & Side Effects:** Fully functional backend code waiting for wave data.
* **Player-Facing Value:** Adds great gameplay depth and panic moments if activated.
* **Recommendation:** `IMPROVE` (Integrate into Level 4–6 wave plans and add to Encyclopedia).
* **Priority:** `P1`

#### `ENT-15`: Allied Mercenary Unit
* **Element ID:** `ENT-15`
* **Name:** Mercenary Ally Fighter
* **Scene / File Location:** `scenes/mercenary.tscn`, `scripts/mercenary.gd`, `scripts/camp_structures.gd:MercenaryCamp`
* **Intended Purpose:** Recruited allied melee fighter (40 in-match gold) that patrols castle gates, attacks nearby creeps, and takes damage.
* **Actual Observed Behavior:** Spawns from Mercenary Camp; patrols perimeter at least 4.0m from castle center; attacks approaching enemies with sword; flashes red and clangs when hurt; dies cleanly when health depletes.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_camps_and_sfx.gd` passes 100%.
* **Dependencies & Side Effects:** `Sim`, `GameState`, `CampStructures`.
* **Player-Facing Value:** Provides direct tactical defense reinforcement during difficult waves.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `ENT-16`: Village NPC & Wood Trader
* **Element ID:** `ENT-16`
* **Name:** Village Trader & Lumberjack
* **Scene / File Location:** `scenes/villager.tscn`, `scripts/villager.gd`, `scripts/villagers.gd`, `scripts/villager_trade.gd`
* **Intended Purpose:** Ambient villagers wandering castle paths; tapping opens trade card to exchange gold for wood or hire them permanently as lumberjacks.
* **Actual Observed Behavior:** Villagers wander using `WalkGrid`; player can sell 20w for 15g or buy 30w for 20g; hiring a villager (25g) attaches an axe overhead and generates +1 wood periodically.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_villagers.gd`, `tests/test_wood_economy.gd`.
* **Dependencies & Side Effects:** `VillagerTrade`, `GameState`, `Sim`.
* **Player-Facing Value:** Gives life to the castle surroundings and provides emergency wood procurement.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `ENT-17`: Choppable Wood Tree
* **Element ID:** `ENT-17`
* **Name:** Choppable Resource Tree
* **Scene / File Location:** `scenes/wood_tree.tscn`, `scripts/wood_tree.gd`, `scripts/grove.gd`
* **Intended Purpose:** Environmental resource nodes providing wood for towers and repairs; hero auto-chops when standing near; standing trees batched via MultiMesh (`Grove`).
* **Actual Observed Behavior:** Each hit yields wood (+3w); fells after 4 hits (12w total); collision disables upon felling; stumps remain; regrows over time in endless/long modes.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Verified in `tests/test_gameplay.gd`, `tests/test_hero_fixes.gd`.
* **Dependencies & Side Effects:** `Hero`, `GameState`, `Grove`.
* **Player-Facing Value:** Core economy pillar defining the early game pacing.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `ENT-18`: Outpost & Thicket Grove Trees
* **Element ID:** `ENT-18`
* **Name:** Chupacabra Outpost & Thicket Grove
* **Scene / File Location:** `scenes/outpost.tscn`, `scripts/outpost.gd`
* **Intended Purpose:** Enemy outpost at lane portals surrounded by thicket trees. Chopping thicket trees reduces enemy lane flow down to a 40% floor.
* **Actual Observed Behavior:** Felling thicket trees grants 0 wood but immediately weakens lane creep density; trees regrow slowly over 150s, restoring flow. Deterministic simulation verified.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_outposts.gd` passes 100% across all levels.
* **Dependencies & Side Effects:** `WavePlan`, `Sim`, `WoodTree`.
* **Player-Facing Value:** Deep strategic macro mechanic allowing aggressive players to throttle creep flow.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

---

### Category E: In-Match Mechanics, Controls & Systems

#### `MEC-01`: Prepared Tower Slots
* **Element ID:** `MEC-01`
* **Name:** Fixed Tower Slots
* **Scene / File Location:** `scenes/tower_slot.tscn`, `scripts/tower_slot.gd`, `scripts/build_manager.gd`
* **Intended Purpose:** Pre-placed building stone platforms on the level map for tower construction.
* **Actual Observed Behavior:** Tapping selects slot, lights gold selection ring, opens build/upgrade/sell command card; blocks walk grid when occupied.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Core TD gameplay verified in `tests/test_gameplay.gd`.
* **Dependencies & Side Effects:** `BuildManager`, `WalkGrid`.
* **Player-Facing Value:** Standard intuitive TD placement.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `MEC-02`: Free Warcraft-Style Placement
* **Element ID:** `MEC-02`
* **Name:** Dynamic Free Tower Placement
* **Scene / File Location:** `scripts/tower_placement_controller.gd`
* **Intended Purpose:** Allows players to tap open ground or press Workbench button to place towers freely anywhere outside enemy paths, trees, and camps (0.5m grid snap).
* **Actual Observed Behavior:** Interactive placement mode with 3D ghost preview, green/red valid footprint rings, and range preview circle; validates clearance; creates dynamic `TowerSlot` on confirm; cleans up cleanly on cancel; restores from checkpoint.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_warcraft_placement.gd` passes 100%.
* **Dependencies & Side Effects:** `BuildManager`, `WalkGrid`, `BattleCheckpoint`.
* **Player-Facing Value:** Tremendous freedom and creativity for advanced players.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MEC-03`: Command Cards System
* **Element ID:** `MEC-03`
* **Name:** Contextual HUD Command Card
* **Scene / File Location:** `scripts/command_cards.gd`, `scripts/card_controller.gd`
* **Intended Purpose:** Adapts HUD buttons based on active selection: Stance/Forge when empty, Tower build when free slot, Tower upgrade/sell/priority when occupied, Trade when village camp selected.
* **Actual Observed Behavior:** Smoothly transitions card buttons, costs, and hotkeys; handles touch input and keyboard shortcuts.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_card_select.gd`, `tests/test_forge_button.gd`.
* **Dependencies & Side Effects:** `HUD`, `BuildManager`, `Hero`.
* **Player-Facing Value:** Clean mobile UI without screen clutter.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `MEC-04`: Hero Primary Attack & Auto-Stance
* **Element ID:** `MEC-04`
* **Name:** Hero Sword Strike & Auto-Action
* **Scene / File Location:** `scripts/hero.gd:attack()`, `scripts/hero.gd:auto_action`
* **Intended Purpose:** Hero attacks targeted enemy or auto-swings at nearby enemies/trees when stationary.
* **Actual Observed Behavior:** Deals sword damage in 120° arc; damage scales with sword upgrade level ($16 \to 22 \to 28 \to 36$); swings trigger sword whoosh SFX.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Verified in `tests/test_combat.gd`, `tests/test_gameplay.gd`.
* **Dependencies & Side Effects:** `Puppet`, `HitBox`, `HurtBox`.
* **Player-Facing Value:** Active tactile engagement.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `MEC-05`: Whirlwind Spin Ability
* **Element ID:** `MEC-05`
* **Name:** Hero Whirlwind Special Skill
* **Scene / File Location:** `scripts/hero.gd:try_spin()`, `scenes/fx/spin_fx.tscn`
* **Intended Purpose:** Active cooldown ability (10s) dealing heavy 360° AoE damage to all surrounding creeps.
* **Actual Observed Behavior:** Triggers full-body spin animation and golden trail particle mesh; knocks back and damages all enemies within 2.2m radius.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Verified in `tests/test_combat.gd`.
* **Dependencies & Side Effects:** `SpinFx`, `Sim`.
* **Player-Facing Value:** Emergency panic button when gates are overrun.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MEC-06`: Hero Enemy Pursuit
* **Element ID:** `MEC-06`
* **Name:** Hero Target Chase & Melee Stance
* **Scene / File Location:** `scripts/hero.gd:chase_enemy()`
* **Intended Purpose:** Tapping an enemy orders hero to run toward and engage that specific enemy, holding attack distance as the enemy moves.
* **Actual Observed Behavior:** Hero navigates toward pursued creep, maintains 1.4m attack distance, swings continuously until enemy dies, then resumes idle stance.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_hero_fixes.gd` passes 100%.
* **Dependencies & Side Effects:** `WalkGrid`, `CharacterBody3D`.
* **Player-Facing Value:** Essential mobile touch quality of life.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MEC-07`: Auto & Manual Tree Chopping
* **Element ID:** `MEC-07`
* **Name:** Tree Harvesting
* **Scene / File Location:** `scripts/hero.gd`, `scripts/wood_tree.gd`
* **Intended Purpose:** Standing next to tree automatically chops it; tapping a distant tree causes hero to pathfind there and chop.
* **Actual Observed Behavior:** Functions reliably. Auto-action detects nearest valid tree; grants wood to `GameState`; stops when tree is felled.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Verified in `tests/test_gameplay.gd`.
* **Dependencies & Side Effects:** `WoodTree`, `Hero`, `GameState`.
* **Player-Facing Value:** Core pacing mechanic.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `MEC-08`: Forge / Sword Upgrade
* **Element ID:** `MEC-08`
* **Name:** Battlefield Forge
* **Scene / File Location:** `scripts/command_cards.gd:forge_card`, `scripts/hero.gd:sword_level`
* **Intended Purpose:** Accessible from hero command card to upgrade sword damage and repair castle.
* **Actual Observed Behavior:** Upgrades sword up to Tier 3 for in-match gold; immediately increases damage output; repairs castle lives for wood.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_forge_button.gd`, `tests/test_gameplay.gd`.
* **Dependencies & Side Effects:** `Hero`, `GameState`.
* **Player-Facing Value:** Alternative gold sink if towers are sufficient.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MEC-09`: Castle Upgrades & Armor
* **Element ID:** `MEC-09`
* **Name:** Castle Fortification System
* **Scene / File Location:** `scripts/castle_upgrades.gd`, `scripts/castle_model.gd`, `resources/castle_upgrades.json`
* **Intended Purpose:** 4-tier castle upgrade system increasing base lives and granting passive armor against leaking creeps.
* **Actual Observed Behavior:** Upgrading castle consumes gold and wood; swaps 3D castle model (`castle_lv1..4.glb`); adds armor reducing creep breach damage.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_castle_upgrade.gd` passes 100%.
* **Dependencies & Side Effects:** `CastleModel`, `GameState`.
* **Player-Facing Value:** Visual castle progression during long waves.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MEC-10`: Battlefield Camps (Lumberjack & Mercenary)
* **Element ID:** `MEC-10`
* **Name:** Tactical Field Camps
* **Scene / File Location:** `scripts/camp_structures.gd`, `scripts/level_builder.gd:120`
* **Intended Purpose:** Procedural 3D structures on the map (Lumberjack lodge, Mercenary pavilion) providing interaction points for hiring units.
* **Actual Observed Behavior:** Procedurally built with wooden beams, canvas pavilions, weapons racks, and ambient rings; tap detection opens corresponding hiring command cards.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_camps_and_sfx.gd` passes 100%.
* **Dependencies & Side Effects:** `BuildManager`, `Villagers`, `Sim`.
* **Player-Facing Value:** Visual landmarks grounding village economy.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MEC-11`: Wave Management & Multi-Lane Balancing
* **Element ID:** `MEC-11`
* **Name:** Wave Spawner & Lane Router
* **Scene / File Location:** `scripts/wave_manager.gd`, `scripts/wave_plan.gd`
* **Intended Purpose:** Spawns enemy waves across 4–6 ground and air paths converging on 4 castle gates from all 4 compass directions.
* **Actual Observed Behavior:** Spawns creeps per wave plan; announces wave compass direction ("С востока!"); spawns elites and bosses on schedule; handles outposts flow reductions.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_waves.gd`, `tests/test_gameplay.gd`.
* **Dependencies & Side Effects:** `Path3D`, `Curve3D`, `WavePlan`.
* **Player-Facing Value:** Dynamic multi-directional TD pressure.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `MEC-12`: Threat Alarm Vignette
* **Element ID:** `MEC-12`
* **Name:** Threat Alarm & Leak Flash
* **Scene / File Location:** `scripts/hud.gd:update_threat()`, `ui/hud.tscn:ThreatVignette`
* **Intended Purpose:** Edge-of-screen red pulsating vignette warning the player when enemies are close to breaching a castle gate.
* **Actual Observed Behavior:** Monitors distance-to-gate across all live creeps; smoothly pulses red alpha when danger $> 0$; flashes bright red when life is lost.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_threat_alarm.gd` passes 100%.
* **Dependencies & Side Effects:** `HUD`, `WaveManager`.
* **Player-Facing Value:** Critical spatial awareness on wide mobile screens.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MEC-13`: Touch & Virtual Joystick
* **Element ID:** `MEC-13`
* **Name:** On-Screen Touch Joystick
* **Scene / File Location:** `scripts/touch_joystick.gd`, `scripts/virtual_joystick.gd`
* **Intended Purpose:** Virtual analogue thumbstick on lower-left screen for direct hero steering.
* **Actual Observed Behavior:** Dynamic or fixed placement; smooth direction vector output; auto-hides when unused.
* **Status:** `WORKING` (Note: `virtual_joystick.gd` is an unnecessary 2-line wrapper over `touch_joystick.gd`).
* **Evidence Supporting Status:** Verified in `tests/test_hud_layout.gd`.
* **Dependencies & Side Effects:** `Hero`, `HudLayout`.
* **Player-Facing Value:** Smooth hero control on touch screens.
* **Recommendation:** `KEEP` (remove `virtual_joystick.gd` wrapper).
* **Priority:** `P1`

#### `MEC-14`: Mid-Battle Checkpointing
* **Element ID:** `MEC-14`
* **Name:** Wave Checkpoint & Save State
* **Scene / File Location:** `scripts/battle_checkpoint.gd`, `scripts/main.gd:800`
* **Intended Purpose:** Saves match state atomically at wave clear, allowing players to safely close the app and resume later.
* **Actual Observed Behavior:** Serializes gold, wood, lives, castle level, sword tier, towers (including dynamic slot positions), villager assignments, and stats to `user://battle_checkpoint.json`. Map screen button displays `CHECKPOINT_CONTINUE % wave`. Restores 100% accurately.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_checkpoint.gd` passes 100%.
* **Dependencies & Side Effects:** `Main`, `LevelCatalog`.
* **Player-Facing Value:** Huge mobile convenience preventing loss of 20-minute runs.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `MEC-15`: 2-Player Co-op Matchmaking & Lockstep
* **Element ID:** `MEC-15`
* **Name:** 2-Player Co-op Mode
* **Scene / File Location:** `scripts/coop_battle.gd`, `scripts/coop_lockstep.gd`, `scripts/coop_transport.gd`
* **Intended Purpose:** Synchronous 2-player cooperative defense over Firebase Realtime Database using lockstep frame ticks.
* **Actual Observed Behavior:** Room code lobby; exchanges seed and player cosmetics; locks simulation frames; transmits partner commands; displays ghost partner hero; desync detection via state hash.
* **Status:** `WORKING` (in fake transport & local emulator tests; sensitive to mobile network jitter).
* **Evidence Supporting Status:** `tests/test_coop_net.gd`, `tests/test_coop_flow.gd`, `tests/test_coop_integration.gd`.
* **Dependencies & Side Effects:** `RTDBClient`, `Sim`, `CommandLog`.
* **Player-Facing Value:** Exceptional social multiplayer experience for a mobile TD.
* **Recommendation:** `KEEP` / `INVESTIGATE` (needs real-device testing on cellular networks).
* **Priority:** `P1`

---

### Category F: Currencies, Economy & Metagame Systems

#### `ECO-01`: In-Match Gold
* **Element ID:** `ECO-01`
* **Name:** Tactical Battle Gold
* **Scene / File Location:** `scripts/game_state.gd:gold`
* **Intended Purpose:** Tactical in-battle volatile resource.
* **Actual Observed Behavior:** Earned from creep kills and wave bonuses; spent on towers, upgrades, sword, mercenaries, and wood. Resets every match.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Verified in all tests.
* **Dependencies & Side Effects:** Core game loop.
* **Player-Facing Value:** Core tactical decision making.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `ECO-02`: In-Match Wood
* **Element ID:** `ECO-02`
* **Name:** Tactical Battle Wood
* **Scene / File Location:** `scripts/game_state.gd:wood`
* **Intended Purpose:** Tactical in-battle volatile construction material.
* **Actual Observed Behavior:** Gathered by chopping trees or automated lumberjacks; spent on towers, castle repair, and castle tiers. Resets every match.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Verified in all tests.
* **Dependencies & Side Effects:** Core game loop.
* **Player-Facing Value:** Creates unique resource management tension.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `ECO-03`: In-Match Castle Lives
* **Element ID:** `ECO-03`
* **Name:** Castle Health / Lives
* **Scene / File Location:** `scripts/game_state.gd:lives`
* **Intended Purpose:** Castle hit points; match fails when reaching 0.
* **Actual Observed Behavior:** Decremented by leaking creeps; repaired with wood in Forge; increased by castle tier upgrades.
* **Status:** `WORKING`
* **Evidence Supporting Status:** Verified in all tests.
* **Dependencies & Side Effects:** Core game loop.
* **Player-Facing Value:** Win/loss condition.
* **Recommendation:** `KEEP`
* **Priority:** `P0`

#### `ECO-04`: Permanent Stars & Perks
* **Element ID:** `ECO-04`
* **Name:** Campaign Star Progression & Perks
* **Scene / File Location:** `scripts/perks.gd`, `resources/perks/*.tres`
* **Intended Purpose:** Earned by beating levels (up to 3★ per level); spent in Treasury on 7 permanent perks.
* **Actual Observed Behavior:** Perks correctly boost starting gold/wood/lives, hero damage, hero chop speed, tower damage, and hero movement. Can be refunded 100% for free at any time.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_meta.gd` passes 100%.
* **Dependencies & Side Effects:** `PlayerProfile`, `Main`.
* **Player-Facing Value:** Rewarding, flexible permanent progression.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `ECO-05`: Permanent Gems Ledger
* **Element ID:** `ECO-05`
* **Name:** Gem Currency & Wallet
* **Scene / File Location:** `scripts/wallet.gd`, `resources/economy.json`
* **Intended Purpose:** Hard meta-currency earned strictly through gameplay (never sold for real money). Balance is mathematically derived: `sum(claims) - sum(buys)`.
* **Actual Observed Behavior:** Earned from first wins, achievements, quests, streaks, calendar; spent in Shop on cosmetics. Prevents duplicate claims and syncs seamlessly across devices.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_wallet.gd` passes 100%.
* **Dependencies & Side Effects:** `PlayerProfile`, `Shop`.
* **Player-Facing Value:** Ethical, non-predatory cosmetic currency.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `ECO-06`: Treasury Coins & Meta Camp
* **Element ID:** `ECO-06`
* **Name:** Camp Treasury Coins
* **Scene / File Location:** `scripts/camp.gd`, `scripts/camp_panel.gd`, `scripts/economy.gd`
* **Intended Purpose:** Soft meta-currency intended to fund long-term automated helpers and tower talent trees per `docs/RETENTION_V2.md`.
* **Actual Observed Behavior:** Accumulated offline via Camp generator, rewarded on battle victories (+40/+80) and calendar. **CRITICAL DISCONNECT: The talent tree was never built. The only sink is upgrading the Camp generator itself up to Level 5. Once at Level 5, coins accumulate indefinitely with zero use.**
* **Status:** `PARTIAL` / `REWORK`
* **Evidence Supporting Status:** Code analysis of `camp.gd` and `economy.gd`. Zero references to spending `camp["coins"]` outside `Camp.upgrade()`.
* **Dependencies & Side Effects:** `CampPanel`, `Calendar28`, `Economy`.
* **Player-Facing Value:** Extremely confusing. Players earn thousands of coins with nothing to spend them on.
* **Recommendation:** `REWORK` (Build a real sink such as Tower Mastery / Codex upgrades, or convert coins to gems).
* **Priority:** `P0`

#### `ECO-07`: 28-Day Cumulative Calendar
* **Element ID:** `ECO-07`
* **Name:** 28-Day Retention Calendar
* **Scene / File Location:** `scripts/calendar28.gd`, `scripts/calendar_panel.gd`
* **Intended Purpose:** 28-step cumulative reward calendar granting coins and gems.
* **Actual Observed Behavior:** Fully functional, idempotent, and non-punishing.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_retention.gd`.
* **Dependencies & Side Effects:** `PlayerProfile`, `Wallet`, `Camp`.
* **Player-Facing Value:** Strong daily return hook.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `ECO-08`: 7-Day Streak & Forgiveness
* **Element ID:** `ECO-08`
* **Name:** Daily Login Streak
* **Scene / File Location:** `scripts/streak.gd`, `resources/economy.json`
* **Intended Purpose:** 7-day escalating gem reward ($5 \to 100$ gems) with 1 weekly forgiveness for a missed day.
* **Actual Observed Behavior:** Accurately tracks consecutive days; handles clock rollbacks safely; awards gems to wallet.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_streak.gd`.
* **Dependencies & Side Effects:** `PlayerProfile`, `Wallet`.
* **Player-Facing Value:** Proven retention mechanic.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `ECO-09`: Daily Quests
* **Element ID:** `ECO-09`
* **Name:** Daily Quest System
* **Scene / File Location:** `scripts/quests.gd`, `scripts/quest_tracker.gd`, `resources/quests.json`
* **Intended Purpose:** 3 randomized daily objectives offering gem rewards.
* **Actual Observed Behavior:** Listens to game commands and wave events; tracks progress; awards gems upon claiming.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_quests.gd`.
* **Dependencies & Side Effects:** `AchievementTracker`, `Wallet`.
* **Player-Facing Value:** Gives session-by-session direction.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `ECO-10`: Achievements Bitmask
* **Element ID:** `ECO-10`
* **Name:** 16-Bit Achievement System
* **Scene / File Location:** `scripts/achievements.gd`, `scripts/achievement_tracker.gd`, `resources/achievements.json`
* **Intended Purpose:** Compact bitmask tracking 16 gameplay achievements.
* **Actual Observed Behavior:** Evaluates conditions during battle; updates bitmask; unlocks claimable gems.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_achievements.gd`.
* **Dependencies & Side Effects:** `AchievementTracker`, `PlayerProfile`.
* **Player-Facing Value:** Milestone gratification.
* **Recommendation:** `KEEP`
* **Priority:** `P2`

#### `ECO-11`: Cosmetic Shop Catalog
* **Element ID:** `ECO-11`
* **Name:** Cosmetic Catalog (Lavka)
* **Scene / File Location:** `scripts/shop.gd`, `resources/shop.json`, `scripts/cosmetics.gd`
* **Intended Purpose:** Purely cosmetic shop offering 4 categories: Hero skins, Tower themes, Castle flag heraldry, and Hit spark FX.
* **Actual Observed Behavior:** Prices checked against `shop.json`; purchases deduct gems; items can be freely equipped/unequipped; 3D viewport live preview.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_shop.gd`, `tests/test_shop_ui.gd`.
* **Dependencies & Side Effects:** `Wallet`, `Cosmetics`.
* **Player-Facing Value:** Rewarding customization without pay-to-win.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `ECO-12`: First Win of Day Bonus
* **Element ID:** `ECO-12`
* **Name:** Daily First Victory Bonus
* **Scene / File Location:** `scripts/economy.gd:record_battle_victory()`
* **Intended Purpose:** Grants +5 gems under idempotent key `"fw:<date>"` and $\times 2$ treasury coins (+80) on the first campaign victory of each UTC day. Subsequent wins award +40 coins and 0 gems.
* **Actual Observed Behavior:** Correctly detects first daily victory, credits wallet and camp, and persists to save.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_retention.gd`.
* **Dependencies & Side Effects:** `Economy`, `Wallet`, `Camp`.
* **Player-Facing Value:** Strong incentive to complete at least one match daily.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

---

### Category G: Performance, Hardware & Device Adapters

#### `SYS-01`: Quality Guard Dynamic Scaler
* **Element ID:** `SYS-01`
* **Name:** Dynamic Performance Scaler
* **Scene / File Location:** `scripts/quality_guard.gd`
* **Intended Purpose:** Dynamically degrades rendering load if frame time $> 30$ ms: disables shadows, disables MSAA, scales 3D resolution down to 60%, hides distant decor.
* **Actual Observed Behavior:** Monitors frame times; drops quality tiers progressively; never flip-flops; remembers session tier.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_quality_guard.gd` passes 100%.
* **Dependencies & Side Effects:** `DirectionalLight3D`, `Viewport`.
* **Player-Facing Value:** Prevents stutter and crashes on low-end hardware.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `SYS-02`: Memory Watch
* **Element ID:** `SYS-02`
* **Name:** System RAM Monitor
* **Scene / File Location:** `scripts/memory_watch.gd`
* **Intended Purpose:** Reads `/proc/meminfo` on Android or monitors engine memory to trigger emergency quality reduction before Android OOM killer terminates the process.
* **Actual Observed Behavior:** Triggers `memory_low(critical)` signal; forces QualityGuard to lowest tier if RAM is critically low.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_memory_budget.gd`.
* **Dependencies & Side Effects:** `QualityGuard`.
* **Player-Facing Value:** Dramatically reduces low-memory background kills.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `SYS-03`: Crash Reporter & Exit Reasons
* **Element ID:** `SYS-03`
* **Name:** Crashlytics & Low-Memory Kill Attribution
* **Scene / File Location:** `scripts/crash_reporter.gd`, `scripts/exit_reasons.gd`, `scripts/crash_trace.gd`
* **Intended Purpose:** Reports native crash traces and queries `ApplicationExitInfo` to explain why the previous session terminated (e.g. user swipe vs OS memory kill).
* **Actual Observed Behavior:** Works on Android Gradle builds; safely no-ops on desktop and tests.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `tests/test_exit_reasons.gd`.
* **Dependencies & Side Effects:** `JavaClassWrapper`.
* **Player-Facing Value:** Essential diagnostics for stability.
* **Recommendation:** `KEEP`
* **Priority:** `P1`

#### `SYS-04`: Diagnostics Overlay
* **Element ID:** `SYS-04`
* **Name:** On-Screen Debug HUD
* **Scene / File Location:** `scripts/diag_overlay.gd`
* **Intended Purpose:** Secret debug overlay toggled by tapping version line 5 times in Settings. Displays FPS, frame time, RAM usage, entity counts, simulation tick cost.
* **Actual Observed Behavior:** Instantiated by `Main._start_diagnostics()`; visible when `GameSettings.diagnostics() == true`.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `main.gd:572`, `tests/test_quality_guard.gd`.
* **Dependencies & Side Effects:** `GameSettings`, `QualityGuard`.
* **Player-Facing Value:** Invaluable QA tool for testers without desktop cables.
* **Recommendation:** `KEEP`
* **Priority:** `P2`

#### `SYS-05`: Layout Preview
* **Element ID:** `SYS-05`
* **Name:** HUD Layout Schematic
* **Scene / File Location:** `scripts/layout_preview.gd`
* **Intended Purpose:** Schematic drawing inside Settings dialog showing control layout.
* **Actual Observed Behavior:** Drawn procedurally using `_draw()`.
* **Status:** `WORKING`
* **Evidence Supporting Status:** `settings_panel.gd:272`.
* **Dependencies & Side Effects:** `HudLayout`.
* **Player-Facing Value:** Visual clarification of layout settings.
* **Recommendation:** `KEEP`
* **Priority:** `P3`

#### `SYS-06`: Camera Follow vs Game Camera Wrapper
* **Element ID:** `SYS-06`
* **Name:** Camera System Wrapper Redundancy
* **Scene / File Location:** `scripts/camera_follow.gd`, `scripts/game_camera.gd`
* **Intended Purpose:** Camera management.
* **Actual Observed Behavior:** `scripts/camera_follow.gd` (230 lines) implements all camera follow, gestures, pans, zoom, and bounds logic. `scripts/game_camera.gd` is an empty 3-line wrapper (`class_name GameCamera extends CameraFollow`).
* **Status:** `UNUSED` / `REDUNDANT`
* **Evidence Supporting Status:** Inspection of `scripts/game_camera.gd`. `main.tscn` directly attaches `scripts/camera_follow.gd`.
* **Dependencies & Side Effects:** None.
* **Player-Facing Value:** None.
* **Recommendation:** `REMOVE` `scripts/game_camera.gd` to eliminate dead abstraction.
* **Priority:** `P3`

#### `SYS-07`: Touch Joystick vs Virtual Joystick Wrapper
* **Element ID:** `SYS-07`
* **Name:** Joystick System Wrapper Redundancy
* **Scene / File Location:** `scripts/touch_joystick.gd`, `scripts/virtual_joystick.gd`
* **Intended Purpose:** On-screen joystick control.
* **Actual Observed Behavior:** `scripts/touch_joystick.gd` implements the full virtual touch joystick. `scripts/virtual_joystick.gd` is an obsolete 2-line wrapper (`extends TouchJoystick`).
* **Status:** `UNUSED` / `REDUNDANT`
* **Evidence Supporting Status:** `ui/hud.tscn` directly attaches `scripts/touch_joystick.gd`.
* **Dependencies & Side Effects:** Backwards compatibility comment only.
* **Player-Facing Value:** None.
* **Recommendation:** `REMOVE` `scripts/virtual_joystick.gd`.
* **Priority:** `P3`

---

## 3. Deep-Dive Audits of Critical Architectural Areas

### 3.1 Deep Dive: The "Camp" Disconnect (Main Menu Coins vs In-Match Gold)

A primary directive of this audit is investigating the relationship between Main Menu Treasury Coins and In-Match Tactical Gold.

#### The Reality in the Codebase:
1. **Two Completely Disconnected Currencies:**
   * **In-Match Gold (`GameState.gold`):** Volatile runtime currency earned during battle by killing creeps and clearing waves. Spent in battle on building towers, upgrading towers, hero sword upgrades, hiring mercenaries, and buying wood from villagers. Resets completely at the end of each battle.
   * **Treasury Coins (`Camp.coins`):** Meta-currency stored in `user://progress.cfg` under `[camp]` and synchronized to Firestore `users/{uid}`. Earned through offline idle accumulation in the Camp dialog, daily first-win battle bonuses (+80 coins), subsequent victories (+40 coins), and the 28-day calendar.
2. **The Missing Sink (Dead-End Loop):**
   * Coins can be spent on exactly **ONE** thing: upgrading the offline Camp generator (`Camp.upgrade()`) across 5 levels (Costs: 0, 150, 350, 750, 1500 coins).
   * Upgrading the Camp only increases the rate at which it generates more coins ($10 \to 30$ coins/h) and increases the cap ($8 \to 16$ h).
   * **Once a player reaches Camp Level 5, Treasury Coins have ZERO utility.** They cannot be spent in battle, cannot purchase shop items (the shop strictly uses gems), cannot purchase perk stars (perks strictly use stars), and cannot be converted into any other asset.
3. **Severe Naming Collision & Player Confusion:**
   * **Meta Camp (`scripts/camp.gd`, `scripts/camp_panel.gd`):** Accessed via the World Map. Generates offline treasury coins.
   * **Battlefield Camps (`scripts/camp_structures.gd`):** Procedural 3D buildings physically placed inside the battle match (`LumberjackCamp` and `MercenaryCamp`). They interact with in-match Gold and Wood to hire lumberjacks and recruit mercenaries.
   * Both are called "Лагерь" / "Camp" in the UI and localization, leading players to assume that upgrading the Camp on the World Map improves the Lumberjack/Mercenary camps in battle. **In reality, there is zero programmatic connection between them.**
4. **Historical Root Cause:**
   * `docs/RETENTION_V2.md` outlined a two-stage retention vision:
     - Stage A/B: Camp offline accumulator + 28-day calendar (Implemented).
     - Stage C: A deep "Tower Talent Tree" and "Automation Assistants" funded by Treasury Coins (Never Implemented).
   * Stage A/B was merged into the codebase without Stage C, leaving the currency orphaned.

#### Recommendation:
* **Option A (Recommended - Meaningful Meta Sink):** Implement a simple Tower Mastery / Codex sink. Allow Treasury Coins to fund minor permanent cosmetic or utility upgrades in the Encyclopedia (e.g. unlocking lore entries, bestiary stats, or small non-breaking campaign perks).
* **Option B (Currency Consolidation):** Remove Treasury Coins entirely. Change the Camp offline generator to accumulate Gems at a modest rate (e.g. 1–3 gems/h up to 15 gems cap), feeding directly into the cosmetic Shop.
* **Rename Battlefield Structures:** Rename the in-match structures to "Woodcutter Lodge" (`LumberjackLodge`) and "Mercenary Pavilion" (`MercenaryPavilion`) to immediately dispel the naming confusion.

---

### 3.2 Deep Dive: UI Controls, Buttons, Tabs & Modals Audit

A comprehensive traversal of every button, tab, and modal confirms:
* **Total Screens:** 8 (`boot`, `welcome`, `nickname`, `tutorial`, `level_select`, `main`, `shop`, `coop_lobby`). All 8 open, transition, and close cleanly.
* **Total Modals:** 15 (`Treasury`, `StreakPanel`, `CampPanel`, `CalendarPanel`, `ModesPanel`, `DailyPanel`, `RecordsPanel`, `AchievementsPanel`, `EncyclopediaPanel`, `SettingsPanel`, `AccountPanel`, `EmailAuthDialog`, `AccountReminder`, `GemsHud`, `EndScreen`).
* **Modal Architecture:** All dialogs use `scripts/dialog_frame.gd` with centered dimming overlays and standard close buttons.
* **Android Back Button Integration:** `NOTIFICATION_WM_GO_BACK_REQUEST` is universally handled across all screens. Tapping Back while a modal is open closes the top-most modal; tapping Back on the World Map exits cleanly.
* **Button State Visual Feedback:** Buttons properly differentiate disabled, hovered, and pressed states through `ui/theme.tres` variations (`NodeBlue`, `NodeGold`, `NodeGreen`, `PrimaryButton`, `SecondaryButton`, `TabButton`).
* **Visual Polish Defect Identified:**
  - In `StreakPanel`, the top buttons for `CampButton` and `CalendarButton` are standard rectangular buttons that feel visually cramped next to the flame banner. A unified "Rewards Hub" ribbon header would look much cleaner.

---

### 3.3 Deep Dive: Unused Resources & Dead Code Inventory

| Item Path | Type | Current Status | Impact & Recommendation |
| :--- | :--- | :--- | :--- |
| `resources/enemies/slime_splitter.tres` | `Resource` | Unused in wave plans | **KEEP & ACTIVATE:** Fully functional splitting enemy logic in `enemy.gd`. Add to Level 4–6 wave plans. |
| `resources/enemies/slime_mini.tres` | `Resource` | Unused in wave plans | **KEEP & ACTIVATE:** Child unit spawned by `slime_splitter`. |
| `assets/models/slime_splitter.glb` | 3D Model | Referenced by unused tres | Keep alongside `slime_splitter.tres`. |
| `assets/models/slime_mini.glb` | 3D Model | Referenced by unused tres | Keep alongside `slime_mini.tres`. |
| `ui/icons/slime_splitter.png` | Texture | Unused in UI | Keep for Encyclopedia when splitter is activated. |
| `scripts/game_camera.gd` | Script | Obsolete wrapper | **REMOVE:** 3-line stub inheriting `CameraFollow`. Unused. |
| `scripts/virtual_joystick.gd` | Script | Obsolete wrapper | **REMOVE:** 2-line stub inheriting `TouchJoystick`. Unused. |

---

### 3.4 Deep Dive: Critical Pre-Release Gaps & Test Flaws

1. **Missing Google Play Required URLs in `GameInfo` (P0 Blocker):**
   `scripts/game_info.gd` contains:
   ```gdscript
   const PRIVACY_URL := ""
   const DELETION_URL := ""
   const SUPPORT_EMAIL := ""
   ```
   *Google Play will reject app submission* without an active web-accessible Privacy Policy and an in-browser Account Deletion request URL.
   *Action:* Publish `docs/PRIVACY.md` to web hosting (e.g. GitHub Pages or Firebase Hosting) and populate these strings.
2. **Headless Test Frame-Rate Sensitivity:**
   In `tests/test_gameplay.gd`, testing Level 3 failed on `wait_until()` when executed under heavy CPU load without `--fixed-fps 60`, but passed 100% when run with fixed FPS.
   *Action:* Ensure all headless test runners enforce `--fixed-fps 60` consistently in CI scripts.
3. **Headless AudioStreamPlaybackWAV Object Leaks:**
   Godot's headless dummy audio driver leaks audio stream playback instances at exit.
   *Action:* Harmless in production builds on Android, but noisy in CI. Already documented in `expected_errors.txt`.

---

## 4. Prioritized Action Matrix for Subsequent Phases

| Priority | Element ID | Title / Task | Subsystem | Action Required |
| :--- | :--- | :--- | :--- | :--- |
| **P0** | `SYS-REL` | **Store Compliance URLs** | Meta / Legal | Set `PRIVACY_URL`, `DELETION_URL`, and `SUPPORT_EMAIL` in `scripts/game_info.gd`. |
| **P0** | `ECO-06` | **Resolve Camp Coin Disconnect** | Economy | Implement a meaningful sink for Treasury Coins (Tower Mastery in Encyclopedia) or convert to Gems. |
| **P1** | `MEC-10` | **Disambiguate Camp Naming** | In-Match / UI | Rename in-match structures to "Woodcutter Lodge" and "Mercenary Pavilion" to eliminate player confusion with the Meta Camp. |
| **P1** | `ENT-14` | **Activate Slime Splitter** | Content / Waves | Add `slime_splitter` to Level 4–6 wave plans in `resources/levels.json` and add entry to `EncyclopediaPanel`. |
| **P2** | `MOD-03` | **Camp Panel UI Polish** | UI / Modals | Add visual feedback explaining what Camp coins are for once Level 5 is reached. |
| **P2** | `MOD-02` | **Rewards Hub Layout** | UI / Modals | Improve layout of `CampButton` and `CalendarButton` inside `StreakPanel`. |
| **P3** | `SYS-06` | **Delete `game_camera.gd`** | Technical Debt | Remove redundant 3-line wrapper script. |
| **P3** | `SYS-07` | **Delete `virtual_joystick.gd`** | Technical Debt | Remove redundant 2-line wrapper script. |

---

## 5. Audit Certification

This completes Phase 1 (Project Discovery) and Phase 2 (Functionality & Placeholder Audit) for Bimbleguard. All systems, scripts, scenes, UI screens, economy loops, and assets have been rigorously evaluated against the codebase without modifying any game code or scene files.
