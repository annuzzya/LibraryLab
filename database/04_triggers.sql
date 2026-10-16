SET search_path TO library, public;

CREATE OR REPLACE FUNCTION tf_set_modified()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_staff INT := fn_current_staff_id();
BEGIN
    NEW.updated_at := now();
    IF v_staff IS NOT NULL THEN
        NEW.updated_by := v_staff;
    ELSIF TG_OP = 'UPDATE' AND NEW.updated_by IS NOT DISTINCT FROM OLD.updated_by THEN
        NEW.updated_by := NULL;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tf_set_created_by()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.created_by := coalesce(NEW.created_by, fn_current_staff_id());
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tf_soft_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_pk_column TEXT := TG_ARGV[0];
    v_pk_value  INT  := (to_jsonb(OLD) ->> TG_ARGV[0])::INT;
BEGIN
    IF current_setting('app.allow_hard_delete', true) = 'on' THEN
        RETURN OLD;
    END IF;

    EXECUTE format(
        'UPDATE %I.%I SET is_deleted = TRUE, deleted_at = now(), deleted_by = $1 WHERE %I = $2 AND NOT is_deleted',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, v_pk_column)
    USING fn_current_staff_id(), v_pk_value;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION tf_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_old JSONB;
    v_new JSONB;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old := to_jsonb(OLD);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new := to_jsonb(NEW);
    END IF;

    IF TG_OP = 'UPDATE' AND (v_old - 'updated_at') = (v_new - 'updated_at') THEN
        RETURN NULL;
    END IF;

    INSERT INTO audit_log (table_name, record_id, operation, old_data, new_data, changed_by)
    VALUES (TG_TABLE_NAME,
            (coalesce(v_new, v_old) ->> TG_ARGV[0])::INT,
            left(TG_OP, 1),
            v_old,
            v_new,
            fn_current_staff_id());

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION tf_loans_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_status     copy_status;
    v_deleted    BOOLEAN;
    v_book_id    INT;
BEGIN
    SELECT status, is_deleted, book_id
    INTO v_status, v_deleted, v_book_id
    FROM book_copies
    WHERE copy_id = NEW.copy_id
    FOR UPDATE;

    IF v_deleted THEN
        RAISE EXCEPTION 'Примірник % списано', NEW.copy_id USING ERRCODE = 'P0001';
    END IF;

    IF v_status = 'reserved' THEN
        IF NOT EXISTS (
            SELECT 1 FROM reservations
            WHERE book_id = v_book_id
              AND member_id = NEW.member_id
              AND status = 'ready'
        ) THEN
            RAISE EXCEPTION 'Примірник % зарезервовано для іншого читача', NEW.copy_id USING ERRCODE = 'P0001';
        END IF;
    ELSIF v_status <> 'available' THEN
        RAISE EXCEPTION 'Примірник % недоступний (статус: %)', NEW.copy_id, v_status USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (SELECT 1 FROM members WHERE member_id = NEW.member_id AND is_deleted) THEN
        RAISE EXCEPTION 'Читача % видалено', NEW.member_id USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tf_loans_sync_copy_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id        INT;
    v_branch_id      INT;
    v_reservation_id INT;
BEGIN
    SELECT book_id, branch_id INTO v_book_id, v_branch_id
    FROM book_copies WHERE copy_id = NEW.copy_id;

    IF TG_OP = 'INSERT' THEN
        UPDATE book_copies SET status = 'on_loan' WHERE copy_id = NEW.copy_id;

        UPDATE reservations
        SET status = 'fulfilled'
        WHERE book_id = v_book_id
          AND member_id = NEW.member_id
          AND status IN ('pending', 'ready');

        RETURN NULL;
    END IF;

    IF NEW.status = 'lost' AND OLD.status <> 'lost' THEN
        UPDATE book_copies SET status = 'lost' WHERE copy_id = NEW.copy_id;
        RETURN NULL;
    END IF;

    IF OLD.return_date IS NULL AND NEW.return_date IS NOT NULL THEN
        SELECT reservation_id INTO v_reservation_id
        FROM reservations
        WHERE book_id = v_book_id
          AND branch_id = v_branch_id
          AND status = 'pending'
        ORDER BY reserved_at
        LIMIT 1
        FOR UPDATE SKIP LOCKED;

        IF v_reservation_id IS NOT NULL THEN
            UPDATE book_copies SET status = 'reserved' WHERE copy_id = NEW.copy_id;
            UPDATE reservations
            SET status = 'ready', expires_at = now() + INTERVAL '3 days'
            WHERE reservation_id = v_reservation_id;
        ELSE
            UPDATE book_copies SET status = 'available' WHERE copy_id = NEW.copy_id;
        END IF;
    END IF;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION tf_event_registration_check()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_max      SMALLINT;
    v_starts   TIMESTAMPTZ;
    v_deleted  BOOLEAN;
    v_count    INT;
BEGIN
    SELECT max_participants, starts_at, is_deleted
    INTO v_max, v_starts, v_deleted
    FROM events
    WHERE event_id = NEW.event_id
    FOR UPDATE;

    IF v_deleted OR v_starts <= now() THEN
        RAISE EXCEPTION 'Реєстрація на захід % закрита', NEW.event_id USING ERRCODE = 'P0001';
    END IF;

    SELECT count(*) INTO v_count FROM event_registrations WHERE event_id = NEW.event_id;
    IF v_count >= v_max THEN
        RAISE EXCEPTION 'На захід % немає вільних місць', NEW.event_id USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION tf_reservation_check()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM members WHERE member_id = NEW.member_id AND is_deleted) THEN
        RAISE EXCEPTION 'Читача % видалено', NEW.member_id USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM books WHERE book_id = NEW.book_id AND is_deleted) THEN
        RAISE EXCEPTION 'Книгу % видалено з каталогу', NEW.book_id USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_membership_plans_modified BEFORE INSERT OR UPDATE ON membership_plans FOR EACH ROW EXECUTE FUNCTION tf_set_modified();
