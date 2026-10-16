CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;

DROP SCHEMA IF EXISTS library CASCADE;
CREATE SCHEMA library;
SET search_path TO library, public;

DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET search_path = library, public', current_database());
END;
$$;

CREATE TYPE copy_status AS ENUM ('available', 'on_loan', 'reserved', 'in_repair', 'lost', 'written_off');
CREATE TYPE loan_status AS ENUM ('active', 'returned', 'overdue', 'lost');
CREATE TYPE reservation_status AS ENUM ('pending', 'ready', 'fulfilled', 'cancelled', 'expired');
CREATE TYPE fine_status AS ENUM ('unpaid', 'paid', 'waived');
CREATE TYPE payment_method AS ENUM ('cash', 'card', 'online');
CREATE TYPE order_status AS ENUM ('new', 'in_progress', 'completed', 'cancelled');

CREATE TABLE roles (
    role_id      SMALLSERIAL PRIMARY KEY,
    code         VARCHAR(30)  NOT NULL UNIQUE,
    name         VARCHAR(100) NOT NULL,
    description  TEXT
);

CREATE TABLE branches (
    branch_id    SERIAL PRIMARY KEY,
    name         VARCHAR(150) NOT NULL UNIQUE,
    address      VARCHAR(255) NOT NULL,
    phone        VARCHAR(20),
    opens_at     TIME NOT NULL DEFAULT '09:00',
    closes_at    TIME NOT NULL DEFAULT '19:00',
    CONSTRAINT ck_branches_hours CHECK (closes_at > opens_at)
);

