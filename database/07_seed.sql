SET search_path TO library, public;

BEGIN;

INSERT INTO roles (code, name, description) VALUES
('admin', 'Адміністратор', 'Повний доступ до системи'),
('librarian', 'Бібліотекар', 'Видача та прийом книг, робота з читачами'),
('manager', 'Менеджер послуг', 'Додаткові послуги, бронювання залів, заходи'),
('cataloger', 'Каталогізатор', 'Ведення каталогу та фонду');

INSERT INTO branches (name, address, phone, opens_at, closes_at) VALUES
('Центральна бібліотека', 'м. Київ, вул. Хрещатик, 10', '+380442001010', '09:00', '20:00'),
('Філія "Поділ"', 'м. Київ, вул. Сагайдачного, 25', '+380442002020', '10:00', '19:00'),
('Філія "Оболонь"', 'м. Київ, просп. Оболонський, 7', '+380442003030', '10:00', '18:00');

INSERT INTO staff (role_id, branch_id, first_name, last_name, email, login, hired_at) VALUES
(1, 1, 'Олександр', 'Ковальчук', 'o.kovalchuk@library.ua', 'admin', '2019-02-01'),
(2, 1, 'Ірина', 'Мельник', 'i.melnyk@library.ua', 'imelnyk', '2020-09-15'),
(2, 2, 'Тарас', 'Шевчук', 't.shevchuk@library.ua', 'tshevchuk', '2021-03-10'),
(3, 1, 'Наталія', 'Бондаренко', 'n.bondarenko@library.ua', 'nbondarenko', '2022-01-20'),
(4, 1, 'Андрій', 'Ткаченко', 'a.tkachenko@library.ua', 'atkachenko', '2018-11-05'),
(2, 3, 'Марія', 'Кравець', 'm.kravets@library.ua', 'mkravets', '2023-06-01');

SELECT set_config('app.current_staff_id', '1', true);

INSERT INTO membership_plans (name, max_loans, loan_days, daily_fine, monthly_price, service_discount) VALUES
('Базовий', 3, 14, 5.00, 0.00, 0),
('Стандарт', 5, 21, 4.00, 99.00, 10),
('Преміум', 10, 30, 3.00, 249.00, 25),
('Студентський', 5, 21, 2.00, 49.00, 15);

INSERT INTO members (card_number, first_name, last_name, birth_date, email, phone, address, registered_at) VALUES
('LIB-00000001', 'Анна', 'Петренко', '1998-04-12', 'anna.petrenko@gmail.com', '+380671112233', 'м. Київ, вул. Лесі Українки, 5', now() - INTERVAL '400 days'),
('LIB-00000002', 'Богдан', 'Савченко', '1985-11-03', 'b.savchenko@ukr.net', '+380502223344', 'м. Київ, вул. Антоновича, 44', now() - INTERVAL '380 days'),
('LIB-00000003', 'Олена', 'Гнатюк', '2003-07-21', 'olena.hnatiuk@kpi.ua', '+380633334455', 'м. Київ, просп. Перемоги, 37', now() - INTERVAL '300 days'),
('LIB-00000004', 'Дмитро', 'Литвиненко', '1979-01-30', 'd.lytvynenko@gmail.com', '+380674445566', 'м. Київ, вул. Січових Стрільців, 12', now() - INTERVAL '250 days'),
('LIB-00000005', 'Софія', 'Марченко', '2001-09-09', 's.marchenko@gmail.com', '+380935556677', 'м. Київ, вул. Велика Васильківська, 100', now() - INTERVAL '200 days'),
('LIB-00000006', 'Максим', 'Романюк', '1992-05-17', 'max.romaniuk@outlook.com', '+380506667788', 'м. Київ, вул. Набережно-Хрещатицька, 3', now() - INTERVAL '150 days'),
('LIB-00000007', 'Юлія', 'Олійник', '1995-12-01', 'yulia.oliinyk@gmail.com', '+380677778899', 'м. Київ, вул. Героїв Дніпра, 20', now() - INTERVAL '120 days'),
('LIB-00000008', 'Віктор', 'Зінченко', '1968-08-25', 'v.zinchenko@ukr.net', '+380668889900', 'м. Київ, вул. Мінська, 8', now() - INTERVAL '90 days'),
('LIB-00000009', 'Катерина', 'Бойко', '2004-02-14', 'k.boiko@knu.ua', '+380639990011', 'м. Київ, вул. Володимирська, 60', now() - INTERVAL '60 days'),
('LIB-00000010', 'Ігор', 'Карпенко', '1988-06-06', 'i.karpenko@gmail.com', '+380671231231', 'м. Київ, вул. Оболонська, 15', now() - INTERVAL '30 days'),
('LIB-00000011', 'Леся', 'Ярошенко', '1999-03-03', 'l.yaroshenko@gmail.com', '+380503213213', 'м. Київ, вул. Кирилівська, 70', now() - INTERVAL '20 days'),
('LIB-00000012', 'Роман', 'Тимошенко', '1975-10-10', 'r.tymoshenko@ukr.net', '+380964564564', 'м. Київ, вул. Ярославська, 9', now() - INTERVAL '10 days');

