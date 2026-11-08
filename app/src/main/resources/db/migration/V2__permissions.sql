-- ADR-0002: the application login may only execute procedures from schema `app`.
-- No SELECT/INSERT/UPDATE/DELETE on tables, no access to `seed`. ${app_user} is a Flyway placeholder.
GRANT EXECUTE ON SCHEMA::app TO [${app_user}];
