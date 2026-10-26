-- =====================================================
-- Little Lemon Booking System  (MySQL 8)
-- Schema, data load, and stored procedures
-- Data source: LittleLemon_data.xlsx (cleaned by prepare_data.py)
-- =====================================================

DROP DATABASE IF EXISTS LittleLemonDB;
CREATE DATABASE LittleLemonDB;
USE LittleLemonDB;

-- ---------------------- TABLES -----------------------

CREATE TABLE Customers (
    CustomerID   VARCHAR(15) PRIMARY KEY,          -- e.g. 72-055-7985
    FullName     VARCHAR(100) NOT NULL,
    City         VARCHAR(100),
    Country      VARCHAR(100),
    CountryCode  CHAR(2)                            -- 'NA' = Namibia (not NULL)
);

CREATE TABLE Staff (
    StaffID       INT AUTO_INCREMENT PRIMARY KEY,
    FullName      VARCHAR(100) NOT NULL,
    Role          VARCHAR(50)  NOT NULL,
    ContactNumber VARCHAR(20),
    AnnualSalary  DECIMAL(10,2)
);

CREATE TABLE Cuisines (
    CuisineID   INT PRIMARY KEY,
    CuisineName VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE MenuItems (
    MenuItemID INT PRIMARY KEY,
    ItemType   ENUM('Course','Starter','Dessert','Drink','Side') NOT NULL,
    ItemName   VARCHAR(100) NOT NULL,
    UNIQUE (ItemType, ItemName)
);

CREATE TABLE Bookings (
    BookingID      INT AUTO_INCREMENT PRIMARY KEY,
    BookingDate    DATE NOT NULL,
    TableNumber    INT  NOT NULL,
    NumberOfGuests INT  NOT NULL DEFAULT 1,
    CustomerID     VARCHAR(15) NOT NULL,
    StaffID        INT,
    CONSTRAINT fk_bk_customer FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID),
    CONSTRAINT fk_bk_staff    FOREIGN KEY (StaffID)    REFERENCES Staff(StaffID),
    CONSTRAINT uq_table_date  UNIQUE (BookingDate, TableNumber)
);

-- One row per source line. OrderID repeats (21 lines per order in the data file).
CREATE TABLE Orders (
    OrderLineID  INT PRIMARY KEY,                   -- 'Row Number' in the source
    OrderID      VARCHAR(15) NOT NULL,
    CustomerID   VARCHAR(15) NOT NULL,
    OrderDate    DATE NOT NULL,
    DeliveryDate DATE,
    PostalCode   VARCHAR(20),
    Cost         DECIMAL(8,2) NOT NULL,
    Sales        DECIMAL(8,2) NOT NULL,
    Quantity     INT NOT NULL,
    Discount     DECIMAL(6,2),
    DeliveryCost DECIMAL(6,2),
    CuisineID    INT NOT NULL,
    CourseID     INT NOT NULL,
    StarterID    INT NOT NULL,
    DessertID    INT NOT NULL,
    DrinkID      INT NOT NULL,
    SideID       INT NOT NULL,
    INDEX idx_orders_orderid (OrderID),
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID),
    FOREIGN KEY (CuisineID)  REFERENCES Cuisines(CuisineID),
    FOREIGN KEY (CourseID)   REFERENCES MenuItems(MenuItemID),
    FOREIGN KEY (StarterID)  REFERENCES MenuItems(MenuItemID),
    FOREIGN KEY (DessertID)  REFERENCES MenuItems(MenuItemID),
    FOREIGN KEY (DrinkID)    REFERENCES MenuItems(MenuItemID),
    FOREIGN KEY (SideID)     REFERENCES MenuItems(MenuItemID)
);

-- ------------------- DATA LOAD -----------------------
-- Run from the repo root so the relative paths resolve, and start the client with
--   mysql --local-infile=1 -u root -p
-- (In Workbench: enable OPT_LOCAL_INFILE=1 under Connection > Advanced.)
-- Alternatively use Workbench's Table Data Import Wizard on each CSV in /data.

SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE 'data/cuisines.csv' INTO TABLE Cuisines
  FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/menu_items.csv' INTO TABLE MenuItems
  FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/customers.csv' INTO TABLE Customers
  FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES;

LOAD DATA LOCAL INFILE 'data/orders.csv' INTO TABLE Orders
  FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- Sample staff and bookings for testing the booking procedures