INSERT INTO memberships (member_id, plan_id, start_date, end_date) VALUES
(1, 3, CURRENT_DATE - 60, CURRENT_DATE + 305),
(2, 2, CURRENT_DATE - 100, CURRENT_DATE + 80),
(3, 4, CURRENT_DATE - 200, CURRENT_DATE + 165),
(4, 1, CURRENT_DATE - 250, CURRENT_DATE + 115),
(5, 2, CURRENT_DATE - 30, CURRENT_DATE + 150),
(6, 3, CURRENT_DATE - 140, CURRENT_DATE + 40),
(7, 1, CURRENT_DATE - 120, CURRENT_DATE + 245),
(8, 2, CURRENT_DATE - 400, CURRENT_DATE - 35),
(9, 4, CURRENT_DATE - 60, CURRENT_DATE + 120),
(10, 1, CURRENT_DATE - 30, CURRENT_DATE + 335),
(11, 2, CURRENT_DATE - 20, CURRENT_DATE + 160);

INSERT INTO authors (first_name, last_name, birth_year, country) VALUES
('Тарас', 'Шевченко', 1814, 'Україна'),
('Іван', 'Франко', 1856, 'Україна'),
('Леся', 'Українка', 1871, 'Україна'),
('Михайло', 'Коцюбинський', 1864, 'Україна'),
('Валер''ян', 'Підмогильний', 1901, 'Україна'),
('Іван', 'Багряний', 1906, 'Україна'),
('Сергій', 'Жадан', 1974, 'Україна'),
('Марія', 'Матіос', 1959, 'Україна'),
('Софія', 'Андрухович', 1982, 'Україна'),
('Джордж', 'Орвелл', 1903, 'Велика Британія'),
('Роберт', 'Мартін', 1952, 'США'),
('Ерих', 'Гамма', 1961, 'Швейцарія'),
('Річард', 'Гелм', 1960, 'США'),
('Ральф', 'Джонсон', 1955, 'США'),
('Джон', 'Вліссідес', 1961, 'США'),
('Абрахам', 'Зільбершац', 1952, 'США');

INSERT INTO publishers (name, city, website) VALUES
('Видавництво Старого Лева', 'Львів', 'https://starylev.com.ua'),
('А-БА-БА-ГА-ЛА-МА-ГА', 'Київ', 'https://ababahalamaha.com.ua'),
('Віхола', 'Київ', 'https://vikhola.com'),
('Фабула', 'Харків', 'https://fabulabook.com'),
('Наш Формат', 'Київ', 'https://nashformat.ua'),
('Pearson', 'Лондон', 'https://pearson.com');

INSERT INTO genres (name, parent_genre_id) VALUES
('Художня література', NULL),
('Наукова та навчальна література', NULL),
('Поезія', 1),
('Роман', 1),
('Повість', 1),
('Драма', 1),
('Антиутопія', 1),
('Програмування', 2),
('Бази даних', 2),
('Українська класика', 1);

