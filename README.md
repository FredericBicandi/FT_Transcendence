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

For Google and GitHub authentication, enable each provider in Supabase and add
`http://localhost:3000/auth/callback` and `https://pixelfight.live/auth/callback`
to the allowed redirect URLs. Never place a Supabase secret key or service-role
key in a `NEXT_PUBLIC_` variable.

For email login, enable the Email provider in Supabase. Configure SMTP in
`Supabase Dashboard > Project Settings > Authentication > SMTP Settings`, then
set the confirmation or magic-link email template to send an OTP token:

```html
<h2>🎮 Verify your PixelFight account</h2>

<p>Welcome to PixelFight.</p>

<p>Use the verification code below to continue:</p>

<div style="text-align:center; margin:30px 0;">
  <span style="
    font-size:36px;
    font-weight:bold;
    letter-spacing:10px;
    padding:12px 24px;
    border:2px solid #3b82f6;
    border-radius:8px;
    display:inline-block;
  ">
    {{ .Token }}
  </span>
</div>

<p>This code will expire in 10 minutes.</p>

<p>If you did not request this code, you can safely ignore this email.</p>

<hr>

<p><strong>PixelFight Team</strong></p>

<p>https://pixelfight.live</p>
```

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
