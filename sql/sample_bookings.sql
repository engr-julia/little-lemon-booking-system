-- Run AFTER LittleLemonDB.sql and after importing all four CSVs.
USE LittleLemonDB;

INSERT INTO Bookings (BookingDate, TableNumber, NumberOfGuests, CustomerID, StaffID) VALUES
 ('2022-10-10', 5, 2, '72-055-7985', 3),
 ('2022-11-12', 3, 4, '65-353-0657', 3),
 ('2022-10-11', 2, 3, '90-876-6799', 3),
 ('2022-10-13', 2, 5, '73-873-4827', 3);
