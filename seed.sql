-- =============================================================
--  Sample data for Blood Bank Management System
-- =============================================================

INSERT INTO blood_stock (blood_group, units) VALUES
    ('A+', 0), ('A-', 0), ('B+', 0), ('B-', 0),
    ('AB+', 0), ('AB-', 0), ('O+', 0), ('O-', 0);

INSERT INTO donors (name, gender, age, blood_group, phone, city) VALUES
    ('Arjun Kumar',   'M', 24, 'O+',  '9840011111', 'Chennai'),
    ('Priya Raman',   'F', 29, 'A+',  '9840022222', 'Chennai'),
    ('Karthik S',     'M', 35, 'B+',  '9840033333', 'Coimbatore'),
    ('Divya Menon',   'F', 22, 'AB+', '9840044444', 'Madurai'),
    ('Rahul Verma',   'M', 41, 'O-',  '9840055555', 'Chennai'),
    ('Sneha Iyer',    'F', 27, 'A-',  '9840066666', 'Trichy'),
    ('Vikram R',      'M', 31, 'B-',  '9840077777', 'Chennai'),
    ('Meena Lakshmi', 'F', 38, 'O+',  '9840088888', 'Coimbatore'),
    ('Suresh Babu',   'M', 45, 'A+',  '9840099999', 'Madurai'),
    ('Anitha J',      'F', 26, 'AB-', '9840012345', 'Chennai');

-- Donations: triggers automatically update blood_stock & donors.last_donated
INSERT INTO donations (donor_id, donation_date, units) VALUES
    (1,  date('now', '-200 days'), 1),
    (1,  date('now', '-40 days'),  1),
    (2,  date('now', '-120 days'), 1),
    (3,  date('now', '-15 days'),  2),
    (4,  date('now', '-100 days'), 1),
    (5,  date('now', '-60 days'),  2),
    (6,  date('now', '-95 days'),  1),
    (7,  date('now', '-10 days'),  1),
    (8,  date('now', '-30 days'),  2),
    (9,  date('now', '-150 days'), 1),
    (10, date('now', '-5 days'),   1);

INSERT INTO hospitals (name, city, phone) VALUES
    ('Apollo Hospital',        'Chennai',    '4428290200'),
    ('Government General Hospital', 'Chennai', '4425305000'),
    ('KMCH',                   'Coimbatore', '4224323800'),
    ('Meenakshi Mission',      'Madurai',    '4524263000');

INSERT INTO requests (hospital_id, patient_name, blood_group, units, request_date) VALUES
    (1, 'Ramesh P',   'O+', 2, date('now', '-3 days')),
    (2, 'Kavya S',    'A+', 1, date('now', '-2 days')),
    (3, 'Mohan K',    'B+', 1, date('now', '-1 days')),
    (4, 'Lalitha R',  'AB-', 3, date('now'));

-- Approve one request (trigger deducts stock)
UPDATE requests SET status = 'Approved' WHERE request_id = 1;