INSERT INTO books (isbn, title, publisher_id, publish_year, language, pages, description) VALUES
('9786175850510', 'Кобзар', 2, 2019, 'uk', 704, 'Збірка поетичних творів Тараса Шевченка'),
('9789660375421', 'Захар Беркут', 4, 2020, 'uk', 224, 'Історична повість про боротьбу тухольців з монголами'),
('9786176794653', 'Лісова пісня', 4, 2018, 'uk', 160, 'Драма-феєрія про кохання Мавки та Лукаша'),
('9789660398765', 'Тіні забутих предків', 4, 2021, 'uk', 128, 'Повість про життя гуцулів та трагічне кохання'),
('9786175851234', 'Місто', 1, 2022, 'uk', 288, 'Роман про молодого селянина, що підкорює місто'),
('9786175855555', 'Тигролови', 1, 2021, 'uk', 320, 'Пригодницький роман про втечу з радянського табору'),
('9786171201234', 'Сад Гетсиманський', 4, 2020, 'uk', 640, 'Автобіографічний роман про репресії'),
('9786171234567', 'Інтернат', 5, 2017, 'uk', 336, 'Роман про війну на сході України'),
('9786176798888', 'Ворошиловград', 5, 2010, 'uk', 448, 'Роман про повернення в рідне місто'),
('9789660302222', 'Солодка Даруся', 1, 2004, 'uk', 224, 'Драма на три життя'),
('9786176799999', 'Фелікс Австрія', 1, 2014, 'uk', 288, 'Роман про Станиславів початку XX століття'),
('9786177563011', '1984', 5, 2021, 'uk', 320, 'Антиутопія про тоталітарне суспільство'),
('9780132350884', 'Clean Code', 6, 2008, 'en', 464, 'A Handbook of Agile Software Craftsmanship'),
('9780201633610', 'Design Patterns', 6, 1994, 'en', 395, 'Elements of Reusable Object-Oriented Software'),
('9780078022159', 'Database System Concepts', 6, 2019, 'en', 1376, 'Fundamentals of database systems design and implementation');

INSERT INTO book_authors (book_id, author_id, author_order) VALUES
(1, 1, 1), (2, 2, 1), (3, 3, 1), (4, 4, 1), (5, 5, 1), (6, 6, 1), (7, 6, 1),
(8, 7, 1), (9, 7, 1), (10, 8, 1), (11, 9, 1), (12, 10, 1), (13, 11, 1),
(14, 12, 1), (14, 13, 2), (14, 14, 3), (14, 15, 4), (15, 16, 1);

INSERT INTO book_genres (book_id, genre_id) VALUES
(1, 3), (1, 10), (2, 5), (2, 10), (3, 6), (3, 10), (4, 5), (4, 10), (5, 4), (5, 10),
(6, 4), (7, 4), (8, 4), (9, 4), (10, 4), (11, 4), (12, 7), (12, 4),
(13, 8), (14, 8), (15, 9);

INSERT INTO book_copies (book_id, branch_id, inventory_code, shelf, price, acquired_at)
SELECT b.book_id,
       br.branch_id,
       format('INV-%s-%s-%s', br.branch_id, lpad(b.book_id::TEXT, 3, '0'), n),
       format('%s-%s', chr(64 + ((b.book_id - 1) % 6) + 1), ((b.book_id * 7 + n) % 20) + 1),
       200 + b.book_id * 15,
       CURRENT_DATE - (b.book_id * 30 + n * 10)
FROM books b
CROSS JOIN branches br
CROSS JOIN generate_series(1, 2) AS n
WHERE br.branch_id = 1 OR (br.branch_id = 2 AND b.book_id <= 10) OR (br.branch_id = 3 AND b.book_id % 3 = 0 AND n = 1);

INSERT INTO loans (copy_id, member_id, issued_by, loan_date, due_date)
SELECT c.copy_id, x.member_id, 2, now() - make_interval(days => x.ago), CURRENT_DATE - x.ago + x.days
FROM (VALUES
    ('INV-1-001-1', 1, 200, 30), ('INV-1-002-1', 2, 190, 21), ('INV-1-005-1', 3, 170, 21),
    ('INV-1-008-1', 1, 150, 30), ('INV-1-012-1', 5, 120, 21), ('INV-1-013-1', 6, 110, 30),
    ('INV-1-014-1', 3, 100, 21), ('INV-1-012-2', 7, 80, 14), ('INV-1-009-1', 9, 60, 21),
    ('INV-1-003-1', 2, 50, 21), ('INV-2-004-1', 4, 45, 14), ('INV-2-006-1', 10, 25, 14)
) AS x(code, member_id, ago, days)
JOIN book_copies c ON c.inventory_code = x.code
ORDER BY x.ago DESC;

