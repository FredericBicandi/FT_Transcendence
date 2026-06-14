# FT_Transcendence

<p align="center">
  <img src="https://github.com/FreddyBicandy50/FreddyBicandy50/blob/main/42_badges/ft_transcendencee.png" alt="ft_transcendencee 42 project badge"/>
</p>

## Status
Started: 04/03/2026.

Finished: -.

Grade: -%.

## Project Idea
 Design, develop, and organize a full-stack web application with complete creative freedom. Choose your project concept, select from a wide range of technical modules, and make key architectural decisions. This highly flexible project allows you to explore modern web     development while demonstrating your technical skills and creativity through a modular approach. 

## Usage
1. Install dependencies:

   ```bash
   npm install
   ```

2. Create the local environment file:

   ```bash
   cp .env.example .env
   ```

3. Fill in the Supabase project URL and publishable key from
   `Supabase Dashboard > Project Settings > API`. Set
   `NEXT_PUBLIC_DASHBOARD_WS_URL` to the dedicated dashboard WebSocket endpoint,
   for example `wss://example.com/ws/dashboard`. Dashboard WebSocket connections
   do not use Supabase authentication. Global chat messages send `player_id`,
   `player_name`, and `content` in the message payload.

4. Start the dashboard:

   ```bash
   npm run dev
   ```

For Google authentication, enable the Google provider in Supabase and add
`http://localhost:3000/auth/callback` and the production callback URL to the
allowed redirect URLs. Never place a Supabase secret key or service-role key in
a `NEXT_PUBLIC_` variable.

## Godot match callback

After a match ends, the Godot web export must send this message to its parent
window:

```javascript
window.parent.postMessage(
  {
    type: "match_saved",
    match_id: "00000000-0000-0000-0000-000000000000",
    score: 1200,
    kills: 8,
    deaths: 3,
    duration_seconds: 245,
  },
  window.location.origin,
);
```

The dashboard accepts the callback only from the same-origin game iframe. For
authenticated players, it reads the current Supabase user and asynchronously
inserts `match_id`, `user_id`, `score`, `kills`, `deaths`, and `time_played`
into `public.played_matches`. The `match_id` must already exist in
`public.matches`. Guest match callbacks are ignored.

## Guides

The most interesting part of any project is the research that goes behind it. If you are a student, please don't miss out on that opportunity by simply following guides such as these. In any case, they should under no circumstances be your only source of information about this project. Try things, fail, research, try again and succeed! And maybe write your own guide about it. Writing really is the best way to learn.

---
fbicandy@student.42.fr | LinkedIn: [fbicandy](https://www.linkedin.com/in/freddy-bicandy/)