INSERT INTO Staff (FullName, Role, ContactNumber, AnnualSalary) VALUES
 ('Mario Gollini',   'Manager',   '0918-000-0001', 70000),
 ('Adrian Gollini',  'Head Chef', '0918-000-0002', 65000),
 ('Giorgos Dioudis', 'Waiter',    '0918-000-0003', 35000);

INSERT INTO Bookings (BookingDate, TableNumber, NumberOfGuests, CustomerID, StaffID) VALUES
 ('2022-10-10', 5, 2, '72-055-7985', 3),
 ('2022-11-12', 3, 4, '65-353-0657', 3),
 ('2022-10-11', 2, 3, '90-876-6799', 3),
 ('2022-10-13', 2, 5, '73-873-4827', 3);

-- ================== STORED PROCEDURES =================
DELIMITER //

-- 1. GetMaxQuantity: largest quantity in any order line
CREATE PROCEDURE GetMaxQuantity()
BEGIN
    SELECT MAX(Quantity) AS `Max Quantity in Order` FROM Orders;
END//

-- 2. ManageBooking: report whether a table is already booked on a date
CREATE PROCEDURE ManageBooking(IN booking_date DATE, IN table_number INT)
BEGIN
    DECLARE booked INT DEFAULT 0;
    SELECT COUNT(*) INTO booked FROM Bookings
     WHERE BookingDate = booking_date AND TableNumber = table_number;
    IF booked > 0 THEN
        SELECT CONCAT('Table ', table_number, ' is already booked on ', booking_date) AS `Booking Status`;
    ELSE
        SELECT CONCAT('Table ', table_number, ' is available on ', booking_date) AS `Booking Status`;
    END IF;
END//

-- 3. UpdateBooking: move a booking to a new date (blocks conflicts)
CREATE PROCEDURE UpdateBooking(IN booking_id INT, IN new_date DATE)
BEGIN
    DECLARE tbl INT;
    SELECT TableNumber INTO tbl FROM Bookings WHERE BookingID = booking_id;
    IF tbl IS NULL THEN
        SELECT CONCAT('Booking ', booking_id, ' not found') AS Confirmation;
    ELSEIF EXISTS (SELECT 1 FROM Bookings
                    WHERE BookingDate = new_date AND TableNumber = tbl AND BookingID <> booking_id) THEN
        SELECT CONCAT('Table ', tbl, ' is already booked on ', new_date, '; booking not updated') AS Confirmation;
    ELSE
        UPDATE Bookings SET BookingDate = new_date WHERE BookingID = booking_id;
        SELECT CONCAT('Booking ', booking_id, ' updated') AS Confirmation;
    END IF;
END//

-- 4. AddBooking: add a booking inside a transaction; reject double-booking
CREATE PROCEDURE AddBooking(
    IN booking_id INT, IN customer_id VARCHAR(15), IN booking_date DATE, IN table_number INT)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Booking failed (check customer ID, booking ID, or table availability)' AS Confirmation;
    END;

    START TRANSACTION;
    IF EXISTS (SELECT 1 FROM Bookings
                WHERE BookingDate = booking_date AND TableNumber = table_number) THEN
        ROLLBACK;
        SELECT CONCAT('Table ', table_number, ' is already booked; booking cancelled') AS Confirmation;
    ELSE
        INSERT INTO Bookings (BookingID, BookingDate, TableNumber, NumberOfGuests, CustomerID)
        VALUES (booking_id, booking_date, table_number, 1, customer_id);
        COMMIT;
        SELECT 'New booking added' AS Confirmation;
    END IF;
END//

-- 5. CancelBooking: delete a booking by ID
CREATE PROCEDURE CancelBooking(IN booking_id INT)
BEGIN
    DELETE FROM Bookings WHERE BookingID = booking_id;
    IF ROW_COUNT() > 0 THEN
        SELECT CONCAT('Booking ', booking_id, ' cancelled') AS Confirmation;
    ELSE
        SELECT CONCAT('Booking ', booking_id, ' not found') AS Confirmation;
    END IF;
END//

DELIMITER ;

-- ---------------- QUICK TESTS (optional) --------------
-- CALL GetMaxQuantity();
-- CALL ManageBooking('2022-10-10', 5);
-- CALL AddBooking(9, '72-055-7985', '2022-12-20', 6);
-- CALL UpdateBooking(9, '2022-12-21');
-- CALL CancelBooking(9);
