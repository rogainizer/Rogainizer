# Vue 3 + Vite

This template should help get you started developing with Vue 3 in Vite. The template uses Vue 3 `<script setup>` SFCs, check out the [script setup docs](https://v3.vuejs.org/api/sfc-script-setup.html#sfc-script-setup) to learn more.

Learn more about IDE Support for Vue in the [Vue Docs Scaling up Guide](https://vuejs.org/guide/scaling-up/tooling.html#ide-support).

## Environment

### `VITE_API_BASE_URL`

Configures the backend API base URL used by the frontend.

- Default dev value: `http://localhost:3000`
- Example deployed value: `https://your-deployed-api.example.com`

For the normal local workflow, run `npm run dev` and the frontend will use the local backend.

To run the frontend in dev mode against a deployed backend API:

1. Copy `frontend/.env.remote-api.example` to `frontend/.env.remote-api.local`
2. Set `VITE_API_BASE_URL` to the deployed backend URL
3. Run `npm run dev:web:remote-api` from the repo root, or `npm run dev:remote-api` from `frontend`

### `VITE_SCALE_WEIGHTING_TABLE`

Configures duration-based weighting for scaled transformed values.

- Format: `duration,weighting;duration,weighting;...`
- Example: `24,1.20;12,1.00;6,0.80;3,0.60;2,0.50;0,0.30`
- Matching rule: scan from left to right and use the first row where `event_duration >= duration`

If omitted or invalid, the app uses the example table above as defaults.
