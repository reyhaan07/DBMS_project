"""Blood Bank Management System - Flask + SQLite."""
import os
import sqlite3
from datetime import date

from flask import Flask, flash, g, redirect, render_template, request, url_for

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(BASE_DIR, "bloodbank.db")
BLOOD_GROUPS = ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]

app = Flask(__name__)
app.secret_key = "bloodbank-dbms-project"


# ---------------------------------------------------------------- database
def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DB_PATH)
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA foreign_keys = ON")
    return g.db


@app.teardown_appcontext
def close_db(_exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    """Create tables, triggers, views and load sample data."""
    db = sqlite3.connect(DB_PATH)
    for script in ("schema.sql", "seed.sql"):
        with open(os.path.join(BASE_DIR, script)) as f:
            db.executescript(f.read())
    db.commit()
    db.close()


def run(sql, params=()):
    """Execute a write query; flash the DB error message if a constraint/trigger fails."""
    db = get_db()
    try:
        db.execute(sql, params)
        db.commit()
        return True
    except sqlite3.Error as e:
        db.rollback()
        msg = str(e)
        if "FOREIGN KEY" in msg:
            msg = "Record is linked to other data (donations/requests) and cannot be removed"
        elif "UNIQUE" in msg:
            msg = "A record with the same phone/name already exists"
        flash(f"Error: {msg}", "error")
        return False


# ---------------------------------------------------------------- dashboard
@app.route("/")
def dashboard():
    db = get_db()
    stock = db.execute("SELECT * FROM blood_stock ORDER BY blood_group").fetchall()
    counts = db.execute("""
        SELECT (SELECT COUNT(*) FROM donors)    AS donors,
               (SELECT COUNT(*) FROM hospitals) AS hospitals,
               (SELECT COALESCE(SUM(units), 0) FROM blood_stock) AS units,
               (SELECT COUNT(*) FROM requests WHERE status = 'Pending') AS pending
    """).fetchone()
    recent = db.execute(
        "SELECT * FROM v_donation_history ORDER BY donation_date DESC LIMIT 5"
    ).fetchall()
    return render_template("dashboard.html", stock=stock, counts=counts, recent=recent)


# ---------------------------------------------------------------- donors
@app.route("/donors", methods=["GET", "POST"])
def donors():
    if request.method == "POST":
        f = request.form
        if run("INSERT INTO donors (name, gender, age, blood_group, phone, city) "
               "VALUES (?, ?, ?, ?, ?, ?)",
               (f["name"].strip(), f["gender"], f["age"], f["blood_group"],
                f["phone"].strip(), f["city"].strip().title())):
            flash("Donor registered successfully.", "success")
        return redirect(url_for("donors"))

    group = request.args.get("group", "")
    city = request.args.get("city", "").strip()
    sql = "SELECT * FROM donors WHERE 1=1"
    params = []
    if group:
        sql += " AND blood_group = ?"
        params.append(group)
    if city:
        sql += " AND city LIKE ?"
        params.append(f"%{city}%")
    rows = get_db().execute(sql + " ORDER BY donor_id", params).fetchall()
    return render_template("donors.html", donors=rows, groups=BLOOD_GROUPS,
                           group=group, city=city)


@app.route("/donors/<int:donor_id>/delete", methods=["POST"])
def delete_donor(donor_id):
    if run("DELETE FROM donors WHERE donor_id = ?", (donor_id,)):
        flash("Donor deleted.", "success")
    return redirect(url_for("donors"))


# ---------------------------------------------------------------- donations
@app.route("/donations", methods=["GET", "POST"])
def donations():
    db = get_db()
    if request.method == "POST":
        f = request.form
        if run("INSERT INTO donations (donor_id, donation_date, units) VALUES (?, ?, ?)",
               (f["donor_id"], f["donation_date"], f["units"])):
            flash("Donation recorded. Stock updated automatically by trigger.", "success")
        return redirect(url_for("donations"))

    all_donors = db.execute(
        "SELECT donor_id, name, blood_group FROM donors ORDER BY name").fetchall()
    history = db.execute(
        "SELECT * FROM v_donation_history ORDER BY donation_date DESC").fetchall()
    return render_template("donations.html", donors=all_donors, history=history,
                           today=date.today().isoformat())


# ---------------------------------------------------------------- hospitals
@app.route("/hospitals", methods=["GET", "POST"])
def hospitals():
    if request.method == "POST":
        f = request.form
        if run("INSERT INTO hospitals (name, city, phone) VALUES (?, ?, ?)",
               (f["name"].strip(), f["city"].strip().title(), f["phone"].strip())):
            flash("Hospital added.", "success")
        return redirect(url_for("hospitals"))

    rows = get_db().execute("""
        SELECT h.*, COUNT(r.request_id) AS total_requests
          FROM hospitals h
          LEFT JOIN requests r ON r.hospital_id = h.hospital_id
         GROUP BY h.hospital_id
         ORDER BY h.name
    """).fetchall()
    return render_template("hospitals.html", hospitals=rows)


# ---------------------------------------------------------------- requests
@app.route("/requests", methods=["GET", "POST"])
def requests_page():
    db = get_db()
    if request.method == "POST":
        f = request.form
        if run("INSERT INTO requests (hospital_id, patient_name, blood_group, units) "
               "VALUES (?, ?, ?, ?)",
               (f["hospital_id"], f["patient_name"].strip(), f["blood_group"], f["units"])):
            flash("Blood request submitted.", "success")
        return redirect(url_for("requests_page"))

    all_hospitals = db.execute("SELECT hospital_id, name FROM hospitals ORDER BY name").fetchall()
    rows = db.execute("""
        SELECT v.*, s.units AS in_stock
          FROM v_request_details v
          JOIN blood_stock s ON s.blood_group = v.blood_group
         ORDER BY CASE v.status WHEN 'Pending' THEN 0 ELSE 1 END, v.request_date DESC
    """).fetchall()
    return render_template("requests.html", requests=rows, hospitals=all_hospitals,
                           groups=BLOOD_GROUPS)


@app.route("/requests/<int:request_id>/<action>", methods=["POST"])
def process_request(request_id, action):
    status = {"approve": "Approved", "reject": "Rejected"}.get(action)
    if status and run("UPDATE requests SET status = ? WHERE request_id = ?",
                      (status, request_id)):
        flash(f"Request #{request_id} {status.lower()}.", "success")
    return redirect(url_for("requests_page"))


# ---------------------------------------------------------------- reports
REPORTS = [
    ("Eligible donors (view v_eligible_donors)",
     "SELECT name, blood_group, city, phone, last_donated FROM v_eligible_donors"),
    ("Donors count per blood group (GROUP BY)",
     "SELECT blood_group, COUNT(*) AS donors FROM donors GROUP BY blood_group ORDER BY donors DESC"),
    ("Donors per city (GROUP BY + HAVING)",
     "SELECT city, COUNT(*) AS donors FROM donors GROUP BY city HAVING COUNT(*) >= 2"),
    ("Top donors by units donated (JOIN + aggregate)",
     "SELECT dn.name, dn.blood_group, COUNT(*) AS times, SUM(d.units) AS total_units "
     "FROM donors dn JOIN donations d ON d.donor_id = dn.donor_id "
     "GROUP BY dn.donor_id ORDER BY total_units DESC LIMIT 5"),
    ("Low stock groups (< 2 units)",
     "SELECT blood_group, units FROM blood_stock WHERE units < 2"),
    ("Donors who never donated (subquery)",
     "SELECT name, blood_group, city FROM donors "
     "WHERE donor_id NOT IN (SELECT donor_id FROM donations)"),
    ("Units issued to each hospital (JOIN + SUM)",
     "SELECT hospital_name, SUM(units) AS units_received FROM v_request_details "
     "WHERE status = 'Approved' GROUP BY hospital_name"),
]


@app.route("/reports")
def reports():
    db = get_db()
    results = []
    for title, sql in REPORTS:
        cur = db.execute(sql)
        cols = [c[0] for c in cur.description]
        results.append({"title": title, "sql": sql, "cols": cols, "rows": cur.fetchall()})
    return render_template("reports.html", results=results)


if __name__ == "__main__":
    if not os.path.exists(DB_PATH):
        init_db()
    app.run(debug=True)
