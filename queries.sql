-- =============================================================
--  Sample queries for demo / viva  (run after schema.sql + seed.sql)
--  sqlite3 bloodbank.db < queries.sql
-- =============================================================
.headers on
.mode column

-- 1. Current stock of every blood group
SELECT * FROM blood_stock ORDER BY units DESC;

-- 2. Search O+ donors in Chennai (uses index idx_donor_group_city)
SELECT name, phone FROM donors WHERE blood_group = 'O+' AND city = 'Chennai';

-- 3. INNER JOIN: donation history with donor names
SELECT * FROM v_donation_history ORDER BY donation_date DESC;

-- 4. LEFT JOIN: every hospital with number of requests (including 0)
SELECT h.name, COUNT(r.request_id) AS requests
  FROM hospitals h LEFT JOIN requests r ON r.hospital_id = h.hospital_id
 GROUP BY h.hospital_id;

-- 5. GROUP BY + HAVING: cities with at least 2 donors
SELECT city, COUNT(*) AS donors FROM donors GROUP BY city HAVING COUNT(*) >= 2;

-- 6. Subquery: donors who have never donated
SELECT name, blood_group FROM donors
 WHERE donor_id NOT IN (SELECT donor_id FROM donations);

-- 7. Aggregate: total units donated per blood group
SELECT dn.blood_group, SUM(d.units) AS total_donated
  FROM donations d JOIN donors dn ON dn.donor_id = d.donor_id
 GROUP BY dn.blood_group;

-- 8. View: donors eligible to donate today
SELECT * FROM v_eligible_donors;

-- 9. Pending requests that CAN be fulfilled with current stock
SELECT r.request_id, r.patient_name, r.blood_group, r.units, s.units AS in_stock
  FROM requests r JOIN blood_stock s ON s.blood_group = r.blood_group
 WHERE r.status = 'Pending' AND s.units >= r.units;

-- 10. Trigger demo: this INSERT fails (donor 1 donated less than 90 days ago)
-- INSERT INTO donations (donor_id, donation_date) VALUES (1, date('now'));

-- 11. Trigger demo: approving with insufficient stock fails
-- UPDATE requests SET status = 'Approved' WHERE request_id = 4;
