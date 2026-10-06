-- =============================================================
--  BLOOD BANK MANAGEMENT SYSTEM  -  Database Schema (SQLite)
-- =============================================================

PRAGMA foreign_keys = ON;

DROP VIEW    IF EXISTS v_donation_history;
DROP VIEW    IF EXISTS v_request_details;
DROP VIEW    IF EXISTS v_eligible_donors;
DROP TABLE   IF EXISTS requests;
DROP TABLE   IF EXISTS donations;
DROP TABLE   IF EXISTS blood_stock;
DROP TABLE   IF EXISTS hospitals;
DROP TABLE   IF EXISTS donors;

-- -------------------------------------------------------------
-- 1. DONORS : people who donate blood
-- -------------------------------------------------------------
CREATE TABLE donors (
    donor_id     INTEGER PRIMARY KEY AUTOINCREMENT,
    name         VARCHAR(50)  NOT NULL,
    gender       CHAR(1)      NOT NULL CHECK (gender IN ('M', 'F', 'O')),
    age          INTEGER      NOT NULL CHECK (age BETWEEN 18 AND 65),
    blood_group  VARCHAR(3)   NOT NULL
                 CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    phone        VARCHAR(10)  NOT NULL UNIQUE CHECK (length(phone) = 10),
    city         VARCHAR(30)  NOT NULL,
    last_donated DATE                         -- maintained by trigger
);

-- -------------------------------------------------------------
-- 2. HOSPITALS : who request blood
-- -------------------------------------------------------------
CREATE TABLE hospitals (
    hospital_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    name         VARCHAR(60)  NOT NULL UNIQUE,
    city         VARCHAR(30)  NOT NULL,
    phone        VARCHAR(10)  NOT NULL CHECK (length(phone) = 10)
);

-- -------------------------------------------------------------
-- 3. BLOOD_STOCK : one row per blood group (8 rows)
-- -------------------------------------------------------------
CREATE TABLE blood_stock (
    blood_group  VARCHAR(3) PRIMARY KEY,
    units        INTEGER NOT NULL DEFAULT 0 CHECK (units >= 0)
);

-- -------------------------------------------------------------
-- 4. DONATIONS : every time a donor gives blood
-- -------------------------------------------------------------
CREATE TABLE donations (
    donation_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    donor_id      INTEGER NOT NULL,
    donation_date DATE    NOT NULL DEFAULT (date('now')),
    units         INTEGER NOT NULL DEFAULT 1 CHECK (units BETWEEN 1 AND 2),
    FOREIGN KEY (donor_id) REFERENCES donors(donor_id) ON DELETE RESTRICT
);

-- -------------------------------------------------------------
-- 5. REQUESTS : blood requested by hospitals for patients
-- -------------------------------------------------------------
CREATE TABLE requests (
    request_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    hospital_id   INTEGER NOT NULL,
    patient_name  VARCHAR(50) NOT NULL,
    blood_group   VARCHAR(3)  NOT NULL REFERENCES blood_stock(blood_group),
    units         INTEGER     NOT NULL CHECK (units BETWEEN 1 AND 10),
    request_date  DATE        NOT NULL DEFAULT (date('now')),
    status        VARCHAR(10) NOT NULL DEFAULT 'Pending'
                  CHECK (status IN ('Pending', 'Approved', 'Rejected')),
    FOREIGN KEY (hospital_id) REFERENCES hospitals(hospital_id) ON DELETE RESTRICT
);

-- Index to speed up searching donors by blood group & city
CREATE INDEX idx_donor_group_city ON donors(blood_group, city);

-- =============================================================
--  TRIGGERS  (business rules enforced inside the database)
-- =============================================================

-- T1: A donor must wait at least 90 days between two donations
CREATE TRIGGER trg_check_donation_gap
BEFORE INSERT ON donations
WHEN EXISTS (
    SELECT 1 FROM donations
    WHERE donor_id = NEW.donor_id
      AND abs(julianday(NEW.donation_date) - julianday(donation_date)) < 90
)
BEGIN
    SELECT RAISE(ABORT, 'Donor must wait at least 90 days between donations');
END;

-- T2: After a donation -> add units to stock & update donor's last_donated
CREATE TRIGGER trg_after_donation
AFTER INSERT ON donations
BEGIN
    UPDATE blood_stock
       SET units = units + NEW.units
     WHERE blood_group = (SELECT blood_group FROM donors WHERE donor_id = NEW.donor_id);

    UPDATE donors
       SET last_donated = NEW.donation_date
     WHERE donor_id = NEW.donor_id
       AND (last_donated IS NULL OR last_donated < NEW.donation_date);
END;

-- T3: A request can be approved only if enough stock is available
CREATE TRIGGER trg_check_stock
BEFORE UPDATE OF status ON requests
WHEN NEW.status = 'Approved' AND OLD.status = 'Pending'
 AND (SELECT units FROM blood_stock WHERE blood_group = NEW.blood_group) < NEW.units
BEGIN
    SELECT RAISE(ABORT, 'Insufficient stock to approve this request');
END;

-- T4: When a request is approved -> deduct units from stock
CREATE TRIGGER trg_after_approve
AFTER UPDATE OF status ON requests
WHEN NEW.status = 'Approved' AND OLD.status = 'Pending'
BEGIN
    UPDATE blood_stock
       SET units = units - NEW.units
     WHERE blood_group = NEW.blood_group;
END;

-- T5: Once decided, a request cannot be changed again
CREATE TRIGGER trg_lock_decided_request
BEFORE UPDATE OF status ON requests
WHEN OLD.status <> 'Pending'
BEGIN
    SELECT RAISE(ABORT, 'This request has already been processed');
END;

-- =============================================================
--  VIEWS
-- =============================================================

-- V1: Full donation history (JOIN donors + donations)
CREATE VIEW v_donation_history AS
SELECT d.donation_id, d.donation_date, dn.donor_id, dn.name AS donor_name,
       dn.blood_group, dn.city, d.units
  FROM donations d
  JOIN donors dn ON dn.donor_id = d.donor_id;

-- V2: Requests with hospital name (JOIN hospitals + requests)
CREATE VIEW v_request_details AS
SELECT r.request_id, r.request_date, h.name AS hospital_name, h.city,
       r.patient_name, r.blood_group, r.units, r.status
  FROM requests r
  JOIN hospitals h ON h.hospital_id = r.hospital_id;

-- V3: Donors who are eligible to donate today (never donated / 90+ days ago)
CREATE VIEW v_eligible_donors AS
SELECT donor_id, name, blood_group, city, phone, last_donated
  FROM donors
 WHERE last_donated IS NULL
    OR julianday('now') - julianday(last_donated) >= 90;
