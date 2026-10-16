SET search_path TO library, public;

CREATE OR REPLACE VIEW v_members AS
SELECT m.member_id,
       m.card_number,
       m.first_name,
       m.last_name,
       m.first_name || ' ' || m.last_name AS full_name,
       m.birth_date,
       m.email,
       m.phone,
       m.address,
       m.registered_at,
       mp.name AS plan_name,
       ms.end_date AS membership_until,
       fn_active_loans_count(m.member_id) AS active_loans,
       fn_member_debt(m.member_id) AS debt,
       m.updated_at,
       s.login AS updated_by_login
FROM members m
LEFT JOIN LATERAL (
    SELECT x.plan_id, x.end_date
    FROM memberships x
    WHERE x.member_id = m.member_id
      AND CURRENT_DATE >= x.start_date
      AND CURRENT_DATE < x.end_date
    ORDER BY x.end_date DESC
    LIMIT 1
) ms ON TRUE
LEFT JOIN membership_plans mp ON mp.plan_id = ms.plan_id
LEFT JOIN staff s ON s.staff_id = m.updated_by
WHERE NOT m.is_deleted;

CREATE OR REPLACE VIEW v_members_archive AS
SELECT m.member_id,
       m.card_number,
       m.first_name || ' ' || m.last_name AS full_name,
       m.email,
       m.deleted_at,
       s.login AS deleted_by_login
FROM members m
LEFT JOIN staff s ON s.staff_id = m.deleted_by
WHERE m.is_deleted;

CREATE OR REPLACE VIEW v_books_catalog AS
SELECT b.book_id,
       b.isbn,
       b.title,
       p.name AS publisher,
       b.publish_year,
       b.language,
       b.pages,
       b.description,
       coalesce(au.authors, '') AS authors,
       coalesce(gn.genres, '') AS genres,
       coalesce(cp.total_copies, 0) AS total_copies,
       coalesce(cp.available_copies, 0) AS available_copies,
       rv.avg_rating,
       b.updated_at,
       s.login AS updated_by_login
FROM books b
LEFT JOIN publishers p ON p.publisher_id = b.publisher_id
LEFT JOIN LATERAL (
    SELECT string_agg(a.first_name || ' ' || a.last_name, ', ' ORDER BY ba.author_order) AS authors
    FROM book_authors ba
    JOIN authors a ON a.author_id = ba.author_id
    WHERE ba.book_id = b.book_id
) au ON TRUE
LEFT JOIN LATERAL (
    SELECT string_agg(g.name, ', ' ORDER BY g.name) AS genres
    FROM book_genres bg
    JOIN genres g ON g.genre_id = bg.genre_id
    WHERE bg.book_id = b.book_id
) gn ON TRUE
LEFT JOIN LATERAL (
    SELECT count(*)::INT AS total_copies,
           (count(*) FILTER (WHERE c.status = 'available'))::INT AS available_copies
    FROM book_copies c
    WHERE c.book_id = b.book_id AND NOT c.is_deleted
) cp ON TRUE
LEFT JOIN LATERAL (
    SELECT round(avg(r.rating), 2) AS avg_rating
    FROM book_reviews r
    WHERE r.book_id = b.book_id AND NOT r.is_deleted
) rv ON TRUE
LEFT JOIN staff s ON s.staff_id = b.updated_by
WHERE NOT b.is_deleted;

CREATE OR REPLACE VIEW v_book_copies AS
SELECT c.copy_id,
       c.book_id,
       b.title,
       c.branch_id,
       br.name AS branch_name,
       c.inventory_code,
       c.status::TEXT AS status,
       c.shelf,
       c.price,
       c.acquired_at,
       c.updated_at
FROM book_copies c
JOIN books b ON b.book_id = c.book_id
JOIN branches br ON br.branch_id = c.branch_id
WHERE NOT c.is_deleted;

CREATE OR REPLACE VIEW v_loans AS
SELECT l.loan_id,
       l.member_id,
       m.card_number,
       m.first_name || ' ' || m.last_name AS member_name,
       l.copy_id,
       c.inventory_code,
       b.book_id,
       b.title,
       br.name AS branch_name,
       l.loan_date,
       l.due_date,
       l.return_date,
       l.extensions,
       l.status::TEXT AS status,
       greatest(coalesce(l.return_date::DATE, CURRENT_DATE) - l.due_date, 0) AS days_overdue,
       fn_calc_fine(l.loan_id) AS fine_estimate,
       si.login AS issued_by_login,
       sr.login AS received_by_login
FROM loans l
JOIN members m ON m.member_id = l.member_id
JOIN book_copies c ON c.copy_id = l.copy_id
JOIN books b ON b.book_id = c.book_id
JOIN branches br ON br.branch_id = c.branch_id
JOIN staff si ON si.staff_id = l.issued_by
LEFT JOIN staff sr ON sr.staff_id = l.received_by;

CREATE OR REPLACE VIEW v_active_loans AS
SELECT *
FROM v_loans
WHERE return_date IS NULL;

CREATE OR REPLACE VIEW v_overdue_loans AS
SELECT v.*, m.email, m.phone
FROM v_loans v
JOIN members m ON m.member_id = v.member_id
WHERE v.return_date IS NULL
  AND v.due_date < CURRENT_DATE;

CREATE OR REPLACE VIEW v_fines AS
SELECT f.fine_id,
       f.member_id,
       m.first_name || ' ' || m.last_name AS member_name,
       f.loan_id,
       f.amount,
       f.reason,
       f.status::TEXT AS status,
       f.issued_at,
       p.paid_at