UPDATE loans
SET return_date = loan_date + make_interval(days => d.kept),
    received_by = 3,
    status = 'returned'
FROM (VALUES (1, 25), (2, 30), (3, 18), (4, 28), (5, 21), (6, 35), (7, 15), (8, 20), (9, 22), (10, 19), (11, 10)) AS d(loan_id, kept)
WHERE loans.loan_id = d.loan_id;

INSERT INTO fines (loan_id, member_id, amount, reason, issued_at, status)
SELECT l.loan_id, l.member_id, fn_calc_fine(l.loan_id),
       format('Прострочення повернення на %s дн.', l.return_date::DATE - l.due_date),
       l.return_date,
       CASE WHEN l.loan_id = 2 THEN 'paid' ELSE 'unpaid' END::fine_status
FROM loans l
WHERE l.return_date IS NOT NULL AND l.return_date::DATE > l.due_date;

INSERT INTO payments (member_id, amount, method, paid_at, received_by, fine_id)
SELECT member_id, amount, 'cash', issued_at, 3, fine_id FROM fines WHERE status = 'paid';

INSERT INTO loans (copy_id, member_id, issued_by, loan_date, due_date)
SELECT c.copy_id, x.member_id, x.staff, now() - make_interval(days => x.ago), CURRENT_DATE - x.ago + x.days
FROM (VALUES
    ('INV-1-010-1', 1, 2, 10, 30), ('INV-1-011-1', 1, 2, 5, 30), ('INV-1-007-1', 4, 2, 25, 14),
    ('INV-2-001-1', 5, 3, 7, 21), ('INV-1-013-2', 6, 2, 40, 30), ('INV-3-003-1', 9, 6, 3, 21),
    ('INV-1-006-1', 11, 2, 2, 21), ('INV-1-013-1', 2, 2, 4, 21)
) AS x(code, member_id, staff, ago, days)
JOIN book_copies c ON c.inventory_code = x.code
ORDER BY x.ago DESC;

INSERT INTO reservations (book_id, member_id, branch_id, reserved_at, expires_at, status) VALUES
(13, 3, 1, now() - INTERVAL '2 days', now() + INTERVAL '28 days', 'pending'),
(10, 7, 1, now() - INTERVAL '1 day', now() + INTERVAL '2 days', 'ready'),
(2, 11, 1, now() - INTERVAL '40 days', now() - INTERVAL '10 days', 'expired');

UPDATE book_copies SET status = 'reserved' WHERE inventory_code = 'INV-1-010-2';

INSERT INTO additional_services (code, name, unit, unit_price) VALUES
('PRINT_BW', 'Друк чорно-білий А4', 'сторінка', 2.00),
('PRINT_COLOR', 'Друк кольоровий А4', 'сторінка', 8.00),
('SCAN', 'Сканування документів', 'сторінка', 3.00),
('COPY', 'Ксерокопіювання', 'сторінка', 1.50),
('ILL', 'Міжбібліотечний абонемент', 'замовлення', 120.00),
('LAMINATE', 'Ламінування', 'аркуш', 15.00),
('PC_HOUR', 'Робоче місце з ПК', 'година', 25.00);

INSERT INTO service_orders (member_id, service_id, branch_id, quantity, unit_price, discount, status, ordered_at, handled_by) VALUES
(1, 1, 1, 40, 2.00, 25, 'completed', now() - INTERVAL '50 days', 4),
(2, 3, 1, 12, 3.00, 10, 'completed', now() - INTERVAL '35 days', 4),
(3, 7, 2, 3, 25.00, 15, 'completed', now() - INTERVAL '20 days', 4),
(5, 5, 1, 1, 120.00, 10, 'in_progress', now() - INTERVAL '5 days', 4),
(9, 2, 1, 10, 8.00, 15, 'completed', now() - INTERVAL '3 days', 4),
(6, 4, 2, 25, 1.50, 25, 'new', now() - INTERVAL '1 day', NULL);

