# Zenith Account Server (Prototype)

Simple auth server for Zenith account creation/login and reward balance.

## Run

```bash
cd server
dart pub get
dart run bin/server.dart
```

Server defaults to `http://0.0.0.0:3000`.

## Environment Variables

- `ZENITH_HOST` (default `0.0.0.0`)
- `ZENITH_PORT` (default `3000`)
- `ZENITH_JWT_SECRET` (default `dev-secret-change-me` for local dev only)
- `ZENITH_DB_PATH` (default `data/accounts.json`)

## API

- `POST /api/register` body: `{ "email": "a@b.com", "password": "secret123" }`
- `POST /api/login` body: `{ "email": "a@b.com", "password": "secret123" }`
- `GET /api/me` header: `Authorization: Bearer <token>`
- `POST /api/reward` header: `Authorization: Bearer <token>` body: `{ "amount": 10 }`

A lightweight web page for signup/login is available at `/`.
