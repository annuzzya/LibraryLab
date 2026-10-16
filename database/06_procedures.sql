SET search_path TO library, public;

CREATE OR REPLACE FUNCTION fn_require_staff()
RETURNS INT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_staff INT := fn_current_staff_id();
BEGIN
    IF v_staff IS NULL THEN
        RAISE EXCEPTION 'Не визначено працівника для поточної сесії' USING ERRCODE = '28000';
    END IF;
    RETURN v_staff;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_set_session_staff(p_staff_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM staff WHERE staff_id = p_staff_id AND is_active) THEN
        RAISE EXCEPTION 'Працівник % не існує або неактивний', p_staff_id USING ERRCODE = '28000';
    END IF;
    PERFORM set_config('app.current_staff_id', p_staff_id::TEXT, true);
END;
$$;

CREATE OR REPLACE PROCEDURE sp_member_register(
    p_first_name  VARCHAR,
    p_last_name   VARCHAR,
    p_email       VARCHAR,
    p_phone       VARCHAR,
    p_birth_date  DATE,
    p_address     VARCHAR,
    INOUT p_member_id   INT DEFAULT NULL,
    INOUT p_card_number VARCHAR DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_require_staff();

    IF EXISTS (SELECT 1 FROM members WHERE lower(email) = lower(p_email) AND NOT is_deleted) THEN
        RAISE EXCEPTION 'Читач з email % вже зареєстрований', p_email USING ERRCODE = '23505';
    END IF;

    p_member_id := nextval(pg_get_serial_sequence('library.members', 'member_id'));
    p_card_number := fn_generate_card_number(p_member_id);

    INSERT INTO members (member_id, card_number, first_name, last_name, email, phone, birth_date, address)
    VALUES (p_member_id, p_card_number, trim(p_first_name), trim(p_last_name), lower(trim(p_email)), p_phone, p_birth_date, p_address);
END;
$$;

CREATE OR REPLACE PROCEDURE sp_member_update(
    p_member_id  INT,
    p_first_name VARCHAR,
    p_last_name  VARCHAR,
    p_email      VARCHAR,
    p_phone      VARCHAR,
    p_address    VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_require_staff();

    UPDATE members
    SET first_name = trim(p_first_name),
        last_name  = trim(p_last_name),
        email      = lower(trim(p_email)),
        phone      = p_phone,
        address    = p_address
    WHERE member_id = p_member_id
      AND NOT is_deleted;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Читача % не знайдено', p_member_id USING ERRCODE = 'P0002';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_member_soft_delete(p_member_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_require_staff();

    IF fn_active_loans_count(p_member_id) > 0 THEN
        RAISE EXCEPTION 'Читач % має неповернені книги', p_member_id USING ERRCODE = 'P0001';
    END IF;
    IF fn_member_debt(p_member_id) > 0 THEN
        RAISE EXCEPTION 'Читач % має непогашені штрафи', p_member_id USING ERRCODE = 'P0001';
    END IF;

    UPDATE reservations SET status = 'cancelled'
    WHERE member_id = p_member_id AND status IN ('pending', 'ready');

    DELETE FROM members WHERE member_id = p_member_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_member_restore(p_member_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_require_staff();

    UPDATE members
    SET is_deleted = FALSE, deleted_at = NULL, deleted_by = NULL
    WHERE member_id = p_member_id AND is_deleted;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Видаленого читача % не знайдено', p_member_id USING ERRCODE = 'P0002';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_membership_purchase(
    p_member_id INT,
    p_plan_id   INT,
    p_months    INT,
    p_method    payment_method,
    INOUT p_membership_id INT DEFAULT NULL,
    INOUT p_end_date      DATE DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_staff INT := fn_require_staff();
    v_start DATE;
    v_price NUMERIC(10,2);
BEGIN
    IF p_months NOT BETWEEN 1 AND 24 THEN
        RAISE EXCEPTION 'Некоректний термін абонемента: %', p_months USING ERRCODE = '22023';
    END IF;

    SELECT monthly_price INTO v_price FROM membership_plans WHERE plan_id = p_plan_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Тарифний план % не існує', p_plan_id USING ERRCODE = 'P0002';
    END IF;

    SELECT greatest(coalesce(max(end_date), CURRENT_DATE), CURRENT_DATE) INTO v_start
    FROM memberships WHERE member_id = p_member_id;

    p_end_date := (v_start + make_interval(months => p_months))::DATE;

    INSERT INTO memberships (member_id, plan_id, start_date, end_date)
    VALUES (p_member_id, p_plan_id, v_start, p_end_date)
    RETURNING membership_id INTO p_membership_id;

    IF v_price * p_months > 0 THEN
        INSERT INTO payments (member_id, amount, method, received_by, membership_id)
        VALUES (p_member_id, v_price * p_months, p_method, v_staff, p_membership_id);
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_book_create(
    p_isbn         VARCHAR,
    p_title        VARCHAR,
    p_publisher_id INT,
    p_publish_year SMALLINT,
    p_language     VARCHAR,
    p_pages        INT,
    p_description  TEXT,
    p_author_ids   INT[],
    p_genre_ids    INT[],
    INOUT p_book_id INT DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_require_staff();

    IF coalesce(cardinality(p_author_ids), 0) = 0 THEN
        RAISE EXCEPTION 'Книга повинна мати хоча б одного автора' USING ERRCODE = '22023';
    END IF;

    INSERT INTO books (isbn, title, publisher_id, publish_year, language, pages, description)
    VALUES (replace(p_isbn, '-', ''), p_title, p_publisher_id, p_publish_year, coalesce(p_language, 'uk'), p_pages, p_description)
    RETURNING book_id INTO p_book_id;

    INSERT INTO book_authors (book_id, author_id, author_order)
    SELECT p_book_id, a.id, a.ord
    FROM unnest(p_author_ids) WITH ORDINALITY AS a(id, ord);

    INSERT INTO book_genres (book_id, genre_id)
    SELECT DISTINCT p_book_id, g
    FROM unnest(coalesce(p_genre_ids, ARRAY[]::INT[])) AS g;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_book_update(
    p_book_id      INT,
    p_title        VARCHAR,
    p_publisher_id INT,
    p_publish_year SMALLINT,
    p_pages        INT,
    p_description  TEXT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_require_staff();

    UPDATE books
    SET title = p_title,
        publisher_id = p_publisher_id,
        publish_year = p_publish_year,
        pages = p_pages,
        description = p_description
    WHERE book_id = p_book_id AND NOT is_deleted;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Книгу % не знайдено', p_book_id USING ERRCODE = 'P0002';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_book_soft_delete(p_book_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_require_staff();

    IF EXISTS (
        SELECT 1 FROM book_copies
        WHERE book_id = p_book_id AND status = 'on_loan' AND NOT is_deleted
    ) THEN
        RAISE EXCEPTION 'Неможливо видалити книгу %: є видані примірники', p_book_id USING ERRCODE = 'P0001';
    END IF;

    UPDATE reservations SET status = 'cancelled'
    WHERE book_id = p_book_id AND status IN ('pending', 'ready');

    UPDATE book_copies SET status = 'written_off' WHERE book_id = p_book_id AND NOT is_deleted;
    DELETE FROM book_copies WHERE book_id = p_book_id;
    DELETE FROM books WHERE book_id = p_book_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_copy_add(
    p_book_id        INT,
    p_branch_id      INT,
    p_inventory_code VARCHAR,
    p_shelf          VARCHAR,
    p_price          NUMERIC,
    INOUT p_copy_id  INT DEFAULT NULL)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_require_staff();

    IF NOT EXISTS (SELECT 1 FROM books WHERE book_id = p_book_id AND NOT is_deleted) THEN
        RAISE EXCEPTION 'Книгу % не знайдено', p_book_id USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO book_copies (book_id, branch_id, inventory_code, shelf, price)
    VALUES (p_book_id, p_branch_id, p_inventory_code, p_shelf, p_price)
    RETURNING copy_id INTO p_copy_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_copy_write_off(p_copy_id INT)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_require_staff();

    IF EXISTS (SELECT 1 FROM loans WHERE copy_id = p_copy_id AND return_date IS NULL) THEN
        RAISE EXCEPTION 'Примірник % зараз виданий', p_copy_id USING ERRCODE = 'P0001';
    END IF;

    UPDATE book_copies SET status = 'written_off' WHERE copy_id = p_copy_id;
    DELETE FROM book_copies WHERE copy_id = p_copy_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_loan_issue(
    p_member_id INT,
    p_copy_id   INT,
    INOUT p_loan_id  INT DEFAULT NULL,
    INOUT p_due_date DATE DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_staff INT := fn_require_staff();
    v_days  SMALLINT;
BEGIN
    IF NOT fn_member_can_borrow(p_member_id) THEN
        RAISE EXCEPTION 'Читач % не може отримати книгу: немає дійсного абонемента, перевищено ліміт, є борг або прострочення', p_member_id
            USING ERRCODE = 'P0001';
    END IF;

    SELECT loan_days INTO v_days
    FROM membership_plans
    WHERE plan_id = fn_member_plan_id(p_member_id);

    p_due_date := CURRENT_DATE + v_days;

    INSERT INTO loans (copy_id, member_id, issued_by, due_date)
    VALUES (p_copy_id, p_member_id, v_staff, p_due_date)
    RETURNING loan_id INTO p_loan_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_loan_return(
    p_loan_id INT,
    INOUT p_fine_id     INT DEFAULT NULL,
    INOUT p_fine_amount NUMERIC DEFAULT 0)
LANGUAGE plpgsql
AS $$
DECLARE
    v_staff     INT := fn_require_staff();
    v_member_id INT;
    v_due       DATE;
BEGIN
    SELECT member_id, due_date INTO v_member_id, v_due
    FROM loans
    WHERE loan_id = p_loan_id AND return_date IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активну позику % не знайдено', p_loan_id USING ERRCODE = 'P0002';
    END IF;

    UPDATE loans
    SET return_date = now(),
        received_by = v_staff,
        status = 'returned'
    WHERE loan_id = p_loan_id;

    p_fine_amount := fn_calc_fine(p_loan_id);
    p_fine_id := NULL;

    IF p_fine_amount > 0 THEN
        INSERT INTO fines (loan_id, member_id, amount, reason)
        VALUES (p_loan_id, v_member_id, p_fine_amount,
                format('Прострочення повернення на %s дн.', CURRENT_DATE - v_due))
        RETURNING fine_id INTO p_fine_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_loan_extend(
    p_loan_id INT,
    p_days    INT DEFAULT 7,
    INOUT p_new_due_date DATE DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INT;
BEGIN
    PERFORM fn_require_staff();

    SELECT c.book_id INTO v_book_id
    FROM loans l JOIN book_copies c ON c.copy_id = l.copy_id
    WHERE l.loan_id = p_loan_id AND l.return_date IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активну позику % не знайдено', p_loan_id USING ERRCODE = 'P0002';
    END IF;

    IF EXISTS (SELECT 1 FROM reservations WHERE book_id = v_book_id AND status = 'pending') THEN
        RAISE EXCEPTION 'Продовження неможливе: книгу очікують інші читачі' USING ERRCODE = 'P0001';
    END IF;

    UPDATE loans
    SET due_date = greatest(due_date, CURRENT_DATE) + p_days,
        extensions = extensions + 1
    WHERE loan_id = p_loan_id
    RETURNING due_date INTO p_new_due_date;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_mark_overdue_loans(INOUT p_affected INT DEFAULT 0)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE loans
    SET status = 'overdue'
    WHERE return_date IS NULL
      AND status = 'active'
      AND due_date < CURRENT_DATE;
    GET DIAGNOSTICS p_affected = ROW_COUNT;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_reservation_create(
    p_member_id INT,
    p_book_id   INT,
    p_branch_id INT,
    INOUT p_reservation_id INT DEFAULT NULL,
    INOUT p_status VARCHAR DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_copy_id INT;
BEGIN
    PERFORM fn_require_staff();

    SELECT copy_id INTO v_copy_id
    FROM book_copies
    WHERE book_id = p_book_id AND branch_id = p_branch_id
      AND status = 'available' AND NOT is_deleted
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    INSERT INTO reservations (book_id, member_id, branch_id, status, expires_at)
    VALUES (p_book_id, p_member_id, p_branch_id,
            CASE WHEN v_copy_id IS NULL THEN 'pending' ELSE 'ready' END::reservation_status,
            now() + CASE WHEN v_copy_id IS NULL THEN INTERVAL '30 days' ELSE INTERVAL '3 days' END)
    RETURNING reservation_id, status::TEXT INTO p_reservation_id, p_status;

    IF v_copy_id IS NOT NULL THEN
        UPDATE book_copies SET status = 'reserved' WHERE copy_id = v_copy_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_reservation_cancel(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id   INT;
    v_branch_id INT;
    v_status    reservation_status;
    v_copy_id   INT;
    v_next_id   INT;
BEGIN
    PERFORM fn_require_staff();

    SELECT book_id, branch_id, status INTO v_book_id, v_branch_id, v_status
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF v_status NOT IN ('pending', 'ready') THEN
        RAISE EXCEPTION 'Резервування % вже закрите', p_reservation_id USING ERRCODE = 'P0001';
    END IF;

    UPDATE reservations SET status = 'cancelled' WHERE reservation_id = p_reservation_id;

    IF v_status = 'ready' THEN
        SELECT copy_id INTO v_copy_id
        FROM book_copies
        WHERE book_id = v_book_id AND branch_id = v_branch_id AND status = 'reserved'
        LIMIT 1;

        SELECT reservation_id INTO v_next_id
        FROM reservations
        WHERE book_id = v_book_id AND branch_id = v_branch_id AND status = 'pending'
        ORDER BY reserved_at LIMIT 1;

        IF v_next_id IS NOT NULL THEN
            UPDATE reservations SET status = 'ready', expires_at = now() + INTERVAL '3 days'
            WHERE reservation_id = v_next_id;
        ELSIF v_copy_id IS NOT NULL THEN
            UPDATE book_copies SET status = 'available' WHERE copy_id = v_copy_id;
        END IF;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_fine_pay(
    p_fine_id INT,
    p_method  payment_method,
    INOUT p_payment_id INT DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_staff     INT := fn_require_staff();
    v_member_id INT;
    v_amount    NUMERIC(10,2);
BEGIN
    SELECT member_id, amount INTO v_member_id, v_amount
    FROM fines
    WHERE fine_id = p_fine_id AND status = 'unpaid'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Неоплачений штраф % не знайдено', p_fine_id USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO payments (member_id, amount, method, received_by, fine_id)
    VALUES (v_member_id, v_amount, p_method, v_staff, p_fine_id)
    RETURNING payment_id INTO p_payment_id;

    UPDATE fines SET status = 'paid' WHERE fine_id = p_fine_id;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_fine_waive(p_fine_id INT, p_comment VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_require_staff();

    UPDATE fines
    SET status = 'waived',
        reason = reason || ' | Списано: ' || p_comment
    WHERE fine_id = p_fine_id AND status = 'unpaid';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Неоплачений штраф % не знайдено', p_fine_id USING ERRCODE = 'P0002';
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_service_order_create(
    p_member_id  INT,
    p_service_id INT,
    p_branch_id  INT,
    p_quantity   NUMERIC,
    INOUT p_order_id INT DEFAULT NULL,
    INOUT p_total    NUMERIC DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_price NUMERIC(10,2);
BEGIN
    PERFORM fn_require_staff();

    SELECT unit_price INTO v_price
    FROM additional_services
    WHERE service_id = p_service_id AND is_active AND NOT is_deleted;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Послуга % недоступна', p_service_id USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO service_orders (member_id, service_id, branch_id, quantity, unit_price, discount)
    VALUES (p_member_id, p_service_id, p_branch_id, p_quantity, v_price, fn_member_service_discount(p_member_id))
    RETURNING order_id, total_price INTO p_order_id, p_total;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_service_order_complete(
    p_order_id INT,
    p_method   payment_method,
    INOUT p_payment_id INT DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_staff     INT := fn_require_staff();
    v_member_id INT;
    v_total     NUMERIC(12,2);
BEGIN
    UPDATE service_orders
    SET status = 'completed', handled_by = v_staff
    WHERE order_id = p_order_id AND status IN ('new', 'in_progress')
    RETURNING member_id, total_price INTO v_member_id, v_total;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Замовлення % не знайдено або вже закрите', p_order_id USING ERRCODE = 'P0002';
    END IF;

    IF v_total > 0 THEN
        INSERT INTO payments (member_id, amount, method, received_by, order_id)
        VALUES (v_member_id, v_total, p_method, v_staff, p_order_id)
        RETURNING payment_id INTO p_payment_id;
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_room_booking_create(
    p_room_id   INT,
    p_member_id INT,
    p_starts_at TIMESTAMPTZ,
    p_ends_at   TIMESTAMPTZ,
    p_purpose   VARCHAR,
    p_method    payment_method,
    INOUT p_booking_id INT DEFAULT NULL,
    INOUT p_price      NUMERIC DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_staff  INT := fn_require_staff();
    v_rate   NUMERIC(10,2);
    v_opens  TIME;
    v_closes TIME;
BEGIN
    SELECT r.hourly_rate, b.opens_at, b.closes_at
    INTO v_rate, v_opens, v_closes
    FROM rooms r JOIN branches b ON b.branch_id = r.branch_id
    WHERE r.room_id = p_room_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Приміщення % не існує', p_room_id USING ERRCODE = 'P0002';
    END IF;

    IF p_starts_at::TIME < v_opens OR p_ends_at::TIME > v_closes OR p_starts_at::DATE <> p_ends_at::DATE THEN
        RAISE EXCEPTION 'Бронювання поза робочими годинами філії (% - %)', v_opens, v_closes USING ERRCODE = 'P0001';
    END IF;

    BEGIN
        INSERT INTO room_bookings (room_id, member_id, period, purpose)
        VALUES (p_room_id, p_member_id, tstzrange(p_starts_at, p_ends_at, '[)'), p_purpose)
        RETURNING booking_id INTO p_booking_id;
    EXCEPTION WHEN exclusion_violation THEN
        RAISE EXCEPTION 'Приміщення % вже заброньоване на цей час', p_room_id USING ERRCODE = 'P0001';
    END;

    p_price := round(v_rate * extract(EPOCH FROM (p_ends_at - p_starts_at)) / 3600
                     * (1 - fn_member_service_discount(p_member_id) / 100), 2);

    IF p_price > 0 THEN
        INSERT INTO payments (member_id, amount, method, received_by, booking_id)
        VALUES (p_member_id, p_price, p_method, v_staff, p_booking_id);
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_event_register(
    p_event_id  INT,
    p_member_id INT,
    p_method    payment_method,
    INOUT p_registration_id INT DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_staff INT := fn_require_staff();
    v_price NUMERIC(10,2);
BEGIN
    INSERT INTO event_registrations (event_id, member_id)
    VALUES (p_event_id, p_member_id)
    RETURNING registration_id INTO p_registration_id;

    SELECT ticket_price INTO v_price FROM events WHERE event_id = p_event_id;

    IF v_price > 0 THEN
        INSERT INTO payments (member_id, amount, method, received_by, registration_id)
        VALUES (p_member_id, v_price, p_method, v_staff, p_registration_id);
    END IF;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_refresh_reports()
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_matviews WHERE schemaname = 'library' AND matviewname = 'mv_monthly_report' AND ispopulated) THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_report;
    ELSE
        REFRESH MATERIALIZED VIEW mv_monthly_report;
    END IF;
END;
$$;
