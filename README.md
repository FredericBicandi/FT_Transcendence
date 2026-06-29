*This project has been created as part of the 42 curriculum by fbicandy, dawwad.*

# FT Transcendence - PixelFight

<p align="center">
  <img src="https://github.com/FreddyBicandy50/FreddyBicandy50/blob/main/42_badges/ft_transcendencee.png" alt="ft_transcendencee 42 project badge"/>
</p>

## Description

PixelFight is a full-stack multiplayer web game built for ft_transcendence. The project combines a Next.js dashboard, a Godot web game export, a Godot source project, a .NET 8 WebSocket server, and Supabase-backed authentication and persistence hosted on google cloud services.

Key features:

- Browser dashboard with guest play, authenticated profiles, OAuth login, account deletion, avatar/name setup, XP, levels, and match history.
- Embedded Godot web export served from `public/Game`.
- Source Godot project in `game/` for gameplay iteration and re-export.
- .NET 8 WebSocket server in `server/` for matchmaking, game rooms, live dashboard presence, global chat, authoritative combat events, leaderboard updates, match timers, and Supabase match persistence.
- Multiplayer 2D shooter gameplay with movement, weapons, projectiles, health, medkits, deaths, respawns, kill feed, scoreboard, custom cursor, sound, map work, and chat support.

## Instructions

Prerequisites:

- Node.js 22 or compatible with Next.js 16.
- npm.
- .NET SDK 8.0.
- Docker, if using the Makefile Docker targets.
- Godot 4.6, if editing or exporting the game source in `game/`.
- A Supabase project with the tables described below.

Environment variables for the web app:

```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=your-publishable-key
NEXT_PUBLIC_APP_URL=http://localhost:3000
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

Copy `.env.example` to `.env` at the repository root and replace its
placeholders with the evaluator configuration. The file is used by the Next.js
application and passed to the dashboard container at runtime. For the deployed
website, use `https://pixelfight.live` for `NEXT_PUBLIC_APP_URL`. The dashboard
socket defaults to `/ws/dashboard` on the current host;
`NEXT_PUBLIC_DASHBOARD_WS_URL` is an optional override for deployments where
the WebSocket uses a different origin. Keep the service-role key only in the
local `.env`; it must never be committed or exposed to browser code.

The Dockerized game server receives the same root `.env` through its Makefile,
so `make re` does not require an ignored local configuration file. For direct
`dotnet run`, either export `Supabase__Url` and `Supabase__ServiceRoleKey`, or
copy `server/Properties/examples/appsettings.json` to
`server/Properties/appsettings.json` and replace its placeholders.
`appsettings.json` remains ignored because the service-role key must never be
committed or exposed to browser code.

Run locally without Docker:

```sh
npm ci
npm run dev
dotnet run --project server/FT_Transcendence.csproj
```

The web dashboard runs on `http://localhost:3000`. The server exposes the game socket at `ws://localhost:5000/ws` and the dashboard socket at `ws://localhost:5000/ws/dashboard`.

Run with Makefile/Docker:

```sh
make re
```

`make re` is the single-command deployment entry point. It removes previous
project containers/images, rebuilds the dashboard and server images, and starts
both containers. The individual lifecycle commands remain available:

```sh
make build
make run
make logs
make stop
```

Useful scoped targets:

```sh
make web-build
make web-run
make server-build
make server-run
make server-logs
```

Open the editable game project with Godot from `game/project.godot`. The exported web build used by the dashboard is committed under `public/Game`.

## Team Information

- `fbicandy`: Product Owner (PO), Project Manager (PM), and Technical Lead.
- `dawwad`: Developer and Artist.

## Project Management