INSERT INTO payments (member_id, amount, method, paid_at, received_by, order_id)
SELECT member_id, total_price, 'card', ordered_at, handled_by, order_id
FROM service_orders WHERE status = 'completed';

INSERT INTO rooms (branch_id, name, capacity, hourly_rate, has_projector) VALUES
(1, 'Конференц-зала', 40, 300.00, TRUE),
(1, 'Кімната для групової роботи №1', 8, 80.00, FALSE),
(1, 'Кімната для групової роботи №2', 6, 60.00, TRUE),
(2, 'Читальна зала', 25, 150.00, TRUE),
(3, 'Дитяча кімната', 15, 100.00, FALSE);

INSERT INTO room_bookings (room_id, member_id, period, purpose) VALUES
(2, 3, tstzrange(date_trunc('day', now()) + INTERVAL '2 days 10 hours', date_trunc('day', now()) + INTERVAL '2 days 12 hours'), 'Підготовка курсового проєкту'),
(3, 9, tstzrange(date_trunc('day', now()) + INTERVAL '3 days 14 hours', date_trunc('day', now()) + INTERVAL '3 days 16 hours'), 'Репетиція захисту'),
(1, 6, tstzrange(date_trunc('day', now()) + INTERVAL '5 days 11 hours', date_trunc('day', now()) + INTERVAL '5 days 15 hours'), 'Презентація книги');

INSERT INTO events (branch_id, room_id, title, description, starts_at, ends_at, max_participants, ticket_price, organizer_id) VALUES
(1, 1, 'Зустріч з автором: сучасна українська проза', 'Розмова про нові книги та читання уривків', date_trunc('day', now()) + INTERVAL '7 days 17 hours', date_trunc('day', now()) + INTERVAL '7 days 19 hours', 40, 0, 4),
(1, 3, 'Майстер-клас з SQL для початківців', 'Практичне заняття з основ реляційних баз даних', date_trunc('day', now()) + INTERVAL '10 days 15 hours', date_trunc('day', now()) + INTERVAL '10 days 18 hours', 6, 150, 4),
(2, 4, 'Книжковий клуб: "Місто" Підмогильного', 'Обговорення роману', date_trunc('day', now()) + INTERVAL '12 days 16 hours', date_trunc('day', now()) + INTERVAL '12 days 18 hours', 20, 0, 4),
(3, 5, 'Казкотерапія для дітей', 'Читання казок для дітей 5-8 років', date_trunc('day', now()) - INTERVAL '5 days' + INTERVAL '11 hours', date_trunc('day', now()) - INTERVAL '5 days' + INTERVAL '12 hours', 15, 0, 4);

INSERT INTO event_registrations (event_id, member_id) VALUES
(1, 1), (1, 2), (1, 5), (2, 3), (2, 9), (3, 6), (3, 7);

INSERT INTO payments (member_id, amount, method, received_by, registration_id)
SELECT er.member_id, e.ticket_price, 'online', 4, er.registration_id
FROM event_registrations er JOIN events e ON e.event_id = er.event_id
WHERE e.ticket_price > 0;

INSERT INTO payments (member_id, amount, method, paid_at, received_by, membership_id)
SELECT ms.member_id, mp.monthly_price, 'card', ms.created_at, 2, ms.membership_id
FROM memberships ms JOIN membership_plans mp ON mp.plan_id = ms.plan_id
WHERE mp.monthly_price > 0;

INSERT INTO book_reviews (book_id, member_id, rating, comment) VALUES
(1, 1, 5, 'Must-read для кожного українця'),
(2, 2, 4, 'Захоплива історична повість'),
(5, 3, 5, 'Дуже сучасна книга, хоч і написана майже 100 років тому'),
(12, 5, 5, 'Лякає своєю актуальністю'),
(13, 6, 5, 'Обов''язкова книга для програміста'),
(14, 3, 4, 'Класика, але подекуди застаріла'),
(8, 1, 5, 'Сильний і болючий роман'),
(12, 7, 4, NULL);

COMMIT;

CALL library.sp_mark_overdue_loans();
CALL library.sp_refresh_reports();
