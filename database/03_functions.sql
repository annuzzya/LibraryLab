SET search_path TO library, public;

CREATE OR REPLACE FUNCTION fn_current_staff_id()
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT nullif(current_setting('app.current_staff_id', true), '')::INT;
$$;

CREATE OR REPLACE FUNCTION fn_member_plan_id(p_member_id INT, p_on_date DATE DEFAULT CURRENT_DATE)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT ms.plan_id
    FROM memberships ms
    WHERE ms.member_id = p_member_id
      AND p_on_date >= ms.start_date
      AND p_on_date < ms.end_date
    ORDER BY ms.end_date DESC
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_active_loans_count(p_member_id INT)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT count(*)::INT
    FROM loans
    WHERE member_id = p_member_id
      AND return_date IS NULL;
$$;

CREATE OR REPLACE FUNCTION fn_member_debt(p_member_id INT)
RETURNS NUMERIC(12,2)
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(sum(amount), 0)::NUMERIC(12,2)
    FROM fines
    WHERE member_id = p_member_id
      AND status = 'unpaid';
$$;

CREATE OR REPLACE FUNCTION fn_available_copies(p_book_id INT, p_branch_id INT DEFAULT NULL)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
    SELECT count(*)::INT
    FROM book_copies
    WHERE book_id = p_book_id
      AND status = 'available'
      AND NOT is_deleted
      AND (p_branch_id IS NULL OR branch_id = p_branch_id);
$$;

CREATE OR REPLACE FUNCTION fn_calc_fine(p_loan_id INT, p_on_date DATE DEFAULT CURRENT_DATE)
RETURNS NUMERIC(10,2)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_due        DATE;
    v_returned   DATE;
    v_member_id  INT;
    v_loan_date  DATE;
    v_rate       NUMERIC(8,2);
    v_price      NUMERIC(10,2);
    v_days       INT;
BEGIN
    SELECT l.due_date, l.return_date::DATE, l.member_id, l.loan_date::DATE, c.price
    INTO v_due, v_returned, v_member_id, v_loan_date, v_price
    FROM loans l
    JOIN book_copies c ON c.copy_id = l.copy_id
    WHERE l.loan_id = p_loan_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Позику % не знайдено', p_loan_id USING ERRCODE = 'P0002';
    END IF;

    v_days := coalesce(v_returned, p_on_date) - v_due;
    IF v_days <= 0 THEN
        RETURN 0;
    END IF;

    SELECT mp.daily_fine INTO v_rate
    FROM membership_plans mp
    WHERE mp.plan_id = fn_member_plan_id(v_member_id, v_loan_date);

    v_rate := coalesce(v_rate, 5.00);

    RETURN CASE
        WHEN v_price IS NOT NULL THEN least(v_days * v_rate, v_price * 2)
        ELSE v_days * v_rate
    END;
END;
$$;

CREATE OR REPLACE FUNCTION fn_member_can_borrow(p_member_id INT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_plan_id   INT;
    v_max_loans INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM members WHERE member_id = p_member_id AND NOT is_deleted) THEN
        RETURN FALSE;
    END IF;

    v_plan_id := fn_member_plan_id(p_member_id);
    IF v_plan_id IS NULL THEN
        RETURN FALSE;
    END IF;

    SELECT max_loans INTO v_max_loans FROM membership_plans WHERE plan_id = v_plan_id;

    RETURN fn_active_loans_count(p_member_id) < v_max_loans
       AND fn_member_debt(p_member_id) = 0
       AND NOT EXISTS (
           SELECT 1 FROM loans
           WHERE member_id = p_member_id
             AND return_date IS NULL
             AND due_date < CURRENT_DATE
       );
END;
$$;

CREATE OR REPLACE FUNCTION fn_generate_card_number(p_member_id INT)
RETURNS VARCHAR(20)
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT 'LIB-' || lpad(p_member_id::TEXT, 8, '0');
$$;

CREATE OR REPLACE FUNCTION fn_search_books(p_query TEXT, p_limit INT DEFAULT 20)
RETURNS TABLE (
    book_id          INT,
    title            VARCHAR,
    authors          TEXT,
    publish_year     SMALLINT,
    available_copies INT,
    relevance        REAL
)
LANGUAGE sql
STABLE
SET search_path = library, public
AS $$
    SELECT b.book_id,
           b.title,
           string_agg(a.first_name || ' ' || a.last_name, ', ' ORDER BY ba.author_order),
           b.publish_year,
           fn_available_copies(b.book_id),
           greatest(ts_rank(b.search_vector, plainto_tsquery('simple', p_query)),
                    similarity(b.title, p_query)) AS relevance
    FROM books b
    LEFT JOIN book_authors ba ON ba.book_id = b.book_id
    LEFT JOIN authors a ON a.author_id = ba.author_id
    WHERE NOT b.is_deleted
      AND (b.search_vector @@ plainto_tsquery('simple', p_query)
           OR b.title % p_query
           OR a.last_name % p_query)
    GROUP BY b.book_id
    ORDER BY relevance DESC
    LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION fn_member_service_discount(p_member_id INT)
RETURNS NUMERIC(5,2)
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce((
        SELECT service_discount
        FROM membership_plans
        WHERE plan_id = fn_member_plan_id(p_member_id)
    ), 0);
$$;
