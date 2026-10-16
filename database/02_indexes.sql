SET search_path TO library, public;

CREATE INDEX ix_staff_role ON staff USING btree (role_id);
CREATE INDEX ix_members_name ON members USING btree (last_name, first_name) WHERE NOT is_deleted;
CREATE UNIQUE INDEX ux_members_email_active ON members USING btree (lower(email)) WHERE NOT is_deleted;
CREATE INDEX ix_members_phone_hash ON members USING hash (phone);

CREATE UNIQUE INDEX ux_books_isbn_active ON books USING btree (isbn) WHERE NOT is_deleted;
CREATE INDEX ix_books_title_trgm ON books USING gin (title gin_trgm_ops);
CREATE INDEX ix_books_search ON books USING gin (search_vector);
CREATE INDEX ix_books_publisher ON books USING btree (publisher_id);
CREATE INDEX ix_authors_last_name_trgm ON authors USING gin (last_name gin_trgm_ops);
CREATE INDEX ix_book_authors_author ON book_authors USING btree (author_id);
CREATE INDEX ix_book_genres_genre ON book_genres USING btree (genre_id);

CREATE INDEX ix_copies_book_branch_status ON book_copies USING btree (book_id, branch_id, status) WHERE NOT is_deleted;

CREATE INDEX ix_loans_member_active ON loans USING btree (member_id) WHERE return_date IS NULL;
CREATE INDEX ix_loans_copy ON loans USING btree (copy_id);
CREATE UNIQUE INDEX ux_loans_copy_open ON loans USING btree (copy_id) WHERE return_date IS NULL;
CREATE INDEX ix_loans_due_date ON loans USING btree (due_date) INCLUDE (member_id, copy_id) WHERE return_date IS NULL;
CREATE INDEX ix_loans_loan_date_brin ON loans USING brin (loan_date);

CREATE INDEX ix_reservations_book_status ON reservations USING btree (book_id, status, reserved_at);
CREATE UNIQUE INDEX ux_reservations_open ON reservations USING btree (book_id, member_id) WHERE status IN ('pending', 'ready');

CREATE INDEX ix_fines_member_unpaid ON fines USING btree (member_id) WHERE status = 'unpaid';
CREATE INDEX ix_payments_member ON payments USING btree (member_id, paid_at DESC);
CREATE INDEX ix_payments_paid_at_brin ON payments USING brin (paid_at);

CREATE INDEX ix_service_orders_member ON service_orders USING btree (member_id, ordered_at DESC);
CREATE INDEX ix_room_bookings_period ON room_bookings USING gist (period);
CREATE INDEX ix_events_starts ON events USING btree (starts_at) WHERE NOT is_deleted;

CREATE INDEX ix_audit_log_record ON audit_log USING btree (table_name, record_id);
CREATE INDEX ix_audit_log_changed_at_brin ON audit_log USING brin (changed_at);
CREATE INDEX ix_audit_log_new_data ON audit_log USING gin (new_data jsonb_path_ops);