FROM fines f
JOIN members m ON m.member_id = f.member_id
LEFT JOIN payments p ON p.fine_id = f.fine_id;

CREATE OR REPLACE VIEW v_member_debts AS
SELECT m.member_id,
       m.card_number,
       m.first_name || ' ' || m.last_name AS member_name,
       m.email,
       count(f.fine_id) AS unpaid_fines,
       sum(f.amount) AS total_debt,
       min(f.issued_at) AS oldest_fine_at
FROM members m
JOIN fines f ON f.member_id = m.member_id AND f.status = 'unpaid'
WHERE NOT m.is_deleted
GROUP BY m.member_id;

CREATE OR REPLACE VIEW v_popular_books AS
SELECT b.book_id,
       b.title,
       count(l.loan_id) AS loans_last_year,
       dense_rank() OVER (ORDER BY count(l.loan_id) DESC) AS popularity_rank
FROM books b
JOIN book_copies c ON c.book_id = b.book_id
JOIN loans l ON l.copy_id = c.copy_id AND l.loan_date >= now() - INTERVAL '1 year'
WHERE NOT b.is_deleted
GROUP BY b.book_id, b.title;

CREATE OR REPLACE VIEW v_branch_statistics AS
SELECT br.branch_id,
       br.name,
       (SELECT count(*) FROM book_copies c WHERE c.branch_id = br.branch_id AND NOT c.is_deleted) AS copies_total,
       (SELECT count(*) FROM book_copies c WHERE c.branch_id = br.branch_id AND c.status = 'on_loan') AS copies_on_loan,
       (SELECT count(*) FROM loans l JOIN book_copies c ON c.copy_id = l.copy_id
         WHERE c.branch_id = br.branch_id AND l.return_date IS NULL AND l.due_date < CURRENT_DATE) AS overdue_loans,
       (SELECT count(*) FROM rooms r WHERE r.branch_id = br.branch_id) AS rooms,
       (SELECT coalesce(sum(o.total_price), 0) FROM service_orders o
         WHERE o.branch_id = br.branch_id AND o.status = 'completed') AS services_revenue
FROM branches br;

CREATE OR REPLACE VIEW v_service_revenue AS
SELECT date_trunc('month', o.ordered_at)::DATE AS month,
       s.code,
       s.name AS service_name,
       count(*) AS orders,
       sum(o.quantity) AS quantity,
       sum(o.total_price) AS revenue
FROM service_orders o
JOIN additional_services s ON s.service_id = o.service_id
WHERE o.status = 'completed'
GROUP BY 1, s.service_id;

CREATE OR REPLACE VIEW v_upcoming_events AS
SELECT e.event_id,
       e.title,
       br.name AS branch_name,
       r.name AS room_name,
       e.starts_at,
       e.ends_at,
       e.ticket_price,
       e.max_participants,
       e.max_participants - count(er.registration_id) AS free_places
FROM events e
JOIN branches br ON br.branch_id = e.branch_id
LEFT JOIN rooms r ON r.room_id = e.room_id
LEFT JOIN event_registrations er ON er.event_id = e.event_id
WHERE NOT e.is_deleted
  AND e.starts_at > now()
GROUP BY e.event_id, br.name, r.name;

CREATE OR REPLACE VIEW v_room_schedule AS
SELECT rb.booking_id,
       r.room_id,
       r.name AS room_name,
       br.name AS branch_name,
       lower(rb.period) AS starts_at,
       upper(rb.period) AS ends_at,
       m.first_name || ' ' || m.last_name AS member_name,
       rb.purpose
FROM room_bookings rb
JOIN rooms r ON r.room_id = rb.room_id
JOIN branches br ON br.branch_id = r.branch_id
JOIN members m ON m.member_id = rb.member_id
WHERE NOT rb.is_cancelled
  AND upper(rb.period) > now();

CREATE OR REPLACE VIEW v_audit_trail AS
SELECT a.audit_id,
       a.table_name,
       a.record_id,
       CASE a.operation WHEN 'I' THEN 'INSERT' WHEN 'U' THEN 'UPDATE' ELSE 'DELETE' END AS operation,
       a.changed_at,
       s.login AS changed_by_login,
       (SELECT jsonb_object_agg(n.key, n.value)
        FROM jsonb_each(a.new_data) n
        WHERE a.old_data IS NULL OR a.old_data -> n.key IS DISTINCT FROM n.value) AS changes
FROM audit_log a
LEFT JOIN staff s ON s.staff_id = a.changed_by;

CREATE MATERIALIZED VIEW mv_monthly_report AS
SELECT date_trunc('month', d.day)::DATE AS month,
       (SELECT count(*) FROM loans l WHERE date_trunc('month', l.loan_date) = date_trunc('month', d.day)) AS loans_issued,
       (SELECT count(*) FROM members m WHERE date_trunc('month', m.registered_at) = date_trunc('month', d.day)) AS new_members,
       (SELECT coalesce(sum(p.amount), 0) FROM payments p WHERE date_trunc('month', p.paid_at) = date_trunc('month', d.day)) AS income,
       (SELECT coalesce(sum(f.amount), 0) FROM fines f WHERE date_trunc('month', f.issued_at) = date_trunc('month', d.day)) AS fines_issued
FROM generate_series(date_trunc('month', now()) - INTERVAL '11 months', date_trunc('month', now()), INTERVAL '1 month') AS d(day)
WITH NO DATA;

CREATE UNIQUE INDEX ux_mv_monthly_report_month ON mv_monthly_report (month);
