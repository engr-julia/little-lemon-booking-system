"""Little Lemon booking client.

Connects to MySQL with mysql-connector-python and calls the five stored procedures.

Setup:
    pip install mysql-connector-python
    (optional) set LITTLELEMON_DB_PASSWORD so you aren't prompted for the password

Run:
    python booking_client.py
"""
import os
from getpass import getpass

import mysql.connector
from mysql.connector import Error

DB_CONFIG = {
    "host": "localhost",
    "port": 3306,
    "user": "root",
    "database": "littlelemondb",
}


def connect():
    """Open a connection. Password comes from an env var, else a prompt (never hard-coded)."""
    password = os.environ.get("LITTLELEMON_DB_PASSWORD") or getpass("MySQL password: ")
    return mysql.connector.connect(password=password, autocommit=True, **DB_CONFIG)


def call(cursor, name, args=()):
    """Call a stored procedure and return every row it produced."""
    cursor.callproc(name, args)
    rows = []
    for result in cursor.stored_results():
        rows.extend(result.fetchall())
    return rows


def show(title, rows):
    print(f"\n{title}")
    for row in rows:
        print("  ", row)


def main():
    try:
        cnx = connect()
    except Error as err:
        print(f"Could not connect: {err}")
        return

    cursor = cnx.cursor()
    try:
        print("Connected to", DB_CONFIG["database"])

        show("GetMaxQuantity()", call(cursor, "GetMaxQuantity"))

        show("ManageBooking('2022-10-10', 5)  -- already booked",
             call(cursor, "ManageBooking", ("2022-10-10", 5)))
        show("ManageBooking('2022-10-10', 6)  -- free table",
             call(cursor, "ManageBooking", ("2022-10-10", 6)))

        show("AddBooking(9, ..., '2022-12-20', 6)",
             call(cursor, "AddBooking", (9, "72-055-7985", "2022-12-20", 6)))
        show("AddBooking(10, ..., '2022-12-20', 6)  -- should be rejected (table taken)",
             call(cursor, "AddBooking", (10, "72-055-7985", "2022-12-20", 6)))

        show("UpdateBooking(9, '2022-12-21')",
             call(cursor, "UpdateBooking", (9, "2022-12-21")))

        cursor.execute("SELECT BookingID, BookingDate, TableNumber, CustomerID FROM Bookings")
        show("Bookings after changes", cursor.fetchall())

        show("CancelBooking(9)", call(cursor, "CancelBooking", (9,)))

        cursor.execute("SELECT BookingID, BookingDate, TableNumber, CustomerID FROM Bookings")
        show("Bookings after cancelling", cursor.fetchall())
    except Error as err:
        print(f"Database error: {err}")
    finally:
        cursor.close()
        cnx.close()
        print("\nConnection closed.")


if __name__ == "__main__":
    main()
