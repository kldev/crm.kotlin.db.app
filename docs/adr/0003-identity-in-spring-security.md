# 0003. Identity in Spring Security, users in the database

Status: Accepted
Date: 2026-11-08

## Decision

- Login with `POST /api/auth/login` (JSON). `AuthenticationManager` with `DaoAuthenticationProvider`, users loaded
  by `EXEC app.user_get_for_login`, passwords hashed with the delegating encoder (bcrypt by default). The hash is
  verified in the application, never in SQL.
- The authenticated user is stored in the HTTP session (cookie `JSESSIONID`, HttpOnly, SameSite=Lax); the session
  id changes on login. CSRF: cookie `XSRF-TOKEN`, sent back as the `X-XSRF-TOKEN` header; `GET /api/auth/csrf`
  sets the cookie before the first POST.
- Every failure answers the same 401 "Invalid login or password." A wrong password calls
  `app.user_login_failed`, which locks the account for `CRM_LOGIN_LOCK_MINUTES` after `CRM_LOGIN_MAX_FAILED`
  failures in a row.
- Roles: ADMIN (users, teams), MANAGER (all clients and projects, deletes clients), SALES (own clients; projects
  they own, of their teams or of their clients). Coarse rules in `SecurityConfig`, the real rules in the procedures.
- The first ADMIN comes from `CRM_ADMIN_LOGIN` / `CRM_ADMIN_PASSWORD` and is created only when no ADMIN exists.

## Alternatives considered

- JWT: no server state, but our own token issuing and revocation; a session is simpler for one instance.
- An external identity provider: out of scope for a small self-contained project.