- Work was split by component: web dashboard, WebSocket server, Godot gameplay, and deployment/export integration.
- Git branches were used for parallel work: `web`, `server`, and `game`, then merged into `main` with preserved history.
- Notion was used to organize the roadmap, assign tasks, and track progress.
- Project roadmap and task tracking: [FT_TRANSCENDENCE Notion workspace](https://freddybicandy.notion.site/FT_TRANSCENDENCE-5ab4c72bfb668349a1a101a19ff19a99).
- Git branches and commits connected implementation work to the tracked tasks.
- Communication and coordination happened through Discord text/voice channels and regular face-to-face meetings.
- Progress was reviewed through team discussions, iterative commits, local testing, and feature-focused branch updates.

## Technical Stack

- Frontend: Next.js 16, React 19, TypeScript, Tailwind CSS 4, Supabase SSR/client libraries.
- Game: Godot 4.6 source project and Godot web export.
- Backend: .NET 8 ASP.NET Core minimal app using native WebSockets and `HttpClient`.
- Database/auth: Supabase Auth and Supabase Postgres.
- Runtime/deployment: Dockerfiles for web and server, Makefile targets for build/run/cleanup.
- Hosting: Google Cloud Platform.
- Domain and DNS: Name.com.
- Reverse proxy and HTTPS termination: Nginx.
- TLS certificates: Let’s Encrypt managed with Certbot.

Supabase was chosen because it provides hosted Postgres, authentication, OAuth support, REST access, and browser/server SDKs with a small amount of infrastructure code. The .NET server owns real-time gameplay because authoritative room and combat state needs long-running WebSocket handling. The Godot export is embedded in Next.js so the dashboard can pass player identity and profile state into the game.

## Database Schema

The application uses Supabase Auth and three public Postgres tables:

- `profiles`: at most one row per authenticated user. `id` is a UUID primary key referencing `auth.users(id)` with cascade deletion. It stores the unique username, optional avatar, level, XP, and creation/update timestamps.
- `matches`: one authoritative record per completed game. It stores the match UUID, start/end timestamps, duration, and creation timestamp.
- `played_matches`: one result per player and match. It references `matches(id)` and `auth.users(id)` with cascade deletion and stores score, kills, deaths, play time, and creation time.

Relationships and indexes:

- One Auth user has at most one profile.
- One match has many player-result rows.
- One Auth user has many player-result rows.
- `(user_id, match_id)` is unique, preventing duplicate match rewards.
- User and match foreign-key columns are indexed for history queries.
- Usernames have a case-insensitive unique index.

Database-enforced validation:

- Usernames contain 1–12 lowercase letters.
- Avatar values must be HTTPS URLs or supported image data URLs and are size-limited.
- XP is restricted to `0..1,000,000`; levels to `0..10,000`.
- Match duration and player play time are restricted to `0..300` seconds.
- Scores are restricted to `0..1,000,000`; kills and deaths to `0..1,000`.
- Match end timestamps cannot precede their start timestamps.

Row-level security and trusted writers:

- Anonymous and authenticated clients may read public profiles.
- Authenticated users may read only their own `played_matches` rows.
- Browser roles cannot directly insert, update, or delete game data.
- `PATCH /api/profile` validates profile changes and writes with the server-only service role.
- `POST /api/matches` validates match results, prevents duplicates, and calculates XP server-side.
- The authoritative .NET server writes `matches` using its server-only service-role key.
- The account deletion route uses the service role after validating the requesting user’s session.

Apply `supabase/migrations/schema.sql` first and
`supabase/migrations/rls.sql` second. Both scripts are idempotent and can
create missing objects or reconcile an existing project without deleting
legacy rows.

## Features List

### Frontend

- UI and UX: `fbicandy`.
- Global dashboard chat: `fbicandy`.
- Forms and server-side validation: `fbicandy`.
- Secure authentication and login flows: `fbicandy`.

- Website responsiveness: `dawwad`.
- Profile management and match logs: `dawwad`.

### Database

- Database schema and constraints: `dawwad`.

- Row-level security policies: `fbicandy`.
- SMTP, email OTP, Google OAuth, and GitHub OAuth setup: `fbicandy`.

### Backend

- Multiplayer game WebSocket server: `fbicandy`.
- Player count and global chat dashboard WebSocket server: `fbicandy`.

### Game

- Pixel art and visual assets: `dawwad`.
- Weapons and player sprites: `dawwad`.
- Game balancing and gameplay features: `dawwad`.

- In-game chat: `fbicandy`.
- Kill feed and respawn systems: `fbicandy`.
- Connection and online multiplayer logic: `fbicandy`.
- Match timer, leaderboard, and weapon switcher: `fbicandy`.

## Modules

Official module set:

- IV.1 Web - Major: Use a framework for both the frontend and backend, 2 pts. Owner: `fbicandy`. Implemented with Next.js 16, React 19, and TypeScript for the frontend dashboard, plus an ASP.NET Core/.NET 8 backend framework for the real-time game server.
- IV.1 Web - Major: Implement real-time features using WebSockets or similar technology, 2 pts. Owner: `fbicandy`. Implemented with `/ws` for multiplayer gameplay and `/ws/dashboard` for live lobby presence/global chat. The server broadcasts room state, movement, combat events, medkit state, timers, leaderboard snapshots, chat messages, and online counts while handling disconnect cleanup, heartbeat/inactivity timeouts, message size limits, and chat rate limits.
- IV.1 Web - Minor: Server-Side Rendering (SSR) for improved performance and SEO, 1 pt. Owner: `fbicandy`. The Next.js dashboard route is dynamically rendered for each request. It validates the Supabase session from the request cookies and loads the authenticated user's normalized username, avatar, XP, and level on the server, so the initial HTML contains the user's dashboard state before React hydration. Browser-side controllers then add live WebSocket and game interactions.
- IV.1 Web - Minor: Custom-made design system with reusable components, including a proper color palette, typography, and icons, 1 pt. Owners: `fbicandy`, `dawwad`. `fbicandy` owns the dashboard UI/UX and reusable React components; `dawwad` owns the pixel-art direction and visual assets. The shared visual system defines the project palette, typography, interaction states, animations, and iconography.
- IV.2 Accessibility and Internationalization - Minor: Support for multiple languages, 1 pt. Owners: `fbicandy` for the dashboard and `dawwad` for the Godot game. Implemented an i18n system for English, French, and Arabic in `src/views/home/homeTranslations.ts`, with a language switcher in the UI. The Godot game also has localization helpers for translated in-game text and language-specific fonts.
- IV.2 Accessibility and Internationalization - Minor: Right-to-left (RTL) language support, 1 pt. Owners: `fbicandy` for the dashboard and `dawwad` for the Godot game. Implemented Arabic RTL support in the dashboard with `dir="rtl"`/`lang="ar"` switching and RTL-aware chat layout. The Godot game applies Arabic fonts and RTL layout direction through its localization helper.
- IV.2 Accessibility and Internationalization - Minor: Support for additional browsers, 1 pt. Owners: `fbicandy`, `dawwad`. `fbicandy` owns dashboard compatibility and `dawwad` owns responsive behavior and the Godot web experience. The complete application has been tested on Chrome, Firefox, Microsoft Edge, and Brave.
- IV.3 User Management - Minor: Game statistics and match history, 1 pt. Owner: `dawwad`. Implemented Supabase-backed player progression and match logs through `profiles`, `matches`, and `played_matches`. The dashboard displays XP, level, score, kills, deaths, play time, saved match history, and leaderboard-derived match results.
- IV.3 User Management - Minor: Implement remote authentication with OAuth 2.0, 1 pt. Owner: `fbicandy`. Implemented and tested Supabase OAuth login with Google and GitHub providers, plus email OTP authentication and an OAuth callback route that returns users to the dashboard after authentication.
- IV.6 Gaming and user experience - Major: Implement a complete web-based game where users can play against each other, 2 pts. Owners: `fbicandy`, `dawwad`. `dawwad` owns pixel art, assets, weapons, player sprites, balancing, and gameplay features. `fbicandy` owns the kill feed, respawn system, timer, leaderboard, weapon switcher, connection logic, and in-game chat.
- IV.6 Gaming and user experience - Major: Remote players - Enable two players on separate computers to play the same game in real-time, 2 pts. Owner: `fbicandy`. Implemented through the .NET game WebSocket server and Godot connection/online logic, including shared rooms, real-time combat state, leaderboard updates, disconnect cleanup, and timeouts.
- IV.6 Gaming and user experience - Major: Multiplayer game (more than two players), 2 pts. Owner: `fbicandy`. Implemented game rooms with a maximum capacity of 8 players. The server synchronizes room membership, player state, combat events, medkit state, leaderboard snapshots, match timers, and final match results across all joined clients.

Total: 17 points.

## Individual Contributions

`fbicandy`, acting as Product Owner, Project Manager, and Technical Lead, contributed frontend UI/UX, secure authentication, forms and server-side validation, global chat, SMTP/OTP/OAuth configuration, row-level security, both .NET WebSocket paths, and the game’s kill feed, respawn, timer, leaderboard, weapon switcher, connection logic, and in-game chat.

`dawwad`, acting as Developer and Artist, contributed website responsiveness, profile management and match logs, database schema and constraints, pixel art and assets, game balancing and features, weapons, and player sprites.

Main challenges included keeping the Godot export synchronized with the dashboard, maintaining a stable WebSocket protocol across client/server changes, avoiding duplicate online presence across reconnects, handling guest versus authenticated profiles, and preserving branch history while consolidating the final repository structure.

## Resources

- Next.js documentation: https://nextjs.org/docs
- React documentation: https://react.dev
- Supabase documentation: https://supabase.com/docs
- ASP.NET Core WebSockets documentation: https://learn.microsoft.com/aspnet/core/fundamentals/websockets
- Godot documentation: https://docs.godotengine.org
- Docker documentation: https://docs.docker.com
- Google Cloud documentation: https://cloud.google.com/docs
- Name.com domain and DNS documentation: https://www.name.com/support
- Nginx documentation: https://nginx.org/en/docs/
- Let’s Encrypt documentation: https://letsencrypt.org/docs/
- Certbot documentation: https://eff-certbot.readthedocs.io/

AI usage: AI assistance was used during development for debugging, code review, protocol edge-case analysis, refactoring suggestions, comments, README preparation, and repository integration planning. The team reviewed and integrated the resulting changes manually in the project codebase.

## License

See `LICENSE`.