CREATE TABLE staff (
    staff_id     SERIAL PRIMARY KEY,
    role_id      SMALLINT NOT NULL REFERENCES roles(role_id),
    branch_id    INT REFERENCES branches(branch_id),
    first_name   VARCHAR(60)  NOT NULL,
    last_name    VARCHAR(60)  NOT NULL,
    email        VARCHAR(120) NOT NULL UNIQUE,
    login        VARCHAR(50)  NOT NULL UNIQUE,
    hired_at     DATE NOT NULL DEFAULT CURRENT_DATE,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE membership_plans (
    plan_id          SERIAL PRIMARY KEY,
    name             VARCHAR(80) NOT NULL UNIQUE,
    max_loans        SMALLINT NOT NULL CHECK (max_loans > 0),
    loan_days        SMALLINT NOT NULL CHECK (loan_days > 0),
    daily_fine       NUMERIC(8,2) NOT NULL CHECK (daily_fine >= 0),
    monthly_price    NUMERIC(10,2) NOT NULL CHECK (monthly_price >= 0),
    service_discount NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (service_discount BETWEEN 0 AND 100),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by       INT REFERENCES staff(staff_id)
);

CREATE TABLE members (
    member_id     SERIAL PRIMARY KEY,
    card_number   VARCHAR(20)  NOT NULL UNIQUE,
    first_name    VARCHAR(60)  NOT NULL,
    last_name     VARCHAR(60)  NOT NULL,
    birth_date    DATE,
    email         VARCHAR(120) NOT NULL,
    phone         VARCHAR(20),
    address       VARCHAR(255),
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by    INT REFERENCES staff(staff_id),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by    INT REFERENCES staff(staff_id),
    is_deleted    BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at    TIMESTAMPTZ,
    deleted_by    INT REFERENCES staff(staff_id),
    CONSTRAINT ck_members_email CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    CONSTRAINT ck_members_soft_delete CHECK ((is_deleted AND deleted_at IS NOT NULL) OR (NOT is_deleted AND deleted_at IS NULL))
);

CREATE TABLE memberships (
    membership_id SERIAL PRIMARY KEY,
    member_id     INT NOT NULL REFERENCES members(member_id),
    plan_id       INT NOT NULL REFERENCES membership_plans(plan_id),
    start_date    DATE NOT NULL,
    end_date      DATE NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_memberships_period CHECK (end_date > start_date),
    CONSTRAINT ex_memberships_overlap EXCLUDE USING gist (member_id WITH =, daterange(start_date, end_date, '[)') WITH &&)
);

CREATE TABLE authors (
    author_id   SERIAL PRIMARY KEY,
    first_name  VARCHAR(60) NOT NULL,
    last_name   VARCHAR(60) NOT NULL,
    birth_year  SMALLINT,
    country     VARCHAR(60),
    biography   TEXT,
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at  TIMESTAMPTZ,
    deleted_by  INT REFERENCES staff(staff_id)
);

CREATE TABLE publishers (
    publisher_id SERIAL PRIMARY KEY,
    name         VARCHAR(150) NOT NULL UNIQUE,
    city         VARCHAR(80),
    website      VARCHAR(200)
);

CREATE TABLE genres (
    genre_id        SERIAL PRIMARY KEY,
    name            VARCHAR(80) NOT NULL UNIQUE,
    parent_genre_id INT REFERENCES genres(genre_id)
);

CREATE TABLE books (
    book_id        SERIAL PRIMARY KEY,
    isbn           VARCHAR(17) NOT NULL,
    title          VARCHAR(255) NOT NULL,
    publisher_id   INT REFERENCES publishers(publisher_id),
    publish_year   SMALLINT CHECK (publish_year BETWEEN 1450 AND 2100),
    language       VARCHAR(30) NOT NULL DEFAULT 'uk',
    pages          INT CHECK (pages > 0),
    description    TEXT,
    search_vector  TSVECTOR GENERATED ALWAYS AS (
                       setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
                       setweight(to_tsvector('simple', coalesce(description, '')), 'B')
                   ) STORED,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by     INT REFERENCES staff(staff_id),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by     INT REFERENCES staff(staff_id),
    is_deleted     BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ,
    deleted_by     INT REFERENCES staff(staff_id)
);

CREATE TABLE book_authors (
    book_id     INT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
    author_id   INT NOT NULL REFERENCES authors(author_id),
    author_order SMALLINT NOT NULL DEFAULT 1,
    PRIMARY KEY (book_id, author_id)
);

CREATE TABLE book_genres (
    book_id   INT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
    genre_id  INT NOT NULL REFERENCES genres(genre_id),
    PRIMARY KEY (book_id, genre_id)
);

CREATE TABLE book_copies (
    copy_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    branch_id      INT NOT NULL REFERENCES branches(branch_id),
    inventory_code VARCHAR(30) NOT NULL UNIQUE,
    status         copy_status NOT NULL DEFAULT 'available',
    shelf          VARCHAR(20),
    acquired_at    DATE NOT NULL DEFAULT CURRENT_DATE,
    price          NUMERIC(10,2) CHECK (price >= 0),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by     INT REFERENCES staff(staff_id),
    is_deleted     BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at     TIMESTAMPTZ,
    deleted_by     INT REFERENCES staff(staff_id)
);

CREATE TABLE loans (
    loan_id      SERIAL PRIMARY KEY,
    copy_id      INT NOT NULL REFERENCES book_copies(copy_id),
    member_id    INT NOT NULL REFERENCES members(member_id),
    issued_by    INT NOT NULL REFERENCES staff(staff_id),
    loan_date    TIMESTAMPTZ NOT NULL DEFAULT now(),
    due_date     DATE NOT NULL,
    return_date  TIMESTAMPTZ,
    received_by  INT REFERENCES staff(staff_id),
    extensions   SMALLINT NOT NULL DEFAULT 0 CHECK (extensions BETWEEN 0 AND 2),
    status       loan_status NOT NULL DEFAULT 'active',
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by   INT REFERENCES staff(staff_id),
    CONSTRAINT ck_loans_dates CHECK (due_date >= loan_date::date),
    CONSTRAINT ck_loans_return CHECK (return_date IS NULL OR return_date >= loan_date)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    member_id      INT NOT NULL REFERENCES members(member_id),
    branch_id      INT NOT NULL REFERENCES branches(branch_id),
    reserved_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at     TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '7 days',
    status         reservation_status NOT NULL DEFAULT 'pending'
);

CREATE TABLE fines (
    fine_id    SERIAL PRIMARY KEY,
    loan_id    INT REFERENCES loans(loan_id),
    member_id  INT NOT NULL REFERENCES members(member_id),
    amount     NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    reason     VARCHAR(255) NOT NULL,
    issued_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    status     fine_status NOT NULL DEFAULT 'unpaid',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by INT REFERENCES staff(staff_id)
);

CREATE TABLE additional_services (
    service_id   SERIAL PRIMARY KEY,
    code         VARCHAR(30) NOT NULL UNIQUE,
    name         VARCHAR(120) NOT NULL,
    unit         VARCHAR(30) NOT NULL,
    unit_price   NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by   INT REFERENCES staff(staff_id),
    is_deleted   BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at   TIMESTAMPTZ,
    deleted_by   INT REFERENCES staff(staff_id)
);

CREATE TABLE service_orders (
    order_id     SERIAL PRIMARY KEY,
    member_id    INT NOT NULL REFERENCES members(member_id),
    service_id   INT NOT NULL REFERENCES additional_services(service_id),
    branch_id    INT NOT NULL REFERENCES branches(branch_id),
    quantity     NUMERIC(8,2) NOT NULL CHECK (quantity > 0),
    unit_price   NUMERIC(10,2) NOT NULL,
    discount     NUMERIC(5,2) NOT NULL DEFAULT 0,
    total_price  NUMERIC(12,2) GENERATED ALWAYS AS (round(quantity * unit_price * (1 - discount / 100), 2)) STORED,
    status       order_status NOT NULL DEFAULT 'new',
    ordered_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    handled_by   INT REFERENCES staff(staff_id),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by   INT REFERENCES staff(staff_id)
);

CREATE TABLE rooms (
    room_id        SERIAL PRIMARY KEY,
    branch_id      INT NOT NULL REFERENCES branches(branch_id),
    name           VARCHAR(80) NOT NULL,
    capacity       SMALLINT NOT NULL CHECK (capacity > 0),
    hourly_rate    NUMERIC(10,2) NOT NULL CHECK (hourly_rate >= 0),
    has_projector  BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (branch_id, name)
);

CREATE TABLE room_bookings (
    booking_id  SERIAL PRIMARY KEY,
    room_id     INT NOT NULL REFERENCES rooms(room_id),
    member_id   INT NOT NULL REFERENCES members(member_id),
    period      TSTZRANGE NOT NULL,
    purpose     VARCHAR(200),
    is_cancelled BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by  INT REFERENCES staff(staff_id),
    CONSTRAINT ck_room_bookings_period CHECK (NOT isempty(period) AND upper(period) - lower(period) <= INTERVAL '8 hours'),
    CONSTRAINT ex_room_bookings_overlap EXCLUDE USING gist (room_id WITH =, period WITH &&) WHERE (NOT is_cancelled)
);

CREATE TABLE events (
    event_id     SERIAL PRIMARY KEY,
    branch_id    INT NOT NULL REFERENCES branches(branch_id),
    room_id      INT REFERENCES rooms(room_id),
    title        VARCHAR(200) NOT NULL,
    description  TEXT,
    starts_at    TIMESTAMPTZ NOT NULL,
    ends_at      TIMESTAMPTZ NOT NULL,
    max_participants SMALLINT NOT NULL CHECK (max_participants > 0),
    ticket_price NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (ticket_price >= 0),
    organizer_id INT REFERENCES staff(staff_id),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_by   INT REFERENCES staff(staff_id),
    is_deleted   BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at   TIMESTAMPTZ,
    deleted_by   INT REFERENCES staff(staff_id),
    CONSTRAINT ck_events_time CHECK (ends_at > starts_at)
);

CREATE TABLE event_registrations (
    registration_id SERIAL PRIMARY KEY,
    event_id        INT NOT NULL REFERENCES events(event_id),
    member_id       INT NOT NULL REFERENCES members(member_id),
    registered_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    attended        BOOLEAN,
    UNIQUE (event_id, member_id)
);

CREATE TABLE payments (
    payment_id        SERIAL PRIMARY KEY,
    member_id         INT NOT NULL REFERENCES members(member_id),
    amount            NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    method            payment_method NOT NULL,
    paid_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    received_by       INT REFERENCES staff(staff_id),
    fine_id           INT REFERENCES fines(fine_id),
    order_id          INT REFERENCES service_orders(order_id),
    membership_id     INT REFERENCES memberships(membership_id),
    booking_id        INT REFERENCES room_bookings(booking_id),
    registration_id   INT REFERENCES event_registrations(registration_id),
    CONSTRAINT ck_payments_target CHECK (num_nonnulls(fine_id, order_id, membership_id, booking_id, registration_id) = 1)
);

CREATE TABLE book_reviews (
    review_id   SERIAL PRIMARY KEY,
    book_id     INT NOT NULL REFERENCES books(book_id),
    member_id   INT NOT NULL REFERENCES members(member_id),
    rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment     TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    is_deleted  BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at  TIMESTAMPTZ,
    deleted_by  INT REFERENCES staff(staff_id),
    UNIQUE (book_id, member_id)
);

CREATE TABLE audit_log (
    audit_id    BIGSERIAL PRIMARY KEY,
    table_name  VARCHAR(63) NOT NULL,
    record_id   INT NOT NULL,
    operation   CHAR(1) NOT NULL CHECK (operation IN ('I', 'U', 'D')),
    old_data    JSONB,
    new_data    JSONB,
    changed_by  INT REFERENCES staff(staff_id),
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