CREATE TRIGGER trg_members_modified BEFORE INSERT OR UPDATE ON members FOR EACH ROW EXECUTE FUNCTION tf_set_modified();
CREATE TRIGGER trg_books_modified BEFORE INSERT OR UPDATE ON books FOR EACH ROW EXECUTE FUNCTION tf_set_modified();
CREATE TRIGGER trg_book_copies_modified BEFORE INSERT OR UPDATE ON book_copies FOR EACH ROW EXECUTE FUNCTION tf_set_modified();
CREATE TRIGGER trg_loans_modified BEFORE INSERT OR UPDATE ON loans FOR EACH ROW EXECUTE FUNCTION tf_set_modified();
CREATE TRIGGER trg_fines_modified BEFORE INSERT OR UPDATE ON fines FOR EACH ROW EXECUTE FUNCTION tf_set_modified();
CREATE TRIGGER trg_services_modified BEFORE INSERT OR UPDATE ON additional_services FOR EACH ROW EXECUTE FUNCTION tf_set_modified();
CREATE TRIGGER trg_service_orders_modified BEFORE INSERT OR UPDATE ON service_orders FOR EACH ROW EXECUTE FUNCTION tf_set_modified();
CREATE TRIGGER trg_room_bookings_modified BEFORE INSERT OR UPDATE ON room_bookings FOR EACH ROW EXECUTE FUNCTION tf_set_modified();
CREATE TRIGGER trg_events_modified BEFORE INSERT OR UPDATE ON events FOR EACH ROW EXECUTE FUNCTION tf_set_modified();

CREATE TRIGGER trg_members_created_by BEFORE INSERT ON members FOR EACH ROW EXECUTE FUNCTION tf_set_created_by();
CREATE TRIGGER trg_books_created_by BEFORE INSERT ON books FOR EACH ROW EXECUTE FUNCTION tf_set_created_by();

CREATE TRIGGER trg_members_soft_delete BEFORE DELETE ON members FOR EACH ROW EXECUTE FUNCTION tf_soft_delete('member_id');
CREATE TRIGGER trg_books_soft_delete BEFORE DELETE ON books FOR EACH ROW EXECUTE FUNCTION tf_soft_delete('book_id');
CREATE TRIGGER trg_book_copies_soft_delete BEFORE DELETE ON book_copies FOR EACH ROW EXECUTE FUNCTION tf_soft_delete('copy_id');
CREATE TRIGGER trg_authors_soft_delete BEFORE DELETE ON authors FOR EACH ROW EXECUTE FUNCTION tf_soft_delete('author_id');
CREATE TRIGGER trg_services_soft_delete BEFORE DELETE ON additional_services FOR EACH ROW EXECUTE FUNCTION tf_soft_delete('service_id');
CREATE TRIGGER trg_events_soft_delete BEFORE DELETE ON events FOR EACH ROW EXECUTE FUNCTION tf_soft_delete('event_id');
CREATE TRIGGER trg_book_reviews_soft_delete BEFORE DELETE ON book_reviews FOR EACH ROW EXECUTE FUNCTION tf_soft_delete('review_id');

CREATE TRIGGER trg_members_audit AFTER INSERT OR UPDATE OR DELETE ON members FOR EACH ROW EXECUTE FUNCTION tf_audit_log('member_id');
CREATE TRIGGER trg_books_audit AFTER INSERT OR UPDATE OR DELETE ON books FOR EACH ROW EXECUTE FUNCTION tf_audit_log('book_id');
CREATE TRIGGER trg_book_copies_audit AFTER INSERT OR UPDATE OR DELETE ON book_copies FOR EACH ROW EXECUTE FUNCTION tf_audit_log('copy_id');
CREATE TRIGGER trg_loans_audit AFTER INSERT OR UPDATE OR DELETE ON loans FOR EACH ROW EXECUTE FUNCTION tf_audit_log('loan_id');
CREATE TRIGGER trg_fines_audit AFTER INSERT OR UPDATE OR DELETE ON fines FOR EACH ROW EXECUTE FUNCTION tf_audit_log('fine_id');
CREATE TRIGGER trg_membership_plans_audit AFTER INSERT OR UPDATE OR DELETE ON membership_plans FOR EACH ROW EXECUTE FUNCTION tf_audit_log('plan_id');
CREATE TRIGGER trg_services_audit AFTER INSERT OR UPDATE OR DELETE ON additional_services FOR EACH ROW EXECUTE FUNCTION tf_audit_log('service_id');

CREATE TRIGGER trg_loans_before_insert BEFORE INSERT ON loans FOR EACH ROW EXECUTE FUNCTION tf_loans_before_insert();
CREATE TRIGGER trg_loans_sync_copy AFTER INSERT OR UPDATE OF return_date, status ON loans FOR EACH ROW EXECUTE FUNCTION tf_loans_sync_copy_status();
CREATE TRIGGER trg_event_registrations_check BEFORE INSERT ON event_registrations FOR EACH ROW EXECUTE FUNCTION tf_event_registration_check();
CREATE TRIGGER trg_reservations_check BEFORE INSERT ON reservations FOR EACH ROW EXECUTE FUNCTION tf_reservation_check();
